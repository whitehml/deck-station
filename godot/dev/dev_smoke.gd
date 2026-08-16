extends Node

const CRASH_OPMODE := "Crash Test"


func _ready() -> void:
	print("SMOKE backend: ", "fake_rc" if OS.get_environment("DECK_DS_MOCK") == "1" else "real RC")
	if RobotClient.phase == RobotClient.Phase.DISCONNECTED:
		await RobotClient.connection_changed
	if RobotClient.opmodes.is_empty():
		await RobotClient.opmode_list_changed
	print("SMOKE opmodes: ", RobotClient.opmodes)
	var opmode: String = RobotClient.opmodes[0].name

	RobotClient.select_opmode(opmode)
	RobotClient.init_opmode()
	while RobotClient.phase != RobotClient.Phase.INIT:
		await RobotClient.phase_changed
	var entries: Array = await RobotClient.telemetry_received
	print("SMOKE init telemetry: ", entries)

	RobotClient.start_opmode()
	while RobotClient.phase != RobotClient.Phase.RUNNING:
		await RobotClient.phase_changed
	await get_tree().create_timer(1.2).timeout
	var keys: Array = TelemetryLog.keys()
	print("SMOKE logged keys: ", keys)
	assert(not keys.is_empty())
	print("SMOKE run_elapsed: ", RobotClient.run_elapsed())
	assert(RobotClient.run_elapsed() > 0.5)

	await _smoke_field()

	RobotClient.stop_opmode()
	while RobotClient.phase != RobotClient.Phase.IDLE:
		await RobotClient.phase_changed

	await _smoke_opmode_crash()
	await _smoke_config_crud()
	await _smoke_battery_voltage()
	await _smoke_video()

	print("SMOKE OK")
	get_tree().quit()


## Connects a one-shot listener BEFORE calling `action`, so a signal that
## fires before the caller's next line runs is still captured. A plain
## `await some_signal` right after would start listening too late and hang,
## since GDScript signals aren't buffered.
func _trigger_and_capture(sig: Signal, action: Callable) -> Variant:
	# GDScript lambdas capture outer locals BY VALUE, not by reference — a
	# plain `var got := false` mutated from inside `cb` would only update
	# the closure's own copy. A Dictionary is a reference type, so this is
	# the standard workaround to get a result back out of a callback.
	var state := {"got": false, "result": null}
	var cb := func(v = null) -> void:
		state.result = v
		state.got = true
	sig.connect(cb, CONNECT_ONE_SHOT)
	action.call()
	while not state.got:
		await get_tree().process_frame
	return state.result


## fake_rc's "Crash Test" OpMode throws a couple of seconds into the run and
## the RC stops it immediately — the error has to outlive that teardown.
func _smoke_opmode_crash() -> void:
	if not RobotClient.opmodes.any(func(o: Dictionary) -> bool: return o.name == CRASH_OPMODE):
		print("SMOKE crash test skipped: no ", CRASH_OPMODE, " OpMode")
		return

	RobotClient.select_opmode(CRASH_OPMODE)
	RobotClient.init_opmode()
	while RobotClient.phase != RobotClient.Phase.INIT:
		await RobotClient.phase_changed
	RobotClient.start_opmode()
	while RobotClient.phase != RobotClient.Phase.RUNNING:
		await RobotClient.phase_changed

	var error: String = await RobotClient.opmode_error_changed
	print("SMOKE crash error: ", error)
	assert(error.contains("NullPointerException"))

	while RobotClient.phase != RobotClient.Phase.IDLE:
		await RobotClient.phase_changed
	await get_tree().create_timer(0.5).timeout
	assert(RobotClient.opmode_error == error)

	var telemetry: Array = await RobotClient.telemetry_received
	var text := RobotClient.format_telemetry(telemetry)
	print("SMOKE post-crash telemetry: ", text)
	assert(not text.contains("100.0|true"))

	RobotClient.select_opmode(RobotClient.opmodes[0].name)
	RobotClient.init_opmode()
	assert(RobotClient.opmode_error.is_empty())
	while RobotClient.phase != RobotClient.Phase.INIT:
		await RobotClient.phase_changed
	RobotClient.stop_opmode()
	while RobotClient.phase != RobotClient.Phase.IDLE:
		await RobotClient.phase_changed
	print("SMOKE crash error cleared on next init")


func _smoke_config_crud() -> void:
	if RobotClient.configurations.is_empty():
		await _trigger_and_capture(
			RobotClient.configurations_changed, RobotClient.request_configurations
		)
	print("SMOKE configs: ", RobotClient.configurations)
	assert(not RobotClient.configurations.is_empty())

	var target: Dictionary = RobotClient.configurations[0]
	var active: Dictionary = await _trigger_and_capture(
		RobotClient.active_config_changed,
		func() -> void: RobotClient.activate_configuration(target)
	)
	print("SMOKE active config: ", active)
	assert(active.get("name") == target.get("name"))

	var xml: String = await _trigger_and_capture(
		RobotClient.configuration_received,
		func() -> void: RobotClient.request_particular_configuration(target)
	)
	print("SMOKE config xml: ", xml)
	assert(not xml.is_empty())

	# Neither the protocol nor the reference DS auto-pushes a fresh configs
	# list after save/delete — re-request explicitly, same as a real config
	# editor UI would after a successful write.
	var new_meta := {
		"isDirty": true, "location": RobotClient.LOCATION_LOCAL, "name": "smoke_test_config"
	}
	await _trigger_and_capture(
		RobotClient.configurations_changed,
		func() -> void:
			RobotClient.save_configuration(new_meta, "<Robot/>")
			RobotClient.request_configurations()
	)
	assert(
		RobotClient.configurations.any(
			func(c: Dictionary) -> bool: return c.get("name") == "smoke_test_config"
		)
	)

	var matches := RobotClient.configurations.filter(
		func(c: Dictionary) -> bool: return c.get("name") == "smoke_test_config"
	)
	var saved: Dictionary = matches[0]
	await _trigger_and_capture(
		RobotClient.configurations_changed,
		func() -> void:
			RobotClient.delete_configuration(saved)
			RobotClient.request_configurations()
	)
	assert(
		not RobotClient.configurations.any(
			func(c: Dictionary) -> bool: return c.get("name") == "smoke_test_config"
		)
	)
	print("SMOKE config CRUD OK")


func _smoke_field() -> void:
	var classes := FieldLog.class_names()
	print("SMOKE field classes: ", classes)
	assert(classes.has("Robot") and classes.has("Game Pieces"))

	var kinds := FieldLog.items().map(func(i: Dictionary) -> String: return i["kind"])
	print("SMOKE field kinds: ", kinds)
	for kind in FieldLog.KINDS:
		assert(kinds.has(kind))

	var multiple := FieldLog.items().filter(
		func(i: Dictionary) -> bool: return i["cls"] == "Game Pieces"
	)
	assert(multiple.size() > 1)

	var entries: Array = await RobotClient.telemetry_received
	assert(not RobotClient.format_telemetry(entries).contains(FieldLog.MARKER))
	print("SMOKE field lines hidden from telemetry text")


func _smoke_battery_voltage() -> void:
	var volts: float = await RobotClient.battery_voltage_changed
	print("SMOKE battery voltage: ", volts)
	assert(volts > 0.0)


func _smoke_video() -> void:
	var got: Array = await RobotClient.video_frame
	var source: String = got[0]
	var texture: Texture2D = got[1]
	var size := texture.get_size()
	print("SMOKE video frame: ", source, " ", size)
	assert(size.x > 0 and size.y > 0)
