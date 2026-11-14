local surf = require("scripts.surface")
local designs = require("scripts.designs")
local editor = require("scripts.editor")
local instances = require("scripts.instances")
local gui = require("scripts.gui")

local function init()
  designs.init()
  editor.init()
  instances.init()
end

script.on_init(function()
  init()
  surf.get()
end)
script.on_configuration_changed(init)

-- Hotkey / shortcut:
--   on the designer  -> save & return
--   holding a blueprint -> edit it on the designer (importing it as a new design if it isn't one yet)
--   otherwise        -> toggle the Designs window
local function toggle(player)
  if editor.is_editing(player) then
    editor.leave(player, { save = true, deliver = true })
    return
  end

  local blueprint = designs.readable_blueprint(player)
  if blueprint then
    local id, tier = designs.identify(blueprint)
    local design = id and designs.get(id)
    if design and design.tiers[tier] then
      editor.enter(player, design, tier)
    else
      design = designs.import(player, blueprint)
      player.print({ "bpd.imported", design.name })
      editor.enter(player, design, 1)
    end
    return
  end

  if player.gui.screen.bpd_window then
    gui.close_window(player)
  else
    gui.open_window(player)
  end
end

script.on_event("bpd-toggle", function(event)
  toggle(game.get_player(event.player_index))
end)

script.on_event(defines.events.on_lua_shortcut, function(event)
  if event.prototype_name == "bpd-toggle" then
    toggle(game.get_player(event.player_index))
  end
end)

-- Auto-save when the player leaves the designer on their own.
script.on_event(defines.events.on_player_controller_changed, function(event)
  editor.check_left(game.get_player(event.player_index))
end)
script.on_event(defines.events.on_player_changed_surface, function(event)
  editor.check_left(game.get_player(event.player_index))
end)

local function on_built(event)
  local entity = event.entity
  if not (entity and entity.valid) then return end
  if entity.surface.name == surf.NAME then
    editor.on_built(event)
  elseif entity.type == "entity-ghost" and entity.ghost_name == designs.MARKER then
    instances.on_marker_ghost(entity, event.tags, event.player_index)
  end
end
script.on_event(defines.events.on_built_entity, on_built)
script.on_event(defines.events.script_raised_built, on_built)
script.on_event(defines.events.on_pre_build, instances.on_pre_build)
script.on_event(defines.events.on_object_destroyed, instances.on_object_destroyed)
script.on_event(defines.events.on_player_setup_blueprint, instances.on_player_setup_blueprint)
script.on_event(defines.events.on_marked_for_deconstruction, editor.on_marked_for_deconstruction)
script.on_event(defines.events.on_marked_for_upgrade, editor.on_marked_for_upgrade)
script.on_nth_tick(30, editor.on_nth_tick)

script.on_event(defines.events.on_gui_click, gui.on_click)
script.on_event(defines.events.on_gui_text_changed, gui.on_text_changed)
script.on_event(defines.events.on_gui_closed, gui.on_closed)
script.on_event(defines.events.on_gui_checked_state_changed, gui.on_checked_state_changed)
script.on_event(defines.events.on_gui_selection_state_changed, gui.on_selection_state_changed)
script.on_event(defines.events.on_gui_selected_tab_changed, gui.on_selected_tab_changed)

script.on_event(defines.events.on_player_removed, function(event)
  storage.editing[event.player_index] = nil
end)
