extends Node

signal items_changed(items: Array)
signal classes_changed(names: Array)
signal toggles_changed
signal frame_changed
signal image_changed(index: int)

const MARKER := "#f"
const LONG_MARKER := "#field"
const KINDS := ["robot", "point", "zone", "vec"]
const HEADING_KINDS := ["robot", "point"]
const DEFAULT_ROBOT_SIZE := 18.0
const SETTINGS_PATH := "user://settings.cfg"
const CLASS_COLORS := [
	Color(0.35, 0.8, 1.0),
	Color(1.0, 0.6, 0.3),
	Color(0.5, 0.9, 0.5),
	Color(1.0, 0.5, 0.7),
	Color(0.8, 0.7, 1.0),
	Color(1.0, 0.85, 0.4),
	Color(0.45, 0.95, 0.85),
	Color(0.95, 0.45, 0.45),
]

var frame_min := Vector2(0.0, 0.0)
var frame_max := Vector2(144.0, 144.0)
var robot_size := DEFAULT_ROBOT_SIZE
var image_index := 0

var _items: Array = []
var _classes: Dictionary = {}
var _order: Array = []


func _ready() -> void:
	_load_settings()
	RobotClient.telemetry_received.connect(_on_telemetry)


func items() -> Array:
	return _items


func class_names() -> Array:
	return _order.duplicate()


func class_color(cls: String) -> Color:
	return _classes.get(cls, {}).get("color", Color.WHITE)


func is_shown(cls: String) -> bool:
	return _classes.get(cls, {}).get("shown", true)


func shows_heading(cls: String) -> bool:
	return _classes.get(cls, {}).get("heading", true)


func has_heading(cls: String) -> bool:
	var kinds: Array = _classes.get(cls, {}).get("kinds", [])
	return kinds.any(func(kind: String) -> bool: return HEADING_KINDS.has(kind))


func set_shown(cls: String, shown: bool) -> void:
	_set_flag(cls, "shown", shown)


func set_heading(cls: String, shown: bool) -> void:
	_set_flag(cls, "heading", shown)


func set_all(flag: String, value: bool) -> void:
	for cls in _order:
		if flag == "heading" and not has_heading(cls):
			continue
		_classes[cls][flag] = value
	toggles_changed.emit()


func clear() -> void:
	_items.clear()
	_classes.clear()
	_order.clear()
	classes_changed.emit(class_names())
	items_changed.emit(_items)


func set_frame(corner_min: Vector2, corner_max: Vector2, size: float) -> void:
	frame_min = corner_min
	frame_max = corner_max
	robot_size = size
	_save_settings()
	frame_changed.emit()


func set_image_index(index: int) -> void:
	if index == image_index:
		return
	image_index = index
	_save_settings()
	image_changed.emit(index)


func _on_telemetry(entries: Array) -> void:
	var parsed: Array = []
	var added := false
	for e in entries:
		var line := _payload(e)
		if line.is_empty():
			continue
		var item := _parse(line)
		if item.is_empty():
			continue
		if _register(item["cls"], item["kind"]):
			added = true
		parsed.append(item)
	if parsed.is_empty() and _items.is_empty():
		return
	_items = parsed
	if added:
		classes_changed.emit(class_names())
	items_changed.emit(_items)


func _payload(entry: Dictionary) -> String:
	if entry.get("phase", "") == "SYSTEM":
		return ""
	var value: Variant = entry.get("value")
	if typeof(value) != TYPE_STRING or not String(value).is_empty():
		return ""
	var line := String(entry.get("key", "")).strip_edges()
	var marker := ""
	if line.begins_with(LONG_MARKER):
		marker = LONG_MARKER
	elif line.begins_with(MARKER):
		marker = MARKER
	else:
		return ""
	return line.substr(marker.length()).lstrip(" \t:")


func _parse(line: String) -> Dictionary:
	var tokens := _tokens(line)
	if tokens.size() < 2:
		return {}
	var kind := tokens[0].to_lower()
	if not KINDS.has(kind):
		return {}
	var attrs := {}
	for i in range(2, tokens.size()):
		var pair := tokens[i].split("=", true, 1)
		if pair.size() == 2:
			attrs[pair[0].to_lower()] = pair[1]
	var item := {
		"kind": kind,
		"cls": tokens[1],
		"color": _attr_color(attrs),
		"heading": _num(attrs, "h", NAN),
	}
	match kind:
		"robot":
			return _fill_robot(item, attrs)
		"point":
			return _fill_point(item, attrs)
		"zone":
			return _fill_zone(item, attrs)
		_:
			return _fill_vector(item, attrs)


