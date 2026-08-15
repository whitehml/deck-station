extends Node

signal changed

const FILE_NAME := "device_filter.json"
const FALLBACK_DIR := "user://"

var _hidden := {}
var _path := ""


func _ready() -> void:
	_path = _resolve_path()
	if FileAccess.file_exists(_path):
		_hidden = _read()


func path() -> String:
	return _path


func is_hidden(tag: String) -> bool:
	return _hidden.has(tag)


func hidden_tags() -> Array:
	var tags := _hidden.keys()
	tags.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)
	return tags


func visible(catalog: Array) -> Array:
	return catalog.filter(func(entry: Dictionary) -> bool: return not _hidden.has(entry.tag))


func set_hidden_tags(tags: Array) -> void:
	_hidden = {}
	for tag: String in tags:
		_hidden[tag] = true
	_write(hidden_tags())
	changed.emit()


func _resolve_path() -> String:
	var root := InstallPaths.root()
	return root.path_join(FILE_NAME) if not root.is_empty() else FALLBACK_DIR + FILE_NAME


func _read() -> Dictionary:
	var tags := {}
	var text := FileAccess.get_file_as_string(_path)
	if text.is_empty():
		push_warning("Device filter: cannot read %s" % _path)
		return tags
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary and parsed.get("hidden") is Array):
		push_warning("Device filter: malformed %s" % _path)
		return tags
	for tag: Variant in parsed["hidden"]:
		tags[str(tag)] = true
	return tags


func _write(tags: Array) -> void:
	var file := FileAccess.open(_path, FileAccess.WRITE)
	if file == null:
		push_warning("Device filter: cannot write %s" % _path)
		return
	file.store_string(JSON.stringify({"hidden": tags}, "\t") + "\n")
