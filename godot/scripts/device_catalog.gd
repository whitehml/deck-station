class_name DeviceCatalog
extends RefCounted

const CUSTOM_TAG := "__custom__"


static func parse(json: String) -> Array:
	var entries: Array = []
	var seen := {}
	_collect(JSON.parse_string(json), entries, seen)
	entries.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool: return a.label.naturalnocasecmp_to(b.label) < 0
	)
	return entries


static func _collect(value: Variant, entries: Array, seen: Dictionary) -> void:
	if value is Array:
		for item in value:
			_collect(item, entries, seen)
	elif value is Dictionary and value.has("xmlTag"):
		var tag := str(value["xmlTag"])
		if tag.is_empty() or tag.begins_with("<") or seen.has(tag):
			return
		seen[tag] = true
		(
			entries
			. append(
				{
					"tag": tag,
					"label": str(value.get("name", tag)),
					"needs_bus": _category(str(value.get("deviceFlavor", ""))) == "i2c",
				}
			)
		)


static func _category(flavor: String) -> String:
	match flavor.to_upper():
		"MOTOR":
			return "motor"
		"SERVO", "CRSERVO", "CR_SERVO", "CONTINUOUS_ROTATION_SERVO":
			return "servo"
		"I2C":
			return "i2c"
		_:
			return "other"
