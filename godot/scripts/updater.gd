extends Control

## Manual-trigger updater over the install layout the launcher stub reads: the
## app lives in `<root>/bin/`, the stub sits at `<root>/`. Applying an update
## only ever writes `<root>/bin.new/`; the launcher swaps it into place on the
## next start, when nothing under `bin/` is open. The shortcut target never
## moves, and every failure path here leaves the live install untouched.

signal answered(accepted: bool)

const REPO := "whitehml/deck-station"
const RELEASE_API := "https://api.github.com/repos/%s/releases/tags/latest"
const RELEASES_PAGE := "https://github.com/%s/releases"
const HEADERS := [
	"Accept: application/vnd.github+json",
	"User-Agent: deck-station-updater",
]

const BIN_DIR := "bin"
const STAGED_DIR := "bin.new"
const STAGING_DIR := ".staging"
const SUMS_ASSET := "SHA256SUMS"
const ASSET_PREFIX := "deck-station-"
const DOWNLOAD_DIR := "user://updates"
const REQUEST_TIMEOUT := 20.0
const DEV_VERSION := "dev"

var _http: HTTPRequest
var _message: AcceptDialog
var _confirm: ConfirmationDialog


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = REQUEST_TIMEOUT
	_http.use_threads = true
	add_child(_http)

	_message = AcceptDialog.new()
	_message.title = "Update"
	add_child(_message)

	_confirm = ConfirmationDialog.new()
	_confirm.title = "Update"
	_confirm.confirmed.connect(func() -> void: answered.emit(true))
	_confirm.canceled.connect(func() -> void: answered.emit(false))
	add_child(_confirm)

	set_process(false)


func _process(_delta: float) -> void:
	var total := _http.get_body_size()
	if total > 0:
		_message.dialog_text = "Downloading… %d%%" % (_http.get_downloaded_bytes() * 100 / total)


## --- Entry point ---


func run() -> void:
	if RobotClient.phase != RobotClient.Phase.DISCONNECTED:
		_show(
			(
				"Still connected to the robot.\n\n"
				+ "Disconnect and join a network with internet access to update."
			)
		)
		return

	var blocked := _unavailable_reason()
	if not blocked.is_empty():
		_show(blocked)
		return

	_show("Checking for updates…")
	var release := await _fetch_latest()
	if release.has("error"):
		_show(release["error"])
		return

	if release["version"] == current_version():
		_show("Already up to date (%s)." % current_version())
		return

	_confirm.dialog_text = (
		"Update to %s?\n\nCurrent: %s\nDownload: %.1f MB"
		% [release["version"], current_version(), release["size"] / 1048576.0]
	)
	_confirm.ok_button_text = "Update"
	_confirm.cancel_button_text = "Cancel"
	_message.hide()
	_confirm.popup_centered()
	if not await _confirmed():
		return

	_show("Starting download…")
	var failure := await _apply(release)
	if not failure.is_empty():
		_show(failure)
		return

	_confirm.dialog_text = (
		"Updated to %s.\n\nThe new version starts the next time you launch." % release["version"]
	)
	_confirm.ok_button_text = "OK"
	_confirm.cancel_button_text = "Quit"
	_message.hide()
	_confirm.popup_centered()
	if not await _confirmed():
		get_tree().quit()


func current_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", DEV_VERSION))


## --- Install layout ---


## The app runs out of `<root>/bin/`, but not always directly inside it — a
## macOS export nests it in an `.app` bundle — so walk up from the resolved
## binary to the `bin` directory, and confirm the stub sits beside it.
func install_root() -> String:
	var dir := OS.get_executable_path().get_base_dir()
	while not dir.is_empty():
		if dir.get_file() == BIN_DIR:
			var root := dir.get_base_dir()
			return root if FileAccess.file_exists(root.path_join(_launcher_name())) else ""
		var parent := dir.get_base_dir()
		if parent == dir:
			break
		dir = parent
	return ""


func _launcher_name() -> String:
	return "deck-station.exe" if OS.get_name() == "Windows" else "deck-station.x86_64"


func _unavailable_reason() -> String:
	if current_version() == DEV_VERSION:
		return "This is a source build.\n\nUpdate it with `git pull` and `cargo xtask export`."
	var root := install_root()
	if root.is_empty():
		return (
			"This install isn't managed by the updater.\n\nDownload a release bundle from\n%s"
			% [RELEASES_PAGE % REPO]
		)
	if not _writable(root):
		return "The install directory isn't writable:\n\n%s" % root
	return ""


func _writable(root: String) -> bool:
	var probe := root.path_join(".write-probe")
	var file := FileAccess.open(probe, FileAccess.WRITE)
	if file == null:
		return false
	file.close()
	DirAccess.remove_absolute(probe)
	return true


func _asset_suffix() -> String:
	match OS.get_name():
		"Windows":
			return "-windows-x86_64-unsigned.zip"
		"Linux":
			return "-linux-x86_64.tar.gz"
	return ""


## --- Release feed ---


func _fetch_latest() -> Dictionary:
	var suffix := _asset_suffix()
	if suffix.is_empty():
		return {"error": "No release bundle is published for %s." % OS.get_name()}

	var response := await _fetch_url(RELEASE_API % REPO)
	if response.has("error"):
		return response

	var release = JSON.parse_string(response["body"].get_string_from_utf8())
	if typeof(release) != TYPE_DICTIONARY or not release.has("assets"):
		return {"error": "The release feed came back malformed."}

	var found := {}
	for asset in release["assets"]:
		var asset_name := str(asset.get("name", ""))
		var url := str(asset.get("browser_download_url", ""))
		if asset_name == SUMS_ASSET:
			found["sums_url"] = url
		elif asset_name.ends_with(suffix):
			found["name"] = asset_name
			found["url"] = url
			found["size"] = int(asset.get("size", 0))
			found["version"] = asset_name.trim_prefix(ASSET_PREFIX).trim_suffix(suffix)

	if not found.has("url"):
		return {"error": "The latest release has no bundle for %s." % OS.get_name()}
	if not found.has("sums_url"):
		return {"error": "The latest release is missing %s." % SUMS_ASSET}
	return found


