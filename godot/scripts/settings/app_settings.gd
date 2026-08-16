class_name AppSettings

const PATH := "user://settings.cfg"


static func get_value(section: String, key: String, fallback: Variant) -> Variant:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return fallback
	return cfg.get_value(section, key, fallback)


static func store(section: String, values: Dictionary) -> void:
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	for key: String in values:
		cfg.set_value(section, key, values[key])
	cfg.save(PATH)
