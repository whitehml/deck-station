class_name PortWheel
extends Control

## Port picker on the ViewCapture contract: focus alone leaves ui_up /
## ui_down to focus navigation, ui_accept opens the wheel and takes them
## over, ui_accept commits and ui_cancel restores the value it opened on.

signal value_changed(value: int)

const ROW_HEIGHT := 22.0
const EXPANDED_ROWS := 3
const TYPE_WINDOW_S := 0.8
const SPIN_DECAY := 14.0
const DRAG_STEP := 18.0
const MIN_TEXT_WIDTH := 24.0
const ARROW_WIDTH := 16.0
const ARROW_SIZE := 4.0
const VERT_PAD := 4.0
const CELL_LIT := 0.16
const CELL_DIM := 0.0

var _values: Array[int] = []
var _index := 0
var _spin_offset := 0.0
var _typed := ""
var _typed_at := 0.0
var _dragging := false
var _drag_accum := 0.0
var _overlay: Control = null
var _entry_value := 0


func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	set_process(false)
	focus_exited.connect(_hide_overlay)


func _exit_tree() -> void:
	_hide_overlay()


func setup(values: Array[int], current: int) -> void:
	_values = values.duplicate()
	_index = maxi(_values.find(current), 0)
	_apply_min_size()
	queue_redraw()


func value() -> int:
	return _values[_index] if _index < _values.size() else 0


func _apply_min_size() -> void:
	var font := get_theme_default_font()
	var font_size := get_theme_default_font_size()
	var widest := MIN_TEXT_WIDTH
	for v in _values:
		widest = maxf(
			widest, font.get_string_size(str(v), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		)
	var box := _box("normal")
	var padding := box.get_minimum_size().x if box != null else 8.0
	custom_minimum_size = Vector2(
		widest + ARROW_WIDTH + padding + 8.0, font.get_height(font_size) + VERT_PAD
	)


func _box(name: String) -> StyleBox:
	return get_theme_stylebox(name, "LineEdit")


func _show_overlay() -> void:
	if _overlay != null or _values.size() < 2:
		return
	_entry_value = value()
	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay.bind(_overlay))
	get_tree().root.add_child(_overlay)
	_place_overlay()
	set_process(true)
	queue_redraw()


func _hide_overlay() -> void:
	if is_instance_valid(_overlay):
		_overlay.hide()
		_overlay.queue_free()
	_overlay = null
	set_process(false)
	queue_redraw()


func _place_overlay() -> void:
	if not is_instance_valid(_overlay):
		_overlay = null
		set_process(false)
		return
	var height := ROW_HEIGHT * EXPANDED_ROWS
	var rect := get_global_rect()
	var pos := Vector2(rect.position.x, rect.get_center().y - height * 0.5)
	var bounds := get_viewport_rect()
	pos.y = clampf(pos.y, bounds.position.y, bounds.end.y - height)
	_overlay.position = pos
	_overlay.size = Vector2(rect.size.x, height)


func _gui_input(event: InputEvent) -> void:
	match ViewCapture.verdict(event, _overlay != null):
		ViewCapture.TOGGLE:
			if _overlay == null:
				_show_overlay()
			else:
				_hide_overlay()
			accept_event()
			return
		ViewCapture.RELEASE:
			_select(_entry_value)
			_hide_overlay()
			accept_event()
			return
	if event is InputEventMouseButton:
		_mouse_button(event)
		return
	if event is InputEventMouseMotion and _dragging:
		_drag_accum += event.relative.y
		while absf(_drag_accum) >= DRAG_STEP:
			var way := 1 if _drag_accum > 0.0 else -1
			_drag_accum -= DRAG_STEP * way
			_step(-way)
		accept_event()
		return
	if _overlay != null:
		_nav(event)


func _mouse_button(event: InputEventMouseButton) -> void:
	if not event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = false
		return
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			_step(1)
			accept_event()
		MOUSE_BUTTON_WHEEL_DOWN:
			_step(-1)
			accept_event()
		MOUSE_BUTTON_LEFT:
			grab_focus()
			if event.position.x >= size.x - ARROW_WIDTH:
				_step(1 if event.position.y < size.y * 0.5 else -1)
			else:
				_show_overlay()
				_dragging = true
				_drag_accum = 0.0
			accept_event()


## Only reached with the wheel open, so ui_up / ui_down belong to it whatever
## device they arrived from — d-pad and stick included, not just the keyboard.
func _nav(event: InputEvent) -> void:
	if event.is_action_pressed("ui_up", true):
		_step(1)
		accept_event()
		return
	if event.is_action_pressed("ui_down", true):
		_step(-1)
		accept_event()
		return
	if event is InputEventKey and event.pressed:
		var digit := _digit((event as InputEventKey).keycode)
		if digit >= 0:
			_type_digit(str(digit))
			accept_event()


func _digit(keycode: Key) -> int:
	if keycode >= KEY_0 and keycode <= KEY_9:
		return keycode - KEY_0
	if keycode >= KEY_KP_0 and keycode <= KEY_KP_9:
		return keycode - KEY_KP_0
	return -1


