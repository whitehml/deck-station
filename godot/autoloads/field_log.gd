extends Node

signal items_changed(items: Array)
signal classes_changed(names: Array)
signal toggles_changed
signal frame_changed
signal image_changed(index: int)
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
var robot_size := FieldContract.DEFAULT_ROBOT_SIZE
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
	return kinds.any(func(kind: String) -> bool: return FieldContract.HEADING_KINDS.has(kind))


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
		var line := FieldContract.payload(e)
		if line.is_empty():
			continue
		var item := FieldContract.parse(line, robot_size)
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
