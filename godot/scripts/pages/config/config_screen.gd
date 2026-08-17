extends HSplitContainer

const LIST_POLL_TRIES := 5
const LIST_POLL_INTERVAL := 0.4
const STATE_PATH := "user://config_state.cfg"

var _configs: Array = []
var _stale_key := ""
var _activated_key := ""
var _group := ButtonGroup.new()
var _selected_name := ""
var _pending_metas: Array[Dictionary] = []
var _ambiguity_prompted := false
var _ambiguity_candidates: Array[Dictionary] = []
var _ambiguous_keys: Array[String] = []
var _ambiguity_dialog: AcceptDialog
var _ambiguity_buttons: Array[Button] = []

@onready var _editor: Node = %Editor


func _ready() -> void:
	RobotClient.configurations_changed.connect(_on_configurations_changed)
	RobotClient.active_config_changed.connect(_on_active_config_changed)
	RobotClient.configuration_received.connect(_on_configuration_received)
	RobotClient.connection_changed.connect(_on_connection_changed)
	%NewButton.pressed.connect(_on_new)
	_editor.saved.connect(_on_editor_saved)
	_editor.activated.connect(_on_editor_activated)
	_editor.deleted.connect(_on_editor_deleted)

	_build_ambiguity_dialog()
	_load_state()
	_on_configurations_changed(RobotClient.configurations)
	_on_active_config_changed(RobotClient.active_configuration)


## --- Config list ---


func _on_configurations_changed(configs: Array) -> void:
	_configs = configs
	_refresh_list()
	_maybe_prompt_ambiguity()


func _on_active_config_changed(_config: Dictionary) -> void:
	_refresh_list()
	_maybe_prompt_ambiguity()


func _on_connection_changed(connected: bool) -> void:
	if not connected:
		return
	_ambiguity_prompted = false
	_ambiguous_keys.clear()
	RobotClient.request_active_config()


func _refresh_list() -> void:
	for child in %ConfigList.get_children():
		child.queue_free()
	for meta: Dictionary in _configs:
		var row := Button.new()
		row.text = _list_label(meta)
		row.toggle_mode = true
		row.button_group = _group
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.button_pressed = meta.get("name") == _selected_name
		row.pressed.connect(_on_config_selected.bind(meta))
		%ConfigList.add_child(row)
		var status := _row_status(meta)
		if status != &"":
			row.add_theme_color_override(
				"font_color", row.get_theme_color(status, ThemeTokens.STATUS_TYPE)
			)
		elif _is_read_only(meta):
			row.add_theme_color_override(
				"font_color", row.get_theme_color("font_disabled_color", "Button")
			)


func _list_label(meta: Dictionary) -> String:
	var label: String = meta.get("name", "")
	if _is_read_only(meta):
		label += "  (read-only)"
	if _is_active(meta):
		match _active_status(meta):
			&"warn":
				label += "  (active · out of date)"
			&"ok":
				label += "  (active)"
			_:
				label += "  (active · unverified)"
	elif _config_key(meta) in _ambiguous_keys:
		label += "  (may be running)"
	return label


func _active_status(meta: Dictionary) -> StringName:
	if not _is_active(meta):
		return &""
	var key := _config_key(meta)
	if key == _stale_key:
		return &"warn"
	return &"ok" if key == _activated_key else &""


func _row_status(meta: Dictionary) -> StringName:
	if _config_key(meta) in _ambiguous_keys:
		return &"warn"
	return _active_status(meta)


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
		_stale_key = _config_key(meta)
		if _activated_key == _stale_key:
			_activated_key = ""
		_save_state()
	_refresh_list()
	_poll_until_listed(_selected_name)


func _poll_until_listed(name: String) -> void:
	for _i in LIST_POLL_TRIES:
		RobotClient.request_configurations()
		await get_tree().create_timer(LIST_POLL_INTERVAL).timeout
		if _configs.any(func(c: Dictionary) -> bool: return c.get("name") == name):
			return


func _on_editor_activated(meta: Dictionary) -> void:
	_mark_activated(meta)


func _on_editor_deleted(meta: Dictionary) -> void:
	var key := _config_key(meta)
	if _stale_key == key:
		_stale_key = ""
	if _activated_key == key:
		_activated_key = ""
	_ambiguous_keys.erase(key)
	_save_state()
	if _selected_name == meta.get("name", ""):
		_selected_name = ""
	_pending_metas.clear()
	_refresh_list()
	_poll_until_unlisted(meta.get("name", ""))


