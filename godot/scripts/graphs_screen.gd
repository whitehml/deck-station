extends VBoxContainer

signal graph_keys_changed(keys: PackedStringArray)
signal graph_window_changed(seconds: float)

## Discrete time-window options the scale slider snaps between, in seconds.
const WINDOW_VALUES := [2.0, 5.0, 10.0, 20.0, 30.0, 60.0]

var _picker_popup: PopupMenu
var _recorder := TelemetryRecorder.new()
var _save_dialog: FileDialog
var _message_dialog: AcceptDialog
var _record_started_s := 0.0


func _ready() -> void:
	TelemetryLog.keys_changed.connect(_on_keys_changed)
	TelemetryLog.samples_added.connect(_on_samples_added)
	_picker_popup = %SignalPicker.get_popup()
	_picker_popup.hide_on_checkable_item_selection = false
	_picker_popup.index_pressed.connect(_on_signal_toggled)
	%ClearButton.pressed.connect(_clear_selection)
	%TimeScale.value_changed.connect(_on_time_scale_changed)
	%RecordButton.pressed.connect(_on_record_pressed)
	_build_dialogs()
	_update_record_ui()
	_on_time_scale_changed(%TimeScale.value)
	_on_keys_changed(TelemetryLog.keys())


func _exit_tree() -> void:
	_recorder.stop()


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


## --- Recording ---


func _process(_delta: float) -> void:
	var elapsed := Time.get_ticks_msec() / 1000.0 - _record_started_s
	%RecordStatus.text = (
		"REC %02d:%02d · %d rows" % [elapsed / 60, int(elapsed) % 60, _recorder.row_count]
	)


func _on_samples_added(samples: Array) -> void:
	_recorder.write(samples)


func _on_record_pressed() -> void:
	if _recorder.is_recording():
		_stop_recording()
		return
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	_save_dialog.current_file = "telemetry_%s.csv" % stamp
	_save_dialog.popup_centered_ratio(0.8)


func _on_save_path_selected(target: String) -> void:
	if target.get_extension().to_lower() != "csv":
		target += ".csv"
	var err := _recorder.start(target)
	if err != OK:
		_show_message("Recording failed", "Could not open\n%s\n\n%s" % [target, error_string(err)])
		return
	_record_started_s = Time.get_ticks_msec() / 1000.0
	_update_record_ui()


func _stop_recording() -> void:
	var target := _recorder.path
	var rows := _recorder.row_count
	_recorder.stop()
	_update_record_ui()
	if _recorder.last_error != OK:
		_show_message(
			"Recording incomplete",
			(
				"%s\n\nWriting failed part-way through: %s"
				% [target, error_string(_recorder.last_error)]
			)
		)
		return
	_show_message("Recording saved", "%d rows written to\n\n%s" % [rows, target])


func _update_record_ui() -> void:
	var recording := _recorder.is_recording()
	%RecordButton.text = "Stop recording" if recording else "Record CSV"
	%RecordStatus.visible = recording
	set_process(recording)


func _show_message(title: String, text: String) -> void:
	_message_dialog.title = title
	_message_dialog.dialog_text = text
	_message_dialog.popup_centered()


func _build_dialogs() -> void:
	_save_dialog = FileDialog.new()
	_save_dialog.title = "Record telemetry to CSV"
	_save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_save_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_save_dialog.add_filter("*.csv", "CSV files")
	_save_dialog.current_dir = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	_save_dialog.file_selected.connect(_on_save_path_selected)
	add_child(_save_dialog)

	_message_dialog = AcceptDialog.new()
	add_child(_message_dialog)
