class_name RadialMenu
extends Control

const RADIUS := 150.0
const CENTER_RADIUS := 40.0
const ARC_POINTS := 24
const DISABLED_LABEL_ALPHA := 0.4

var _slices: Array = []  # [{label: String, disabled: bool}]
var _center := Vector2.ZERO
var _offset := 0.0  # radians added to the default "slice 0 centered up"
var _cursor := Vector2.ZERO
var _saved_mouse := Vector2.ZERO
var _interactive := false
var _highlight := -1


func _ready() -> void:
	visible = false
	mouse_filter = MOUSE_FILTER_IGNORE
	set_process_input(false)


func is_open() -> bool:
	return _interactive


func open(slices: Array, center: Vector2, offset := 0.0) -> void:
	_slices = slices
	_center = center
	_offset = offset
	_cursor = Vector2.ZERO
	_interactive = true
	_highlight = -1
	visible = true
	set_process_input(true)
	_saved_mouse = get_viewport().get_mouse_position()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	queue_redraw()


func finish() -> int:
	if not _interactive:
		return -1
	_interactive = false
	set_process_input(false)
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Input.warp_mouse(_saved_mouse)
	return _picked_index()


func _input(event: InputEvent) -> void:
	if not _interactive:
		return
	if event is InputEventMouseMotion:
		_cursor = (_cursor + event.relative).limit_length(RADIUS)
		_highlight = _picked_index()
		queue_redraw()
		get_viewport().set_input_as_handled()


func _picked_index() -> int:
	if _cursor.length() < CENTER_RADIUS:
		return -1
	var step := TAU / _slices.size()
	# Slice 0 is centered on "up" (-PI/2) plus the configured offset.
	var angle := fposmod(_cursor.angle() + PI / 2.0 - _offset + step / 2.0, TAU)
	var idx := int(angle / step) % _slices.size()
	if _slices[idx].get("disabled", false):
		return -1
	return idx


func _slice_arc(i: int) -> Array:  # [from_angle, to_angle]
	var step := TAU / _slices.size()
	var from := -PI / 2.0 + _offset - step / 2.0 + i * step
	return [from, from + step]


func _draw() -> void:
	if _slices.is_empty():
		return
	var font := ThemeDB.fallback_font
	var label_color := _color(&"label")
	for i in _slices.size():
		var arc: Array = _slice_arc(i)
		var color := _color(&"slice")
		if _slices[i].get("disabled", false):
			color = _color(&"slice_disabled")
		if i == _highlight:
			color = _color(&"slice_highlight")
		var points := PackedVector2Array([_center])
		for p in range(ARC_POINTS + 1):
			var a: float = lerpf(arc[0], arc[1], float(p) / ARC_POINTS)
			points.append(_center + Vector2.from_angle(a) * RADIUS)
		draw_colored_polygon(points, color)
		var mid: float = (arc[0] + arc[1]) / 2.0
		var label: String = _slices[i].get("label", "")
		var text_color := label_color
		if _slices[i].get("disabled", false):
			text_color.a *= DISABLED_LABEL_ALPHA
		var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, 16)
		var pos := (
			_center
			+ Vector2.from_angle(mid) * (RADIUS * 0.65)
			+ Vector2(-text_size.x / 2.0, text_size.y / 4.0)
		)
		draw_string(font, pos, label, HORIZONTAL_ALIGNMENT_CENTER, -1, 16, text_color)
	draw_circle(_center, CENTER_RADIUS, _color(&"center"))
	draw_arc(_center, RADIUS, 0, TAU, ARC_POINTS * 4, _color(&"rim"), 2.0)
	draw_circle(_center + _cursor, 7.0, _color(&"cursor"))


func _color(name: StringName) -> Color:
	return get_theme_color(name, ThemeTokens.RADIAL_TYPE)
