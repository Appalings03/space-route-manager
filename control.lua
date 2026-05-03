local GUI_NAME = "srm_route_panel"

local function find_platform_by_name(platform_name)
  for _, surface in pairs(game.surfaces) do
    if surface.platform and surface.platform.name == platform_name then
      return surface.platform
    end
  end

  return nil
end

local function is_planet_forbidden(platform_name, planet_name)
  if not storage.srm_forbidden then
    return false
  end

  local key = platform_name .. "|" .. planet_name
  return storage.srm_forbidden[key] == true
end

local function set_planet_forbidden(platform_name, planet_name, state)
  storage.srm_forbidden = storage.srm_forbidden or {}

  local key = platform_name .. "|" .. planet_name
  storage.srm_forbidden[key] = state or nil
end

local function build_graph()
  if storage.srm_graph then
    return storage.srm_graph
  end

  local graph = {}
  for _, conn in pairs(prototypes.space_connection) do
    local a = type(conn.from) == "string" and conn.from or conn.from.name
    local b = type(conn.to) == "string" and conn.to or conn.to.name

    graph[a] = graph[a] or {}
    graph[b] = graph[b] or {}
    graph[a][b] = true
    graph[b][a] = true
  end

  storage.srm_graph = graph
  return graph
end

local function get_all_reachable_planets(graph, start_name)
  local visited = { [start_name] = true }
  local queue = { start_name }
  local result = { start_name }

  while #queue > 0 do
    local current = table.remove(queue, 1)
    for neighbor, _ in pairs(graph[current] or {}) do
      if not visited[neighbor] then
        visited[neighbor] = true
        table.insert(result, neighbor)
        table.insert(queue, neighbor)
      end
    end
  end

  table.sort(result)
  return result
end

local function bfs_path(graph, start_name, goal_name, forbidden)
  if start_name == goal_name then
    return { start_name }
  end

  local visited = { [start_name] = true }
  local queue = { { name = start_name, path = { start_name } } }

  while #queue > 0 do
    local current = table.remove(queue, 1)
    for neighbor, _ in pairs(graph[current.name] or {}) do
      if not visited[neighbor] then
        if neighbor == goal_name or not forbidden[neighbor] then
          visited[neighbor] = true

          local new_path = {}
          for _, p in ipairs(current.path) do
            table.insert(new_path, p)
          end
          table.insert(new_path, neighbor)

          if neighbor == goal_name then
            return new_path
          end

          table.insert(queue, { name = neighbor, path = new_path })
        end
      end
    end
  end

  return nil
end

local function get_space_location_proto(name)
  local planet = game.planets[name]
  if planet then
    return planet
  end

  return nil
end

local function stop_platform(platform)
  storage.srm_full_schedules = storage.srm_full_schedules or {}
  if platform.schedule and platform.schedule.records and #platform.schedule.records > 0 then
    if not storage.srm_full_schedules[platform.name] then
      storage.srm_full_schedules[platform.name] = platform.schedule.records
    end
  end

  platform.paused = true
end

local function apply_and_restart(platform, player)
  storage.srm_full_schedules = storage.srm_full_schedules or {}
  storage.srm_forbidden = storage.srm_forbidden or {}

  local original = storage.srm_full_schedules[platform.name]
  if not original or #original == 0 then
    if player then
      player.print({ "space-route-manager.no-saved-routes", platform.name }, { r = 1, g = 0.6, b = 0 })
    end
    return
  end

  local forbidden = {}
  for key, val in pairs(storage.srm_forbidden) do
    local pname, planet = key:match("^(.+)|(.+)$")
    if pname == platform.name and val == true then
      forbidden[planet] = true
    end
  end

  local graph = build_graph()
  local new_records = {}
  local warnings = {}

  local current_loc = platform.space_location
  local prev_name = current_loc and current_loc.name or nil

  for _, record in ipairs(original) do
    local dest_name = record.planet and record.planet.name or nil

    if not dest_name then
      table.insert(new_records, record)
    else
      if prev_name and prev_name ~= dest_name then
        local path = bfs_path(graph, prev_name, dest_name, forbidden)

        if not path then
          table.insert(warnings, { "space-route-manager.warning-no-path", prev_name, dest_name })
          table.insert(new_records, record)
        elseif #path > 2 then
          for step_i = 2, #path - 1 do
            local wp_proto = get_space_location_proto(path[step_i])
            if wp_proto then
              table.insert(new_records, {
                planet = wp_proto,
                wait_conditions = {}
              })
            end
          end
          table.insert(new_records, record)
        else
          table.insert(new_records, record)
        end
      else
        table.insert(new_records, record)
      end

      prev_name = dest_name
    end
  end

  local current_index = (platform.schedule and platform.schedule.current) or 1
  if #new_records == 0 or current_index > #new_records or current_index < 1 then
    current_index = 1
  end

  platform.schedule = { current = current_index, records = new_records }
  platform.paused = false

  if player then
    player.print({ "space-route-manager.ship-restarted", platform.name }, { r = 0.4, g = 0.9, b = 0.4 })
    for _, warning in ipairs(warnings) do
      player.print({ "space-route-manager.warning-prefix", warning }, { r = 1, g = 0.8, b = 0 })
    end
  end
