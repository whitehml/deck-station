class_name FieldImages

const FIELDS := [
	{"name": "2025-26 DECODE", "path": "res://assets/fields/decode.webp"},
	{"name": "2024-25 INTO THE DEEP", "path": "res://assets/fields/into_the_deep.webp"},
	{"name": "Field (no game elements)", "path": "res://assets/fields/base.webp"},
]


static func count() -> int:
	return FIELDS.size()


static func display_name(index: int) -> String:
	return FIELDS[clampi(index, 0, FIELDS.size() - 1)]["name"]


static func texture(index: int) -> Texture2D:
	var path: String = FIELDS[clampi(index, 0, FIELDS.size() - 1)]["path"]
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D