func _poll_until_unlisted(name: String) -> void:
	for _i in LIST_POLL_TRIES:
		RobotClient.request_configurations()
		await get_tree().create_timer(LIST_POLL_INTERVAL).timeout
		if not _configs.any(func(c: Dictionary) -> bool: return c.get("name") == name):
			return


func _mark_activated(meta: Dictionary) -> void:
	_activated_key = _config_key(meta)
	if _stale_key == _activated_key:
		_stale_key = ""
	_ambiguous_keys.clear()
	_save_state()
	_refresh_list()


func _build_ambiguity_dialog() -> void:
	_ambiguity_dialog = AcceptDialog.new()
	_ambiguity_dialog.title = "Which config is running?"
	_ambiguity_dialog.ok_button_text = "Continue without activating"
	_ambiguity_dialog.custom_action.connect(_on_ambiguity_action)
	_ambiguity_dialog.confirmed.connect(_on_ambiguity_dismissed)
	_ambiguity_dialog.canceled.connect(_on_ambiguity_dismissed)
	add_child(_ambiguity_dialog)


func _maybe_prompt_ambiguity() -> void:
	if _ambiguity_prompted or _configs.is_empty():
		return
	var active: Dictionary = RobotClient.active_configuration
	if active.is_empty() or (_stale_key.is_empty() and _activated_key.is_empty()):
		return
	var active_key := _config_key(active)
	if active_key == _activated_key and _stale_key != active_key:
		return

	_ambiguity_candidates.clear()
	var active_meta := _listed_config(active_key)
	if not active_meta.is_empty():
		_ambiguity_candidates.append(active_meta)
	if not _activated_key.is_empty() and _activated_key != active_key:
		var previous := _listed_config(_activated_key)
		if not previous.is_empty():
			_ambiguity_candidates.append(previous)
	if _ambiguity_candidates.is_empty():
		return

	_ambiguity_prompted = true
	_ambiguity_dialog.dialog_text = _ambiguity_text(active_key)
	for button in _ambiguity_buttons:
		_ambiguity_dialog.remove_button(button)
		button.queue_free()
	_ambiguity_buttons.clear()
	for i in _ambiguity_candidates.size():
		_ambiguity_buttons.append(
			_ambiguity_dialog.add_button(
				'Activate "%s"' % _ambiguity_candidates[i].get("name", ""), false, str(i)
			)
		)
	_ambiguity_dialog.popup_centered()


func _ambiguity_text(active_key: String) -> String:
	var active_name: String = RobotClient.active_configuration.get("name", "")
	if _stale_key == active_key:
		return (
			(
				'"%s" was saved but never activated, so the robot may still be running the '
				+ "previous configuration. Activating restarts the robot."
			)
			% active_name
		)
	return (
		(
			'The robot reports "%s" as active, but this Driver Station last activated "%s". '
			+ "Activating restarts the robot and settles which one is running."
		)
		% [active_name, _key_name(_activated_key)]
	)


func _on_ambiguity_action(action: StringName) -> void:
	var idx := int(str(action))
	if idx < 0 or idx >= _ambiguity_candidates.size():
		return
	var meta: Dictionary = _ambiguity_candidates[idx]
	_ambiguity_dialog.hide()
	RobotClient.activate_configuration(meta)
	_mark_activated(meta)


func _on_ambiguity_dismissed() -> void:
	_ambiguous_keys.clear()
	for meta: Dictionary in _ambiguity_candidates:
		_ambiguous_keys.append(_config_key(meta))
	_refresh_list()


func _listed_config(key: String) -> Dictionary:
	for meta: Dictionary in _configs:
		if _config_key(meta) == key:
			return meta
	return {}


func _key_name(key: String) -> String:
	return key.substr(key.find("/") + 1)


func _is_active(meta: Dictionary) -> bool:
	return RobotClient.config_is_active(meta)


func _is_read_only(meta: Dictionary) -> bool:
	return RobotClient.location_is_read_only(str(meta.get("location", "")))


func _config_key(meta: Dictionary) -> String:
	return "%s/%s" % [meta.get("location", ""), meta.get("name", "")]


func _load_state() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(STATE_PATH) != OK:
		return
	_stale_key = str(cfg.get_value("active", "stale", ""))
	_activated_key = str(cfg.get_value("active", "activated", ""))


func _save_state() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("active", "stale", _stale_key)
	cfg.set_value("active", "activated", _activated_key)
	cfg.save(STATE_PATH)
