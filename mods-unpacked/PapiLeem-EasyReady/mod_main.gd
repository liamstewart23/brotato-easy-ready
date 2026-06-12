extends Node

const MOD_DIR = "PapiLeem-EasyReady"
const MOD_LOG = "PapiLeem-EasyReady"
const ACTION_NAME = "easy_ready"
# Seconds the player must hold the hotkey before ready-up fires. Matches
# CoopService.HOLD_DURATION (the coop-join hold-to-confirm duration).
const HOLD_DURATION = 0.7

const ShopDetector = preload("res://mods-unpacked/PapiLeem-EasyReady/scripts/shop_detector.gd")
const HintView = preload("res://mods-unpacked/PapiLeem-EasyReady/scripts/hint_view.gd")

var _key_scancode: int = 71
var _joy_button: int = 10

var _active_shops = []

# Hold-to-confirm state. Each input source accumulates time while held;
# completion fires _on_GoButton_pressed once, then waits for release before
# it can fire again.
var _key_hold_time: float = 0.0
var _key_fired: bool = false
var _joy_hold_times: Dictionary = {}    # device → float
var _joy_fired: Dictionary = {}         # device → bool


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
		var hint = HintView.make_hint(player_index)
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


# ─── hold-to-confirm polling ────────────────────────────────────────────
# Polls Input.is_key_pressed / Input.is_joy_button_pressed each frame and
# accumulates hold time per input source. At HOLD_DURATION the action fires
# once; on release, the timer resets so the next hold can fire again. The
# progress disc on the GO button fills in real time. Mirrors Brotato's
# coop-join hold-to-confirm pattern (see coop_service.gd:114-122).

func _process(delta: float) -> void:
	var shop = _get_current_shop()
	if shop == null:
		# Clear hold state so a key held across scene transitions doesn't
		# accumulate or fire on re-entry.
		_key_hold_time = 0.0
		_key_fired = false
		_joy_hold_times.clear()
		_joy_fired.clear()
		return
	if get_tree().paused:
		return

	_tick_keyboard(shop, delta)
	_tick_joypads(shop, delta)


func _tick_keyboard(shop, delta: float) -> void:
	if Input.is_key_pressed(_key_scancode):
		_key_hold_time += delta
		var progress01 = _key_hold_time / HOLD_DURATION
		if progress01 > 1.0:
			progress01 = 1.0
		_update_keyboard_progress(shop, progress01)
		if _key_hold_time >= HOLD_DURATION and not _key_fired:
			_key_fired = true
			_fire_for_keyboard(shop)
	else:
		if _key_hold_time > 0.0 or _key_fired:
			_key_hold_time = 0.0
			_key_fired = false
			_update_keyboard_progress(shop, 0.0)


func _tick_joypads(shop, delta: float) -> void:
	var connected = Input.get_connected_joypads()
	for device in connected:
		var down = Input.is_joy_button_pressed(device, _joy_button)
		var t = 0.0
		if _joy_hold_times.has(device):
			t = _joy_hold_times[device]
		var fired = false
		if _joy_fired.has(device):
			fired = _joy_fired[device]
		if down:
			t += delta
			_joy_hold_times[device] = t
			var progress01 = t / HOLD_DURATION
			if progress01 > 1.0:
				progress01 = 1.0
			_update_joypad_progress(shop, device, progress01)
			if t >= HOLD_DURATION and not fired:
				_joy_fired[device] = true
				_fire_for_joypad(shop, device)
		else:
			if t > 0.0 or fired:
				_joy_hold_times[device] = 0.0
				_joy_fired[device] = false
				_update_joypad_progress(shop, device, 0.0)
	# Drop entries for disconnected devices so they re-arm cleanly if
	# reconnected.
	var stale = []
	for known in _joy_hold_times.keys():
		if not (known in connected):
			stale.append(known)
	for d in stale:
		_joy_hold_times.erase(d)
		_joy_fired.erase(d)


# ─── routing ────────────────────────────────────────────────────────────

func _keyboard_player_index() -> int:
	if not RunData.is_coop_run:
		return 0
	for i in RunData.get_player_count():
		if CoopService.get_player_input_type(i) == CoopService.PlayerType.KEYBOARD_AND_MOUSE:
			return i
	return -1


func _joypad_player_index(device: int) -> int:
	if not RunData.is_coop_run:
		return 0
	for i in RunData.get_player_count():
		var t = CoopService.get_player_input_type(i)
		if t == CoopService.PlayerType.KEYBOARD_AND_MOUSE:
			continue
		var remapped = CoopService.get_remapped_player_device(i)
		var expected = remapped
		if remapped == CoopService.GAMEPAD_REMAPPED_DEVICE_ID:
			expected = 0
		if device == expected:
			return i
	return -1


func _fire_for_keyboard(shop) -> void:
	_fire_ready(shop, _keyboard_player_index())


func _fire_for_joypad(shop, device: int) -> void:
	_fire_ready(shop, _joypad_player_index(device))


# Fires ready-up for the given player, then focuses their GO button. The
# GO button has a focus_exited signal wired to _clear_go_button_pressed
# (base_shop.gd:349) — so as soon as the player navigates away with
# arrow keys / D-pad, the ready state auto-cancels. Matches the UX of
# clicking the GO button directly.
func _fire_ready(shop, player_index: int) -> void:
	if player_index < 0:
		return
	if not shop.has_method("_on_GoButton_pressed"):
		return
	shop._on_GoButton_pressed(player_index)
	if shop.has_method("_get_go_button"):
		var go_button = shop._get_go_button(player_index)
		if go_button != null:
			Utils.focus_player_control(go_button, player_index)


func _update_keyboard_progress(shop, progress01: float) -> void:
	var player_index = _keyboard_player_index()
	if player_index < 0:
		return
	_set_player_hint_progress(shop, player_index, progress01)


func _update_joypad_progress(shop, device: int, progress01: float) -> void:
	var player_index = _joypad_player_index(device)
	if player_index < 0:
		return
	_set_player_hint_progress(shop, player_index, progress01)


func _set_player_hint_progress(shop, player_index: int, progress01: float) -> void:
	if not shop.has_method("_get_go_button"):
		return
	var go_button = shop._get_go_button(player_index)
	if go_button == null:
		return
	var hint = go_button.get_node_or_null(HintView.HINT_NODE_NAME)
	if hint != null:
		HintView.set_progress(hint, progress01)


# ─── helpers ────────────────────────────────────────────────────────────

func _device_type_for_player(player_index: int) -> int:
	if RunData.is_coop_run and player_index < CoopService.connected_players.size():
		return CoopService.get_player_input_type(player_index)
	return UIService.current_device
