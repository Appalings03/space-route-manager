local GUI_NAME = "srm_route_panel"

-- ─────────────────────────────────────────────
-- UTILITAIRES
-- ─────────────────────────────────────────────

local function find_platform_by_name(platform_name)
  for _, surface in pairs(game.surfaces) do
    if surface.platform and surface.platform.name == platform_name then
      return surface.platform
    end
  end
  return nil
end

local function is_planet_forbidden(platform_name, planet_name)
  if not storage.srm_forbidden then return false end
  local key = platform_name .. "|" .. planet_name
  return storage.srm_forbidden[key] == true
end

local function set_planet_forbidden(platform_name, planet_name, state)
  storage.srm_forbidden = storage.srm_forbidden or {}
  local key = platform_name .. "|" .. planet_name
  storage.srm_forbidden[key] = state or nil
end

-- ─────────────────────────────────────────────
-- GRAPHE DES CONNEXIONS (via prototypes)
-- ─────────────────────────────────────────────

-- Construit le graphe en lisant les connexions depuis chaque planete
-- game.planets expose les connexions via planet.connected_to
-- Retourne { ["Nauvis"] = { ["Gleba"]=true, ... }, ... }
local function build_graph()
  local graph = {}
  -- Methode 1 : via les surfaces de type platform en transit (LuaSpaceConnectionPrototype)
  -- On passe par prototypes au sens large : on cherche dans data.raw via helpers
  -- Methode la plus fiable : lire depuis chaque surface spatiale connue
  -- En Factorio 2.0, game.planets retourne des LuaPlanet avec leurs connexions
  for name, planet in pairs(game.planets) do
    graph[name] = graph[name] or {}
    -- LuaPlanet.connected_to liste les planetes directement connectees
    if planet.connected_to then
      for _, neighbor in pairs(planet.connected_to) do
        local nb = neighbor.name
        graph[name][nb] = true
        graph[nb] = graph[nb] or {}
        graph[nb][name] = true
      end
    end
  end
  return graph
end

-- Retourne la liste de toutes les planetes accessibles depuis une planete de depart
-- (utile pour afficher les planetes que le vaisseau pourrait traverser)
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

-- BFS : chemin le plus court de start_name a goal_name en evitant forbidden
local function bfs_path(graph, start_name, goal_name, forbidden)
  if start_name == goal_name then return {start_name} end
  local visited = { [start_name] = true }
  local queue = { { name = start_name, path = {start_name} } }
  while #queue > 0 do
    local current = table.remove(queue, 1)
    for neighbor, _ in pairs(graph[current.name] or {}) do
      if not visited[neighbor] then
        if neighbor == goal_name or not forbidden[neighbor] then
          visited[neighbor] = true
          local new_path = {}
          for _, p in ipairs(current.path) do table.insert(new_path, p) end
          table.insert(new_path, neighbor)
          if neighbor == goal_name then return new_path end
          table.insert(queue, { name = neighbor, path = new_path })
        end
      end
    end
  end
  return nil
end

-- Cherche un LuaSpaceLocationPrototype par nom dans les prototypes
local function get_space_location_proto(name)
  -- Cherche d'abord dans les planetes
  -- game.planets est le seul acces fiable en runtime Factorio 2.0
  if game.planets[name] then return game.planets[name] end
  return nil
end

-- ─────────────────────────────────────────────
-- ARRET ET RELANCE DU VAISSEAU
-- ─────────────────────────────────────────────

-- Met le vaisseau en orbite et sauvegarde son etat pour le relancer apres
local function stop_platform(platform)
  -- Sauvegarde le schedule avant modification
  storage.srm_full_schedules = storage.srm_full_schedules or {}
  if platform.schedule and platform.schedule.records and #platform.schedule.records > 0 then
    if not storage.srm_full_schedules[platform.name] then
      storage.srm_full_schedules[platform.name] = platform.schedule.records
    end
  end

  -- Supprime le schedule pour arreter le vaisseau en orbite
  -- (nil = pas de destination, le vaisseau reste sur place)
  platform.schedule = nil
end

