extends Control

## Manual-trigger updater over the install layout the launcher stub reads: the
## app lives in `<root>/bin/`, the stub sits at `<root>/`. Applying an update
## only ever writes `<root>/bin.new/`; the launcher swaps it into place on the
## next start, when nothing under `bin/` is open. The shortcut target never
## moves, and every failure path here leaves the live install untouched.

signal answered(accepted: bool)

const HEADERS := [
	"Accept: application/vnd.github+json",
	"User-Agent: deck-station-updater",
]

const STAGED_DIR := "bin.new"
const STAGING_DIR := ".staging"
const SUMS_ASSET := "SHA256SUMS"
const SIG_ASSET := "SHA256SUMS.sig"
const ASSET_PREFIX := "deck-station-"
const DOWNLOAD_DIR := "user://updates"
const DEV_VERSION := "dev"

var _http: HTTPRequest
var _message: AcceptDialog
var _confirm: ConfirmationDialog


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = ReleaseFeed.REQUEST_TIMEOUT
	_http.use_threads = true
	_http.set_tls_options(TLSOptions.client_unsafe())
	add_child(_http)

	_message = AcceptDialog.new()
	_message.title = "Update"
	add_child(_message)

	_confirm = ConfirmationDialog.new()
	_confirm.title = "Update"
	_confirm.confirmed.connect(func() -> void: answered.emit(true))
	_confirm.canceled.connect(func() -> void: answered.emit(false))
	add_child(_confirm)
	DialogCancel.install(_confirm)

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


func _unavailable_reason() -> String:
	if current_version() == DEV_VERSION:
		return "This is a source build.\n\nUpdate it with `git pull` and `cargo xtask export`."
	var root := InstallPaths.root()
	if root.is_empty():
		return (
			"This install isn't managed by the updater.\n\nDownload a release bundle from\n%s"
			% [ReleaseFeed.RELEASES_PAGE % ReleaseFeed.REPO]
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

	var response := await _fetch_url(ReleaseFeed.RELEASE_API % ReleaseFeed.REPO)
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
		elif asset_name == SIG_ASSET:
			found["sig_url"] = url
		elif asset_name.ends_with(suffix):
			found["name"] = asset_name
			found["url"] = url
			found["size"] = int(asset.get("size", 0))
			found["version"] = asset_name.trim_prefix(ASSET_PREFIX).trim_suffix(suffix)

	var missing := _missing_asset(found)
	return {"error": missing} if not missing.is_empty() else found


func _missing_asset(found: Dictionary) -> String:
	if not found.has("url"):
		return "The latest release has no bundle for %s." % OS.get_name()
	if not found.has("sums_url"):
		return "The latest release is missing %s." % SUMS_ASSET
	if not found.has("sig_url"):
		return "The latest release is missing %s." % SIG_ASSET
	return ""


func _fetch_url(url: String) -> Dictionary:
	var attempt := await _perform(url)
	if attempt.has("start_error"):
		return {"error": "Couldn't reach GitHub (error %d)." % attempt["start_error"]}
	return _response(attempt["result"])


func _perform(url: String) -> Dictionary:
	var err := _http.request(url, HEADERS)
	if err != OK:
		return {"start_error": err}
	return {"result": await _http.request_completed}


func _response(result: Array) -> Dictionary:
	if result[0] != HTTPRequest.RESULT_SUCCESS:
		return {"error": "Couldn't reach GitHub.\n\n%s" % ReleaseFeed.failure_reason(result[0])}
	if result[1] != 200:
		return {"error": "GitHub answered with HTTP %d." % result[1]}
	return {"body": result[3]}


## --- Download and apply ---


## Returns an empty string on success, otherwise a message for the user. Every
## failure path leaves the existing install untouched.
func _apply(release: Dictionary) -> String:
	var verified := await _trusted_hash(release)
	if verified.has("error"):
		return verified["error"]
	var expected: String = verified["hash"]

	DirAccess.make_dir_recursive_absolute(DOWNLOAD_DIR)
	var archive := ProjectSettings.globalize_path(DOWNLOAD_DIR.path_join(str(release["name"])))
	var downloaded := await _download(str(release["url"]), archive)
	if not downloaded.is_empty():
		return downloaded

	if FileAccess.get_sha256(archive) != expected:
		DirAccess.remove_absolute(archive)
		return "The download failed its checksum.\n\nNothing was installed."

	_message.dialog_text = "Installing…"
	return _install(InstallPaths.root(), archive)


## Unpacks beside the live install and leaves the new build staged as
## `bin.new/`; the launcher promotes it on the next start.
func _install(root: String, archive: String) -> String:
	var staging := root.path_join(STAGING_DIR)
	ReleaseArchive.remove_tree(staging)
	DirAccess.make_dir_recursive_absolute(staging)

	var extracted := ReleaseArchive.extract(archive, staging)
	DirAccess.remove_absolute(archive)
	if not extracted.is_empty():
		ReleaseArchive.remove_tree(staging)
		return extracted

	# Bundles carry a whole install; only the app directory is transplanted.
	var payload := staging.path_join(InstallPaths.BIN_DIR)
	if not DirAccess.dir_exists_absolute(payload):
		ReleaseArchive.remove_tree(staging)
		return "The bundle didn't contain a %s directory." % InstallPaths.BIN_DIR

	var target := root.path_join(STAGED_DIR)
	ReleaseArchive.remove_tree(target)
	var moved := DirAccess.rename_absolute(payload, target)
	ReleaseArchive.remove_tree(staging)
	if moved != OK:
		return "Couldn't stage the new version (error %d)." % moved
	return ""


func _download(url: String, destination: String) -> String:
	_http.download_file = destination
	set_process(true)
	var attempt := await _perform(url)
	set_process(false)
	_http.download_file = ""

	if attempt.has("start_error"):
		return "Couldn't start the download (error %d)." % attempt["start_error"]
	return _response(attempt["result"]).get("error", "")


func _trusted_hash(release: Dictionary) -> Dictionary:
	var sums := await _fetch_url(str(release["sums_url"]))
	if sums.has("error"):
		return sums
	var signature := await _fetch_url(str(release["sig_url"]))
	if signature.has("error"):
		return signature
	if not ReleaseVerify.signed(sums["body"], signature["body"]):
		return {
			"error":
			(
				"%s failed its signature check.\n\nNothing was downloaded.\n\n" % SUMS_ASSET
				+ (
					"Download a release bundle by hand from\n%s"
					% [ReleaseFeed.RELEASES_PAGE % ReleaseFeed.REPO]
				)
			)
		}

	var expected := ReleaseVerify.expected_hash(
		sums["body"].get_string_from_utf8(), str(release["name"])
	)
	if expected.is_empty():
		return {"error": "%s has no entry for this bundle." % SUMS_ASSET}
	return {"hash": expected}


## --- Dialogs ---


func _show(text: String) -> void:
	_message.dialog_text = text
	_message.popup_centered()


func _confirmed() -> bool:
	return await answered
