-- Design records, importing blueprints into design cells, and capturing cells back into blueprints.
--
-- storage.designs[id] = {
--   id, name,
--   tiers = { [n] = cell },
--   deleted_tiers = { n, ... },   -- tier numbers deleted so far, in order; later tiers moved down each time
-- }
-- Saved blueprints carry bpd_rev = #deleted_tiers at the time they were made, so a blueprint made before a
-- deletion still maps to the right tier (or to none, if its tier was the one deleted).
-- cell = {
--   tier,
--   version,          -- bumped every time a save changes the content
--   export,           -- blueprint export string of the latest saved version
--   snapshot,         -- normalised entity list of the latest version (used by tier diffs / instance updates)
--   snapshots,        -- { [version] = snapshot } for every saved version (old ones are diffed against)
--   radar, marker, outline, label   -- runtime objects on the designer surface
-- }

local surf = require("scripts.surface")
local deepcopy = require("scripts.copy")

local M = {}

M.MARKER = "bpd-marker"

function M.init()
  storage.designs = storage.designs or {}
  storage.next_design_id = storage.next_design_id or 1
  if not (storage.scratch and storage.scratch.valid) then
    storage.scratch = game.create_inventory(1)
  end
end

function M.scratch_blueprint()
  local stack = storage.scratch[1]
  stack.clear()
  stack.set_stack({ name = "blueprint", count = 1 })
  return stack
end

function M.get(id) return storage.designs[id] end

function M.create(name, force)
  local id = storage.next_design_id
  storage.next_design_id = id + 1
  local design = { id = id, name = name or ("Design " .. id), tiers = {} }
  storage.designs[id] = design
  M.ensure_tier(design, 1, force)
  return design
end

function M.ensure_tier(design, tier, force)
  local cell = design.tiers[tier]
  if not cell then
    cell = { tier = tier, version = 0 }
    design.tiers[tier] = cell
  end
  surf.prepare_cell(cell, design, force)
  return cell
end

function M.max_tier(design)
  local n = 0
  for t in pairs(design.tiers) do if t > n then n = t end end
  return n
end

-- Add the next tier, starting as an exact copy of `from_tier`'s cell. Returns the new tier number.
function M.new_tier(design, from_tier, force)
  local tier = M.max_tier(design) + 1
  local cell = M.ensure_tier(design, tier, force)   -- generates chunks, radar, marker
  local surface = surf.get()
  surface.clone_area({
    source_area = surf.area(design.id, from_tier),
    destination_area = surf.area(design.id, tier),
    destination_surface = surface,
    clone_tiles = true,
    clone_entities = true,
    clone_decoratives = false,
    clear_destination_entities = true,
    expand_map = false,
    create_build_effect_smoke = false,
  })
  surf.prepare_cell(cell, design, force)            -- re-find the cloned marker and radar
  return tier
end

-- Map a tier number recorded at revision `rev` (number of deletions back then) to today's numbering.
-- Returns nil if that tier has since been deleted.
function M.resolve_tier(design, tier, rev)
  local deleted = design.deleted_tiers or {}
  for i = (rev or 0) + 1, #deleted do
    local d = deleted[i]
    if tier == d then return nil end
    if tier > d then tier = tier - 1 end
  end
  return tier
end

function M.rev(design)
  return design.deleted_tiers and #design.deleted_tiers or 0
end

function M.marker_tags(design, tier, version)
  return { bpd_design = design.id, bpd_tier = tier, bpd_version = version, bpd_rev = M.rev(design) }
end

