-- control.lua

local GUI_NAME = "srm_route_panel"

-- ─────────────────────────────────────────────
-- UTILITAIRES
-- ─────────────────────────────────────────────

local function get_selected_platform(player)
  if player.surface and player.surface.platform then
    return player.surface.platform
  end
  return nil
end

local function get_platform_ships(platform)
  local ships = {}
  if not platform then return ships end

  for _, surface in pairs(game.surfaces) do
    if surface.platform then
      local p = surface.platform
      table.insert(ships, {
        name = p.name,
        platform = p,
        surface = surface
      })
    end
  end
  return ships
end

local function is_route_disabled(platform_name, target_name)
  if not global.srm_disabled_routes then return false end
  local key = platform_name .. "|" .. target_name
  return global.srm_disabled_routes[key] == true
end

local function toggle_route(platform_name, target_name)
  if not global.srm_disabled_routes then
    global.srm_disabled_routes = {}
  end
  local key = platform_name .. "|" .. target_name
  global.srm_disabled_routes[key] = not global.srm_disabled_routes[key]
end

local function apply_routes(platform)
  if not platform then return end

  local hub = platform.hub_surface_index and game.surfaces[platform.hub_surface_index]
  local schedule = platform.schedule
  if not schedule then return end

  local new_records = {}
  for _, record in pairs(schedule.records) do
    local target = record.station or (record.planet and record.planet.name) or "?"
    if not is_route_disabled(platform.name, target) then
      table.insert(new_records, record)
    end
  end

  if not global.srm_full_schedules then global.srm_full_schedules = {} end
  if not global.srm_full_schedules[platform.name] then
    global.srm_full_schedules[platform.name] = schedule.records
  end

  platform.schedule = { current = schedule.current, records = new_records }
end

-- ─────────────────────────────────────────────
-- GUI
-- ─────────────────────────────────────────────

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

  local full_records = {}
  if global.srm_full_schedules and global.srm_full_schedules[platform.name] then
    full_records = global.srm_full_schedules[platform.name]
  elseif platform.schedule then
    full_records = platform.schedule.records or {}
  end

  local frame = player.gui.screen.add{
    type = "frame",
    name = GUI_NAME,
    caption = {"", "🚀 Routes — ", platform.name},
    direction = "vertical"
  }
  frame.auto_center = true
  frame.style.minimal_width = 320

  local subtitle = frame.add{
    type = "label",
    caption = "Cliquez sur une destination pour activer / désactiver la route."
  }
  subtitle.style.single_line = false
  subtitle.style.bottom_margin = 8

  local scroll = frame.add{
    type = "scroll-pane",
    name = "srm_scroll",
    direction = "vertical"
  }
  scroll.style.maximal_height = 400

  local list = scroll.add{
    type = "table",
    name = "srm_route_list",
    column_count = 1
  }
  list.style.horizontally_stretchable = true

  if #full_records == 0 then
    list.add{
      type = "label",
      caption = "Aucune route configurée pour ce vaisseau."
    }
  else
    for i, record in pairs(full_records) do
      local dest_name = "?"
      if record.planet then
        dest_name = record.planet.name
      elseif record.station then
        dest_name = record.station
      end

      local disabled = is_route_disabled(platform.name, dest_name)
      local icon = disabled and "❌ " or "✅ "
      local style = disabled and "srm_disabled_route_button" or "srm_enabled_route_button"
      local caption = icon .. dest_name .. (disabled and "  [désactivée]" or "  [active]")

      local btn = list.add{
        type = "button",
        name = "srm_toggle_" .. i .. "_" .. dest_name,
        caption = caption,
        style = style,
        tags = {
          srm_action = "toggle_route",
          platform_name = platform.name,
          dest_name = dest_name
        }
      }
      btn.style.horizontally_stretchable = true
    end
  end

  local footer = frame.add{ type = "flow", direction = "horizontal" }
  footer.style.top_margin = 8
  footer.style.horizontal_align = "right"
  footer.style.horizontally_stretchable = true

  local apply_btn = footer.add{
    type = "button",
    name = "srm_apply",
    caption = "Appliquer",
    tags = { srm_action = "apply_routes", platform_name = platform.name }
  }
  apply_btn.style.right_margin = 4

  footer.add{
    type = "button",
    name = "srm_close",
    caption = "Fermer",
    tags = { srm_action = "close" }
  }
