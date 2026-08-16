class_name FieldFrame

const LABEL_SIZE := 12
const CORNER_COLOR := Color(0.6, 0.64, 0.72)


static func square(size: Vector2, pad: float) -> Rect2:
	var usable := size - Vector2(pad, pad) * 2.0
	var side := maxf(minf(usable.x, usable.y), 1.0)
	return Rect2((size - Vector2(side, side)) * 0.5, Vector2(side, side))


static func span(corner_min: Vector2, corner_max: Vector2) -> Vector2:
	var extent := corner_max - corner_min
	if is_zero_approx(extent.x) or is_zero_approx(extent.y):
		return Vector2.ONE
	return extent


static func to_screen(p: Vector2, rect: Rect2, corner_min: Vector2, extent: Vector2) -> Vector2:
	var u := (p.x - corner_min.x) / extent.x
	var v := (p.y - corner_min.y) / extent.y
	return Vector2(rect.position.x + u * rect.size.x, rect.end.y - v * rect.size.y)


static func trim(value: float) -> String:
	return "%d" % int(value) if is_equal_approx(value, roundf(value)) else "%0.1f" % value


static func draw_corners(
	canvas: CanvasItem, rect: Rect2, corner_min: Vector2, corner_max: Vector2, pad: float
) -> void:
	var lo := corner_min
	var hi := corner_max
	var above := pad * 0.25
	var below := pad * 0.6
	_label(canvas, Vector2(lo.x, hi.y), rect.position + Vector2(0, -above), false)
	_label(canvas, hi, Vector2(rect.end.x, rect.position.y - above), true)
	_label(canvas, lo, Vector2(rect.position.x, rect.end.y + below), false)
	_label(canvas, Vector2(hi.x, lo.y), Vector2(rect.end.x, rect.end.y + below), true)


static func _label(canvas: CanvasItem, value: Vector2, at: Vector2, right: bool) -> void:
	var text := "%s, %s" % [trim(value.x), trim(value.y)]
	var font := ThemeDB.fallback_font
	if right:
		at.x -= font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE).x
	canvas.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, CORNER_COLOR)
