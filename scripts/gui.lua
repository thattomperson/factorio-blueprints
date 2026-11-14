-- GUIs:
--   * Designs window (screen): searchable design list + details (tier picker, camera preview, stats, actions)
--   * Copies window (screen): placed copies of one design, tabbed by tier, with filters, selection and bulk actions
--   * Editing bar (top): while on the designer: tier switcher, New tier, Delete tier, Save, Save & return
--   * Confirmation dialogs (screen): delete tier, delete design
--
-- Per-player GUI state lives in storage.ui[player_index]:
--   { search, selected (design id), tier, list_ids, refs = { list },
--     copies = { design, tab, status, surface, selected = { [inst id] = true }, visible, surfaces, moves, refs } }

local designs = require("scripts.designs")
local editor = require("scripts.editor")
local instances = require("scripts.instances")
local surf = require("scripts.surface")

local M = {}

local WINDOW = "bpd_window"
local COPIES = "bpd_copies"
local BAR = "bpd_editing_bar"
local CONFIRM = "bpd_confirm_delete_tier"
local CONFIRM_DESIGN = "bpd_confirm_delete_design"

local STATUS_ANY, STATUS_OUTDATED, STATUS_CURRENT = 1, 2, 3

local function destroy(element) if element and element.valid then element.destroy() end end

local function ui(player)
  storage.ui = storage.ui or {}
  local u = storage.ui[player.index]
  if not u then
    u = { search = "", refs = {} }
    storage.ui[player.index] = u
  end
  return u
end

local function filler(parent, style, drag_target)
  local w = parent.add({ type = "empty-widget", style = style, ignored_by_interaction = drag_target == nil })
  w.style.horizontally_stretchable = true
  if drag_target then w.drag_target = drag_target end
  return w
end

-- Vanilla titlebar: [back] title ====drag==== [extra buttons] [close]
local function titlebar(frame, caption, opts)
  opts = opts or {}
  local bar = frame.add({ type = "flow", direction = "horizontal", style = "frame_header_flow" })
  bar.drag_target = frame
  if opts.back then
    bar.add({ type = "sprite-button", style = "frame_action_button", sprite = "utility/left_arrow",
      tooltip = { "bpd.back" }, tags = opts.back })
  end
  bar.add({ type = "label", caption = caption, style = "frame_title", ignored_by_interaction = true })
  local drag = bar.add({ type = "empty-widget", style = "draggable_space_header", ignored_by_interaction = true })
  drag.style.horizontally_stretchable = true
  drag.style.height = 24
  drag.style.right_margin = 4
  for _, b in pairs(opts.buttons or {}) do
    bar.add({ type = "sprite-button", style = "frame_action_button", sprite = b.sprite, tooltip = b.tooltip, tags = b.tags })
  end
  if opts.close then
    bar.add({ type = "sprite-button", style = "frame_action_button", sprite = "utility/close",
      tooltip = { "bpd.close" }, tags = { bpd = "close", window = opts.close } })
  end
  return bar
end

local function screen_frame(player, name)
  destroy(player.gui.screen[name])
  local frame = player.gui.screen.add({ type = "frame", name = name, direction = "vertical" })
  frame.auto_center = true
  return frame
end

---------------------------------------------------------------------------------------------------
-- Shared helpers

local function copy_counts(design_id)
  local total, outdated, per_tier = 0, 0, {}
  for _, inst in pairs(instances.for_design(design_id)) do
    total = total + 1
    per_tier[inst.tier] = (per_tier[inst.tier] or 0) + 1
    if instances.is_outdated(inst) then outdated = outdated + 1 end
  end
  return total, outdated, per_tier
end

local function saved(cell) return cell ~= nil and cell.version > 0 end

-- Camera position and zoom that fit a cell's saved contents into a w x h widget.
local function cell_view(design, tier, w, h)
  local c = surf.center(design.id, tier)
  local cell = design.tiers[tier]
  local snap = cell and cell.snapshot
  local x1, y1, x2, y2
  if snap and #snap > 0 then
    x1, y1, x2, y2 = math.huge, math.huge, -math.huge, -math.huge
    for _, e in pairs(snap) do
      local p = e.position
      if p.x < x1 then x1 = p.x end
      if p.y < y1 then y1 = p.y end
      if p.x > x2 then x2 = p.x end
      if p.y > y2 then y2 = p.y end
    end
    x1, y1, x2, y2 = x1 - 3, y1 - 3, x2 + 3, y2 + 3
  else
    x1, y1, x2, y2 = -10, -10, 10, 10
  end
  -- Snapshot positions are relative to the marker, which sits at the cell centre + 0.5.
  local position = { x = c.x + 0.5 + (x1 + x2) / 2, y = c.y + 0.5 + (y1 + y2) / 2 }
  local zoom = math.min(w / ((x2 - x1) * 32), h / ((y2 - y1) * 32))
  zoom = math.max(0.03, math.min(1, zoom))
  return position, zoom
