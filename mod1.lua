strict(true)

local POSITION_RATE = 2
local CHUNK_SIZE    = 50

function init()
  global("player")
  global("enemy")
  global("player_home")
  global("enemy_home")
  global("labels")
  global("clock")
  global("frame")
  global("view_page")
  global("map_version")
  global("log_events")
  global("log_pos")
  global("prev_fleets")
  global("prev_planets")
  global("prev_selected")
  global("chunk_index")
  global("save_timer")
  global("log")
  global("pos_frame")
  main_menu()
end

function getSaandbuffVals(version, prod)
  local cost = 0
  if version == 1 then
    if prod >= 30 and prod < 51 then cost = math.floor(math.random(5, 10))
    elseif prod >= 51 and prod < 76 then cost = math.floor(math.random(11, 30))
    elseif prod >= 76 and prod < 90 then cost = math.floor(math.random(30, 45))
    elseif prod >= 90 then cost = math.floor(math.random(45, 60))
    end
  elseif version == 2 then
    if prod >= 30 and prod < 46 then cost = math.floor(math.random(1, 5))
    elseif prod >= 46 and prod < 61 then cost = math.floor(math.random(5, 10))
    elseif prod >= 61 and prod < 75 then cost = math.floor(math.random(15, 30))
    elseif prod >= 75 and prod < 90 then cost = math.floor(math.random(30, 45))
    elseif prod >= 90 then cost = math.floor(math.random(45, 60))
    end
  elseif version == 3 then
    if prod >= 30 and prod < 46 then cost = math.floor(math.random(1, 5))
    elseif prod >= 46 and prod < 61 then cost = math.floor(math.random(5, 10))
    elseif prod >= 61 and prod < 75 then cost = math.floor(math.random(11, 29))
    elseif prod >= 75 and prod < 90 then cost = math.floor(math.random(30, 45))
    elseif prod >= 90 then cost = math.floor(math.random(45, 60))
    end
  elseif version == 4 then
    if prod >= 20 and prod < 40 then cost = math.floor(math.random(0, 5))
    elseif prod >= 40 and prod < 66 then cost = math.floor(math.random(6, 15))
    elseif prod >= 66 and prod < 86 then cost = math.floor(math.random(16, 40))
    elseif prod >= 86 and prod < 100 then cost = math.floor(math.random(41, 60))
    elseif prod >= 100 then cost = math.floor(math.random(60, 70))
    end
  elseif version == 5 then
    if prod >= 20 and prod < 41 then cost = math.floor(math.random(0, 5))
    elseif prod >= 41 and prod < 61 then cost = math.floor(math.random(5, 10))
    elseif prod >= 61 and prod < 81 then cost = math.floor(math.random(20, 35))
    elseif prod >= 81 and prod < 100 then cost = math.floor(math.random(36, 55))
    elseif prod >= 100 then cost = math.floor(math.random(56, 65))
    end
  elseif version == 6 then
    if prod >= 20 and prod < 41 then cost = math.floor(math.random(0, 5))
    elseif prod >= 41 and prod < 66 then cost = math.floor(math.random(5, 15))
    elseif prod >= 66 and prod < 81 then cost = math.floor(math.random(12, 30))
    elseif prod >= 81 and prod < 100 then cost = math.floor(math.random(25, 60))
    elseif prod >= 100 then cost = math.floor(math.random(30, 70))
    end
  elseif version == 7 then
    if prod >= 30 and prod < 51 then cost = math.floor(math.random(5, 10))
    elseif prod >= 51 and prod < 71 then cost = math.floor(math.random(10, 20))
    elseif prod >= 71 and prod < 81 then cost = math.floor(math.random(20, 30))
    elseif prod >= 81 and prod < 100 then cost = math.floor(math.random(30, 60))
    elseif prod >= 100 then cost = math.floor(math.random(40, 70))
    end
  elseif version == 8 then
    if prod >= 20 and prod < 41 then cost = math.floor(math.random(0, 5))
    elseif prod >= 41 and prod < 61 then cost = math.floor(math.random(10, 20))
    elseif prod >= 61 and prod < 81 then cost = math.floor(math.random(20, 30))
    elseif prod >= 81 then cost = math.floor(math.random(35, 70))
    end
  elseif version == 9 then
    if prod >= 15 and prod < 41 then cost = math.floor(math.random(0, 5))
    elseif prod >= 41 and prod < 61 then cost = math.floor(math.random(5, 10))
    elseif prod >= 61 and prod < 71 then cost = math.floor(math.random(11, 20))
    elseif prod >= 71 then cost = math.floor(math.random(20, 40))
    end
  elseif version == 10 then
    if prod >= 15 and prod < 30 then cost = math.floor(math.random(0, 3))
    elseif prod >= 30 and prod < 51 then cost = math.floor(math.random(4, 9))
    elseif prod >= 51 and prod < 71 then cost = math.floor(math.random(10, 20))
    elseif prod >= 71 and prod < 80 then cost = math.floor(math.random(20, 35))
    elseif prod >= 80 then cost = math.floor(math.random(30, 40))
    end
  end
  return cost
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

