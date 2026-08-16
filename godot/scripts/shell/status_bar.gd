extends PanelContainer

const PHASE_NAMES := {
	RobotClient.Phase.DISCONNECTED: "—",
	RobotClient.Phase.IDLE: "IDLE",
	RobotClient.Phase.INIT: "INIT",
	RobotClient.Phase.RUNNING: "RUNNING",
}

const MATCH_SECONDS := 120.0
const ENDGAME_SECONDS := 30.0
const SLOT_STATUS := {1: &"slot1", 2: &"slot2"}

var _clock_idle := false
var _connected := false


func _ready() -> void:
	%StopButton.pressed.connect(_on_action_pressed)
	_size_action_button()
	RobotClient.connection_changed.connect(_on_connection_changed)
	RobotClient.phase_changed.connect(_on_phase_changed)
	RobotClient.selected_opmode_changed.connect(_on_selected_opmode_changed)
	RobotClient.battery_voltage_changed.connect(_on_battery_voltage)
	RobotClient.opmode_error_changed.connect(_on_opmode_error_changed)
	%ErrorDismiss.pressed.connect(RobotClient.clear_opmode_error)
	_on_opmode_error_changed(RobotClient.opmode_error)
	GamepadBridge.slot_changed.connect(_on_slot_changed)
	GamepadBridge.claims_changed.connect(_update_slot_badge)
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	_update_slot_badge()
	_update_action()


func _process(_delta: float) -> void:
	_update_clock()


func _tint(label: Label, status: StringName) -> void:
	label.add_theme_color_override("font_color", get_theme_color(status, ThemeTokens.STATUS_TYPE))


func _untint(label: Label) -> void:
	label.remove_theme_color_override("font_color")


func refresh_tints() -> void:
	_on_connection_changed(_connected)
	_update_slot_badge()
	_clock_idle = false


func _on_connection_changed(connected: bool) -> void:
	_connected = connected
	%ConnectionLabel.text = "CONNECTED" if connected else "DISCONNECTED"
	_tint(%ConnectionLabel, &"connected" if connected else &"disconnected")


func _on_phase_changed(phase: int, opmode_name: String) -> void:
	_refresh_phase_label(phase, opmode_name)
	_update_action()


func _refresh_phase_label(phase: int, opmode_name: String) -> void:
	var label: String = PHASE_NAMES.get(phase, "?")
	var name := opmode_name if not opmode_name.is_empty() else RobotClient.selected_opmode
	if not name.is_empty():
		label += "  ·  " + name
	%PhaseLabel.text = label


func _on_action_pressed() -> void:
	match RobotClient.phase:
		RobotClient.Phase.IDLE:
			RobotClient.init_opmode()
		RobotClient.Phase.INIT:
			RobotClient.start_opmode()
		RobotClient.Phase.RUNNING:
			RobotClient.stop_opmode()


func _on_selected_opmode_changed(_opmode_name: String) -> void:
	_refresh_phase_label(RobotClient.phase, "")
	_update_action()


func _update_action() -> void:
	PhaseAction.apply(%StopButton, RobotClient.phase)


func _size_action_button() -> void:
	var btn: Button = %StopButton
	var font := btn.get_theme_font(&"font")
	var font_size := btn.get_theme_font_size(&"font_size")
	var widest := 0.0
	for label: String in PhaseAction.LABELS.values():
		widest = maxf(
			widest, font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size).x
		)
	var style := btn.get_theme_stylebox(&"normal")
	btn.custom_minimum_size.x = ceilf(
		widest + style.get_margin(SIDE_LEFT) + style.get_margin(SIDE_RIGHT)
	)


func _on_slot_changed(_slot: int) -> void:
	_update_slot_badge()


func _on_joy_connection_changed(_device: int, _connected: bool) -> void:
	_update_slot_badge()


func _update_slot_badge() -> void:
	%GP1Badge.text = "1:" + _slot_letter(1)
	_tint(%GP1Badge, SLOT_STATUS[1])
	%GP2Badge.text = "2:" + _slot_letter(2)
	_tint(%GP2Badge, SLOT_STATUS[2])


func _slot_letter(slot_n: int) -> String:
	var device = GamepadBridge.device_for_slot(slot_n)
	if GamepadBridge.is_unclaimed(device):
		return "—"
	if device == GamepadBridge.KEYBOARD_DEVICE_ID:
		return "K"
	if GamepadBridge.is_steam_deck() and device == GamepadBridge.deck_device():
		return "D"
	return "C"


func _on_battery_voltage(volts: float) -> void:
	%BatteryLabel.text = "%0.2f V" % volts


func _on_opmode_error_changed(text: String) -> void:
	%ErrorText.text = text
	%ErrorBanner.visible = not text.is_empty()


func _update_clock() -> void:
	if RobotClient.phase != RobotClient.Phase.RUNNING:
		if not _clock_idle:
			%MatchClockLabel.text = "-:--"
			_untint(%MatchClockLabel)
			_clock_idle = true
		return
	_clock_idle = false
	var remaining := maxf(0.0, MATCH_SECONDS - RobotClient.run_elapsed())
	%MatchClockLabel.text = "%d:%04.1f" % [int(remaining) / 60, fmod(remaining, 60.0)]
	if remaining <= ENDGAME_SECONDS:
		_tint(%MatchClockLabel, &"endgame")
	else:
		_untint(%MatchClockLabel)
