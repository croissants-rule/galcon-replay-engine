strict(true)

local ROOM_TITLE    = "1v1 Replays"
local DEFAULT_PORT  = "23099"
local POSITION_RATE = 1   
local CHUNK_SIZE    = 200  
local WIN_CHECK_DELAY = 8.0

local SW, SH = 520, 360

local MAP = {
    neutrals   = 25,  -- matches Aphid's galcon_classic_init OPTS.neutrals exactly (shared by every style, including Stages)
    prod_min   = 30,
    prod_max   = 100,
    home_prod  = 100,
    home_ships = 100,
    pad        = 30,
}

local PLAYER_COLORS = {
    0x00ff88, 0xff4444, 0x4488ff, 0xffee44,
    0xff88ff, 0x44ffff, 0xff8800, 0x88ff00,
}

local APHID_COLORS={
{"8a0000","bb0000","ff0000"},{"008a00","00bb00","00ff00"},
{"00008a","0000bb","0000ff"},{"8a8a00","bbbb00","ffff00"},
{"008a8a","00bbbb","00ffff"},{"8a008a","bb00bb","ff00ff"},
{"8a8a8a","bbbbbb","ffffff"},{"a84a02","cf5b02","ff6f00"},
{"9e3c81","c947a2","ff73d5"},{"029e68","00d68c","00ffa6"},
{"0053ed","0080ff","59acff"},{"ab5443","cc6854","ff917a"},
}

local ALL_COLORS = {
    "7f0000",
    "ff0000",
    "ff7f7f",
    "7f3f00",
    "ff7f00",
    "ffbf7f",
    "7f7f00",
    "feff00",
    "feff7f",
    "3f7f00",
    "7fff00",
    "bfff7f",
    "007f00",
    "00ff00",
    "7fff7f",
    "007f7f",
    "00feff",
    "7ffeff",
    "003f7f",
    "007fff",
    "7fbfff",
    "00007f",
    "0000ff",
    "7f7fff",
    "3f007f",
    "7f00ff",
    "bf7fff",
    "7f007f",
    "ff00fe",
    "ff7ffe",
}
local GALCON_COLORS = ALL_COLORS  
local GALCON_COLOR_NAMES = {}
local PRESET_COLORS = ALL_COLORS

local player_custom_colors = {}
local player_custom_ships   = {}
local player_custom_skins   = {}  

local SHIP_NAMES = {
    "f17",
    "f16",
    "f15",
    "f14",
    "f13",
    "f12",
    "f11",
    "f10",
    "f9",
    "f8",
    "f7",
    "f6",
    "f5",
    "f4",
    "f3",
    "f2",
    "f1",
    "dis1",
    "dec6",
    "dec5",
    "dec4",
    "dec3",
    "dec2",
    "dec1",
    "22c",
    "22b",
    "110",
    "109",
    "108",
    "107",
    "106",
    "105",
    "104",
    "103",
    "102",
    "101",
    "80",
    "79",
    "78",
    "77",
    "76",
    "70",
    "69",
    "68",
    "67",
    "66",
    "60",
    "59",
    "58",
    "50",
    "49",
    "48",
    "47",
    "46",
    "45",
    "44",
    "43",
    "42",
    "41",
    "40",
    "39",
    "38",
    "37",
    "36",
    "35",
    "34",
    "33",
    "32",
    "31",
    "30",
    "29",
    "28",
    "27",
    "26",
    "25",
    "24",
    "23",
    "22",
    "21",
    "20",
    "19",
    "18",
    "17",
    "16",
    "15",
    "14",
    "13",
    "12",
    "11",
    "10",
    "9",
    "8",
    "7",
    "6",
    "5",
    "4",
    "3",
    "2",
    "1",
    "0",
}

-- Planet skins, following the same pattern Aphid uses in SaandCon: a name list
-- for iteration/search plus a style table encoded onto `user.planet_style` as JSON.
local SKIN_NAMES = {
    "normal", "honeycomb", "ice", "terrestrial", "gasgiant", "craters",
    "gaseous", "lava", "void", "disco", "swirls", "floralpattern",
    "hearts", "clovers", "zerba", "giraffe", "eyes", "cow", "fossil",
    "snowcaps", "smooth", "whisp", "charlie", "snowflake", "candycane",
    "snowglobe",
}

local SKIN_LABELS = {
    normal       = "Normal",
    honeycomb    = "Honeycomb",
    ice          = "Ice",
    terrestrial  = "Terrestrial",
    gasgiant     = "Gas Giant",
    craters      = "Craters",
    gaseous      = "Gaseous",
    lava         = "Lava",
    void         = "Void",
    disco        = "Disco",
    swirls       = "Swirls",
    floralpattern= "Floral",
    hearts       = "Hearts",
    clovers      = "Clovers",
    zerba        = "Zebra",
    giraffe      = "Giraffe",
    eyes         = "Eyes",
    cow          = "Cow",
    fossil       = "Fossil",
    snowcaps     = "Snowcaps",
    smooth       = "Smooth",
    whisp        = "Whisp",
    charlie      = "Charlie",
    snowflake    = "Snowflake",
    candycane    = "Candycane",
    snowglobe    = "Snowglobe",
}

-- Render definitions -- same shape SaandCon encodes onto user.planet_style.
-- NOTE: "void" has no confirmed reference definition; approximated here as a
-- flat, unlit texture. Tweak texture id if/when we confirm Aphid's real value.
local SKIN_STYLES = {
    normal        = {normal=true, lighting=true, texture="tex0"},
    honeycomb     = {lighting=true, texture="tex13", normal=true},
    ice           = {ambient=true, texture="tex3", drawback=true, alpha=.65, addition=true, lighting=true},
    terrestrial   = {overdraw={addition=true, alpha=.5, reflection=true, texture="tex7w"}, normal=true, lighting=true, texture="tex7"},
    gasgiant      = {overdraw={texture="tex1", yaxis=true, alpha=.25, addition=true, lighting=true}, normal=true, lighting=true, texture="tex9"},
    craters       = {texture="tex12", normal=true, lighting=true, overdraw={texture="tex12b", yaxis=true, lighting=true, alpha=1, addition=true}},
    gaseous       = {overdraw={texture="tex2", yaxis=true, addition=true, lighting=true}, normal=true, lighting=true, texture="tex2"},
    lava          = {overdraw={ambient=true, addition=true, texture="tex5"}, normal=true, lighting=true, texture="tex0"},
    void          = {normal=false, lighting=false, texture="tex6"},
    disco         = {overdraw={ambient=true, addition=true, yaxis=true, texture="dis2"}, normal=true, lighting=true, texture="dis1"},
    swirls        = {normal=true, lighting=true, texture="tex16"},
    floralpattern = {normal=false, lighting=false, texture="tex19"},
    hearts        = {normal=true, lighting=true, texture="tex17"},
    clovers       = {normal=true, lighting=true, texture="tex18"},
    zerba         = {normal=true, lighting=true, texture="texs1"},
    giraffe       = {normal=true, lighting=true, texture="texs2"},
    eyes          = {normal=true, lighting=true, texture="texs3"},
    cow           = {normal=true, lighting=true, texture="texw1"},
    fossil        = {normal=true, lighting=true, texture="texw2"},
    snowcaps      = {normal=true, lighting=true, texture="tex15"},
    smooth        = {normal=false, lighting=false, texture="tex6"},
    whisp         = {overdraw={texture="tex12b", yaxis=true, addition=true, lighting=true}, normal=true, lighting=true, texture="tex12b"},
    charlie       = {normal=true, lighting=true, texture="dec1"},
    snowflake     = {normal=true, lighting=true, texture="dec2"},
    candycane     = {normal=true, lighting=true, texture="dec3"},
    snowglobe     = {overdraw={texture="dec4", alpha=1.5, drawback=true, yaxis=true, addition=false, lighting=false}, normal=true, lighting=true, texture="dec4"},
}

local DEFAULT_ELO = 1200
local ELO_K       = 15   -- same as Aphid's SaandCon
local STATS       = {}   

function ensure_stats(uid, name, color)
    if not STATS[uid] then
        STATS[uid] = {
            name    = name  or "?",
            color   = color or "aaaaaa",
            elo     = DEFAULT_ELO,
            wins    = 0,
            losses  = 0,
            streak  = 0,            h2h     = {},   
            history = {},   -- [{elo=N,label="vs Name"}]
        }
    end
    if name  then STATS[uid].name  = name  end
    if color then STATS[uid].color = color end
    return STATS[uid]
end

function calc_elo_change(winner_elo, loser_elo)
    local exp = 1 / (1 + 10 ^ ((loser_elo - winner_elo) / 400))
    return math.max(1, math.floor(ELO_K * (1 - exp)))
end

-- Every finished game with a winner counts for ELO (no ranked/warm-up split).
function apply_result(winner_uid, loser_uid)
    local ws = ensure_stats(winner_uid)
    local ls = ensure_stats(loser_uid)
    if not ws or not ls then return end

    ws.h2h[loser_uid]  = ws.h2h[loser_uid]  or {w=0,l=0}
    ls.h2h[winner_uid] = ls.h2h[winner_uid] or {w=0,l=0}
    ws.h2h[loser_uid].w  = ws.h2h[loser_uid].w  + 1
    ls.h2h[winner_uid].l = ls.h2h[winner_uid].l + 1

    ws.wins   = ws.wins   + 1
    ls.losses = ls.losses + 1

    ws.streak = ws.streak >= 0 and ws.streak + 1 or  1
    ls.streak = ls.streak <= 0 and ls.streak - 1 or -1

    local delta = calc_elo_change(ws.elo, ls.elo)
    ws.elo = ws.elo + delta
    ls.elo = math.max(100, ls.elo - delta)

    table.insert(ws.history, {elo=ws.elo, vs=ls.name, won=true})
    table.insert(ls.history, {elo=ls.elo, vs=ws.name, won=false})

    net_send("", "message", string.format(
        "%s +%d ELO (%d)  ·  %s -%d ELO (%d)",
        ws.name, delta, ws.elo,
        ls.name, delta, ls.elo
    ))
end

function streak_emoji(streak)
    if streak >= 5 then return " [W" .. streak .. "!!]"
    elseif streak >= 2 then return " [W" .. streak .. "]"
    elseif streak <= -5 then return " [L" .. math.abs(streak) .. "!!]"
    elseif streak <= -2 then return " [L" .. math.abs(streak) .. "]"
    else return "" end
end

function h2h_text(uid1, uid2)
    local s = STATS[uid1]
    if not s or not s.h2h[uid2] then return "" end
    local h = s.h2h[uid2]
    local total = h.w + h.l
    if total == 0 then return "" end
    local pct = math.floor(h.w / total * 100)
    return string.format(" [vs %s: %dW-%dL %d%%]", STATS[uid2] and STATS[uid2].name or "?", h.w, h.l, pct)
end

function elo_text(uid)
    local s = STATS[uid]
    if not s then return "ELO: " .. DEFAULT_ELO end
    return string.format("ELO: %d  %dW-%dL", s.elo, s.wins, s.losses)
end