-- Destroy everything in a cell's area and put the plain lab floor back.
local function wipe_area(surface, area)
  for _, e in pairs(surface.find_entities_filtered({ area = area })) do
    if e.valid and e.type ~= "character" then e.destroy() end
  end
  local tiles = {}
  for x = area.left_top.x, area.right_bottom.x - 1 do
    for y = area.left_top.y, area.right_bottom.y - 1 do
      local pos = { x = x, y = y }
      tiles[#tiles + 1] = { name = surf.lab_tile_at(pos), position = pos }
    end
  end
  surface.set_tiles(tiles, true, false, true, false)
end

local function drop_render(cell)
  if cell.outline and cell.outline.valid then cell.outline.destroy() end
  if cell.label and cell.label.valid then cell.label.destroy() end
  cell.outline, cell.label = nil, nil
end

-- Re-tag a cell's stored export so it names its current tier number (after tiers moved).
local function refresh_export(design, cell)
  if not cell.export then return end
  local stack = M.scratch_blueprint()
  if stack.import_stack(cell.export) ~= 0 or not stack.is_blueprint_setup() then return end
  for i, e in pairs(stack.get_blueprint_entities() or {}) do
    if e.name == M.MARKER then
      stack.set_blueprint_entity_tags(i, M.marker_tags(design, cell.tier, cell.version))
      break
    end
  end
  stack.label = design.name .. " T" .. cell.tier
  cell.export = stack.export_stack()
end

-- Delete a tier: its designer cell is cleared and every later tier moves down one (cells, numbers, exports).
-- The caller handles placed copies and players on the designer. Returns false if it is the only tier.
function M.delete_tier(design, tier, force)
  local max = M.max_tier(design)
  if max <= 1 or not design.tiers[tier] then return false end
  local surface = surf.get()

  drop_render(design.tiers[tier])
  for t = tier + 1, max do
    -- Move cell t into column t-1 (overwriting whatever is there, including the deleted tier's contents).
    surface.clone_area({
      source_area = surf.area(design.id, t),
      destination_area = surf.area(design.id, t - 1),
      destination_surface = surface,
      clone_tiles = true,
      clone_entities = true,
      clone_decoratives = false,
      clear_destination_entities = true,
      expand_map = false,
      create_build_effect_smoke = false,
    })
    local cell = design.tiers[t]
    drop_render(cell)
    cell.tier = t - 1
    cell.radar, cell.marker = nil, nil
    design.tiers[t - 1] = cell
  end
  design.tiers[max] = nil
  wipe_area(surface, surf.area(design.id, max))

  design.deleted_tiers = design.deleted_tiers or {}
  design.deleted_tiers[#design.deleted_tiers + 1] = tier

  for t = tier, max - 1 do
    local cell = design.tiers[t]
    surf.prepare_cell(cell, design, force)   -- re-find the moved marker and radar, redraw outline/label
    refresh_export(design, cell)
  end
  return true
end

-- Is this cursor thing a blueprint we can read? Accepts an item stack or a library record.
function M.readable_blueprint(player)
  local stack = player.cursor_stack
  if stack and stack.valid_for_read and stack.is_blueprint and stack.is_blueprint_setup() then
    return stack
  end
  local record = player.cursor_record
  if record and record.valid and record.type == "blueprint" and record.is_blueprint_setup() then
    return record
  end
  return nil
end

-- Returns design_id, tier from the marker inside a blueprint (or nil). tier is nil if it was deleted.
function M.identify(blueprint)
  local entities = blueprint.get_blueprint_entities() or {}
  for _, e in pairs(entities) do
    if e.name == M.MARKER and e.tags and e.tags.bpd_design then
      local id, tier = e.tags.bpd_design, e.tags.bpd_tier or 1
      local design = M.get(id)
      if design then tier = M.resolve_tier(design, tier, e.tags.bpd_rev) end
      return id, tier, e.tags.bpd_version
    end
  end
  return nil
end

local function revive_all(entities)
  for _, ghost in pairs(entities) do
    if ghost.valid and (ghost.type == "entity-ghost" or ghost.type == "tile-ghost") then
      M.instant_revive(ghost)
    end
  end
end

-- Turn a ghost on the designer surface into a real (inert) entity, filling module requests.
function M.instant_revive(ghost)
  if ghost.type == "entity-ghost" and ghost.ghost_name == M.MARKER then
    -- Only the mod places markers on the designer surface.
    ghost.destroy()
    return nil
  end
  local _, entity, proxy = ghost.silent_revive({ raise_revive = false })
  if proxy and proxy.valid then
    if entity and entity.valid then
      for _, req in pairs(proxy.item_requests) do
        pcall(entity.insert, { name = req.name, quality = req.quality, count = req.count })
      end
    end
    proxy.destroy()
  end
  if entity and entity.valid then
    entity.disabled_by_script = true
  end
  return entity
end

-- Build a blueprint from the player's cursor into a fresh design. Returns the design.
function M.import(player, blueprint)
  local label = blueprint.label
  local design = M.create((label and label ~= "") and label or nil, player.force)
  local cell = design.tiers[1]
  local surface = surf.get()
  local center = surf.center(design.id, 1)

  local ghosts = blueprint.build_blueprint({
    surface = surface,
    force = player.force,
    position = center,
    build_mode = defines.build_mode.forced,
    raise_built = false,
  })
  revive_all(ghosts)

  -- An imported blueprint may carry a marker from another save/design; keep only ours.
  for _, m in pairs(surface.find_entities_filtered({ name = M.MARKER, area = surf.area(design.id, 1) })) do
    if m ~= cell.marker then m.destroy() end
  end

  local bp_entities = blueprint.get_blueprint_entities() or {}
  if #bp_entities > 0 and #ghosts == 0 then
    player.print({ "bpd.import-nothing-built" })
  end
  return design
end

-- Strip volatile fields so two captures of the same layout compare equal.
local function normalise(entities, marker_index)
  local list = {}
  local origin = entities[marker_index] and entities[marker_index].position or { x = 0, y = 0 }
  for i, e in pairs(entities) do
    if i ~= marker_index then
      local copy = deepcopy(e)
      copy.entity_number = nil
      copy.wires = nil   -- wire references use entity numbers, which shift between captures
      copy.position = { x = e.position.x - origin.x, y = e.position.y - origin.y }
      list[#list + 1] = copy
    end
  end
  table.sort(list, function(a, b)
    if a.position.y ~= b.position.y then return a.position.y < b.position.y end
    if a.position.x ~= b.position.x then return a.position.x < b.position.x end
    return a.name < b.name
  end)
  return list
end

-- Capture a design cell into a blueprint. Returns the scratch stack holding it (valid until next call).
function M.save(design, tier, force)
  local cell = design.tiers[tier]
  local stack = M.scratch_blueprint()
  stack.create_blueprint({
    surface = surf.get(),
    force = force,
    area = surf.area(design.id, tier),
    always_include_tiles = true,
    include_entities = true,
    include_modules = true,
    include_station_names = true,
    include_trains = false,
    include_fuel = true,
  })
  if not stack.is_blueprint_setup() then
    return nil
  end

  local entities = stack.get_blueprint_entities() or {}
  local marker_index
  for i, e in pairs(entities) do
    if e.name == M.MARKER then marker_index = i break end
  end

  local snapshot = normalise(entities, marker_index)
  local changed = serpent.line(snapshot) ~= serpent.line(cell.snapshot or {})
  if changed or cell.version == 0 then
    cell.version = cell.version + 1
    cell.snapshot = snapshot
    cell.snapshots = cell.snapshots or {}
    cell.snapshots[cell.version] = snapshot
  end

  if marker_index then
    stack.set_blueprint_entity_tags(marker_index, M.marker_tags(design, tier, cell.version))
  end
  stack.label = design.name .. " T" .. tier
  cell.export = stack.export_stack()
  return stack, changed
end

-- Give the player the latest saved blueprint of a design tier in their cursor.
function M.give(player, design, tier)
  local cell = design.tiers[tier]
  if not (cell and cell.export) then
    player.print({ "bpd.nothing-saved", design.name })
    return false
  end
  if not player.clear_cursor() then return false end
  local cursor = player.cursor_stack
  if not cursor then return false end
  cursor.import_stack(cell.export)
  return true
end

return M
