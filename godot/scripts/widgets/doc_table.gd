class_name DocTable

const ANY_HOST := 0
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


static func table(headers: Array, rows: Array, host_text: Callable, applies: Callable) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override(&"panel", flat(TABLE_COLOR, 8))

	var grid := GridContainer.new()
	grid.columns = headers.size()
	grid.add_theme_constant_override(&"h_separation", 0)
	grid.add_theme_constant_override(&"v_separation", 0)
	for column in headers.size():
		grid.add_child(
			cell(
				label(host_text.call(str(headers[column])), MUTED_COLOR, false),
				HEADER_ROW_COLOR,
				column
			)
		)

	var shown := 0
	for row: Array in rows:
		if not applies.call(row[-1] if row.size() > headers.size() else ANY_HOST):
			continue
		var background := ALT_ROW_COLOR if shown % 2 == 1 else Color(0, 0, 0, 0)
		for column in headers.size():
			var content: Control
			if column == 0:
				content = chips(row[column], host_text)
			else:
				content = label(host_text.call(str(row[column])), ACTION_COLOR)
			grid.add_child(cell(content, background, column))
		shown += 1

	panel.add_child(grid)
	return panel


static func cell(content: Control, background: Color, column: int) -> PanelContainer:
	var cell := PanelContainer.new()
	cell.add_theme_stylebox_override(&"panel", flat(background, 0, CELL_PADDING))
	if column == 0:
		cell.custom_minimum_size.x = FIRST_COLUMN_WIDTH
	else:
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.add_child(content)
	return cell


static func chips(inputs: Variant, host_text: Callable) -> Control:
	if inputs is not Array:
		return chip(host_text.call(str(inputs)))

	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", ROW_SEPARATION * 0.75)
	for input: String in inputs:
		row.add_child(chip(host_text.call(input)))
	return row


static func chip(text: String) -> Control:
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override(&"panel", flat(CHIP_COLOR, 5, ROW_SEPARATION * 0.75, 3))
	chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.add_child(label(text, INPUT_COLOR, false))
	return chip


static func label(text: String, color: Color, wrap := true) -> Label:
	var label := Label.new()
	label.text = text
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override(&"font_color", color)
	return label


static func paragraph(text: String) -> Control:
	return label(text, ACTION_COLOR)


static func code(lines: Array) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override(&"panel", flat(TABLE_COLOR, 8, CELL_PADDING))
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 2)
	for line: String in lines:
		var label := label(line, INPUT_COLOR if not line.begins_with("//") else MUTED_COLOR, false)
		label.clip_text = false
		box.add_child(label)
	panel.add_child(box)
	return panel


static func heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override(&"font_color", HEADING_COLOR)
	return label


static func flat(color: Color, radius: int, padding_x := 0.0, padding_y := 0.0) -> StyleBoxFlat:
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
