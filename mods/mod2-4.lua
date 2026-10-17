strict(true)

local ROOM_TITLE    = "Bot Room"
local DEFAULT_PORT  = "23100"
local POSITION_RATE = 1
local CHUNK_SIZE    = 200
local WIN_CHECK_DELAY = 8.0
local BOT_AUTO_START_DELAY = 3.0

local SW, SH = 520, 360

local MAP = {
    neutrals   = 25,
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
    "7f0000","ff0000","ff7f7f","7f3f00","ff7f00","ffbf7f",
    "7f7f00","feff00","feff7f","3f7f00","7fff00","bfff7f",
    "007f00","00ff00","7fff7f","007f7f","00feff","7ffeff",
    "003f7f","007fff","7fbfff","00007f","0000ff","7f7fff",
    "3f007f","7f00ff","bf7fff","7f007f","ff00fe","ff7ffe",
}
local GALCON_COLORS = ALL_COLORS
local GALCON_COLOR_NAMES = {}
local PRESET_COLORS = ALL_COLORS

local player_custom_colors = {}
local player_custom_ships  = {}
local player_custom_skins  = {}

local SHIP_NAMES = {
    "f17","f16","f15","f14","f13","f12","f11","f10","f9","f8","f7","f6","f5","f4","f3","f2","f1",
    "dis1","dec6","dec5","dec4","dec3","dec2","dec1","22c","22b","110","109","108","107","106","105",
    "104","103","102","101","80","79","78","77","76","70","69","68","67","66","60","59","58","50",
    "49","48","47","46","45","44","43","42","41","40","39","38","37","36","35","34","33","32","31",
    "30","29","28","27","26","25","24","23","22","21","20","19","18","17","16","15","14","13","12",
    "11","10","9","8","7","6","5","4","3","2","1","0",
}

local SKIN_NAMES = {
    "normal","honeycomb","ice","terrestrial","gasgiant","craters","gaseous","lava","void","disco",
    "swirls","floralpattern","hearts","clovers","zerba","giraffe","eyes","cow","fossil","snowcaps",
    "smooth","whisp","charlie","snowflake","candycane","snowglobe",
}

local SKIN_LABELS = {
    normal="Normal",honeycomb="Honeycomb",ice="Ice",terrestrial="Terrestrial",gasgiant="Gas Giant",
    craters="Craters",gaseous="Gaseous",lava="Lava",void="Void",disco="Disco",swirls="Swirls",
    floralpattern="Floral",hearts="Hearts",clovers="Clovers",zerba="Zebra",giraffe="Giraffe",
    eyes="Eyes",cow="Cow",fossil="Fossil",snowcaps="Snowcaps",smooth="Smooth",whisp="Whisp",
    charlie="Charlie",snowflake="Snowflake",candycane="Candycane",snowglobe="Snowglobe",
}

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

local HOST_UID  = nil
local HOST_NAME = nil

function init()
    global("GAME"); GAME = {}
    g2.console = 0
    HOST_UID  = g2.uid
    HOST_NAME = g2.name
    GAME.host_window         = "lobby"
    GAME.host_color          = 0x00ff88
    GAME.batch_mode          = false
    GAME.distance_change     = false
    GAME.distance_strength   = 1.0
    GAME.distance_isolation  = 1.0
    GAME.last_style          = "philbuff"
    GAME.last_ver            = nil
    GAME.start_countdown_seconds = 3

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
        customize= (w=="customize") and "tab0" or "tab",
    }
    local status_icon = "icon-" .. (client.status or "queue")
    return "<table><tr>" ..
        "<td><input width='20%' type='button' disabled='true' pseudo='first' class='tab'/>" ..
        "<td><input width='20%' type='button' onclick='/lobby'    value='Lobby'    icon='icon-lobby'     class='" .. cl.lobby    .. "'/>" ..
        "<td><input width='20%' type='button' onclick='/status'   value='Settings' icon='" .. status_icon .. "' class='" .. cl.settings  .. "'/>" ..
        "<td><input width='20%' type='button' onclick='/profile'  value='Profile'  icon='icon-profile'   class='" .. cl.profile  .. "'/>" ..
        "<td><input width='20%' type='button' onclick='/customize' value='Customize' icon='icon-galaxy' pseudo='last' class='" .. cl.customize .. "'/>" ..
    "</table>"