-- /elo        -> your own rating
-- /elo name   -> anyone's rating (exact name first, then partial match)
function elo_command(uid, query)
    local target_uid
    if not query or query == "" then
        target_uid = uid
        ensure_stats(uid, GAME.clients[uid] and GAME.clients[uid].name or nil)
    else
        local q = query:lower()
        local partial = {}
        for ouid, s in pairs(STATS) do
            local n = tostring(s.name or ""):lower()
            if n == q then target_uid = ouid; break end
            if n:find(q, 1, true) then partial[#partial + 1] = ouid end
        end
        if not target_uid then
            if #partial == 1 then
                target_uid = partial[1]
            elseif #partial > 1 then
                local names = {}
                for i = 1, math.min(6, #partial) do names[#names + 1] = STATS[partial[i]].name end
                net_send(uid, "message", "Several players match '" .. query .. "': " .. table.concat(names, ", "))
                return
            else
                net_send(uid, "message", "No player named '" .. query .. "' has played here yet.")
                return
            end
        end
    end
    local s = STATS[target_uid]
    if not s then net_send(uid, "message", "No games played yet."); return end
    local all = {}
    for ouid, os_ in pairs(STATS) do all[#all + 1] = { uid = ouid, elo = os_.elo } end
    table.sort(all, function(a, b) return a.elo > b.elo end)
    local rank = 0
    for i, x in ipairs(all) do if x.uid == target_uid then rank = i; break end end
    local streak = ""
    if (s.streak or 0) >= 2 then streak = "  ·  W" .. s.streak .. " streak"
    elseif (s.streak or 0) <= -2 then streak = "  ·  L" .. math.abs(s.streak) .. " streak" end
    local msg = string.format("%s: %d ELO  ·  #%d of %d  ·  %dW-%dL%s",
        s.name, s.elo, rank, #all, s.wins, s.losses, streak)
    if target_uid ~= uid and STATS[uid] and STATS[uid].h2h[target_uid] then
        local h = STATS[uid].h2h[target_uid]
        msg = msg .. string.format("  ·  you vs them: %dW-%dL", h.w, h.l)
    end
    net_send(uid, "message", msg)
end

-- ── Persistent stats ─────────────────────────────────────────────────────
-- STATS used to live only in memory, so every reload of the mod (an update,
-- a restart, closing Galcon) wiped everyone's ELO. It is now saved inside
-- g2.data (mod1.bin) under "stats" on every write and loaded whenever this
-- file runs. Saved as a list of player records, not a uid-keyed table:
-- Galcon's JSON (lua-cjson, sparse arrays as objects) would turn numeric uid
-- keys into strings and they would no longer match anyone after loading.
local STATS_HISTORY_KEEP = 20

function stats_serialize()
    local out = {}
    for uid, s in pairs(STATS) do
        local h2h = {}
        for ouid, r in pairs(s.h2h or {}) do
            h2h[#h2h + 1] = { uid = ouid, w = r.w or 0, l = r.l or 0 }
        end
        local hist, h = {}, s.history or {}
        for i = math.max(1, #h - STATS_HISTORY_KEEP + 1), #h do hist[#hist + 1] = h[i] end
        out[#out + 1] = {
            uid = uid, name = s.name, color = s.color, elo = s.elo,
            wins = s.wins, losses = s.losses, streak = s.streak,
            h2h = h2h, history = hist,
        }
    end
    return out
end

-- Merge saved records into STATS (saved values win over defaults).
function stats_load(list)
    if type(list) ~= "table" then return 0 end
    local n = 0
    for _, r in ipairs(list) do
        if type(r) == "table" and r.uid ~= nil then
            local h2h = {}
            if type(r.h2h) == "table" then
                for _, x in ipairs(r.h2h) do
                    if type(x) == "table" and x.uid ~= nil then
                        h2h[x.uid] = { w = tonumber(x.w) or 0, l = tonumber(x.l) or 0 }
                    end
                end
            end
            local hist = {}
            if type(r.history) == "table" then
                for _, x in ipairs(r.history) do if type(x) == "table" then hist[#hist + 1] = x end end
            end
            STATS[r.uid] = {
                name = r.name or "?", color = r.color or "aaaaaa",
                elo = tonumber(r.elo) or DEFAULT_ELO,
                wins = tonumber(r.wins) or 0, losses = tonumber(r.losses) or 0,
                streak = tonumber(r.streak) or 0,
                h2h = h2h, history = hist,
            }
            n = n + 1
        end
    end
    return n
end

-- Every g2.data write goes through here so the saved stats and the server
-- port survive the replay recorder's chunk writes.
function g2data_write(tbl)
    tbl.stats = stats_serialize()
    if GAME and GAME.data and GAME.data.port then tbl.port = GAME.data.port end
    g2.data = json.encode(tbl)
end

-- Re-save the current g2.data contents with up-to-date stats.
function stats_save()
    local ok, decoded = pcall(json.decode, g2.data)
    local existing = (ok and type(decoded) == "table") and decoded or {}
    g2data_write(existing)
end

local HOST_UID  = nil   
local HOST_NAME = nil   

-- ══ ROOM MODES ═══════════════════════════════════════════════════════════
-- standard : the original 1v1 room (2 queued players, START or 2nd /play starts)
-- wso      : winner stays on. Everyone who /plays joins a line. The winner
--            keeps playing; the loser goes to the back of the line (away) and
--            the front of the line challenges next. With 2 players it is just
--            the same two again.
-- tourney  : single elimination. Random bracket, odd player out gets a bye
--            (never the same player twice in a row when avoidable), winners
--            advance until a final decides it. Every match is an ordinary
--            recorded game -- nothing about the final is special.
-- rr / drr : round robin / double round robin. Everyone plays everyone once
--            (twice, with sides swapped, for double). Most wins takes it
--            (head-to-head among the tied players breaks ties).
-- Every event game is a normal game: same recording, same ELO handling.
-- State lives under GAME: room_mode, wso, ev (active event), ev_last,
-- ev_names. A client in an event/line has c.rot = true; the two players in
-- the next match are status "queue", every other client is "away".
local ROOM_MODE_ORDER = { "standard", "wso", "tourney", "rr", "drr" }
local ROOM_MODE_LABEL = {
    standard = "Standard", wso = "Winner Stays On", tourney = "Tournament",
    rr = "Round Robin", drr = "Double Round Robin",
}
local ROOM_MODE_BTN = {
    standard = "Standard", wso = "Winner Stays", tourney = "Tournament",
    rr = "Round Robin", drr = "Double RR",
}
local ROOM_MODE_HELP = {
    standard = "Normal 1v1 room: two players queue and play.",
    wso      = "Winner keeps playing. The loser goes to the back of the line and the next player in line challenges.",
    tourney  = "Single elimination bracket. Odd player out gets a bye. Winners advance until the final.",
    rr       = "Everyone plays everyone once. Most wins takes it.",
    drr      = "Everyone plays everyone twice (sides swapped). Most wins takes it.",
}

function is_event_mode() return (GAME.room_mode or "standard") ~= "standard" end
function is_bracket_mode()
    local m = GAME.room_mode
    return m == "tourney" or m == "rr" or m == "drr"
end
function ev_active() return GAME.ev ~= nil and not GAME.ev.done end

function ev_say(msg) net_send("", "message", msg) end

function ev_name(uid)
    local c = GAME.clients[uid]
    if c then return c.name end
    return (GAME.ev_names and GAME.ev_names[uid]) or "?"
end

function ev_remember(uid)
    GAME.ev_names = GAME.ev_names or {}
    local c = GAME.clients[uid]
    if c then GAME.ev_names[uid] = c.name end
end

function ev_present(uid)
    local c = GAME.clients[uid]
    return c ~= nil and c.rot == true and not c.is_host
end

function ev_shuffle(t)
    for i = #t, 2, -1 do
        local j = math.random(1, i)
        t[i], t[j] = t[j], t[i]
    end
    return t
end

function ev_index(list, v)
    for i, x in ipairs(list) do if x == v then return i end end
    return nil
end

-- Clients who have joined the line/event pool, in room join order.
function pool_uids()
    local out = {}
    for _, uid in ipairs(GAME.client_order) do
        local c = GAME.clients[uid]
        if c and c.rot and not c.is_host then out[#out + 1] = uid end
    end
    return out
end

-- ── Winner stays on ─────────────────────────────────────────────────────
function wso_state()
    if not GAME.wso then GAME.wso = { champ = nil, line = {}, streak = 0 } end
    return GAME.wso
end

-- Drop anyone who left or stepped away; append pool members not yet in line.
function wso_clean()
    local w = wso_state()
    if w.champ and not ev_present(w.champ) then w.champ = nil; w.streak = 0 end
    local line = {}
    for _, uid in ipairs(w.line) do
        if ev_present(uid) and uid ~= w.champ and not ev_index(line, uid) then line[#line + 1] = uid end
    end
    for _, uid in ipairs(pool_uids()) do
        if uid ~= w.champ and not ev_index(line, uid) then line[#line + 1] = uid end
    end
    w.line = line
end

function wso_pair()
    local w = wso_state()
    wso_clean()
    if w.champ then return w.champ, w.line[1] end
    return w.line[1], w.line[2]
end

function wso_on_result(winner, a, b)
    local w = wso_state()
    if not winner then
        ev_say("Match not counted -- same two play again.")
        return
    end
    local loser = (winner == a) and b or a
    local old_champ = w.champ
    if old_champ == winner then w.streak = (w.streak or 0) + 1 else w.streak = 1 end
    -- Take both players out of the line, crown the winner, send the loser to the back.
    local line = {}
    for _, uid in ipairs(w.line) do
        if uid ~= a and uid ~= b then line[#line + 1] = uid end
    end
    w.champ = winner
    if loser and ev_present(loser) then line[#line + 1] = loser end
    w.line = line
    wso_clean()
    if old_champ and old_champ ~= winner and loser == old_champ then
        ev_say(ev_name(winner) .. " dethrones " .. ev_name(loser) .. "!")
    elseif w.streak >= 2 then
        ev_say(ev_name(winner) .. " stays on -- " .. w.streak .. " wins in a row.")
    end
end

-- ── Tournament (single elimination) ─────────────────────────────────────
function tourney_round_name(n_alive)
    if n_alive <= 2 then return "Final" end
    if n_alive <= 4 then return "Semifinals" end
    if n_alive <= 8 then return "Quarterfinals" end
    return nil
end

function tourney_build_round(ev, alive)
    ev.matches, ev.cur, ev.bye = {}, 1, nil
    local list = {}
    for i, uid in ipairs(alive) do list[i] = uid end
    if #list % 2 == 1 then
        -- Bye goes to the last player (from the end) who hasn't had one.
        local pick = #list
        for i = #list, 1, -1 do
            if not ev.had_bye[list[i]] then pick = i; break end
        end
        ev.bye = table.remove(list, pick)
        ev.had_bye[ev.bye] = true
    end
    for i = 1, #list - 1, 2 do
        ev.matches[#ev.matches + 1] = { a = list[i], b = list[i + 1] }
    end
    ev.round_label = tourney_round_name(#alive) or ("Round " .. ev.round)
    local parts = {}
    for _, m in ipairs(ev.matches) do parts[#parts + 1] = ev_name(m.a) .. " vs " .. ev_name(m.b) end
    ev_say("[TOURNAMENT] " .. ev.round_label .. ": " .. table.concat(parts, ", ")
        .. (ev.bye and (" -- bye: " .. ev_name(ev.bye)) or ""))
end

-- Called whenever a match is decided or a player drops out. Settles
-- walkovers, and when the round is complete, builds the next one or
-- crowns the champion.
function tourney_advance(ev)
    for _, m in ipairs(ev.matches) do
        if not m.winner and not m.void and not m.live then
            local ga, gb = ev.gone[m.a], ev.gone[m.b]
            if ga and gb then
                m.void = true
            elseif ga or gb then
                m.winner = ga and m.b or m.a
                m.loser  = ga and m.a or m.b
                m.walkover = true
                ev.out[m.loser] = true
                ev_say("[TOURNAMENT] " .. ev_name(m.winner) .. " advances -- "
                    .. ev_name(m.loser) .. " is out (walkover).")
            end
        end
    end
    if ev.bye and ev.gone[ev.bye] then ev.bye = nil end
    ev.cur = nil
    for i, m in ipairs(ev.matches) do
        if not m.winner and not m.void then ev.cur = i; break end
    end
    if ev.cur then return end
    -- Round complete.
    local alive = {}
    for _, m in ipairs(ev.matches) do
        if m.winner and not ev.gone[m.winner] then alive[#alive + 1] = m.winner end
    end
    if ev.bye then alive[#alive + 1] = ev.bye end
    if #alive >= 2 then
        ev.round = ev.round + 1
        tourney_build_round(ev, alive)
        tourney_advance(ev)   -- a player may already be gone
        return
    end
    ev.done = true
    ev.champion = alive[1]
    if ev.champion then
        local beat = ev.beat[ev.champion] or {}
        local names = {}
        for _, uid in ipairs(beat) do names[#names + 1] = ev_name(uid) end
        ev_say("==============================")
        ev_say("*** " .. ev_name(ev.champion) .. " WINS THE TOURNAMENT! ***")
        if #names > 0 then ev_say("Path: beat " .. table.concat(names, ", ")) end
        ev_say("==============================")
    else
        ev_say("[TOURNAMENT] Ended with no winner (everyone left).")
    end
end

-- ── Round robin / double round robin ────────────────────────────────────
-- Circle method: one player fixed, the rest rotate, so every round has
-- everyone playing once and nobody waits long between games. Sides
-- alternate so nobody is always P1. Double adds a second leg with sides
-- swapped.
-- Reorder so nobody plays two games in a row when it can be avoided:
-- always take the earliest remaining match that shares no player with
-- the previous one (falls back to the earliest if every one does).
function rr_spread(list, prev)
    local rest, out = {}, {}
    for i, m in ipairs(list) do rest[i] = m end
    while #rest > 0 do
        local pick = 1
        if prev then
            for i, m in ipairs(rest) do
                if m.a ~= prev.a and m.a ~= prev.b and m.b ~= prev.a and m.b ~= prev.b then pick = i; break end
            end
        end
        prev = table.remove(rest, pick)
        out[#out + 1] = prev
    end
    return out
end

function rr_build(ev, players, double)
    local arr = {}
    for i, uid in ipairs(players) do arr[i] = uid end
    ev_shuffle(arr)
    if #arr % 2 == 1 then arr[#arr + 1] = false end   -- false = bye slot
    local n, half = #arr, math.floor(#arr / 2)
    ev.matches = {}
    for r = 1, n - 1 do
        for i = 1, half do
            local a, b = arr[i], arr[n + 1 - i]
            if a and b then
                if (r + i) % 2 == 0 then a, b = b, a end
                ev.matches[#ev.matches + 1] = { a = a, b = b, leg = 1 }
            end
        end
        local last = table.remove(arr, n)
        table.insert(arr, 2, last)
    end
    local leg1 = rr_spread(ev.matches, nil)
    ev.matches = leg1
    if double then
        local leg2 = {}
        for i, m in ipairs(leg1) do leg2[i] = { a = m.b, b = m.a, leg = 2 } end
        leg2 = rr_spread(leg2, leg1[#leg1])
        for _, m in ipairs(leg2) do ev.matches[#ev.matches + 1] = m end
    end
    ev.wins, ev.losses = {}, {}
    for _, uid in ipairs(players) do ev.wins[uid] = 0; ev.losses[uid] = 0 end
    ev.cur = 1
end

-- Players ordered by wins (desc), then fewer losses, then name.
function rr_standings(ev)
    local list = {}
    for _, uid in ipairs(ev.players) do list[#list + 1] = uid end
    table.sort(list, function(x, y)
        local wx, wy = ev.wins[x] or 0, ev.wins[y] or 0
        if wx ~= wy then return wx > wy end
        local lx, ly = ev.losses[x] or 0, ev.losses[y] or 0
        if lx ~= ly then return lx < ly end
        return ev_name(x):lower() < ev_name(y):lower()
    end)
    return list
end

function rr_advance(ev)
    for _, m in ipairs(ev.matches) do
        if not m.winner and not m.void and not m.live and (ev.gone[m.a] or ev.gone[m.b]) then
            m.void = true
            ev.dropped = (ev.dropped or 0) + 1
        end
    end
    ev.cur = nil
    for i, m in ipairs(ev.matches) do
        if not m.winner and not m.void then ev.cur = i; break end
    end
    if ev.cur then return end
    ev.done = true
    -- Winner(s): most wins; ties broken by wins in games between the tied players.
    local st = rr_standings(ev)
    local present = {}
    for _, uid in ipairs(st) do if not ev.gone[uid] then present[#present + 1] = uid end end
    if #present == 0 then present = st end
    local top = ev.wins[present[1]] or 0
    local tied = {}
    for _, uid in ipairs(present) do if (ev.wins[uid] or 0) == top then tied[#tied + 1] = uid end end
    local winners = tied
    if #tied > 1 then
        local h2h, best = {}, -1
        for _, uid in ipairs(tied) do h2h[uid] = 0 end
        for _, m in ipairs(ev.matches) do
            if m.winner and h2h[m.a] and h2h[m.b] then h2h[m.winner] = h2h[m.winner] + 1 end
        end
        for _, uid in ipairs(tied) do if h2h[uid] > best then best = h2h[uid] end end
        winners = {}
        for _, uid in ipairs(tied) do if h2h[uid] == best then winners[#winners + 1] = uid end end
    end
    ev.champions = winners
    local label = (ev.kind == "drr") and "DOUBLE ROUND ROBIN" or "ROUND ROBIN"
    local parts = {}
    for i, uid in ipairs(st) do
        parts[#parts + 1] = i .. ". " .. ev_name(uid) .. " " .. (ev.wins[uid] or 0) .. "-" .. (ev.losses[uid] or 0)
    end
    ev_say("==============================")
    if #winners == 1 then
        local w = winners[1]
        ev_say("*** " .. ev_name(w) .. " WINS THE " .. label .. "! *** ("
            .. (ev.wins[w] or 0) .. "-" .. (ev.losses[w] or 0) .. ")")
        if #tied > 1 then ev_say("(Tiebreak: head-to-head)") end
    else
        local names = {}
        for _, uid in ipairs(winners) do names[#names + 1] = ev_name(uid) end
        ev_say("*** " .. table.concat(names, " & ") .. " SHARE THE " .. label .. "! *** (" .. top .. " wins each)")
    end
    ev_say("Final: " .. table.concat(parts, "   "))
    ev_say("==============================")
end

function ev_advance(ev)
    if ev.kind == "tourney" then tourney_advance(ev) else rr_advance(ev) end
    if ev.done then
        GAME.ev_last = ev
        GAME.ev = nil
    end
end

function ev_games_total(ev)
    local n = 0
    for _, m in ipairs(ev.matches) do if not m.void then n = n + 1 end end
    return n
end

function ev_games_played(ev)
    local n = 0
    for _, m in ipairs(ev.matches) do if m.winner and not m.walkover then n = n + 1 end end
    return n
end

-- ── Event lifecycle ─────────────────────────────────────────────────────
function ev_start()
    local pool = pool_uids()
    if #pool < 2 then
        return false, "Need at least 2 players -- type /play to join."
    end
    for _, uid in ipairs(pool) do ev_remember(uid) end
    local kind = GAME.room_mode
    local ev = { kind = kind, players = pool, gone = {}, out = {}, beat = {}, round = 1, had_bye = {} }
    GAME.ev_last = nil
    if kind == "tourney" then
        local order = {}
        for i, uid in ipairs(pool) do order[i] = uid end
        ev_shuffle(order)
        GAME.ev = ev
        tourney_build_round(ev, order)
    else
        rr_build(ev, pool, kind == "drr")
        GAME.ev = ev
        local names = {}
        for _, uid in ipairs(pool) do names[#names + 1] = ev_name(uid) end
        ev_say("[" .. ROOM_MODE_LABEL[kind]:upper() .. "] " .. #pool .. " players, "
            .. #ev.matches .. " games: " .. table.concat(names, ", "))
    end
    return true
end

function ev_cancel(by)
    if GAME.room_mode == "wso" then
        local w = wso_state()
        w.champ, w.streak = nil, 0
        ev_say("Winner-stays-on reset by " .. by .. " -- line kept, no champion.")
        return
    end
    if not ev_active() then return end
    GAME.ev = nil
    ev_say(ROOM_MODE_LABEL[GAME.room_mode] .. " cancelled by " .. by .. ".")
end

-- The two uids who play next, or nil.
function ev_next_pair()
    if GAME.room_mode == "wso" then return wso_pair() end
    local ev = GAME.ev
    if not ev or ev.done or not ev.cur then return nil end
    local m = ev.matches[ev.cur]
    if not m then return nil end
    return m.a, m.b
end

-- Mark exactly the next match's two players "queue", everyone else "away".
-- Never touches anyone currently in a game unless `force` (galcon_stop,
-- which has already moved them back out of "play").
function ev_apply_statuses(force)
    if not is_event_mode() then return end
    if g2.state == "play" and not force then return end
    local a, b = ev_next_pair()
    for uid, c in pairs(GAME.clients) do
        if not c.is_host and (force or c.status ~= "play") then
            c.status = (uid == a or uid == b) and "queue" or "away"
        end
    end
    clients_assign_colors()
end

function ev_match_label()
    local mode = GAME.room_mode
    if mode == "wso" then
        local w = wso_state()
        return "Winner stays on" .. ((w.champ and (w.streak or 0) > 0) and (" (champion streak " .. w.streak .. ")") or "")
    end
    local ev = GAME.ev
    if not ev or not ev.cur then return "" end
    if ev.kind == "tourney" then
        local k, n = 0, 0
        for i, m in ipairs(ev.matches) do
            if not m.void and not m.walkover then
                n = n + 1
                if i <= ev.cur then k = k + 1 end
            end
        end
        return "Tournament - " .. ev.round_label .. (n > 1 and (" match " .. k .. "/" .. n) or "")
    end
    return ROOM_MODE_LABEL[ev.kind] .. " - game " .. (ev_games_played(ev) + 1) .. "/" .. ev_games_total(ev)
end

-- Called from the galcon module once the two players are in the game.
function ev_on_game_start(uids)
    GAME.ev_game_label = nil
    if not is_event_mode() then return end
    GAME.ev_game_label = ev_match_label()
    local ev = GAME.ev
    if not ev or not ev.cur then return end
    local m = ev.matches[ev.cur]
    local a, b = uids[1], uids[2]
    if m and ((m.a == a and m.b == b) or (m.a == b and m.b == a)) then
        m.live = true
        ev.live = ev.cur
    end
end

-- Called from galcon_stop with the winner (nil = no result) and both uids.
function ev_on_result(winner, uids)
    if not is_event_mode() then return end
    local a, b = uids and uids[1], uids and uids[2]
    if GAME.room_mode == "wso" then
        if a and b then wso_on_result(winner, a, b) end
    else
        local ev = GAME.ev
        if ev and ev.live then
            local m = ev.matches[ev.live]
            m.live, ev.live = nil, nil
            if winner and (winner == m.a or winner == m.b) then
                m.winner = winner
                m.loser  = (winner == m.a) and m.b or m.a
                if ev.kind == "tourney" then ev.out[m.loser] = true end
                ev.beat[winner] = ev.beat[winner] or {}
                table.insert(ev.beat[winner], m.loser)
                if ev.wins then
                    ev.wins[winner] = (ev.wins[winner] or 0) + 1
                    ev.losses[m.loser] = (ev.losses[m.loser] or 0) + 1
                end
                if ev.kind == "tourney" then
                    ev_say("[TOURNAMENT] " .. ev_name(winner) .. " advances, " .. ev_name(m.loser) .. " is out.")
                end
            elseif not (ev.gone[m.a] or ev.gone[m.b]) then
                ev_say("Match not counted -- it will be replayed.")
            end
            ev_advance(ev)
        end
    end
    -- Players who typed /away during their own game step out now, before
    -- the next match is announced.
    for _, uid in ipairs({ a, b }) do
        local c = uid and GAME.clients[uid]
        if c and c.withdraw_after then
            c.withdraw_after = nil
            ev_withdraw(uid, c.name .. " stepped out.")
        end
    end
    local na, nb = ev_next_pair()
    if na and nb then
        local lbl = (GAME.room_mode == "wso") and "" or (" (" .. ev_match_label() .. ")")
        ev_say("Next: " .. ev_name(na) .. " vs " .. ev_name(nb) .. lbl .. ". Press START.")
    end
end

-- Player leaves the pool (typed /away, or left the room).
function ev_withdraw(uid, msg)
    local c = GAME.clients[uid]
    if c then c.rot = nil end
    if msg then ev_say(msg) end
    if GAME.room_mode == "wso" then
        wso_clean()
        return
    end
    local ev = GAME.ev
    if not ev or ev.done or not ev_index(ev.players, uid) then return end
    ev.gone[uid] = true
    if ev.live then
        local m = ev.matches[ev.live]
        if m and (m.a == uid or m.b == uid) then return end   -- the game's result settles it
    end
    ev_advance(ev)
end

function ev_on_join(uid)
    local c = GAME.clients[uid]
    if not c or c.is_host then return end
    c.status = "away"
    if GAME.room_mode == "wso" then
        c.rot = true
        ev_remember(uid)
        wso_clean()
        net_send(uid, "message", "Winner Stays On -- you're in the line. /away to sit out.")
    elseif ev_active() then
        net_send(uid, "message", ROOM_MODE_LABEL[GAME.room_mode] .. " in progress -- you can watch; /play joins the next one.")
    else
        c.rot = true
        ev_remember(uid)
        net_send(uid, "message", ROOM_MODE_LABEL[GAME.room_mode] .. " -- you're in. /away to sit out.")
    end
end

-- /play in an event mode.
function ev_on_play(uid)
    local c = GAME.clients[uid]
    if not c or c.is_host then return end
    if c.rot then
        net_send(uid, "message", "You're already in.")
        return
    end
    if is_bracket_mode() and ev_active() then
        net_send(uid, "message", ROOM_MODE_LABEL[GAME.room_mode] .. " in progress -- you'll be in the next one.")
        c.rot = true
        ev_remember(uid)
        return
    end
    c.rot = true
    ev_remember(uid)
    if GAME.room_mode == "wso" then
        wso_clean()
        local pos = ev_index(wso_state().line, uid) or 0
        ev_say(c.name .. " joined the line (#" .. pos .. ").")
    else
        ev_say(c.name .. " joined (" .. #pool_uids() .. " in).")
    end
    ev_apply_statuses()
end

-- /away in an event mode.
function ev_on_away(uid)
    local c = GAME.clients[uid]
    if not c or c.is_host then return end
    if c.status == "play" then
        c.withdraw_after = true
        net_send(uid, "message", "You'll step out after this game.")
        return
    end
    if not c.rot then
        c.status = "away"
        return
    end
    local in_event = is_bracket_mode() and ev_active() and ev_index(GAME.ev.players, uid)
    ev_withdraw(uid, c.name .. (in_event and " withdrew -- remaining matches forfeited." or " stepped out."))
    c.status = "away"
    ev_apply_statuses()
end

function ev_on_leave(uid)
    if not is_event_mode() then return end
    ev_withdraw(uid, nil)
    ev_apply_statuses()
end

function set_room_mode(mode, by)
    if not ROOM_MODE_LABEL[mode] then return end
    local old = GAME.room_mode or "standard"
    if mode == old then return end
    if ev_active() then
        ev_say("Finish or end the current " .. ROOM_MODE_LABEL[old] .. " before changing modes.")
        return
    end
    -- Carry everyone who's playing/queued/in a line into the new mode.
    for _, c in pairs(GAME.clients) do
        if not c.is_host and (c.status == "queue" or c.rot) then c.rot = true; ev_remember(c.uid) end
    end
    GAME.room_mode = mode
    GAME.wso = nil
    GAME.ev_last = nil
    if mode == "standard" then
        local kept = 0
        for _, uid in ipairs(GAME.client_order) do
            local c = GAME.clients[uid]
            if c and not c.is_host then
                if c.rot and kept < 2 then c.status = "queue"; kept = kept + 1 else c.status = "away" end
                c.rot = nil
            end
        end
        clients_assign_colors()
    else
        ev_apply_statuses()
    end
    ev_say("Room mode: " .. ROOM_MODE_LABEL[mode] .. " (set by " .. by .. "). " .. ROOM_MODE_HELP[mode])
    if is_bracket_mode() then ev_say(#pool_uids() .. " in -- /play to join, then START to begin.") end
end

-- START pressed in an event mode. Returns true when a match countdown should begin.
function ev_on_start(by)
    if GAME.room_mode == "wso" then
        local a, b = wso_pair()
        if not (a and b) then
            ev_say("Winner Stays On needs 2 players in the line -- /play to join.")
            return false
        end
        ev_apply_statuses()
        return true
    end
    if not ev_active() then
        local ok, err = ev_start()
        if not ok then ev_say(err); return false end
    end
    if not ev_next_pair() then return false end
    ev_apply_statuses()
    local a, b = ev_next_pair()
    ev_say("Up now: " .. ev_name(a) .. " vs " .. ev_name(b) .. " (" .. ev_match_label() .. ")")
    return true
end

-- ── Lobby / settings HTML ───────────────────────────────────────────────
local EV_TXT = "font='font-gui2:13' color='#cccccc'"
local EV_HEAD = "font='font-outline:14' color='#44ccff'"
local EV_DIM = "font='font-gui2:12' color='#888888'"

function ev_line(text, attrs)
    return "<tr><td><div " .. (attrs or EV_TXT) .. ">" .. text .. "</div>"
end

function ev_bracket_html(ev)
    local h = ev_line(ev.round_label .. (ev.round > 1 and (" (round " .. ev.round .. ")") or ""), EV_HEAD)
    for i, m in ipairs(ev.matches) do
        local res
        if m.void then res = "void"
        elseif m.walkover then res = ev_name(m.winner) .. " (walkover)"
        elseif m.winner then res = ev_name(m.winner) .. " won"
        elseif m.live then res = "LIVE"
        elseif i == ev.cur then res = "next"
        else res = "" end
        h = h .. ev_line(ev_name(m.a) .. " vs " .. ev_name(m.b) .. (res ~= "" and ("  --  " .. res) or ""))
    end
    if ev.bye then h = h .. ev_line("Bye: " .. ev_name(ev.bye), EV_DIM) end
    return h
end

function ev_standings_html(ev)
    local h = ev_line(ROOM_MODE_LABEL[ev.kind] .. " -- game " .. math.min(ev_games_played(ev) + (ev.done and 0 or 1), ev_games_total(ev))
        .. " of " .. ev_games_total(ev), EV_HEAD)
    for i, uid in ipairs(rr_standings(ev)) do
        h = h .. ev_line(i .. ". " .. ev_name(uid) .. "   " .. (ev.wins[uid] or 0) .. "-" .. (ev.losses[uid] or 0)
            .. (ev.gone[uid] and "  (left)" or ""))
    end
    if ev.dropped and ev.dropped > 0 then
        h = h .. ev_line(ev.dropped .. " game(s) dropped -- player left", EV_DIM)
    end
    return h
end

function ev_player_tag(uid)
    if GAME.room_mode == "wso" then
        local k = ev_index(wso_state().line, uid)
        return k and ("[line #" .. k .. "]") or "[in]"
    end
    local ev = GAME.ev
    if ev and not ev.done then
        if not ev_index(ev.players, uid) then return "[next event]" end
        if ev.out[uid] then return "[out]" end
        if ev.bye == uid then return "[bye]" end
    end
    return "[in]"
end

function build_event_lobby_html(client)
    local mode = GAME.room_mode
    local a, b = ev_next_pair()
    local h = "<tr><td align=center><div " .. EV_HEAD .. ">Mode: " .. ROOM_MODE_LABEL[mode] .. "</div>"

    local start_label = nil
    if mode == "wso" then
        if a and b then start_label = "START: " .. ev_name(a) .. " vs " .. ev_name(b) end
    elseif ev_active() then
        if a and b then start_label = "START NEXT MATCH" end
    elseif #pool_uids() >= 2 then
        start_label = "START " .. ROOM_MODE_LABEL[mode]:upper()
    end
    if start_label then
        h = h .. "<tr><td><input type='button' value='" .. start_label .. "' onclick='/start' icon='icon-play'/>"
    end
    if not (client.is_host == true) then
        local in_cls = client.rot and "ibutton2" or "ibutton1"
        local out_cls = client.rot and "ibutton1" or "ibutton2"
        h = h .. "<tr><td><input type='button' value='" .. (client.rot and "IN" or "JOIN") .. "' onclick='/play' icon='icon-play' class='" .. in_cls .. "'/>"
            .. "<tr><td><input type='button' value='SIT OUT' onclick='/away' icon='icon-away' class='" .. out_cls .. "'/>"
            .. "<tr><td><input type='button' value='GG' onclick='/gg' icon='icon-leave' class='ibutton1'/>"
    end
    h = h .. "<tr><td><p>&nbsp;</p>"

    -- Next match
    if a and b then
        h = h .. "<tr><td><h2>NEXT MATCH</h2>"
        local ca, cb = GAME.clients[a], GAME.clients[b]
        if ca then h = h .. make_player_row(ca, b) end
        if cb then h = h .. make_player_row(cb, a) end
        h = h .. "<tr><td><p>&nbsp;</p>"
    end

    -- Event detail
    if mode == "wso" then
        local w = wso_state()
        if w.champ then
            h = h .. ev_line("Champion: " .. ev_name(w.champ) .. ((w.streak or 0) > 0 and ("  (" .. w.streak .. " in a row)") or ""), EV_HEAD)
        end
        if #w.line > 0 then
            h = h .. ev_line("Line:", EV_HEAD)
            for i, uid in ipairs(w.line) do h = h .. ev_line(i .. ". " .. ev_name(uid)) end
        end
    else
        local ev = GAME.ev or GAME.ev_last
        if ev then
            if ev.kind == "tourney" then h = h .. ev_bracket_html(ev) else h = h .. ev_standings_html(ev) end
            if ev.done then
                local w = ev.champion and ev_name(ev.champion)
                if ev.champions then
                    local names = {}
                    for _, uid in ipairs(ev.champions) do names[#names + 1] = ev_name(uid) end
                    w = table.concat(names, " & ")
                end
                h = h .. ev_line("Finished -- winner: " .. (w or "none") .. ". START runs a new one.", EV_HEAD)
            end
        else
            h = h .. ev_line(#pool_uids() .. " in. Everyone who joins is included when START is pressed.", EV_DIM)
        end
    end
    if ev_active() or (mode == "wso" and wso_state().champ) then
        h = h .. "<tr><td><input type='button' value='" .. (mode == "wso" and "Reset Champion" or "End Event")
            .. "' onclick='/endevent' class='ibutton1'/>"
    end
    h = h .. "<tr><td><p>&nbsp;</p>"

    -- Everyone else
    local rows_in, rows_out = "", ""
    for _, uid in ipairs(GAME.client_order) do
        local c = GAME.clients[uid]
        if c and uid ~= a and uid ~= b then
            if c.rot and not c.is_host then
                rows_in = rows_in .. make_player_row(c, nil, ev_player_tag(uid))
            else
                rows_out = rows_out .. make_player_row(c)
            end
        end
    end
    if rows_in ~= "" then h = h .. "<tr><td><h2>IN</h2>" .. rows_in end
    if rows_out ~= "" then h = h .. "<tr><td><h2>WATCHING</h2>" .. rows_out end
    return h
end

function build_room_mode_settings_html()
    local function mbtn(mode)
        local on = (GAME.room_mode or "standard") == mode
        return "<td><input type='button' onclick='/toggle:mode:" .. mode .. "' value='" .. ROOM_MODE_BTN[mode]
            .. "' class='" .. (on and "ibutton2" or "ibutton1") .. "' width=150/>"
    end
    local h = "<tr><td align=center><table>"
        .. "<tr><td colspan=2><b>Room Mode:</b>"
        .. "<tr>" .. mbtn("standard") .. mbtn("wso")
        .. "<tr>" .. mbtn("tourney") .. mbtn("rr")
        .. "<tr>" .. mbtn("drr") .. "<td>"
        .. "<tr><td colspan=2><div font='font-gui2:12'><i>" .. ROOM_MODE_HELP[GAME.room_mode or "standard"] .. "</i></div>"
    if ev_active() then
        h = h .. "<tr><td colspan=2><div font='font-gui2:12' color='#ffcc44'>Event in progress -- end it in the Lobby to change modes.</div>"
    end
    return h .. "</table>"
end
-- ══ END ROOM MODES ═══════════════════════════════════════════════════════


function init()
    global("GAME"); GAME = {}
    g2.console = 0
    HOST_UID  = g2.uid
    HOST_NAME = g2.name
    GAME.host_window = "lobby"
    GAME.host_color  = 0x00ff88
    GAME.batch_mode  = false
    GAME.ranked          = false
    GAME.distance_change = false
    GAME.last_style      = "saandbuff"
    GAME.last_ver        = 7
    GAME.warmup_mode     = false
    GAME.start_countdown_seconds = 3
    -- Map style pool: which styles are active for non-ranked mode
    -- SaandBuff versions collectively count as ONE style slot (split equally among selected)
    GAME.map_styles = {
        stages   = true,
        classic  = false,
        philbuff = true,
        ["12p"]  = false,
        wonk     = false,
        sb       = {},   -- [1..13] true/false
    }
    for i = 1, 13 do GAME.map_styles.sb[i] = true end  -- all SaandBuff versions on by default
    GAME.game_mode   = "standard"  
    GAME.room_mode   = "standard"   -- standard / wso / tourney / rr / drr (see ROOM MODES)

    global("rec_clock");        rec_clock        = 0
    global("rec_frame");        rec_frame        = 0
    global("rec_pos_frame");    rec_pos_frame    = 0
    global("rec_save_timer");   rec_save_timer   = 0
    global("rec_chunk_index");  rec_chunk_index  = 1
    global("rec_log_events");   rec_log_events   = {}
    global("rec_log_pos");      rec_log_pos      = {}
    global("rec_log_summary");  rec_log_summary  = {}
    global("rec_prev_fleets");  rec_prev_fleets  = {}
    global("rec_prev_planets"); rec_prev_planets = {}
    global("rec_game_users");   rec_game_users   = nil
    global("rec_player1_n");    rec_player1_n    = nil
    global("rec_player2_n");    rec_player2_n    = nil
    global("labels");           labels           = nil

    engine_init()
    menu_init()
    clients_init()
    params_init()
    chat_init()
    lobby_init()
    galcon_init()
    register_init()
    GAME.engine:init()
end

function round(x) return math.floor(x + 0.5) end

function net_send(uid, mtype, mvalue)
    g2.net_send(uid, mtype, mvalue)
end

function int_to_hex(n)
    return string.format("%06x", n)
end

function build_tabs(client)
    local w = client.window or "lobby"
    local cl = {
        lobby    = (w=="lobby")     and "tab0" or "tab",
        settings = (w=="status" or w=="settings") and "tab0" or "tab",
        profile  = (w=="profile")  and "tab0" or "tab",
        ranks    = (w=="ranks")    and "tab0" or "tab",
        customize= (w=="customize") and "tab0" or "tab",
    }
    local status_icon = "icon-" .. (client.status or "queue")
    return "<table><tr>" ..
        "<td><input width='16%' type='button' disabled='true' pseudo='first' class='tab'/>" ..
        "<td><input width='16%' type='button' onclick='/lobby'    value='Lobby'    icon='icon-lobby'     class='" .. cl.lobby    .. "'/>" ..
        "<td><input width='16%' type='button' onclick='/status'   value='Settings' icon='" .. status_icon .. "' class='" .. cl.settings  .. "'/>" ..
        "<td><input width='16%' type='button' onclick='/profile'  value='Profile'  icon='icon-profile'   class='" .. cl.profile  .. "'/>" ..
        "<td><input width='16%' type='button' onclick='/ranks'    value='Ranks'    icon='icon-queue'     class='" .. cl.ranks    .. "'/>" ..
        "<td><input width='16%' type='button' onclick='/customize' value='Customize' icon='icon-galaxy' pseudo='last' class='" .. cl.customize .. "'/>" ..
    "</table>"
end

function build_customize_html(client)
    return "<table width=340>" ..
        "<tr><td align=center><div font='font-outline:22' color='#44ccff'>Customize</div>" ..
        "<tr><td><input type='button' onclick='/lobby' value='Back' " ..
            "icon='icon-resume' class='ibutton1'/>" ..
        "<tr><td><p>&nbsp;</p>" ..
        "<tr><td><input type='button' onclick='/colors' value='COLORS' " ..
            "icon='icon-galaxy' class='ibutton1'/>" ..
        "<tr><td><input type='button' onclick='/ships' value='SHIPS' " ..
            "icon='icon-galaxy' class='ibutton1'/>" ..
        "<tr><td><input type='button' onclick='/skins' value='SKINS' " ..
            "icon='icon-galaxy' class='ibutton1'/>" ..
        "<tr><td><p>&nbsp;</p>" ..
        "</table>"
end

-- Flat list of preset swatches, built once from APHID_COLORS, so the color
-- picker can be paginated like Ships instead of one long scrolling table.
local FLAT_COLORS = {}
for _, row in ipairs(APHID_COLORS) do
    for _, c in ipairs(row) do
        FLAT_COLORS[#FLAT_COLORS + 1] = c
    end
end

function build_colors_html(client, page)
    page = page or 1
    local per   = 15  -- 5 rows x 3
    local total = #FLAT_COLORS
    local pages = math.ceil(total / per)
    local from_i = (page - 1) * per + 1
    local to_i   = math.min(page * per, total)

    -- Everything below is pinned above the swatch grid on every page, so the
    -- Back button, Random button, and hex entry are always reachable without
    -- needing to scroll (fixes the "can't scroll back up" issue).
    local html =
        "<table width=340>" ..
        "<tr><td colspan=3 align=center><h2>Colors</h2>" ..
        "<tr><td colspan=3><input type='button' width=100 value='Back' onclick='/customize' class='ibutton1'/>" ..
        "<td colspan=1><input type='button' width=100 value='Random' onclick='/setcolor:random' class='ibutton1'/>" ..
        "<tr><td colspan=3><p>&nbsp;</p>" ..
        "<tr><td colspan=3><div font='font-outline:12' color='#aaaaaa'>" ..
            "Type a 6-character hex code (letters a-f, numbers 0-9, no # symbol) " ..
            "then tap Set -- e.g. ff8800 for orange." ..
        "</div>" ..
        "<tr><td colspan=2><input type='text' name='hexcolor' value=''/>" ..
        "<td><input type='button' width=100 value='Set' onclick='/setcolor:{$hexcolor}' class='ibutton1'/>" ..
        "<tr><td colspan=3><p>&nbsp;</p>" ..
        "<tr><td colspan=3 align=center><div font='font-outline:12' color='#44ccff'>Presets  " .. page .. "/" .. pages .. "</div>"

    for i = from_i, to_i do
        local c = FLAT_COLORS[i]
        if (i - from_i) % 3 == 0 then html = html .. "<tr>" end
        html = html .. "<td><input type='button' width=50 background='white:0x" .. c ..
            "' value=' ' onclick='/setcolor:" .. c .. "' class='ibutton1'/>"
    end

    html = html .. "<tr>"
    if page > 1 then
        html = html .. "<td colspan=2><input type='button' onclick='/colors:" .. (page - 1) ..
            "' value='Prev' class='ibutton1' width=150/>"
    end
    if page < pages then
        html = html .. "<td><input type='button' onclick='/colors:" .. (page + 1) ..
            "' value='Next' class='ibutton1' width=150/>"
    end
    return html .. "</table>"
end

function build_ships_html(client, page, filter)
    page = page or 1
    filter = filter or ""
    local uid     = client and client.uid or ""
    local current = player_custom_ships[uid] or ""

    -- Build the working list: either every ship name (paginated) or every
    -- ship name matching the search term (shown in full, no pagination).
    local list = {}
    if filter ~= "" then
        for _, s in ipairs(SHIP_NAMES) do
            if s:lower():find(filter, 1, true) then list[#list + 1] = s end
        end
    else
        list = SHIP_NAMES
    end

    local per    = 12
    local total  = #list
    local pages  = math.max(1, math.ceil(total / per))
    if page > pages then page = pages end
    local from_i = (page - 1) * per + 1
    local to_i   = math.min(page * per, total)

    local html =
        "<table width=340>" ..
        "<tr><td colspan=3 align=center><div font='font-outline:14' color='#44ccff'>Ships</div>" ..
        "<tr><td colspan=3><input type='button' onclick='/customize' value='Back' class='ibutton1'/>" ..
        "<tr><td colspan=3><p>&nbsp;</p>" ..
        "<tr><td colspan=2><input type='text' name='shipsearch' value='" .. filter .. "'/>" ..
        "<td><input type='button' width=90 value='Search' onclick='/shipsearch' class='ibutton1'/>"
    if filter ~= "" then
        html = html .. "<tr><td colspan=3><input type='button' width=100 value='Clear Search' onclick='/shipsearch:clear' class='ibutton1'/>"
    end
    html = html .. "<tr><td colspan=3><p>&nbsp;</p>"

    if current ~= "" then
        html = html ..
            "<tr><td colspan=3 align=center>" ..
            "<img src='ship-" .. current .. "' width=72 height=72/>" ..
            "<div font='font-outline:12' color='#44ccff'>Active: ship-" .. current .. "</div>"
    end

    if total == 0 then
        html = html .. "<tr><td colspan=3 align=center><p>No ships match '" .. filter .. "'</p>"
    else
        html = html .. "<tr><td colspan=3 align=center><div font='font-outline:11' color='#666666'>" ..
            (filter ~= "" and (total .. " match" .. (total == 1 and "" or "es")) or ("Page " .. page .. "/" .. pages)) .. "</div>"
        html = html .. "<tr><td><p>&nbsp;</p>"
        for i = from_i, to_i do
            local s = list[i]
            if (i - from_i) % 3 == 0 then html = html .. "<tr>" end
            local active = (s == current)
            -- Mirrors the Skins tile exactly: label on its own row, then the
            -- image nested INSIDE the <input>...</input> button below it.
            -- The image was previously a sibling of the button, which is
            -- why taps never registered on it -- Skins works because the
            -- planet preview is nested inside the button the same way.
            html = html ..
                "<td width=113 align=center><table>" ..
                "<tr><td align=center><div font='font-outline:10' color='#aaaaaa'>ship-" .. s ..
                    (active and " (ON)" or "") .. "</div>" ..
                "<tr><td align=center><input type='button' width=75 height=75 onclick='/setship:" .. s ..
                "' class='" .. (active and "ibutton2" or "ibutton1") .. "'>" ..
                "<img src='ship-" .. s .. "' width=55 height=55/>" ..
                "</input>" ..
                "</table>"
        end
    end

    if filter == "" then
        html = html .. "<tr>"
        if page > 1 then
            html = html .. "<td colspan=2><input type='button' onclick='/ships:" .. (page-1) ..
                "' value='Prev' class='ibutton1' width=150/>"
        end
        if page < pages then
            html = html .. "<td><input type='button' onclick='/ships:" .. (page+1) ..
                "' value='Next' class='ibutton1' width=150/>"
        end
    end
    return html .. "</table>"
end

function build_skins_html(client, page, filter)
    page = page or 1
    filter = filter or ""
    local uid     = client and client.uid or ""
    local current = player_custom_skins[uid] or "normal"

    local list = {}
    if filter ~= "" then
        for _, s in ipairs(SKIN_NAMES) do
            local label = (SKIN_LABELS[s] or s):lower()
            if s:lower():find(filter, 1, true) or label:find(filter, 1, true) then
                list[#list + 1] = s
            end
        end
    else
        list = SKIN_NAMES
    end

    local per    = 9
    local total  = #list
    local pages  = math.max(1, math.ceil(total / per))
    if page > pages then page = pages end
    local from_i = (page - 1) * per + 1
    local to_i   = math.min(page * per, total)

    local html =
        "<table width=340>" ..
        "<tr><td colspan=3 align=center><div font='font-outline:18' color='#44ccff'>Skins</div>" ..
        "<tr><td colspan=3><input type='button' onclick='/customize' value='Back' class='ibutton1'/>" ..
        "<tr><td colspan=3><p>&nbsp;</p>" ..
        "<tr><td colspan=2><input type='text' name='skinsearch' value='" .. filter .. "'/>" ..
        "<td><input type='button' width=90 value='Search' onclick='/skinsearch' class='ibutton1'/>"
    if filter ~= "" then
        html = html .. "<tr><td colspan=3><input type='button' width=100 value='Clear Search' onclick='/skinsearch:clear' class='ibutton1'/>"
    end
    html = html .. "<tr><td colspan=3><p>&nbsp;</p>" ..
        "<tr><td colspan=3 align=center><div font='font-outline:12' color='#44ccff'>Active: " .. (SKIN_LABELS[current] or current) .. "</div>" ..
        "<tr><td colspan=3><p>&nbsp;</p>"

    if total == 0 then
        html = html .. "<tr><td colspan=3 align=center><p>No skins match '" .. filter .. "'</p>"
    else
        html = html .. "<tr><td colspan=3 align=center><div font='font-outline:11' color='#666666'>" ..
            (filter ~= "" and (total .. " match" .. (total == 1 and "" or "es")) or ("Page " .. page .. "/" .. pages)) .. "</div>"
        html = html .. "<tr><td><p>&nbsp;</p>"
        for i = from_i, to_i do
            local s = list[i]
            if (i - from_i) % 3 == 0 then html = html .. "<tr>" end
            local active = (s == current)
            local style_json = json.encode(SKIN_STYLES[s] or {})
            -- <planet data=...> is the widget Aphid uses for live skin
            -- previews (see SaandCon's wardrobe/settings screens) -- it
            -- renders the actual texture instead of a static image file.
            html = html ..
                "<td width=113 align=center><table>" ..
                "<tr><td align=center><div font='font-outline:10' color='#aaaaaa'>" ..
                    (SKIN_LABELS[s] or s) .. (active and " (ON)" or "") .. "</div>" ..
                "<tr><td align=center><input type='button' width=75 height=75 onclick='/setskin:" .. s ..
                "' class='" .. (active and "ibutton2" or "ibutton1") .. "'>" ..
                "<planet data='" .. style_json .. "' color='#aaaaaa' team='#aaaaaa' width=55 height=55/>" ..
                "</input>" ..
                "</table>"
        end
    end

    if filter == "" then
        html = html .. "<tr>"
        if page > 1 then
            html = html .. "<td colspan=2><input type='button' onclick='/skins:" .. (page-1) ..
                "' value='Prev' class='ibutton1' width=150/>"
        end
        if page < pages then
            html = html .. "<td><input type='button' onclick='/skins:" .. (page+1) ..
                "' value='Next' class='ibutton1' width=150/>"
        end
    end
    return html .. "</table>"
end

function hex_darken(col)
    local r = math.floor(math.floor(col / 0x10000) * 0.5)
    local g = math.floor(math.floor((col % 0x10000) / 0x100) * 0.5)
    local b = math.floor((col % 0x100) * 0.5)
    return string.format("%02x%02x%02x", r, g, b)
end

function make_player_row(c, opponent_uid, tag_override)
    local s   = STATS[c.uid]
    local elo_str = s and (" · " .. s.elo .. " ELO") or ""
    local sfx = s and streak_emoji(s.streak) or ""
    local h2h_str = ""
    if opponent_uid and s and s.h2h[opponent_uid] then
        local h  = s.h2h[opponent_uid]
        local ht = h.w + h.l
        local hp = ht>0 and math.floor(h.w/ht*100) or 0
        h2h_str = "  vs opp: " .. h.w .. "W-" .. h.l .. "L (" .. hp .. "%)"
    end
    local info = elo_str .. sfx .. h2h_str

    if c.status == "queue" and not c.is_host then
        local col = "#" .. int_to_hex(c.color)
        local bg  = "#" .. hex_darken(c.color)
        return "<tr><td><table width=330 background='white:" .. bg .. "'><tr>" ..
               "<td width=6><img src='blank' width=6 height=5>" ..
               "<td align=left clip=1><div font='font-outline:18' color='" .. col .. "'>" ..
               c.name .. sfx .. " [play]</div>" ..
               "<div font='font-outline:11' color='#aaaaaa'>" .. elo_str:gsub("^ · ","") .. h2h_str .. "</div>" ..
               "</table>"
    else
        local tag = tag_override or (c.is_host and "[host]" or "[away]")
        return "<tr><td><table width=330 background='white:#2b2b2b'><tr>" ..
               "<td width=6><img src='blank' width=6 height=5>" ..
               "<td align=left clip=1><div font='font-outline:18' color='#777777'>" ..
               c.name .. " " .. tag .. "</div>" ..
               (info ~= "" and "<div font='font-outline:11' color='#555555'>" .. info:gsub("^ · ","") .. "</div>" or "") ..
               "</table>"
    end
end

function build_lobby_html(client)
    if is_event_mode() then
        local batch_class = GAME.batch_mode and "ibutton2" or "ibutton1"
        local batch_label = GAME.batch_mode and "Batch REC: ON" or "Batch REC: OFF"
        local batch_html = "<tr><td><p>&nbsp;</p><tr><td><input type='button' onclick='/batch' value='"
            .. batch_label .. "' class='" .. batch_class .. "'/>"
        if GAME.batch_mode then
            batch_html = batch_html .. "<tr><td><input type='button' onclick='/endbatch' value='End Batch + Upload' class='ibutton1'/>"
        end
        return "<tr><td align=center><h2>1v1 Replays</h2>" .. build_event_lobby_html(client) .. batch_html
    end
    local queued    = count_queued()
    local is_queued = (client.status == "queue") and not (client.is_host == true)
    local is_away   = (client.status == "away")  or  (client.is_host == true)

    local start_btn = ""
    if queued >= 1 then
        start_btn = "<tr><td><input type='button' value='START' onclick='/start' icon='icon-play'/>"
    end

    local play_class = is_queued and "ibutton2" or "ibutton1"
    local away_class = is_away   and "ibutton2" or "ibutton1"

    local rows = "<tr><td><h2>PLAYERS</h2>"
    for _, uid in ipairs(GAME.client_order) do
        local c = GAME.clients[uid]
        if c and c.status == "queue" and not c.is_host then
            rows = rows .. make_player_row(c)
        end
    end
    for _, uid in ipairs(GAME.client_order) do
        local c = GAME.clients[uid]
        if c and (c.status == "away" or c.is_host) then
            rows = rows .. make_player_row(c)
        end
    end

    local action_btns = ""
    if not (client.is_host == true) then
        action_btns = [[
        <tr><td><input type='button' value='PLAY'  onclick='/play'  icon='icon-play'  class=']] .. play_class .. [['/>
        <tr><td><input type='button' value='AWAY'  onclick='/away'  icon='icon-away'  class=']] .. away_class .. [['/>
        <tr><td><input type='button' value='GG'    onclick='/gg'    icon='icon-leave' class='ibutton1'/>]]
    end

    local batch_class = GAME.batch_mode and "ibutton2" or "ibutton1"
    local batch_label = GAME.batch_mode and "Batch REC: ON" or "Batch REC: OFF"
    local batch_toggle_btn = "<tr><td><input type='button' onclick='/batch' value='"
        .. batch_label .. "' class='" .. batch_class .. "'/>"

    local end_batch_btn = ""
    if GAME.batch_mode then
        end_batch_btn = "<tr><td><input type='button' onclick='/endbatch' value='End Batch + Upload' class='ibutton1'/>"
    end

    return [[
        <tr><td align=center><h2>1v1 Replays</h2>
        <tr><td align=center><p>]] .. tostring(queued) .. [[ ready</p>
        ]] .. start_btn .. [[
        ]] .. action_btns .. [[
        <tr><td><p>&nbsp;</p>
        ]] .. rows .. [[
        <tr><td><p>&nbsp;</p>
    ]] .. batch_toggle_btn .. end_batch_btn
end

function build_status_html(client)
    local html = "<table width=340>"
    html = html .. "<tr><td><h2>Settings</h2>"
    html = html .. build_room_mode_settings_html() .. "<tr><td><p>&nbsp;</p>"

    -- ── Ranked mode: label + toggle button (clearer than a single ambiguous button) ──
    html = html .. "<tr><td align=center><table><tr>"
        .. "<td><div font='font-outline:14' color='#44ccff'>ElimV2 Rotation:</div>"
        .. "<td><input type='button' onclick='/toggle:ranked' value='" .. (GAME.ranked and "ON" or "OFF")
        .. "' class='" .. (GAME.ranked and "ibutton2" or "ibutton1") .. "' width=80/>"
        .. "</table>"

    -- ── Start delay: how long the countdown runs after /start is pressed ──
    -- Applies regardless of ranked mode, since it's a UX preference, not a map setting.
    html = html .. "<tr><td colspan=3><p>&nbsp;</p>"
        .. "<tr><td align=center><table><tr>"
        .. "<td><input type='button' width=50 value='-' onclick='/toggle:countdown_dec' class='ibutton1'/>"
        .. "<td><div font='font-outline:14' color='#44ccff'>Start Delay: " .. GAME.start_countdown_seconds .. "s</div>"
        .. "<td><input type='button' width=50 value='+' onclick='/toggle:countdown_inc' class='ibutton1'/>"
        .. "</table>"

    if GAME.ranked then
        -- Ranked: show rotation info, lock settings
        html = html
            .. "<tr><td><p>&nbsp;</p>"
            .. "<tr><td align=center><b>ElimV2 Map Rotation:</b>"
            .. "<tr><td><div font='font-gui2:13'>"
            .. "SaandBuff 50%&nbsp;&nbsp;Stages 16.7%&nbsp;&nbsp;Philbuff 16.7%&nbsp;&nbsp;12p 16.7%"
            .. "</div>"
            .. "<tr><td><p>&nbsp;</p>"
            .. "<tr><td align=center><i>Turn off ElimV2 rotation to change map settings</i>"
    else
        -- Non-ranked: show style selector + SB versions + distance change
        local ms = GAME.map_styles

        -- Each button gets its own <td> and rows wrap explicitly -- previously
        -- all buttons were crammed into one <td>, which overflowed the table
        -- width and left everything past the first button invisible.
        local function tbtn(cmd, lbl, on)
            return "<td><input type='button' onclick='/toggle:" .. cmd .. "' value='" .. lbl
                .. "' class='" .. (on and "ibutton2" or "ibutton1") .. "' width=100/>"
        end

        local all_sb_on = true
        for v = 1, 13 do if not ms.sb[v] then all_sb_on = false break end end

        html = html
            .. "<tr><td colspan=3><p>&nbsp;</p>"
            .. "<tr><td colspan=3><b>Map Styles:</b>"
            .. "<tr>" .. tbtn("stages",   "Stages",   ms.stages) .. tbtn("classic", "Classic", ms.classic) .. tbtn("philbuff", "Philbuff", ms.philbuff)
            .. "<tr>" .. tbtn("12p", "12 Planet", ms["12p"]) .. tbtn("wonk", "Wonk", ms.wonk) .. tbtn("saandbuff", "SaandBuff", all_sb_on)

        -- SaandBuff versions -- 3 columns, short "V1".."V13" labels so they
        -- fit comfortably and stay readable on a phone. The SaandBuff button
        -- above selects/deselects all of these at once.
        html = html
            .. "<tr><td colspan=3><p>&nbsp;</p>"
            .. "<tr><td colspan=3><b>SaandBuff Versions (share 1 slot equally):</b>"
        for v = 1, 13 do
            if (v - 1) % 3 == 0 then html = html .. "<tr>" end
            local on = ms.sb[v]
            html = html
                .. "<td><input type='button' onclick='/toggle:sb" .. v
                .. "' value='V" .. v
                .. "' class='" .. (on and "ibutton2" or "ibutton1") .. "' width=100/>"
        end

        -- Distance Change toggle
        html = html
            .. "<tr><td colspan=3><p>&nbsp;</p>"
            .. "<tr><td colspan=3 align=center>"
            .. "<input type='button' onclick='/toggle:distance' value='Distance Change: "
            .. (GAME.distance_change and "ON ✓" or "OFF")
            .. "' class='" .. (GAME.distance_change and "ibutton2" or "ibutton1") .. "' width=240/>"
            .. "<tr><td colspan=3><div font='font-gui2:12'><i>"
            .. "Within each cost tier, distance from home replaces the random roll: "
            .. "far from home = cheapest + highest prod, near home = priciest + lowest prod"
            .. "</i></div>"
    end

    html = html
        .. "<tr><td><p>&nbsp;</p>"
        -- Status buttons
        .. "<tr><td align=center><input type='button' class='ibutton"
        .. (client.status == "play"  and "2" or "1")
        .. "' value='Play'  onclick='/play' icon='icon-play'/>"
        .. "<tr><td align=center><input type='button' class='ibutton"
        .. (client.status == "queue" and "2" or "1")
        .. "' value='Queue' onclick='/play' icon='icon-queue'/>"
        .. "<tr><td align=center><input type='button' class='ibutton"
        .. (client.status == "away"  and "2" or "1")
        .. "' value='Away'  onclick='/away' icon='icon-away'/>"
        .. "<tr><td align=center><input type='button' class='ibutton1'"
        .. " value='Back' onclick='*lobby	' icon='icon-restart'/>"
        .. "</table>"
    return html
end


function build_profile_html(client)
    local uid    = client.profile_uid or client.uid
    local pc     = GAME.clients[uid]
    local pname  = pc and pc.name  or (STATS[uid] and STATS[uid].name  or "?")
    local pcol_i = pc and pc.color or 0x555555
    local s      = ensure_stats(uid, pname, int_to_hex(pcol_i))
    local col    = "#" .. s.color
    local tot    = s.wins + s.losses
    local wpct   = tot > 0 and math.floor(s.wins/tot*100) or 0
    local strk   = s.streak
    local strk_txt = strk > 0 and ("W"..strk..streak_emoji(strk)) or
                     strk < 0 and ("L"..math.abs(strk)..streak_emoji(strk)) or "--"

    local nav = ""
    if client.profile_uid and client.profile_uid ~= client.uid then
        nav = "<input type='button' onclick='/profile' value='&lt; Back' class='ibutton1'/>  "
    end
    nav = nav .. "<input type='button' onclick='/customize' value='Customize' icon='icon-galaxy' class='ibutton1'/>"

    local h2h_html = ""
    for ouid, h in pairs(s.h2h) do
        local oname  = STATS[ouid] and STATS[ouid].name or "?"
        local htotal = h.w + h.l
        local hpct   = htotal > 0 and math.floor(h.w/htotal*100) or 0
        local win_col = hpct >= 50 and "#44ff88" or "#ff6655"
        h2h_html = h2h_html ..
            "<tr>" ..
            "<td><input type='button' onclick='/profile:" .. ouid ..
            "' value='" .. oname .. "' class='ibutton1' width=130/>" ..
            "<td><div color='" .. win_col .. "'>" ..
                h.w .. "W-" .. h.l .. "L " .. hpct .. "%</div>"
    end
    if h2h_html == "" then h2h_html = "<tr><td colspan=2><p>No games yet</p>" end

    local ship_html = ""
    local cur_ship = player_custom_ships[uid]
    if cur_ship and cur_ship ~= "" then
        ship_html = "<div font='font-outline:13' color='#44ccff'>Ship: ship-"..cur_ship.."</div>"
    end


    -- Browsable list of everyone with stats, so any profile is reachable
    -- from here -- not just people you've personally played (H2H).
    local browse_html = ""
    local sorted = {}
    for ouid, os_ in pairs(STATS) do table.insert(sorted, {uid=ouid, s=os_}) end
    table.sort(sorted, function(a,b) return a.s.elo > b.s.elo end)
    for _, entry in ipairs(sorted) do
        if entry.uid ~= uid then
            browse_html = browse_html ..
                "<tr><td><input type='button' onclick='/profile:" .. entry.uid ..
                "' value='" .. entry.s.name .. "' class='ibutton1' width=200/>" ..
                "<td><div color='#888888'>" .. entry.s.elo .. " ELO</div>"
        end
    end
    if browse_html == "" then browse_html = "<tr><td colspan=2><p>Nobody else has played yet</p>" end

    return "<table width=340>" ..
        "<tr><td>" .. nav ..
        "<tr><td><p>&nbsp;</p>" ..
        "<tr><td align=center>" .. ship_html ..
            "<div font='font-outline:28' color='" .. col .. "'>" .. s.name .. "</div>" ..
        "<tr><td align=center><div font='font-outline:18' color='#44ccff'>ELO: "..s.elo.."</div>" ..
        "<tr><td align=center><p>" ..
            s.wins.."W -- "..s.losses.."L -- "..wpct.."% -- Streak: "..strk_txt ..
        "</p>" ..
        "<tr><td><p>&nbsp;</p>" ..
        "<tr><td><b>H2H Record</b>" ..
        "<tr><td><table width=300>" ..
            "<tr><td><b>vs Player</b><td><b>Record</b>" ..
            h2h_html ..
        "</table>" ..
        "<tr><td><p>&nbsp;</p>" ..
        "<tr><td><b>Browse Players</b>" ..
        "<tr><td><table width=300>" ..
            browse_html ..
        "</table>" ..
        "</table>"
end

function build_ranks_html()
    local sorted={}
    for uid,s in pairs(STATS) do table.insert(sorted,{uid=uid,s=s}) end
    table.sort(sorted,function(a,b) return a.s.elo>b.s.elo end)
    local out="<table width=340><tr><td><h2>Rankings</h2><tr><td><div color='#44ccff'>Every game counts -- /elo name in chat</div><tr><td><p>&nbsp;</p>"
    if #sorted==0 then return out.."<tr><td><p>No games yet.</p></table>" end
    local maxE,minE=1400,1000
    for _,e in ipairs(sorted) do
        if e.s.elo>maxE then maxE=e.s.elo end
        if e.s.elo<minE then minE=e.s.elo end
    end
    local rng=math.max(1,maxE-minE)
    for rank,entry in ipairs(sorted) do
        local s=entry.s; local col="#"..(s.color or "aaaaaa")
        local tot=s.wins+s.losses; local wpct=tot>0 and math.floor(s.wins/tot*100) or 0
        local bw=math.max(4,math.floor((s.elo-minE)/rng*260+20))
        local bar="<table background='white:"..(s.color or "00ff88").."' width="..bw.." height=8><tr><td></table>"
        local trend=""
        local hist=s.history or {}
        for i=math.max(1,#hist-4),#hist do
            local h=hist[i]; trend=trend.."<div color='"..(h.won and "#00ff88" or "#ff4455").."'>"..(h.won and "W" or "L").."</div> "
        end
        out=out.."<tr><td>" ..
            "<table width=330 background='white:#0d1c2c'><tr>" ..
            "<td width=18><div color='#445566'>"..rank..".</div>" ..
            "<td colspan=2><input type='button' onclick='/profile:"..entry.uid..
                "' value='"..s.name..streak_emoji(s.streak).."' class='ibutton1' width=190/>" ..
            "<td align=right><div color='#44ccff' font='font-outline:16'>"..s.elo.."</div></table>" ..
            "<table width=330><tr><td>"..bar .."<td width=80><div color='#888888' font='font-outline:11'>"..s.wins.."W-"..s.losses.."L "..wpct.."%</div></table>" ..
            "<table width=330><tr><td><div color='#445566' font='font-outline:11'>Recent: </div>"..trend.."</table><tr><td><p>&nbsp;</p>"
    end
    return out.."</table>"
end

function build_help_html()
    return [[
        <tr><td align=center><h2>Help</h2>
        <tr><td><table class='box' width=240>
        <tr><td>/play</td><td>Join queue</td>
        <tr><td>/away</td><td>Leave queue</td>
        <tr><td>/start</td><td>Force start</td>
        <tr><td>/surrender</td><td>Forfeit game</td>
        <tr><td>/abort</td><td>End game</td>
        <tr><td>/gg</td><td>Good game</td>
        <tr><td>/who</td><td>List players</td>
        </table>
        <tr><td><p>&nbsp;</p>
        <tr><td align=center><input type='button' class='ibutton1' value='Back' onclick='*lobby	' icon='icon-restart'/>
    ]]
end

function build_ingame_html(client)
    return [[
        <tr><td align=center><input type='button' class='ibutton1' value='Surrender'   onclick='/surrender'  icon='icon-surrender'/>
        <tr><td align=center><input type='button' class='ibutton1' value='GG'           onclick='/gg'        icon='icon-leave'/>
    ]]
end

function update_host_html()
    local fake_c = {
        status = "away", window = GAME.host_window or "lobby",
        is_host = true, name = HOST_NAME, color = GAME.host_color or 0x00ff88,
        uid = HOST_UID, profile_uid = GAME.host_profile_uid,
    }
    local win = GAME.host_window or "lobby"
    local body
    if win == "status" then
        body = build_status_html(fake_c)
    elseif win == "help" then
        body = build_help_html()
    elseif win == "profile" then
        body = build_profile_html(fake_c)
    elseif win == "ranks" then
        body = build_ranks_html()
    elseif win == "customize" then
        body = build_customize_html(fake_c)
    elseif win == "colors" then
        body = build_colors_html(fake_c, GAME.host_colors_page or 1)
    elseif win == "ships" then
        body = build_ships_html(fake_c, GAME.host_ships_page or 1, GAME.host_ships_filter or "")
    elseif win == "skins" then
        body = build_skins_html(fake_c, GAME.host_skins_page or 1, GAME.host_skins_filter or "")
    else
        body = build_lobby_html(fake_c)
    end
    g2.html = "<table width=340>" .. body .. "</table>"
    if g2.state ~= "play" then
        g2.tabs = build_tabs(fake_c)
    end
end

function send_html(uid)
    local c = GAME.clients[uid]
    if not c then return end
    local body
    local win = c.window or "lobby"
    if g2.state == "play" then
        if c.status == "play" then
            net_send(uid, "html", "<table width=340>" .. build_ingame_html(c) .. "</table>")
            net_send(uid, "tabs", "")
            return
        else
            return
        end
    elseif win == "status" then
        body = build_status_html(c)
    elseif win == "help" then
        body = build_help_html()
    elseif win == "profile" then
        body = build_profile_html(c)
    elseif win == "ranks" then
        body = build_ranks_html()
    elseif win == "customize" then
        body = build_customize_html(c)
    elseif win == "colors" then
        local pg = c.colors_page or 1
        body = build_colors_html(c, pg)
    elseif win == "ships" then
        local pg = c.ships_page or 1
        body = build_ships_html(c, pg, c.ships_filter or "")
    elseif win == "skins" then
        local pg = c.skins_page or 1
        body = build_skins_html(c, pg, c.skins_filter or "")
    else
        body = build_lobby_html(c)
    end
    net_send(uid, "html", "<table width=340>" .. body .. "</table>")
    if g2.state == "play" and c.status == "play" then
        net_send(uid, "tabs", "")
    else
        net_send(uid, "tabs", build_tabs(c))
    end
end

function broadcast_html()
    for uid, _ in pairs(GAME.clients) do
        send_html(uid)
    end
    if g2.state ~= "play" then
        if GAME.host_window and GAME.host_window ~= "lobby" then
            update_host_html()
        else
            g2.html = "<table width=340>" .. build_lobby_html({
                status="away", window="lobby", is_host=true, name=HOST_NAME
            }) .. "</table>"
            g2.tabs = ""
        end
    end
end

function engine_init()
    GAME.engine  = {}
    GAME.modules = {}
    local obj    = GAME.engine

    function obj:next(module)
        GAME.module = module
        GAME.module:init()
    end
    function obj:init() self:next(GAME.modules.menu) end
    function obj:loop(t)
        GAME.module:loop(t)
        GAME.modules.register:loop(t)
    end
    function obj:event(e)
        GAME.modules.clients:event(e)
        GAME.modules.params:event(e)
        GAME.modules.chat:event(e)
        GAME.module:event(e)
    end
end

function menu_init()
    GAME.modules.menu = {}
    local obj = GAME.modules.menu
    function obj:init()
        -- A corrupted/truncated g2.data (Steam Cloud mid-resync, a stale
        -- partial write from a previous crash, etc.) used to be able to
        -- take the whole mod down right here: json.decode raises a Lua
        -- error on malformed input rather than returning nil, and nothing
        -- caught it before this point -- so the type() check below never
        -- even ran. pcall contains that exactly the way apply_result and
        -- galcon_stop already do elsewhere in this file.
        local ok, decoded = pcall(json.decode, g2.data)
        GAME.data = ok and decoded or nil
        if type(GAME.data) ~= "table" then
            if not ok then
                print("[warn] g2.data was corrupt/unreadable on load -- resetting to defaults: " .. tostring(decoded))
            end
            GAME.data = {}
        end
        if next(STATS) == nil then
            local n = stats_load(GAME.data.stats)
            if n > 0 then print("[stats] loaded " .. n .. " players from saved data") end
        end
        g2.form      = g2.form or {}
        g2.form.port = GAME.data.port or DEFAULT_PORT
        g2.html = [[
            <table>
            <tr><td colspan=2><h1>1v1 Replay Room</h1>
            <tr><td><p>Port:</p>
            <td><input type='text' name='port' value=']] .. DEFAULT_PORT .. [[' />
            <tr><td><p>&nbsp;</p>
            <tr><td colspan=2>
                <input type='button' value='Start Server' onclick='host' />
            </table>
        ]]
        g2.state = "menu"
    end
    function obj:loop(t) end
    function obj:event(e)
        if e.type == "onclick" and e.value == "host" then
            GAME.data.port = g2.form.port or DEFAULT_PORT
            g2data_write(GAME.data)
            g2.net_host(GAME.data.port)
            GAME.engine:next(GAME.modules.lobby)
        end
    end
end

function clients_assign_colors()
    for _, c in pairs(GAME.clients) do c.color = 0x555555 end
    local slot = 1
    for _, uid in ipairs(GAME.client_order) do
        local c = GAME.clients[uid]
        if c and c.status == "queue" and not c.is_host then
            if player_custom_colors[uid] then
                                                    local hex = player_custom_colors[uid]
                local r = tonumber(hex:sub(1,2), 16) or 0
                local g = tonumber(hex:sub(3,4), 16) or 0
                local b = tonumber(hex:sub(5,6), 16) or 0
                c.color = r * 0x10000 + g * 0x100 + b
            elseif slot <= #PLAYER_COLORS then
                c.color = PLAYER_COLORS[slot]
            end
            slot = slot + 1
        end
    end
end

function count_queued()
    local n = 0
    for _, c in pairs(GAME.clients) do
        if c.status == "queue" then n = n + 1 end
    end
    return n
end

function clients_init()
GAME.modules.clients = {}
GAME.clients         = {}
GAME.client_order    = {}
local obj            = GAME.modules.clients
function obj:event(e)
if e.type == "net:join" then
local is_host = (e.uid == HOST_UID)
GAME.clients[e.uid] = {
uid     = e.uid,
name    = e.name,
color   = 0x555555,
status  = is_host and "away" or "queue",
window  = "lobby",
is_host = is_host,
}
GAME.client_order[#GAME.client_order + 1] = e.uid
if is_event_mode() then ev_on_join(e.uid); ev_apply_statuses() end
clients_assign_colors()
ensure_stats(e.uid, e.name, int_to_hex(GAME.clients[e.uid].color or 0x555555))
net_send("", "message", e.name .. " joined")
net_send("", "sfx",    "join")
if is_host then
net_send(e.uid, "message", "Host account -- status is permanently Away.")
else
net_send(e.uid, "message", "Welcome to 1v1 Replays! /play to queue, /away to step back.")
end
broadcast_html()
end
if e.type == "net:leave" then
net_send("", "message", e.name .. " left")
net_send("", "sfx",    "leave")
GAME.clients[e.uid] = nil
for i, uid in ipairs(GAME.client_order) do
if uid == e.uid then table.remove(GAME.client_order, i); break end
end
if is_event_mode() then
local ok, err = pcall(ev_on_leave, e.uid)
if not ok then print("[ERROR] ev_on_leave: " .. tostring(err)) end
end
clients_assign_colors()
broadcast_html()
end
local function switch_window(win)
if e.uid == HOST_UID then
GAME.host_window = win
update_host_html()
elseif GAME.clients[e.uid] then
GAME.clients[e.uid].window = win
send_html(e.uid)
end
end
if e.type == "net:message" then
if e.value == "/lobby"     then switch_window("lobby");     return end
if e.value == "/status"    then switch_window("status");    return end
if e.value:sub(1,8) == "/profile" then
local target = nil
if #e.value > 9 and e.value:sub(9,9) == ":" then
target = e.value:sub(10)
end
local c2 = GAME.clients[e.uid]
if c2 then c2.window="profile"; c2.profile_uid=target end
if e.uid == HOST_UID then
GAME.host_window="profile"; GAME.host_profile_uid=target
update_host_html()
else send_html(e.uid) end
return
end
if e.value == "/ranks"     then switch_window("ranks");     return end
if e.value == "/customize" then switch_window("customize"); return end
if e.value:sub(1,7) == "/colors" then
local pg = tonumber(e.value:sub(9)) or 1
local c2 = GAME.clients[e.uid]
if c2 then c2.window="colors"; c2.colors_page=pg end
if e.uid == HOST_UID then
GAME.host_window="colors"; GAME.host_colors_page=pg
update_host_html()
else send_html(e.uid) end
return
end
if e.value:sub(1,6) == "/ships" then
local pg = tonumber(e.value:sub(8)) or 1
local c2 = GAME.clients[e.uid]
if c2 then c2.window="ships"; c2.ships_page=pg end
if e.uid == HOST_UID then
GAME.host_window="ships"; GAME.host_ships_page=pg
update_host_html()
else send_html(e.uid) end
return
end
if e.value:sub(1,8) == "/setship" then
local ship = e.value:sub(10)
local valid = false
for _,s in ipairs(SHIP_NAMES) do if s==ship then valid=true; break end end
if valid then
player_custom_ships[e.uid] = ship
net_send(e.uid, "message", "Ship set to: ship-" .. ship)
local c2 = GAME.clients[e.uid]
if c2 then c2.window="ships" end
send_html(e.uid)
end
return
end
if e.value == "/shipsearch" then
local q = (g2.form.shipsearch or ""):lower():gsub("^%s+",""):gsub("%s+$","")
local c2 = GAME.clients[e.uid]
if c2 then c2.window="ships"; c2.ships_page=1; c2.ships_filter=q end
if e.uid == HOST_UID then
GAME.host_window="ships"; GAME.host_ships_page=1; GAME.host_ships_filter=q
update_host_html()
else send_html(e.uid) end
return
end
if e.value == "/shipsearch:clear" then
local c2 = GAME.clients[e.uid]
if c2 then c2.ships_filter=nil; c2.ships_page=1 end
if e.uid == HOST_UID then
GAME.host_ships_filter=nil; GAME.host_ships_page=1
update_host_html()
else send_html(e.uid) end
return
end
if e.value:sub(1,6) == "/skins" then
local pg = tonumber(e.value:sub(8)) or 1
local c2 = GAME.clients[e.uid]
if c2 then c2.window="skins"; c2.skins_page=pg end
if e.uid == HOST_UID then
GAME.host_window="skins"; GAME.host_skins_page=pg
update_host_html()
else send_html(e.uid) end
return
end
if e.value:sub(1,8) == "/setskin" then
local skin = e.value:sub(10)
local valid = false
for _,s in ipairs(SKIN_NAMES) do if s==skin then valid=true; break end end
if valid then
player_custom_skins[e.uid] = skin
net_send(e.uid, "message", "Skin set to: " .. (SKIN_LABELS[skin] or skin))
local c2 = GAME.clients[e.uid]
if c2 then c2.window="skins" end
if e.uid == HOST_UID then update_host_html() else send_html(e.uid) end
end
return
end
if e.value == "/skinsearch" then
local q = (g2.form.skinsearch or ""):lower():gsub("^%s+",""):gsub("%s+$","")
local c2 = GAME.clients[e.uid]
if c2 then c2.window="skins"; c2.skins_page=1; c2.skins_filter=q end
if e.uid == HOST_UID then
GAME.host_window="skins"; GAME.host_skins_page=1; GAME.host_skins_filter=q
update_host_html()
else send_html(e.uid) end
return
end
if e.value == "/skinsearch:clear" then
local c2 = GAME.clients[e.uid]
if c2 then c2.skins_filter=nil; c2.skins_page=1 end
if e.uid == HOST_UID then
GAME.host_skins_filter=nil; GAME.host_skins_page=1
update_host_html()
else send_html(e.uid) end
return
end
if e.value == "/help"      then switch_window("help");      return end
if e.value == "/warmup" then
net_send(e.uid, "message", "There's no warm-up mode -- ELO counts for every game.")
return
end
end
if e.type == "net:message" then
local v = e.value
local lv = v:lower():gsub("^%s+","")
if lv:find("^/play") == 1 and is_event_mode() then
local c = GAME.clients[e.uid]
if c and c.is_host then
net_send(e.uid, "message", "Host account is permanently away.")
elseif c then
ev_on_play(e.uid)
broadcast_html()
end
elseif lv == "/away" and is_event_mode() then
if GAME.clients[e.uid] then
ev_on_away(e.uid)
broadcast_html()
end
elseif lv:find("^/play") == 1 then
local c = GAME.clients[e.uid]
if c and not c.is_host then
if c.status ~= "queue" and count_queued() >= 2 then
net_send(e.uid, "message", "Play is full (2/2) -- you'll stay Away until a slot opens.")
else
c.status = "queue"
clients_assign_colors()
net_send("", "message", e.name .. " is /play")
broadcast_html()
end
elseif c and c.is_host then
net_send(e.uid, "message", "Host account is permanently away.")
end
elseif lv == "/away" then
local c = GAME.clients[e.uid]
if c and not c.is_host then
c.status = "away"
clients_assign_colors()
net_send("", "message", e.name .. " is /away")
broadcast_html()
end
elseif lv == "/elo" or lv:find("^/elo%s") == 1 then
elo_command(e.uid, (v:gsub("^%s+",""):sub(5):gsub("^%s+",""):gsub("%s+$","")))
elseif lv == "/who" then
local msg = "Players: "
for _, c in pairs(GAME.clients) do
msg = msg .. c.name .. "(" .. c.status .. ") "
end
net_send(e.uid, "message", msg)
end
end
end
end

function params_set(k, v)
    GAME.params[k] = v
    net_send("", k, v)
end

function params_init()
    GAME.modules.params = {}
    GAME.params         = {}
    local obj           = GAME.modules.params
    function obj:event(e)
        if e.type == "net:join" then
            net_send(e.uid, "state", GAME.params.state or "lobby")
            send_html(e.uid)
        end
    end
end

function chat_init()
    GAME.modules.chat = {}
    local obj         = GAME.modules.chat
    function obj:event(e)
        if e.type == "net:message" then
            local v = e.value
            if v:sub(1,1) == "*" then return end
            local c = GAME.clients[e.uid]
            if c then
                net_send("", "chat", json.encode({
                    uid   = e.uid,
                    color = c.color,
                    value = "<" .. c.name .. "> " .. v,
                }))
            end
        end
    end
end

function begin_match_countdown()
    if GAME.pending_countdown then return end  -- already counting down
    if (GAME.start_countdown_seconds or 0) <= 0 then
        GAME.engine:next(GAME.modules.galcon)
        return
    end
    GAME.pending_countdown = GAME.start_countdown_seconds
    GAME.countdown_accum   = 0
    net_send("", "message", "Match starting in " .. GAME.pending_countdown .. "...")
end

function lobby_init()
GAME.modules.lobby = {}
local obj          = GAME.modules.lobby
function obj:init()
g2.state = "lobby"
params_set("state", "lobby")
GAME.host_window = GAME.host_window or "lobby"
broadcast_html()
end
function obj:loop(t)
    if GAME.pending_countdown then
        GAME.countdown_accum = (GAME.countdown_accum or 0) + t
        if GAME.countdown_accum >= 1 then
            GAME.countdown_accum = GAME.countdown_accum - 1
            GAME.pending_countdown = GAME.pending_countdown - 1
            if GAME.pending_countdown <= 0 then
                GAME.pending_countdown = nil
                GAME.countdown_accum   = nil
                if is_event_mode() then ev_apply_statuses() end
                if is_event_mode() and count_queued() < 2 then
                    net_send("", "message", "Match cancelled -- a player stepped out. Press START again.")
                    broadcast_html()
                    return
                end
                GAME.engine:next(GAME.modules.galcon)
            else
                net_send("", "message", GAME.pending_countdown .. "...")
            end
        end
    end
end
function obj:event(e)
if e.type == "net:join" or e.type == "net:leave" then
net_send("", "tabs", "")
broadcast_html()
return
end
if e.type == "net:message" then
local lv = e.value:lower():gsub("^%s+","")
-- ── Unified /toggle: command ─────────────────────────────────────
if lv:sub(1,8) == "/toggle:" then
                local what = lv:sub(9)
                if what:sub(1,5) == "mode:" then
                    set_room_mode(what:sub(6), e.name or "?")
                elseif what == "ranked" then
                    GAME.ranked = not GAME.ranked
                    net_send("","message","ElimV2 map rotation " .. (GAME.ranked and "ON - map settings locked." or "OFF - custom map pool active."))
                elseif what == "distance" then
                    if GAME.ranked then net_send("","message","Distance Change not available with ElimV2 rotation on.") return end
                    GAME.distance_change = not GAME.distance_change
                    net_send("","message","Distance Change: " .. (GAME.distance_change and "ON" or "OFF"))
                elseif what == "stages" or what == "classic" or what == "philbuff" or what == "12p" or what == "wonk" then
                    if GAME.ranked then net_send("","message","Map settings locked while ElimV2 rotation is on.") return end
                    GAME.map_styles[what] = not GAME.map_styles[what]
                    net_send("","message",what .. ": " .. (GAME.map_styles[what] and "ON" or "OFF"))
                elseif what == "saandbuff" then
                    if GAME.ranked then net_send("","message","Map settings locked while ElimV2 rotation is on.") return end
                    local all_on = true
                    for v = 1, 13 do if not GAME.map_styles.sb[v] then all_on = false break end end
                    for v = 1, 13 do GAME.map_styles.sb[v] = not all_on end
                    net_send("","message","SaandBuff: " .. (not all_on and "ALL ON" or "ALL OFF"))
                elseif what == "countdown_inc" then
                    GAME.start_countdown_seconds = math.min(10, GAME.start_countdown_seconds + 1)
                    net_send("","message","Start delay: " .. GAME.start_countdown_seconds .. "s")
                elseif what == "countdown_dec" then
                    GAME.start_countdown_seconds = math.max(0, GAME.start_countdown_seconds - 1)
                    net_send("","message","Start delay: " .. GAME.start_countdown_seconds .. "s")
                elseif what:sub(1,2) == "sb" then
                    local v = tonumber(what:sub(3))
                    if v and v >= 1 and v <= 13 then
                        if GAME.ranked then net_send("","message","Map settings locked while ElimV2 rotation is on.") return end
                        GAME.map_styles.sb[v] = not GAME.map_styles.sb[v]
                        net_send("","message","SaandBuff V"..v..": "..(GAME.map_styles.sb[v] and "ON" or "OFF"))
                    end
                end
                broadcast_html()
                return
            end
            if lv == "/batch" then
if not GAME.batch_mode then
GAME.batch_mode = true
broadcast_html()
net_send("", "message", "Batch REC ON -- games will be grouped. Press 'End Batch + Upload' when done.")
else
net_send(e.uid, "message", "Batch already active. Press 'End Batch + Upload' to finish.")
end
return
end
if lv == "/endbatch" then
if GAME.batch_mode then
GAME.batch_mode = false
broadcast_html()
net_send("", "message", "Batch ended -- uploading to Discord now...")
g2data_write({batch_end = true})
else
net_send(e.uid, "message", "No batch is currently active.")
end
return
end
if lv == "/endevent" then
ev_cancel(e.name or "?")
ev_apply_statuses()
broadcast_html()
return
end
if (lv == "/start" or lv:find("^/start") == 1) and is_event_mode() then
if ev_on_start(e.name or "?") then begin_match_countdown() end
broadcast_html()
elseif lv == "/start" or lv:find("^/start") == 1 then
if count_queued() >= 1 then
begin_match_countdown()
else
net_send(e.uid, "message", "No queued players. Type /play first.")
end
elseif lv:sub(1, 10) == "/setcolor:" then
local hex = lv:sub(11)
if hex == "pick" then
local raw = g2.form.colorpick or ""
raw = raw:gsub("^#",""):lower()
if #raw == 6 then hex = raw else hex = nil end
elseif hex == "random" then
local ri = math.random(1, #PRESET_COLORS)
hex = PRESET_COLORS[ri]
elseif hex == "default" then
player_custom_colors[e.uid] = nil
if e.uid == HOST_UID then
GAME.host_color = 0x00ff88
update_host_html()
else
clients_assign_colors()
send_html(e.uid)
end
net_send(e.uid, "message", "Color reset to default")
hex = nil
else
-- Typed into the hex box. This arrives here already substituted via
-- {$hexcolor} (the templating remote clients actually use), NOT via
-- g2.form.hexcolor, which only ever reflects the host's own input.
hex = hex:gsub("#",""):gsub("%s","")
if #hex ~= 6 or not hex:match("^%x%x%x%x%x%x$") then hex = nil end
end
if hex and #hex == 6 then
local r  = tonumber(hex:sub(1,2), 16) or 0
local g_ = tonumber(hex:sub(3,4), 16) or 0
local b  = tonumber(hex:sub(5,6), 16) or 0
local col_int = r*0x10000 + g_*0x100 + b
player_custom_colors[e.uid] = hex
if e.uid == HOST_UID then
GAME.host_color = col_int
update_host_html()
elseif GAME.clients[e.uid] then
GAME.clients[e.uid].color = col_int
send_html(e.uid)
end
net_send(e.uid, "message", "Color set to #" .. hex)
end
elseif lv == "/gg" then
net_send("", "message", e.name .. ": gg")
end
if (lv:find("^/play") == 1 or lv == "/away") and not is_event_mode() then
if count_queued() >= 2 then
begin_match_countdown()
end
end
end
end
end

-- Galcon's in-game user objects hand back user_uid as the engine stores
-- it, which is not guaranteed to be the same Lua type (number vs string)
-- as the uid on the client's net events. Comparing them with == then fails
-- silently: the winner's ELO went to a separate STATS entry nobody saw, so
-- only the loser's rating appeared to move. Always compare with same_uid
-- and key stats/events by the client uid from client_uid_of.
function same_uid(a, b)
    return a ~= nil and b ~= nil and tostring(a) == tostring(b)
end

function client_uid_of(user)
    if not user or user.user_uid == nil then return nil end
    local want = user.user_uid
    for _, uid in ipairs(GAME.player_uids or {}) do
        if same_uid(uid, want) then return uid end
    end
    for uid, _ in pairs(GAME.clients or {}) do
        if same_uid(uid, want) then return uid end
    end
    return want
end

function find_user(uid)
    for _, u in ipairs(g2.search("user")) do
        if same_uid(u.user_uid, uid) then return u end
    end
end

function galcon_surrender(uid)
    -- Intentionally do not mutate planets or fleets here. Fleet ship counts
    -- are engine-managed and may be read-only; assigning f.fleet_ships = 0
    -- can terminate the Lua script. galcon_handle_surrender() disables normal
    -- winner detection with pending_end and chooses the result after 2 seconds,
    -- so no world-state mutation is necessary.
end

function galcon_log_surrender_event(uid, user, reason)
    -- Explicit, always-written record of the surrender/leave -- not
    -- something downstream tooling has to infer from a cluster of pc/fu
    -- events. Pushed into rec_log_events, which flush_chunk persists on
    -- its next call regardless of how the match ultimately resolves, so
    -- this is present in every game where a surrender/leave happened.
    local t_now = math.floor(rec_clock * 10) / 10
    rec_log_events[#rec_log_events+1] = {
        e = "surrender", t = t_now, uid = uid,
        n = user and user.n or nil, reason = reason,
    }
end

-- Shared entry point for both /surrender and a mid-match disconnect.
-- First call in a match: logs an explicit surrender event and arms a 2s
-- countdown before the match
-- actually ends -- giving the other player a moment to also bail (in
-- which case nothing is recorded as a decisive result) rather than ending
-- the instant one side hits zero. A second call from the SAME uid (e.g.
-- surrender, then the client disconnects) is a no-op -- already handled.
function galcon_handle_surrender(uid, reason)
    local G = GAME.galcon
    if not G then return end
    G.surrendered = G.surrendered or {}
    if G.surrendered[uid] then return end  -- already processed this player

    -- Only one of the active match players may surrender. In particular, a
    -- spectator typing /surrender must not start pending_end and accidentally
    -- award the game to the first player in G.users.
    local user = nil
    for _, u in ipairs(G.users or {}) do
        if same_uid(u.user_uid, uid) then
            user = u
            break
        end
    end
    if not user then return end

    galcon_log_surrender_event(uid, user, reason)
    galcon_surrender(uid)
    G.surrendered[uid] = true

    if G.pending_end then
        -- A second, DIFFERENT player surrendered/left inside the window --
        -- abort entirely. galcon_stop(nil) already never writes a winner
        -- (flush_chunk only sets existing.winner when winner_info is
        -- truthy), and the explicit event below makes the abort itself
        -- unambiguous in the recording for any downstream tooling that
        -- wants to filter these games out.
        G.pending_end = nil
        local t_now = math.floor(rec_clock * 10) / 10
        rec_log_events[#rec_log_events+1] = { e = "double_surrender_abort", t = t_now }
        net_send("", "message", "Both players surrendered/left -- match aborted, not recorded.")
        local ok, err = pcall(galcon_stop, nil)
        if not ok then
            print("[ERROR] galcon_stop after double surrender: " .. tostring(err))
            net_send("", "message", "Match ended abnormally -- returning everyone to the lobby.")
            GAME.engine:next(GAME.modules.lobby)
        end
        return
    end

    -- First surrender/leave: arm the 2s countdown before ending the match.
    local name = user and user.title_value or "A player"
    net_send("", "message", name .. (reason == "left" and " left the match!" or " surrendered!") .. " Ending in 2s...")
    G.pending_end = { remaining = 2.0, leaving_uid = uid }
end

function galcon_stop(winner_user)
    if GAME.galcon then GAME.galcon.pending_end = nil end
    local winner_info = nil
    if winner_user then
        winner_info = {
            uid  = client_uid_of(winner_user),
            name = winner_user.title_value,
            n    = winner_user.n,
            side = (winner_user.n == rec_player1_n) and "player" or "enemy",
        }
    end
    flush_chunk(true, winner_info)
    local winner_uid = winner_user and client_uid_of(winner_user) or nil
    if winner_uid and GAME.player_uids then
        local loser_uid = nil
        for _, uid in ipairs(GAME.player_uids) do
            if uid ~= winner_uid then loser_uid = uid; break end
        end
        if loser_uid then
pcall(function()
                apply_result(winner_uid, loser_uid)
            end)
            local ok_s, err_s = pcall(stats_save)
            if not ok_s then print("[ERROR] stats_save: " .. tostring(err_s)) end
        end
        net_send("", "message", winner_user.title_value .. " conquered the galaxy!")
    else
        net_send("", "message", "Game over.")
    end
    net_send("", "sfx", "stop")
    for _, c in pairs(GAME.clients) do
        if c.status == "play" then c.status = "queue" end
    end
    if is_event_mode() then
        local ok, err = pcall(ev_on_result, winner_uid, GAME.player_uids or {})
        if not ok then print("[ERROR] ev_on_result: " .. tostring(err)) end
        ok, err = pcall(ev_apply_statuses, true)
        if not ok then print("[ERROR] ev_apply_statuses: " .. tostring(err)) end
    end
    clients_assign_colors()
    GAME.engine:next(GAME.modules.lobby)
end

function set_stage_label(G, text)
    -- Previously this drove a g2.new_label world object pinned at (SW/2,12)
    -- in MAP coordinates. That's the actual cause of the portrait-mode bug:
    -- world coordinates don't reliably land at "top-center of the screen"
    -- once the client's viewport/camera differs by orientation -- a fixed
    -- map-space x,y is not the same thing as a fixed screen-space position.
    -- Switched to broadcasting via the status field instead, which (like
    -- the existing versus-stats status line) is client UI chrome, not a
    -- world object, so it isn't subject to camera/viewport positioning at all.
    G.current_stage_text = text
    for _, c in pairs(GAME.clients) do
        if c.status == "play" then
            net_send(c.uid, "status", text)
        end
    end
    if not GAME.host_paused then
        g2.status = text
    end
end

-- Matches Aphid's confirmed SaandCon stages.lua + galcon_init timings exactly:
--   Stage 2 @ t=30  -- reveal first hidden batch
--   Stage 3 @ t=70  -- reveal second hidden batch (NOT 60 -- that was our own guess)
--   Stage 4 @ t=150 -- Aphid literally rewinds his match clock by `self.wait`
--                       (=1) every time it fires, re-triggering the same
--                       check next frame, for up to `self.counter < 110`
--                       iterations -- net effect is a 110-tick burst of
--                       "every neutral planet loses 1 ship" all happening
--                       right at t=150, with the clock held there meanwhile.
--   Stage 5         -- fires once his stage-4 counter hits 60 (partway through the burst)
--   Final stage @ t=200 -- production decay. Aphid's source is truncated right
--                       at this block's closing brace, so whether it's capped
--                       the same way as stage 4 isn't confirmed from what we
--                       have. Mirroring stage 4's bounded-burst pattern here
--                       rather than draining forever unbounded, since an
--                       uncapped every-frame drain would zero every planet's
--                       production within a couple of real-time seconds.
function stages_loop(t, G)
    G.stages_timer   = (G.stages_timer or 0) + t
    G.stage_counter  = G.stage_counter or 0
    G.stage6_counter = G.stage6_counter or 0
    local wait = 1
    local st = G.stages_timer

    if not G.stage2_done and math.floor(st) >= 30 then
        G.stage2_done = true
        if G.neutral_hide then
            for _,e in ipairs(g2.search("planet owner:"..G.neutral_hide.n)) do
                e:planet_chown(G.neutral)
            end
        end
        net_send("","message","[STAGES] New planets unlocked!")
        set_stage_label(G, "Stage 2 - 40s")
    end

    if not G.stage3_done and math.floor(st) >= 70 then
        G.stage3_done = true
        if G.neutral_hide2 then
            for _,e in ipairs(g2.search("planet owner:"..G.neutral_hide2.n)) do
                e:planet_chown(G.neutral)
            end
        end
        net_send("","message","[STAGES] More planets unlocked!")
        set_stage_label(G, "Stage 3 - 80s")
    end

    -- Changed == to >= here: exact equality risks silently never firing if a
    -- tick's floor(st) ever jumps past 150 in one step (skipping the exact
    -- frame) -- the same >= pattern stage2/3 already used safely. The
    -- G.stage_counter < 110 guard already prevents re-entry once the burst
    -- finishes, so this doesn't change post-burst behavior at all.
    if math.floor(st) >= 150 and G.stage_counter < 110 then
        if not G.stage4_announced then
            G.stage4_announced = true
            net_send("","message","[STAGES] Neutral planets weakening...")
            set_stage_label(G, "Stage 4 - Weakening")
        end
        for _,e in ipairs(g2.search("planet neutral")) do
            if e.ships_value > 0 then e.ships_value = e.ships_value - 1 end
        end
        G.stages_timer  = G.stages_timer - wait
        G.stage_counter = G.stage_counter + 1
    end

    if not G.stage5_done and G.stage_counter == 60 then
        G.stage5_done = true
        for _,e in ipairs(g2.search("user")) do e.fleet_v_factor = 1.5 end
        net_send("","message","[STAGES] Fleets accelerated!")
        set_stage_label(G, "Stage 5 - Fleets Accelerated")
    end

    -- Same >= fix as stage 4 above.
    if math.floor(st) >= 200 and G.stage6_counter < 110 then
        if not G.stage6_announced then
            G.stage6_announced = true
            net_send("","message","[STAGES] Planet production decaying...")
            set_stage_label(G, "Final Stage")
        end
        for _,e in ipairs(g2.search("planet")) do
            if e.ships_production > 0 then e.ships_production = e.ships_production - 1 end
        end
        G.stages_timer   = G.stages_timer - wait
        G.stage6_counter = G.stage6_counter + 1
    end
end

function galcon_check_winner()
    local G       = GAME.galcon
    if G and G.pending_end then return end  -- a surrender/leave sequence is already deciding the outcome
    local neutral = G.neutral
    local alive   = {}

    for _, p in ipairs(g2.search("planet")) do
        local own = p.owner_n
        if not (neutral and own == neutral.n) then
            for _, u in ipairs(G.users) do
                if u.n == own then
                    alive[own] = u
                    break
                end
            end
        end
    end

    local count  = 0
    local winner = nil
    for _, u in pairs(alive) do
        count  = count + 1
        winner = u
    end

    if count < #G.users then
        for _, f in ipairs(g2.search("fleet")) do
            for _, u in ipairs(G.users) do
                if u.n == f.owner_n and not alive[u.n] then
                    count = count + 1
                    break
                end
            end
        end
    end

    if #G.users <= 1 then return end

    if count <= 1 then
        if count == 0 then winner = nil end
        galcon_stop(winner)
    end
end

function galcon_init()
GAME.modules.galcon = {}
GAME.galcon         = {}
local obj           = GAME.modules.galcon
function obj:init()
local G = GAME.galcon

-- Full reset every game. G is the SAME table reused across every match
-- (it's created once in galcon_init(), not per-game), so anything set
-- during a Stages game -- neutral_hide/neutral_hide2 references, stage
-- trigger flags, timers -- was still sitting there on the NEXT game.
-- If that next game wasn't Stages, GAME.game_mode == "stages" was false
-- so this block never re-created neutral_hide, but build_map() below
-- still received the STALE (now-dangling) reference from last game and
-- happily assigned 4+3 neutral pairs to it -- which is exactly what
-- showed up as "planets already owned" plus the ship/production
-- imbalance in Philbuff/SaandBuff games that followed a Stages game.
G.neutral_hide     = nil
G.neutral_hide2    = nil
G.stages_nh        = nil
G.stages_nh2       = nil
G.stages_timer     = nil
G.stage_counter    = nil
G.stage6_counter   = nil
G.stage2_done      = nil
G.stage3_done      = nil
G.stage4_timer     = nil
G.stage4_announced = nil
G.stage5_done      = nil
G.stage6_timer     = nil
G.stage6_announced = nil
G.current_stage_text = nil
G.win_check_timer  = nil
G.stats_timer      = nil
G.pending_end      = nil
G.surrendered      = nil
for _, c in pairs(GAME.clients) do c.resumed = nil end

-- Pick map style for this game (also sets GAME.game_mode if stages)
    local _style, _ver, _is_stages
    if GAME.ranked then
        _style, _ver, _is_stages = pick_ranked_style()
    else
        _style, _ver, _is_stages = pick_random_style()
    end
    GAME.last_style = _style
    GAME.last_ver   = _ver or 7
    if _is_stages then
        GAME.game_mode = "stages"
    else
        GAME.game_mode = "standard"
    end

    g2.game_reset()
    math.randomseed(os.time())
    local neutral                    = g2.new_user("neutral", 0x444444)
neutral.user_neutral             = 1
neutral.ships_production_enabled = 0
G.neutral                        = neutral
GAME.neutral                     = neutral
G.users                          = {}
if GAME.game_mode == "stages" then
-- Confirmed from Aphid's SaandCon source: hidden planets aren't a
-- planet_style trick, they're owned by a user with ui_to_mask=0x4 --
-- a vision-mask bit no player has, so they simply never render for
-- anyone until re-owned to the visible `neutral` user.
local nh  = g2.new_user("neutral", 0x555555)
nh.user_neutral  = 0
nh.ships_production_enabled = 0
nh.planet_crash  = 2
nh.ui_to_mask    = 0x4
local nh2 = g2.new_user("neutral", 0x555555)
nh2.user_neutral = 0
nh2.ships_production_enabled = 0
nh2.planet_crash = 2
nh2.ui_to_mask   = 0x4
G.neutral_hide   = nh;  G.stages_nh  = nh
G.neutral_hide2  = nh2; G.stages_nh2 = nh2
G.stages_timer   = 0
end
local player_clients = {}
for _, uid in ipairs(GAME.client_order) do
local c = GAME.clients[uid]
if c and c.status == "queue" and not c.is_host then
if #player_clients < 2 then
player_clients[#player_clients + 1] = c
else
-- Shouldn't normally happen -- /play already caps the queue at 2 --
-- but bounce any overflow back to Away rather than let a 3rd+
-- player slip into the match.
c.status = "away"
end
end
end
if is_event_mode() and player_clients[2] then
-- Event schedule decides sides (double round robin swaps them in leg 2;
-- winner stays on keeps the champion as P1).
local ea = ev_next_pair()
if ea and player_clients[2].uid == ea then
player_clients[1], player_clients[2] = player_clients[2], player_clients[1]
end
end
for i, c in ipairs(player_clients) do
local col
if player_custom_colors[c.uid] then
local h  = player_custom_colors[c.uid]
local rr = tonumber(h:sub(1,2),16) or 0
local gg = tonumber(h:sub(3,4),16) or 0
local bb = tonumber(h:sub(5,6),16) or 0
col = rr*0x10000 + gg*0x100 + bb
else
col = c.color or PLAYER_COLORS[i] or 0xffffff
end
local u   = g2.new_user(c.name, col)
u.user_uid = c.uid
local shipSel = player_custom_ships[c.uid]
if shipSel and shipSel ~= "" then
    u.fleet_image = "ship-" .. shipSel
end
local skinSel = player_custom_skins[c.uid] or "normal"
u.planet_style = json.encode(SKIN_STYLES[skinSel] or SKIN_STYLES.normal)
G.users[i] = u
GAME.clients[c.uid].status = "play"
GAME.clients[c.uid].color  = col
end
GAME.player_uids = {}
for i2, c2 in ipairs(player_clients) do
GAME.player_uids[i2] = c2.uid
end
do
local ok, err = pcall(ev_on_game_start, GAME.player_uids)
if not ok then print("[ERROR] ev_on_game_start: " .. tostring(err)) end
end
G.p1 = G.users[1]
G.p2 = G.users[2]
if GAME.game_mode == "stages" then
    set_stage_label(G, "Stage 1 - 30s")
end
build_map(neutral, G.users, G.neutral_hide, G.neutral_hide2)
local map_planets = {}
for _, p in ipairs(g2.search("planet")) do
map_planets[#map_planets + 1] = {
n=p.n, x=round(p.position_x), y=round(p.position_y),
r=round(p.planet_r), prod=round(p.ships_production),
ships=round(p.ships_value), owner=p.owner_n,
}
end
rec_game_users = {
p1      = G.users[1],
p2      = G.users[2],
neutral = neutral,
}
rec_player1_n = G.users[1] and G.users[1].n or 0
rec_player2_n = G.users[2] and G.users[2].n or 0
reset_recording()
local p1_name  = G.users[1] and G.users[1].title_value or "Player1"
local p2_name  = G.users[2] and G.users[2].title_value or "Player2"
local p1_uid   = (GAME.player_uids and GAME.player_uids[1]) or (G.users[1] and G.users[1].user_uid) or ""
local p2_uid   = (GAME.player_uids and GAME.player_uids[2]) or (G.users[2] and G.users[2].user_uid) or ""
local p1_color = "00ff88"
local p2_color = "ff4455"
for uid, c in pairs(GAME.clients) do
local hex = string.format("%06x", c.color or 0x555555)
if uid == p1_uid then p1_color = hex
elseif uid == p2_uid then p2_color = hex end
end
g2data_write({
payload = {
chunk=0, final=false, status="part0",
map=map_planets,
player_n=rec_player1_n, enemy_n=rec_player2_n,
player_name=p1_name, enemy_name=p2_name,
player_uid=p1_uid, enemy_uid=p2_uid,
batch_mode=(GAME.batch_mode and true or false),
player_color=p1_color, enemy_color=p2_color,
version=1, w=SW, h=SH,
style=GAME.last_style, style_ver=GAME.last_ver,
distance_change=(GAME.distance_change and true or false),
game_mode=GAME.game_mode, ranked=(GAME.ranked and true or false),
room_mode=GAME.room_mode or "standard", event_label=GAME.ev_game_label or "",
},
summary={},
})
rec_chunk_index = 1
for _, f in ipairs(g2.search("fleet")) do
local id = tostring(f.sync_id)
rec_prev_fleets[id] = {
id=id, x=round(f.position_x), y=round(f.position_y),
ships=round(f.fleet_ships), owner=f.owner_n, target=f.fleet_target,
}
end
G.win_check_timer = 0  
local names = {}
for _, u in ipairs(G.users) do names[#names+1] = u.title_value end
net_send("", "message", table.concat(names, " vs ") .. " -- GO!")
local _ver_lbl = (GAME.last_style == "saandbuff") and (" V"..(GAME.last_ver or "?")) or ""
        local _stage_lbl = (GAME.game_mode == "stages") and " [STAGES]" or ""
local _mode_lbl = (GAME.game_mode == "stages") and "  [STAGES]" or ""
net_send("", "message", "Map: " .. GAME.last_style .. _ver_lbl .. _stage_lbl)
net_send("", "sfx", "start")
g2.state = "play"
params_set("state", "play")
for _, c in pairs(GAME.clients) do
if c.status == "play" then
g2.net_send(c.uid, "html", "<table width=340>" .. build_ingame_html(c) .. "</table>")
g2.net_send(c.uid, "tabs", "")
end
end
end
function obj:loop(t)
local G = GAME.galcon
GAME._last_t = t
G.win_check_timer = (G.win_check_timer or 0) + t
record_loop(t)
if G.p1 then update_stats_html(G.p1, G.p2) end
if GAME.game_mode == "stages" then stages_loop(t, G) end
if G.pending_end then
    G.pending_end.remaining = G.pending_end.remaining - t
    if G.pending_end.remaining <= 0 then
        local leaving_uid = G.pending_end.leaving_uid
        G.pending_end = nil
        local winner = nil
        for _, u in ipairs(G.users) do
            if u.user_uid ~= nil and not same_uid(u.user_uid, leaving_uid) then winner = u; break end
        end
        local ok, err = pcall(galcon_stop, winner)
        if not ok then
            print("[ERROR] galcon_stop after surrender/leave: " .. tostring(err))
            net_send("", "message", "Match ended abnormally -- returning everyone to the lobby.")
            GAME.engine:next(GAME.modules.lobby)
        end
        return  -- galcon_stop already switched modules -- don't touch a dead G below
    end
end
if G.win_check_timer >= WIN_CHECK_DELAY then galcon_check_winner() end
end
function obj:event(e)
if e.type == "net:leave" then
local G = GAME.galcon
local left_uid = e.uid
local was_player = false
for _, uid in ipairs(GAME.player_uids or {}) do
if uid == left_uid then was_player = true break end
end
if was_player and G and G.users then
-- Same shared handler /surrender uses: log an explicit surrender event
-- and arm the 2s window rather than
-- ending the match this instant. Covers the original concern here (a
-- player closing the app via the native X button shouldn't be able to
-- stall the room) just as well, since this timer runs every frame in
-- obj:loop rather than waiting on the slower periodic win-check.
galcon_handle_surrender(left_uid, "left")
return
end
-- Spectator/host disconnects do not alter the active match.
end
if e.type == "net:message" then
local lv = e.value:lower():gsub("^%s+","")
if lv == "/surrender" then
local G = GAME.galcon
if #G.users <= 1 then
galcon_stop(nil)
else
galcon_handle_surrender(e.uid, "surrender")
end
elseif lv == "/abort" then
galcon_stop(nil)
elseif lv == "/gg" then
net_send("", "message", e.name .. ": gg")
end
end
end
end

function register_init()
    GAME.modules.register   = {}
    GAME.modules.register.t = 0
    local obj               = GAME.modules.register
    function obj:loop(t)
        if GAME.module == GAME.modules.menu then return end
        self.t = self.t - t
        if self.t <= 0 then
            self.t = 60
            g2_api_call("register", json.encode({
                title = ROOM_TITLE,
                port  = GAME.data and GAME.data.port or DEFAULT_PORT,
            }))
        end
    end
end

function fmt_time(t)
    local m = math.floor(t / 60)
    local s = math.floor(t % 60)
    return string.format("%02d:%02d", m, s)
end

function total_ships(user)
    local total = 0
    for _, p in ipairs(g2.search("planet owner:" .. user)) do
        total = total + math.floor(p.ships_value)
    end
    for _, f in ipairs(g2.search("fleet owner:" .. user)) do
        total = total + math.floor(f.fleet_ships)
    end
    return total
end

function total_production(user)
    local total = 0
    for _, p in ipairs(g2.search("planet owner:" .. user)) do
        total = total + math.floor(p.ships_production)
    end
    return total
end

function calc_versus_timer(ps, pp, es, ep)
    local prod_diff = (pp - ep) / 50.0
    if prod_diff == 0 then return nil end
    return -(ps - es) / prod_diff
end

function get_player_color(user, fallback)
    if not user then return fallback or "#888888" end
    local cu = user and client_uid_of(user)
    local c = GAME.clients and cu and GAME.clients[cu]
    if c and c.color then return "#" .. int_to_hex(c.color) end
    return fallback or "#888888"
end

function build_spectator_html(p1,p2,ps,pp,es,ep,extra_rows)
    if not p1 then return "<table><tr><td><p>Loading...</p></table>" end
    p2=p2 or p1; es=es or 0; ep=ep or 0

    local c1 = get_player_color(p1, "#00ff88")
    local c2 = get_player_color(p2, "#ff4455")

    local adv=ps-es; local prod_adv=pp-ep
    local vt=calc_versus_timer(ps,pp,es,ep)
    local e_name=(p2 and p2~=p1) and p2.title_value or "???"

    local adv_str,adv_col
    if adv>0 then adv_str="Ship +"..adv; adv_col=c1
    elseif adv<0 then adv_str="Ship "..adv; adv_col=c2
    else adv_str="Ships even"; adv_col="#ffffff" end

    local pa_str,pa_col
    if prod_adv>0 then pa_str="Prod +"..prod_adv; pa_col=c1
    elseif prod_adv<0 then pa_str="Prod "..prod_adv; pa_col=c2
    else pa_str="Prod even"; pa_col="#ffffff" end

    local vs_str,vs_col
    if vt==nil then vs_str="Even production"; vs_col="#ffffff"
    elseif vt<=0 then
        local ldr=pp>ep and p1.title_value or e_name
        vs_str=ldr.." dominating"; vs_col=pp>ep and c1 or c2
    else
        local ldr=pp>ep and p1.title_value or e_name
        local vt_str=vt<60 and string.format("%.1fs",vt) or fmt_time(vt)
        vs_str=ldr.." +"..vt_str; vs_col=pp>ep and c1 or c2
    end

    local p_light,e_light
    if adv>0 and prod_adv>0 then p_light=c1; e_light="#333333"
    elseif adv<0 and prod_adv<0 then p_light="#333333"; e_light=c2
    else p_light="#aaaaaa"; e_light="#aaaaaa" end

    return "<table width=340>" ..
        "<tr>" ..
            "<td align=left width=110><div font='font-outline:22' color='"..c1.."'>"..p1.title_value.."</div></td>" ..
            "<td align=center width=120><div font='font-outline:20' color='"..p_light.."'>&#9679;</div></td>" ..
            "<td align=right width=110><div font='font-outline:22' color='"..c2.."'>"..e_name.."</div></td>" ..
        "</tr>" ..
        "<tr>" ..
            "<td align=left><div font='font-outline:20' color='"..c1.."'>Ships: "..ps.."</div></td>" ..
            "<td align=center><div font='font-outline:28' color='"..adv_col.."'>"..adv_str.."</div></td>" ..
            "<td align=right><div font='font-outline:20' color='"..c2.."'>Ships: "..es.."</div></td>" ..
        "</tr>" ..
        "<tr>" ..
            "<td align=left><div font='font-outline:20' color='"..c1.."'>Prod: "..pp.."</div></td>" ..
            "<td align=center><div font='font-outline:28' color='"..pa_col.."'>"..pa_str.."</div></td>" ..
            "<td align=right><div font='font-outline:20' color='"..c2.."'>Prod: "..ep.."</div></td>" ..
        "</tr>" ..
        "<tr>" ..
            "<td colspan=3 align=center>" ..
                "<div font='font-outline:34' color='"..vs_col.."'>"..vs_str.."</div>" ..
            "</td>" ..
        "</tr>" ..
        (extra_rows or "") ..
    "</table>"
end

function build_spectator_pause_html(p1, p2, ps, pp, es, ep)
    -- Both extra bits are inserted as rows INSIDE build_spectator_html's one
    -- table, not as separate concatenated <table> blocks. That concatenation
    -- was the actual bug: this html renderer only shows the FIRST top-level
    -- table when several are chained together, which is why the stats
    -- table vanished and only the stage-text table was left visible.
    local extra = ""
    if GAME.game_mode == "stages" and GAME.galcon and GAME.galcon.current_stage_text then
        extra = extra .. "<tr><td colspan=3 align=center><div font='font-outline:16' color='#ffcc44'>"
            .. GAME.galcon.current_stage_text .. "</div></td></tr>"
    end
    extra = extra .. "<tr><td colspan=3 align=right>"
        .. "<input type='button' value='Resume' onclick='resume' class='ibutton1' width=80 height=32/>"
        .. "</td></tr>"
    return build_spectator_html(p1, p2, ps, pp, es, ep, extra)
end

function build_status_line(p1,p2,ps,pp,es,ep)
    p2=p2 or p1; es=es or 0; ep=ep or 0
    local adv=ps-es; local padv=pp-ep
    local vt=calc_versus_timer(ps,pp,es,ep)
    local en=(p2 and p2~=p1) and p2.title_value or "???"
    local vs
    if vt==nil then vs="even"
    elseif vt<=0 then vs=(pp>ep and p1.title_value or en).." dominating"
    else
        local vts=vt<60 and string.format("%.1fs",vt) or fmt_time(vt)
        vs=(pp>ep and p1.title_value or en).." evens "..vts
    end
    return p1.title_value.."  S"..ps.." P"..pp.."  |ShipAdv "..(adv>0 and "+" or "")..adv..
           "  ProdAdv "..(padv>0 and "+" or "")..padv.."  VS "..vs.."  "..en.."  S"..es.." P"..ep
end

function build_spectator_game_tabs()
    return "<table><tr><td><input width='100%' type='button' onclick='*chat\t' value='' icon='icon-chat' class='tab' pseudo='first last'/></table>"
end

function update_stats_html(p1,p2)
    if not p1 or not GAME.galcon then return end
    GAME.galcon.stats_timer=(GAME.galcon.stats_timer or 0)+(GAME._last_t or 0.05)
    if GAME.galcon.stats_timer<0.5 then return end
    GAME.galcon.stats_timer=0
    local ps=total_ships(p1); local es=p2 and total_ships(p2) or 0
    local pp=total_production(p1); local ep=p2 and total_production(p2) or 0
    local sl=build_status_line(p1,p2,ps,pp,es,ep)
    local ph=build_spectator_pause_html(p1,p2,ps,pp,es,ep)
    for _,c in pairs(GAME.clients) do
        if c.status=="away" then
            -- Removed the plain numeric status bar for spectators entirely --
            -- they only ever see the pause-mode stats panel now (added below
            -- in build_spectator_pause_html), never a separate black-and-white
            -- status line.
            if not c.resumed then
                g2.net_send(c.uid,"html",ph)
            end
            g2.net_send(c.uid,"tabs",build_spectator_game_tabs())
        end
    end
    -- Host gets the same treatment as spectators now: no plain numeric
    -- status line at all outside pause mode -- only the colored panel via
    -- g2.html when actually paused. (Stage-indicator text, written
    -- separately by set_stage_label, is unaffected -- that's a distinct
    -- thing from these "stats", per the request.)
    if GAME.host_paused then g2.html=ph end
end

-- ── Cost tiers ───────────────────────────────────────────────────────────
-- Every tier boundary and cost range below is copied verbatim from Aphid's
-- mapkit.lua getSaandbuffVals (previously an if/elseif chain here). Each
-- entry is {prod_lo, prod_hi, cost_lo, cost_hi}: prod_lo inclusive, prod_hi
-- exclusive for tier LOOKUP, but used as the inclusive top of the tier's
-- production span when Distance Change interpolates (Saand's spec: range 4
-- of V5 spans prod 81..100). "P" in prod_hi means the version's own max
-- generated production (see sb_prod_range), so the top tier closes cleanly.
local SB_TIERS = {
    [1]  = { {30,51,5,10},  {51,76,11,30},  {76,90,30,45},  {90,"P",45,60} },
    [2]  = { {30,46,1,5},   {46,61,5,10},   {61,75,15,30},  {75,90,30,45},  {90,"P",45,60} },
    [3]  = { {30,46,1,5},   {46,61,5,10},   {61,75,11,29},  {75,90,30,45},  {90,"P",45,60} },
    [4]  = { {20,40,0,5},   {40,66,6,15},   {66,86,16,40},  {86,100,41,60}, {100,"P",60,70} },
    [5]  = { {20,41,0,5},   {41,61,5,10},   {61,81,20,35},  {81,100,36,55}, {100,"P",56,65} },
    [6]  = { {20,41,0,5},   {41,66,5,15},   {66,81,12,30},  {81,100,25,60}, {100,"P",30,70} },
    [7]  = { {30,51,5,10},  {51,71,10,20},  {71,81,20,30},  {81,100,30,60}, {100,"P",40,70} },
    [8]  = { {20,41,0,5},   {41,61,10,20},  {61,81,20,30},  {81,"P",35,70} },
    [9]  = { {15,41,0,5},   {41,61,5,10},   {61,71,11,20},  {71,"P",20,40} },
    [10] = { {15,30,0,3},   {30,51,4,9},    {51,71,10,20},  {71,80,20,35},  {80,"P",30,40} },
    -- V11 tiers are ratios of the map's mean production (getV11Cost), resolved
    -- to absolute prod bounds at lookup time in sb_tier().
    [11] = { {0,0.60,0,8},  {0.60,0.90,8,20}, {0.90,1.20,20,40}, {1.20,"P",40,70} },
    [12] = { {15,40,0,8},   {40,60,8,18},   {60,80,20,28},  {80,100,35,45}, {100,"P",50,60} },
    -- V13 adds a per-planet bias of random(-5,5) to both cost bounds (applied in sb_tier).
    [13] = { {"M",40,0,8},  {40,60,8,20},   {60,80,20,35},  {80,"P",35,60} },
}

-- Per-version generated production range (SaandConV3.lua mapStyle==3 branch).
function sb_prod_range(v)
    if v == 4 then return 20, 120
    elseif v == 5 then return 20, 110
    elseif v == 6 then return 20, 120
    elseif v == 7 then return 30, 120
    elseif v == 8 then return 20, 120
    elseif v == 9 then return 15, 80
    elseif v == 10 then return 15, 90
    else return MAP.prod_min, MAP.prod_max end -- v1,2,3,11,12,13
end

-- Returns prod_lo, prod_hi, cost_lo, cost_hi for the tier `prod` falls in.
function sb_tier(v, prod, meanProd)
    local pmin, pmax = sb_prod_range(v)
    local list = SB_TIERS[v]
    if not list then return pmin, pmax, 5, 20 end  -- unknown version fallback
    local ref = (v == 11) and (meanProd or 70) or 1
    local bias = (v == 13) and math.random(-5, 5) or 0
    for _, t in ipairs(list) do
        local lo, hi = t[1], t[2]
        if lo == "M" then lo = pmin end
        if hi == "P" then hi = pmax else hi = hi * ref end
        lo = lo * ref
        if prod >= lo and prod < hi then
            local clo, chi = t[3] + bias, t[4] + bias
            clo = math.max(0, clo); chi = math.max(clo, chi)
            return math.max(pmin, lo), hi, clo, chi
        end
    end
    -- prod above every tier's upper bound (only possible if a range table is
    -- edited inconsistently) -- use the top tier.
    local t = list[#list]
    local clo, chi = math.max(0, t[3] + bias), t[4] + bias
    return math.max(pmin, t[1] == "M" and pmin or t[1] * ref), pmax, clo, math.max(clo, chi)
end

-- Random-roll path (Distance Change OFF). Same distributions as before.
function getSaandbuffVals(v, prod, meanProd)
    local _, _, clo, chi = sb_tier(v, prod, meanProd)
    return math.floor(math.random(clo, chi))
end

-- Tier bounds for every style, so Distance Change can interpolate uniformly.
-- Non-SaandBuff styles have no production tiering, so their single "tier"
-- is the style's whole prod range x its whole cost range. Philbuff's cost
-- bounds depend on prod, so callers must recompute them after moving prod.
function style_tier(style, ver, prod, mean_prod, home_ships)
    if style == "classic"  then return MAP.prod_min, MAP.prod_max, 0, 30
    elseif style == "12p"  then return MAP.prod_min, MAP.prod_max, 0, 20
    elseif style == "wonk" then return 1, 100, 0, math.max(1, math.floor(home_ships * 0.5))
    elseif style == "stages" then return 35, 100, 5, 35
    elseif style == "philbuff" then
        return MAP.prod_min, MAP.prod_max, math.floor(prod / 20), math.floor(prod / 1.50)
    else
        return sb_tier(ver, prod, mean_prod)
    end
end

function reset_recording()
    rec_clock=0; rec_frame=0; rec_pos_frame=0; rec_save_timer=0
    rec_chunk_index=1; rec_log_events={}; rec_log_pos={}
    rec_log_summary={}; rec_prev_fleets={}; rec_prev_planets={}
end

function flush_chunk(final, winner_info)
    local t_now = math.floor(rec_clock * 10) / 10
    for id, f in pairs(rec_prev_fleets) do
        rec_log_pos[#rec_log_pos+1] = { t_now, id, f.x, f.y, 0 }
    end
    if #rec_log_events + #rec_log_pos == 0 and not final then return end
    -- Same corruption guard as menu_init:init() -- a bad g2.data must never
    -- crash the recorder mid-match and strand two players in a stuck room.
    local ok, decoded = pcall(json.decode, g2.data)
    local existing = (ok and type(decoded) == "table") and decoded or {}
    existing.payload   = {
        chunk=rec_chunk_index, final=final and true or false,
        status="part"..rec_chunk_index,
        events=rec_log_events, pos=rec_log_pos,
    }
    -- Confirmed by actually reading replay_viewer.html: detectWinnerFromLines()
    -- scans each decoded JSONL line for a TOP-LEVEL field literally called
    -- `winner` (sibling to `summary`, not nested under `payload`), and expects
    -- it to be a plain string exactly equal to player_name or enemy_name --
    -- it does obj.winner===p1Name / ===p2Name for a direct string match, and
    -- it's read from the LAST line backwards, so writing it on the final
    -- chunk is exactly right. My previous guess (nested winner_uid/winner_name/
    -- winner_n/winner_side under payload) didn't match this at all -- kept
    -- below as harmless extras, but `existing.winner` is the field that
    -- actually matters.
    if final and winner_info then
        existing.winner = winner_info.name
        existing.payload.winner_uid  = winner_info.uid
        existing.payload.winner_name = winner_info.name
        existing.payload.winner_n    = winner_info.n
        existing.payload.winner_side = winner_info.side
    end
    existing.summary   = rec_log_summary
    g2data_write(existing)
    rec_log_events     = {}
    rec_log_pos        = {}
    rec_chunk_index    = rec_chunk_index + 1
end




-- Pick the next map style from the non-ranked pool.
-- All non-SB styles each count as 1 slot (Stages included -- it's its own
-- independent style, not a SaandBuff variant, matching Aphid's real
-- mode/variant split where Stages always has an empty variant). All
-- selected SaandBuff versions collectively count as 1 slot, split equally
-- among them. No style is allowed to repeat back-to-back -- GAME.last_style
-- still holds the PREVIOUS game's style at the point this runs (it's only
-- overwritten after this returns).
-- Returns: style, ver (nil if not SB), is_stages (bool)
function pick_random_style()
    local ms = GAME.map_styles

    local function build_pool(exclude)
        local pool    = {}
        local sb_pool = {}
        if ms.stages    and exclude ~= "stages"   then pool[#pool+1] = "stages"   end
        if ms.classic   and exclude ~= "classic"  then pool[#pool+1] = "classic"  end
        if ms.philbuff  and exclude ~= "philbuff" then pool[#pool+1] = "philbuff" end
        if ms["12p"]    and exclude ~= "12p"      then pool[#pool+1] = "12p"      end
        if ms.wonk      and exclude ~= "wonk"     then pool[#pool+1] = "wonk"     end
        for v = 1, 13 do
            if ms.sb[v] then sb_pool[#sb_pool+1] = v end
        end
        if #sb_pool > 0 and exclude ~= "saandbuff" then pool[#pool+1] = "_sb" end
        return pool, sb_pool
    end

    local function resolve(pick, sb_pool)
        if pick == "_sb" then
            return "saandbuff", sb_pool[math.random(1, #sb_pool)], false
        elseif pick == "stages" then
            return "stages", nil, true
        else
            return pick, nil, false
        end
    end

    local pool, sb_pool = build_pool(nil)
    if #pool == 0 then return "saandbuff", 7, false end  -- fallback: nothing selected at all

    local style, ver, is_stages = resolve(pool[math.random(1, #pool)], sb_pool)

    if style == GAME.last_style then
        -- Rebuild the pool excluding whatever just repeated and try again.
        local pool2, sb_pool2 = build_pool(style)
        if #pool2 > 0 then
            style, ver, is_stages = resolve(pool2[math.random(1, #pool2)], sb_pool2)
        end
        -- If pool2 came back empty, only one style is enabled in settings
        -- at all -- a repeat is genuinely unavoidable, so let it through.
    end

    return style, ver, is_stages
end

-- Ranked uses ElimV2: SaandBuff gets 50% total, split evenly across all 13
-- versions; 12p, Stages, and Philbuff each get the remaining 50% split three
-- ways (50/3% ~= 16.67% each). No style is allowed to repeat back-to-back --
-- GAME.last_style still holds the PREVIOUS game's style at the point this
-- runs (it's only overwritten after this returns), so we can check it directly.
function pick_ranked_style()
    local function roll_once()
        local roll = math.random() * 100
        if roll < 50 then
            return "saandbuff", math.random(1, 13), false
        elseif roll < 50 + (50/3) then
            return "stages", nil, true
        elseif roll < 50 + 2*(50/3) then
            return "philbuff", nil, false
        else
            return "12p", nil, false
        end
    end

    local style, ver, is_stages = roll_once()

    if style == GAME.last_style then
        -- Reroll evenly among the other three -- no style is allowed to
        -- repeat back-to-back in ranked, not just SaandBuff.
        local alt = {}
        for _, s in ipairs({"saandbuff", "stages", "philbuff", "12p"}) do
            if s ~= style then alt[#alt+1] = s end
        end
        local pick = alt[math.random(1, #alt)]
        if pick == "saandbuff" then
            return "saandbuff", math.random(1, 13), false
        elseif pick == "stages" then
            return "stages", nil, true
        else
            return pick, nil, false
        end
    end

    return style, ver, is_stages
end


-- Exact fidelity: SaandConV3.lua / utils.lua
function prodToRadius(p)
    return (p * 12 / 5 + 168) / 17
end

-- Exact fidelity: SaandConV3.lua / utils.lua getDistance -- plain Euclidean
-- distance between two points, used by the placement collision check below.
function getDistance(x1, y1, x2, y2)
    local dx, dy = x1 - x2, y1 - y2
    return math.sqrt(dx * dx + dy * dy)
end

function build_map(neutral, player_users, neutral_hide, neutral_hide2)
    local sw, sh = SW, SH
    local pad = 0  -- SaandConV3.lua: `local pad = 0`, shared by every gamemode block

    -- Style was already picked in galcon_init before staged users were created
    local style = GAME.last_style
    local ver   = GAME.last_ver

    -- Number of neutral pairs
    local npairs = (style == "12p") and math.floor(MAP.neutrals / 2 / 2) or MAP.neutrals / 2

    -- Home planet stats (wonk randomises)
    local home_prod, home_ships = MAP.home_prod, MAP.home_ships
    if style == "wonk" then
        home_prod  = math.random(1, 100)
        home_ships = math.random(1, 100)
    end
    local home_r = prodToRadius(home_prod)

    -- Map size adjustments
    if style == "classic" then
        sw = sw / 1.1;  sh = sh / 1.1
    elseif style == "12p" then
        sw = sw / 1.25; sh = sh / 1.25
    end

    -- ── Homes are placed FIRST, matching Aphid's control flow exactly:
    -- both his Stages and Classic blocks create + record home planets into
    -- `planets` before generating any neutral. This ordering matters:
    -- `planets` is the collision registry the neutral placement loop below
    -- checks against, so homes must be in it before any neutral is placed.
    local planets = {}
    local homes   = {}   -- home positions only, for Distance Change
    local nplayers = #player_users
    local angle_offset = math.random(0, 360)
    for i, u in ipairs(player_users) do
        local angle = angle_offset + (i - 1) * (360 / nplayers)
        local hx = sw / 2 + (sw - pad * 2) * math.cos(angle * math.pi / 180.0) / 2.0
        local hy = sh / 2 + (sh - sh / 15 * 2) * math.sin(angle * math.pi / 180.0) / 2.0
        g2.new_planet(u, hx, hy, home_prod, home_ships)
        table.insert(planets, { x = hx,      y = hy,      r = home_r })
        table.insert(planets, { x = sw - hx, y = sh - hy, r = home_r })
        table.insert(homes,   { x = hx,      y = hy })
    end
    -- Normalize against the TRUE farthest a point anywhere in the map
    -- rectangle can be from its nearest home -- not just home-to-centre,
    -- and not just the 4 corners either (checked: for some home angles the
    -- true worst point is out along the perpendicular bisector between the
    -- two homes, up to ~1.76x farther than the corners suggest). Using an
    -- under-sized max there was the actual cause of "every planet huge and
    -- 5-ship cheap": most of the map reported t > 1, clamped to 1, and got
    -- slammed to the tier's extreme (max prod / min cost). A coarse grid
    -- scan of the rectangle is a one-time, cheap (~500-point) cost per game
    -- and is correct regardless of home geometry.
    local d_home_max = 1
    if #homes >= 1 then
        local step = 20
        for gx = 0, sw, step do
            for gy = 0, sh, step do
                local nearest = math.huge
                for _, hp in ipairs(homes) do
                    nearest = math.min(nearest, getDistance(gx, gy, hp.x, hp.y))
                end
                if nearest > d_home_max then d_home_max = nearest end
            end
        end
    end

    -- Generate production values for each pair
    -- SaandBuff production ranges are per-version in Aphid's source (SaandConV3.lua,
    -- mapStyle==3 / distOn==false branch) -- versions 4-10 each draw from their own
    -- wider range, not the flat 30-100 every other style uses. Matching those exactly
    -- matters because getSaandbuffVals' tier boundaries are calibrated against them.
    local prods = {}
    for i = 1, npairs do
        if style == "wonk" then
            prods[i] = math.random(1, 100)
        elseif style == "stages" then
            prods[i] = math.random(35, 100)  -- Aphid's exact Stages range
        elseif style == "saandbuff" then
            local pmin, pmax = sb_prod_range(ver)
            prods[i] = math.random(pmin, pmax)
        else
            prods[i] = math.random(MAP.prod_min, MAP.prod_max)
        end
    end
    local tot = 0
    for _, p in ipairs(prods) do tot = tot + p end
    local mean_prod = tot / #prods

    -- Place neutral planet pairs (symmetric)
    for i = 1, npairs do
        local prod = prods[i]
        local plo, phi, clo, chi = style_tier(style, ver, prod, mean_prod, home_ships)
        local cost = math.floor(math.random(clo, chi))

        local radius = prodToRadius(prod)
        -- floor() guards Lua 5.3+, where math.random rejects non-integer
        -- bounds outright (confirmed: radius is never an integer here).
        -- Aphid's source calls math.random(radius, sw-radius) unguarded,
        -- which only works as-is under Lua 5.1's all-doubles number model.
        local x_lo, x_hi = math.floor(radius), math.floor(sw - radius)
        local y_lo, y_hi = math.floor(radius), math.floor(sh - radius)
        if x_hi < x_lo then x_hi = x_lo end
        if y_hi < y_lo then y_hi = y_lo end
        local x = math.random(x_lo, x_hi)
        local y = math.random(y_lo, y_hi)

        -- ── Collision-avoidance placement, exact fidelity to SaandConV3.lua ──
        -- Reject a candidate position if it's (a) within radius+margin of the
        -- map center (the symmetry point -- a planet there would sit on top of
        -- its own mirror), or (b) within radius + other.r + margin of any
        -- planet already in `planets` (homes + every prior neutral pair).
        -- Re-roll and re-check, up to 500 attempts, same cap as Aphid. The
        -- `d ~= 0` guard is his too. margin = prodToRadius(30) is the gap
        -- his maps ship with; it's what keeps neighbors visibly separated.
        local margin = prodToRadius(30)
        if #planets > 1 then
            local didCollide = true
            local attempts = 0
            while didCollide and attempts < 500 do
                didCollide = false
                if getDistance(x, y, sw / 2, sh / 2) <= radius + margin then
                    x = math.random(x_lo, x_hi)
                    y = math.random(y_lo, y_hi)
                    didCollide = true
                    attempts = attempts + 1
                end
                for j = 1, #planets do
                    local d = getDistance(x, y, planets[j].x, planets[j].y)
                    if d <= radius + planets[j].r + margin and d ~= 0 then
                        x = math.random(x_lo, x_hi)
                        y = math.random(y_lo, y_hi)
                        didCollide = true
                        attempts = attempts + 1
                        break
                    end
                end
            end
        end

        -- ── Distance Change (Saand's spec, replaces the random roll above) ──
        -- Keep the tier prod rolled into, but inside it let distance from the
        -- nearest home decide both values instead of math.random:
        --   t = 0 (touching home)  -> prod = tier low,  cost = tier high
        --   t = 1 (map centre)     -> prod = tier high, cost = tier low
        -- Mirror pairs are equidistant from their respective homes, so both
        -- halves land on the same numbers -- symmetry is preserved exactly.
        if GAME.distance_change then
            local d_home = math.huge
            for _, hp in ipairs(homes) do
                d_home = math.min(d_home, getDistance(x, y, hp.x, hp.y))
            end
            local t = math.max(0, math.min(1, d_home / d_home_max))
            -- (t should no longer clamp against d_home_max in practice --
            -- see the corner-sampling note above.)
            prod = math.floor(plo + t * (phi - plo) + 0.5)
            if style == "philbuff" then
                clo, chi = math.floor(prod / 20), math.floor(prod / 1.50)
            end
            cost = math.floor(chi - t * (chi - clo) + 0.5)
        end

        local owner, ships = neutral, cost

        -- Stages: these pairs start owned by a "hidden" neutral user (whose
        -- ui_to_mask=0x4 keeps them invisible to everyone) and just get
        -- re-owned to the visible neutral at the right stage -- no fake
        -- ship count needed, they already carry their real final cost
        -- from generation. Thresholds match Aphid's exact OPTS values
        -- (first_neutrals=12, second_neutrals=18 -> /2 = 6 and 9): pairs
        -- 1-6 stay visible from the start (discounted -4), pairs 7-9 are
        -- hidden batch 1, pairs 10+ are hidden batch 2.
        if style == "stages" then
            if i <= 6 then
                ships = math.max(0, ships - 4)
            elseif neutral_hide and i <= 9 then
                owner = neutral_hide
            elseif neutral_hide2 then
                owner = neutral_hide2
            end
        end

        g2.new_planet(owner, x,      y,      prod, ships)
        g2.new_planet(owner, sw - x, sh - y, prod, ships)

        table.insert(planets, { x = x,      y = y,      r = radius })
        table.insert(planets, { x = sw - x, y = sh - y, r = radius })
    end

    g2.view_set(0, 0, sw, sh)
    -- No g2.bounds_set, no g2.planets_settle: confirmed from Aphid's
    -- galcon_classic_init() -- the trailing settle pass there explicitly
    -- excludes Stages and Classic-family styles ("gamemode ~= 'Classic'
    -- and ~= 'Stages'"), which covers every style this mod supports.
    -- Aphid's maps ship exactly as generated; no physics pass ever runs.
    -- That's exactly why the collision check above has to exist: nothing
    -- downstream will ever push overlapping planets apart.

end


function record_loop(t)
if g2.state ~= "play" then return end
rec_clock=rec_clock+t; rec_frame=rec_frame+1
rec_pos_frame=rec_pos_frame+1; rec_save_timer=rec_save_timer+t
local t_now = math.floor(rec_clock * 10) / 10
for _, p in ipairs(g2.search("planet")) do
local pid=p.n
end
local curr_fleets={}
for _,f in ipairs(g2.search("fleet")) do
local id=tostring(f.sync_id)
local fx=round(f.position_x); local fy=round(f.position_y)
local fs=round(f.fleet_ships)
curr_fleets[id]={id=id,x=fx,y=fy,ships=fs,owner=f.owner_n,target=f.fleet_target}
if not rec_prev_fleets[id] then
local rem=nil
for _,sp in ipairs(g2.search("planet owner:"..f.owner_n)) do
local dx=sp.position_x-f.position_x; local dy=sp.position_y-f.position_y
if math.sqrt(dx*dx+dy*dy)<60 then rem=math.floor(sp.ships_value); break end
end
rec_log_events[#rec_log_events+1]={e="fs",t=t_now,id=id,o=f.owner_n,s=fs,tg=f.fleet_target,x=fx,y=fy,rem=rem}
rec_log_pos[#rec_log_pos+1]={t_now,id,fx,fy,0}
else
local prev=rec_prev_fleets[id]
if prev.target~=f.fleet_target then rec_log_events[#rec_log_events+1]={e="fr",t=t_now,id=id,tg=f.fleet_target} end
if prev.ships~=fs then rec_log_events[#rec_log_events+1]={e="fu",t=t_now,id=id,s=fs} end
end
end
for id,pf in pairs(rec_prev_fleets) do
if not curr_fleets[id] then
rec_log_pos[#rec_log_pos+1]={t_now,id,pf.x,pf.y,0}
rec_log_events[#rec_log_events+1]={e="fd",t=t_now,id=id,tg=pf.target,o=pf.owner}
end
end
rec_prev_fleets=curr_fleets
for _,p in ipairs(g2.search("planet")) do
local pid=p.n; local owner=p.owner_n
rec_prev_planets[pid]=rec_prev_planets[pid] or {}
if rec_prev_planets[pid].owner~=nil and rec_prev_planets[pid].owner~=owner then
rec_log_events[#rec_log_events+1]={e="pc",t=t_now,n=pid,o=owner}
end
rec_prev_planets[pid].owner=owner
end
if rec_pos_frame >= POSITION_RATE then
rec_pos_frame=0
for id,f in pairs(curr_fleets) do rec_log_pos[#rec_log_pos+1]={t_now,id,f.x,f.y,0} end
for _,p in ipairs(g2.search("planet")) do rec_log_events[#rec_log_events+1]={e="pn",t=t_now,n=p.n,s=round(p.ships_value)} end
end
if rec_frame%6==0 and rec_game_users then
local p1=rec_game_users.p1; local p2=rec_game_users.p2
local ps,pp,es,ep=0,0,0,0
for _,p in ipairs(g2.search("planet")) do
local own=p.owner_n
if p1 and own==p1.n then ps=ps+round(p.ships_value); pp=pp+round(p.ships_production)
elseif p2 and own==p2.n then es=es+round(p.ships_value); ep=ep+round(p.ships_production) end
end
for _,f in ipairs(g2.search("fleet")) do
local own=f.owner_n
if p1 and own==p1.n then ps=ps+round(f.fleet_ships)
elseif p2 and own==p2.n then es=es+round(f.fleet_ships) end
end
rec_log_summary[#rec_log_summary+1]={t=math.floor(rec_clock*100)/100,ps=ps,pp=pp,es=es,ep=ep}
end
if #rec_log_events+#rec_log_pos>=CHUNK_SIZE or rec_save_timer>=1.0 then
rec_save_timer=0; flush_chunk(false)
end
end

-- Load saved stats every time this file runs -- including Galcon's automatic
-- mod refresh, which re-runs the file (recreating STATS empty) without
-- calling init().
pcall(function()
    local d = json.decode(g2.data)
    if type(d) == "table" then stats_load(d.stats) end
end)

function loop(t)  GAME.engine:loop(t)  end
function event(e)
    if e.type == "pause" then
        if e.uid and e.uid ~= HOST_UID then
            -- A remote spectator's own pause gesture -- let them re-summon
            -- the stats overlay (their next update_stats_html tick will
            -- push it again since resumed is now false).
            local c = GAME.clients[e.uid]
            if c then c.resumed = false end
            return
        end
                g2.state = "play"
            if GAME.galcon and GAME.galcon.p1 then
            GAME.host_paused = not GAME.host_paused
            if GAME.host_paused then
                local G  = GAME.galcon
                local ps = total_ships(G.p1)
                local es = G.p2 and total_ships(G.p2) or 0
                local pp = total_production(G.p1)
                local ep = G.p2 and total_production(G.p2) or 0
                g2.html = build_spectator_pause_html(G.p1, G.p2, ps, pp, es, ep)
            end
        end
        return
    end
    if e.type == "onclick" and e.value == "resume" then
        if e.uid and e.uid ~= HOST_UID then
            -- This is the bug fix: tell THIS client specifically to go back
            -- to the live view, and stop re-sending them the overlay.
            -- Previously this branch only ever touched host-only state, so
            -- a remote spectator's own Resume tap did nothing for them at
            -- all -- combined with update_stats_html's unconditional
            -- re-push, they were stuck on the stats screen until the match
            -- ended or they left and rejoined.
            local c = GAME.clients[e.uid]
            if c then c.resumed = true end
            net_send(e.uid, "state", "play")
            return
        end
            GAME.host_paused = false
        g2.state = "play"
        return
    end
    if e.type == "net:message" and e.value == "/hide_stats" then
        GAME.host_paused = false
        return
    end

    GAME.engine:event(e)
end