function fmt_time(t)
  local m = math.floor(t / 60)
  local s = math.floor(t % 60)
  return string.format("%02d:%02d", m, s)
end

function calc_versus_timer(ps, pp, es, ep)
  local prod_diff = (pp - ep) / 50.0
  if prod_diff == 0 then return nil end
  return -(ps - es) / prod_diff
end

function round(x)
  return math.floor(x + 0.5)
end

function flush_chunk(final)
  local t_now = math.floor(clock * 10) / 10
  for id, f in pairs(prev_fleets) do
    log_pos[#log_pos + 1] = {
      t_now, id, f.x, f.y, 0
    }
  end

  local total = #log_events + #log_pos
  if total == 0 and not final then return end

  local existing = json.decode(g2.data) or {}
  existing.payload = {
    chunk  = chunk_index,
    final  = final and true or false,
    status = "part" .. chunk_index,
    events = log_events,
    pos    = log_pos,
  }
  existing.summary = log
  g2.data     = json.encode(existing)
  log_events  = {}
  log_pos     = {}
  chunk_index = chunk_index + 1
end

function main_menu()
  g2.state = "menu"
  local has_data = g2.data and #g2.data > 2
  g2.html = [[
    <table>
      <tr><td><h1>Eliminator Mod</h1>
      <tr><td><input type='button' value='Start' onclick='start' />
  ]] .. (has_data and [[
      <tr><td><input type='button' value='View Summary' onclick='viewsaved' />
      <tr><td><input type='button' value='Clear Data' onclick='cleardata' />
  ]] or [[
      <tr><td><p>No saved data yet.</p>
  ]]) .. [[
    </table>
  ]]
end