end

function build_customize_html(client)
    return "<table width=340>" ..
        "<tr><td align=center><div font='font-outline:22' color='#44ccff'>Customize</div>" ..
        "<tr><td><input type='button' onclick='/lobby' value='Back' icon='icon-resume' class='ibutton1'/>" ..
        "<tr><td><p>&nbsp;</p>" ..
        "<tr><td><input type='button' onclick='/colors' value='COLORS' icon='icon-galaxy' class='ibutton1'/>" ..
        "<tr><td><input type='button' onclick='/ships' value='SHIPS' icon='icon-galaxy' class='ibutton1'/>" ..
        "<tr><td><input type='button' onclick='/skins' value='SKINS' icon='icon-galaxy' class='ibutton1'/>" ..
        "<tr><td><p>&nbsp;</p>" ..
        "</table>"
end

local FLAT_COLORS = {}
for _, row in ipairs(APHID_COLORS) do
    for _, c in ipairs(row) do
        FLAT_COLORS[#FLAT_COLORS + 1] = c
    end
end

function build_colors_html(client, page)
    page = page or 1
    local per   = 15
    local total = #FLAT_COLORS
    local pages = math.ceil(total / per)
    local from_i = (page - 1) * per + 1
    local to_i   = math.min(page * per, total)
    local html =
        "<table width=340>" ..
        "<tr><td colspan=3 align=center><h2>Colors</h2>" ..
        "<tr><td colspan=3><input type='button' width=100 value='Back' onclick='/customize' class='ibutton1'/>" ..
        "<td colspan=1><input type='button' width=100 value='Random' onclick='/setcolor:random' class='ibutton1'/>" ..
        "<tr><td colspan=3><p>&nbsp;</p>" ..
        "<tr><td colspan=3><div font='font-outline:12' color='#aaaaaa'>" ..
            "Type a 6-character hex code then tap Set -- e.g. ff8800 for orange." ..
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

function make_player_row(c)
    if c.status == "queue" and not c.is_host then
        local col = "#" .. int_to_hex(c.color)
        local bg  = "#" .. hex_darken(c.color)
        return "<tr><td><table width=330 background='white:" .. bg .. "'><tr>" ..
               "<td width=6><img src='blank' width=6 height=5>" ..
               "<td align=left clip=1><div font='font-outline:18' color='" .. col .. "'>" ..
               c.name .. " [spectate]</div>" ..
               "</table>"
    else
        local tag = c.is_host and "[host]" or "[away]"
        return "<tr><td><table width=330 background='white:#2b2b2b'><tr>" ..
               "<td width=6><img src='blank' width=6 height=5>" ..
               "<td align=left clip=1><div font='font-outline:18' color='#777777'>" ..
               c.name .. " " .. tag .. "</div>" ..
               "</table>"
    end
end

function build_lobby_html(client)
    local queued    = count_queued()
    local is_queued = (client.status == "queue") and not (client.is_host == true)
    local is_away   = (client.status == "away")  or  (client.is_host == true)

    local play_class = is_queued and "ibutton2" or "ibutton1"
    local away_class = is_away   and "ibutton2" or "ibutton1"

    local rows = "<tr><td><h2>SPECTATORS</h2>"
    for _, uid in ipairs(GAME.client_order) do
        local c = GAME.clients[uid]
        if c then rows = rows .. make_player_row(c) end
    end

    local action_btns = ""
    if not (client.is_host == true) then
        action_btns = [[
        <tr><td><input type='button' value='SPECTATE' onclick='/play' icon='icon-play' class=']] .. play_class .. [['/>
        <tr><td><input type='button' value='AWAY'     onclick='/away' icon='icon-away' class=']] .. away_class .. [['/>
        <tr><td><input type='button' value='GG'       onclick='/gg'   icon='icon-leave' class='ibutton1'/>]]
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
        <tr><td align=center><h2>Bot Room</h2>
        <tr><td align=center><p>Bot vs Bot · Philbuff · Auto-starting...</p>
        ]] .. action_btns .. [[
        <tr><td><p>&nbsp;</p>
        ]] .. rows .. [[
        <tr><td><p>&nbsp;</p>
    ]] .. batch_toggle_btn .. end_batch_btn
end

