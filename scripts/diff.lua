-- Diff engine shared by tier upgrades and instance updates.
--
-- A snapshot is a list of blueprint entities with positions relative to the design marker
-- (see designs.save). Plans are computed in design space and applied at a placed copy through
-- its transform (scripts/transform.lua).

local transform = require("scripts.transform")
local deepcopy = require("scripts.copy")

local M = {}

local EPS = 0.01
local IGNORED_TYPES = {
  ["character"] = true, ["item-request-proxy"] = true, ["tile-ghost"] = true,
  ["deconstructible-tile-proxy"] = true, ["item-entity"] = true, ["corpse"] = true,
}

local function pos_key(p) return string.format("%.1f,%.1f", p.x, p.y) end

-- Everything except identity/placement fields: if this differs, settings need re-pasting.
local function settings_line(e)
  local c = {}
  for k, v in pairs(e) do
    if k ~= "position" and k ~= "name" and k ~= "direction" and k ~= "entity_number" and k ~= "wires" then
      c[k] = v
    end
  end
  return serpent.line(c, { sortkeys = true })
end

-- Compute what to do to turn `old` into `new`.
-- Returns { add = {e...}, remove = {e...}, upgrade = {{from=e, to=e}...}, paste = {e...} }
function M.plan(old, new)
  local plan = { add = {}, remove = {}, upgrade = {}, paste = {} }
  local by_pos = {}
  for _, e in pairs(new) do
    local k = pos_key(e.position)
    by_pos[k] = by_pos[k] or {}
    table.insert(by_pos[k], { e = e, used = false })
  end

  local unmatched_old = {}
  for _, o in pairs(old) do
    local slot = by_pos[pos_key(o.position)]
    local match
    if slot then
      for _, n in pairs(slot) do
        if not n.used and n.e.name == o.name then match = n break end
      end
    end
    if match then
      match.used = true
      if (match.e.direction or 0) ~= (o.direction or 0) then
        table.insert(plan.remove, o)
        table.insert(plan.add, match.e)
      elseif settings_line(match.e) ~= settings_line(o) then
        table.insert(plan.paste, match.e)
      end
    else
      table.insert(unmatched_old, o)
    end
  end

  -- Same position, different entity: an upgrade candidate (decided at apply time).
  for _, o in pairs(unmatched_old) do
    local slot = by_pos[pos_key(o.position)]
    local pair
    if slot then
      for _, n in pairs(slot) do
        if not n.used then pair = n break end
      end
    end
    if pair then
      pair.used = true
      table.insert(plan.upgrade, { from = o, to = pair.e })
    else
      table.insert(plan.remove, o)
    end
  end

  for _, slot in pairs(by_pos) do
    for _, n in pairs(slot) do
      if not n.used then table.insert(plan.add, n.e) end
    end
  end
  return plan
end

function M.is_empty(plan)
  return #plan.add + #plan.remove + #plan.upgrade + #plan.paste == 0
end

---------------------------------------------------------------------------------------------------
-- Applying at a placed copy. `ctx` = { surface, force, origin, t, player?, scratch = LuaItemStack }

local function find_at(ctx, name, world)
  local area = { { world.x - 0.1, world.y - 0.1 }, { world.x + 0.1, world.y + 0.1 } }
  for _, e in pairs(ctx.surface.find_entities_filtered({ area = area, force = ctx.force })) do
    local ename = (e.type == "entity-ghost") and e.ghost_name or e.name
    if ename == name and math.abs(e.position.x - world.x) < EPS and math.abs(e.position.y - world.y) < EPS then
      return e
    end
  end
  return nil
end

local function remove_entity(ctx, e)
  if e.type == "entity-ghost" then
    e.destroy()
  else
    e.order_deconstruction(ctx.force, ctx.player)
  end
end

-- Place one snapshot entity as a ghost (or paste its settings onto a matching entity already there).
local function build_one(ctx, snap, mode)
  local e = deepcopy(snap)
  e.entity_number = 1
  e.position = { x = 0, y = 0 }
  e.wires = nil
  e.direction = transform.direction(ctx.t, snap.direction)
  if ctx.t.f then e.mirror = not e.mirror or nil end
  local stack = ctx.scratch
  stack.clear()
  stack.set_stack({ name = "blueprint", count = 1 })
  stack.set_blueprint_entities({ e })
  stack.build_blueprint({
    surface = ctx.surface,
    force = ctx.force,
    position = transform.world(ctx.t, ctx.origin, snap.position),
    build_mode = mode or defines.build_mode.forced,
    by_player = ctx.player,
    raise_built = ctx.player == nil,
  })
end

