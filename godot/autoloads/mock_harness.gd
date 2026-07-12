extends Node

## Must autoload BEFORE RobotClient so the env is set when it reads it.

const MOCK_PORT := 20884
const MOCK_LIMELIGHT_STREAM := "http://127.0.0.1:5800/"

var _fake_rc_pid := -1


func _ready() -> void:
	if OS.get_environment("DECK_DS_MOCK") != "1":
		return
	if not _spawn_fake_rc():
		return

	print("MockHarness: fake_rc on 127.0.0.1:%d" % MOCK_PORT)
	OS.set_environment("DECK_DS_PEER", "127.0.0.1")
	OS.set_environment("DECK_DS_PEER_PORT", str(MOCK_PORT))
	OS.set_environment("DECK_DS_BIND_PORT", "0")
	OS.set_environment("DECK_LIMELIGHT_STREAM", MOCK_LIMELIGHT_STREAM)


func _exit_tree() -> void:
	if _fake_rc_pid > 0:
		OS.kill(_fake_rc_pid)
		_fake_rc_pid = -1


func _spawn_fake_rc() -> bool:
	var candidates := [
		OS.get_executable_path().get_base_dir().path_join("fake_rc"),
		ProjectSettings.globalize_path("res://").path_join(
			"../external/robocol/target/debug/fake_rc"
		),
	]
	for exe: String in candidates:
		if FileAccess.file_exists(exe):
			_fake_rc_pid = OS.create_process(exe, [str(MOCK_PORT)])
			if _fake_rc_pid > 0:
				return true
			push_error("MockHarness: failed to launch fake_rc at %s" % exe)
			return false
	push_warning(
		(
			"MockHarness: DECK_DS_MOCK=1 but fake_rc was not found — the mock driver "
			+ "station needs a build with fake_rc bundled next to the executable "
			+ "(dev machine: `cargo build -p fake_rc` in external/robocol/). "
			+ "Connecting to a real RC instead."
		)
	)
	return false
