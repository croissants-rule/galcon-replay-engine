-- ─────────────────────────────────────────────────────────────────────────────
-- Galcon 2  —  1v1 Server Mod with Replay Recording
-- ─────────────────────────────────────────────────────────────────────────────
-- HOW TO USE:
--   1. Copy this file to your Galcon 2 mod folder and load it as your server mod.
--   2. Run galcon.py on your PC before hosting. It will poll mod1.bin as usual.
--   3. Host the room on your PC. Join on your phone. A third person (or you
--      in a second client) can spectate — their view triggers all the stat labels.
--   4. When the game ends, the recording is flushed automatically and galcon.py
--      picks it up, writes the .jsonl, and the Discord bot uploads it.
--
-- PLAYER SLOTS:
--   Exactly 2 "play" players are required to start.
--   Any additional joiners are spectators (they watch, labels update for them).
--   The host PC running the mod is the spectator by default.
--
-- COMMANDS (chat):
--   /play       — mark yourself as ready (status: queue → ready)
--   /away       — mark yourself as away
--   /surrender  — forfeit current game
--   /start      — force-start if exactly 2 queued players (admin only)
--   /stop       — abort current game (admin only)
--   /who        — list connected players and their status
-- ─────────────────────────────────────────────────────────────────────────────

strict(true)

-- ── Recording constants (must match galcon.py expectations) ──────────────────
local POSITION_RATE = 4      -- flush position sample every N frames
local CHUNK_SIZE    = 100    -- max pending events+pos before auto-flush
local NUM_NEUTRALS  = 24     -- total planets (12 symmetric pairs + 2 homes)
local W, H          = 800, 600

-- ── Global state ─────────────────────────────────────────────────────────────
function init()
    g2.data = '{"payload":null,"summary":[]}'

    global("CLIENTS")       -- uid → client info table
    global("GAME_STATE")    -- "lobby" | "play" | "postgame"
    global("ADMIN_UID")     -- uid of first connected player (admin)

    -- recording globals (mirrors mod1.lua solo recorder)
    global("rec_clock")
    global("rec_frame")
    global("rec_pos_frame")
    global("rec_save_timer")
    global("rec_chunk_index")
    global("rec_log_events")
    global("rec_log_pos")
    global("rec_log_summary")
    global("rec_prev_fleets")
    global("rec_prev_planets")
    global("rec_game_users")   -- {p1=user_obj, p2=user_obj, neutral=user_obj}
    global("rec_player1_n")
    global("rec_player2_n")

    CLIENTS    = {}
    GAME_STATE = "lobby"
    ADMIN_UID  = nil

    reset_recording()
    update_lobby_html()
    g2.state = "lobby"
end

-- ─────────────────────────────────────────────────────────────────────────────
-- UTILITY
-- ─────────────────────────────────────────────────────────────────────────────
function round(x)
    return math.floor(x + 0.5)
end

function fmt_time(t)
    local m = math.floor(t / 60)
    local s = math.floor(t % 60)
    return string.format("%02d:%02d", m, s)
end

function count_queued()
    local n = 0
    for _, c in pairs(CLIENTS) do
        if c.status == "queue" then n = n + 1 end
    end
    return n
end

function find_user_obj(uid)
    for _, u in ipairs(g2.search("user")) do
        if u.user_uid == uid then return u end
    end
    return nil
end

function set_admin()
    -- admin = first connected player still in the room
    for uid, _ in pairs(CLIENTS) do
        ADMIN_UID = uid
        return
    end
    ADMIN_UID = nil
end

-- ─────────────────────────────────────────────────────────────────────────────
-- LOBBY HTML
-- ─────────────────────────────────────────────────────────────────────────────
function update_lobby_html()
    local queued = count_queued()
    local list   = ""
    for _, c in pairs(CLIENTS) do
        list = list .. "<tr><td><p>" .. c.name .. " — " .. c.status .. "</p>"
    end
    local start_btn = ""
    if queued >= 2 then
        start_btn = "<tr><td><input type='button' value='Start 1v1' onclick='/start' />"
    end
    local html = [[
        <table>
        <tr><td><h2>1v1 Replay Room</h2>
        <tr><td><p>Need 2 players queued to start.</p>
    ]] .. list .. [[
        <tr><td><p>&nbsp;</p>
    ]] .. start_btn .. [[
        <tr><td><input type='button' value='I am ready (/play)' onclick='/play' />
        <tr><td><input type='button' value='Away (/away)' onclick='/away' />
        </table>
    ]]
    g2.html = html
    g2.net_send("", "html", html)
    g2.net_send("", "state", "lobby")