local function can_fast_replace(from_name, to_name)
  local a, b = prototypes.entity[from_name], prototypes.entity[to_name]
  if not (a and b) then return false end
  return a.fast_replaceable_group ~= nil and a.fast_replaceable_group == b.fast_replaceable_group
    and a.tile_width == b.tile_width and a.tile_height == b.tile_height
end

-- Returns counts { add, remove, upgrade, paste }.
function M.apply(ctx, plan)
  local counts = { add = 0, remove = 0, upgrade = 0, paste = 0 }

  for _, o in pairs(plan.remove) do
    local e = find_at(ctx, o.name, transform.world(ctx.t, ctx.origin, o.position))
    if e then remove_entity(ctx, e) counts.remove = counts.remove + 1 end
  end

  for _, u in pairs(plan.upgrade) do
    local world = transform.world(ctx.t, ctx.origin, u.from.position)
    local e = find_at(ctx, u.from.name, world)
    local same_dir = (u.from.direction or 0) == (u.to.direction or 0)
    if e and e.type ~= "entity-ghost" and same_dir and can_fast_replace(u.from.name, u.to.name) then
      e.order_upgrade({ target = { name = u.to.name, quality = u.to.quality or "normal" }, force = ctx.force, player = ctx.player })
      if settings_line(u.from) ~= settings_line(u.to) then build_one(ctx, u.to) end
    else
      if e then remove_entity(ctx, e) end
      build_one(ctx, u.to)
    end
    counts.upgrade = counts.upgrade + 1
  end

  for _, n in pairs(plan.add) do build_one(ctx, n) counts.add = counts.add + 1 end
  for _, n in pairs(plan.paste) do build_one(ctx, n) counts.paste = counts.paste + 1 end
  return counts
end

---------------------------------------------------------------------------------------------------
-- Tiles. A tile list is { { name, position = tile centre relative to the marker } ... } (see designs.save).

-- Compute what to do to turn tile list `old` into `new`: { place = {t...}, remove = {t...} }.
function M.plan_tiles(old, new)
  local plan = { place = {}, remove = {} }
  local was = {}
  for _, t in pairs(old or {}) do was[pos_key(t.position)] = t.name end
  local now = {}
  for _, t in pairs(new or {}) do
    local k = pos_key(t.position)
    now[k] = true
    if was[k] ~= t.name then table.insert(plan.place, t) end
  end
  for _, t in pairs(old or {}) do
    if not now[pos_key(t.position)] then table.insert(plan.remove, t) end
  end
  return plan
end

-- World tile position of a design-space tile centre at a copy.
local function world_tile(ctx, t)
  local c = transform.world(ctx.t, ctx.origin, t.position)
  return { x = math.floor(c.x), y = math.floor(c.y) }
end

local function tile_ghosts_at(ctx, pos)
  return ctx.surface.find_entities_filtered({
    area = { { pos.x + 0.1, pos.y + 0.1 }, { pos.x + 0.9, pos.y + 0.9 } },
    type = "tile-ghost", force = ctx.force,
  })
end

-- Ghost `name` onto a world tile, unless it is already that tile (or already ghosted). Returns true if placed.
local function place_tile(ctx, name, pos)
  local ghosts = tile_ghosts_at(ctx, pos)
  for _, g in pairs(ghosts) do
    if g.valid and g.ghost_name == name then return false end
  end
  local tile = ctx.surface.get_tile(pos.x, pos.y)
  if tile.valid and tile.name == name then
    if tile.to_be_deconstructed(ctx.force) then tile.cancel_deconstruction(ctx.force, ctx.player) end
    return false
  end
  for _, g in pairs(ghosts) do if g.valid then g.destroy() end end
  local ok, ghost = pcall(ctx.surface.create_entity, {
    name = "tile-ghost", inner_name = name, position = { x = pos.x + 0.5, y = pos.y + 0.5 },
    force = ctx.force, player = ctx.player,
  })
  return ok and ghost ~= nil
end

-- Mark a world tile for removal if it is (or is ghosted as) `name`. Returns true if anything was done.
local function remove_tile(ctx, name, pos)
  local done = false
  for _, g in pairs(tile_ghosts_at(ctx, pos)) do
    if g.valid and g.ghost_name == name then g.destroy() done = true end
  end
  local tile = ctx.surface.get_tile(pos.x, pos.y)
  if tile.valid and tile.name == name and not tile.to_be_deconstructed(ctx.force) then
    if tile.order_deconstruction(ctx.force, ctx.player) then done = true end
  end
  return done
end

-- Apply a tile plan at a copy. Adds to counts.add / counts.remove.
function M.apply_tiles(ctx, plan, counts)
  for _, t in pairs(plan.remove) do
    if remove_tile(ctx, t.name, world_tile(ctx, t)) then counts.remove = counts.remove + 1 end
  end
  for _, t in pairs(plan.place) do
    if place_tile(ctx, t.name, world_tile(ctx, t)) then counts.add = counts.add + 1 end
  end
  return counts
