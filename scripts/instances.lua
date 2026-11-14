-- Placed copies of designs, tracked through the design marker in each placed blueprint.
--
-- storage.instances[unit_number] = {
--   id, marker (LuaEntity), design, tier, version,
--   surface_index, position, force, t = { k, f },  -- transform from design space to world
--   label (LuaRenderObject, alt-mode only)
-- }

local surf = require("scripts.surface")
local designs = require("scripts.designs")
local transform = require("scripts.transform")
local diff = require("scripts.diff")

local M = {}

local MARKER = designs.MARKER

function M.init()
  storage.instances = storage.instances or {}
  storage.pre_build = storage.pre_build or {}
end

local function label_text(inst)
  local design = designs.get(inst.design)
  return { "bpd.instance-label", design and design.name or "?", inst.tier, inst.version }
end

local function refresh_label(inst)
  if not (inst.marker and inst.marker.valid) then return end
  if inst.label and inst.label.valid then
    inst.label.text = label_text(inst)
    return
  end
  inst.label = rendering.draw_text({
    text = label_text(inst),
    surface = inst.marker.surface,
    target = { entity = inst.marker, offset = { 0, -0.9 } },
    color = { 0.6, 0.8, 1 },
    scale = 1.2,
    alignment = "center",
    only_in_alt_mode = true,
  })
end