end

-- ─────────────────────────────────────────────
-- INJECTION DU BOUTON DANS LE PANNEAU PLATFORM
-- ─────────────────────────────────────────────

local function inject_button(player, platform)
  local target_frame = nil

  for _, gui_root in pairs({player.gui.relative, player.gui.left, player.gui.center}) do
    if gui_root["space-platform-hub-gui"] then
      target_frame = gui_root["space-platform-hub-gui"]
      break
    end

    for name, child in pairs(gui_root.children_names and gui_root or {}) do
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
        sprite = "utility/slot_icon_module",
        tooltip = "Gérer les routes de ce vaisseau",
        style = "frame_action_button",
        tags = { srm_action = "open_panel", platform_name = platform.name }
      }
    end
  else
    -- Fallback : bouton dans player.gui.left
    if not player.gui.left["srm_open_button_left"] then
      local btn = player.gui.left.add{
        type = "button",
        name = "srm_open_button_left",
        caption = "🚀 Routes",
        tooltip = "Gérer les routes du vaisseau",
        tags = { srm_action = "open_panel", platform_name = platform.name }
      }
    end
  end
end

local function remove_inject_button(player)
  if player.gui.left["srm_open_button_left"] then
    player.gui.left["srm_open_button_left"].destroy()
  end
end

-- ─────────────────────────────────────────────
-- ÉVÉNEMENTS
-- ─────────────────────────────────────────────

-- Initialisation du storage global
script.on_init(function()
  global.srm_disabled_routes = {}
  global.srm_full_schedules = {}
end)

script.on_configuration_changed(function()
  global.srm_disabled_routes = global.srm_disabled_routes or {}
  global.srm_full_schedules = global.srm_full_schedules or {}
end)

-- Détection de l'ouverture du panneau d'une space platform
script.on_event(defines.events.on_gui_opened, function(event)
  local player = game.players[event.player_index]
  if not player then return end

  -- Vérifie si c'est une space platform hub qui est ouverte
  if event.entity and event.entity.type == "space-platform-hub" then
    local platform = player.surface.platform
    if platform then
      inject_button(player, platform)
    end
  end
end)

script.on_event(defines.events.on_gui_closed, function(event)
  local player = game.players[event.player_index]
  if not player then return end
  remove_inject_button(player)
  destroy_gui(player)
end)

-- Gestion des clics sur les boutons
script.on_event(defines.events.on_gui_click, function(event)
  local player = game.players[event.player_index]
  if not player then return end

  local element = event.element
  if not element or not element.valid then return end
  if not element.tags or not element.tags.srm_action then return end

  local action = element.tags.srm_action

  -- Ouvre le panneau de gestion des routes
  if action == "open_panel" then
    local platform_name = element.tags.platform_name
    -- Cherche la platform par nom
    local platform = nil
    for _, surface in pairs(game.surfaces) do
      if surface.platform and surface.platform.name == platform_name then
        platform = surface.platform
        break
      end
    end
    if platform then
      build_gui(player, platform)
    else
      player.print("[Space Route Manager] Platform introuvable : " .. tostring(platform_name))
    end

  -- Bascule l'état d'une route
  elseif action == "toggle_route" then
    local platform_name = element.tags.platform_name
    local dest_name = element.tags.dest_name
    toggle_route(platform_name, dest_name)

    -- Rafraîchit le GUI
    local platform = nil
    for _, surface in pairs(game.surfaces) do
      if surface.platform and surface.platform.name == platform_name then
        platform = surface.platform
        break
      end
    end
    if platform then
      build_gui(player, platform)
    end

  -- Applique les routes (modifie le schedule)
  elseif action == "apply_routes" then
    local platform_name = element.tags.platform_name
    for _, surface in pairs(game.surfaces) do
      if surface.platform and surface.platform.name == platform_name then
        apply_routes(surface.platform)
        player.print("[Space Route Manager] Routes appliquées pour : " .. platform_name)
        break
      end
    end
    destroy_gui(player)

  -- Ferme le panneau
  elseif action == "close" then
    destroy_gui(player)
  end
end)