class_name FieldContract

const MARKER := "#f"
const LONG_MARKER := "#field"
const KINDS := ["robot", "point", "zone", "vec"]
const HEADING_KINDS := ["robot", "point"]
const DEFAULT_ROBOT_SIZE := 18.0
const ATTRIBUTES := {
	"robot": ["x", "y", "h", "size", "l", "w", "color"],
	"point": ["x", "y", "h", "color"],
	"zone": ["pts", "color"],
	"vec": ["x", "y", "dx", "dy", "mag", "h", "unit", "color"],
}
const REQUIRED := {
	"robot": ["x", "y"],
	"point": ["x", "y"],
	"zone": ["pts"],
	"vec": ["x", "y"],
}
const NUMERIC := ["x", "y", "h", "size", "l", "w", "dx", "dy", "mag"]


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


static func consumed(entry: Dictionary) -> bool:
	var line := payload(entry)
	return not line.is_empty() and not parse(line, DEFAULT_ROBOT_SIZE).is_empty()


static func parse(line: String, default_size: float) -> Dictionary:
	var tokens := _tokens(line)
	if tokens.size() < 2:
		return {}
	var kind := tokens[0].to_lower()
	if not KINDS.has(kind):
		return {}
	var parsed: Variant = _attrs(tokens, kind)
	if parsed == null:
		return {}
	var attrs: Dictionary = parsed
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


static func _attrs(tokens: PackedStringArray, kind: String) -> Variant:
	var allowed: Array = ATTRIBUTES[kind]
	var attrs := {}
	for i in range(2, tokens.size()):
		var pair := tokens[i].split("=", true, 1)
		if pair.size() != 2:
			return null
		var key := pair[0].to_lower()
		if not allowed.has(key) or attrs.has(key):
			return null
		if NUMERIC.has(key) and not _numeric(pair[1]):
			return null
		attrs[key] = pair[1]
	for key: String in REQUIRED[kind]:
		if not attrs.has(key):
			return null
	if attrs.has("color") and not Color.html_is_valid(attrs["color"]):
		return null
	return null if _conflicting(attrs, kind) else attrs


static func _conflicting(attrs: Dictionary, kind: String) -> bool:
	match kind:
		"robot":
			return attrs.has("size") and (attrs.has("l") or attrs.has("w"))
		"vec":
			if attrs.has("dx") != attrs.has("dy"):
				return true
			return attrs.has("dx") and (attrs.has("mag") or attrs.has("h"))
	return false


static func _fill_point(item: Dictionary, attrs: Dictionary) -> Dictionary:
	item["origin"] = Vector2(_num(attrs, "x", NAN), _num(attrs, "y", NAN))
	return item


static func _fill_robot(item: Dictionary, attrs: Dictionary, default_size: float) -> Dictionary:
	_fill_point(item, attrs)
	var square := _num(attrs, "size", default_size)
	item["extent"] = Vector2(_num(attrs, "l", square), _num(attrs, "w", square))
	return item


static func _fill_zone(item: Dictionary, attrs: Dictionary) -> Dictionary:
	var raw: String = attrs.get("pts", "")
	var points := PackedVector2Array()
	for pair in raw.replace("|", ";").split(";"):
		var xy := String(pair).split(",")
		if xy.size() != 2 or not _numeric(xy[0]) or not _numeric(xy[1]):
			return {}
		points.append(Vector2(float(xy[0]), float(xy[1])))
	if points.size() < 3:
		return {}
	item["points"] = points
	return item


static func _fill_vector(item: Dictionary, attrs: Dictionary) -> Dictionary:
	_fill_point(item, attrs)
	if attrs.has("dx"):
		item["delta"] = Vector2(_num(attrs, "dx", NAN), _num(attrs, "dy", NAN))
	else:
		if not attrs.has("mag") or not attrs.has("h"):
			return {}
		item["delta"] = Vector2.RIGHT.rotated(deg_to_rad(item["heading"])) * _num(attrs, "mag", NAN)
		item["heading"] = NAN
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
	if quoted:
		return PackedStringArray()
	if not current.is_empty():
		out.append(current)
	return out


static func _numeric(text: String) -> bool:
	var s := text.strip_edges()
	return s.is_valid_float() or s.is_valid_int()


static func _num(attrs: Dictionary, key: String, fallback: float) -> float:
	var raw: String = attrs.get(key, "")
	return float(raw) if _numeric(raw) else fallback


static func _attr_color(attrs: Dictionary) -> Variant:
	var raw: String = attrs.get("color", "")
	return Color.from_string(raw, Color.WHITE) if Color.html_is_valid(raw) else null