end

-- ─────────────────────────────────────────────────────────────────────────────
-- NET EVENTS
-- ─────────────────────────────────────────────────────────────────────────────
function net_join(e)
    g2.net_send("", "sfx", "join")
    g2.net_send("", "message", e.name .. " joined")
    g2.net_send(e.uid, "message", "Welcome to 1v1 Replay Room!")
    g2.net_send(e.uid, "message", "Type /play to queue. /away to step back. /who to see players.")
    g2.net_send(e.uid, "message", "Games auto-start when 2 players queue up.")

    CLIENTS[e.uid] = {
        uid    = e.uid,
        name   = e.name,
        color  = e.client and e.client.color or 0xffffff,
        status = "queue",  -- auto-queue on join
    }

    if ADMIN_UID == nil then
        ADMIN_UID = e.uid
    end

    -- send current game state to the joiner
    if GAME_STATE == "play" then
        g2.net_send(e.uid, "state", "play")
        g2.net_send(e.uid, "message", "A game is in progress — you are spectating.")
    else
        update_lobby_html()
        maybe_auto_start()
    end
end

function net_leave(e)
    CLIENTS[e.uid] = nil
    g2.net_send("", "sfx", "leave")
    g2.net_send("", "message", e.name .. " left")

    if ADMIN_UID == e.uid then set_admin() end

    if GAME_STATE == "play" then
        -- if one of the two players left, surrender them
        surrender_uid(e.uid)
    else
        update_lobby_html()
    end
end

