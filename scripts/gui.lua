-- GUIs:
--   * Designs window (screen): designs with Edit / Get blueprint / Copies, plus New design
--   * Copies window (screen): placed copies of one design with Update / Upgrade / Force match / Show
--   * Editing bar (top): while on the designer: tier switcher, New tier, Save, Save & return

local designs = require("scripts.designs")
local editor = require("scripts.editor")
local instances = require("scripts.instances")

local M = {}

local WINDOW = "bpd_window"
local COPIES = "bpd_copies"
local BAR = "bpd_editing_bar"

local function destroy(element) if element and element.valid then element.destroy() end end

local function titled_frame(player, name, caption)
  destroy(player.gui.screen[name])
  local frame = player.gui.screen.add({ type = "frame", name = name, direction = "vertical" })
  frame.auto_center = true
  local titlebar = frame.add({ type = "flow", direction = "horizontal" })
  titlebar.drag_target = frame
  titlebar.add({ type = "label", caption = caption, style = "frame_title", ignored_by_interaction = true })
  local filler = titlebar.add({ type = "empty-widget", style = "draggable_space_header", ignored_by_interaction = true })
  filler.style.horizontally_stretchable = true
  filler.style.height = 24
  titlebar.add({ type = "sprite-button", style = "close_button", sprite = "utility/close", tags = { bpd = "close", window = name } })
  local inner = frame.add({ type = "frame", style = "inside_shallow_frame_with_padding", direction = "vertical" })
  local scroll = inner.add({ type = "scroll-pane" })
  scroll.style.maximal_height = 500
  return frame, scroll
end

function M.close_window(player)
  destroy(player.gui.screen[WINDOW])
  destroy(player.gui.screen[COPIES])
end

function M.open_window(player)
  M.close_window(player)
  local frame, scroll = titled_frame(player, WINDOW, { "bpd.window-title" })
  local tbl = scroll.add({ type = "table", column_count = 5 })
  tbl.style.horizontal_spacing = 12
  local any = false
  for id, design in pairs(storage.designs) do
    any = true
    local name = tbl.add({ type = "textfield", text = design.name, tags = { bpd = "rename", design = id } })
    name.style.width = 200
    local copies, outdated = 0, 0
    for _, inst in pairs(instances.for_design(id)) do
      copies = copies + 1
      if instances.is_outdated(inst) then outdated = outdated + 1 end
    end
    tbl.add({ type = "label", caption = { "bpd.design-summary", designs.max_tier(design), copies, outdated } })
    tbl.add({ type = "button", caption = { "bpd.edit" }, tags = { bpd = "edit", design = id } })
    tbl.add({ type = "button", caption = { "bpd.get" }, tags = { bpd = "get", design = id } })
    tbl.add({ type = "button", caption = { "bpd.copies" }, tags = { bpd = "copies", design = id } })
  end
  if not any then
    scroll.add({ type = "label", caption = { "bpd.no-designs" } })
  end
  local footer = frame.add({ type = "flow", direction = "horizontal" })
  footer.style.top_margin = 8
  footer.add({ type = "button", caption = { "bpd.new-design" }, style = "confirm_button", tags = { bpd = "new" } })
  player.opened = frame
end

function M.open_copies(player, design_id)
  local design = designs.get(design_id)
  if not design then return end
  destroy(player.gui.screen[WINDOW])
  local frame, scroll = titled_frame(player, COPIES, { "bpd.copies-title", design.name })

  local actions = frame.add({ type = "flow", direction = "horizontal" })
  actions.style.top_margin = 8
  actions.add({ type = "button", caption = { "bpd.back" }, tags = { bpd = "back" } })
  actions.add({ type = "button", caption = { "bpd.update-all" }, tags = { bpd = "update_all", design = design_id } })
  for t = 1, designs.max_tier(design) - 1 do
    local next_cell = design.tiers[t + 1]
    if next_cell and next_cell.version > 0 then
      actions.add({ type = "button", caption = { "bpd.upgrade-all", t, t + 1 }, tags = { bpd = "upgrade_all", design = design_id, tier = t } })
    end
  end

  local list = instances.for_design(design_id)
  if #list == 0 then
    scroll.add({ type = "label", caption = { "bpd.no-copies" } })
  else
    local tbl = scroll.add({ type = "table", column_count = 6 })
    tbl.style.horizontal_spacing = 8
    for _, inst in pairs(list) do
      local cell = design.tiers[inst.tier]
      local surface = game.surfaces[inst.surface_index]
      local status = instances.is_outdated(inst) and { "bpd.outdated", cell.version } or { "bpd.current" }
      tbl.add({ type = "label", caption = { "", { "bpd.instance-row", inst.tier, inst.version, surface and surface.name or "?",
        math.floor(inst.position.x), math.floor(inst.position.y) }, "  ", status } })
      tbl.add({ type = "button", caption = { "bpd.show" }, tags = { bpd = "show", inst = inst.id } })
      tbl.add({ type = "button", caption = { "bpd.update" }, tags = { bpd = "update", inst = inst.id } })
      local next_cell = design.tiers[inst.tier + 1]
      local up = tbl.add({ type = "button", caption = { "bpd.upgrade", inst.tier + 1 }, tags = { bpd = "upgrade", inst = inst.id } })
      up.enabled = next_cell ~= nil and next_cell.version > 0
      tbl.add({ type = "button", caption = { "bpd.force-match" }, style = "red_button", tooltip = { "bpd.force-match-tooltip" }, tags = { bpd = "force", inst = inst.id } })
      tbl.add({ type = "empty-widget" })
    end
  end
  player.opened = frame