end

local function destroy_gui(player)
  if player.gui.relative[GUI_NAME] then
    player.gui.relative[GUI_NAME].destroy()
  end

  if player.gui.screen[GUI_NAME] then
    player.gui.screen[GUI_NAME].destroy()
  end
end

local function build_gui(player, platform)
  destroy_gui(player)

  storage.srm_full_schedules = storage.srm_full_schedules or {}
  if platform.schedule and platform.schedule.records and #platform.schedule.records > 0 then
    if not storage.srm_full_schedules[platform.name] then
      storage.srm_full_schedules[platform.name] = platform.schedule.records
    end
  end

  local graph = build_graph()

  local start_name = nil
  if platform.space_location then
    start_name = platform.space_location.name
  elseif storage.srm_full_schedules[platform.name] then
    local first = storage.srm_full_schedules[platform.name][1]
    if first and first.planet then
      start_name = first.planet.name
    end
  end

  local all_planets = {}
  if start_name then
    all_planets = get_all_reachable_planets(graph, start_name)
  else
    for name, _ in pairs(game.planets) do
      table.insert(all_planets, name)
    end
    table.sort(all_planets)
  end

  local frame = player.gui.screen.add{
    type = "frame",
    name = GUI_NAME,
    caption = { "space-route-manager.forbidden-panel-title", platform.name },
    direction = "vertical"
  }
  frame.auto_center = true
  frame.style.minimal_width = 340

  local subtitle = frame.add{
    type = "label",
    caption = { "space-route-manager.forbidden-panel-subtitle" }
  }
  subtitle.style.single_line = false
  subtitle.style.bottom_margin = 8

  local scroll = frame.add{
    type = "scroll-pane",
    name = "srm_scroll",
    direction = "vertical"
  }
  scroll.style.maximal_height = 380
  scroll.style.horizontally_stretchable = true

  local tbl = scroll.add{
    type = "table",
    name = "srm_planet_table",
    column_count = 1
  }
  tbl.style.horizontally_stretchable = true

  if #all_planets == 0 then
    tbl.add{
      type = "label",
      caption = { "space-route-manager.no-planets-found" }
    }
  else
    for _, pname in ipairs(all_planets) do
      local forbidden = is_planet_forbidden(platform.name, pname)
      local row = tbl.add{ type = "flow", direction = "horizontal" }
      row.style.vertical_align = "center"
      row.style.bottom_margin = 2

      row.add{
        type = "checkbox",
        name = "srm_cb_" .. pname,
        caption = pname,
        state = forbidden,
        tags = {
          srm_action = "toggle_planet",
          platform_name = platform.name,
          planet_name = pname
        }
      }
    end
  end

  local footer = frame.add{ type = "flow", direction = "horizontal" }
  footer.style.top_margin = 10
  footer.style.horizontal_align = "right"
  footer.style.horizontally_stretchable = true

  footer.add{
    type = "button",
    name = "srm_reset",
    caption = { "space-route-manager.reset" },
    tags = { srm_action = "reset", platform_name = platform.name }
  }.style.right_margin = 6

  footer.add{
    type = "button",
    name = "srm_apply",
    caption = { "space-route-manager.stop-and-apply" },
    tags = { srm_action = "apply", platform_name = platform.name }
  }.style.right_margin = 4

  footer.add{
    type = "button",
    name = "srm_close",
    caption = { "space-route-manager.close" },
    tags = { srm_action = "close" }
  }
end

