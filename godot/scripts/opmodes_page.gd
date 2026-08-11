extends VBoxContainer

const AUTONOMOUS := "AUTONOMOUS"
const SYSTEM := "SYSTEM"
const TELEMETRY_HEADER := "Telemetry"
const UNFILTERED_LABEL := "All"
const DEFAULT_GROUP := "$$$$$$$"

const ACTION_LABELS := {
	RobotClient.Phase.IDLE: "INIT",
	RobotClient.Phase.INIT: "START",
	RobotClient.Phase.RUNNING: "STOP",
}
const ACTION_COLORS := {
	RobotClient.Phase.IDLE: Color(0.55, 0.75, 1.0),
	RobotClient.Phase.INIT: Color(0.4, 0.9, 0.4),
	RobotClient.Phase.RUNNING: Color(1, 0.3, 0.3),
}

## Injected by main.gd — the shared full-screen radial overlay.
var radial: Control

var _group := ButtonGroup.new()
var _group_filter := ""
var _auto_header_text := ""
var _tele_header_text := ""
var _group_radial_open := false

@onready var _auto_telem_box = %AutoTelem.get_node("Box")
@onready var _tele_telem_box = %TeleTelem.get_node("Box")


func _ready() -> void:
	RobotClient.opmode_list_changed.connect(_on_opmode_list)
	RobotClient.phase_changed.connect(_on_phase_changed)
	RobotClient.telemetry_received.connect(_on_telemetry)
	%GroupFilter.item_selected.connect(_on_group_filter_selected)
	%ActionButton.pressed.connect(_advance_phase)
	_auto_header_text = %AutoHeader.text
	_tele_header_text = %TeleHeader.text
	# RobotClient may already hold a list from the connect-time auto-request.
	_on_opmode_list(RobotClient.opmodes)


func _on_opmode_list(opmodes: Array) -> void:
	_rebuild_group_filter(opmodes)
	_rebuild_lists(opmodes)


func _selectable(opmodes: Array) -> Array:
	return opmodes.filter(func(opmode): return opmode.get("flavor", "") != SYSTEM)


func _group_of(opmode: Dictionary) -> String:
	var group: String = opmode.get("group", "")
	return "" if group == DEFAULT_GROUP else group


func _rebuild_group_filter(opmodes: Array) -> void:
	var groups := {}
	for opmode in _selectable(opmodes):
		var g := _group_of(opmode)
		if not g.is_empty():
			groups[g] = true
	var names := groups.keys()
	names.sort()
	if not names.has(_group_filter):
		_group_filter = ""
	%GroupFilter.clear()
	%GroupFilter.add_item("")
	for g in names:
		%GroupFilter.add_item(g)
	for i in %GroupFilter.item_count:
		if %GroupFilter.get_item_text(i) == _group_filter:
			%GroupFilter.select(i)
			break


func _rebuild_lists(opmodes: Array) -> void:
	for list in [%AutoList, %TeleList]:
		for child in list.get_children():
			child.queue_free()
	for opmode in _selectable(opmodes):
		if not _group_filter.is_empty() and _group_of(opmode) != _group_filter:
			continue
		var column: VBoxContainer = %AutoList if _is_auto(opmode) else %TeleList
		var op_name: String = opmode.get("name", "")
		var row := Button.new()
		row.text = op_name
		row.toggle_mode = true
		row.button_group = _group
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.button_pressed = op_name == RobotClient.selected_opmode
		row.pressed.connect(_on_opmode_selected.bind(op_name))
		column.add_child(row)
	_update_buttons()


func _on_group_filter_selected(index: int) -> void:
	_group_filter = %GroupFilter.get_item_text(index)
	_rebuild_lists(RobotClient.opmodes)


func _on_opmode_selected(opmode_name: String) -> void:
	RobotClient.select_opmode(opmode_name)
	_update_buttons()


func _update_buttons() -> void:
	var phase: int = RobotClient.phase
	%ActionButton.text = ACTION_LABELS.get(phase, "STOP")
	%ActionButton.add_theme_color_override(&"font_color", ACTION_COLORS.get(phase, Color.WHITE))
	%ActionButton.disabled = (
		phase == RobotClient.Phase.DISCONNECTED
		or (phase == RobotClient.Phase.IDLE and RobotClient.selected_opmode.is_empty())
	)


func _advance_phase() -> void:
	match RobotClient.phase:
		RobotClient.Phase.IDLE:
			RobotClient.init_opmode()
		RobotClient.Phase.INIT:
			RobotClient.start_opmode()
		RobotClient.Phase.RUNNING:
			RobotClient.stop_opmode()


## --- Grip routing (L4 = phase, L5 = group filter) ---


func grip_tap(grip: StringName) -> void:
	if grip == &"L4":
		if not %ActionButton.disabled:
			_advance_phase()
	else:
		_cycle_group(1)


func grip_hold_started(grip: StringName) -> void:
	if grip != &"L5" or radial == null or radial.is_open():
		return
	_group_radial_open = true
	radial.open(_group_slices(), get_viewport_rect().size / 2.0)


func grip_hold_ended(grip: StringName) -> void:
	if grip != &"L5" or not _group_radial_open:
		return
	_group_radial_open = false
	var picked: int = radial.finish()
	if picked >= 0:
		%GroupFilter.select(picked)
		_on_group_filter_selected(picked)


func _cycle_group(dir: int) -> void:
	var count: int = %GroupFilter.item_count
	if count == 0:
		return
	var next: int = (%GroupFilter.selected + dir + count) % count
	%GroupFilter.select(next)
	_on_group_filter_selected(next)


func _group_slices() -> Array:
	var slices := []
	for i in %GroupFilter.item_count:
		var label: String = %GroupFilter.get_item_text(i)
		var slice := {
			"label": UNFILTERED_LABEL if label.is_empty() else label,
			"disabled": i == %GroupFilter.selected,
		}
		slices.append(slice)
	return slices


func _is_auto(opmode: Dictionary) -> bool:
	return opmode.get("flavor", "") == AUTONOMOUS


func _on_phase_changed(phase: int, opmode_name: String) -> void:
	var telem_side := -1  # 0 = Auto column, 1 = Tele column, -1 = neither
	if phase == RobotClient.Phase.INIT:
		telem_side = 1 if _flavor_of(opmode_name) == AUTONOMOUS else 0
	_set_telemetry_column(0, telem_side == 0)
	_set_telemetry_column(1, telem_side == 1)
	_update_buttons()


func _set_telemetry_column(side: int, show_telem: bool) -> void:
	var scroll: Control = %AutoScroll if side == 0 else %TeleScroll
	var telem: Control = %AutoTelem if side == 0 else %TeleTelem
	var header: Label = %AutoHeader if side == 0 else %TeleHeader
	var original_text: String = _auto_header_text if side == 0 else _tele_header_text
	scroll.visible = not show_telem
	telem.visible = show_telem
	header.text = TELEMETRY_HEADER if show_telem else original_text


func _flavor_of(opmode_name: String) -> String:
	for opmode in RobotClient.opmodes:
		if opmode.get("name", "") == opmode_name:
			return opmode.get("flavor", "")
	return ""


func _on_telemetry(entries: Array) -> void:
	if RobotClient.phase != RobotClient.Phase.INIT:
		return
	_auto_telem_box.set_entries(entries)
	_tele_telem_box.set_entries(entries)