func _fetch_url(url: String) -> Dictionary:
	var err := _http.request(url, HEADERS)
	if err != OK:
		return {"error": "Couldn't reach GitHub (error %d)." % err}
	var result: Array = await _http.request_completed
	return _response(result)


func _response(result: Array) -> Dictionary:
	if result[0] != HTTPRequest.RESULT_SUCCESS:
		return {"error": "Couldn't reach GitHub.\n\n%s" % _failure_reason(result[0])}
	if result[1] != 200:
		return {"error": "GitHub answered with HTTP %d." % result[1]}
	return {"body": result[3]}


func _failure_reason(code: int) -> String:
	var detail := ""
	match code:
		HTTPRequest.RESULT_CANT_RESOLVE:
			detail = "The address couldn't be resolved. Check DNS."
		HTTPRequest.RESULT_CANT_CONNECT, HTTPRequest.RESULT_CONNECTION_ERROR:
			detail = "The connection failed. Check that you're on a network with internet access."
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			detail = (
				"The TLS handshake failed. Something is intercepting HTTPS, "
				+ "or the system clock is wrong."
			)
		HTTPRequest.RESULT_TIMEOUT:
			detail = "The request timed out after %d seconds." % int(REQUEST_TIMEOUT)
		HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED:
			detail = "Too many redirects."
		HTTPRequest.RESULT_DOWNLOAD_FILE_CANT_OPEN, HTTPRequest.RESULT_DOWNLOAD_FILE_WRITE_ERROR:
			detail = "The download couldn't be written to disk."
		_:
			detail = "Check that you're on a network with internet access."
	return "%s\n\n(HTTPRequest result %d)" % [detail, code]


## --- Download and apply ---


## Returns an empty string on success, otherwise a message for the user. Every
## failure path leaves the existing install untouched.
func _apply(release: Dictionary) -> String:
	var sums := await _fetch_url(str(release["sums_url"]))
	if sums.has("error"):
		return sums["error"]
	var expected := _expected_hash(sums["body"].get_string_from_utf8(), str(release["name"]))
	if expected.is_empty():
		return "%s has no entry for this bundle." % SUMS_ASSET

	DirAccess.make_dir_recursive_absolute(DOWNLOAD_DIR)
	var archive := ProjectSettings.globalize_path(DOWNLOAD_DIR.path_join(str(release["name"])))
	var downloaded := await _download(str(release["url"]), archive)
	if not downloaded.is_empty():
		return downloaded

	if FileAccess.get_sha256(archive) != expected:
		DirAccess.remove_absolute(archive)
		return "The download failed its checksum.\n\nNothing was installed."

	_message.dialog_text = "Installing…"
	return _install(install_root(), archive)


## Unpacks beside the live install and leaves the new build staged as
## `bin.new/`; the launcher promotes it on the next start.
func _install(root: String, archive: String) -> String:
	var staging := root.path_join(STAGING_DIR)
	_remove_tree(staging)
	DirAccess.make_dir_recursive_absolute(staging)

	var extracted := _extract(archive, staging)
	DirAccess.remove_absolute(archive)
	if not extracted.is_empty():
		_remove_tree(staging)
		return extracted

	# Bundles carry a whole install; only the app directory is transplanted.
	var payload := staging.path_join(BIN_DIR)
	if not DirAccess.dir_exists_absolute(payload):
		_remove_tree(staging)
		return "The bundle didn't contain a %s directory." % BIN_DIR

	var target := root.path_join(STAGED_DIR)
	_remove_tree(target)
	var moved := DirAccess.rename_absolute(payload, target)
	_remove_tree(staging)
	if moved != OK:
		return "Couldn't stage the new version (error %d)." % moved
	return ""


func _download(url: String, destination: String) -> String:
	_http.download_file = destination
	var err := _http.request(url, HEADERS)
	if err != OK:
		_http.download_file = ""
		return "Couldn't start the download (error %d)." % err

	set_process(true)
	var result: Array = await _http.request_completed
	set_process(false)
	_http.download_file = ""

	var response := _response(result)
	return response.get("error", "")


func _expected_hash(sums: String, asset_name: String) -> String:
	for line in sums.split("\n", false):
		var parts := line.split(" ", false)
		if parts.size() >= 2 and parts[parts.size() - 1].get_file() == asset_name:
			return parts[0]
	return ""


## Godot reads zip natively but has no tar.gz; `tar` is present on every Linux
## and preserves the executable bit that ZIPReader would drop.
func _extract(archive: String, destination: String) -> String:
	if OS.get_name() == "Windows":
		return _extract_zip(archive, destination)

	var output: Array = []
	var code := OS.execute("tar", ["-xzf", archive, "-C", destination], output, true)
	if code != 0:
		return "Couldn't unpack the bundle.\n\n%s" % "\n".join(output)
	return ""


func _extract_zip(archive: String, destination: String) -> String:
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


func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for entry in DirAccess.get_directories_at(path):
		_remove_tree(path.path_join(entry))
	for entry in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(entry))
	DirAccess.remove_absolute(path)


## --- Dialogs ---


func _show(text: String) -> void:
	_message.dialog_text = text
	_message.popup_centered()


func _confirmed() -> bool:
	return await answered