function init_game()
  g2.game_reset()
  math.randomseed(os.time())
  map_version = math.random(1, 10)

  local neutrals = 12
  local w, h = 800, 600
  g2.view_set(0, 0, w, h)

  local neutral = g2.new_user("neutral", 0x999999)
  neutral.user_neutral = true
  neutral.ships_production_enabled = 0

  player = g2.new_user("Player", 0x00ff00)
  g2.player = player

  enemy = g2.new_user("Enemy", 0xff0000)

  for i = 1, neutrals / 2 do
    local prod = math.random(30, 100)
    local cost = getSaandbuffVals(map_version, prod)
    local x = math.random(100, w - 100)
    local y = math.random(100, h - 100)
    g2.new_planet(neutral,     x,     y, prod, cost)
    g2.new_planet(neutral, w - x, h - y, prod, cost)
  end

  player_home = g2.new_planet(player, 150, h / 2, 100, 100)
  enemy_home  = g2.new_planet(enemy,  w - 150, h / 2, 100, 100)

  g2.planets_settle()

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

  log_events    = {}
  log_pos       = {}
  chunk_index   = 1
  save_timer    = 0
  clock         = 0
  frame         = 0
  pos_frame     = 0
  prev_fleets   = {}
  prev_planets  = {}
  prev_selected = {}
  log           = {}

  local init_payload = {
    chunk    = 0,
    final    = false,
    status   = "part0",
    map      = map_planets,
    player_n = player.n,
    enemy_n  = enemy.n,
    version  = map_version,
    w        = w,
    h        = h,
  }
  g2.data     = json.encode({ payload = init_payload, summary = {} })
  chunk_index = 1

  labels = {}
  labels.p_light = g2.new_circle(0x333333, 150, 28, 5)
  labels.e_light = g2.new_circle(0x333333, 550, 28, 5)
  labels.p_name   = g2.new_label("Player",     84,  8, 0x00ff00)
  labels.p_prod   = g2.new_label("Prod: 100",  84, 24, 0x00ff00)
  labels.p_ships  = g2.new_label("Ships: 100", 84, 40, 0x00ff00)
  labels.prod_adv = g2.new_label("Prod Adv: 0",  330, 8,  0xffffff)
  labels.adv      = g2.new_label("Ship Adv: 0",  330, 24, 0xffffff)
  labels.vs       = g2.new_label("VS: --",        330, 40, 0xffff00)
  labels.chunk    = g2.new_label("c:0",           330, 56, 0x888888)
  labels.e_name   = g2.new_label("Enemy",      620,  8, 0xff4444)
  labels.e_prod   = g2.new_label("Prod: 100",  620, 24, 0xff4444)
  labels.e_ships  = g2.new_label("Ships: 100", 620, 40, 0xff4444)
end

