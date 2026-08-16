extends HBoxContainer

enum Source { WEBCAM, LIMELIGHT, GRAPHS, FIELD, TELEMETRY }

const SOURCE_NAMES := ["Webcam", "Limelight", "Graphs", "Field", "Telemetry"]
const CAM_FEEDS := {Source.WEBCAM: "webcam", Source.LIMELIGHT: "limelight"}

var radial: Control

var sources: Array[int] = [Source.WEBCAM, Source.TELEMETRY]  # [left, right]

var _radial_slot := -1  # slot whose source radial is currently open
var _graph_keys := PackedStringArray()
var _graph_window := 10.0
var _telemetry_entries: Array = []
var _cam_textures := {}  # feed name -> Texture2D

var _cam: Array = []
var _graph: Array = []
var _field: Array = []
var _telem: Array = []
var _graph_view: Array = []
var _telem_box: Array = []
var _header: Array = []

@onready var _slots: Array[Control] = [%SlotA, %SlotB]


func _ready() -> void:
	for slot: Control in _slots:
		_cam.append(slot.get_node("Cam"))
		_graph.append(slot.get_node("Graph"))
		_field.append(slot.get_node("Field"))
		_telem.append(slot.get_node("Telem"))
		_graph_view.append(slot.get_node("Graph/Box/View"))
		_telem_box.append(slot.get_node("Telem/Box"))
		_header.append(slot.get_node("Header"))
	RobotClient.telemetry_received.connect(_on_telemetry)
	RobotClient.video_frame.connect(_on_frame)
	RobotClient.video_stream_ended.connect(_on_stream_ended)
	_refresh()


## --- Grip routing  ---


func _slot_for(grip: StringName) -> int:
	return 0 if grip == &"L4" else 1


func grip_tap(grip: StringName) -> void:
	var slot := _slot_for(grip)
	sources[slot] = (sources[slot] + 1) % SOURCE_NAMES.size()
	_refresh()


func grip_hold_started(grip: StringName) -> void:
	if radial == null or radial.is_open():
		return
	_radial_slot = _slot_for(grip)
	radial.open(_source_slices(_radial_slot), _slot_center(_radial_slot))


func grip_hold_ended(grip: StringName) -> void:
	var slot := _slot_for(grip)
	if _radial_slot != slot:
		return
	_radial_slot = -1
	var picked: int = radial.finish()
	if picked >= 0:
		sources[slot] = picked
		_refresh()


func set_graph_keys(keys: PackedStringArray) -> void:
	_graph_keys = keys
	_refresh()


func set_graph_window(seconds: float) -> void:
	_graph_window = seconds
	_refresh()


## --- Display ---


func _refresh() -> void:
	if not is_node_ready():
		return
	var fullscreen: bool = sources[0] == sources[1]
	for i in 2:
		_slots[i].visible = not fullscreen or i == 0
		if _slots[i].visible:
			_apply_source(i, sources[i])


func _apply_source(slot: int, source: int) -> void:
	var cam: TextureRect = _cam[slot]
	cam.visible = CAM_FEEDS.has(source)
	_graph[slot].visible = source == Source.GRAPHS
	_field[slot].visible = source == Source.FIELD
	_telem[slot].visible = source == Source.TELEMETRY

	var header: String = SOURCE_NAMES[source]
	if CAM_FEEDS.has(source):
		cam.flip_v = source == Source.WEBCAM
		cam.texture = _cam_textures.get(CAM_FEEDS[source])
		if cam.texture == null:
			header += " — no feed"
	elif source == Source.GRAPHS:
		var view: Control = _graph_view[slot]
		view.keys = _graph_keys
		view.window_seconds = _graph_window
	elif source == Source.TELEMETRY:
		_telem_box[slot].set_entries(_telemetry_entries)
	_header[slot].text = header


func _slot_center(slot: int) -> Vector2:
	var size := get_viewport_rect().size
	var half_w := size.x / 2.0
	return Vector2(half_w * slot + half_w / 2.0, size.y / 2.0)


func _source_slices(slot: int) -> Array:
	var slices := []
	for s in SOURCE_NAMES.size():
		slices.append({"label": SOURCE_NAMES[s], "disabled": s == sources[slot]})
	return slices


## --- Data feeds ---


func _on_telemetry(entries: Array) -> void:
	_telemetry_entries = entries
	for i in 2:
		if _slots[i].visible and sources[i] == Source.TELEMETRY:
			_telem_box[i].set_entries(entries)


func _on_frame(source_name: String, texture: Texture2D) -> void:
	_cam_textures[source_name] = texture
	_reapply_feed(source_name)


func _on_stream_ended(source_name: String) -> void:
	_cam_textures.erase(source_name)
	_reapply_feed(source_name)


func _reapply_feed(source_name: String) -> void:
	for i in 2:
		if _slots[i].visible and CAM_FEEDS.get(sources[i]) == source_name:
			_apply_source(i, sources[i])
