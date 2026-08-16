class_name ReleaseArchive


## Godot reads zip natively but has no tar.gz; `tar` is present on every Linux
## and preserves the executable bit that ZIPReader would drop.
static func extract(archive: String, destination: String) -> String:
	if OS.get_name() == "Windows":
		return extract_zip(archive, destination)

	var output: Array = []
	var code := OS.execute("tar", ["-xzf", archive, "-C", destination], output, true)
	if code != 0:
		return "Couldn't unpack the bundle.\n\n%s" % "\n".join(output)
	return ""


static func extract_zip(archive: String, destination: String) -> String:
	var zip := ZIPReader.new()
	if zip.open(archive) != OK:
		return "Couldn't open the downloaded bundle."

	for entry in zip.get_files():
		var path := destination.path_join(entry)
		if entry.ends_with("/"):
			DirAccess.make_dir_recursive_absolute(path)
			continue
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			zip.close()
			return "Couldn't write %s." % path
		file.store_buffer(zip.read_file(entry))
		file.close()

	zip.close()
	return ""


static func remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for entry in DirAccess.get_directories_at(path):
		remove_tree(path.path_join(entry))
	for entry in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(entry))
	DirAccess.remove_absolute(path)