func _type_digit(digit: String) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _typed_at > TYPE_WINDOW_S:
		_typed = ""
	_typed_at = now
	if _select(int(_typed + digit)):
		_typed += digit
	elif _select(int(digit)):
		_typed = digit
	else:
		_typed = ""


func _select(target: int) -> bool:
	var idx := _values.find(target)
	if idx == -1:
		return false
	if idx != _index:
		_spin_offset += (idx - _index) * ROW_HEIGHT
		_index = idx
		value_changed.emit(value())
	_redraw()
	return true


func _step(dir: int) -> void:
	if _values.size() < 2:
		return
	_index = wrapi(_index + dir, 0, _values.size())
	_spin_offset += dir * ROW_HEIGHT
	value_changed.emit(value())
	_redraw()


func _redraw() -> void:
	queue_redraw()
	if is_instance_valid(_overlay):
		_overlay.queue_redraw()


func _process(delta: float) -> void:
	_place_overlay()
	if _overlay == null or is_zero_approx(_spin_offset):
		return
	_spin_offset = lerpf(_spin_offset, 0.0, minf(1.0, delta * SPIN_DECAY))
	if absf(_spin_offset) < 0.5:
		_spin_offset = 0.0
	_redraw()


func _draw() -> void:
	var box := _box("focus" if has_focus() else "normal")
	if box != null:
		draw_style_box(box, Rect2(Vector2.ZERO, size))
	if _values.is_empty():
		return

	var color := get_theme_color("font_color", "Label")
	var font := get_theme_default_font()
	var font_size := get_theme_default_font_size()
	var normal := _box("normal")
	var left := normal.get_margin(SIDE_LEFT) if normal != null else 4.0
	if _overlay == null:
		draw_string(
			font,
			Vector2(
				left, (size.y + font.get_height(font_size)) * 0.5 - font.get_descent(font_size)
			),
			str(value()),
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size,
			color
		)
	_draw_arrows(color)


func _draw_arrows(color: Color) -> void:
	var x := size.x - ARROW_WIDTH * 0.5
	var faded := Color(color, 0.75)
	for dir in [1, -1]:
		var y := size.y * (0.32 if dir > 0 else 0.68)
		var tip := Vector2(x, y - ARROW_SIZE * 0.5 * dir)
		draw_colored_polygon(
			[
				tip,
				Vector2(x - ARROW_SIZE, y + ARROW_SIZE * 0.5 * dir),
				Vector2(x + ARROW_SIZE, y + ARROW_SIZE * 0.5 * dir)
			],
			faded
		)


func _shade_cells(overlay: Control, rect: Rect2, center_y: float, color: Color) -> void:
	var left := rect.position.x + 1.0
	var right := rect.end.x - 1.0
	var top := center_y - ROW_HEIGHT * 0.5
	var bottom := center_y + ROW_HEIGHT * 0.5
	overlay.draw_rect(Rect2(left, top, right - left, ROW_HEIGHT), Color(color, CELL_LIT), true)
	_gradient_band(
		overlay, left, right, rect.position.y, top, Color(color, CELL_DIM), Color(color, CELL_LIT)
	)
	_gradient_band(
		overlay, left, right, bottom, rect.end.y, Color(color, CELL_LIT), Color(color, CELL_DIM)
	)


func _gradient_band(
	overlay: Control,
	left: float,
	right: float,
	top: float,
	bottom: float,
	at_top: Color,
	at_bottom: Color
) -> void:
	var points := PackedVector2Array(
		[
			Vector2(left, top),
			Vector2(right, top),
			Vector2(right, bottom),
			Vector2(left, bottom),
		]
	)
	overlay.draw_polygon(points, [at_top, at_top, at_bottom, at_bottom])


func _draw_overlay(overlay: Control) -> void:
	var panel := get_theme_stylebox("panel", "PopupPanel")
	if panel == null:
		panel = get_theme_stylebox("panel", "PanelContainer")
	var rect := Rect2(Vector2.ZERO, overlay.size)
	if panel != null:
		overlay.draw_style_box(panel, rect)

	var font := get_theme_default_font()
	var font_size := get_theme_default_font_size()
	var color := get_theme_color("font_color", "Label")
	var center_y := overlay.size.y * 0.5
	var reach := int(EXPANDED_ROWS / 2)

	_shade_cells(overlay, rect, center_y, color)
	overlay.draw_rect(rect, Color(color, 0.55), false, 1.0)

	var wraps := _values.size() >= EXPANDED_ROWS
	for offset in range(-reach, reach + 1):
		var idx := _index + offset
		if wraps:
			idx = wrapi(idx, 0, _values.size())
		elif idx < 0 or idx >= _values.size():
			continue
		var y := center_y + offset * ROW_HEIGHT + _spin_offset
		var distance: float = clampf(absf(y - center_y) / ROW_HEIGHT, 0.0, 1.5)
		var alpha: float = lerpf(1.0, 0.0, distance / 1.5)
		if alpha <= 0.01:
			continue
		var size_here := font_size + roundi(lerpf(2.0, 0.0, minf(distance, 1.0)))
		var text := str(_values[idx])
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_here).x
		overlay.draw_string(
			font,
			Vector2((overlay.size.x - width) * 0.5, y + size_here * 0.36),
			text,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			size_here,
			Color(color, alpha)
		)
