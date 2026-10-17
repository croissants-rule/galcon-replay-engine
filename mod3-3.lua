strict(true)

local ROOM_TITLE    = "1v1 Replays"
local DEFAULT_PORT  = "23099"
local POSITION_RATE = 1   
local CHUNK_SIZE    = 200  
local WIN_CHECK_DELAY = 8.0

local SW, SH = 520, 360

local MAP = {
    neutrals   = 22,
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

local DEFAULT_ELO = 1200
local ELO_K       = 32
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

function apply_result(winner_uid, loser_uid, is_warmup)
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

    if is_warmup then return end  

    local delta = calc_elo_change(ws.elo, ls.elo)
    ws.elo = ws.elo + delta
    ls.elo = math.max(100, ls.elo - delta)

    table.insert(ws.history, {elo=ws.elo, vs=ls.name, won=true})
    table.insert(ls.history, {elo=ls.elo, vs=ws.name, won=false})

    net_send("", "message", string.format(
        "%s +%d ELO (%d)  ·  %s -%d ELO (%d)%s",
        ws.name, delta, ws.elo,
        ls.name, delta, ls.elo,
        GAME.warmup_mode and "  [WARMUP -- no ELO]" or ""
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

local HOST_UID  = nil   
local HOST_NAME = nil   

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
    -- Map style pool: which styles are active for non-ranked mode
    -- SaandBuff versions collectively count as ONE style slot (split equally among selected)
    GAME.map_styles = {
        stages   = false,
        classic  = true,
        philbuff = false,
        ["12p"]  = false,
        wonk     = false,
        sb       = {},   -- [1..13] true/false
    }
    for i = 1, 13 do GAME.map_styles.sb[i] = (i == 7) end  -- V7 on by default
    GAME.game_mode   = "standard"  

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

function build_colors_html(client, page)
local html="<table><tr><td><td><h2>Colors</h2><tr><td><td><input type='button' width=80 value='Back' onclick='/customize' class='ibutton1'/><tr><td><td><input type='button' width=80 value='Random' onclick='/setcolor:random' class='ibutton1'/>"
for _,row in ipairs(APHID_COLORS) do
html=html.."<tr>"
for _,c in ipairs(row) do html=html.."<td><input type='button' width=50 background='white:0x"..c.."' value=' ' onclick='/setcolor:"..c.."' class='ibutton1'/>" end
end
return html.."</table>"
end

function build_ships_html(client, page)
    page = page or 1
    local uid     = client and client.uid or ""
    local current = player_custom_ships[uid] or ""
    local per     = 12   
    local total   = #SHIP_NAMES
    local pages   = math.ceil(total / per)
    local from_i  = (page-1)*per + 1
    local to_i    = math.min(page*per, total)
    local html =
        "<table width=340>" ..
        "<tr><td colspan=3 align=center>" ..
            "<div font='font-outline:14' color='#44ccff'>Ships  " .. page .. "/" .. pages .. "</div>" ..
        "<tr><td colspan=3><input type='button' onclick='/customize' value='Back' " ..
            "class='ibutton1'/>"
    if current ~= "" then
        html = html ..
            "<tr><td colspan=3 align=center>" ..
            "<img src='ship" .. current .. "' width=72 height=72/>" ..
            "<div font='font-outline:12' color='#44ccff'>Active: ship-" .. current .. "</div>"
    end
    html = html .. "<tr><td><p>&nbsp;</p>"
    for i = from_i, to_i do
        local s = SHIP_NAMES[i]
        if (i - from_i) % 3 == 0 then html = html .. "<tr>" end
        local active = (s == current)
        html = html ..
            "<td width=113 align=center>" ..
            "<img src='ship" .. s .. "' width=80 height=80/>" ..
            "<input type='button' onclick='/setship:" .. s ..
            "' value='" .. (active and "ON" or "pick") ..
            "' class='" .. (active and "ibutton2" or "ibutton1") ..
            "' width=100/>"
    end
    html = html .. "<tr>"
    if page > 1 then
        html = html .. "<td colspan=2><input type='button' onclick='/ships:" .. (page-1) ..
            "' value='Prev' class='ibutton1' width=150/>"
    end
    if page < pages then
        html = html .. "<td><input type='button' onclick='/ships:" .. (page+1) ..
            "' value='Next' class='ibutton1' width=150/>"
    end
    return html .. "</table>"
end

function build_skins_html()
    return "<table width=340>" ..
        "<tr><td align=center><div font='font-outline:18' color='#44ccff'>Skins</div>" ..
        "<tr><td><input type='button' onclick='/customize' value='back' class='ibutton1'/>" ..
        "<tr><td><p>&nbsp;</p>" ..
        "<tr><td align=center><p>Planet skin customization coming soon!</p>" ..
        "</table>"
end

function hex_darken(col)
    local r = math.floor(math.floor(col / 0x10000) * 0.5)
    local g = math.floor(math.floor((col % 0x10000) / 0x100) * 0.5)
    local b = math.floor((col % 0x100) * 0.5)
    return string.format("%02x%02x%02x", r, g, b)
end

function make_player_row(c, opponent_uid)
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
        local tag = c.is_host and "[host]" or "[away]"
        return "<tr><td><table width=330 background='white:#2b2b2b'><tr>" ..
               "<td width=6><img src='blank' width=6 height=5>" ..
               "<td align=left clip=1><div font='font-outline:18' color='#777777'>" ..
               c.name .. " " .. tag .. "</div>" ..
               (info ~= "" and "<div font='font-outline:11' color='#555555'>" .. info:gsub("^ · ","") .. "</div>" or "") ..
               "</table>"
    end
end

function build_lobby_html(client)
    local queued    = count_queued()
    local is_queued = (client.status == "queue") and not (client.is_host == true)
    local is_away   = (client.status == "away")  or  (client.is_host == true)

    local start_btn = ""
    if queued >= 1 then
        start_btn = "<tr><td><input type='button' value='START' onclick='/start' icon='icon-play' class='ibutton1'/>"
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

    -- ── Big ranked / non-ranked toggle ───────────────────────────────────
    local rclass = GAME.ranked and "ibutton2" or "ibutton1"
    local rlabel = GAME.ranked and "RANKED MODE: ON" or "Regular Mode"
    html = html .. "<tr><td align=center>"
        .. "<input type='button' onclick='/toggle:ranked' value='" .. rlabel
        .. "' class='" .. rclass .. "' width=240/>"

    if GAME.ranked then
        -- Ranked: show rotation info, lock settings
        html = html
            .. "<tr><td><p>&nbsp;</p>"
            .. "<tr><td align=center><b>Ranked Map Rotation (ElimV2):</b>"
            .. "<tr><td><div font='font-gui2:13'>"
            .. "Stages 20%&nbsp;&nbsp;Philbuff 20%&nbsp;&nbsp;Classic 20%&nbsp;&nbsp;SaandBuff 20%&nbsp;&nbsp;12p 20%"
            .. "</div>"
            .. "<tr><td><p>&nbsp;</p>"
            .. "<tr><td align=center><i>Disable ranked to change map settings</i>"
    else
        -- Non-ranked: show style selector + SB versions + distance change
        local ms = GAME.map_styles

        local function tbtn(cmd, lbl, on)
            return "<input type='button' onclick='/toggle:" .. cmd .. "' value='" .. lbl
                .. "' class='" .. (on and "ibutton2" or "ibutton1") .. "' width=80/> "
        end

        html = html
            .. "<tr><td><p>&nbsp;</p>"
            .. "<tr><td><b>Map Styles:</b>"
            .. "<tr><td>"
            .. tbtn("stages",   "Stages",   ms.stages)
            .. tbtn("classic",  "Classic",  ms.classic)
            .. tbtn("philbuff", "Philbuff", ms.philbuff)
            .. tbtn("12p",      "12 Planet",ms["12p"])
            .. tbtn("wonk",     "Wonk",     ms.wonk)

        -- SaandBuff versions
        html = html
            .. "<tr><td><b>SaandBuff Versions (share 1 slot equally):</b>"
            .. "<tr><td>"
        for v = 1, 13 do
            local on = ms.sb[v]
            html = html
                .. "<input type='button' onclick='/toggle:sb" .. v
                .. "' value='V" .. v
                .. "' class='" .. (on and "ibutton2" or "ibutton1") .. "' width=40/>"
        end

        -- Distance Change toggle
        html = html
            .. "<tr><td><p>&nbsp;</p>"
            .. "<tr><td align=center>"
            .. "<input type='button' onclick='/toggle:distance' value='Distance Change: "
            .. (GAME.distance_change and "ON ✓" or "OFF")
            .. "' class='" .. (GAME.distance_change and "ibutton2" or "ibutton1") .. "' width=240/>"
            .. "<tr><td><div font='font-gui2:12'><i>"
            .. "Prod increases + cost decreases with distance from home &amp; other planets"
            .. "</i></div>"
    end

    html = html
        .. "<tr><td><p>&nbsp;</p>"
        -- Warmup / ELO toggle
        .. "<tr><td align=center>"
        .. "<input type='button' onclick='/warmup' class='ibutton"
        .. (GAME.warmup_mode and "2' icon='icon-away' value='WARM-UP (no ELO)" or "1' icon='icon-play' value='RANKED ELO active")
        .. "' width=200/>"
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

    local warmup_note = GAME.warmup_mode and
        "<p><div color='#ffaa44'>WARM-UP -- ELO paused</div></p>" or ""

    return "<table width=340>" ..
        "<tr><td>" .. nav ..
        "<tr><td><p>&nbsp;</p>" ..
        "<tr><td align=center>" .. ship_html ..
            "<div font='font-outline:28' color='" .. col .. "'>" .. s.name .. "</div>" ..
        "<tr><td align=center><div font='font-outline:18' color='#44ccff'>ELO: "..s.elo.."</div>" ..
        "<tr><td align=center><p>" ..
            s.wins.."W -- "..s.losses.."L -- "..wpct.."% -- Streak: "..strk_txt ..
        "</p>" ..
        warmup_note ..
        "<tr><td><p>&nbsp;</p>" ..
        "<tr><td><b>H2H Record</b>" ..
        "<tr><td><table width=300>" ..
            "<tr><td><b>vs Player</b><td><b>Record</b>" ..
            h2h_html ..
        "</table>" ..
        "</table>"
end

function build_ranks_html()
    local sorted={}
    for uid,s in pairs(STATS) do table.insert(sorted,{uid=uid,s=s}) end
    table.sort(sorted,function(a,b) return a.s.elo>b.s.elo end)
    local mode_lbl=GAME.warmup_mode and "<div color='#ffaa44'>WARM-UP</div>" or "<div color='#44ccff'>RANKED</div>"
    local out="<table width=340><tr><td><h2>Rankings</h2><tr><td>"..mode_lbl.."<tr><td><p>&nbsp;</p>"
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
            "<td><div color='"..col.."' font='font-outline:18'>"..s.name..streak_emoji(s.streak).."</div>" ..
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
    local G         = GAME.galcon
    local is_solo   = G and #(G.users or {}) <= 1
    local end_label = is_solo and "End + Replay" or "Surrender"
    return [[
        <tr><td align=center><input type='button' class='ibutton1' value=']] .. end_label .. [['   onclick='/surrender'  icon='icon-surrender'/>
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
    elseif win == "customize" then
        body = build_customize_html(fake_c)
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
        body = build_ships_html(c, pg)
    elseif win == "skins" then
        body = build_skins_html()
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
        GAME.data = json.decode(g2.data)
        if type(GAME.data) ~= "table" then GAME.data = {} end
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
            g2.data        = json.encode(GAME.data)
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
GAME.host_window="colors"; update_host_html()
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
if e.value == "/skins"     then switch_window("skins");     return end
if e.value == "/help"      then switch_window("help");      return end
if e.value == "/warmup" then
GAME.warmup_mode = not GAME.warmup_mode
broadcast_html()
net_send("", "message", GAME.warmup_mode
and "WARM-UP MODE ON -- games won't affect ELO"
or  "RANKED MODE -- ELO active")
return
end
end
if e.type == "net:message" then
local v = e.value
local lv = v:lower():gsub("^%s+","")
if lv:find("^/play") == 1 then
local c = GAME.clients[e.uid]
if c and not c.is_host then
c.status = "queue"
clients_assign_colors()
net_send("", "message", e.name .. " is /play")
broadcast_html()
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

function lobby_init()
GAME.modules.lobby = {}
local obj          = GAME.modules.lobby
function obj:init()
g2.state = "lobby"
params_set("state", "lobby")
GAME.host_window = GAME.host_window or "lobby"
broadcast_html()
end
function obj:loop(t) end
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
                if what == "ranked" then
                    GAME.ranked = not GAME.ranked
                    net_send("","message","[RANKED] Ranked " .. (GAME.ranked and "ON - ElimV2 rotation, settings locked." or "OFF - custom map pool active."))
                elseif what == "distance" then
                    if GAME.ranked then net_send("","message","Distance Change not available in ranked.") return end
                    GAME.distance_change = not GAME.distance_change
                    net_send("","message","Distance Change: " .. (GAME.distance_change and "ON" or "OFF"))
                elseif what == "stages" or what == "classic" or what == "philbuff" or what == "12p" or what == "wonk" then
                    if GAME.ranked then net_send("","message","Settings locked in ranked mode.") return end
                    GAME.map_styles[what] = not GAME.map_styles[what]
                    net_send("","message",what .. ": " .. (GAME.map_styles[what] and "ON" or "OFF"))
                elseif what:sub(1,2) == "sb" then
                    local v = tonumber(what:sub(3))
                    if v and v >= 1 and v <= 13 then
                        if GAME.ranked then net_send("","message","Settings locked in ranked mode.") return end
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
g2.data = json.encode({batch_end = true})
else
net_send(e.uid, "message", "No batch is currently active.")
end
return
end
if lv == "/start" or lv:find("^/start") == 1 then
if count_queued() >= 1 then
GAME.engine:next(GAME.modules.galcon)
else
net_send(e.uid, "message", "No queued players. Type /play first.")
end
elseif lv:sub(1, 10) == "/setcolor:" then
local hex = lv:sub(11)
if hex == "pick" then
local raw = g2.form.colorpick or ""
raw = raw:gsub("^#",""):lower()
if #raw == 6 then hex = raw else hex = nil end
elseif hex == "custom" then
local raw = g2.form.hexcolor or ""
raw = raw:gsub("#",""):gsub("%s",""):lower()
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
hex = nil
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
end
elseif lv == "/gg" then
net_send("", "message", e.name .. ": gg")
end
if lv:find("^/play") == 1 or lv == "/away" then
if count_queued() >= 2 then
GAME.engine:next(GAME.modules.galcon)
end
end
end
end
end

function find_user(uid)
    for _, u in ipairs(g2.search("user")) do
        if u.user_uid == uid then return u end
    end
end

function galcon_surrender(uid)
    local user    = find_user(uid)
    if not user then return end
    local neutral = GAME.galcon and GAME.galcon.neutral
    if neutral then
        for _, p in ipairs(g2.search("planet owner:" .. user)) do
            p:planet_chown(neutral)
        end
    end
end

function galcon_stop(winner_user)
    flush_chunk(true)
    local winner_uid = winner_user and winner_user.user_uid or nil
    if winner_uid and GAME.player_uids then
        local loser_uid = nil
        for _, uid in ipairs(GAME.player_uids) do
            if uid ~= winner_uid then loser_uid = uid; break end
        end
        if loser_uid then
pcall(function()
                apply_result(winner_uid, loser_uid, GAME.warmup_mode or not GAME.ranked)
            end)
        end
        net_send("", "message", winner_user.title_value .. " conquered the galaxy!" .. (GAME.ranked and "  [RANKED]" or ""))
    else
        net_send("", "message", "Game over.")
    end
    net_send("", "sfx", "stop")
    for _, c in pairs(GAME.clients) do
        if c.status == "play" then c.status = "queue" end
    end
    clients_assign_colors()
    GAME.engine:next(GAME.modules.lobby)
end

function stages_loop(t, G)
    G.stages_timer = (G.stages_timer or 0) + t
    local st = G.stages_timer

    local LOCK_SHIPS = 999
    if G.neutral_hide then
        for _,e in ipairs(g2.search("planet owner:"..G.neutral_hide.n)) do
            if e.ships_value < LOCK_SHIPS then e.ships_value = LOCK_SHIPS end
        end
    end
    if G.neutral_hide2 then
        for _,e in ipairs(g2.search("planet owner:"..G.neutral_hide2.n)) do
            if e.ships_value < LOCK_SHIPS then e.ships_value = LOCK_SHIPS end
        end
    end

    if not G.stage2_done and st > 30 then
        G.stage2_done = true
        if G.neutral_hide then
            for _,e in ipairs(g2.search("planet owner:"..G.neutral_hide.n)) do
                e:planet_chown(G.neutral)
                            e.ships_value = getSaandbuffVals(GAME.last_ver, math.floor(e.ships_production))
            end
        end
        net_send("","message","[STAGES] New planets unlocked!")
    end

    if not G.stage3_done and st > 60 then
        G.stage3_done = true
        if G.neutral_hide2 then
            for _,e in ipairs(g2.search("planet owner:"..G.neutral_hide2.n)) do
                e:planet_chown(G.neutral)
                e.ships_value = getSaandbuffVals(GAME.last_ver, math.floor(e.ships_production))
            end
        end
        net_send("","message","[STAGES] More planets unlocked!")
    end

    if st > 90 then
        G.stage4_timer = (G.stage4_timer or 0) + t
        if G.stage4_timer > 5 then
            G.stage4_timer = 0
            for _,e in ipairs(g2.search("planet owner:"..G.neutral.n)) do
                if e.ships_value > 0 then e.ships_value = e.ships_value - 1 end
            end
        end
    end
    if not G.stage4_announced and st > 90 then
        G.stage4_announced = true
        net_send("","message","[STAGES] Neutral planets weakening...")
    end

    if not G.stage5_done and st > 120 then
        G.stage5_done = true
        for _,e in ipairs(g2.search("user")) do e.fleet_v_factor = 1.5 end
        net_send("","message","[STAGES] Fleets accelerated!")
    end

    if st > 150 then
        G.stage6_timer = (G.stage6_timer or 0) + t
        if G.stage6_timer > 10 then
            G.stage6_timer = 0
            for _,e in ipairs(g2.search("planet")) do
                if e.ships_production > 1 then e.ships_production = e.ships_production - 1 end
            end
        end
    end
    if not G.stage6_announced and st > 150 then
        G.stage6_announced = true
        net_send("","message","[STAGES] Planet production decaying...")
    end
end

function galcon_check_winner()
    local G       = GAME.galcon
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
local nh  = g2.new_user("neutral_hide",  0x111111)
nh.user_neutral  = 1; nh.ships_production_enabled = 0
local nh2 = g2.new_user("neutral_hide2", 0x222222)
nh2.user_neutral = 1; nh2.ships_production_enabled = 0
G.neutral_hide   = nh;  G.stages_nh  = nh
G.neutral_hide2  = nh2; G.stages_nh2 = nh2
G.stages_timer   = 0
end
local player_clients = {}
for _, uid in ipairs(GAME.client_order) do
local c = GAME.clients[uid]
if c and c.status == "queue" and not c.is_host then
player_clients[#player_clients + 1] = c
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
G.users[i] = u
GAME.clients[c.uid].status = "play"
GAME.clients[c.uid].color  = col
end
GAME.player_uids = {}
for i2, c2 in ipairs(player_clients) do
GAME.player_uids[i2] = c2.uid
end
G.p1 = G.users[1]
G.p2 = G.users[2]
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
local p1_uid   = G.users[1] and G.users[1].user_uid or ""
local p2_uid   = G.users[2] and G.users[2].user_uid or ""
local p1_color = "00ff88"
local p2_color = "ff4455"
for uid, c in pairs(GAME.clients) do
local hex = string.format("%06x", c.color or 0x555555)
if uid == p1_uid then p1_color = hex
elseif uid == p2_uid then p2_color = hex end
end
g2.data = json.encode({
payload = {
chunk=0, final=false, status="part0",
map=map_planets,
player_n=rec_player1_n, enemy_n=rec_player2_n,
player_name=p1_name, enemy_name=p2_name,
batch_mode=(GAME.batch_mode and true or false),
player_color=p1_color, enemy_color=p2_color,
version=1, w=SW, h=SH,
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
if G.win_check_timer >= WIN_CHECK_DELAY then galcon_check_winner() end
end
function obj:event(e)
if e.type == "net:leave" then
galcon_surrender(e.uid)
if (GAME.galcon.win_check_timer or 0) >= WIN_CHECK_DELAY then
galcon_check_winner()
end
end
if e.type == "net:message" then
local lv = e.value:lower():gsub("^%s+","")
if lv == "/surrender" then
local G = GAME.galcon
if #G.users <= 1 then
galcon_stop(nil)
else
galcon_surrender(e.uid)
if (GAME.galcon.win_check_timer or 0) >= WIN_CHECK_DELAY then
galcon_check_winner()
end
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
    local c = GAME.clients and user.user_uid and GAME.clients[user.user_uid]
    if c and c.color then return "#" .. int_to_hex(c.color) end
    return fallback or "#888888"
end

function build_spectator_html(p1,p2,ps,pp,es,ep)
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
    "</table>"
end

function build_spectator_pause_html(p1, p2, ps, pp, es, ep)
    return build_spectator_html(p1, p2, ps, pp, es, ep) ..
        "<table align=right><tr><td>" ..
        "<input type='button' value='Resume' onclick='resume' class='ibutton1' width=80 height=32/>" ..
        "</table>"
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
            g2.net_send(c.uid,"status",sl)
            g2.net_send(c.uid,"html",ph)
            g2.net_send(c.uid,"tabs",build_spectator_game_tabs())
        end
    end
    g2.status=sl
    if GAME.host_paused then g2.html=ph end
end

function getV11Cost(prod, meanProd)
    local ref   = meanProd or 70
    local ratio = prod / ref
    local cost
    if ratio < 0.60 then
        cost = math.floor(math.random(0, 8))
    elseif ratio < 0.90 then
        cost = math.floor(math.random(8, 20))
    elseif ratio < 1.20 then
        cost = math.floor(math.random(20, 40))
    else
        cost = math.floor(math.random(40, 70))
    end
    return cost
end

function getV11Cost(prod, meanProd)
    local ref = meanProd or 70
    local ratio = prod / ref
    if ratio < 0.60 then
        return math.floor(math.random(0, 8))
    elseif ratio < 0.90 then
        return math.floor(math.random(8, 20))
    elseif ratio < 1.20 then
        return math.floor(math.random(20, 40))
    else
        return math.floor(math.random(40, 70))
    end
end

function getSaandbuffVals(v,p,m)
local t={
[1]={{30,51,5,10},{51,76,11,30},{76,90,31,55},{90,101,56,75}},
[2]={{30,46,5,10},{46,61,11,20},{61,76,21,35},{76,86,36,50},{86,101,51,70}},
[3]={{30,51,1,5},{51,71,6,15},{71,86,16,35},{86,101,36,60}},
[4]={{30,46,15,25},{46,61,26,40},{61,76,41,55},{76,86,56,70},{86,101,71,90}},
[5]={{30,51,20,40},{51,71,41,65},{71,86,66,85},{86,101,86,110}},
[6]={{30,51,5,15},{51,71,16,30},{71,86,31,50},{86,101,51,75}},
[7]={{30,46,5,15},{46,61,16,25},{61,71,26,35},{71,81,36,50},{81,91,51,65},{91,101,66,85}},
[8]={{30,51,10,20},{51,71,21,40},{71,86,41,60},{86,101,61,85}},
[9]={{30,46,3,8},{46,61,9,18},{61,76,19,32},{76,86,33,48},{86,101,49,70}},
[10]={{30,51,8,18},{51,71,19,35},{71,86,36,55},{86,101,56,80}},
[11]={},
[12]={{30,51,5,12},{51,71,13,28},{71,86,29,48},{86,101,49,72}},
[13]={{30,46,4,9},{46,61,10,20},{61,76,21,36},{76,86,37,52},{86,101,53,75}},
}
if v==11 then
local base=math.floor(math.random(5,15))
local bonus=math.floor(((p-(m or p))/(100-30+1))*20)
return math.max(1,base+bonus)
end
local rows=t[v] or t[7]
for _,r in ipairs(rows) do
if p>=r[1] and p<r[2] then return math.floor(math.random(r[3],r[4])) end
end
return math.floor(math.random(5,20))
end

function reset_recording()
    rec_clock=0; rec_frame=0; rec_pos_frame=0; rec_save_timer=0
    rec_chunk_index=1; rec_log_events={}; rec_log_pos={}
    rec_log_summary={}; rec_prev_fleets={}; rec_prev_planets={}
end

function flush_chunk(final)
    local t_now = math.floor(rec_clock * 10) / 10
    for id, f in pairs(rec_prev_fleets) do
        rec_log_pos[#rec_log_pos+1] = { t_now, id, f.x, f.y, 0 }
    end
    if #rec_log_events + #rec_log_pos == 0 and not final then return end
    local existing     = json.decode(g2.data) or {}
    existing.payload   = {
        chunk=rec_chunk_index, final=final and true or false,
        status="part"..rec_chunk_index,
        events=rec_log_events, pos=rec_log_pos,
    }
    existing.summary   = rec_log_summary
    g2.data            = json.encode(existing)
    rec_log_events     = {}
    rec_log_pos        = {}
    rec_chunk_index    = rec_chunk_index + 1
end




-- Pick the next map style from the non-ranked pool.
-- All non-SB styles each count as 1 slot. All selected SaandBuff versions
-- collectively count as 1 slot, split equally among them.
-- Returns: style, ver (nil if not SB), is_stages (bool)
function pick_random_style()
    local pool     = {}
    local sb_pool  = {}
    local ms = GAME.map_styles
    if ms.stages    then pool[#pool+1] = "stages"   end
    if ms.classic   then pool[#pool+1] = "classic"  end
    if ms.philbuff  then pool[#pool+1] = "philbuff" end
    if ms["12p"]    then pool[#pool+1] = "12p"      end
    if ms.wonk      then pool[#pool+1] = "wonk"     end
    for v = 1, 13 do
        if ms.sb[v] then sb_pool[#sb_pool+1] = v end
    end
    if #sb_pool > 0 then pool[#pool+1] = "_sb" end

    if #pool == 0 then return "saandbuff", 7, false end  -- fallback

    local pick = pool[math.random(1, #pool)]
    if pick == "_sb" then
        return "saandbuff", sb_pool[math.random(1, #sb_pool)], false
    elseif pick == "stages" then
        -- Stages uses SaandBuff costs (random version, or V7 if none selected)
        local sver = #sb_pool > 0 and sb_pool[math.random(1,#sb_pool)] or 7
        return "saandbuff", sver, true
    else
        return pick, nil, false
    end
end

-- Ranked uses ElimV2: Stages, Philbuff, Classic, SaandBuff, 12p (20% each)
function pick_ranked_style()
    local ranked_pool = {"stages", "philbuff", "classic", "saandbuff", "12p"}
    local pick = ranked_pool[math.random(1, #ranked_pool)]
    if pick == "stages" then
        return "saandbuff", math.random(1, 13), true
    elseif pick == "saandbuff" then
        return "saandbuff", math.random(1, 13), false
    else
        return pick, nil, false
    end
end


function build_map(neutral, player_users, neutral_hide, neutral_hide2)
    local sw, sh, pad = SW, SH, MAP.pad

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

    -- Map size adjustments
    if style == "classic" then
        sw = sw / 1.1;  sh = sh / 1.1
    elseif style == "12p" then
        sw = sw / 1.25; sh = sh / 1.25
    end

    -- Generate production values for each pair
    local prods = {}
    for i = 1, npairs do
        prods[i] = (style == "wonk") and math.random(1, 100) or math.random(MAP.prod_min, MAP.prod_max)
    end
    local tot = 0
    for _, p in ipairs(prods) do tot = tot + p end
    local mean_prod = tot / #prods

    -- Place neutral planet pairs (symmetric)
    for i = 1, npairs do
        local prod = prods[i]
        local cost
        if style == "classic" then
            cost = math.random(0, 30)
        elseif style == "philbuff" then
            cost = math.floor(math.random(math.floor(prod / 20), math.floor(prod / 1.50)))
        elseif style == "12p" then
            cost = math.random(0, 20)
        elseif style == "wonk" then
            cost = math.random(0, math.max(1, math.floor(home_ships * 0.5)))
        else  -- saandbuff (used for SB, stages, default)
            cost = getSaandbuffVals(ver, prod, mean_prod)
        end

        local x = math.random(pad, math.floor(sw) - pad)
        local y = math.random(pad, math.floor(sh) - pad)
        local owner, ships = neutral, cost

        -- Stages: lock early pairs
        if neutral_hide  and i <= 4 then owner = neutral_hide;  ships = 999
        elseif neutral_hide2 and i <= 7 then owner = neutral_hide2; ships = 999
        end

        g2.new_planet(owner, x,              y,              prod, ships)
        g2.new_planet(owner, math.floor(sw) - x, math.floor(sh) - y, prod, ships)
    end

    -- Home planets
    local nplayers = #player_users
    local angle_offset = math.random(0, 360)
    for i, u in ipairs(player_users) do
        local angle = angle_offset + (i - 1) * (360 / nplayers)
        local hx = sw / 2 + (sw - pad * 2) * math.cos(angle * math.pi / 180.0) / 2.0
        local hy = sh / 2 + (sh - sh / 15 * 2) * math.sin(angle * math.pi / 180.0) / 2.0
        g2.new_planet(u, math.floor(hx), math.floor(hy), home_prod, home_ships)
    end

    g2.planets_settle(0, 0, math.floor(sw), math.floor(sh))
    g2.view_set(0, 0, math.floor(sw), math.floor(sh))

    -- ── Distance Change post-processing ──────────────────────────────────
    -- Applied AFTER planets_settle so positions are final.
    -- Prod increases further from home / other planets.
    -- Cost decreases further from home / other planets (can go below initial range).
    if GAME.distance_change then
        -- Find home planets
        local home1, home2 = nil, nil
        for _, p in ipairs(g2.search("planet")) do
            if #player_users >= 1 and player_users[1] and p.owner_n == player_users[1].n then
                home1 = p
            end
            if #player_users >= 2 and player_users[2] and p.owner_n == player_users[2].n then
                home2 = p
            end
        end
        if home1 and home2 then
            local all_planets = g2.search("planet")
            local map_diag = math.sqrt(sw * sw + sh * sh)
            local norm_home = map_diag * 0.45  -- distance at which home_factor = 1
            local norm_iso  = map_diag * 0.12  -- isolation distance at which iso_factor = 1

            for _, p in ipairs(all_planets) do
                if p.owner_n == neutral.n then  -- only neutrals
                    -- Distance to nearest home
                    local d1 = math.sqrt((p.position_x - home1.position_x)^2 + (p.position_y - home1.position_y)^2)
                    local d2 = math.sqrt((p.position_x - home2.position_x)^2 + (p.position_y - home2.position_y)^2)
                    local home_factor = math.min(math.min(d1, d2) / norm_home, 1.0)

                    -- Distance to nearest other planet
                    local nearest = map_diag
                    for _, other in ipairs(all_planets) do
                        if other.n ~= p.n then
                            local dd = math.sqrt((p.position_x - other.position_x)^2 + (p.position_y - other.position_y)^2)
                            if dd < nearest then nearest = dd end
                        end
                    end
                    local iso_factor = math.min(nearest / norm_iso, 1.0)

                    -- Cost: cheaper farther from home; additionally cheaper if isolated (up to -5)
                    local new_cost = math.max(0, math.floor(
                        p.ships_value * (1.0 - home_factor * 0.85) - iso_factor * 5
                    ))
                    p.ships_value = new_cost

                    -- Prod: higher farther from home and isolated
                    local prod_boost = math.floor((home_factor * 0.65 + iso_factor * 0.35) * (MAP.prod_max - p.ships_production))
                    p.ships_production = math.min(MAP.prod_max, p.ships_production + prod_boost)
                end
            end
        end
    end
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

function loop(t)  GAME.engine:loop(t)  end
function event(e)
    if e.type == "pause" then
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