end

local function add_camera(parent, design, tier, w, h)
  local box = parent.add({ type = "frame", style = "deep_frame_in_shallow_frame" })
  local position, zoom = cell_view(design, tier, w, h)
  local cam = box.add({ type = "camera", position = position, surface_index = surf.get().index, zoom = zoom })
  cam.style.width = w
  cam.style.height = h
  return cam
end

local function tier_tooltip(design, tier)
  local cell = design.tiers[tier]
  if not saved(cell) then return { "bpd.tier-tooltip-unsaved", tier } end
  return { "bpd.tier-tooltip", tier, cell.version, #(cell.snapshot or {}), instances.count_on_tier(design.id, tier) }
end

local function saved_ago(cell)
  if not (cell and cell.saved_tick) then return nil end
  local minutes = math.floor((game.tick - cell.saved_tick) / 3600)
  if minutes < 1 then return { "bpd.saved-just-now" } end
  if minutes < 120 then return { "bpd.saved-minutes-ago", minutes } end
  return { "bpd.saved-hours-ago", math.floor(minutes / 60) }
end

---------------------------------------------------------------------------------------------------
-- Designs window

local function sorted_designs(search)
  local list = {}
  local needle = search and search ~= "" and string.lower(search) or nil
  for _, design in pairs(storage.designs) do
    if not needle or string.find(string.lower(design.name), needle, 1, true) then
      list[#list + 1] = design
    end
  end
  table.sort(list, function(a, b) return a.id < b.id end)
  return list
end

local function list_item(design)
  local _, outdated = copy_counts(design.id)
  local warn = outdated > 0 and { "bpd.list-outdated", outdated } or ""
  return { "bpd.list-item", design.name, designs.max_tier(design), warn }
end

-- Refill the list-box in place (keeps focus in the search/rename textfields).
local function refresh_list(player)
  local u = ui(player)
  local list = u.refs.list
  if not (list and list.valid) then return end
  local items, ids, selected_index = {}, {}, 0
  for i, design in pairs(sorted_designs(u.search)) do
    items[i] = list_item(design)
    ids[i] = design.id
    if design.id == u.selected then selected_index = i end
  end
  list.items = items
  list.selected_index = selected_index
  u.list_ids = ids
end

function M.close_window(player)
  destroy(player.gui.screen[WINDOW])
  destroy(player.gui.screen[COPIES])
end

local function stat(parent, caption, value)
  local box = parent.add({ type = "frame", style = "deep_frame_in_shallow_frame", direction = "vertical" })
  box.style.padding = { 4, 10, 6, 10 }
  box.style.horizontally_stretchable = true
  box.add({ type = "label", caption = caption })
  box.add({ type = "label", caption = value, style = "bold_label" })
end

local function design_details(parent, player, design, u)
  local max = designs.max_tier(design)
  if not (u.tier and design.tiers[u.tier]) then u.tier = max end
  local tier = u.tier
  local cell = design.tiers[tier]
  local total, outdated = copy_counts(design.id)

  local pane = parent.add({ type = "frame", style = "inside_shallow_frame", direction = "vertical" })
  pane.style.width = 540
  pane.style.vertically_stretchable = true

  local sub = pane.add({ type = "frame", style = "subheader_frame", direction = "horizontal" })
  sub.style.horizontally_stretchable = true
  local name = sub.add({ type = "textfield", text = design.name, tooltip = { "bpd.rename-tooltip" },
    tags = { bpd = "rename", design = design.id } })
  name.style.width = 280
  filler(sub)
  sub.add({ type = "sprite-button", style = "tool_button_red", sprite = "utility/trash",
    tooltip = { "bpd.delete-design-tooltip" }, tags = { bpd = "delete_design", design = design.id } })

  local body = pane.add({ type = "flow", direction = "vertical" })
  body.style.padding = 12
  body.style.vertical_spacing = 8

  local tiers = body.add({ type = "flow", direction = "horizontal" })
  tiers.style.vertical_align = "center"
  tiers.style.horizontal_spacing = 4
  local tl = tiers.add({ type = "label", caption = { "bpd.tier-heading" }, style = "caption_label" })
  tl.style.right_margin = 6
  for t = 1, max do
    local b = tiers.add({ type = "button", caption = { "bpd.tier", t }, toggled = t == tier,
      tooltip = tier_tooltip(design, t), tags = { bpd = "select_tier", tier = t } })
    b.style.minimal_width = 44
  end
  filler(tiers)
  local ago = saved_ago(cell)
  tiers.add({ type = "label", caption = saved(cell)
    and (ago and { "", { "bpd.version", cell.version }, " · ", ago } or { "bpd.version", cell.version })
    or { "bpd.not-saved" } })

  add_camera(body, design, tier, 512, 256)

  local stats = body.add({ type = "table", column_count = 4 })
  stats.style.horizontal_spacing = 8
  stats.style.horizontally_stretchable = true
  stat(stats, { "bpd.stat-entities" }, tostring(#((cell and cell.snapshot) or {})))
  stat(stats, { "bpd.stat-on-tier" }, tostring(instances.count_on_tier(design.id, tier)))
  stat(stats, { "bpd.stat-placed" }, tostring(total))
  stat(stats, { "bpd.stat-outdated" }, outdated > 0 and { "", "[img=utility/status_yellow] ", tostring(outdated) } or "0")

  local spacer = pane.add({ type = "empty-widget" })
  spacer.style.vertically_stretchable = true

  local actions = pane.add({ type = "flow", direction = "horizontal" })
  actions.style.padding = { 0, 12, 12, 12 }
  actions.style.horizontal_spacing = 8
  actions.add({ type = "button", caption = { "bpd.edit" }, tooltip = { "bpd.edit-tooltip", tier },
    tags = { bpd = "edit", design = design.id, tier = tier } })
  local get = actions.add({ type = "button", caption = { "", "[img=item/blueprint] ", { "bpd.get" } },
    tooltip = { "bpd.get-tooltip", tier }, tags = { bpd = "get", design = design.id, tier = tier } })
  if not saved(cell) then
    get.enabled = false
    get.tooltip = { "bpd.err-tier-unsaved" }
  end
  filler(actions)
  actions.add({ type = "button", caption = { "bpd.copies-count", total }, tags = { bpd = "copies", design = design.id } })
end

function M.open_window(player)
  M.close_window(player)
  local u = ui(player)
  if u.selected and not designs.get(u.selected) then u.selected = nil end
  local all = sorted_designs(nil)
  if not u.selected and all[1] then u.selected = all[1].id end

  local frame = screen_frame(player, WINDOW)
  titlebar(frame, { "bpd.window-title" }, {
    buttons = { { sprite = "utility/import", tooltip = { "bpd.import-tooltip" }, tags = { bpd = "import" } } },
    close = WINDOW,
  })

  local body = frame.add({ type = "flow", direction = "horizontal" })
  body.style.horizontal_spacing = 12
  body.style.height = 520

  local left = body.add({ type = "frame", style = "inside_deep_frame", direction = "vertical" })
  local sub = left.add({ type = "frame", style = "subheader_frame", direction = "horizontal" })
  sub.style.horizontally_stretchable = true
  local search = sub.add({ type = "textfield", text = u.search or "", tooltip = { "bpd.search-tooltip" },
    tags = { bpd = "search" } })
  search.style.horizontally_stretchable = true
  search.style.width = 280
  local list = left.add({ type = "list-box", tags = { bpd = "design_list" } })
  list.style.width = 300
  list.style.vertically_stretchable = true
  u.refs = { list = list }
  refresh_list(player)

  local design = u.selected and designs.get(u.selected)
  if design then
    design_details(body, player, design, u)
  else
    local empty = body.add({ type = "frame", style = "inside_shallow_frame_with_padding", direction = "vertical" })
    empty.style.width = 540
    empty.style.vertically_stretchable = true
    local l = empty.add({ type = "label", caption = { "bpd.no-designs" } })
    l.style.single_line = false
    l.style.maximal_width = 500
  end

  local footer = frame.add({ type = "flow", direction = "horizontal", style = "dialog_buttons_horizontal_flow" })
  footer.style.vertical_align = "center"
  footer.add({ type = "label", caption = { "bpd.design-count", #all } })
  filler(footer, "draggable_space", frame).style.height = 32
  footer.add({ type = "button", caption = { "bpd.new-design" }, style = "confirm_button", tags = { bpd = "new" } })
  player.opened = frame
end

---------------------------------------------------------------------------------------------------
-- Copies window

local function copy_filter(inst, c, surfaces)
  if c.tab > 1 and inst.tier ~= c.tab - 1 then return false end
  local outdated = instances.is_outdated(inst)
  if c.status == STATUS_OUTDATED and not outdated then return false end
  if c.status == STATUS_CURRENT and outdated then return false end
  if c.surface > 1 and inst.surface_index ~= surfaces[c.surface] then return false end
  return true
end

local function selected_visible(c)
  local n = 0
  for _, id in pairs(c.visible or {}) do
    if c.selected[id] and storage.instances[id] then n = n + 1 end
  end
  return n
end

-- Update the selection counter, select-all box and bulk buttons without rebuilding the window.
local function refresh_selection(c)
  local refs = c.refs or {}
  local n = selected_visible(c)
  if refs.count and refs.count.valid then refs.count.caption = { "bpd.selected", n } end
  if refs.all and refs.all.valid then refs.all.state = n > 0 and n == #c.visible end
  for _, b in pairs(refs.bulk or {}) do
    if b.valid then b.enabled = n > 0 end
  end
end

local function tier_moves(design, per_tier)
  local moves = {}
  local max = designs.max_tier(design)
  for t = 1, max - 1 do
    if (per_tier[t] or 0) > 0 and saved(design.tiers[t + 1]) then
      moves[#moves + 1] = { action = "upgrade_all", tier = t, caption = { "bpd.upgrade-all", t, t + 1 } }
    end
  end
  for t = 2, max do
    if (per_tier[t] or 0) > 0 and saved(design.tiers[t - 1]) then
      moves[#moves + 1] = { action = "downgrade_all", tier = t, caption = { "bpd.downgrade-all", t, t - 1 } }
    end
  end
  return moves
end

local function action_button(parent, sprite, tooltip, tags, enabled, style)
  local b = parent.add({ type = "sprite-button", style = style or "tool_button", sprite = sprite, tooltip = tooltip, tags = tags })
  b.enabled = enabled
  return b
end

local function copy_row(tbl, player, design, inst, c)
  local id = inst.id
  local outdated = instances.is_outdated(inst)
  local surface = game.surfaces[inst.surface_index]
  local refs = c.refs

  refs.rows[id] = tbl.add({ type = "checkbox", state = c.selected[id] == true, tags = { bpd = "select_copy", inst = id } })

  if surface then
    local mm = tbl.add({ type = "minimap", position = inst.position, surface_index = inst.surface_index, zoom = 1.5 })
    mm.style.width = 64
    mm.style.height = 48
  else
    tbl.add({ type = "empty-widget" })
  end

  tbl.add({ type = "label", caption = { "bpd.tier", inst.tier }, style = "bold_label" })
  tbl.add({ type = "label", caption = { "bpd.version", inst.version } })

  local loc = tbl.add({ type = "flow", direction = "vertical" })
  loc.style.vertical_spacing = 0
  loc.add({ type = "label", caption = surface and surface.name or "?", style = "bold_label" })
  loc.add({ type = "label", caption = { "bpd.position", math.floor(inst.position.x), math.floor(inst.position.y) } })

  local status = tbl.add({ type = "flow", direction = "horizontal" })
  status.style.vertical_align = "center"
  local cell = design.tiers[inst.tier]
  status.add({ type = "sprite", style = "status_image", sprite = outdated and "utility/status_yellow" or "utility/status_working" })
  status.add({ type = "label", caption = outdated and { "bpd.outdated", cell.version } or { "bpd.current" } })

  local acts = tbl.add({ type = "flow", direction = "horizontal" })
  acts.style.horizontal_spacing = 4
  local prev_ok = saved(design.tiers[inst.tier - 1])
  local next_ok = saved(design.tiers[inst.tier + 1])
  action_button(acts, "utility/gps_map_icon", { "bpd.show-tooltip" }, { bpd = "show", inst = id }, not editor.is_editing(player))
  action_button(acts, "utility/refresh", outdated and { "bpd.update-tooltip", cell.version } or { "bpd.update-current" },
    { bpd = "update", inst = id }, outdated)
  action_button(acts, "bpd-arrow-down", prev_ok and { "bpd.downgrade", inst.tier - 1 } or { "bpd.err-lowest-tier" },
    { bpd = "downgrade", inst = id }, prev_ok)
  action_button(acts, "bpd-arrow-up", next_ok and { "bpd.upgrade", inst.tier + 1 } or { "bpd.upgrade-none" },
    { bpd = "upgrade", inst = id }, next_ok)
  action_button(acts, "utility/check_mark", { "bpd.force-match-tooltip" }, { bpd = "force", inst = id }, true, "tool_button_red")
end

function M.open_copies(player, design_id)
  local design = designs.get(design_id)
  if not design then return end
  local u = ui(player)
  local c = u.copies
  if not c or c.design ~= design_id then
    c = { design = design_id, tab = 1, status = STATUS_ANY, surface = 1, selected = {} }
    u.copies = c
  end
  destroy(player.gui.screen[WINDOW])
  local frame = screen_frame(player, COPIES)
  titlebar(frame, { "bpd.copies-title", design.name }, { back = { bpd = "back", design = design_id }, close = COPIES })

  local max = designs.max_tier(design)
  local all = instances.for_design(design_id)
  local _, _, per_tier = copy_counts(design_id)
  if c.tab > max + 1 then c.tab = 1 end

  -- Surfaces that hold copies, for the filter.
  local surfaces, surface_items, seen = { false }, { { "bpd.all-surfaces" } }, {}
  for _, inst in pairs(all) do
    local s = game.surfaces[inst.surface_index]
    if s and not seen[s.index] then
      seen[s.index] = true
      surfaces[#surfaces + 1] = s.index
      surface_items[#surface_items + 1] = s.name
    end
  end
  if c.surface > #surfaces then c.surface = 1 end
  c.surfaces = surfaces

  local tabs = frame.add({ type = "tabbed-pane", style = "tabbed_pane_with_no_side_padding", tags = { bpd = "copies_tab" } })
  local contents = {}
  for i = 1, max + 1 do
    local count = i == 1 and #all or (per_tier[i - 1] or 0)
    local tab = tabs.add({ type = "tab", caption = i == 1 and { "bpd.tab-all" } or { "bpd.tier", i - 1 },
      badge_text = tostring(count) })
    contents[i] = tabs.add({ type = "flow", direction = "vertical" })
    tabs.add_tab(tab, contents[i])
  end
  tabs.selected_tab_index = c.tab
  local panel = contents[c.tab]
  panel.style.width = 900

  local visible = {}
  for _, inst in pairs(all) do
    if copy_filter(inst, c, surfaces) then visible[#visible + 1] = inst end
  end
  c.visible = {}
  for i, inst in pairs(visible) do c.visible[i] = inst.id end
  c.refs = { rows = {}, bulk = {} }

  local sub = panel.add({ type = "frame", style = "subheader_frame", direction = "horizontal" })
  sub.style.horizontally_stretchable = true
  c.refs.all = sub.add({ type = "checkbox", state = false, tooltip = { "bpd.select-all" }, tags = { bpd = "select_all" } })
  c.refs.count = sub.add({ type = "label", style = "subheader_caption_label", caption = "" })
  c.refs.count.style.right_margin = 8
  c.refs.bulk[1] = sub.add({ type = "button", caption = { "bpd.update" }, tooltip = { "bpd.bulk-update-tooltip" }, tags = { bpd = "bulk_update" } })
  c.refs.bulk[2] = sub.add({ type = "button", caption = { "bpd.downgrade-short" }, tooltip = { "bpd.bulk-downgrade-tooltip" }, tags = { bpd = "bulk_downgrade" } })
  c.refs.bulk[3] = sub.add({ type = "button", caption = { "bpd.upgrade-short" }, tooltip = { "bpd.bulk-upgrade-tooltip" }, tags = { bpd = "bulk_upgrade" } })
  filler(sub)
  sub.add({ type = "drop-down", items = { { "bpd.status-any" }, { "bpd.status-outdated" }, { "bpd.status-current" } },
    selected_index = c.status, tags = { bpd = "filter_status" } })
  sub.add({ type = "drop-down", items = surface_items, selected_index = c.surface, tags = { bpd = "filter_surface" } })

  local box = panel.add({ type = "frame", style = "deep_frame_in_shallow_frame", direction = "vertical" })
  box.style.margin = 12
  box.style.horizontally_stretchable = true
  local scroll = box.add({ type = "scroll-pane", style = "naked_scroll_pane", horizontal_scroll_policy = "never" })
  scroll.style.maximal_height = 440
  scroll.style.horizontally_stretchable = true

  if #all == 0 then
    local l = scroll.add({ type = "label", caption = { "bpd.no-copies" } })
    l.style.single_line = false
    l.style.margin = 12
    l.style.maximal_width = 860
  elseif #visible == 0 then
    local l = scroll.add({ type = "label", caption = { "bpd.no-matching-copies" } })
    l.style.margin = 12
  else
    local tbl = scroll.add({ type = "table", column_count = 7, draw_horizontal_line_after_headers = true })
    tbl.style.horizontal_spacing = 12
    tbl.style.vertical_spacing = 6
    tbl.style.padding = { 6, 10, 6, 10 }
    for _, h in pairs({ "", { "bpd.col-preview" }, { "bpd.col-tier" }, { "bpd.col-version" }, { "bpd.col-location" },
      { "bpd.col-status" }, { "bpd.col-actions" } }) do
      tbl.add({ type = "label", caption = h, style = "caption_label" })
    end
    for _, inst in pairs(visible) do copy_row(tbl, player, design, inst, c) end
  end
  refresh_selection(c)

  local footer = frame.add({ type = "flow", direction = "horizontal", style = "dialog_buttons_horizontal_flow" })
  footer.style.vertical_align = "center"
  c.moves = tier_moves(design, per_tier)
  local move_items = {}
  for i, m in pairs(c.moves) do move_items[i] = m.caption end
  if #move_items == 0 then move_items[1] = { "bpd.no-tier-moves" } end
  local dd = footer.add({ type = "drop-down", items = move_items, selected_index = 1, tags = { bpd = "tier_move" } })
  dd.enabled = #c.moves > 0
  local apply = footer.add({ type = "button", caption = { "bpd.apply" }, tags = { bpd = "tier_move_apply" } })
  apply.enabled = #c.moves > 0
  c.refs.move = dd
  filler(footer, "draggable_space", frame).style.height = 32
  local n_outdated = 0
  for _, inst in pairs(all) do if instances.is_outdated(inst) then n_outdated = n_outdated + 1 end end
  local upd = footer.add({ type = "button", caption = { "bpd.update-all", n_outdated }, style = "confirm_button",
    tags = { bpd = "update_all", design = design_id } })
  upd.enabled = n_outdated > 0
  player.opened = frame
end

---------------------------------------------------------------------------------------------------
-- Editing bar

function M.refresh_bar(player)
  destroy(player.gui.top[BAR])
  local ed = storage.editing[player.index]
  if not ed then return end
  local design = designs.get(ed.design_id)
  if not design then return end
  local max = designs.max_tier(design)
  local cell = design.tiers[ed.tier]

  local frame = player.gui.top.add({ type = "frame", name = BAR, direction = "horizontal" })
  local row = frame.add({ type = "flow", direction = "horizontal" })
  row.style.vertical_align = "center"
  row.style.horizontal_spacing = 6

  local icon = row.add({ type = "sprite", sprite = "item/blueprint", resize_to_sprite = false })
  icon.style.width = 28
  icon.style.height = 28
  icon.style.stretch_image_to_widget_size = true
  row.add({ type = "label", caption = design.name, style = "frame_title" })
  row.add({ type = "line", direction = "vertical" })

  for t = 1, max do
    local b = row.add({ type = "button", caption = { "bpd.tier", t }, toggled = t == ed.tier,
      tooltip = tier_tooltip(design, t), tags = { bpd = "goto_tier", tier = t } })
    b.style.minimal_width = 40
  end
  row.add({ type = "sprite-button", style = "tool_button", sprite = "utility/add", tooltip = { "bpd.new-tier-tooltip" },
    tags = { bpd = "new_tier" } })
  row.add({ type = "line", direction = "vertical" })

  row.add({ type = "label", caption = saved(cell) and { "bpd.version", cell.version } or { "bpd.not-saved" } })
  row.add({ type = "line", direction = "vertical" })

  local del = row.add({ type = "sprite-button", style = "tool_button_red", sprite = "utility/trash",
    tooltip = { "bpd.delete-tier-tooltip" }, tags = { bpd = "delete_tier" } })
  if max <= 1 then
    del.enabled = false
    del.tooltip = { "bpd.tier-delete-last" }
  end
  row.add({ type = "button", caption = { "bpd.save" }, tooltip = { "bpd.save-tooltip" }, tags = { bpd = "save" } })
  row.add({ type = "button", caption = { "bpd.save-return" }, style = "confirm_button", tags = { bpd = "save_return" } })
end

---------------------------------------------------------------------------------------------------
-- Confirmation dialogs

local function confirm_dialog(player, name, title, preview, lines, cancel_tags, confirm_caption, confirm_tags)
  local frame = screen_frame(player, name)
  titlebar(frame, title)
  local body = frame.add({ type = "frame", style = "inside_shallow_frame_with_padding", direction = "horizontal" })
  body.style.horizontal_spacing = 12
  if preview then add_camera(body, preview.design, preview.tier, 128, 128) end
  local text = body.add({ type = "flow", direction = "vertical" })
  text.style.vertical_spacing = 6
  for i, line in pairs(lines) do
    local caption = i == 1 and { "", "[img=utility/warning_icon] ", line } or line
    local l = text.add({ type = "label", caption = caption })
    l.style.single_line = false
    l.style.maximal_width = 380
  end
  local buttons = frame.add({ type = "flow", direction = "horizontal", style = "dialog_buttons_horizontal_flow" })
  buttons.add({ type = "button", caption = { "bpd.cancel" }, style = "back_button", tags = cancel_tags })
  filler(buttons, "draggable_space", frame).style.height = 32
  buttons.add({ type = "button", caption = confirm_caption, style = "red_confirm_button", tags = confirm_tags })
  player.opened = frame
end

function M.confirm_delete_tier(player)
  local ed = storage.editing[player.index]
  local design = ed and designs.get(ed.design_id)
  if not design or designs.max_tier(design) <= 1 then return end
  local lines = { { "bpd.delete-tier-body" } }
  if ed.tier < designs.max_tier(design) then
    lines[#lines + 1] = { "bpd.delete-tier-shift", ed.tier + 1, ed.tier }
  end
  local copies = instances.count_on_tier(design.id, ed.tier)
  if copies > 0 then
    lines[#lines + 1] = { "bpd.delete-tier-copies", copies }
  end
  confirm_dialog(player, CONFIRM, { "bpd.delete-tier-title", design.name, ed.tier }, { design = design, tier = ed.tier },
    lines, { bpd = "close", window = CONFIRM }, { "bpd.delete-tier" },
    { bpd = "delete_tier_confirm", design = design.id, tier = ed.tier })
end

function M.confirm_delete_design(player, design)
  M.close_window(player)
  local lines = { { "bpd.delete-design-body", designs.max_tier(design) } }
  local copies = #instances.for_design(design.id)
  if copies > 0 then lines[#lines + 1] = { "bpd.delete-design-copies", copies } end
  confirm_dialog(player, CONFIRM_DESIGN, { "bpd.delete-design-title", design.name }, { design = design, tier = 1 },
    lines, { bpd = "cancel_delete_design" }, { "bpd.delete-design" }, { bpd = "delete_design_confirm", design = design.id })
end

editor.on_change = function(player)
  destroy(player.gui.screen[CONFIRM])
  M.refresh_bar(player)
end

---------------------------------------------------------------------------------------------------
-- Actions

local function report(player, counts, err)
  if err then
    player.print({ err })
  elseif counts then
    player.print({ "bpd.applied", counts.add, counts.remove, counts.upgrade, counts.paste })
  end
end

local function run_all(player, list, fn)
  local total = { add = 0, remove = 0, upgrade = 0, paste = 0 }
  local n = 0
  for _, inst in pairs(list) do
    local counts = fn(inst)
    if counts then
      n = n + 1
      for k, v in pairs(counts) do total[k] = total[k] + v end
    end
  end
  player.print({ "bpd.applied-many", n, total.add, total.remove, total.upgrade, total.paste })
end

local function selected_copies(player)
  local c = ui(player).copies
  local list = {}
  if not c then return list end
  for _, id in pairs(c.visible or {}) do
    local inst = storage.instances[id]
    if c.selected[id] and inst then list[#list + 1] = inst end
  end
  return list
end

local function tier_move(player, design_id, action, tier)
  run_all(player, instances.for_design(design_id), function(i)
    if i.tier ~= tier then return nil end
    if action == "upgrade_all" then return instances.upgrade(i, player) end
    return instances.downgrade(i, player)
  end)
end

local function delete_design(player, design)
  for index, ed in pairs(storage.editing) do
    if ed.design_id == design.id then
      local p = game.get_player(index)
      if p and p.valid then editor.leave(p, { save = false }) else storage.editing[index] = nil end
    end
  end
  local copies = instances.for_design(design.id)
  for _, inst in pairs(copies) do instances.unlink(inst) end
  local name = design.name
  designs.delete(design)
  player.print({ "bpd.design-deleted", name, #copies })
end

local function import_held(player)
  local u = ui(player)
  local blueprint = designs.readable_blueprint(player)
  if not blueprint then
    player.print({ "bpd.import-hold" })
    return
  end
  local id, tier = designs.identify(blueprint)
  if id and designs.get(id) then
    u.selected, u.tier = id, tier
    player.print({ "bpd.import-known", designs.get(id).name })
  else
    local design = designs.import(player, blueprint)
    designs.save(design, 1, player.force)
    u.selected, u.tier = design.id, 1
    player.print({ "bpd.imported", design.name })
  end
  M.open_window(player)
end

function M.on_click(event)
  local tags = event.element.tags
  if not (tags and tags.bpd) then return end
  local player = game.get_player(event.player_index)
  local u = ui(player)
  local action = tags.bpd
  local inst = tags.inst and storage.instances[tags.inst]

  if action == "close" then
    destroy(player.gui.screen[tags.window])
  elseif action == "back" then
    if tags.design then u.selected = tags.design end
    M.open_window(player)
  elseif action == "new" then
    M.close_window(player)
    local design = designs.create(nil, player.force)
    u.selected, u.tier = design.id, 1
    editor.enter(player, design, 1)
  elseif action == "import" then
    import_held(player)
  elseif action == "select_tier" then
    u.tier = tags.tier
    M.open_window(player)
  elseif action == "edit" then
    local design = designs.get(tags.design)
    if design then M.close_window(player) editor.enter(player, design, tags.tier or 1) end
  elseif action == "get" then
    local design = designs.get(tags.design)
    if design then M.close_window(player) designs.give(player, design, tags.tier or 1) end
  elseif action == "copies" then
    M.open_copies(player, tags.design)
  elseif action == "delete_design" then
    local design = designs.get(tags.design)
    if design then M.confirm_delete_design(player, design) end
  elseif action == "cancel_delete_design" then
    destroy(player.gui.screen[CONFIRM_DESIGN])
    M.open_window(player)
  elseif action == "delete_design_confirm" then
    destroy(player.gui.screen[CONFIRM_DESIGN])
    local design = designs.get(tags.design)
    if design then delete_design(player, design) end
    M.open_window(player)
  elseif action == "save" then
    editor.save_in_place(player)
    M.refresh_bar(player)
  elseif action == "save_return" then
    editor.leave(player, { save = true, deliver = true })
  elseif action == "new_tier" then
    editor.new_tier(player)
  elseif action == "delete_tier" then
    M.confirm_delete_tier(player)
  elseif action == "delete_tier_confirm" then
    destroy(player.gui.screen[CONFIRM])
    local ed = storage.editing[player.index]
    -- Only act if the player is still on the tier they confirmed for.
    if ed and ed.design_id == tags.design and ed.tier == tags.tier then
      editor.delete_tier(player)
    end
  elseif action == "goto_tier" then
    local ed = storage.editing[player.index]
    local design = ed and designs.get(ed.design_id)
    if design and ed.tier ~= tags.tier then
      editor.enter(player, design, tags.tier)
    elseif design then
      M.refresh_bar(player)   -- keep the toggled state on the current tier
    end
  elseif action == "show" and inst then
    local surface = game.surfaces[inst.surface_index]
    if surface and not editor.is_editing(player) then
      M.close_window(player)
      player.set_controller({ type = defines.controllers.remote, surface = surface, position = inst.position })
    end
  elseif action == "update" and inst then
    report(player, instances.update(inst, player, "safe"))
    M.open_copies(player, inst.design)
  elseif action == "upgrade" and inst then
    report(player, instances.upgrade(inst, player))
    M.open_copies(player, inst.design)
  elseif action == "downgrade" and inst then
    report(player, instances.downgrade(inst, player))
    M.open_copies(player, inst.design)
  elseif action == "force" and inst then
    report(player, instances.update(inst, player, "exact"))
    M.open_copies(player, inst.design)
  elseif action == "update_all" then
    run_all(player, instances.for_design(tags.design), function(i)
      if instances.is_outdated(i) then return instances.update(i, player, "safe") end
    end)
    M.open_copies(player, tags.design)
  elseif action == "upgrade_all" or action == "downgrade_all" then
    tier_move(player, tags.design, action, tags.tier)
    M.open_copies(player, tags.design)
  elseif action == "tier_move_apply" then
    local c = u.copies
    local dd = c and c.refs and c.refs.move
    local move = dd and dd.valid and c.moves[dd.selected_index]
    if move then
      tier_move(player, c.design, move.action, move.tier)
      M.open_copies(player, c.design)
    end
  elseif action == "bulk_update" or action == "bulk_downgrade" or action == "bulk_upgrade" then
    local c = u.copies
    if not c then return end
    run_all(player, selected_copies(player), function(i)
      if action == "bulk_update" then
        if instances.is_outdated(i) then return instances.update(i, player, "safe") end
      elseif action == "bulk_downgrade" then
        return instances.downgrade(i, player)
      else
        local design = designs.get(i.design)
        if design and saved(design.tiers[i.tier + 1]) then return instances.upgrade(i, player) end
      end
    end)
    M.open_copies(player, c.design)
  end
end

function M.on_checked_state_changed(event)
  local el = event.element
  local tags = el.tags
  if not (tags and tags.bpd) then return end
  local c = ui(game.get_player(event.player_index)).copies
  if not c then return end
  if tags.bpd == "select_copy" then
    c.selected[tags.inst] = el.state or nil
  elseif tags.bpd == "select_all" then
    for _, id in pairs(c.visible or {}) do
      c.selected[id] = el.state or nil
      local box = c.refs.rows[id]
      if box and box.valid then box.state = el.state end
    end
  else
    return
  end
  refresh_selection(c)
end

function M.on_selection_state_changed(event)
  local el = event.element
  local tags = el.tags
  if not (tags and tags.bpd) then return end
  local player = game.get_player(event.player_index)
  local u = ui(player)
  if tags.bpd == "design_list" then
    local id = u.list_ids and u.list_ids[el.selected_index]
    if id and id ~= u.selected then
      u.selected, u.tier = id, nil
      M.open_window(player)
    end
  elseif tags.bpd == "filter_status" and u.copies then
    u.copies.status = el.selected_index
    M.open_copies(player, u.copies.design)
  elseif tags.bpd == "filter_surface" and u.copies then
    u.copies.surface = el.selected_index
    M.open_copies(player, u.copies.design)
  end
end

function M.on_selected_tab_changed(event)
  local el = event.element
  if not (el.tags and el.tags.bpd == "copies_tab") then return end
  local player = game.get_player(event.player_index)
  local c = ui(player).copies
  if not c then return end
  c.tab = el.selected_tab_index or 1
  M.open_copies(player, c.design)
end

function M.on_text_changed(event)
  local tags = event.element.tags
  if not (tags and tags.bpd) then return end
  local player = game.get_player(event.player_index)
  if tags.bpd == "rename" then
    local design = designs.get(tags.design)
    if design and event.element.text ~= "" then
      design.name = event.element.text
      refresh_list(player)
    end
  elseif tags.bpd == "search" then
    ui(player).search = event.element.text
    refresh_list(player)
  end
end

function M.on_closed(event)
  local el = event.element
  if el and el.valid and (el.name == WINDOW or el.name == COPIES or el.name == CONFIRM or el.name == CONFIRM_DESIGN) then
    el.destroy()
  end
end

return M
