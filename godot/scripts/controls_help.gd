extends AcceptDialog

## Read-only controls reference, opened from Settings -> Controls…. Two pages:
## the driver-station bindings, and a keyboard map of the gamepad emulation.

enum { ANY, DECK, DESKTOP }

const MIN_SIZE := Vector2i(900, 620)
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

## Braced text is the Deck's grip name for the same key — dropped off the Deck.
const DRIVER_STATION := [
	["F3 {R4} tap", "E-STOP", DECK],
	[["F3 tap", "Delete"], "E-STOP", DESKTOP],
	["F3 {R4} hold", "Send gamepad output to the UI instead of the robot.", ANY],
	["Space", "Freeze / unfreeze the telemetry graph.", ANY],
	["F1 / F2 {L4 / L5}", "Page-contextual — see the table below.", ANY],
	["F4 {R5} tap", "Swap gamepad slots.", DECK],
	["F4 {R5} hold", "Slot-swap radial: 1 left, 2 right.", DECK],
	["Trackpads", "Cursor; either pad clicks as left-click.", DECK],
	["Touchscreen", "Full interaction.", DECK],
]

const NAVIGATION := [
	["Sticks / D-pad", "Move focus.", ANY],
	["L2 / R2 triggers", "Step the page tabs left / right.", DECK],
	[["L2 / R2 triggers", "Keyboard Q / E"], "Step the page tabs left / right.", DESKTOP],
	["Gamepad A / X", "Confirm / cancel.", ANY],
	["Start + A / Start + B", "Claim robot slot 1 / 2 for that controller.", DESKTOP],
	["[ / ]", "Claim robot slot 1 / 2 for the keyboard.", DESKTOP],
]

const BY_PAGE := [
	[
		"Drive",
		"Step the left pane's source; hold for its radial.",
		"Same, for the right pane.",
		ANY
	],
	["Graphs", "Shrink the graph's time window.", "Grow the time window.", ANY],
	[
		"OpModes",
		"Advance the run phase (INIT → START → STOP).",
		"Cycle the group filter; hold for the group radial.",
		ANY
	],
	["Config", "Select the previous config.", "Select the next config.", ANY],
]


