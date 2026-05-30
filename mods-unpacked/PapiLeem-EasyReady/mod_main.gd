extends Node

const MOD_DIR = "PapiLeem-EasyReady"
const MOD_LOG = "PapiLeem-EasyReady"
const ACTION_NAME = "easy_ready"

const ShopDetector = preload("res://mods-unpacked/PapiLeem-EasyReady/scripts/shop_detector.gd")
const HintView = preload("res://mods-unpacked/PapiLeem-EasyReady/scripts/hint_view.gd")

# Live binding values. We match events directly against these instead of
# relying on InputMap.is_action_pressed (proved unreliable in logs).
var _key_scancode: int = 71
var _joy_button: int = 10

var _active_shops = []
# Guards against firing twice when both _input and _unhandled_input see
# the same event.
var _last_handled_event_id: int = -1


func _init():
	ModLoaderLog.info("Init", MOD_LOG)


func _ready():
	# Force-enable — auto-enable can be unreliable when our script is added
	# as a child of an autoload rather than as a top-level autoload itself.
	set_process_unhandled_input(true)
	set_process_input(true)

	_register_input_action()
	if not get_tree().is_connected("node_added", self, "_on_node_added"):
		get_tree().connect("node_added", self, "_on_node_added")
	if not UIService.is_connected("change_device", self, "_on_device_changed"):
		UIService.connect("change_device", self, "_on_device_changed")
	ModLoaderLog.info("Ready", MOD_LOG)


# ─── input action registration ──────────────────────────────────────────

func _register_input_action() -> void:
	_key_scancode = 71
	_joy_button = 10
	_apply_input_binding(_key_scancode, _joy_button)
	ModLoaderLog.info("Registered " + ACTION_NAME + " G=71 btn=10", MOD_LOG)

	var config = ModLoaderConfig.get_current_config(MOD_DIR)
	if config == null or config.data == null:
		return
	var changed = false
	if config.data.has("keyboard_scancode"):
		_key_scancode = int(config.data["keyboard_scancode"])
		changed = true
	if config.data.has("joypad_button_index"):
		_joy_button = int(config.data["joypad_button_index"])
		changed = true
	if changed:
		_apply_input_binding(_key_scancode, _joy_button)
		ModLoaderLog.info("Config override: key=" + str(_key_scancode) + " btn=" + str(_joy_button), MOD_LOG)


func _apply_input_binding(scancode: int, button_index: int) -> void:
	if not InputMap.has_action(ACTION_NAME):
		InputMap.add_action(ACTION_NAME)
	InputMap.action_erase_events(ACTION_NAME)

	var key_event = InputEventKey.new()
	key_event.scancode = scancode
	key_event.physical_scancode = scancode
	InputMap.action_add_event(ACTION_NAME, key_event)

	var btn_event = InputEventJoypadButton.new()
	btn_event.button_index = button_index
	btn_event.device = -1
	InputMap.action_add_event(ACTION_NAME, btn_event)


# ─── shop tracking ──────────────────────────────────────────────────────

func _on_node_added(node: Node) -> void:
	if not ShopDetector.is_shop(node):
		return
	if _active_shops.has(node):
		return
	_active_shops.append(node)
	node.connect("tree_exited", self, "_on_shop_exited", [node])
	call_deferred("_setup_shop", node)


func _on_shop_exited(shop) -> void:
	_active_shops.erase(shop)


func _setup_shop(shop) -> void:
	if not is_instance_valid(shop) or not shop.is_inside_tree():
		return
	for player_index in RunData.get_player_count():
		if not shop.has_method("_get_go_button"):
			continue
		var go_button = shop._get_go_button(player_index)
		if go_button == null or go_button.has_node(HintView.HINT_NODE_NAME):
			continue
		var hint = HintView.make_hint()
		go_button.add_child(hint)
		HintView.update_hint(hint, _key_scancode, _joy_button)


func _on_device_changed() -> void:
	for shop in _active_shops:
		if not is_instance_valid(shop) or not shop.is_inside_tree():
			continue
		for player_index in RunData.get_player_count():
			if not shop.has_method("_get_go_button"):
				continue
			var go_button = shop._get_go_button(player_index)
			if go_button == null:
				continue
			var hint = go_button.get_node_or_null(HintView.HINT_NODE_NAME)
			if hint != null:
				HintView.update_hint(hint, _key_scancode, _joy_button)


func _get_current_shop():
	for shop in _active_shops:
		if is_instance_valid(shop) and shop.is_inside_tree():
			return shop
	return null


# ─── hotkey input handling ──────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	_try_handle_hotkey(event)


func _unhandled_input(event: InputEvent) -> void:
	_try_handle_hotkey(event)


func _try_handle_hotkey(event: InputEvent) -> void:
	if not _event_matches_binding(event):
		return
	if get_tree().paused:
		return

	var event_id = event.get_instance_id()
	if event_id == _last_handled_event_id:
		return
	_last_handled_event_id = event_id

	var shop = _get_current_shop()
	if shop == null:
		shop = ShopDetector.find_shop_in_tree(get_tree())
		if shop != null and not _active_shops.has(shop):
			_active_shops.append(shop)
			if not shop.is_connected("tree_exited", self, "_on_shop_exited"):
				shop.connect("tree_exited", self, "_on_shop_exited", [shop])
			call_deferred("_setup_shop", shop)
	if shop == null:
		return

	var player_index = 0
	if RunData.is_coop_run:
		player_index = _player_index_for_event(event)
		if player_index < 0:
			return

	if not shop.has_method("_on_GoButton_pressed"):
		return
	shop._on_GoButton_pressed(player_index)
	get_tree().set_input_as_handled()


func _event_matches_binding(event: InputEvent) -> bool:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.scancode == _key_scancode or event.physical_scancode == _key_scancode:
			return true
	elif event is InputEventJoypadButton and event.pressed:
		if event.button_index == _joy_button:
			return true
	return false


func _player_index_for_event(event: InputEvent) -> int:
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		for i in RunData.get_player_count():
			if CoopService.get_remapped_player_device(i) == event.device:
				return i
		return -1
	if event is InputEventKey:
		return 0
	return -1