-- Applique le nouveau schedule avec detours et relance le vaisseau
local function apply_and_restart(platform, player)
  storage.srm_full_schedules = storage.srm_full_schedules or {}
  storage.srm_forbidden = storage.srm_forbidden or {}

  local original = storage.srm_full_schedules[platform.name]
  if not original or #original == 0 then
    if player then
      player.print("[Space Route Manager] Aucune route sauvegardee pour " .. platform.name, {r=1, g=0.6, b=0})
    end
    return
  end

  -- Construit la table des planetes interdites pour ce vaisseau
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

  -- Point de depart : ou est le vaisseau maintenant
  local current_loc = platform.space_location
  local prev_name = current_loc and current_loc.name or nil

  for i, record in ipairs(original) do
    local dest_name = record.planet and record.planet.name or nil

    if not dest_name then
      -- Enregistrement sans planete cible : garde tel quel
      table.insert(new_records, record)
    else
      if prev_name and prev_name ~= dest_name then
        local path = bfs_path(graph, prev_name, dest_name, forbidden)

        if not path then
          table.insert(warnings, "Impossible d'eviter les planetes interdites de " .. prev_name .. " vers " .. dest_name)
          table.insert(new_records, record)
        elseif #path > 2 then
          -- Injecte les waypoints intermediaires (sans arret)
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

  -- Securise l'index courant
  local current_index = (platform.schedule and platform.schedule.current) or 1
  if #new_records == 0 then
    current_index = 1
  elseif current_index > #new_records then
    current_index = 1
  elseif current_index < 1 then
    current_index = 1
  end

  -- Applique et relance
  platform.schedule = { current = current_index, records = new_records }

  if player then
    player.print("[Space Route Manager] Vaisseau relance : " .. platform.name, {r=0.4, g=0.9, b=0.4})
    for _, w in ipairs(warnings) do
      player.print("[Space Route Manager] ATTENTION : " .. w, {r=1, g=0.8, b=0})
    end
  end
end

-- ─────────────────────────────────────────────
-- GUI
-- ─────────────────────────────────────────────

local function destroy_gui(player)
  if player.gui.relative[GUI_NAME] then player.gui.relative[GUI_NAME].destroy() end
  if player.gui.screen[GUI_NAME] then player.gui.screen[GUI_NAME].destroy() end
end

