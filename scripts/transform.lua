-- Placement transforms. A transform is { k = quarter-turns clockwise (0..3), f = mirrored (bool) }
-- meaning: world_offset = Rot(k) * FlipX^f * design_offset   (FlipX mirrors left/right).
-- Directions are Factorio 2.0 16-way directions (north = 0, east = 4, south = 8, west = 12).

local M = {}

M.IDENTITY = { k = 0, f = false }

-- From the on_pre_build event of a blueprint placement.
function M.from_placement(direction, flip_h, flip_v)
  local k = math.floor((direction or 0) / 4) % 4
  local f = (flip_h and true or false) ~= (flip_v and true or false)
  if flip_v then k = (k + 2) % 4 end   -- vertical flip = horizontal flip + half turn
  return { k = k, f = f }
end

-- outer applied after inner: Rot(k2)Fx^f2 Rot(k1)Fx^f1 = Rot(k2 +/- k1) Fx^(f1 xor f2)
function M.compose(outer, inner)
  local k1 = outer.f and -inner.k or inner.k
  return { k = (outer.k + k1) % 4, f = outer.f ~= inner.f }
end

function M.offset(t, p)
  local x, y = p.x, p.y
  if t.f then x = -x end
  for _ = 1, t.k do x, y = -y, x end
  return { x = x, y = y }
end

function M.direction(t, d)
  d = d or 0
  if t.f then d = (16 - d) % 16 end
  return (d + 4 * t.k) % 16
end

function M.world(t, origin, offset)
  local o = M.offset(t, offset)
  return { x = origin.x + o.x, y = origin.y + o.y }
end

return M