class KeyboardMap:
	extends Control

	## Scale-to-fit drawing of a 60%-plus-function-row keyboard, each cap tinted
	## by the gamepad control it stands in for.

	enum { PLAIN, LEFT_STICK, RIGHT_STICK, FACE, SHOULDER, SYSTEM, DPAD, STATION }

	const ROLE_COLORS := {
		PLAIN: Color(0.42, 0.44, 0.5),
		LEFT_STICK: Color(0.38, 0.66, 0.98),
		RIGHT_STICK: Color(0.42, 0.82, 0.58),
		FACE: Color(0.98, 0.74, 0.32),
		SHOULDER: Color(0.78, 0.52, 0.92),
		SYSTEM: Color(0.62, 0.64, 0.88),
		DPAD: Color(0.36, 0.82, 0.86),
		STATION: Color(0.94, 0.44, 0.44),
	}

	const LEGEND := [
		[LEFT_STICK, "Left stick"],
		[RIGHT_STICK, "Right stick"],
		[DPAD, "D-pad"],
		[FACE, "Face buttons"],
		[SHOULDER, "Bumpers / triggers"],
		[SYSTEM, "Stick clicks, Start / Back"],
		[STATION, "Driver station"],
	]

	const UNITS_WIDE := 18.5
	const UNITS_TALL := 6.0
	const CLUSTER_X := 15.5
	const GAP := 0.06

	const ROWS := [
		[
			["Esc", 1.0, PLAIN, ""],
			["F1", 1.0, STATION, "L4"],
			["F2", 1.0, STATION, "L5"],
			["F3", 1.0, STATION, "R4"],
			["F4", 1.0, STATION, "R5"],
			["F5", 1.0, PLAIN, ""],
			["F6", 1.0, PLAIN, ""],
			["F7", 1.0, PLAIN, ""],
			["F8", 1.0, PLAIN, ""],
			["F9", 1.0, PLAIN, ""],
			["F10", 1.0, PLAIN, ""],
			["F11", 1.0, PLAIN, ""],
			["F12", 1.0, PLAIN, ""],
		],
		[
			["`", 1.0, PLAIN, ""],
			["1", 1.0, SHOULDER, "L1"],
			["2", 1.0, SHOULDER, "R1"],
			["3", 1.0, SHOULDER, "L2"],
			["4", 1.0, SHOULDER, "R2"],
			["5", 1.0, PLAIN, ""],
			["6", 1.0, PLAIN, ""],
			["7", 1.0, PLAIN, ""],
			["8", 1.0, PLAIN, ""],
			["9", 1.0, PLAIN, ""],
			["0", 1.0, PLAIN, ""],
			["-", 1.0, PLAIN, ""],
			["=", 1.0, PLAIN, ""],
			["Bksp", 2.0, SYSTEM, "Back"],
		],
		[
			["Tab", 1.5, PLAIN, ""],
			["Q", 1.0, LEFT_STICK, "↖"],
			["W", 1.0, LEFT_STICK, "↑"],
			["E", 1.0, LEFT_STICK, "↗"],
			["R", 1.0, PLAIN, ""],
			["T", 1.0, FACE, "Y"],
			["Y", 1.0, PLAIN, ""],
			["U", 1.0, RIGHT_STICK, "↖"],
			["I", 1.0, RIGHT_STICK, "↑"],
			["O", 1.0, RIGHT_STICK, "↗"],
			["P", 1.0, PLAIN, ""],
			["[", 1.0, STATION, "Slot 1"],
			["]", 1.0, STATION, "Slot 2"],
			["\\", 1.5, PLAIN, ""],
		],
		[
			["Caps", 1.75, PLAIN, ""],
			["A", 1.0, LEFT_STICK, "←"],
			["S", 1.0, LEFT_STICK, "50%"],
			["D", 1.0, LEFT_STICK, "→"],
			["F", 1.0, FACE, "X"],
			["G", 1.0, FACE, "A"],
			["H", 1.0, FACE, "B"],
			["J", 1.0, RIGHT_STICK, "←"],
			["K", 1.0, RIGHT_STICK, "50%"],
			["L", 1.0, RIGHT_STICK, "→"],
			[";", 1.0, PLAIN, ""],
			["'", 1.0, PLAIN, ""],
			["Enter", 2.25, SYSTEM, "Start"],
		],
		[
			["Shift", 2.25, PLAIN, ""],
			["Z", 1.0, LEFT_STICK, "↙"],
			["X", 1.0, LEFT_STICK, "↓"],
			["C", 1.0, LEFT_STICK, "↘"],
			["V", 1.0, PLAIN, ""],
			["B", 1.0, PLAIN, ""],
			["N", 1.0, PLAIN, ""],
			["M", 1.0, RIGHT_STICK, "↙"],
			[",", 1.0, RIGHT_STICK, "↓"],
			[".", 1.0, RIGHT_STICK, "↘"],
			["/", 1.0, PLAIN, ""],
			["Shift", 2.75, PLAIN, ""],
		],
		[
			["Ctrl", 1.25, SYSTEM, "L3"],
			["Win", 1.25, PLAIN, ""],
			["Alt", 1.25, SYSTEM, "R3"],
			["Space", 6.25, STATION, "Freeze graphs"],
			["Alt", 1.25, SYSTEM, "R3"],
			["Win", 1.25, PLAIN, ""],
			["Menu", 1.25, PLAIN, ""],
			["Ctrl", 1.25, SYSTEM, "L3"],
		],
	]

	## [row, column-offset within the cluster, label, width, role, sub-label]
	const CLUSTER := [
		[1, 0.0, "Del", 1.0, STATION, "E-STOP"],
		[4, 1.0, "↑", 1.0, DPAD, ""],
		[5, 0.0, "←", 1.0, DPAD, ""],
		[5, 1.0, "↓", 1.0, DPAD, ""],
		[5, 2.0, "→", 1.0, DPAD, ""],
	]

	var _font: Font = ThemeDB.fallback_font

	func _ready() -> void:
		resized.connect(queue_redraw)

	func _draw() -> void:
		var unit := minf(size.x / UNITS_WIDE, size.y / UNITS_TALL)
		var origin := Vector2(
			(size.x - unit * UNITS_WIDE) * 0.5, (size.y - unit * UNITS_TALL) * 0.5
		)

		for row_index in ROWS.size():
			var x := 0.0
			for key: Array in ROWS[row_index]:
				_draw_key(origin, unit, x, row_index, key[1], key[0], key[2], key[3])
				x += key[1]

		for key: Array in CLUSTER:
			_draw_key(origin, unit, CLUSTER_X + key[1], key[0], key[3], key[2], key[4], key[5])

	func _draw_key(
		origin: Vector2,
		unit: float,
		units_x: float,
		row: int,
		units_w: float,
		label: String,
		role: int,
		sub: String
	) -> void:
		var color: Color = ROLE_COLORS[role]
		var rect := Rect2(
			origin + Vector2(units_x + GAP, row + GAP) * unit,
			Vector2(units_w - GAP * 2.0, 1.0 - GAP * 2.0) * unit
		)
		draw_rect(rect, color * Color(1.0, 1.0, 1.0, 0.16 if role == PLAIN else 0.3))
		draw_rect(
			rect, color.darkened(0.1 if role == PLAIN else 0.0), false, maxf(1.0, unit * 0.03)
		)

		var label_size := int(maxf(9.0, unit * (0.3 if sub.is_empty() else 0.26)))
		var label_y := rect.position.y + (rect.size.y * (0.62 if sub.is_empty() else 0.44))
		draw_string(
			_font,
			Vector2(rect.position.x, label_y),
			label,
			HORIZONTAL_ALIGNMENT_CENTER,
			rect.size.x,
			label_size,
			Color(0.94, 0.95, 0.97) if role != PLAIN else Color(0.72, 0.74, 0.78)
		)
		if not sub.is_empty():
			draw_string(
				_font,
				Vector2(rect.position.x, rect.position.y + rect.size.y * 0.86),
				sub,
				HORIZONTAL_ALIGNMENT_CENTER,
				rect.size.x,
				int(maxf(8.0, unit * 0.2)),
				color
			)


