-- The designer surface and its grid of design cells.
--
-- Layout: one row per design, one column per tier.
--   cell centre = { x = (tier - 1) * CELL, y = (design_id - 1) * CELL }
-- Only the inner HALF-radius square of a cell is the buildable design area;
-- the rest is a gap so neighbouring designs never touch.

local M = {}

M.NAME = "bpd-designer"
M.CELL = 256          -- distance between cell centres (tiles); multiple of 32 keeps cells chunk-aligned
M.HALF = 112          -- design area is centre +/- HALF on both axes (224 x 224 tiles)

local LAB_A, LAB_B = "lab-dark-1", "lab-dark-2"

function M.get()
  local surface = game.surfaces[M.NAME]
  if surface then return surface end

  surface = game.create_surface(M.NAME, {
    default_enable_all_autoplace_controls = false,
    autoplace_controls = {},
    autoplace_settings = {
      entity = { treat_missing_as_default = false, settings = {} },
      tile = { treat_missing_as_default = false, settings = {} },
      decorative = { treat_missing_as_default = false, settings = {} },
    },
    cliff_settings = { richness = 0 },
    no_enemies_mode = true,
    peaceful_mode = true,
  })
  surface.generate_with_lab_tiles = true
  surface.always_day = true
  surface.show_clouds = false
  return surface
end

function M.center(design_id, tier)
  return { x = (tier - 1) * M.CELL, y = (design_id - 1) * M.CELL }
end

function M.area(design_id, tier)
  local c = M.center(design_id, tier)
  return {
    left_top = { x = c.x - M.HALF, y = c.y - M.HALF },
    right_bottom = { x = c.x + M.HALF, y = c.y + M.HALF },
  }
end

-- Which design cell (if any) contains this position? Returns design_id, tier.
function M.cell_at(position)
  local col = math.floor((position.x + M.CELL / 2) / M.CELL)
  local row = math.floor((position.y + M.CELL / 2) / M.CELL)
  if col < 0 or row < 0 then return nil end
  local c = { x = col * M.CELL, y = row * M.CELL }
  if math.abs(position.x - c.x) > M.HALF or math.abs(position.y - c.y) > M.HALF then return nil end
  return row + 1, col + 1
end

function M.lab_tile_at(position)
  local x, y = math.floor(position.x), math.floor(position.y)
  return ((x + y) % 2 == 0) and LAB_A or LAB_B
end

-- Make sure the cell exists: chunks generated, charted, radar, marker, outline.
-- `cell` is the storage record for (design, tier); fields are filled in here.
function M.prepare_cell(cell, design, force)
  local surface = M.get()
  local center = M.center(design.id, cell.tier)
  local area = M.area(design.id, cell.tier)

  local radius = math.ceil(M.HALF / 32) + 1
  surface.request_to_generate_chunks(center, radius)
  surface.force_generate_chunk_requests()
  force.chart(surface, area)

  if not (cell.radar and cell.radar.valid) then
    cell.radar = surface.find_entity("bpd-editor-radar", center)
      or surface.create_entity({ name = "bpd-editor-radar", position = center, force = force })
    if cell.radar then
      cell.radar.destructible = false
      cell.radar.minable = false
    end
  end

  if not (cell.marker and cell.marker.valid) then
    -- 1x1 entities sit on tile centres, so the marker lives at centre + 0.5.
    local marker_pos = { x = center.x + 0.5, y = center.y + 0.5 }
    cell.marker = surface.find_entity("bpd-marker", marker_pos)
      or surface.create_entity({ name = "bpd-marker", position = marker_pos, force = force })
  end
  cell.marker.destructible = false
  cell.marker.minable = false

  if not (cell.outline and cell.outline.valid) then
    cell.outline = rendering.draw_rectangle({
      color = { 0.3, 0.6, 1, 0.8 },
      width = 4,
      filled = false,
      left_top = area.left_top,
      right_bottom = area.right_bottom,
      surface = surface,
    })
  end
  if cell.label and cell.label.valid then cell.label.destroy() end
  cell.label = rendering.draw_text({
    text = { "", design.name, "  ", { "bpd.tier", cell.tier } },
    surface = surface,
    target = { x = area.left_top.x, y = area.left_top.y - 4 },
    color = { 0.6, 0.8, 1 },
    scale = 4,
  })
end

return M
