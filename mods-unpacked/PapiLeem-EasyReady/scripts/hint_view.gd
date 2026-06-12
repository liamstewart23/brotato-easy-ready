extends Reference

# Builds and updates the hotkey hint on the GO button — mirrors the lock
# button's AdditionalIcon treatment (51x51 glyph at the left edge, vertically
# centered, swaps texture when input device changes). Includes a clockwise
# hold-to-confirm progress disc reused from Brotato's coop-join scene.

const HINT_NODE_NAME = "EasyReadyHint"
const PROGRESS_NODE_NAME = "HoldProgress"
const CoopJoinProgressScene = preload("res://ui/menus/run/coop_join_progress.tscn")

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


static func make_hint(player_index: int = 0) -> Control:
	var container = Control.new()
	container.name = HINT_NODE_NAME
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Left edge of the button, vertically centered.
	container.anchor_left = 0.0
	container.anchor_right = 0.0
	container.anchor_top = 0.5
	container.anchor_bottom = 0.5
	container.margin_left = 8
	container.margin_right = 48
	container.margin_top = -20
	container.margin_bottom = 20
	container.rect_min_size = Vector2(40, 40)

	# Hold-to-confirm progress disc — uses Brotato's own coop-join scene so
	# the animation matches the join screen exactly. Added FIRST so the key
	# glyph above renders on top.
	var progress = CoopJoinProgressScene.instance()
	progress.name = PROGRESS_NODE_NAME
	progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	progress.anchor_left = 0
	progress.anchor_top = 0
	progress.anchor_right = 1
	progress.anchor_bottom = 1
	progress.margin_left = 0
	progress.margin_top = 0
	progress.margin_right = 0
	progress.margin_bottom = 0
	# The scene bakes rect_min_size = 80x80 which would force the disc's layout
	# box to overflow our 40x40 container. Clear it so the disc honors our size.
	progress.rect_min_size = Vector2(0, 0)
	# Inner TextureProgress draws the textures at their NATIVE pixel size
	# (128x128) multiplied by rect_scale. The scene's 0.625 was tuned to
	# render 80px on an 80x80 outer. We want 40px visible, so 40/128 ≈ 0.3125.
	# Also apply the per-player tint to the disc background here — we can't
	# use CoopJoinProgress.inner_color setter yet because its `_join_progress`
	# onready var hasn't resolved before the node enters the tree.
	var inner_progress = progress.get_node_or_null("JoinProgress")
	if inner_progress != null:
		inner_progress.rect_scale = Vector2(0.3125, 0.3125)
		# Background ring: dim player tint. Filling spinner: bright player tint.
		inner_progress.tint_under = CoopService.get_player_color(player_index, 0.4)
		inner_progress.tint_progress = CoopService.get_player_color(player_index, 1.0)
	progress.modulate.a = 0.0
	# We don't need the "?" player label baked into the scene.
	var lbl = progress.get_node_or_null("PlayerLabel")
	if lbl != null:
		lbl.visible = false
	container.add_child(progress)

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
# rendered for the given device_type (CoopService.PlayerType). Caller decides
# which device type to pass — UIService.current_device in single-player, or
# the per-player input type in coop.
static func update_hint(hint: Control, scancode: int, joy_button: int, device_type: int) -> void:
	if hint == null:
		return
	var tex_rect = hint.get_node_or_null("Texture")
	var fallback = hint.get_node_or_null("Fallback")
	if tex_rect == null or fallback == null:
		return

	var texture_path = _texture_path(scancode, joy_button, device_type)
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
	if device_type == CoopService.PlayerType.KEYBOARD_AND_MOUSE:
		label.text = OS.get_scancode_string(scancode)
	else:
		label.text = _joypad_button_name(joy_button)


static func _texture_path(scancode: int, joy_button: int, device_type: int) -> String:
	if device_type == CoopService.PlayerType.KEYBOARD_AND_MOUSE:
		if KEYBOARD_TEXTURES.has(scancode):
			return KEYBOARD_TEXTURES[scancode]
		return ""
	if device_type == CoopService.PlayerType.GAMEPAD_XBOX:
		if XBOX_TEXTURES.has(joy_button):
			return XBOX_TEXTURES[joy_button]
	elif device_type == CoopService.PlayerType.GAMEPAD_PLAYSTATION:
		if PS_TEXTURES.has(joy_button):
			return PS_TEXTURES[joy_button]
	elif device_type == CoopService.PlayerType.GAMEPAD_SWITCH:
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


# Sets the hold-to-confirm progress disc. progress01 is on a 0.0-1.0 scale.
# While holding (progress > 0) both icon branches are hidden so only the
# spinning disc is visible; on release (progress = 0) we restore whichever
# branch update_hint() had set as active.
static func set_progress(hint: Control, progress01: float) -> void:
	if hint == null:
		return
	var progress_node = hint.get_node_or_null(PROGRESS_NODE_NAME)
	var tex_rect = hint.get_node_or_null("Texture")
	var fallback = hint.get_node_or_null("Fallback")
	if progress_node == null:
		return

	var clamped = progress01
	if clamped < 0.0:
		clamped = 0.0
	elif clamped > 1.0:
		clamped = 1.0
	var holding = clamped > 0.0

	progress_node.progress = clamped * 100.0
	if holding:
		progress_node.modulate.a = 1.0
		# Hide both icon branches during the hold animation.
		if tex_rect != null:
			tex_rect.visible = false
		if fallback != null:
			fallback.visible = false
	else:
		progress_node.modulate.a = 0.0
		# Restore whichever icon branch was active. update_hint() sets a
		# texture only for bindings with a baked glyph (G / View / Share /
		# Minus); otherwise the styled Panel+Label fallback is active.
		var has_texture = tex_rect != null and tex_rect.texture != null
		if has_texture:
			tex_rect.visible = true
			if fallback != null:
				fallback.visible = false
		elif fallback != null:
			fallback.visible = true
			if tex_rect != null:
				tex_rect.visible = false
