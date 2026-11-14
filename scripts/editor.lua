-- Entering and leaving the designer surface, and the "creative" build rules that apply there.
--
-- storage.editing[player_index] = { design_id, tier }
-- The player views the designer surface through remote view; their character stays where it was.

local surf = require("scripts.surface")
local designs = require("scripts.designs")
local instances = require("scripts.instances")

local M = {}

function M.init()
  storage.editing = storage.editing or {}
  storage.transitioning = storage.transitioning or {}
end

-- Set by the GUI module; called whenever a player enters or leaves the designer.
function M.on_change(player) end

function M.is_editing(player)
  return storage.editing[player.index] ~= nil
end

local function on_designer(player)
  return player.controller_type == defines.controllers.remote and player.surface.name == surf.NAME
end

function M.enter(player, design, tier)
  tier = tier or 1
  local current = storage.editing[player.index]
  if current then
    -- Switching cells while already on the designer: save the current one, stay in remote view.
    local cur_design = designs.get(current.design_id)
    if cur_design then designs.save(cur_design, current.tier, player.force) end
    storage.editing[player.index] = nil
  end
  designs.ensure_tier(design, tier, player.force)

  storage.transitioning[player.index] = true
  if not current then player.clear_cursor() end
  player.set_controller({
    type = defines.controllers.remote,
    surface = surf.get(),
    position = surf.center(design.id, tier),
  })
  storage.transitioning[player.index] = nil

  if not on_designer(player) then
    player.print({ "bpd.enter-failed" })
    return false
  end
  storage.editing[player.index] = { design_id = design.id, tier = tier }
  M.on_change(player)
  return true
end

-- opts.save: capture the cell into the design. opts.deliver: put the blueprint in the cursor.
-- opts.exit: leave remote view (false when the player already left on their own).
function M.leave(player, opts)
  local ed = storage.editing[player.index]
  if not ed then return end
  storage.editing[player.index] = nil

  local design = designs.get(ed.design_id)
  local saved, changed
  if design and opts.save then
    saved, changed = designs.save(design, ed.tier, player.force)
  end

  if opts.exit ~= false and player.controller_type == defines.controllers.remote then
    storage.transitioning[player.index] = true
    player.exit_remote_view()
    storage.transitioning[player.index] = nil
  end

  if design and saved and opts.deliver ~= false then
    designs.give(player, design, ed.tier)
    player.print({ changed and "bpd.saved" or "bpd.saved-unchanged", design.name, ed.tier, design.tiers[ed.tier].version })
  elseif design and opts.save and not saved then
    player.print({ "bpd.saved-empty", design.name })
  end
  M.on_change(player)
end

-- Add a tier copied from the one being edited, and move to it.
function M.new_tier(player)
  local ed = storage.editing[player.index]
  local design = ed and designs.get(ed.design_id)
  if not design then return end
  designs.save(design, ed.tier, player.force)
  local tier = designs.new_tier(design, ed.tier, player.force)
  M.enter(player, design, tier)
  player.print({ "bpd.tier-created", design.name, tier, ed.tier })
end

-- Delete the tier being edited (no save). Later tiers move down one; copies placed from the deleted tier
-- are unlinked. Everyone editing this design is moved to the tier now at their old cell's number.
function M.delete_tier(player)
  local ed = storage.editing[player.index]
  local design = ed and designs.get(ed.design_id)
  if not design then return end
  local tier = ed.tier
  if not designs.delete_tier(design, tier, player.force) then
    player.print({ "bpd.tier-delete-last" })
    return
  end
  local unlinked = instances.on_tier_deleted(design.id, tier)

  for index, other in pairs(storage.editing) do
    if other.design_id == design.id then
      if other.tier == tier then
        other.tier = math.max(1, tier - 1)
      elseif other.tier > tier then
        other.tier = other.tier - 1
      end
      local p = game.get_player(index)
      if p and p.valid then
        storage.transitioning[index] = true
        p.set_controller({ type = defines.controllers.remote, surface = surf.get(), position = surf.center(design.id, other.tier) })
        storage.transitioning[index] = nil
        M.on_change(p)
      end
    end
  end
  player.print({ "bpd.tier-deleted", design.name, tier, unlinked })
end

-- Save without leaving.
function M.save_in_place(player)
  local ed = storage.editing[player.index]
  if not ed then return end
  local design = designs.get(ed.design_id)
  if not design then return end
  local saved, changed = designs.save(design, ed.tier, player.force)
  if saved then
    player.print({ changed and "bpd.saved" or "bpd.saved-unchanged", design.name, ed.tier, design.tiers[ed.tier].version })
  end
end

-- The player left the designer by themselves (Escape, switched surface, map view...): auto-save.
function M.check_left(player)
  if storage.transitioning[player.index] then return end
  if storage.editing[player.index] and not on_designer(player) then
    M.leave(player, { save = true, deliver = true, exit = false })
  end
end

---------------------------------------------------------------------------------------------------
-- Creative rules on the designer surface

local function is_designer(entity)
  return entity and entity.valid and entity.surface.name == surf.NAME
end

local function reject(entity, player_index)
  local player = player_index and game.get_player(player_index)
  if player then
    player.create_local_flying_text({ text = { "bpd.outside-cell" }, position = entity.position, surface = entity.surface })
  end
  entity.destroy()
end

function M.on_built(event)
  local entity = event.entity
  if not is_designer(entity) then return end
  if not surf.cell_at(entity.position) then
    reject(entity, event.player_index)
    return
  end
  if entity.type == "entity-ghost" or entity.type == "tile-ghost" then
    designs.instant_revive(entity)
  elseif entity.name ~= designs.MARKER then
    entity.disabled_by_script = true
  end
end

function M.on_marked_for_deconstruction(event)
  local entity = event.entity
  if not is_designer(entity) then return end
  if entity.name == designs.MARKER or entity.name == "bpd-editor-radar" then
    entity.cancel_deconstruction(entity.force)
    return
  end
  if entity.name == "deconstructible-tile-proxy" then
    local pos = entity.position
    local surface = entity.surface
    entity.destroy()
    surface.set_tiles({ { name = surf.lab_tile_at(pos), position = pos } }, true, false, true, false)
    return
  end
  entity.destroy()
end

function M.on_marked_for_upgrade(event)
  local entity = event.entity
  if not is_designer(entity) then return end
  local target, quality = event.target, event.quality
  local surface, force = entity.surface, entity.force
  local params = {
    name = target.name,
    quality = quality and quality.name,
    position = entity.position,
    direction = entity.direction,
    force = force,
    fast_replace = true,
    spill = false,
    raise_built = false,
    create_build_effect_smoke = false,
  }
  local new = surface.create_entity(params)
  if new and new.valid then
    new.disabled_by_script = true
  else
    entity.cancel_upgrade(force)
  end
end

return M