function loop(t)
  if g2.state ~= "play" then return end

  clock      = clock + t
  frame      = frame + 1
  pos_frame  = pos_frame + 1
  save_timer = save_timer + t

  local viewer       = g2.viewer
  local is_spectator = (viewer == nil)
                    or (viewer.n ~= player.n and viewer.n ~= enemy.n)

  local ps = total_ships(player)
  local es = total_ships(enemy)
  local pp = total_production(player)
  local ep = total_production(enemy)
  local adv = ps - es
  local vt  = calc_versus_timer(ps, pp, es, ep)

  if is_spectator then
    local prod_adv = pp - ep
    labels.p_prod.label_text  = "Prod: "  .. pp
    labels.p_ships.label_text = "Ships: " .. ps
    labels.e_prod.label_text  = "Prod: "  .. ep
    labels.e_ships.label_text = "Ships: " .. es
    labels.chunk.label_text   = "c:" .. chunk_index
    if prod_adv > 0 then
      labels.prod_adv.label_text   = "Prod Adv: +" .. prod_adv
      labels.prod_adv.render_color = 0x00ff00
    elseif prod_adv < 0 then
      labels.prod_adv.label_text   = "Prod Adv: " .. prod_adv
      labels.prod_adv.render_color = 0xff4444
    else
      labels.prod_adv.label_text   = "Prod Adv: 0"
      labels.prod_adv.render_color = 0xffffff
    end
    if adv > 0 then
      labels.adv.label_text   = "Ship Adv: +" .. adv
      labels.adv.render_color = 0x00ff00
    elseif adv < 0 then
      labels.adv.label_text   = "Ship Adv: " .. adv
      labels.adv.render_color = 0xff4444
    else
      labels.adv.label_text   = "Ship Adv: 0"
      labels.adv.render_color = 0xffffff
    end
    if vt == nil then
      labels.vs.label_text   = "VS: even"
      labels.vs.render_color = 0xffffff
    elseif vt <= 0 then
      local leader = pp > ep and "P" or "E"
      labels.vs.label_text   = "VS: " .. leader .. " dom"
      labels.vs.render_color = pp > ep and 0x00ff00 or 0xff4444
    else
      local leader = pp > ep and "P" or "E"
      local vt_str = vt < 60 and string.format("%.1fs", vt) or fmt_time(vt)
      labels.vs.label_text   = "VS: " .. leader .. " +" .. vt_str
      labels.vs.render_color = pp > ep and 0x00ff00 or 0xff4444
    end
    local prod_adv2 = pp - ep
    if adv > 0 and prod_adv2 > 0 then
      labels.p_light.render_color = 0x00ff00
      labels.e_light.render_color = 0x333333
    elseif adv < 0 and prod_adv2 < 0 then
      labels.p_light.render_color = 0x333333
      labels.e_light.render_color = 0xff4444
    else
      labels.p_light.render_color = 0x333333
      labels.e_light.render_color = 0x333333
    end
  else
    labels.p_prod.label_text  = ""
    labels.p_ships.label_text = ""
    labels.e_prod.label_text  = ""
    labels.e_ships.label_text = ""
    labels.prod_adv.label_text = ""
    labels.adv.label_text     = ""
    labels.vs.label_text      = ""
    labels.chunk.label_text   = ""
    labels.p_light.render_color = 0x333333
    labels.e_light.render_color = 0x333333
  end

  for _, p in ipairs(g2.search("planet")) do
    local pid     = p.n
    local sel_raw = p:selected()
    local is_sel  = (sel_raw == true or sel_raw == 1) and 1 or 0
    local was_sel = prev_selected[pid] or 0
    if is_sel ~= was_sel then
      prev_selected[pid] = is_sel
      log_events[#log_events + 1] = {
        e = is_sel == 1 and "sel" or "dsel",
        t = math.floor(clock * 10) / 10,
        n = pid,
      }
    end
  end

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

    if not prev_fleets[id] then
      local rem = nil
      if f.owner_n == player.n then
        for _, sp in ipairs(g2.search("planet owner:" .. player.n)) do
          local dx = sp.position_x - f.position_x
          local dy = sp.position_y - f.position_y
          if math.sqrt(dx * dx + dy * dy) < 60 then
            rem = math.floor(sp.ships_value)
            break
          end
        end
      end
      log_events[#log_events + 1] = {
        e   = "fs",
        t   = math.floor(clock * 10) / 10,
        id  = id,
        o   = f.owner_n,
        s   = fships,
        tg  = f.fleet_target,
        x   = fx,
        y   = fy,
        rem = rem,
      }
      log_pos[#log_pos + 1] = {
        math.floor(clock * 10) / 10,
        id, fx, fy, 0
      }
    else
      if prev_fleets[id].target ~= f.fleet_target then
        log_events[#log_events + 1] = {
          e  = "fr",
          t  = math.floor(clock * 10) / 10,
          id = id,
          tg = f.fleet_target,
        }
      end
      if prev_fleets[id].ships ~= fships then
        log_events[#log_events + 1] = {
          e  = "fu",
          t  = math.floor(clock * 10) / 10,
          id = id,
          s  = fships,
        }
      end
    end
  end

  for id, pf in pairs(prev_fleets) do
    if not curr_fleets[id] then
      log_pos[#log_pos + 1] = {
        math.floor(clock * 10) / 10,
        id, pf.x, pf.y, 0
      }
      log_events[#log_events + 1] = {
        e  = "fd",
        t  = math.floor(clock * 10) / 10,
        id = id,
        tg = pf.target,
        o  = pf.owner,
      }
    end
  end

  prev_fleets = curr_fleets

  for _, p in ipairs(g2.search("planet")) do
    local pid   = p.n
    local owner = p.owner_n
    local prev  = prev_planets[pid]
    if prev and prev.owner ~= owner then
      log_events[#log_events + 1] = {
        e = "pc",
        t = math.floor(clock * 10) / 10,
        n = pid,
        o = owner,
      }
    end
    prev_planets[pid] = { owner = owner }
  end

  if pos_frame >= POSITION_RATE then
    pos_frame = 0
    for id, f in pairs(curr_fleets) do
      log_pos[#log_pos + 1] = {
        math.floor(clock * 10) / 10,
        id, f.x, f.y, 0
      }
    end
    for _, p in ipairs(g2.search("planet")) do
      log_events[#log_events + 1] = {
        e = "pn",
        t = math.floor(clock * 10) / 10,
        n = p.n,
        s = round(p.ships_value),
      }
    end
  end

  if frame % 30 == 0 then
    log[#log + 1] = {
      t  = math.floor(clock * 100) / 100,
      ps = ps,
      pp = pp,
      es = es,
      ep = ep,
    }
  end

  local total_pending = #log_events + #log_pos
  if total_pending >= CHUNK_SIZE or save_timer >= 0.5 then
    save_timer = 0
    flush_chunk(false)
  end
