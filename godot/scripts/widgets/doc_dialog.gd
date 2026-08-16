class_name DocDialog
extends AcceptDialog

const ANY_HOST := 0
const MIN_SIZE := Vector2i(900, 620)
const SCREEN_MARGIN := 48
const SCROLLBAR_WIDTH := 20
const COLUMN_SEPARATION := 24
const ROW_SEPARATION := 8
const CELL_PADDING := 10
const FIRST_COLUMN_WIDTH := 210
const HEADING_COLOR := Color(0.55, 0.75, 1.0)
const INPUT_COLOR := Color(1.0, 0.85, 0.4)
const ACTION_COLOR := Color(0.86, 0.88, 0.92)
const MUTED_COLOR := Color(0.6, 0.64, 0.72)
const TABLE_COLOR := Color(0.145, 0.155, 0.18)
const HEADER_ROW_COLOR := Color(1.0, 1.0, 1.0, 0.06)
const ALT_ROW_COLOR := Color(1.0, 1.0, 1.0, 0.025)
const CHIP_COLOR := Color(1.0, 1.0, 1.0, 0.07)
const GRABBER_COLOR := Color(1.0, 1.0, 1.0, 0.24)
const GRABBER_HOVER_COLOR := Color(1.0, 1.0, 1.0, 0.38)


class ScrollPane:
	extends ScrollContainer

	const SPEED := 900.0

	func _ready() -> void:
		focus_mode = Control.FOCUS_ALL
		set_process(false)
		focus_entered.connect(func() -> void: set_process(true))
		focus_exited.connect(func() -> void: set_process(false))

	func _process(delta: float) -> void:
		var axis := Input.get_axis(&"ui_up", &"ui_down")
		if not is_zero_approx(axis):
			scroll_vertical += int(axis * SPEED * delta)

	func _gui_input(event: InputEvent) -> void:
		if event.is_action(&"ui_up") or event.is_action(&"ui_down"):
			accept_event()
		elif event.is_action_pressed(&"ui_page_up", true):
			scroll_vertical -= int(get_v_scroll_bar().page)
			accept_event()
		elif event.is_action_pressed(&"ui_page_down", true):
			scroll_vertical += int(get_v_scroll_bar().page)
			accept_event()


var _tabs: TabContainer


func _ready() -> void:
	unresizable = false

	_tabs = TabContainer.new()
	_tabs.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for page: Control in _pages():
		_tabs.add_child(page)
	_tabs.tabs_visible = _tabs.get_tab_count() > 1
	_tabs.tab_changed.connect(func(_tab: int) -> void: focus_page())
	add_child(_tabs)

	about_to_popup.connect(_fit_to_screen)
	visibility_changed.connect(_on_visibility_changed)
	get_tree().root.size_changed.connect(_fit_to_screen)
	_fit_to_screen()


func _pages() -> Array:
	return []


## Gives the visible page's scroll pane focus, so held ui_up / ui_down scroll it
## as soon as the dialog opens — including gamepad input routed to the UI.
func focus_page() -> void:
	var page := _tabs.get_current_tab_control()
	if page:
		page.grab_focus()


func _on_visibility_changed() -> void:
	if visible:
		focus_page()


func _fit_to_screen() -> void:
	var margin := Vector2i(SCREEN_MARGIN, SCREEN_MARGIN)
	var limit := get_tree().root.size - margin * 2
	min_size = MIN_SIZE.min(limit)
	if visible:
		size = size.min(limit)
		position = position.clamp(margin, (get_tree().root.size - size - margin).max(margin))


func _page(page_name: String, always_show_bar := true) -> Control:
	var scroll := ScrollPane.new()
	scroll.name = page_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = (
		ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
		if always_show_bar
		else ScrollContainer.SCROLL_MODE_AUTO
	)

	var bar := scroll.get_v_scroll_bar()
	bar.custom_minimum_size.x = SCROLLBAR_WIDTH
	bar.add_theme_stylebox_override(&"scroll", _flat(TABLE_COLOR, 7, 6))
	bar.add_theme_stylebox_override(&"grabber", _flat(GRABBER_COLOR, 7))
	bar.add_theme_stylebox_override(&"grabber_highlight", _flat(GRABBER_HOVER_COLOR, 7))
	bar.add_theme_stylebox_override(&"grabber_pressed", _flat(HEADING_COLOR, 7))
	return scroll


