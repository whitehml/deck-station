extends Node

signal slot_changed(slot: int)
signal claims_changed

const KEYBOARD_DEVICE_ID := -2
const SLOTS: Array[int] = [1, 2]
const CLAIMS_PATH := "user://gamepad_claims.cfg"

const KB_LEFT_RING := [KEY_W, KEY_E, KEY_D, KEY_C, KEY_X, KEY_Z, KEY_A, KEY_Q]
const KB_RIGHT_RING := [KEY_I, KEY_O, KEY_L, KEY_PERIOD, KEY_COMMA, KEY_M, KEY_J, KEY_U]
const KB_LEFT_CENTER := KEY_S
const KB_RIGHT_CENTER := KEY_K

## Face buttons in the F310's diamond: Y top, A bottom, X left, B right.
const KB_Y := KEY_T
const KB_A := KEY_G
const KB_X := KEY_F
const KB_B := KEY_H

var slot := 1

var _is_deck := OS.get_environment("SteamDeck") == "1"
var _claim_names := {1: null, 2: null}  # intent (persisted); null = unclaimed
var _claims := {1: null, 2: null}  # live device ids (null = unclaimed), from intent + hardware
var _combo_prev := {}  # device id -> claim combo held last frame
var _left_order: Array[int] = []
var _right_order: Array[int] = []


func _ready() -> void:
	if not _is_deck:
		Input.joy_connection_changed.connect(func(_d: int, _c: bool) -> void: _reresolve())
		_load_claims()
		claims_changed.connect(_save_claims)
	if OS.get_environment("DECK_DS_PAD_DEBUG") == "1":
		Input.joy_connection_changed.connect(func(_d: int, _c: bool) -> void: _dump_pads())
		_dump_pads()


func _load_claims() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CLAIMS_PATH) != OK:
		return
	for slot_n in SLOTS:
		set_claim_name(slot_n, str(cfg.get_value("claims", "slot%d" % slot_n, "")))


func _save_claims() -> void:
	var cfg := ConfigFile.new()
	for slot_n in SLOTS:
		cfg.set_value("claims", "slot%d" % slot_n, claim_name(slot_n))
	cfg.save(CLAIMS_PATH)


func _dump_pads() -> void:
	print("[pads] slot=%d deck=%s external=%s" % [slot, deck_device(), external_device()])
	for id in Input.get_connected_joypads():
		print("  id=%d name=%s info=%s" % [id, Input.get_joy_name(id), Input.get_joy_info(id)])


func _process(_delta: float) -> void:
	if _is_deck:
		return
	for dev in Input.get_connected_joypads():
		var combo := &""
		if Input.is_joy_button_pressed(dev, JOY_BUTTON_START):
			if Input.is_joy_button_pressed(dev, JOY_BUTTON_A):
				combo = &"a"
			elif Input.is_joy_button_pressed(dev, JOY_BUTTON_B):
				combo = &"b"
		if combo != &"" and _combo_prev.get(dev, &"") != combo:
			claim(1 if combo == &"a" else 2, dev)
		_combo_prev[dev] = combo


func is_steam_deck() -> bool:
	return _is_deck


func is_text_focused() -> bool:
	var focus := get_viewport().gui_get_focus_owner()
	return focus is LineEdit or focus is TextEdit


func swap_slot() -> void:
	set_slot(2 if slot == 1 else 1)


func set_slot(new_slot: int) -> void:
	new_slot = clampi(new_slot, 1, 2)
	if new_slot == slot:
		return
	slot = new_slot
	slot_changed.emit(slot)


func claim(slot_n: int, device_id: int) -> void:
	set_claim_name(slot_n, _device_name(device_id))


func set_claim_name(slot_n: int, name: String) -> void:
	if _is_deck:
		return
	slot_n = clampi(slot_n, 1, 2)
	var intent = null if name.is_empty() else name
	if intent != null:
		for other in _claim_names:
			if other != slot_n and _claim_names[other] == intent:
				_claim_names[other] = null
	_claim_names[slot_n] = intent
	_reresolve()


func claim_name(slot_n: int) -> String:
	var intent = _claim_names.get(slot_n, null)
	return intent if intent != null else ""