function build_status_html(client)
    local html = "<table width=340>"
    html = html .. "<tr><td><h2>Settings</h2>"

    html = html .. "<tr><td colspan=3><p>&nbsp;</p>"
        .. "<tr><td align=center><table><tr>"
        .. "<td><input type='button' width=50 value='-' onclick='/toggle:countdown_dec' class='ibutton1'/>"
        .. "<td><div font='font-outline:14' color='#44ccff'>Auto-start Delay: " .. GAME.start_countdown_seconds .. "s</div>"
        .. "<td><input type='button' width=50 value='+' onclick='/toggle:countdown_inc' class='ibutton1'/>"
        .. "</table>"

    html = html
        .. "<tr><td colspan=3><p>&nbsp;</p>"
        .. "<tr><td colspan=3 align=center>"
        .. "<div font='font-outline:13' color='#44ccff'>Map Style: Philbuff (locked)</div>"

    -- Distance Change toggle
    html = html
        .. "<tr><td colspan=3><p>&nbsp;</p>"
        .. "<tr><td colspan=3 align=center>"
        .. "<input type='button' onclick='/toggle:distance' value='Distance Change: "
        .. (GAME.distance_change and "ON ✓" or "OFF")
        .. "' class='" .. (GAME.distance_change and "ibutton2" or "ibutton1") .. "' width=240/>"
        .. "<tr><td colspan=3><div font='font-gui2:12'><i>"
        .. "Prod increases + cost decreases with distance from home &amp; other planets"
        .. "</i></div>"

    if GAME.distance_change then
        html = html
            .. "<tr><td colspan=3><p>&nbsp;</p>"
            .. "<tr><td colspan=2><b>Frontier Bonus: " .. string.format("%.1f", GAME.distance_strength) .. "</b>"
            .. "<td><input type='button' width=70 value='Reset' onclick='/toggle:frontier_reset' class='ibutton1'/>"
            .. "<tr><td colspan=3><input type='slider' onchange=\"/frontierbonus {$frontierbonus}\" value='"
            .. math.floor(GAME.distance_strength * 10 + 0.5) .. "' name='frontierbonus' low=0 high=20/>"
            .. "<tr><td colspan=3><p>&nbsp;</p>"
            .. "<tr><td colspan=2><b>Isolation: " .. string.format("%.1f", GAME.distance_isolation) .. "</b>"
            .. "<td><input type='button' width=70 value='Reset' onclick='/toggle:isolation_reset' class='ibutton1'/>"
            .. "<tr><td colspan=3><input type='slider' onchange=\"/isolation {$isolation}\" value='"
            .. math.floor(GAME.distance_isolation * 10 + 0.5) .. "' name='isolation' low=0 high=20/>"
    end

    html = html
        .. "<tr><td><p>&nbsp;</p>"
        .. "<tr><td align=center><input type='button' class='ibutton1'"
        .. " value='Back' onclick='*lobby\t' icon='icon-restart'/>"
        .. "</table>"
    return html
end

function build_profile_html(client)
    local uid   = client.profile_uid or client.uid
    local pc    = GAME.clients[uid]
    local pname = pc and pc.name or "?"

    local nav = "<input type='button' onclick='/customize' value='Customize' icon='icon-galaxy' class='ibutton1'/>"
    if client.profile_uid and client.profile_uid ~= client.uid then
        nav = "<input type='button' onclick='/profile' value='&lt; Back' class='ibutton1'/>  " .. nav
    end

    local ship_html = ""
    local cur_ship = player_custom_ships[uid]
    if cur_ship and cur_ship ~= "" then
        ship_html = "<div font='font-outline:13' color='#44ccff'>Ship: ship-"..cur_ship.."</div>"
    end

    return "<table width=340>" ..
        "<tr><td>" .. nav ..
        "<tr><td><p>&nbsp;</p>" ..
        "<tr><td align=center>" .. ship_html ..
            "<div font='font-outline:28' color='#44ccff'>" .. pname .. "</div>" ..
        "<tr><td><p>&nbsp;</p>" ..
        "</table>"
end

function build_help_html()
    return [[
        <tr><td align=center><h2>Help</h2>
        <tr><td><table class='box' width=240>
        <tr><td>/away</td><td>Leave spectator queue</td>
        <tr><td>/gg</td><td>Good game</td>
        <tr><td>/who</td><td>List spectators</td>
        </table>
        <tr><td><p>&nbsp;</p>
        <tr><td align=center><input type='button' class='ibutton1' value='Back' onclick='*lobby	' icon='icon-restart'/>
    ]]
