class_name FieldFrameDialog
extends ConfirmationDialog

const RANGE := 100000.0
const PREVIEW_SIZE := Vector2(260, 200)
const TEXT_COLOR := Color(0.6, 0.64, 0.72)


class CornerPreview:
	extends Control

	const PAD := 34.0
	const FILL := Color(0.09, 0.11, 0.14)
	const BORDER := Color(0.31, 0.62, 1.0, 0.7)

	var corner_min := Vector2.ZERO
	var corner_max := Vector2.ONE

	func _draw() -> void:
		var rect := FieldFrame.square(size, PAD)
		draw_rect(rect, FILL)
		draw_rect(rect, BORDER, false, 2.0)
		FieldFrame.draw_corners(self, rect, corner_min, corner_max, PAD)


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