function M.for_design(design_id)
  local list = {}
  for _, inst in pairs(storage.instances) do
    if inst.design == design_id then list[#list + 1] = inst end
  end
  table.sort(list, function(a, b) return a.id < b.id end)
  return list
end

function M.is_outdated(inst)
  local design = designs.get(inst.design)
  local cell = design and design.tiers[inst.tier]
  return cell ~= nil and inst.version < cell.version
end

---------------------------------------------------------------------------------------------------
-- Registration

function M.on_pre_build(event)
  storage.pre_build[event.player_index] = {
    tick = event.tick,
    t = transform.from_placement(event.direction, event.flip_horizontal or event.mirror, event.flip_vertical),
  }
end

-- A marker ghost was placed outside the designer. Returns true if handled.
function M.on_marker_ghost(ghost, tags, player_index)
  tags = tags or ghost.tags or {}
  local design = tags.bpd_design and designs.get(tags.bpd_design)
  local tier = design and designs.resolve_tier(design, tags.bpd_tier or 1, tags.bpd_rev)
  if not (tier and design.tiers[tier]) then
    ghost.destroy()   -- a marker from another save, an unknown design, or a deleted tier: drop it
    return true
  end

  local placement = transform.IDENTITY
  local pending = player_index and storage.pre_build[player_index]
  if pending and pending.tick == game.tick then placement = pending.t end
  local source = { k = tags.bpd_k or 0, f = tags.bpd_f or false }   -- set when copied from a placed copy
  local t = transform.compose(placement, source)

  local _, marker = ghost.silent_revive({ raise_revive = false })
  if not (marker and marker.valid) then return true end

  local inst = {
    id = marker.unit_number,
    marker = marker,
    design = design.id,
    tier = tier,
    version = tags.bpd_version or 1,
    surface_index = marker.surface.index,
    position = marker.position,
    force = marker.force.name,
    t = t,
  }
  storage.instances[inst.id] = inst
  script.register_on_object_destroyed(marker)
  refresh_label(inst)
  return true
end

function M.on_object_destroyed(event)
  local inst = event.useful_id and storage.instances[event.useful_id]
  if inst then
    if inst.label and inst.label.valid then inst.label.destroy() end
    storage.instances[event.useful_id] = nil
  end
end

-- When a player copies/blueprints a placed copy (or a designer cell), tag the marker so the new
-- blueprint is recognised too.
function M.on_player_setup_blueprint(event)
  local bp = event.stack or event.record
  if not bp then return end
  local ok, mapping = pcall(function() return event.mapping.get() end)
  if not ok or not mapping then return end
  for index, entity in pairs(mapping) do
    if entity.valid and entity.name == MARKER then
      if entity.surface.name == surf.NAME then
        local id, tier = surf.cell_at(entity.position)
        local design = id and designs.get(id)
        local cell = design and design.tiers[tier]
        if cell then
          bp.set_blueprint_entity_tags(index, designs.marker_tags(design, tier, cell.version))
        end
      else
        local inst = storage.instances[entity.unit_number]
        local design = inst and designs.get(inst.design)
        if design then
          local tags = designs.marker_tags(design, inst.tier, inst.version)
          tags.bpd_k, tags.bpd_f = inst.t.k, inst.t.f
          bp.set_blueprint_entity_tags(index, tags)
        end
      end
    end
  end
end

-- Stop tracking a copy. Its buildings stay; its marker is removed so nothing points at the old tier.
function M.unlink(inst)
  if inst.label and inst.label.valid then inst.label.destroy() end
  storage.instances[inst.id] = nil
  if inst.marker and inst.marker.valid then inst.marker.destroy() end
end

function M.count_on_tier(design_id, tier)
  local n = 0
  for _, inst in pairs(storage.instances) do
    if inst.design == design_id and inst.tier == tier then n = n + 1 end
  end
  return n
end

-- A tier of a design was deleted: unlink copies on it and renumber copies on later tiers.
-- Returns how many copies were unlinked.
function M.on_tier_deleted(design_id, tier)
  local unlinked = 0
  for _, inst in pairs(M.for_design(design_id)) do
    if inst.tier == tier then
      M.unlink(inst)
      unlinked = unlinked + 1
    elseif inst.tier > tier then
      inst.tier = inst.tier - 1
      refresh_label(inst)
    end
  end
  return unlinked
end

---------------------------------------------------------------------------------------------------
-- Updating

local function context(inst, player)
  local surface = game.surfaces[inst.surface_index]
  if not (surface and inst.marker and inst.marker.valid) then return nil end
  return {
    surface = surface,
    force = inst.force,
    origin = inst.marker.position,
    t = inst.t,
    player = player,
    scratch = storage.scratch[1],
  }
end

-- Move a copy to (target_tier, latest version). mode = "safe" | "exact". Returns counts or nil, reason.
function M.apply(inst, player, target_tier, mode)
  local design = designs.get(inst.design)
  if not design then return nil, "bpd.err-no-design" end
  local to_cell = design.tiers[target_tier]
  if not (to_cell and to_cell.snapshot and to_cell.version > 0) then return nil, "bpd.err-tier-unsaved" end
  local ctx = context(inst, player)
  if not ctx then return nil, "bpd.err-gone" end

  local counts
  if mode == "exact" then
    counts = diff.force_match(ctx, to_cell.snapshot, { [MARKER] = true }, to_cell.tiles)
  else
    local from_cell = design.tiers[inst.tier]
    local old = from_cell and from_cell.snapshots and from_cell.snapshots[inst.version]
    local old_tiles = from_cell and from_cell.tile_snapshots and from_cell.tile_snapshots[inst.version]
    -- Without the old snapshot we can't know what to remove; only add/re-paste.
    counts = diff.apply(ctx, diff.plan(old or {}, to_cell.snapshot))
    diff.apply_tiles(ctx, diff.plan_tiles(old_tiles, to_cell.tiles), counts)
  end
  inst.tier = target_tier
  inst.version = to_cell.version
  refresh_label(inst)
  return counts
end

function M.update(inst, player, mode) return M.apply(inst, player, inst.tier, mode) end

function M.upgrade(inst, player)
  return M.apply(inst, player, inst.tier + 1, "safe")
end

-- The reverse of upgrade: diff from this copy's current tier/version back to the previous tier's latest.
function M.downgrade(inst, player)
  if inst.tier <= 1 then return nil, "bpd.err-lowest-tier" end
  return M.apply(inst, player, inst.tier - 1, "safe")
end

return M