func _device_name(device_id: int) -> String:
	if device_id == KEYBOARD_DEVICE_ID:
		return "Keyboard/Mouse"
	if device_id >= 0 and device_id in Input.get_connected_joypads():
		return Input.get_joy_name(device_id)
	return ""


func _reresolve() -> void:
	var changed := false
	for slot_n in SLOTS:
		var want = _claim_names[slot_n]
		var resolved = null
		if want == "Keyboard/Mouse":
			resolved = KEYBOARD_DEVICE_ID
		elif want != null:
			for id in Input.get_connected_joypads():
				if Input.get_joy_name(id) == want:
					resolved = id
					break
		if _claims[slot_n] != resolved:
			_claims[slot_n] = resolved
			changed = true
	if changed:
		claims_changed.emit()


func device_for_slot(slot_n: int):
	if _is_deck:
		return deck_device() if slot_n == slot else external_device()
	return _claims.get(slot_n, null)


## null is the sole "no device" sentinel; KEYBOARD_DEVICE_ID (-2) is a real,
## claimed device and must never be conflated with it.
func is_unclaimed(device_id) -> bool:
	return device_id == null


func neutral_state() -> Dictionary:
	return {
		"left_stick_x": 0.0,
		"left_stick_y": 0.0,
		"right_stick_x": 0.0,
		"right_stick_y": 0.0,
		"left_trigger": 0.0,
		"right_trigger": 0.0,
		"a": false,
		"b": false,
		"x": false,
		"y": false,
		"dpad_up": false,
		"dpad_down": false,
		"dpad_left": false,
		"dpad_right": false,
		"left_bumper": false,
		"right_bumper": false,
		"left_stick_button": false,
		"right_stick_button": false,
		"start": false,
		"back": false,
		"guide": false,
		"touchpad": false,
	}


func full_state(device_id: int) -> Dictionary:
	if device_id == KEYBOARD_DEVICE_ID:
		return _keyboard_state()
	var state := neutral_state()
	if device_id >= 0:
		var p := device_id
		state.left_stick_x = Input.get_joy_axis(p, JOY_AXIS_LEFT_X)
		state.left_stick_y = Input.get_joy_axis(p, JOY_AXIS_LEFT_Y)
		state.right_stick_x = Input.get_joy_axis(p, JOY_AXIS_RIGHT_X)
		state.right_stick_y = Input.get_joy_axis(p, JOY_AXIS_RIGHT_Y)
		state.left_trigger = Input.get_joy_axis(p, JOY_AXIS_TRIGGER_LEFT)
		state.right_trigger = Input.get_joy_axis(p, JOY_AXIS_TRIGGER_RIGHT)
		state.a = Input.is_joy_button_pressed(p, JOY_BUTTON_A)
		state.b = Input.is_joy_button_pressed(p, JOY_BUTTON_B)
		state.x = Input.is_joy_button_pressed(p, JOY_BUTTON_X)
		state.y = Input.is_joy_button_pressed(p, JOY_BUTTON_Y)
		state.dpad_up = Input.is_joy_button_pressed(p, JOY_BUTTON_DPAD_UP)
		state.dpad_down = Input.is_joy_button_pressed(p, JOY_BUTTON_DPAD_DOWN)
		state.dpad_left = Input.is_joy_button_pressed(p, JOY_BUTTON_DPAD_LEFT)
		state.dpad_right = Input.is_joy_button_pressed(p, JOY_BUTTON_DPAD_RIGHT)
		state.left_bumper = Input.is_joy_button_pressed(p, JOY_BUTTON_LEFT_SHOULDER)
		state.right_bumper = Input.is_joy_button_pressed(p, JOY_BUTTON_RIGHT_SHOULDER)
		state.left_stick_button = Input.is_joy_button_pressed(p, JOY_BUTTON_LEFT_STICK)
		state.right_stick_button = Input.is_joy_button_pressed(p, JOY_BUTTON_RIGHT_STICK)
		state.start = Input.is_joy_button_pressed(p, JOY_BUTTON_START)
		state.back = Input.is_joy_button_pressed(p, JOY_BUTTON_BACK)
	return state


