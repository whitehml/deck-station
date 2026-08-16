extends Node

signal connection_changed(connected: bool)
signal opmode_list_changed(opmodes: Array)
signal phase_changed(phase: int, opmode_name: String)
signal selected_opmode_changed(opmode_name: String)
signal telemetry_received(entries: Array)
signal opmode_error_changed(text: String)
signal system_telemetry_shown_changed(shown: bool)
signal active_config_changed(config: Dictionary)
signal configurations_changed(configs: Array)
signal configuration_received(xml: String)
signal scan_result_received(xml: String)
signal user_device_list_received(json: String)
signal lynx_modules_received(json: String)
signal battery_voltage_changed(volts: float)
signal video_frame(source: String, texture: Texture2D)
signal video_stream_ended(source: String)

enum Phase { DISCONNECTED, IDLE, INIT, RUNNING }

const TELEMETRY_HZ := 10.0
const GAMEPAD_HZ := 50.0

const LOCATION_RESOURCE := "RESOURCE"
const LOCATION_LOCAL := "LOCAL_STORAGE"

## Falls back to the Control Hub's own address (the Limelight's Ethernet-over-USB
## link is reachable there too) — same default peer Robocol itself tries first,
## see DEFAULT_PEER_ADDRS in robocol/src/lib.rs. DECK_LIMELIGHT_STREAM overrides
## this for any other topology (direct-to-PC via mDNS, RC phone AP, ...).
const DEFAULT_LIMELIGHT_STREAM := "http://192.168.43.1:5800/"

var phase: int = Phase.DISCONNECTED
var selected_opmode := ""
var opmodes: Array = []
var configurations: Array = []
var active_configuration: Dictionary = {}
var opmode_error := ""
var show_system_telemetry := true

var _reselect_after_stop := ""
var _bridge = null
var _gamepad_accum := 0.0
var _slot_active := {}


func _ready() -> void:
	GamepadBridge.slot_changed.connect(_on_slot_changed)

	if not ClassDB.class_exists("RobocolBridge"):
		push_error(
			"RobotClient: RobocolBridge extension not built — run `cargo build -p robocol_godot` in rust/"
		)
		return

	_assert_phase_constants_match()
	_bridge = ClassDB.instantiate("RobocolBridge")
	add_child(_bridge)
	_bridge.connection_changed.connect(_on_bridge_connection_changed)
	_bridge.opmode_list_changed.connect(_on_bridge_opmode_list)
	_bridge.phase_changed.connect(_on_bridge_phase_changed)
	_bridge.telemetry_received.connect(_on_bridge_telemetry)
	_bridge.stacktrace_received.connect(_on_bridge_stacktrace)
	_bridge.active_config_changed.connect(_on_bridge_active_config)
	_bridge.configurations_changed.connect(_on_bridge_configurations)
	_bridge.configuration_received.connect(_on_bridge_configuration)
	_bridge.scan_result_received.connect(scan_result_received.emit)
	_bridge.user_device_list_received.connect(user_device_list_received.emit)
	_bridge.lynx_modules_received.connect(lynx_modules_received.emit)
	_bridge.battery_voltage_changed.connect(battery_voltage_changed.emit)
	_bridge.video_frame.connect(video_frame.emit)
	_bridge.video_stream_ended.connect(video_stream_ended.emit)
	_bridge.client_error.connect(
		func(message: String) -> void: push_warning("RobocolBridge: " + message)
	)

	print("RobotClient: RobocolBridge backend")
	var peers := PackedStringArray()
	var peer_env := OS.get_environment("DECK_DS_PEER")
	if not peer_env.is_empty():
		peers.append(peer_env)
	var bind_env := OS.get_environment("DECK_DS_BIND_PORT")
	var peer_port_env := OS.get_environment("DECK_DS_PEER_PORT")
	_bridge.start_client(
		peers,
		-1 if bind_env.is_empty() else int(bind_env),
		-1 if peer_port_env.is_empty() else int(peer_port_env)
	)
	_setup_video_streams()


func _assert_phase_constants_match() -> void:
	for phase_name in Phase.keys():
		var rust_value: int = ClassDB.class_get_integer_constant(
			&"RobocolBridge", "PHASE_" + phase_name
		)
		assert(
			rust_value == Phase[phase_name],
			(
				"RobotClient.Phase.%s (%d) != RobocolBridge.PHASE_%s (%d)"
				% [phase_name, Phase[phase_name], phase_name, rust_value]
			)
		)


## The RC webcam needs no registration call — it rides the Robocol connection
## itself and arrives as "webcam" video_frame/video_stream_ended signals.
func _setup_video_streams() -> void:
	var limelight := OS.get_environment("DECK_LIMELIGHT_STREAM")
	if limelight.is_empty():
		limelight = DEFAULT_LIMELIGHT_STREAM
	_bridge.add_video_stream("limelight", limelight)