func _fill_point(item: Dictionary, attrs: Dictionary) -> Dictionary:
	var origin: Variant = _point(attrs, "x", "y")
	if origin == null:
		return {}
	item["origin"] = origin
	return item


func _fill_robot(item: Dictionary, attrs: Dictionary) -> Dictionary:
	if _fill_point(item, attrs).is_empty():
		return {}
	var square := _num(attrs, "size", NAN)
	if is_nan(square):
		square = robot_size
	item["extent"] = Vector2(_num(attrs, "l", square), _num(attrs, "w", square))
	return item


func _fill_zone(item: Dictionary, attrs: Dictionary) -> Dictionary:
	var raw: String = attrs.get("pts", "")
	var points := PackedVector2Array()
	for pair in raw.replace("|", ";").split(";", false):
		var xy := String(pair).split(",")
		if xy.size() != 2 or not _numeric(xy[0]) or not _numeric(xy[1]):
			return {}
		points.append(Vector2(float(xy[0]), float(xy[1])))
	if points.size() < 3:
		return {}
	item["points"] = points
	return item


func _fill_vector(item: Dictionary, attrs: Dictionary) -> Dictionary:
	if _fill_point(item, attrs).is_empty():
		return {}
	var delta: Variant = _point(attrs, "dx", "dy")
	if delta == null:
		var magnitude := _num(attrs, "mag", NAN)
		if is_nan(magnitude) or is_nan(item["heading"]):
			return {}
		delta = Vector2.RIGHT.rotated(deg_to_rad(item["heading"])) * magnitude
		item["heading"] = NAN
	item["delta"] = delta
	item["unit"] = attrs.get("unit", "")
	return item


func _tokens(line: String) -> PackedStringArray:
	var out := PackedStringArray()
	var current := ""
	var quoted := false
	for i in line.length():
		var c := line[i]
		if c == '"':
			quoted = not quoted
		elif not quoted and (c == " " or c == "\t"):
			if not current.is_empty():
				out.append(current)
				current = ""
		else:
			current += c
	if not current.is_empty():
		out.append(current)
	return out


func _numeric(text: String) -> bool:
	var s := text.strip_edges()
	return s.is_valid_float() or s.is_valid_int()


func _num(attrs: Dictionary, key: String, fallback: float) -> float:
	var raw: String = attrs.get(key, "")
	return float(raw) if _numeric(raw) else fallback


func _point(attrs: Dictionary, x_key: String, y_key: String) -> Variant:
	var x := _num(attrs, x_key, NAN)
	var y := _num(attrs, y_key, NAN)
	return null if is_nan(x) or is_nan(y) else Vector2(x, y)


func _attr_color(attrs: Dictionary) -> Variant:
	var raw: String = attrs.get("color", "")
	return Color.from_string(raw, Color.WHITE) if Color.html_is_valid(raw) else null


func _register(cls: String, kind: String) -> bool:
	if not _classes.has(cls):
		_classes[cls] = {
			"shown": true,
			"heading": true,
			"kinds": [kind],
			"color": CLASS_COLORS[_order.size() % CLASS_COLORS.size()],
		}
		_order.append(cls)
		return true
	var kinds: Array = _classes[cls]["kinds"]
	if kinds.has(kind):
		return false
	kinds.append(kind)
	return true


func _set_flag(cls: String, flag: String, value: bool) -> void:
	if not _classes.has(cls) or _classes[cls][flag] == value:
		return
	_classes[cls][flag] = value
	toggles_changed.emit()


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	frame_min = cfg.get_value("field", "corner_min", frame_min)
	frame_max = cfg.get_value("field", "corner_max", frame_max)
	robot_size = float(cfg.get_value("field", "robot_size", robot_size))
	image_index = int(cfg.get_value("field", "image", image_index))


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("field", "corner_min", frame_min)
	cfg.set_value("field", "corner_max", frame_max)
	cfg.set_value("field", "robot_size", robot_size)
	cfg.set_value("field", "image", image_index)
	cfg.save(SETTINGS_PATH)
