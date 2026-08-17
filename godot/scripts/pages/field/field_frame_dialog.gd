class_name FieldFrameDialog
extends ConfirmationDialog

const RANGE := 100000.0
const PREVIEW_SIZE := Vector2(260, 200)


class CornerPreview:
	extends Control

	const PAD := 34.0

	var corner_min := Vector2.ZERO
	var corner_max := Vector2.ONE

	func _ready() -> void:
		theme_changed.connect(queue_redraw)

	func _draw() -> void:
		var rect := FieldFrame.square(size, PAD)
		draw_rect(rect, get_theme_color(&"surface", ThemeTokens.FIELD_TYPE))
		draw_rect(rect, get_theme_color(&"border", ThemeTokens.FIELD_TYPE), false, 2.0)
		FieldFrame.draw_corners(
			self,
			rect,
			corner_min,
			corner_max,
			PAD,
			get_theme_color(&"label", ThemeTokens.FIELD_TYPE)
		)


var _min_x: FocusEdit
var _min_y: FocusEdit
var _max_x: FocusEdit
var _max_y: FocusEdit
var _robot: FocusEdit
var _preview: CornerPreview


func _ready() -> void:
	title = "Field Frame"
	ok_button_text = "Apply"
	_build()
	_wire_focus()
	DialogCancel.install(self)
	confirmed.connect(_apply)


func open() -> void:
	_set_value(_min_x, FieldLog.frame_min.x)
	_set_value(_min_y, FieldLog.frame_min.y)
	_set_value(_max_x, FieldLog.frame_max.x)
	_set_value(_max_y, FieldLog.frame_max.y)
	_set_value(_robot, FieldLog.robot_size)
	_refresh_preview()
	popup_centered()
	_min_x.call_deferred(&"grab_focus")


func _wire_focus() -> void:
	var min_row: Array[Control] = [_min_x, _min_y]
	var max_row: Array[Control] = [_max_x, _max_y]
	var x_column: Array[Control] = [_min_x, _max_x, _robot]
	var y_column: Array[Control] = [_min_y, _max_y]
	FocusWiring.row(min_row)
	FocusWiring.row(max_row)
	FocusWiring.column(x_column)
	FocusWiring.column(y_column)
	FocusWiring.point(_max_y, SIDE_BOTTOM, _robot)
	var ok := get_ok_button()
	FocusWiring.point(_robot, SIDE_BOTTOM, ok)
	for button: Button in [ok, get_cancel_button()]:
		FocusWiring.point(button, SIDE_TOP, _robot)


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


func _row(grid: GridContainer, label_text: String, axis: String) -> FocusEdit:
	var label := Label.new()
	label.text = label_text
	grid.add_child(label)
	return _cell(grid, axis)


func _cell(grid: GridContainer, axis: String) -> FocusEdit:
	var holder := HBoxContainer.new()
	holder.add_theme_constant_override(&"separation", 6)
	if not axis.is_empty():
		var tag := Label.new()
		tag.text = axis
		holder.add_child(tag)

	var edit := FocusEdit.new()
	edit.custom_minimum_size.x = 110
	edit.select_all_on_focus = true
	edit.text_changed.connect(func(_text: String) -> void: _refresh_preview())
	holder.add_child(edit)

	grid.add_child(holder)
	return edit


func _value(edit: FocusEdit) -> float:
	return clampf(float(edit.text), -RANGE, RANGE)


func _set_value(edit: FocusEdit, value: float) -> void:
	edit.text = String.num(value, 3)


func _note(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = PREVIEW_SIZE.x + 160
	return label


func _refresh_preview() -> void:
	_preview.corner_min = Vector2(_value(_min_x), _value(_min_y))
	_preview.corner_max = Vector2(_value(_max_x), _value(_max_y))
	_preview.queue_redraw()


func _apply() -> void:
	FieldLog.set_frame(
		Vector2(_value(_min_x), _value(_min_y)),
		Vector2(_value(_max_x), _value(_max_y)),
		maxf(_value(_robot), 0.1)
	)