func select_opmode(opmode_name: String) -> void:
	if phase == Phase.IDLE:
		selected_opmode = opmode_name
		selected_opmode_changed.emit(opmode_name)
	_bridge.select_opmode(opmode_name)


func init_opmode() -> void:
	clear_opmode_error()
	_bridge.init_opmode()


func clear_opmode_error() -> void:
	if opmode_error.is_empty():
		return
	opmode_error = ""
	opmode_error_changed.emit("")


func start_opmode() -> void:
	_bridge.start_opmode()


func stop_opmode() -> void:
	_reselect_after_stop = selected_opmode if phase in [Phase.INIT, Phase.RUNNING] else ""
	_bridge.stop_opmode()


func run_elapsed() -> float:
	return _bridge.run_elapsed()


func nav_active() -> bool:
	return GripInput.ui_nav_active or phase in [Phase.IDLE, Phase.DISCONNECTED]


func set_show_system_telemetry(shown: bool) -> void:
	if shown == show_system_telemetry:
		return
	show_system_telemetry = shown
	system_telemetry_shown_changed.emit(shown)


## System entries lead, in yellow; opmode telemetry follows in its own order.
func format_telemetry(entries: Array) -> String:
	var system := PackedStringArray()
	var lines := PackedStringArray()
	for e in entries:
		if e.phase == "SYSTEM":
			if show_system_telemetry:
				system.append("[color=yellow]%s[/color]" % e.key)
			continue
		if str(e.key).strip_edges().begins_with(FieldLog.MARKER):
			continue
		lines.append(e.key if str(e.value).is_empty() else "%s: %s" % [e.key, e.value])
	return "\n".join(system + lines)


func request_active_config() -> void:
	_bridge.request_active_config()


func request_configurations() -> void:
	_bridge.request_configurations()


func request_particular_configuration(config: Dictionary) -> void:
	_bridge.request_particular_configuration(config)


func activate_configuration(config: Dictionary) -> void:
	_bridge.activate_configuration(config)


func delete_configuration(config: Dictionary) -> void:
	_bridge.delete_configuration(config)


func scan() -> void:
	_bridge.scan()


func request_user_device_types() -> void:
	_bridge.request_user_device_types()


func save_configuration(meta: Dictionary, xml: String) -> void:
	_bridge.save_configuration(JSON.stringify(meta), xml)


func config_is_active(meta: Dictionary) -> bool:
	return (
		not active_configuration.is_empty()
		and active_configuration.get("name") == meta.get("name")
		and active_configuration.get("location") == meta.get("location")
	)


func _process(delta: float) -> void:
	if _bridge == null or phase == Phase.DISCONNECTED:
		return
	_gamepad_accum += delta
	if _gamepad_accum < 1.0 / GAMEPAD_HZ:
		return
	_gamepad_accum = fmod(_gamepad_accum, 1.0 / GAMEPAD_HZ)

	for slot_n in GamepadBridge.SLOTS:
		var device = GamepadBridge.device_for_slot(slot_n)
		var unclaimed := GamepadBridge.is_unclaimed(device)
		if unclaimed and not _slot_active.get(slot_n, false):
			continue
		var use_neutral := unclaimed or nav_active()
		_bridge.send_gamepad(
			slot_n,
			GamepadBridge.neutral_state() if use_neutral else GamepadBridge.full_state(device)
		)
		_slot_active[slot_n] = not unclaimed


func _on_slot_changed(new_slot: int) -> void:
	if _bridge == null or phase == Phase.DISCONNECTED:
		return
	var vacated := 1 if new_slot == 2 else 2
	_bridge.send_gamepad(vacated, GamepadBridge.neutral_state())


func _on_bridge_connection_changed(connected: bool) -> void:
	connection_changed.emit(connected)


func _on_bridge_opmode_list(list: Array) -> void:
	opmodes = list
	opmode_list_changed.emit(list)


func _on_bridge_phase_changed(new_phase: int, opmode_name: String) -> void:
	phase = new_phase
	if new_phase == Phase.DISCONNECTED:
		_reselect_after_stop = ""
	if new_phase == Phase.IDLE and not _reselect_after_stop.is_empty():
		var target := _reselect_after_stop
		_reselect_after_stop = ""
		phase_changed.emit(new_phase, opmode_name)
		select_opmode(target)
		return
	phase_changed.emit(new_phase, opmode_name)


func _on_bridge_telemetry(entries: Array) -> void:
	telemetry_received.emit(entries)


func _on_bridge_stacktrace(text: String) -> void:
	opmode_error = text.strip_edges()
	opmode_error_changed.emit(opmode_error)


func _on_bridge_active_config(config: Dictionary) -> void:
	active_configuration = config
	active_config_changed.emit(config)


func _on_bridge_configurations(configs: Array) -> void:
	configurations = configs
	configurations_changed.emit(configs)


func _on_bridge_configuration(xml: String) -> void:
	configuration_received.emit(xml)