## Poll-based keyboard "device" (desktop only). Ignores GUI focus, so it yields
## a neutral packet whenever a text field owns focus.
func _keyboard_state() -> Dictionary:
	var state := neutral_state()
	if is_text_focused():
		return state
	var left := _ring_stick(KB_LEFT_RING, _left_order, KB_LEFT_CENTER)
	var right := _ring_stick(KB_RIGHT_RING, _right_order, KB_RIGHT_CENTER)
	state.left_stick_x = left.x
	state.left_stick_y = left.y
	state.right_stick_x = right.x
	state.right_stick_y = right.y
	state.dpad_up = Input.is_key_pressed(KEY_UP)
	state.dpad_down = Input.is_key_pressed(KEY_DOWN)
	state.dpad_left = Input.is_key_pressed(KEY_LEFT)
	state.dpad_right = Input.is_key_pressed(KEY_RIGHT)
	state.a = Input.is_key_pressed(KB_A)
	state.b = Input.is_key_pressed(KB_B)
	state.x = Input.is_key_pressed(KB_X)
	state.y = Input.is_key_pressed(KB_Y)
	state.left_bumper = Input.is_key_pressed(KEY_1)
	state.right_bumper = Input.is_key_pressed(KEY_2)
	state.left_trigger = 1.0 if Input.is_key_pressed(KEY_3) else 0.0
	state.right_trigger = 1.0 if Input.is_key_pressed(KEY_4) else 0.0
	state.left_stick_button = Input.is_key_pressed(KEY_CTRL)
	state.right_stick_button = Input.is_key_pressed(KEY_ALT)
	state.start = Input.is_key_pressed(KEY_ENTER)
	state.back = Input.is_key_pressed(KEY_BACKSPACE)
	return state


func _ring_stick(ring: Array, order: Array[int], center_key: int) -> Vector2:
	var held := order.filter(func(k: int) -> bool: return Input.is_key_pressed(k))
	if held.size() != order.size():
		order.assign(held)
	if held.is_empty():
		return Vector2.ZERO
	var i_new: int = ring.find(held[-1])
	var heading := _ring_vec(i_new)
	if held.size() >= 2:
		var i_prev: int = ring.find(held[-2])
		var gap: int = absi(i_new - i_prev)
		if gap == 1 or gap == ring.size() - 1:
			heading = (heading + _ring_vec(i_prev)).normalized()
	var amplitude := 0.5 if Input.is_key_pressed(center_key) else 1.0
	return heading * amplitude


func _ring_vec(i: int) -> Vector2:
	var a := i * TAU / 8.0
	return Vector2(sin(a), -cos(a))


func _unhandled_key_input(event: InputEvent) -> void:
	if _is_deck or event is not InputEventKey or event.echo:
		return
	if event.pressed:
		# Claim keys reach here only when no text field swallowed them first.
		if event.keycode == KEY_BRACKETLEFT:
			claim(1, KEYBOARD_DEVICE_ID)
		elif event.keycode == KEY_BRACKETRIGHT:
			claim(2, KEYBOARD_DEVICE_ID)
	_track_ring(event, KB_LEFT_RING, _left_order)
	_track_ring(event, KB_RIGHT_RING, _right_order)


func _track_ring(event: InputEventKey, ring: Array, order: Array[int]) -> void:
	if event.keycode not in ring:
		return
	if event.pressed:
		if event.keycode not in order:
			order.append(event.keycode)
	else:
		order.erase(event.keycode)


func _devices_by_index() -> Array:
	var pads := Input.get_connected_joypads()
	pads.sort_custom(func(a: int, b: int) -> bool: return _steam_index(a) < _steam_index(b))
	return pads


func _steam_index(device: int) -> int:
	return int(Input.get_joy_info(device).get("steam_input_index", device))


func deck_device():
	var pads := _devices_by_index()
	for id in pads:
		if _is_builtin_deck(id):
			return id
	return pads[0] if not pads.is_empty() else null


func external_device():
	var deck = deck_device()
	for id in _devices_by_index():
		if id != deck:
			return id
	return null


func _is_builtin_deck(id: int) -> bool:
	var info := Input.get_joy_info(id)
	if int(info.get("vendor_id", 0)) == 0x28DE:
		return true
	return Input.get_joy_name(id).to_lower().contains("deck")
