extends VBoxContainer

signal graph_keys_changed(keys: PackedStringArray)
signal graph_window_changed(seconds: float)

## Discrete time-window options the scale slider snaps between, in seconds.
const WINDOW_VALUES := [2.0, 5.0, 10.0, 20.0, 30.0, 60.0]

var _picker_popup: PopupMenu


func _ready() -> void:
	TelemetryLog.keys_changed.connect(_on_keys_changed)
	_picker_popup = %SignalPicker.get_popup()
	_picker_popup.hide_on_checkable_item_selection = false
	_picker_popup.index_pressed.connect(_on_signal_toggled)
	%ClearButton.pressed.connect(_clear_selection)
	%TimeScale.value_changed.connect(_on_time_scale_changed)
	_on_time_scale_changed(%TimeScale.value)
	_on_keys_changed(TelemetryLog.keys())


func _on_time_scale_changed(index: float) -> void:
	var seconds: float = WINDOW_VALUES[int(index)]
	%Graph.window_seconds = seconds
	%TimeScaleLabel.text = "%ds" % seconds
	graph_window_changed.emit(seconds)


func grip_tap(grip: StringName) -> void:
	var step := -1.0 if grip == &"L4" else 1.0
	%TimeScale.value = clampf(%TimeScale.value + step, %TimeScale.min_value, %TimeScale.max_value)


func _on_keys_changed(keys: Array) -> void:
	var selected := _selected_keys()
	_picker_popup.clear()
	for i in range(keys.size()):
		_picker_popup.add_check_item(keys[i], i)
		_picker_popup.set_item_checked(i, selected.has(keys[i]))
	%SignalPicker.disabled = keys.is_empty()
	_apply_selection()


func _on_signal_toggled(index: int) -> void:
	_picker_popup.set_item_checked(index, not _picker_popup.is_item_checked(index))
	_apply_selection()


func _clear_selection() -> void:
	for i in range(_picker_popup.item_count):
		_picker_popup.set_item_checked(i, false)
	_apply_selection()


func _selected_keys() -> PackedStringArray:
	var out := PackedStringArray()
	for i in range(_picker_popup.item_count):
		if _picker_popup.is_item_checked(i):
			out.append(_picker_popup.get_item_text(i))
	return out


func _apply_selection() -> void:
	var keys := _selected_keys()
	%Graph.keys = keys
	%SignalPicker.text = _picker_label(keys)
	graph_keys_changed.emit(keys)


func _picker_label(keys: PackedStringArray) -> String:
	if keys.is_empty():
		return "Select signals"
	if keys.size() == 1:
		return keys[0]
	return "%d signals" % keys.size()