end

function view_saved(data_str)
  local decoded = json.decode(data_str)
  if not decoded or not decoded.summary then
    g2.state = "menu"
    g2.html = [[<table><tr><td><p>No summary data.</p>
      <tr><td><input type='button' value='Back' onclick='backtomenu' />
    </table>]]
    return
  end
  local data  = decoded.summary
  local count = #data
  if count == 0 then
    g2.state = "menu"
    g2.html = [[<table><tr><td><p>No entries yet.</p>
      <tr><td><input type='button' value='Back' onclick='backtomenu' />
    </table>]]
    return
  end
  local page_size   = 10
  local start       = (view_page or 0) * page_size + 1
  local finish      = math.min(start + page_size - 1, count)
  local total_pages = math.ceil(count / page_size)
  local html = "<table>"
  html = html .. "<tr><td colspan=5><h2>Summary pg "
             .. ((view_page or 0) + 1) .. "/" .. total_pages .. "</h2>"
  html = html .. "<tr><td><p>t</p><td><p>ps</p><td><p>pp</p>"
             .. "<td><p>es</p><td><p>ep</p>"
  for i = start, finish do
    local e = data[i]
    html = html .. "<tr>"
      .. "<td><p>" .. fmt_time(e.t) .. "</p>"
      .. "<td><p>" .. e.ps         .. "</p>"
      .. "<td><p>" .. e.pp         .. "</p>"
      .. "<td><p>" .. e.es         .. "</p>"
      .. "<td><p>" .. e.ep         .. "</p>"
  end
  html = html .. "<tr><td colspan=2>"
  if (view_page or 0) > 0 then
    html = html .. "<input type='button' value='Prev' onclick='prevpage' />"
  end
  html = html .. "<td colspan=2>"
  if finish < count then
    html = html .. "<input type='button' value='Next' onclick='nextpage' />"
  end
  html = html .. "<tr><td colspan=5>"
             .. "<input type='button' value='Back' onclick='backtomenu' />"
             .. "</table>"
  g2.state = "menu"
  g2.html  = html
end

function show_data()
  flush_chunk(true)
  g2.state = "pause"
  g2.html  = [[
    <table>
      <tr><td><h2>Data Saved</h2>
      <tr><td><input type='button' value='Resume'       onclick='resume'     />
      <tr><td><input type='button' value='Quit to Menu' onclick='quittomenu' />
    </table>
  ]]
end

function event(e)
  if e.type == "onclick" then
    if e.value == "start" then
      init_game()
      g2.state = "play"
    elseif e.value == "resume" then
      g2.state = "play"
    elseif e.value == "export" then
      show_data()
    elseif e.value == "quittomenu" then
      main_menu()
    elseif e.value == "backtomenu" then
      main_menu()
    elseif e.value == "viewsaved" then
      view_page = 0
      view_saved(g2.data)
    elseif e.value == "nextpage" then
      view_page = (view_page or 0) + 1
      view_saved(g2.data)
    elseif e.value == "prevpage" then
      view_page = (view_page or 0) - 1
      view_saved(g2.data)
    elseif e.value == "cleardata" then
      g2.data = "{}"
      main_menu()
    elseif e.value == "quit" then
      g2.state = "quit"
    end
  elseif e.type == "pause" then
    g2.state = "pause"
    g2.html  = [[
      <table>
        <tr><td><input type='button' value='Resume'        onclick='resume' />
        <tr><td><input type='button' value='Save and Quit' onclick='export' />
        <tr><td><input type='button' value='Quit'          onclick='quit'   />
      </table>
    ]]
  end
end