end

-- Tiles a blueprint can hold (placeable by an item); natural ground is never touched by force match.
local blueprintable
local function blueprintable_tiles()
  if not blueprintable then
    blueprintable = {}
    for name, proto in pairs(prototypes.tile) do
      if proto.items_to_place_this and #proto.items_to_place_this > 0 then
        blueprintable[#blueprintable + 1] = name
      end
    end
  end
  return blueprintable
end

-- Make the tiles inside `area` exactly match `tiles`: other placeable tiles are marked for removal,
-- stray tile ghosts are dropped, and every master tile is ghosted where it differs.
function M.force_match_tiles(ctx, tiles, area, counts)
  local wanted = {}
  for _, t in pairs(tiles or {}) do
    local p = world_tile(ctx, t)
    wanted[p.x .. "," .. p.y] = t.name
  end
  local box = { area.left_top, area.right_bottom }
  for _, g in pairs(ctx.surface.find_entities_filtered({ area = box, type = "tile-ghost", force = ctx.force })) do
    local p = g.position
    if g.valid and wanted[math.floor(p.x) .. "," .. math.floor(p.y)] ~= g.ghost_name then
      g.destroy()
    end
  end
  local names = blueprintable_tiles()
  if #names > 0 then
    for _, tile in pairs(ctx.surface.find_tiles_filtered({ area = box, name = names })) do
      local p = tile.position
      local want = wanted[p.x .. "," .. p.y]
      if want == nil and not tile.to_be_deconstructed(ctx.force) then
        if tile.order_deconstruction(ctx.force, ctx.player) then counts.remove = counts.remove + 1 end
      end
    end
  end
  for _, t in pairs(tiles or {}) do
    if place_tile(ctx, t.name, world_tile(ctx, t)) then counts.add = counts.add + 1 end
  end
  return counts
end

-- World footprint of a snapshot at a copy (bounding box of all its entities).
function M.footprint(ctx, snapshot, tiles)
  local x1, y1, x2, y2 = math.huge, math.huge, -math.huge, -math.huge
  for _, t in pairs(tiles or {}) do
    local p = transform.world(ctx.t, ctx.origin, t.position)
    x1, y1 = math.min(x1, p.x - 0.5), math.min(y1, p.y - 0.5)
    x2, y2 = math.max(x2, p.x + 0.5), math.max(y2, p.y + 0.5)
  end
  for _, s in pairs(snapshot) do
    local p = transform.world(ctx.t, ctx.origin, s.position)
    local proto = prototypes.entity[s.name]
    local half = proto and math.max(proto.tile_width, proto.tile_height) / 2 or 0.5
    x1, y1 = math.min(x1, p.x - half), math.min(y1, p.y - half)
    x2, y2 = math.max(x2, p.x + half), math.max(y2, p.y + half)
  end
  if x1 == math.huge then return nil end
  return { left_top = { x = x1, y = y1 }, right_bottom = { x = x2, y = y2 } }
end

-- Make the copy exactly match `snapshot` (and `tiles`): remove everything else inside the footprint,
-- then (re)build every master entity, replacing whatever is in the way, and match the tiles.
function M.force_match(ctx, snapshot, keep, tiles)
  local counts = { add = 0, remove = 0, upgrade = 0, paste = 0 }
  local area = M.footprint(ctx, snapshot, tiles)
  if not area then return counts end

  local wanted = {}
  for _, s in pairs(snapshot) do
    local p = transform.world(ctx.t, ctx.origin, s.position)
    wanted[s.name .. "@" .. pos_key(p)] = true
  end

  for _, e in pairs(ctx.surface.find_entities_filtered({ area = area, force = ctx.force })) do
    if e.valid and not IGNORED_TYPES[e.type] and not (keep and keep[e.name]) then
      local p = e.position
      local inside = p.x >= area.left_top.x and p.x <= area.right_bottom.x
        and p.y >= area.left_top.y and p.y <= area.right_bottom.y
      local name = (e.type == "entity-ghost") and e.ghost_name or e.name
      -- Wrong direction is left for the superforced rebuild below to correct.
      if inside and not wanted[name .. "@" .. pos_key(p)] then
        remove_entity(ctx, e)
        counts.remove = counts.remove + 1
      end
    end
  end

  for _, s in pairs(snapshot) do
    build_one(ctx, s, defines.build_mode.superforced)
    counts.add = counts.add + 1
  end
  M.force_match_tiles(ctx, tiles, area, counts)
  return counts
end

return M