function net_message(e)
    local uid = e.uid
    local v   = e.value:lower():gsub("^%s+", "")

    if v == "/play" or v:find("^/play") == 1 then
        if CLIENTS[uid] then
            CLIENTS[uid].status = "queue"
            g2.net_send("", "message", CLIENTS[uid].name .. " is ready.")
        end
        update_lobby_html()
        maybe_auto_start()

    elseif v == "/away" then
        if CLIENTS[uid] then
            CLIENTS[uid].status = "away"
            g2.net_send("", "message", CLIENTS[uid].name .. " is away.")
        end
        update_lobby_html()

    elseif v == "/surrender" then
        if GAME_STATE == "play" then
            surrender_uid(uid)
        end

    elseif v == "/start" and (uid == ADMIN_UID or true) then
        -- allow anyone to force-start if 2 are queued
        if GAME_STATE ~= "play" and count_queued() >= 2 then
            init_game()
        else
            g2.net_send(uid, "message", "Need exactly 2 queued players. Use /play to queue.")
        end

    elseif v == "/stop" and uid == ADMIN_UID then
        if GAME_STATE == "play" then
            finish_game(nil)
        end

    elseif v == "/who" then
        local msg = "Players: "
        for _, c in pairs(CLIENTS) do
            msg = msg .. c.name .. "(" .. c.status .. ") "
        end
        g2.net_send(uid, "message", msg)
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- AUTO-START
-- ─────────────────────────────────────────────────────────────────────────────
function maybe_auto_start()
    if GAME_STATE ~= "lobby" then return end
    if count_queued() >= 2 then
        init_game()
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- GAME INIT  (24 planets, symmetric pairs + 2 homes)
-- ─────────────────────────────────────────────────────────────────────────────
function init_game()
    GAME_STATE = "play"
    g2.game_reset()
    math.randomseed(os.time())

    local neutral = g2.new_user("neutral", 0x999999)
    neutral.user_neutral        = true
    neutral.ships_production_enabled = 0

    -- pick the first two queued clients as players
    local player_clients = {}
    for uid, c in pairs(CLIENTS) do
        if c.status == "queue" and #player_clients < 2 then
            player_clients[#player_clients + 1] = c
        end
    end

    local colors = {0x00ff88, 0xff4444}
    local users  = {}
    for i, c in ipairs(player_clients) do
        local u   = g2.new_user(c.name, colors[i])
        u.user_uid = c.uid
        users[i]   = u
        CLIENTS[c.uid].status = "play"
    end

    -- 11 symmetric neutral pairs (22 neutral planets)
    local pad = 80
    for i = 1, 11 do
        local prod = math.random(20, 100)
        local ships = math.random(0, 30)
        local x    = math.random(pad, W - pad)
        local y    = math.random(pad, H - pad)
        g2.new_planet(neutral, x,     y,     prod, ships)
        g2.new_planet(neutral, W - x, H - y, prod, ships)
    end

    -- 2 home planets, one per player
    local home1 = g2.new_planet(users[1], 120,     H / 2, 100, 100)
    local home2 = g2.new_planet(users[2], W - 120, H / 2, 100, 100)

    g2.planets_settle(0, 0, W, H)
    g2.view_set(0, 0, W, H)

    -- build map snapshot for recorder
    local map_planets = {}
    for _, p in ipairs(g2.search("planet")) do
        map_planets[#map_planets + 1] = {
            n     = p.n,
            x     = round(p.position_x),
            y     = round(p.position_y),
            r     = round(p.planet_r),
            prod  = round(p.ships_production),
            ships = round(p.ships_value),
            owner = p.owner_n,
        }
    end

    -- store user refs for win-detection and recording
    rec_game_users = {
        p1      = users[1],
        p2      = users[2],
        neutral = neutral,
    }
    rec_player1_n = users[1].n
    rec_player2_n = users[2].n

    -- start recording
    reset_recording()
    local init_payload = {
        chunk    = 0,
        final    = false,
        status   = "part0",
        map      = map_planets,
        player_n = rec_player1_n,
        enemy_n  = rec_player2_n,
        version  = 1,
        w        = W,
        h        = H,
    }
    g2.data = json.encode({ payload = init_payload, summary = {} })
    rec_chunk_index = 1

    -- pre-populate prev_fleets
    for _, f in ipairs(g2.search("fleet")) do
        local id = tostring(f.sync_id)
        rec_prev_fleets[id] = {
            id     = id,
            x      = round(f.position_x),
            y      = round(f.position_y),
            ships  = round(f.fleet_ships),
            owner  = f.owner_n,
            target = f.fleet_target,
        }
    end

    -- in-game UI for players
    local play_html = [[
        <table>
        <tr><td><input type='button' value='Resume'    onclick='resume' />
        <tr><td><input type='button' value='Surrender' onclick='/surrender' />
        </table>
    ]]
    g2.html = play_html
    g2.net_send("", "html",  play_html)
    g2.net_send("", "state", "play")
    g2.net_send("", "sfx",   "start")
    g2.state = "play"

    g2.net_send("", "message",
        users[1].title_value .. " vs " .. users[2].title_value .. " — GO!")
end

-- ─────────────────────────────────────────────────────────────────────────────
-- GAME END
-- ─────────────────────────────────────────────────────────────────────────────
function finish_game(winner_user)
    if GAME_STATE ~= "play" then return end
    GAME_STATE = "postgame"

    -- flush final recording chunk FIRST
    flush_chunk(true)

    if winner_user then
        g2.net_send("", "message", winner_user.title_value .. " conquered the galaxy!")
    else
        g2.net_send("", "message", "Game over.")
    end
    g2.net_send("", "sfx", "stop")

    -- reset all play-status clients back to queue
    for _, c in pairs(CLIENTS) do
        if c.status == "play" then c.status = "queue" end
    end

    -- short pause then return to lobby
    GAME_STATE = "lobby"
    g2.state   = "lobby"
    update_lobby_html()
end

function surrender_uid(uid)
    if GAME_STATE ~= "play" then return end
    local user = find_user_obj(uid)
    if user == nil then return end

    -- give their planets to neutral
    local neutral = rec_game_users and rec_game_users.neutral
    if neutral then
        for _, p in ipairs(g2.search("planet owner:" .. user)) do
            p:planet_chown(neutral)
        end
    end

    -- find the other player and declare them winner
    local p1 = rec_game_users and rec_game_users.p1
    local p2 = rec_game_users and rec_game_users.p2
    local winner = nil
    if p1 and p1.user_uid ~= uid then winner = p1 end
    if p2 and p2.user_uid ~= uid then winner = p2 end
    finish_game(winner)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- WIN DETECTION  (called every loop)
-- ─────────────────────────────────────────────────────────────────────────────
function check_winner()
    if GAME_STATE ~= "play" then return end

    local owners = {}
    for _, p in ipairs(g2.search("planet -neutral")) do
        owners[p.owner_n] = true
    end
    -- count distinct non-neutral owners who still hold planets
    local count = 0
    local last_owner_n = nil
    for n, _ in pairs(owners) do
        count      = count + 1
        last_owner_n = n
    end

    if count <= 1 then
        -- find winner user object
        local winner = nil
        if last_owner_n then
            local p1 = rec_game_users and rec_game_users.p1
            local p2 = rec_game_users and rec_game_users.p2
            if p1 and p1.n == last_owner_n then winner = p1 end
            if p2 and p2.n == last_owner_n then winner = p2 end
        end
        finish_game(winner)
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- RECORDING  (ported directly from mod1.lua solo recorder)
-- ─────────────────────────────────────────────────────────────────────────────
function reset_recording()
    rec_clock       = 0
    rec_frame       = 0
    rec_pos_frame   = 0
    rec_save_timer  = 0
    rec_chunk_index = 1
    rec_log_events  = {}
    rec_log_pos     = {}
    rec_log_summary = {}
    rec_prev_fleets = {}
    rec_prev_planets = {}
end

function flush_chunk(final)
    local t_now = math.floor(rec_clock * 10) / 10

    -- snapshot final positions of all live fleets
    for id, f in pairs(rec_prev_fleets) do
        rec_log_pos[#rec_log_pos + 1] = { t_now, id, f.x, f.y, 0 }
    end

    local total = #rec_log_events + #rec_log_pos
    if total == 0 and not final then return end

    local existing = json.decode(g2.data) or {}
    existing.payload = {
        chunk   = rec_chunk_index,
        final   = final and true or false,
        status  = "part" .. rec_chunk_index,
        events  = rec_log_events,
        pos     = rec_log_pos,
    }
    existing.summary = rec_log_summary
    g2.data         = json.encode(existing)
    rec_log_events  = {}
    rec_log_pos     = {}
    rec_chunk_index = rec_chunk_index + 1
end

function record_loop(t)
    if GAME_STATE ~= "play" then return end

    rec_clock      = rec_clock + t
    rec_frame      = rec_frame + 1
    rec_pos_frame  = rec_pos_frame + 1
    rec_save_timer = rec_save_timer + t

    local t_now = math.floor(rec_clock * 10) / 10

    -- ── Planet selection events ───────────────────────────────────────────────
    for _, p in ipairs(g2.search("planet")) do
        local pid     = p.n
        local sel_raw = p:selected()
        local is_sel  = (sel_raw == true or sel_raw == 1) and 1 or 0
        local was_sel = rec_prev_planets[pid] and rec_prev_planets[pid].sel or 0
        if is_sel ~= was_sel then
            rec_prev_planets[pid] = rec_prev_planets[pid] or {}
            rec_prev_planets[pid].sel = is_sel
            rec_log_events[#rec_log_events + 1] = {
                e = is_sel == 1 and "sel" or "dsel",
                t = t_now,
                n = pid,
            }
        end
    end

    -- ── Fleet events ─────────────────────────────────────────────────────────
    local curr_fleets = {}
    for _, f in ipairs(g2.search("fleet")) do
        local id     = tostring(f.sync_id)
        local fx     = round(f.position_x)
        local fy     = round(f.position_y)
        local fships = round(f.fleet_ships)
        curr_fleets[id] = {
            id     = id,
            x      = fx,
            y      = fy,
            ships  = fships,
            owner  = f.owner_n,
            target = f.fleet_target,
        }

        if not rec_prev_fleets[id] then
            -- new fleet spawned — record rem from closest source planet
            local rem = nil
            for _, sp in ipairs(g2.search("planet owner:" .. f.owner_n)) do
                local dx = sp.position_x - f.position_x
                local dy = sp.position_y - f.position_y
                if math.sqrt(dx * dx + dy * dy) < 60 then
                    rem = math.floor(sp.ships_value)
                    break
                end
            end
            rec_log_events[#rec_log_events + 1] = {
                e   = "fs",
                t   = t_now,
                id  = id,
                o   = f.owner_n,
                s   = fships,
                tg  = f.fleet_target,
                x   = fx,
                y   = fy,
                rem = rem,
            }
            rec_log_pos[#rec_log_pos + 1] = { t_now, id, fx, fy, 0 }
        else
            local prev = rec_prev_fleets[id]
            if prev.target ~= f.fleet_target then
                rec_log_events[#rec_log_events + 1] = {
                    e  = "fr",
                    t  = t_now,
                    id = id,
                    tg = f.fleet_target,
                }
            end
            if prev.ships ~= fships then
                rec_log_events[#rec_log_events + 1] = {
                    e  = "fu",
                    t  = t_now,
                    id = id,
                    s  = fships,
                }
            end
        end
    end

    -- ── Fleet destructions ───────────────────────────────────────────────────
    for id, pf in pairs(rec_prev_fleets) do
        if not curr_fleets[id] then
            rec_log_pos[#rec_log_pos + 1] = { t_now, id, pf.x, pf.y, 0 }
            rec_log_events[#rec_log_events + 1] = {
                e  = "fd",
                t  = t_now,
                id = id,
                tg = pf.target,
                o  = pf.owner,
            }
        end
    end
    rec_prev_fleets = curr_fleets

    -- ── Planet owner changes ─────────────────────────────────────────────────
    for _, p in ipairs(g2.search("planet")) do
        local pid   = p.n
        local owner = p.owner_n
        rec_prev_planets[pid] = rec_prev_planets[pid] or {}
        if rec_prev_planets[pid].owner ~= nil and
           rec_prev_planets[pid].owner ~= owner then
            rec_log_events[#rec_log_events + 1] = {
                e = "pc",
                t = t_now,
                n = pid,
                o = owner,
            }
        end
        rec_prev_planets[pid].owner = owner
    end

    -- ── Position + ship-count samples (every POSITION_RATE frames) ───────────
    if rec_pos_frame >= POSITION_RATE then
        rec_pos_frame = 0
        for id, f in pairs(curr_fleets) do
            rec_log_pos[#rec_log_pos + 1] = { t_now, id, f.x, f.y, 0 }
        end
        for _, p in ipairs(g2.search("planet")) do
            rec_log_events[#rec_log_events + 1] = {
                e = "pn",
                t = t_now,
                n = p.n,
                s = round(p.ships_value),
            }
        end
    end

    -- ── Summary log (every 30 frames) ────────────────────────────────────────
    if rec_frame % 30 == 0 and rec_game_users then
        local p1 = rec_game_users.p1
        local p2 = rec_game_users.p2
        local ps, pp, es, ep = 0, 0, 0, 0
        for _, p in ipairs(g2.search("planet")) do
            local own = p.owner_n
            if p1 and own == p1.n then
                ps = ps + round(p.ships_value)
                pp = pp + round(p.ships_production)
            elseif p2 and own == p2.n then
                es = es + round(p.ships_value)
                ep = ep + round(p.ships_production)
            end
        end
        for _, f in ipairs(g2.search("fleet")) do
            local own = f.owner_n
            if p1 and own == p1.n then
                ps = ps + round(f.fleet_ships)
            elseif p2 and own == p2.n then
                es = es + round(f.fleet_ships)
            end
        end
        rec_log_summary[#rec_log_summary + 1] = {
            t  = math.floor(rec_clock * 100) / 100,
            ps = ps, pp = pp, es = es, ep = ep,
        }
    end

    -- ── Auto-flush ───────────────────────────────────────────────────────────
    local total_pending = #rec_log_events + #rec_log_pos
    if total_pending >= CHUNK_SIZE or rec_save_timer >= 1.0 then
        rec_save_timer = 0
        flush_chunk(false)
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- MAIN LOOP
-- ─────────────────────────────────────────────────────────────────────────────
function loop(t)
    if g2.state ~= "play" then return end
    record_loop(t)
    check_winner()
end

-- ─────────────────────────────────────────────────────────────────────────────
-- EVENT DISPATCH
-- ─────────────────────────────────────────────────────────────────────────────
function event(e)
    if e.type == "net:join" then
        net_join(e)
    elseif e.type == "net:leave" then
        net_leave(e)
    elseif e.type == "net:message" then
        net_message(e)
    elseif e.type == "onclick" then
        -- forward button clicks as if they were chat messages
        net_message({ uid = e.uid, value = e.value })
    elseif e.type == "pause" then
        g2.state = "pause"
        g2.html  = [[
            <table>
            <tr><td><input type='button' value='Resume'    onclick='resume' />
            <tr><td><input type='button' value='Surrender' onclick='/surrender' />
            </table>
        ]]
    elseif e.type == "resume" then
        g2.state = "play"
    end
end