end

function M.refresh_bar(player)
  destroy(player.gui.top[BAR])
  local ed = storage.editing[player.index]
  if not ed then return end
  local design = designs.get(ed.design_id)
  if not design then return end
  local frame = player.gui.top.add({ type = "frame", name = BAR, direction = "horizontal" })
  frame.add({ type = "label", caption = { "bpd.editing", design.name }, style = "heading_2_label" })
  for t = 1, designs.max_tier(design) do
    local b = frame.add({ type = "button", caption = { "bpd.tier", t }, tags = { bpd = "goto_tier", tier = t } })
    b.style.minimal_width = 40
    if t == ed.tier then b.enabled = false end
  end
  frame.add({ type = "button", caption = { "bpd.new-tier" }, tooltip = { "bpd.new-tier-tooltip" }, tags = { bpd = "new_tier" } })
  frame.add({ type = "button", caption = { "bpd.save" }, tags = { bpd = "save" } })
  frame.add({ type = "button", caption = { "bpd.save-return" }, style = "confirm_button", tags = { bpd = "save_return" } })
end

editor.on_change = function(player)
  M.refresh_bar(player)
end

local function report(player, counts, err)
  if err then
    player.print({ err })
  elseif counts then
    player.print({ "bpd.applied", counts.add, counts.remove, counts.upgrade, counts.paste })
  end
end

local function run_all(player, design_id, fn)
  local total = { add = 0, remove = 0, upgrade = 0, paste = 0 }
  local n = 0
  for _, inst in pairs(instances.for_design(design_id)) do
    local counts = fn(inst)
    if counts then
      n = n + 1
      for k, v in pairs(counts) do total[k] = total[k] + v end
    end
  end
  player.print({ "bpd.applied-many", n, total.add, total.remove, total.upgrade, total.paste })
end

function M.on_click(event)
  local tags = event.element.tags
  if not (tags and tags.bpd) then return end
  local player = game.get_player(event.player_index)
  local action = tags.bpd
  local inst = tags.inst and storage.instances[tags.inst]

  if action == "close" then
    destroy(player.gui.screen[tags.window])
  elseif action == "back" then
    M.open_window(player)
  elseif action == "new" then
    M.close_window(player)
    editor.enter(player, designs.create(nil, player.force), 1)
  elseif action == "edit" then
    local design = designs.get(tags.design)
    if design then M.close_window(player) editor.enter(player, design, 1) end
  elseif action == "get" then
    local design = designs.get(tags.design)
    if design then M.close_window(player) designs.give(player, design, 1) end
  elseif action == "copies" then
    M.open_copies(player, tags.design)
  elseif action == "save" then
    editor.save_in_place(player)
  elseif action == "save_return" then
    editor.leave(player, { save = true, deliver = true })
  elseif action == "new_tier" then
    editor.new_tier(player)
  elseif action == "goto_tier" then
    local ed = storage.editing[player.index]
    local design = ed and designs.get(ed.design_id)
    if design then editor.enter(player, design, tags.tier) end
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
  elseif action == "force" and inst then
    report(player, instances.update(inst, player, "exact"))
    M.open_copies(player, inst.design)
  elseif action == "update_all" then
    run_all(player, tags.design, function(i)
      if instances.is_outdated(i) then return instances.update(i, player, "safe") end
    end)
    M.open_copies(player, tags.design)
  elseif action == "upgrade_all" then
    run_all(player, tags.design, function(i)
      if i.tier == tags.tier then return instances.upgrade(i, player) end
    end)
    M.open_copies(player, tags.design)
  end
end

function M.on_text_changed(event)
  local tags = event.element.tags
  if not (tags and tags.bpd == "rename") then return end
  local design = designs.get(tags.design)
  if design and event.element.text ~= "" then
    design.name = event.element.text
  end
end

function M.on_closed(event)
  local el = event.element
  if el and el.valid and (el.name == WINDOW or el.name == COPIES) then
    el.destroy()
  end
end

return M
