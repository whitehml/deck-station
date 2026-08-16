class_name FieldFrameDialog
extends ConfirmationDialog

const RANGE := 100000.0
const PREVIEW_SIZE := Vector2(260, 200)
const TEXT_COLOR := Color(0.6, 0.64, 0.72)


class CornerPreview:
	extends Control

	const PAD := 34.0
	const LABEL_SIZE := 12
	const BORDER := Color(0.31, 0.62, 1.0, 0.7)
	const FILL := Color(0.09, 0.11, 0.14)
	const TEXT := Color(0.6, 0.64, 0.72)

	var corner_min := Vector2.ZERO
	var corner_max := Vector2.ONE

	func _draw() -> void:
		var side := minf(size.x, size.y) - PAD * 2.0
		var rect := Rect2((size - Vector2(side, side)) * 0.5, Vector2(side, side))
		draw_rect(rect, FILL)
		draw_rect(rect, BORDER, false, 2.0)
		_corner(Vector2(corner_min.x, corner_max.y), rect.position + Vector2(0, -6), false)
		_corner(corner_max, Vector2(rect.end.x, rect.position.y - 6), true)
		_corner(corner_min, Vector2(rect.position.x, rect.end.y + 16), false)
		_corner(Vector2(corner_max.x, corner_min.y), Vector2(rect.end.x, rect.end.y + 16), true)

	func _corner(value: Vector2, at: Vector2, right: bool) -> void:
		var text := "%s, %s" % [_trim(value.x), _trim(value.y)]
		var font := ThemeDB.fallback_font
		if right:
			at.x -= font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE).x
		draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, TEXT)

	func _trim(value: float) -> String:
		return "%d" % int(value) if is_equal_approx(value, roundf(value)) else "%0.1f" % value


var _min_x: SpinBox
var _min_y: SpinBox
var _max_x: SpinBox
var _max_y: SpinBox
var _robot: SpinBox
var _preview: CornerPreview


func _ready() -> void:
	title = "Field Frame"
	ok_button_text = "Apply"
	_build()
	confirmed.connect(_apply)


func open() -> void:
	_min_x.value = FieldLog.frame_min.x
	_min_y.value = FieldLog.frame_min.y
	_max_x.value = FieldLog.frame_max.x
	_max_y.value = FieldLog.frame_max.y
	_robot.value = FieldLog.robot_size
	_refresh_preview()
	popup_centered()


func _build() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 12)
	add_child(box)

	box.add_child(_note("Give the coordinates your OpMode uses for two opposite field corners."))

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override(&"h_separation", 12)
	grid.add_theme_constant_override(&"v_separation", 8)
	_min_x = _row(grid, "Bottom-left corner", "x")
	_min_y = _cell(grid, "y")
	_max_x = _row(grid, "Top-right corner", "x")
	_max_y = _cell(grid, "y")
	_robot = _row(grid, "Default robot size", "")
	grid.add_child(Control.new())
	box.add_child(grid)

	_preview = CornerPreview.new()
	_preview.custom_minimum_size = PREVIEW_SIZE
	box.add_child(_preview)

	box.add_child(
		_note("A corner pair that decreases along an axis mirrors the field on that axis.")
	)


func _row(grid: GridContainer, label_text: String, axis: String) -> SpinBox:
	var label := Label.new()
	label.text = label_text
	grid.add_child(label)
	return _cell(grid, axis)


func _cell(grid: GridContainer, axis: String) -> SpinBox:
	var holder := HBoxContainer.new()
	holder.add_theme_constant_override(&"separation", 6)
	if not axis.is_empty():
		var tag := Label.new()
		tag.text = axis
		tag.add_theme_color_override(&"font_color", TEXT_COLOR)
		holder.add_child(tag)

	var spin := SpinBox.new()
	spin.min_value = -RANGE
	spin.max_value = RANGE
	spin.step = 0.1
	spin.custom_minimum_size.x = 110
	spin.value_changed.connect(func(_v: float) -> void: _refresh_preview())
	holder.add_child(spin)

	grid.add_child(holder)
	return spin


func _note(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = PREVIEW_SIZE.x + 160
	label.add_theme_color_override(&"font_color", TEXT_COLOR)
	return label


func _refresh_preview() -> void:
	_preview.corner_min = Vector2(_min_x.value, _min_y.value)
	_preview.corner_max = Vector2(_max_x.value, _max_y.value)
	_preview.queue_redraw()


func _apply() -> void:
	FieldLog.set_frame(
		Vector2(_min_x.value, _min_y.value),
		Vector2(_max_x.value, _max_y.value),
		maxf(_robot.value, 0.1)
	)
