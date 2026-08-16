extends Control

const PHASE_NAMES := {
	RobotClient.Phase.DISCONNECTED: "—",
	RobotClient.Phase.IDLE: "IDLE",
	RobotClient.Phase.INIT: "INIT",
	RobotClient.Phase.RUNNING: "RUNNING",
}

const MATCH_SECONDS := 120.0
const ENDGAME_SECONDS := 30.0
const SLOT_STATUS := {1: &"slot1", 2: &"slot2"}

const PAGE_ORDER: Array[StringName] = [&"drive", &"graphs", &"opmodes", &"config"]

## Settings-menu item ids, kept clear of the theme submenu's 0-based ids.
const UPDATE_ID := 1000
const QUIT_ID := 1001
const CONTROLS_ID := 1002
const DEVICE_FILTER_ID := 1003
const SETTINGS_PATH := "user://settings.cfg"
const UPDATER := preload("res://scripts/updater.gd")
const CONTROLS_HELP := preload("res://scripts/controls_help.gd")

var _current_page: StringName = &"drive"
var _slot_radial_open := false
var _theme_index := 0
var _quit_dialog: ConfirmationDialog
var _updater: Node
var _controls_help: AcceptDialog
var _device_filter_dialog: DeviceFilterDialog
var _clock_idle := false
var _connected := false

@onready var _pages := {
	&"drive": %DrivePage,
	&"graphs": %GraphsPage,
	&"opmodes": %OpModesPage,
	&"config": %ConfigPage,
}
@onready var _tabs := {
	&"drive": %DriveTab,
	&"graphs": %GraphsTab,
	&"opmodes": %OpModesTab,
	&"config": %ConfigTab,
}
@onready var _background := %Background


func _ready() -> void:
	for page_name in _tabs:
		_tabs[page_name].pressed.connect(_show_page.bind(page_name))
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
	GamepadBridge.claims_changed.connect(_on_claims_changed)
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	_update_slot_badge()

	GripInput.grip_tap.connect(_on_grip_tap)
	GripInput.grip_hold_started.connect(_on_grip_hold_started)
	GripInput.grip_hold_ended.connect(_on_grip_hold_ended)

	%DrivePage.radial = %Radial
	%OpModesPage.radial = %Radial
	%GraphsPage.graph_keys_changed.connect(%DrivePage.set_graph_keys)
	%GraphsPage.graph_window_changed.connect(%DrivePage.set_graph_window)

	_load_settings()
	_setup_settings_menu()
	_apply_theme(_theme_index)
	_show_page(&"drive")
	_update_action()


func _process(_delta: float) -> void:
	_update_clock()
	if not RobotClient.nav_active():
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			var focus := get_viewport().gui_get_focus_owner()
			if focus:
				focus.release_focus()
		return
	if GamepadBridge.is_text_focused():
		return
	if Input.is_action_just_pressed(&"page_next"):
		_cycle_page(1)
	elif Input.is_action_just_pressed(&"page_prev"):
		_cycle_page(-1)


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if GamepadBridge.is_text_focused():
		return
	match event.keycode:
		KEY_DELETE:
			_stop()
		KEY_SPACE:
			_toggle_graph_pause()
		_:
			return
	get_viewport().set_input_as_handled()


func _toggle_graph_pause() -> void:
	TelemetryLog.paused = not TelemetryLog.paused


## --- Pages ---


func _show_page(page_name: StringName) -> void:
	_current_page = page_name
	for p in _pages:
		var page: Control = _pages[p]
		page.visible = p == page_name
		if page.visible:
			page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_tabs[p].set_pressed_no_signal(p == page_name)
	_link_tab_to_page(page_name)


func _link_tab_to_page(page_name: StringName) -> void:
	var tab: Button = _tabs[page_name]
	var target := _first_focusable(_pages[page_name])
	if target:
		tab.focus_neighbor_bottom = tab.get_path_to(target)
		target.focus_neighbor_top = target.get_path_to(tab)


func _cycle_page(dir: int) -> void:
	var i := PAGE_ORDER.find(_current_page)
	if i == -1:
		return
	_show_page(PAGE_ORDER[(i + dir + PAGE_ORDER.size()) % PAGE_ORDER.size()])
	var target := _first_focusable(_pages[_current_page])
	if target:
		target.grab_focus()


## --- Settings menu  ---


