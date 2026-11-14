-- Two small GUIs:
--   * the Designs window (screen): list of designs with Edit / Get blueprint, plus New design
--   * the Editing bar (top): shown while on the designer surface, with Save and Save & return

local designs = require("scripts.designs")
local editor = require("scripts.editor")

local M = {}

local WINDOW = "bpd_window"
local BAR = "bpd_editing_bar"

local function destroy(element) if element and element.valid then element.destroy() end end

function M.close_window(player) destroy(player.gui.screen[WINDOW]) end

function M.open_window(player)
  M.close_window(player)
  local frame = player.gui.screen.add({ type = "frame", name = WINDOW, direction = "vertical" })
  frame.auto_center = true

  local titlebar = frame.add({ type = "flow", direction = "horizontal" })
  titlebar.drag_target = frame
  titlebar.add({ type = "label", caption = { "bpd.window-title" }, style = "frame_title", ignored_by_interaction = true })
  local filler = titlebar.add({ type = "empty-widget", style = "draggable_space_header", ignored_by_interaction = true })
  filler.style.horizontally_stretchable = true
  filler.style.height = 24
  titlebar.add({ type = "sprite-button", style = "close_button", sprite = "utility/close", tags = { bpd = "close" } })

  local inner = frame.add({ type = "frame", style = "inside_shallow_frame_with_padding", direction = "vertical" })
  local scroll = inner.add({ type = "scroll-pane" })
  scroll.style.maximal_height = 500

  local table_el = scroll.add({ type = "table", column_count = 4 })
  table_el.style.horizontal_spacing = 12
  local any = false
  for id, design in pairs(storage.designs) do
    any = true
    local name = table_el.add({ type = "textfield", text = design.name, tags = { bpd = "rename", design = id } })
    name.style.width = 200
    local tiers = 0
    for _ in pairs(design.tiers) do tiers = tiers + 1 end
    local version = design.tiers[1] and design.tiers[1].version or 0
    table_el.add({ type = "label", caption = { "bpd.design-summary", tiers, version } })
    table_el.add({ type = "button", caption = { "bpd.edit" }, tags = { bpd = "edit", design = id } })
    table_el.add({ type = "button", caption = { "bpd.get" }, tags = { bpd = "get", design = id } })
  end
  if not any then
    scroll.add({ type = "label", caption = { "bpd.no-designs" } })
  end

  local footer = frame.add({ type = "flow", direction = "horizontal" })
  footer.style.top_margin = 8
  footer.add({ type = "button", caption = { "bpd.new-design" }, style = "confirm_button", tags = { bpd = "new" } })
  player.opened = frame
end

function M.refresh_bar(player)
  destroy(player.gui.top[BAR])
  local ed = storage.editing[player.index]
  if not ed then return end
  local design = designs.get(ed.design_id)
  if not design then return end
  local frame = player.gui.top.add({ type = "frame", name = BAR, direction = "horizontal" })
  frame.add({ type = "label", caption = { "bpd.editing", design.name, ed.tier }, style = "heading_2_label" })
  frame.add({ type = "button", caption = { "bpd.save" }, tags = { bpd = "save" } })
  frame.add({ type = "button", caption = { "bpd.save-return" }, style = "confirm_button", tags = { bpd = "save_return" } })
end

editor.on_change = function(player)
  M.refresh_bar(player)
end

function M.on_click(event)
  local tags = event.element.tags
  if not (tags and tags.bpd) then return end
  local player = game.get_player(event.player_index)
  local action = tags.bpd

  if action == "close" then
    M.close_window(player)
  elseif action == "new" then
    M.close_window(player)
    local design = designs.create(nil, player.force)
    editor.enter(player, design, 1)
  elseif action == "edit" then
    local design = designs.get(tags.design)
    if design then
      M.close_window(player)
      editor.enter(player, design, 1)
    end
  elseif action == "get" then
    local design = designs.get(tags.design)
    if design then
      M.close_window(player)
      designs.give(player, design, 1)
    end
  elseif action == "save" then
    editor.save_in_place(player)
  elseif action == "save_return" then
    editor.leave(player, { save = true, deliver = true })
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
  if event.element and event.element.valid and event.element.name == WINDOW then
    event.element.destroy()
  end
end

return M