func _ready() -> void:
	title = "Controls"
	min_size = MIN_SIZE
	unresizable = false

	var tabs := TabContainer.new()
	tabs.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tabs.add_child(_driver_station_page())
	if not GamepadBridge.is_steam_deck():
		tabs.add_child(_keyboard_page())
	tabs.tabs_visible = tabs.get_tab_count() > 1
	add_child(tabs)


func _driver_station_page() -> Control:
	var page := _page("Driver Station")
	var box := _column(page)
	box.add_child(_section("Driver station", ["Input", "Action"], DRIVER_STATION))
	box.add_child(_section("Navigating the UI", ["Input", "Action"], NAVIGATION))
	box.add_child(_section("F1 / F2 by page", ["Page", "F1 {L4}", "F2 {L5}"], BY_PAGE))
	return page


func _section(title_text: String, headers: Array, rows: Array) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", ROW_SEPARATION)
	box.add_child(_heading(title_text))
	box.add_child(_table(headers, rows))
	return box


func _keyboard_page() -> Control:
	var margin := MarginContainer.new()
	margin.name = "Keyboard"
	for side in [&"margin_left", &"margin_right", &"margin_top", &"margin_bottom"]:
		margin.add_theme_constant_override(side, ROW_SEPARATION * 2)

	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", ROW_SEPARATION * 2)

	var map := KeyboardMap.new()
	map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map.custom_minimum_size = Vector2(0, 220)
	box.add_child(map)

	box.add_child(_legend())
	margin.add_child(box)
	return margin


func _legend() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", COLUMN_SEPARATION)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	for entry: Array in KeyboardMap.LEGEND:
		var item := HBoxContainer.new()
		item.add_theme_constant_override(&"separation", ROW_SEPARATION)

		var swatch := ColorRect.new()
		swatch.color = KeyboardMap.ROLE_COLORS[entry[0]]
		swatch.custom_minimum_size = Vector2(14, 14)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		item.add_child(swatch)

		var label := Label.new()
		label.text = str(entry[1])
		item.add_child(label)
		row.add_child(item)
	return row


func _page(page_name: String) -> Control:
	var scroll := ScrollContainer.new()
	scroll.name = page_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	return scroll


func _column(parent: Control) -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in [&"margin_left", &"margin_right", &"margin_top", &"margin_bottom"]:
		margin.add_theme_constant_override(side, ROW_SEPARATION * 2)
	parent.add_child(margin)

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override(&"separation", ROW_SEPARATION * 3)
	margin.add_child(box)
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
		if not _applies(row[-1]):
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


## An input cell is one chip, or an array of them when several inputs share an
## action — each gets its own chip, all on one row.
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


func _applies(host: int) -> bool:
	return host == ANY or (host == DECK) == GamepadBridge.is_steam_deck()


func _host_text(text: String) -> String:
	if GamepadBridge.is_steam_deck():
		return text.replace("{", "(").replace("}", ")")
	return RegEx.create_from_string(" ?\\{[^}]*\\}").sub(text, "", true)


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override(&"font_color", HEADING_COLOR)
	return label
