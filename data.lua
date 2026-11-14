local BLUEPRINT_ICON = "__base__/graphics/icons/blueprint.png"
local EMPTY = "__core__/graphics/empty.png"

data:extend({
  -- Hotkey: edit the held blueprint, or save & leave the designer, or open the designs window.
  {
    type = "custom-input",
    name = "bpd-toggle",
    key_sequence = "CONTROL + ALT + B",
    consuming = "game-only",
    order = "a",
  },
  {
    type = "shortcut",
    name = "bpd-toggle",
    action = "lua",
    associated_control_input = "bpd-toggle",
    icon = "__base__/graphics/icons/shortcut-toolbar/mip/new-blueprint-x56.png",
    icon_size = 56,
    small_icon = "__base__/graphics/icons/shortcut-toolbar/mip/new-blueprint-x24.png",
    small_icon_size = 24,
    style = "blue",
    order = "b[blueprints]-z[blueprint-designer]",
  },

  -- The design marker. One lives at the centre of every design cell and is captured into
  -- every blueprint the mod saves, carrying tags {bpd_design, bpd_tier, bpd_version}.
  -- When a blueprint is placed in the world the marker identifies that placed copy (part 3).
  {
    type = "item",
    name = "bpd-marker",
    icon = BLUEPRINT_ICON,
    icon_size = 64,
    hidden = true,
    flags = { "only-in-cursor" },
    subgroup = "other",
    order = "z[bpd-marker]",
    place_result = "bpd-marker",
    stack_size = 1,
  },
  {
    type = "simple-entity-with-owner",
    name = "bpd-marker",
    icon = BLUEPRINT_ICON,
    icon_size = 64,
    flags = { "placeable-neutral", "player-creation", "not-upgradable", "not-rotatable" },
    hidden = true,
    minable = { mining_time = 0.1 },
    max_health = 50,
    collision_box = { { -0.2, -0.2 }, { 0.2, 0.2 } },
    collision_mask = { layers = {} },
    selection_box = { { -0.5, -0.5 }, { 0.5, 0.5 } },
    selection_priority = 60,
    render_layer = "higher-object-above",
    picture = { filename = BLUEPRINT_ICON, size = 64, scale = 0.35 },
    placeable_by = { item = "bpd-marker", count = 1 },
  },

  -- Invisible radar so the designer surface is live-visible in remote view.
  {
    type = "radar",
    name = "bpd-editor-radar",
    icon = BLUEPRINT_ICON,
    icon_size = 64,
    flags = { "not-on-map", "not-blueprintable", "not-deconstructable", "placeable-off-grid", "hide-alt-info" },
    hidden = true,
    max_health = 1,
    collision_box = { { -0.1, -0.1 }, { 0.1, 0.1 } },
    collision_mask = { layers = {} },
    selectable_in_game = false,
    energy_source = { type = "void" },
    energy_usage = "1W",
    energy_per_sector = "1J",
    energy_per_nearby_scan = "1J",
    max_distance_of_sector_revealed = 0,
    max_distance_of_nearby_sector_revealed = 6,
    connects_to_other_radars = false,
    pictures = { filename = EMPTY, size = 1, direction_count = 1 },
  },
})
