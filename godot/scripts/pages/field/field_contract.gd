class_name FieldContract

const MARKER := "#f"
const LONG_MARKER := "#field"
const KINDS := ["robot", "point", "zone", "vec"]
const HEADING_KINDS := ["robot", "point"]
const DEFAULT_ROBOT_SIZE := 18.0


static func payload(entry: Dictionary) -> String:
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


static func parse(line: String, default_size: float) -> Dictionary:
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
			return _fill_robot(item, attrs, default_size)
		"point":
			return _fill_point(item, attrs)
		"zone":
			return _fill_zone(item, attrs)
		_:
			return _fill_vector(item, attrs)


static func _fill_point(item: Dictionary, attrs: Dictionary) -> Dictionary:
	var origin: Variant = _point(attrs, "x", "y")
	if origin == null:
		return {}
	item["origin"] = origin
	return item


static func _fill_robot(item: Dictionary, attrs: Dictionary, default_size: float) -> Dictionary:
	if _fill_point(item, attrs).is_empty():
		return {}
	var square := _num(attrs, "size", NAN)
	if is_nan(square):
		square = default_size
	item["extent"] = Vector2(_num(attrs, "l", square), _num(attrs, "w", square))
	return item


static func _fill_zone(item: Dictionary, attrs: Dictionary) -> Dictionary:
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


static func _fill_vector(item: Dictionary, attrs: Dictionary) -> Dictionary:
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


static func _tokens(line: String) -> PackedStringArray:
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


static func _numeric(text: String) -> bool:
	var s := text.strip_edges()
	return s.is_valid_float() or s.is_valid_int()


static func _num(attrs: Dictionary, key: String, fallback: float) -> float:
	var raw: String = attrs.get(key, "")
	return float(raw) if _numeric(raw) else fallback


static func _point(attrs: Dictionary, x_key: String, y_key: String) -> Variant:
	var x := _num(attrs, x_key, NAN)
	var y := _num(attrs, y_key, NAN)
	return null if is_nan(x) or is_nan(y) else Vector2(x, y)


static func _attr_color(attrs: Dictionary) -> Variant:
	var raw: String = attrs.get("color", "")
	return Color.from_string(raw, Color.WHITE) if Color.html_is_valid(raw) else null
