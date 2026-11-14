-- Diff engine shared by tier upgrades and instance updates.
--
-- A snapshot is a list of blueprint entities with positions relative to the design marker
-- (see designs.save). Plans are computed in design space and applied at a placed copy through
-- its transform (scripts/transform.lua).

local transform = require("scripts.transform")

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
  local e = table.deepcopy(snap)
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

-- World footprint of a snapshot at a copy (bounding box of all its entities).
function M.footprint(ctx, snapshot)
  local x1, y1, x2, y2 = math.huge, math.huge, -math.huge, -math.huge
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

-- Make the copy exactly match `snapshot`: remove everything else inside the footprint,
-- then (re)build every master entity, replacing whatever is in the way.
function M.force_match(ctx, snapshot, keep)
  local counts = { add = 0, remove = 0, upgrade = 0, paste = 0 }
  local area = M.footprint(ctx, snapshot)
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
  return counts
end

return M