func _column(parent: Control) -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in [&"margin_left", &"margin_right", &"margin_top", &"margin_bottom"]:
		margin.add_theme_constant_override(side, ROW_SEPARATION * 2)
	parent.add_child(margin)

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override(&"separation", ROW_SEPARATION * 3)
	margin.add_child(box)
	return box


func _section(title_text: String, headers: Array, rows: Array) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", ROW_SEPARATION)
	box.add_child(_heading(title_text))
	box.add_child(_table(headers, rows))
	return box


func _table(headers: Array, rows: Array) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override(&"panel", _flat(TABLE_COLOR, 8))

	var grid := GridContainer.new()
	grid.columns = headers.size()
	grid.add_theme_constant_override(&"h_separation", 0)
	grid.add_theme_constant_override(&"v_separation", 0)
	for column in headers.size():
		grid.add_child(
			_cell(
				_label(_host_text(str(headers[column])), MUTED_COLOR, false),
				HEADER_ROW_COLOR,
				column
			)
		)

	var shown := 0
	for row: Array in rows:
		if not _applies(row[-1] if row.size() > headers.size() else ANY_HOST):
			continue
		var background := ALT_ROW_COLOR if shown % 2 == 1 else Color(0, 0, 0, 0)
		for column in headers.size():
			var content: Control
			if column == 0:
				content = _chips(row[column])
			else:
				content = _label(_host_text(str(row[column])), ACTION_COLOR)
			grid.add_child(_cell(content, background, column))
		shown += 1

	panel.add_child(grid)
	return panel


func _cell(content: Control, background: Color, column: int) -> PanelContainer:
	var cell := PanelContainer.new()
	cell.add_theme_stylebox_override(&"panel", _flat(background, 0, CELL_PADDING))
	if column == 0:
		cell.custom_minimum_size.x = FIRST_COLUMN_WIDTH
	else:
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.add_child(content)
	return cell


func _chips(inputs: Variant) -> Control:
	if inputs is not Array:
		return _chip(_host_text(str(inputs)))

	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", ROW_SEPARATION * 0.75)
	for input: String in inputs:
		row.add_child(_chip(_host_text(input)))
	return row


func _chip(text: String) -> Control:
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override(&"panel", _flat(CHIP_COLOR, 5, ROW_SEPARATION * 0.75, 3))
	chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.add_child(_label(text, INPUT_COLOR, false))
	return chip


func _label(text: String, color: Color, wrap := true) -> Label:
	var label := Label.new()
	label.text = text
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override(&"font_color", color)
	return label


func _paragraph(text: String) -> Control:
	return _label(_host_text(text), ACTION_COLOR)


func _code(lines: Array) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override(&"panel", _flat(TABLE_COLOR, 8, CELL_PADDING))
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 2)
	for line: String in lines:
		var label := _label(line, INPUT_COLOR if not line.begins_with("//") else MUTED_COLOR, false)
		label.clip_text = false
		box.add_child(label)
	panel.add_child(box)
	return panel


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override(&"font_color", HEADING_COLOR)
	return label


func _flat(color: Color, radius: int, padding_x := 0.0, padding_y := 0.0) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.corner_radius_top_left = radius
	box.corner_radius_top_right = radius
	box.corner_radius_bottom_left = radius
	box.corner_radius_bottom_right = radius
	box.content_margin_left = padding_x
	box.content_margin_right = padding_x
	box.content_margin_top = padding_y if padding_y > 0.0 else padding_x
	box.content_margin_bottom = padding_y if padding_y > 0.0 else padding_x
	return box


func _applies(_host: int) -> bool:
	return true


func _host_text(text: String) -> String:
	return text