local function build_gui(player, platform)
  destroy_gui(player)

  -- Sauvegarde le schedule original si pas encore fait
  storage.srm_full_schedules = storage.srm_full_schedules or {}
  if platform.schedule and platform.schedule.records and #platform.schedule.records > 0 then
    if not storage.srm_full_schedules[platform.name] then
      storage.srm_full_schedules[platform.name] = platform.schedule.records
    end
  end

  -- Construit le graphe et la liste de toutes les planetes atteignables
  local graph = build_graph()

  -- Planete de depart = position actuelle OU premiere planete du schedule
  local start_name = nil
  if platform.space_location then
    start_name = platform.space_location.name
  elseif storage.srm_full_schedules[platform.name] then
    local first = storage.srm_full_schedules[platform.name][1]
    if first and first.planet then start_name = first.planet.name end
  end

  -- Liste toutes les planetes que le vaisseau pourrait traverser
  local all_planets = {}
  if start_name then
    all_planets = get_all_reachable_planets(graph, start_name)
  else
    -- Fallback : toutes les planetes du jeu
    for name, _ in pairs(game.planets) do
      table.insert(all_planets, name)
    end
    table.sort(all_planets)
  end

  -- Interface
  local frame = player.gui.screen.add{
    type = "frame",
    name = GUI_NAME,
    caption = "Routes interdites — " .. platform.name,
    direction = "vertical"
  }
  frame.auto_center = true
  frame.style.minimal_width = 340

  local subtitle = frame.add{
    type = "label",
    caption = "Cochez les planetes a eviter.\nLe vaisseau sera arrete puis relance avec un chemin alternatif."
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
    tbl.add{ type = "label", caption = "Aucune planete trouvee." }
  else
    for _, pname in ipairs(all_planets) do
      local forbidden = is_planet_forbidden(platform.name, pname)
      local row = tbl.add{ type = "flow", direction = "horizontal" }
      row.style.vertical_align = "center"
      row.style.bottom_margin = 2

      row.add{
        type = "checkbox",
        name = "srm_cb_" .. pname,
        caption = (forbidden and "[color=red]" or "") .. pname .. (forbidden and "[/color]" or ""),
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

  -- Bouton reset
  footer.add{
    type = "button",
    name = "srm_reset",
    caption = "Reinitialiser",
    tags = { srm_action = "reset", platform_name = platform.name }
  }.style.right_margin = 6

  -- Bouton appliquer (arrete + recalcule + relance)
  footer.add{
    type = "button",
    name = "srm_apply",
    caption = "Arreter et appliquer",
    tags = { srm_action = "apply", platform_name = platform.name }
  }.style.right_margin = 4

  footer.add{
    type = "button",
    name = "srm_close",
    caption = "Fermer",
    tags = { srm_action = "close" }
  }
end

-- ─────────────────────────────────────────────
-- BOUTON DANS LE PANNEAU PLATFORM
-- ─────────────────────────────────────────────

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
        tooltip = "Gerer les planetes interdites pour ce vaisseau",
        style = "frame_action_button",
        tags = { srm_action = "open_panel", platform_name = platform.name }
      }
    end
  elseif not player.gui.left["srm_open_button_left"] then
    player.gui.left.add{
      type = "button",
      name = "srm_open_button_left",
      caption = "Routes interdites",
      tooltip = "Gerer les planetes interdites pour ce vaisseau",
      tags = { srm_action = "open_panel", platform_name = platform.name }
    }
  end
end

local function remove_inject_button(player)
  if player.gui.left["srm_open_button_left"] then
    player.gui.left["srm_open_button_left"].destroy()
  end
end

-- ─────────────────────────────────────────────
-- EVENEMENTS
-- ─────────────────────────────────────────────

script.on_init(function()
  storage.srm_forbidden = {}
  storage.srm_full_schedules = {}
end)

script.on_configuration_changed(function()
  storage.srm_forbidden = storage.srm_forbidden or {}
  storage.srm_full_schedules = storage.srm_full_schedules or {}
end)

script.on_event(defines.events.on_gui_opened, function(event)
  local player = game.players[event.player_index]
  if not player then return end
  if event.entity and event.entity.type == "space-platform-hub" then
    local platform = player.surface.platform
    if platform then inject_button(player, platform) end
  end
end)

script.on_event(defines.events.on_gui_closed, function(event)
  local player = game.players[event.player_index]
  if not player then return end
  remove_inject_button(player)
  destroy_gui(player)
end)

script.on_event(defines.events.on_gui_checked_state_changed, function(event)
  local player = game.players[event.player_index]
  if not player then return end
  local el = event.element
  if not el or not el.valid then return end
  if not el.tags or el.tags.srm_action ~= "toggle_planet" then return end

  set_planet_forbidden(el.tags.platform_name, el.tags.planet_name, el.state)
end)

script.on_event(defines.events.on_gui_click, function(event)
  local player = game.players[event.player_index]
  if not player then return end

  local el = event.element
  if not el or not el.valid then return end
  if not el.tags or not el.tags.srm_action then return end

  local action = el.tags.srm_action

  if action == "open_panel" then
    local platform = find_platform_by_name(el.tags.platform_name)
    if platform then
      build_gui(player, platform)
    else
      player.print("[Space Route Manager] Vaisseau introuvable : " .. tostring(el.tags.platform_name))
    end

  elseif action == "apply" then
    local platform = find_platform_by_name(el.tags.platform_name)
    if platform then
      -- 1. Arrete le vaisseau (schedule vide)
      stop_platform(platform)
      -- 2. Petit delai d'1 tick puis recalcule et relance
      -- (on utilise on_tick une seule fois pour laisser le jeu traiter l'arret)
      storage.srm_pending_apply = storage.srm_pending_apply or {}
      storage.srm_pending_apply[platform.name] = {
        tick = game.tick + 2,
        player_index = player.index
      }
      player.print("[Space Route Manager] Vaisseau en cours d'arret...", {r=1, g=0.9, b=0.3})
    end
    destroy_gui(player)

  elseif action == "reset" then
    local platform = find_platform_by_name(el.tags.platform_name)
    if platform then
      -- Supprime toutes les interdictions pour ce vaisseau
      storage.srm_forbidden = storage.srm_forbidden or {}
      for key, _ in pairs(storage.srm_forbidden) do
        local pname, _ = key:match("^(.+)|(.+)$")
        if pname == platform.name then
          storage.srm_forbidden[key] = nil
        end
      end
      -- Restaure le schedule original
      if storage.srm_full_schedules and storage.srm_full_schedules[platform.name] then
        local original = storage.srm_full_schedules[platform.name]
        if original and #original > 0 then
          platform.schedule = { current = 1, records = original }
        else
          platform.schedule = nil
        end
        player.print("[Space Route Manager] Routes restaurees pour " .. platform.name, {r=0.4, g=0.9, b=0.4})
      end
    end
    destroy_gui(player)

  elseif action == "close" then
    destroy_gui(player)
  end
end)

-- Gere le relancement apres l'arret (attend 2 ticks)
script.on_event(defines.events.on_tick, function(event)
  if not storage.srm_pending_apply then return end
  if not next(storage.srm_pending_apply) then return end

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