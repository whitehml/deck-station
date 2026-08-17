class_name FieldView
extends Control

const DRAW_ORDER := ["zone", "vec", "robot", "point"]
const CORNER_PAD := 30.0
const TILES := 6
const POINT_RADIUS := 4.0
const POINT_HEADING_PX := 16.0
const ARROW_HEAD_PX := 10.0
const HINT_SIZE := 16
const ZONE_FILL_ALPHA := 0.22

var _items: Array = []
var _rect := Rect2()
var _span := Vector2.ONE
var _texture: Texture2D


func _ready() -> void:
	FieldLog.items_changed.connect(_on_items_changed)
	FieldLog.toggles_changed.connect(queue_redraw)
	FieldLog.frame_changed.connect(queue_redraw)
	FieldLog.image_changed.connect(_on_image_changed)
	resized.connect(queue_redraw)
	theme_changed.connect(queue_redraw)
	_on_image_changed(FieldLog.image_index)
	_items = FieldLog.items()


func _on_items_changed(items: Array) -> void:
	if TelemetryLog.paused:
		return
	_items = items
	queue_redraw()


func _on_image_changed(index: int) -> void:
	_texture = FieldImages.texture(index)
	queue_redraw()


func _to_screen(p: Vector2) -> Vector2:
	return FieldFrame.to_screen(p, _rect, FieldLog.frame_min, _span)


func _to_screen_all(points: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in points:
		out.append(_to_screen(p))
	return out


func _draw() -> void:
	_rect = FieldFrame.square(size, CORNER_PAD)
	_span = FieldFrame.span(FieldLog.frame_min, FieldLog.frame_max)
	_draw_backdrop()
	FieldFrame.draw_corners(
		self, _rect, FieldLog.frame_min, FieldLog.frame_max, CORNER_PAD, _field_color(&"label")
	)
	if _items.is_empty():
		_draw_hint()
		return
	for kind in DRAW_ORDER:
		for item: Dictionary in _items:
			if item["kind"] == kind and FieldLog.is_shown(item["cls"]):
				_draw_item(item)


func _field_color(name: StringName) -> Color:
	return get_theme_color(name, ThemeTokens.FIELD_TYPE)


func _draw_backdrop() -> void:
	if _texture:
		draw_texture_rect(_texture, _rect, false)
	else:
		draw_rect(_rect, _field_color(&"surface"))
		var grid := _field_color(&"grid")
		var center := _field_color(&"grid_center")
		for i in range(1, TILES):
			var t := float(i) / TILES
			var color := center if i == TILES / 2 else grid
			var x := _rect.position.x + _rect.size.x * t
			var y := _rect.position.y + _rect.size.y * t
			draw_line(Vector2(x, _rect.position.y), Vector2(x, _rect.end.y), color)
			draw_line(Vector2(_rect.position.x, y), Vector2(_rect.end.x, y), color)
	draw_rect(_rect, _field_color(&"border"), false, 2.0)


func _draw_hint() -> void:
	draw_string(
		ThemeDB.fallback_font,
		_rect.position + Vector2(12, 24),
		"No field telemetry",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		HINT_SIZE,
		_field_color(&"label")
	)


func _draw_item(item: Dictionary) -> void:
	var color: Color = item["color"] if item["color"] != null else FieldLog.class_color(item["cls"])
	match item["kind"]:
		"robot":
			_draw_robot(item, color)
		"point":
			_draw_point(item, color)
		"zone":
			_draw_zone(item, color)
		"vec":
			_draw_vector(item, color)


func _draw_robot(item: Dictionary, color: Color) -> void:
	var heading: float = item["heading"]
	var angle := 0.0 if is_nan(heading) else deg_to_rad(heading)
	var extent: Vector2 = item["extent"] * 0.5
	var world := PackedVector2Array()
	for corner in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, -1), Vector2(-1, 1)]:
		world.append(item["origin"] + (corner * extent).rotated(angle))
	var screen := _to_screen_all(world)
	draw_colored_polygon(screen, Color(color, ZONE_FILL_ALPHA * 0.6))
	_draw_outline(screen, color, 2.0)
	if not is_nan(heading) and FieldLog.shows_heading(item["cls"]):
		var nose: Vector2 = item["origin"] + Vector2(extent.x, 0).rotated(angle)
		_draw_arrow(_to_screen(item["origin"]), _to_screen(nose), color)
	var box := Rect2(screen[0], Vector2.ZERO)
	for p in screen:
		box = box.expand(p)
	_draw_label(item["cls"], Vector2(box.get_center().x, box.position.y - 6.0), color)


func _draw_point(item: Dictionary, color: Color) -> void:
	var at := _to_screen(item["origin"])
	draw_circle(at, POINT_RADIUS, color)
	var heading: float = item["heading"]
	if is_nan(heading) or not FieldLog.shows_heading(item["cls"]):
		return
	var dir := Vector2.RIGHT.rotated(-deg_to_rad(heading))
	_draw_arrow(at, at + dir * POINT_HEADING_PX, color)


func _draw_zone(item: Dictionary, color: Color) -> void:
	var screen := _to_screen_all(item["points"])
	draw_colored_polygon(screen, Color(color, ZONE_FILL_ALPHA))
	_draw_outline(screen, color, 2.0)
	var centroid := Vector2.ZERO
	for p in screen:
		centroid += p
	_draw_label(item["cls"], centroid / screen.size(), color)


func _draw_vector(item: Dictionary, color: Color) -> void:
	var tail := _to_screen(item["origin"])
	var head := _to_screen(item["origin"] + item["delta"])
	_draw_arrow(tail, head, color)
	var magnitude: float = (item["delta"] as Vector2).length()
	var text := "%0.1f" % magnitude
	if not String(item["unit"]).is_empty():
		text += " " + String(item["unit"])
	var normal := (head - tail).orthogonal().normalized() * 10.0
	_draw_label(text, tail.lerp(head, 0.5) + normal, color)


func _draw_outline(points: PackedVector2Array, color: Color, width: float) -> void:
	var loop := points.duplicate()
	loop.append(points[0])
	draw_polyline(loop, color, width, true)


func _draw_arrow(from: Vector2, to: Vector2, color: Color) -> void:
	draw_line(from, to, color, 2.0, true)
	var back := (from - to).normalized()
	if back == Vector2.ZERO:
		return
	var wing := back.orthogonal() * ARROW_HEAD_PX * 0.45
	var base := to + back * ARROW_HEAD_PX
	draw_colored_polygon(PackedVector2Array([to, base + wing, base - wing]), color)


func _draw_label(text: String, at: Vector2, color: Color) -> void:
	var font := ThemeDB.fallback_font
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FieldFrame.LABEL_SIZE).x
	draw_string(
		font,
		at - Vector2(width * 0.5, 0),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		FieldFrame.LABEL_SIZE,
		color
	)
