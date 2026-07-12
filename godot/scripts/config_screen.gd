extends HSplitContainer

var _configs: Array = []
var _active_out_of_date := false
var _group := ButtonGroup.new()
var _selected_name := ""
var _pending_metas: Array[Dictionary] = []

@onready var _editor: Node = %Editor


func _ready() -> void:
	RobotClient.configurations_changed.connect(_on_configurations_changed)
	RobotClient.active_config_changed.connect(_on_active_config_changed)
	RobotClient.configuration_received.connect(_on_configuration_received)
	%NewButton.pressed.connect(_on_new)
	_editor.saved.connect(_on_editor_saved)
	_editor.activated.connect(_on_editor_activated)

	_on_configurations_changed(RobotClient.configurations)
	_on_active_config_changed(RobotClient.active_configuration)


## --- Config list ---


func _on_configurations_changed(configs: Array) -> void:
	_configs = configs
	_refresh_list()


func _on_active_config_changed(_config: Dictionary) -> void:
	_active_out_of_date = false
	_refresh_list()


func _refresh_list() -> void:
	for child in %ConfigList.get_children():
		child.queue_free()
	if not _configs.any(func(c: Dictionary) -> bool: return c.get("name") == _selected_name):
		_selected_name = ""
	for meta: Dictionary in _configs:
		var row := Button.new()
		row.text = _list_label(meta)
		row.toggle_mode = true
		row.button_group = _group
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if _is_active(meta):
			row.add_theme_color_override(
				"font_color", Color.ORANGE if _active_out_of_date else Color.GREEN_YELLOW
			)
		row.button_pressed = meta.get("name") == _selected_name
		row.pressed.connect(_on_config_selected.bind(meta))
		%ConfigList.add_child(row)


func _list_label(meta: Dictionary) -> String:
	var label: String = meta.get("name", "")
	if meta.get("location") == RobotClient.LOCATION_RESOURCE:
		label += "  (resource)"
	if _is_active(meta):
		label += "  (active · out of date)" if _active_out_of_date else "  (active)"
	return label


func _on_config_selected(meta: Dictionary) -> void:
	_selected_name = meta.get("name", "")
	_pending_metas.append(meta.duplicate())
	RobotClient.request_particular_configuration(meta)


func grip_tap(grip: StringName) -> void:
	if _configs.is_empty():
		return
	var dir := -1 if grip == &"L4" else 1
	var idx := _selected_index()
	if idx == -1:
		idx = 0 if dir > 0 else _configs.size() - 1
	else:
		idx = (idx + dir + _configs.size()) % _configs.size()
	_on_config_selected(_configs[idx])
	_refresh_list()


func _selected_index() -> int:
	for i in _configs.size():
		if _configs[i].get("name") == _selected_name:
			return i
	return -1


func _on_configuration_received(xml: String) -> void:
	if _pending_metas.is_empty():
		return
	var meta: Dictionary = _pending_metas.pop_front()
	_editor.load_config(RobotConfig.parse(xml), meta)


func _on_new() -> void:
	_selected_name = ""
	_editor.load_new(
		{
			"isDirty": true,
			"location": RobotClient.LOCATION_LOCAL,
			"name": "new_config",
			"resourceId": 0
		}
	)
	_refresh_list()


## --- Editor callbacks ---


func _on_editor_saved(meta: Dictionary, active_out_of_date: bool) -> void:
	_selected_name = meta.get("name", "")
	if active_out_of_date:
		_active_out_of_date = true
	RobotClient.request_configurations()
	_refresh_list()


func _on_editor_activated() -> void:
	_active_out_of_date = false
	_refresh_list()


func _is_active(meta: Dictionary) -> bool:
	return RobotClient.config_is_active(meta)
