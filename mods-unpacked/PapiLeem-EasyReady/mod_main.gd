extends Node

const MOD_DIR = "PapiLeem-EasyReady"
const MOD_LOG = "PapiLeem-EasyReady"
const ACTION_NAME = "easy_ready"

const ShopDetector = preload("res://mods-unpacked/PapiLeem-EasyReady/scripts/shop_detector.gd")
const HintView = preload("res://mods-unpacked/PapiLeem-EasyReady/scripts/hint_view.gd")

var _key_scancode: int = 71
var _joy_button: int = 10

var _active_shops = []

# Polling state — edge-detect raw input every frame in _process.
var _key_was_down: bool = false
var _joy_was_down: Dictionary = {}


func _init():
	ModLoaderLog.info("Init", MOD_LOG)


func _ready():
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

	var config = ModLoaderConfig.get_current_config(MOD_DIR)
	if config == null or config.data == null:
		ModLoaderLog.info("Bindings: key=" + str(_key_scancode) + " btn=" + str(_joy_button), MOD_LOG)
		return
	if config.data.has("keyboard_scancode"):
		_key_scancode = int(config.data["keyboard_scancode"])
	if config.data.has("joypad_button_index"):
		_joy_button = int(config.data["joypad_button_index"])
	_apply_input_binding(_key_scancode, _joy_button)
	ModLoaderLog.info("Bindings: key=" + str(_key_scancode) + " btn=" + str(_joy_button), MOD_LOG)


# Registers the base action in the InputMap so it shows up in any rebinding
# UI. Hotkey detection itself uses raw input polling in _process (not the
# InputMap), so this is purely cosmetic / for config interop.
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
		HintView.update_hint(hint, _key_scancode, _joy_button, _device_type_for_player(player_index))


func _on_device_changed() -> void:
	# In coop each player's hint stays pinned to the device type they joined
	# with — only single-player hints respond to live device swaps.
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
				HintView.update_hint(hint, _key_scancode, _joy_button, _device_type_for_player(player_index))


func _get_current_shop():
	for shop in _active_shops:
		if is_instance_valid(shop) and shop.is_inside_tree():
			return shop
	return null


# ─── polling-based hotkey detection ─────────────────────────────────────
# Queries Input.is_key_pressed / Input.is_joy_button_pressed directly to
# bypass Godot's event dispatch. The event-driven path turned out to be
# unreliable for our custom action in coop (G key never reached _input),
# probably due to InputMap action variants registered by Brotato's
# coop-debug mode. Polling sidesteps the whole question.

func _process(_delta: float) -> void:
	var shop = _get_current_shop()
	if shop == null:
		# Clear edge-state so a key held across scene transitions doesn't
		# fire on re-entry.
		_key_was_down = false
		_joy_was_down.clear()
		return
	if get_tree().paused:
		return

	# Keyboard — one keyboard, polled by scancode.
	var key_down = Input.is_key_pressed(_key_scancode)
	if key_down and not _key_was_down:
		_fire_for_keyboard(shop)
	_key_was_down = key_down

	# Joypad — poll each connected device for the bound button.
	var connected = Input.get_connected_joypads()
	for device in connected:
		var down = Input.is_joy_button_pressed(device, _joy_button)
		var was = false
		if _joy_was_down.has(device):
			was = _joy_was_down[device]
		if down and not was:
			_fire_for_joypad(shop, device)
		_joy_was_down[device] = down

	# Drop tracking entries for disconnected devices so they re-edge cleanly
	# if reconnected.
	var stale = []
	for known_device in _joy_was_down.keys():
		if not (known_device in connected):
			stale.append(known_device)
	for d in stale:
		_joy_was_down.erase(d)


func _fire_for_keyboard(shop) -> void:
	var player_index = 0
	if RunData.is_coop_run:
		player_index = -1
		for i in RunData.get_player_count():
			if CoopService.get_player_input_type(i) == CoopService.PlayerType.KEYBOARD_AND_MOUSE:
				player_index = i
				break
		if player_index < 0:
			return
	if shop.has_method("_on_GoButton_pressed"):
		shop._on_GoButton_pressed(player_index)


func _fire_for_joypad(shop, device: int) -> void:
	var player_index = 0
	if RunData.is_coop_run:
		player_index = -1
		for i in RunData.get_player_count():
			var t = CoopService.get_player_input_type(i)
			if t == CoopService.PlayerType.KEYBOARD_AND_MOUSE:
				continue
			var remapped = CoopService.get_remapped_player_device(i)
			var expected = remapped
			if remapped == CoopService.GAMEPAD_REMAPPED_DEVICE_ID:
				expected = 0
			if device == expected:
				player_index = i
				break
		if player_index < 0:
			return
	if shop.has_method("_on_GoButton_pressed"):
		shop._on_GoButton_pressed(player_index)


# ─── helpers ────────────────────────────────────────────────────────────

func _device_type_for_player(player_index: int) -> int:
	if RunData.is_coop_run and player_index < CoopService.connected_players.size():
		return CoopService.get_player_input_type(player_index)
	return UIService.current_device
