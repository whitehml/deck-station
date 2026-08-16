extends Control

const PAGE_ORDER: Array[StringName] = [&"drive", &"graphs", &"field", &"opmodes", &"config"]

var _current_page: StringName = &"drive"
var _slot_radial_open := false

@onready var _pages := {
	&"drive": %DrivePage,
	&"graphs": %GraphsPage,
	&"field": %FieldPage,
	&"opmodes": %OpModesPage,
	&"config": %ConfigPage,
}
@onready var _tabs := {
	&"drive": %DriveTab,
	&"graphs": %GraphsTab,
	&"field": %FieldTab,
	&"opmodes": %OpModesTab,
	&"config": %ConfigTab,
}
@onready var _background := %Background


func _ready() -> void:
	for page_name in _tabs:
		_tabs[page_name].pressed.connect(_show_page.bind(page_name))

	RobotClient.phase_changed.connect(_on_phase_changed)

	GripInput.grip_tap.connect(_on_grip_tap)
	GripInput.grip_hold_started.connect(_on_grip_hold_started)
	GripInput.grip_hold_ended.connect(_on_grip_hold_ended)

	%DrivePage.radial = %Radial
	%OpModesPage.radial = %Radial
	%GraphsPage.graph_keys_changed.connect(%DrivePage.set_graph_keys)
	%GraphsPage.graph_window_changed.connect(%DrivePage.set_graph_window)
	%FieldPage.format_help_requested.connect(%SettingsButton.show_field_help)
	%FieldPage.frame_requested.connect(%SettingsButton.show_field_frame)
	%SettingsButton.theme_selected.connect(_apply_theme)

	_apply_theme(%SettingsButton.theme_index)
	_show_page(&"drive")


func _process(_delta: float) -> void:
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


func _apply_theme(index: int) -> void:
	theme = AppThemes.for_index(index)
	_background.color = AppThemes.background_color(index)
	%StatusBar.refresh_tints()


func _on_phase_changed(phase: int, _opmode_name: String) -> void:
	if phase == RobotClient.Phase.RUNNING:
		_show_page(&"drive")


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
			if %SettingsButton.controls_help_visible():
				%SettingsButton.focus_controls_help()
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
