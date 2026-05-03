-- data.lua

data:extend({
  {
    type = "sprite",
    name = "srm-route-icon",
    filename = "__space-route-manager__/graphics/route-icon.png",
    size = 32,
    flags = {"icon"}
  }
})

local styles = data.raw["gui-style"]["default"]

styles["srm_route_button"] = {
  type = "button_style",
  parent = "frame_button",
  size = 32,
  padding = 2,
}

styles["srm_route_entry_button"] = {
  type = "button_style",
  parent = "list_box_item",
  horizontally_stretchable = "on",
  left_padding = 8,
  right_padding = 8,
}

styles["srm_disabled_route_button"] = {
  type = "button_style",
  parent = "srm_route_entry_button",
  font_color = {r=0.6, g=0.2, b=0.2},
  hovered_font_color = {r=0.9, g=0.3, b=0.3},
}

styles["srm_enabled_route_button"] = {
  type = "button_style",
  parent = "srm_route_entry_button",
  font_color = {r=0.2, g=0.7, b=0.2},
  hovered_font_color = {r=0.3, g=0.9, b=0.3},
}