func _setup_settings_menu() -> void:
	var popup: PopupMenu = %SettingsButton.get_popup()
	var themes := PopupMenu.new()
	themes.name = "ThemesMenu"
	for i in AppThemes.THEMES.size():
		themes.add_radio_check_item(AppThemes.spec(i)[&"name"], i)
	themes.set_item_checked(_theme_index, true)
	themes.id_pressed.connect(_select_theme)
	popup.add_child(themes)
	popup.add_submenu_item("Themes", "ThemesMenu")

	popup.add_separator()
	popup.add_item("Controls", CONTROLS_ID)
	popup.add_item("Device Filter", DEVICE_FILTER_ID)
	popup.add_item("Check for Updates", UPDATE_ID)
	popup.add_item("Quit", QUIT_ID)
	popup.id_pressed.connect(_on_settings_id)

	_controls_help = CONTROLS_HELP.new()
	add_child(_controls_help)

	_device_filter_dialog = DeviceFilterDialog.new()
	add_child(_device_filter_dialog)

	_updater = UPDATER.new()
	add_child(_updater)

	_quit_dialog = ConfirmationDialog.new()
	_quit_dialog.title = "Quit"
	_quit_dialog.dialog_text = "Quit the Driver Station?"
	_quit_dialog.ok_button_text = "Quit"
	_quit_dialog.confirmed.connect(func() -> void: get_tree().quit())
	add_child(_quit_dialog)


func _on_settings_id(id: int) -> void:
	if id == QUIT_ID:
		_quit_dialog.popup_centered()
	elif id == UPDATE_ID:
		_updater.run()
	elif id == CONTROLS_ID:
		_controls_help.popup_centered_ratio(0.8)
	elif id == DEVICE_FILTER_ID:
		_device_filter_dialog.open()


func _select_theme(index: int) -> void:
	_theme_index = index
	var themes: PopupMenu = %SettingsButton.get_popup().get_node("ThemesMenu")
	for i in AppThemes.THEMES.size():
		themes.set_item_checked(i, i == index)
	_apply_theme(index)
	_save_settings()


func _apply_theme(index: int) -> void:
	theme = AppThemes.for_index(index)
	_background.color = AppThemes.background_color(index)
	_refresh_status_tints()


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	_theme_index = clampi(int(cfg.get_value("ui", "theme", 0)), 0, AppThemes.THEMES.size() - 1)


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("ui", "theme", _theme_index)
	cfg.save(SETTINGS_PATH)


## Any claim change (Start+A/B, keyboard brackets, hot-plug re-resolve) lands
## here to keep the badges in sync; GamepadBridge persists the claim itself.
func _on_claims_changed() -> void:
	_update_slot_badge()


## --- Grips ---


func _on_grip_tap(grip: StringName) -> void:
	match grip:
		&"R4":
			_stop()
		&"R5":
			GamepadBridge.swap_slot()
		&"L4", &"L5":
			var page: Control = _pages[_current_page]
			if page.has_method("grip_tap"):
				page.grip_tap(grip)


func _on_grip_hold_started(grip: StringName) -> void:
	match grip:
		&"R4":
			if GamepadBridge.is_text_focused():
				return
			if _controls_help.visible:
				_controls_help.focus_page()
				return
			var target := _first_focusable(_pages[_current_page])
			if target:
				target.grab_focus()
		&"R5":
			if %Radial.is_open():
				return
			_slot_radial_open = true
			var slices := [
				{"label": "GP1", "disabled": GamepadBridge.slot == 1},
				{"label": "GP2", "disabled": GamepadBridge.slot == 2},
			]
			%Radial.open(slices, get_global_rect().get_center(), -PI / 2)
		&"L4", &"L5":
			var page: Control = _pages[_current_page]
			if page.has_method("grip_hold_started"):
				page.grip_hold_started(grip)


func _on_grip_hold_ended(grip: StringName) -> void:
	match grip:
		&"R5":
			if not _slot_radial_open:
				return
			_slot_radial_open = false
			var picked: int = %Radial.finish()
			if picked >= 0:
				GamepadBridge.set_slot(picked + 1)
		&"L4", &"L5":
			var page: Control = _pages[_current_page]
			if page.has_method("grip_hold_ended"):
				page.grip_hold_ended(grip)


func _stop() -> void:
	if RobotClient.phase in [RobotClient.Phase.INIT, RobotClient.Phase.RUNNING]:
		RobotClient.stop_opmode()


func _first_focusable(node: Node) -> Control:
	if (
		node is Control
		and node.is_visible_in_tree()
		and node.focus_mode == Control.FOCUS_ALL
		and not (node is BaseButton and node.disabled)
	):
		return node
	for child in node.get_children():
		var found := _first_focusable(child)
		if found:
			return found
	return null


## --- Status bar ---


func _tint(label: Label, status: StringName) -> void:
	label.add_theme_color_override("font_color", get_theme_color(status, AppThemes.STATUS_TYPE))


func _untint(label: Label) -> void:
	label.remove_theme_color_override("font_color")


func _refresh_status_tints() -> void:
	_on_connection_changed(_connected)
	_update_slot_badge()
	_clock_idle = false


func _on_connection_changed(connected: bool) -> void:
	_connected = connected
	%ConnectionLabel.text = "CONNECTED" if connected else "DISCONNECTED"
	_tint(%ConnectionLabel, &"connected" if connected else &"disconnected")


func _on_phase_changed(phase: int, opmode_name: String) -> void:
	_refresh_phase_label(phase, opmode_name)
	if phase == RobotClient.Phase.RUNNING:
		_show_page(&"drive")
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