end

function build_ingame_html(client)
    return [[
        <tr><td align=center><input type='button' class='ibutton1' value='GG' onclick='/gg' icon='icon-leave'/>
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
    elseif win == "customize" then
        body = build_customize_html(c)
    elseif win == "colors" then
        body = build_colors_html(c, c.colors_page or 1)
    elseif win == "ships" then
        body = build_ships_html(c, c.ships_page or 1, c.ships_filter or "")
    elseif win == "skins" then
        body = build_skins_html(c, c.skins_page or 1, c.skins_filter or "")
    else
        body = build_lobby_html(c)
    end
    net_send(uid, "html", "<table width=340>" .. body .. "</table>")
    net_send(uid, "tabs", build_tabs(c))
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
            <tr><td colspan=2><h1>Bot Room</h1>
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
net_send("", "message", e.name .. " joined")
net_send("", "sfx",    "join")
if is_host then
net_send(e.uid, "message", "Host account -- status is permanently Away.")
else
net_send(e.uid, "message", "Welcome to Bot Room! Bot vs bot games run automatically.")
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
if #e.value > 9 and e.value:sub(9,9) == ":" then target = e.value:sub(10) end
local c2 = GAME.clients[e.uid]
if c2 then c2.window="profile"; c2.profile_uid=target end
if e.uid == HOST_UID then
GAME.host_window="profile"; GAME.host_profile_uid=target
update_host_html()
else send_html(e.uid) end
return
end
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
if e.uid == HOST_UID then GAME.host_ships_filter=nil; GAME.host_ships_page=1; update_host_html()
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
if e.uid == HOST_UID then GAME.host_skins_filter=nil; GAME.host_skins_page=1; update_host_html()
else send_html(e.uid) end
return
end
if e.value == "/help" then switch_window("help"); return end
end
if e.type == "net:message" then
local v = e.value
local lv = v:lower():gsub("^%s+","")
if lv:find("^/play") == 1 then
local c = GAME.clients[e.uid]
if c and not c.is_host then
c.status = "queue"
clients_assign_colors()
net_send("", "message", e.name .. " is spectating")
broadcast_html()
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
local msg = "Spectators: "
for _, c in pairs(GAME.clients) do msg = msg .. c.name .. "(" .. c.status .. ") " end
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
    if GAME.pending_countdown then return end
    if (GAME.start_countdown_seconds or 0) <= 0 then
        GAME.engine:next(GAME.modules.galcon)
        return
    end
    GAME.pending_countdown = GAME.start_countdown_seconds
    GAME.countdown_accum   = 0
    net_send("", "message", "Bot game starting in " .. GAME.pending_countdown .. "...")
end

function lobby_init()
GAME.modules.lobby = {}
local obj          = GAME.modules.lobby
function obj:init()
g2.state = "lobby"
params_set("state", "lobby")
GAME.host_window = GAME.host_window or "lobby"
broadcast_html()
-- Auto-start bot game after countdown
begin_match_countdown()
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
                GAME.engine:next(GAME.modules.galcon)
            else
                net_send("", "message", GAME.pending_countdown .. "...")
            end
        end
    end
end
function obj:event(e)
if e.type == "net:join" or e.type == "net:leave" then
broadcast_html()
return
end
if e.type == "net:message" then
local lv = e.value:lower():gsub("^%s+","")
if lv:sub(1,15) == "/frontierbonus " then
local raw = tonumber(lv:sub(16))
if raw then
raw = math.max(0, math.min(20, math.floor(raw + 0.5)))
GAME.distance_strength = raw / 10
broadcast_html()
end
return
end
if lv:sub(1,11) == "/isolation " then
local raw = tonumber(lv:sub(12))
if raw then
raw = math.max(0, math.min(20, math.floor(raw + 0.5)))
GAME.distance_isolation = raw / 10
broadcast_html()
end
return
end
if lv:sub(1,8) == "/toggle:" then
local what = lv:sub(9)
if what == "distance" then
GAME.distance_change = not GAME.distance_change
net_send("","message","Distance Change: " .. (GAME.distance_change and "ON" or "OFF"))
elseif what == "countdown_inc" then
GAME.start_countdown_seconds = math.min(10, GAME.start_countdown_seconds + 1)
net_send("","message","Auto-start delay: " .. GAME.start_countdown_seconds .. "s")
elseif what == "countdown_dec" then
GAME.start_countdown_seconds = math.max(0, GAME.start_countdown_seconds - 1)
net_send("","message","Auto-start delay: " .. GAME.start_countdown_seconds .. "s")
elseif what == "frontier_reset" then
GAME.distance_strength = 1.0
elseif what == "isolation_reset" then
GAME.distance_isolation = 1.0
end
broadcast_html()
return
end
if lv == "/batch" then
if not GAME.batch_mode then
GAME.batch_mode = true
broadcast_html()
net_send("", "message", "Batch REC ON -- press 'End Batch + Upload' when done.")
else
net_send(e.uid, "message", "Batch already active.")
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
if lv == "/gg" then net_send("", "message", e.name .. ": gg") end
end
end
end

function find_user(uid)
    for _, u in ipairs(g2.search("user")) do
        if u.user_uid == uid then return u end
    end
end

function galcon_stop(winner_user)
    local winner_info = nil
    if winner_user then
        winner_info = {
            uid  = winner_user.user_uid,
            name = winner_user.title_value,
            n    = winner_user.n,
            side = (winner_user.n == rec_player1_n) and "player" or "enemy",
        }
    end
    flush_chunk(true, winner_info)
    if winner_user then
        net_send("", "message", winner_user.title_value .. " won!")
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

function galcon_check_winner()
    local G       = GAME.galcon
    local neutral = G.neutral
    local alive   = {}
    for _, p in ipairs(g2.search("planet")) do
        local own = p.owner_n
        if not (neutral and own == neutral.n) then
            for _, u in ipairs(G.users) do
                if u.n == own then alive[own] = u; break end
            end
        end
    end
    local count  = 0
    local winner = nil
    for _, u in pairs(alive) do count = count + 1; winner = u end
    if count < #G.users then
        for _, f in ipairs(g2.search("fleet")) do
            for _, u in ipairs(G.users) do
                if u.n == f.owner_n and not alive[u.n] then count = count + 1; break end
            end
        end
    end
    if #G.users <= 1 then return end
    if count <= 1 then
        if count == 0 then winner = nil end
        galcon_stop(winner)
    end
end

-- Always returns philbuff
function pick_style()
    return "philbuff", nil, false
end

function galcon_init()
GAME.modules.galcon = {}
GAME.galcon         = {}
local obj           = GAME.modules.galcon
function obj:init()
    local ok, err = pcall(function()
        local G = GAME.galcon
        -- Full reset
        G.win_check_timer  = nil
        G.stats_timer      = nil
        for _, c in pairs(GAME.clients) do c.resumed = nil end

        GAME.last_style = "philbuff"
        GAME.last_ver   = nil
        GAME.game_mode  = "standard"

        g2.game_reset()
        math.randomseed(os.time())
        local neutral                    = g2.new_user("neutral", 0x444444)
        neutral.user_neutral             = 1
        neutral.ships_production_enabled = 0
        G.neutral                        = neutral
        GAME.neutral                     = neutral
        G.users                          = {}

        -- Create 2 bot users
        local bot_names  = {"Bot A", "Bot B"}
        local bot_colors = {0x00ff88, 0xff4455}
        for i = 1, 2 do
            local u = g2.new_user(bot_names[i], bot_colors[i])
            u.user_bot = 1
            G.users[i] = u
        end

        G.p1 = G.users[1]
        G.p2 = G.users[2]

        build_map(neutral, G.users, nil, nil)

        local map_planets = {}
        for _, p in ipairs(g2.search("planet")) do
            map_planets[#map_planets + 1] = {
                n=p.n, x=round(p.position_x), y=round(p.position_y),
                r=round(p.planet_r), prod=round(p.ships_production),
                ships=round(p.ships_value), owner=p.owner_n,
            }
        end

        rec_game_users = {p1=G.users[1], p2=G.users[2], neutral=neutral}
        rec_player1_n  = G.users[1] and G.users[1].n or 0
        rec_player2_n  = G.users[2] and G.users[2].n or 0
        reset_recording()

        local p1_name  = G.users[1] and G.users[1].title_value or "Bot A"
        local p2_name  = G.users[2] and G.users[2].title_value or "Bot B"

        g2.data = json.encode({
            payload = {
                chunk=0, final=false, status="part0",
                map=map_planets,
                player_n=rec_player1_n, enemy_n=rec_player2_n,
                player_name=p1_name, enemy_name=p2_name,
                batch_mode=(GAME.batch_mode and true or false),
                player_color="00ff88", enemy_color="ff4455",
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
        net_send("", "message", p1_name .. " vs " .. p2_name .. " -- GO!")
        net_send("", "message", "Map: philbuff")
        net_send("", "sfx", "start")
        g2.state = "play"
        params_set("state", "play")
    end)
    if not ok then
        print("GALCON INIT ERROR: " .. tostring(err))
        net_send("", "message", "GALCON INIT ERROR: " .. tostring(err))
    end
end
function obj:loop(t)
    local ok, err = pcall(function()
        local G = GAME.galcon
        GAME._last_t = t
        G.win_check_timer = (G.win_check_timer or 0) + t
        record_loop(t)
        if G.p1 then update_stats_html(G.p1, G.p2) end
        if G.win_check_timer >= WIN_CHECK_DELAY then galcon_check_winner() end
    end)
    if not ok then
        print("GALCON LOOP ERROR: " .. tostring(err))
        net_send("", "message", "GALCON LOOP ERROR: " .. tostring(err))
    end
end
function obj:event(e)
if e.type == "net:message" then
local lv = e.value:lower():gsub("^%s+","")
if lv == "/abort" then galcon_stop(nil)
elseif lv == "/gg" then net_send("", "message", e.name .. ": gg") end
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

function build_spectator_html(p1,p2,ps,pp,es,ep,extra_rows)
    if not p1 then return "<table><tr><td><p>Loading...</p></table>" end
    p2=p2 or p1; es=es or 0; ep=ep or 0
    local c1 = "#00ff88"
    local c2 = "#ff4455"
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
        "<tr><td align=left width=110><div font='font-outline:22' color='"..c1.."'>"..p1.title_value.."</div></td>" ..
        "<td align=center width=120><div font='font-outline:20' color='"..p_light.."'>&#9679;</div></td>" ..
        "<td align=right width=110><div font='font-outline:22' color='"..c2.."'>"..e_name.."</div></td></tr>" ..
        "<tr><td align=left><div font='font-outline:20' color='"..c1.."'>Ships: "..ps.."</div></td>" ..
        "<td align=center><div font='font-outline:28' color='"..adv_col.."'>"..adv_str.."</div></td>" ..
        "<td align=right><div font='font-outline:20' color='"..c2.."'>Ships: "..es.."</div></td></tr>" ..
        "<tr><td align=left><div font='font-outline:20' color='"..c1.."'>Prod: "..pp.."</div></td>" ..
        "<td align=center><div font='font-outline:28' color='"..pa_col.."'>"..pa_str.."</div></td>" ..
        "<td align=right><div font='font-outline:20' color='"..c2.."'>Prod: "..ep.."</div></td></tr>" ..
        "<tr><td colspan=3 align=center><div font='font-outline:34' color='"..vs_col.."'>"..vs_str.."</div></td></tr>" ..
        (extra_rows or "") ..
    "</table>"
end

function build_spectator_pause_html(p1, p2, ps, pp, es, ep)
    local extra = "<tr><td colspan=3 align=right>" ..
        "<input type='button' value='Resume' onclick='resume' class='ibutton1' width=80 height=32/>" ..
        "</td></tr>"
    return build_spectator_html(p1, p2, ps, pp, es, ep, extra)
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
    local ph=build_spectator_pause_html(p1,p2,ps,pp,es,ep)
    for _,c in pairs(GAME.clients) do
        if c.status=="away" then
            if not c.resumed then g2.net_send(c.uid,"html",ph) end
            g2.net_send(c.uid,"tabs",build_spectator_game_tabs())
        end
    end
    if GAME.host_paused then g2.html=ph end
end

function getSaandbuffVals(v,p,m)
local t={
[7]={{30,46,5,15},{46,61,16,25},{61,71,26,35},{71,81,36,50},{81,91,51,65},{91,101,66,85}},
}
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

function flush_chunk(final, winner_info)
    local t_now = math.floor(rec_clock * 10) / 10
    for id, f in pairs(rec_prev_fleets) do
        rec_log_pos[#rec_log_pos+1] = { t_now, id, f.x, f.y, 0 }
    end
    if #rec_log_events + #rec_log_pos == 0 and not final then return end
    local existing   = json.decode(g2.data) or {}
    existing.payload = {
        chunk=rec_chunk_index, final=final and true or false,
        status="part"..rec_chunk_index,
        events=rec_log_events, pos=rec_log_pos,
    }
    if final and winner_info then
        existing.winner = winner_info.name
        existing.payload.winner_uid  = winner_info.uid
        existing.payload.winner_name = winner_info.name
        existing.payload.winner_n    = winner_info.n
        existing.payload.winner_side = winner_info.side
    end
    existing.summary = rec_log_summary
    g2.data          = json.encode(existing)
    rec_log_events   = {}
    rec_log_pos      = {}
    rec_chunk_index  = rec_chunk_index + 1
end

function build_map(neutral, player_users, neutral_hide, neutral_hide2)
    local sw, sh, pad = SW, SH, MAP.pad
    local npairs = MAP.neutrals / 2
    local home_prod, home_ships = MAP.home_prod, MAP.home_ships
    local prods = {}
    for i = 1, npairs do
        prods[i] = math.random(MAP.prod_min, MAP.prod_max)
    end
    for i = 1, npairs do
        local prod = prods[i]
        local cost = math.floor(math.random(math.floor(prod / 20), math.floor(prod / 1.50)))
        local x = math.random(pad, math.floor(sw) - pad)
        local y = math.random(pad, math.floor(sh) - pad)
        g2.new_planet(neutral, x,              y,              prod, cost)
        g2.new_planet(neutral, math.floor(sw) - x, math.floor(sh) - y, prod, cost)
    end
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

    if GAME.distance_change then
        local home1, home2 = nil, nil
        for _, p in ipairs(g2.search("planet")) do
            if #player_users >= 1 and player_users[1] and p.owner_n == player_users[1].n then home1 = p end
            if #player_users >= 2 and player_users[2] and p.owner_n == player_users[2].n then home2 = p end
        end
        if home1 and home2 then
            local all_planets = g2.search("planet")
            local map_diag = math.sqrt(sw * sw + sh * sh)
            local STRENGTH = GAME.distance_strength  or 1.0
            local ISO      = GAME.distance_isolation or 1.0
            local norm_home = map_diag * 0.45 * ISO
            local norm_iso  = map_diag * 0.12 * ISO
            local zero_cost_budget = 2
            local FREE_MAX_PROD    = 50
            for _, p in ipairs(all_planets) do
                if p.owner_n == neutral.n then
                    local d1 = math.sqrt((p.position_x-home1.position_x)^2+(p.position_y-home1.position_y)^2)
                    local d2 = math.sqrt((p.position_x-home2.position_x)^2+(p.position_y-home2.position_y)^2)
                    local home_factor = math.min(math.min(d1,d2)/norm_home, 1.0)
                    local nearest = map_diag
                    for _, other in ipairs(all_planets) do
                        if other.n ~= p.n then
                            local dd = math.sqrt((p.position_x-other.position_x)^2+(p.position_y-other.position_y)^2)
                            if dd < nearest then nearest = dd end
                        end
                    end
                    local iso_factor = math.min(nearest/norm_iso, 1.0)
                    local prod_boost = math.floor((home_factor*0.65+iso_factor*0.35)*STRENGTH*(MAP.prod_max-p.ships_production))
                    p.ships_production = math.min(MAP.prod_max, p.ships_production + prod_boost)
                    local raw_cost = math.floor(p.ships_value*(1.0-home_factor*0.6*STRENGTH)-iso_factor*2*STRENGTH)
                    local new_cost
                    if raw_cost <= 0 and p.ships_production <= FREE_MAX_PROD and zero_cost_budget > 0 then
                        new_cost = 0; zero_cost_budget = zero_cost_budget - 1
                    else
                        new_cost = math.max(1, raw_cost)
                    end
                    p.ships_value = new_cost
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
        if e.uid and e.uid ~= HOST_UID then
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
            local c = GAME.clients[e.uid]
            if c then c.resumed = true end
            net_send(e.uid, "state", "play")
            return
        end
        GAME.host_paused = false
        g2.state = "play"
        return
    end
    GAME.engine:event(e)
end
