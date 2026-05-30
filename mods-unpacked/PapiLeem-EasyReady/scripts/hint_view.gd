extends Reference

# Builds and updates the hotkey hint on the GO button — mirrors the lock
# button's AdditionalIcon treatment (51x51 glyph at the left edge, vertically
# centered, swaps texture when input device changes).

const HINT_NODE_NAME = "EasyReadyHint"

# Only the bindings we actually ship. Anything else falls back to the styled
# Panel+Label.
const KEYBOARD_TEXTURES = {
	71: "res://mods-unpacked/PapiLeem-EasyReady/assets/key_g.png",
}
const XBOX_TEXTURES = {
	10: "res://mods-unpacked/PapiLeem-EasyReady/assets/key_xbox_back.png",
}
const PS_TEXTURES = {
	10: "res://mods-unpacked/PapiLeem-EasyReady/assets/key_ps_share.png",
}
const SWITCH_TEXTURES = {
	10: "res://mods-unpacked/PapiLeem-EasyReady/assets/key_switch_minus.png",
}


static func make_hint() -> Control:
	var container = Control.new()
	container.name = HINT_NODE_NAME
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Left edge of the button, vertically centered.
	container.anchor_left = 0.0
	container.anchor_right = 0.0
	container.anchor_top = 0.5
	container.anchor_bottom = 0.5
	container.margin_left = 8
	container.margin_right = 59
	container.margin_top = -25
	container.margin_bottom = 26
	container.rect_min_size = Vector2(51, 51)

	var tex_rect = TextureRect.new()
	tex_rect.name = "Texture"
	tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tex_rect.anchor_left = 0
	tex_rect.anchor_top = 0
	tex_rect.anchor_right = 1
	tex_rect.anchor_bottom = 1
	tex_rect.expand = true
	tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	container.add_child(tex_rect)

	container.add_child(_make_fallback_panel())
	return container


static func _make_fallback_panel() -> Panel:
	var fallback = Panel.new()
	fallback.name = "Fallback"
	fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fallback.anchor_left = 0
	fallback.anchor_top = 0
	fallback.anchor_right = 1
	fallback.anchor_bottom = 1

	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.28, 0.28, 0.28, 1.0)
	sb.border_width_left = 5
	sb.border_width_top = 5
	sb.border_width_right = 5
	sb.border_width_bottom = 5
	sb.border_color = Color(0.06, 0.06, 0.06, 1.0)
	sb.corner_radius_top_left = 10
	sb.corner_radius_top_right = 10
	sb.corner_radius_bottom_left = 10
	sb.corner_radius_bottom_right = 10
	fallback.add_stylebox_override("panel", sb)

	var label = Label.new()
	label.name = "Text"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.anchor_left = 0
	label.anchor_top = 0
	label.anchor_right = 1
	label.anchor_bottom = 1
	label.align = Label.ALIGN_CENTER
	label.valign = Label.VALIGN_CENTER
	label.add_color_override("font_color", Color(0.95, 0.95, 0.95, 1.0))
	label.add_color_override("font_color_shadow", Color(0, 0, 0, 0.6))
	label.add_constant_override("shadow_offset_x", 1)
	label.add_constant_override("shadow_offset_y", 1)
	fallback.add_child(label)
	return fallback


# Refreshes the hint's texture and fallback text for the given bindings,
# based on the user's current input device (UIService.current_device).
static func update_hint(hint: Control, scancode: int, joy_button: int) -> void:
	if hint == null:
		return
	var tex_rect = hint.get_node_or_null("Texture")
	var fallback = hint.get_node_or_null("Fallback")
	if tex_rect == null or fallback == null:
		return

	var texture_path = _texture_path(scancode, joy_button)
	if texture_path != "":
		var tex = load(texture_path)
		if tex != null:
			tex_rect.texture = tex
			tex_rect.visible = true
			fallback.visible = false
			return

	# No baked glyph for this binding — show styled text instead.
	tex_rect.visible = false
	fallback.visible = true
	var label = fallback.get_node_or_null("Text")
	if label == null:
		return
	if UIService.current_device == CoopService.PlayerType.KEYBOARD_AND_MOUSE:
		label.text = OS.get_scancode_string(scancode)
	else:
		label.text = _joypad_button_name(joy_button)


static func _texture_path(scancode: int, joy_button: int) -> String:
	var device = UIService.current_device
	if device == CoopService.PlayerType.KEYBOARD_AND_MOUSE:
		if KEYBOARD_TEXTURES.has(scancode):
			return KEYBOARD_TEXTURES[scancode]
		return ""
	if device == CoopService.PlayerType.GAMEPAD_XBOX:
		if XBOX_TEXTURES.has(joy_button):
			return XBOX_TEXTURES[joy_button]
	elif device == CoopService.PlayerType.GAMEPAD_PLAYSTATION:
		if PS_TEXTURES.has(joy_button):
			return PS_TEXTURES[joy_button]
	elif device == CoopService.PlayerType.GAMEPAD_SWITCH:
		if SWITCH_TEXTURES.has(joy_button):
			return SWITCH_TEXTURES[joy_button]
	return ""


const JOYPAD_BUTTON_NAMES = {
	0: "A", 1: "B", 2: "X", 3: "Y",
	4: "LB", 5: "RB", 6: "LT", 7: "RT",
	8: "L3", 9: "R3", 10: "Back", 11: "Start",
	12: "Up", 13: "Down", 14: "Left", 15: "Right",
}


static func _joypad_button_name(button_index: int) -> String:
	if JOYPAD_BUTTON_NAMES.has(button_index):
		return JOYPAD_BUTTON_NAMES[button_index]
	return "BTN" + str(button_index)