local function inject_button(player, platform)
  local target_frame = nil

  for _, gui_root in pairs({ player.gui.relative, player.gui.left, player.gui.center }) do
    if gui_root["space-platform-hub-gui"] then
      target_frame = gui_root["space-platform-hub-gui"]
      break
    end

    for _, name in pairs(gui_root.children_names) do
      if type(name) == "string" and name:find("platform") then
        target_frame = gui_root[name]
        break
      end
    end
  end

  if target_frame then
    local toolbar = target_frame["toolbar"] or target_frame["header"] or target_frame
    if toolbar and not toolbar["srm_open_button"] then
      toolbar.add{
        type = "sprite-button",
        name = "srm_open_button",
        sprite = "srm-route-icon",
        tooltip = { "space-route-manager.forbidden-open-tooltip" },
        style = "frame_action_button",
        tags = { srm_action = "open_panel", platform_name = platform.name }
      }
    end
  elseif not player.gui.left["srm_open_button_left"] then
    player.gui.left.add{
      type = "button",
      name = "srm_open_button_left",
      caption = { "space-route-manager.forbidden-open-caption" },
      tooltip = { "space-route-manager.forbidden-open-tooltip" },
      tags = { srm_action = "open_panel", platform_name = platform.name }
    }
  end
end

local function remove_inject_button(player)
  if player.gui.left["srm_open_button_left"] then
    player.gui.left["srm_open_button_left"].destroy()
  end
end

script.on_init(function()
  storage.srm_forbidden = {}
  storage.srm_full_schedules = {}
  storage.srm_graph = nil
end)

script.on_configuration_changed(function()
  storage.srm_forbidden = storage.srm_forbidden or {}
  storage.srm_full_schedules = storage.srm_full_schedules or {}
  storage.srm_graph = nil
end)

script.on_event(defines.events.on_gui_opened, function(event)
  local player = game.players[event.player_index]
  if not player then
    return
  end

  if event.entity and event.entity.type == "space-platform-hub" then
    local platform = player.surface.platform
    if platform then
      inject_button(player, platform)
    end
  end
end)

script.on_event(defines.events.on_gui_closed, function(event)
  local player = game.players[event.player_index]
  if not player then
    return
  end

  remove_inject_button(player)
  destroy_gui(player)
end)

script.on_event(defines.events.on_gui_checked_state_changed, function(event)
  local player = game.players[event.player_index]
  if not player then
    return
  end

  local element = event.element
  if not element or not element.valid then
    return
  end

  if not element.tags or element.tags.srm_action ~= "toggle_planet" then
    return
  end

  set_planet_forbidden(element.tags.platform_name, element.tags.planet_name, element.state)
end)

script.on_event(defines.events.on_gui_click, function(event)
  local player = game.players[event.player_index]
  if not player then
    return
  end

  local element = event.element
  if not element or not element.valid then
    return
  end

  if not element.tags or not element.tags.srm_action then
    return
  end

  local action = element.tags.srm_action

  if action == "open_panel" then
    local platform = find_platform_by_name(element.tags.platform_name)
    if platform then
      build_gui(player, platform)
    else
      player.print({ "space-route-manager.ship-not-found", tostring(element.tags.platform_name) })
    end
  elseif action == "apply" then
    local platform = find_platform_by_name(element.tags.platform_name)
    if platform then
      stop_platform(platform)

      storage.srm_pending_apply = storage.srm_pending_apply or {}
      storage.srm_pending_apply[platform.name] = {
        tick = game.tick + 2,
        player_index = player.index
      }

      player.print({ "space-route-manager.ship-stopping", platform.name }, { r = 1, g = 0.9, b = 0.3 })
    end

    destroy_gui(player)
  elseif action == "reset" then
    local platform = find_platform_by_name(element.tags.platform_name)
    if platform then
      storage.srm_forbidden = storage.srm_forbidden or {}
      for key, _ in pairs(storage.srm_forbidden) do
        local pname = key:match("^(.+)|(.+)$")
        if pname == platform.name then
          storage.srm_forbidden[key] = nil
        end
      end

      if storage.srm_full_schedules and storage.srm_full_schedules[platform.name] then
        local original = storage.srm_full_schedules[platform.name]
        if original and #original > 0 then
          platform.schedule = { current = 1, records = original }
          platform.paused = false
        end

        player.print({ "space-route-manager.routes-restored", platform.name }, { r = 0.4, g = 0.9, b = 0.4 })
      end
    end

    destroy_gui(player)
  elseif action == "close" then
    destroy_gui(player)
  end
end)

script.on_event(defines.events.on_tick, function(event)
  if not storage.srm_pending_apply then
    return
  end

  if not next(storage.srm_pending_apply) then
    return
  end

  for platform_name, data in pairs(storage.srm_pending_apply) do
    if event.tick >= data.tick then
      local platform = find_platform_by_name(platform_name)
      local player = game.players[data.player_index]
      if platform then
        apply_and_restart(platform, player)
      end

      storage.srm_pending_apply[platform_name] = nil
    end
  end
end)
