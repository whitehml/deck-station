class_name ScrollFade
extends Node

## Thin scroll bars that stay invisible until the pointer is over the area or
## the view is moving. Install it on any control that exposes
## scroll bars.

const WIDTH := 6
const FADE_S := 0.15
const LINGER_S := 1.0
const TRACK_ALPHA := 0.1
const GRABBER_ALPHA := 0.4
const GRABBER_HOT_ALPHA := 0.75

var _bar: ScrollBar
var _host: Control
var _linger := 0.0
var _value := 0.0


static func install(host: Control) -> void:
	for getter: StringName in [&"get_v_scroll_bar", &"get_h_scroll_bar"]:
		if not host.has_method(getter):
			continue
		var bar := host.call(getter) as ScrollBar
		if bar == null:
			continue
		var fade := ScrollFade.new()
		fade._bar = bar
		fade._host = host
		bar.add_child(fade)


func _ready() -> void:
	_value = _bar.value
	_bar.modulate.a = 0.0
	_host.theme_changed.connect(_restyle)
	_restyle()


func _restyle() -> void:
	if _bar is VScrollBar:
		_bar.custom_minimum_size.x = WIDTH
	else:
		_bar.custom_minimum_size.y = WIDTH
	var ink := _host.get_theme_color(&"font_color", &"Label")
	_bar.add_theme_stylebox_override(&"scroll", _box(ink, TRACK_ALPHA))
	_bar.add_theme_stylebox_override(&"scroll_focus", _box(ink, TRACK_ALPHA))
	_bar.add_theme_stylebox_override(&"grabber", _box(ink, GRABBER_ALPHA))
	for state: StringName in [&"grabber_highlight", &"grabber_pressed"]:
		_bar.add_theme_stylebox_override(state, _box(ink, GRABBER_HOT_ALPHA))


func _box(ink: Color, alpha: float) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(ink, alpha)
	box.set_corner_radius_all(WIDTH / 2)
	return box


func _process(delta: float) -> void:
	if not is_equal_approx(_bar.value, _value):
		_value = _bar.value
		_linger = LINGER_S
	else:
		_linger = maxf(_linger - delta, 0.0)
	var target := 1.0 if _linger > 0.0 or _hovered() else 0.0
	_bar.modulate.a = move_toward(_bar.modulate.a, target, delta / FADE_S)


func _hovered() -> bool:
	if not _host.is_visible_in_tree():
		return false
	return _host.get_global_rect().has_point(_host.get_global_mouse_position())
