extends Node

signal grip_tap(grip: StringName)
signal grip_hold_started(grip: StringName)
signal grip_hold_ended(grip: StringName)

const HOLD_S := 0.3

const KEY_TO_GRIP := {
	KEY_F1: &"L4",
	KEY_F2: &"L5",
	KEY_F3: &"R4",
	KEY_F4: &"R5",
}

var ui_nav_active := false

var _down := {}  # grip -> seconds held so far
var _held := {}  # grip -> crossed HOLD_S


func _input(event: InputEvent) -> void:
	if event is not InputEventKey or event.echo:
		return
	var grip: StringName = KEY_TO_GRIP.get(event.keycode, &"")
	if grip == &"":
		return
	if event.pressed:
		if GamepadBridge.is_text_focused():
			return
		get_viewport().set_input_as_handled()
		if not _down.has(grip):
			_down[grip] = 0.0
	elif _down.has(grip):
		get_viewport().set_input_as_handled()
		_down.erase(grip)
		if _held.get(grip, false):
			_held.erase(grip)
			if grip == &"R4":
				ui_nav_active = false
			grip_hold_ended.emit(grip)
		else:
			grip_tap.emit(grip)


func _process(delta: float) -> void:
	for grip in _down:
		_down[grip] += delta
		if _down[grip] >= HOLD_S and not _held.get(grip, false):
			_held[grip] = true
			if grip == &"R4":
				ui_nav_active = true
			grip_hold_started.emit(grip)
