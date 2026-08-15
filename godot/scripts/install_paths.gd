class_name InstallPaths

const BIN_DIR := "bin"


static func root() -> String:
	var dir := OS.get_executable_path().get_base_dir()
	while not dir.is_empty():
		if dir.get_file() == BIN_DIR:
			var base := dir.get_base_dir()
			return base if FileAccess.file_exists(base.path_join(launcher_name())) else ""
		var parent := dir.get_base_dir()
		if parent == dir:
			break
		dir = parent
	return ""


static func launcher_name() -> String:
	return "deck-station.exe" if OS.get_name() == "Windows" else "deck-station.x86_64"
