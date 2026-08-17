class_name ConfigEditor
extends VBoxContainer

signal saved(meta: Dictionary, active_out_of_date: bool)
signal activated(meta: Dictionary)
signal deleted(meta: Dictionary)

enum CustomDialogMode { RENAME, CUSTOM_TAG }

const CUSTOM_ID := 999999
const READ_ONLY_DIM := 0.55

const TAG_LYNX_USB_DEVICE := DeviceCatalog.TAG_LYNX_USB_DEVICE
const TAG_LYNX_MODULE := DeviceCatalog.TAG_LYNX_MODULE
const TAG_WEBCAM := DeviceCatalog.TAG_WEBCAM
const TAG_ETHERNET_DEVICE := DeviceCatalog.TAG_ETHERNET_DEVICE

const ADD_CAMERA_TOOLTIP := "Use Scan to find an attached camera; manual entry is for advanced use."

var _catalog: Array = []
var _flavors := {}
var _picker_entries: Array = []
var _config: RobotConfig = null  # working (edited) model
var _meta: Dictionary = {}  # meta of the loaded config
var _baseline_xml := ""  # serialized model as last loaded/saved
var _add_device_target: Dictionary = {}

var _saveas_dialog: ConfirmationDialog
var _saveas_edit: LineEdit
var _custom_dialog: ConfirmationDialog
var _custom_dialog_mode: CustomDialogMode = CustomDialogMode.RENAME
var _custom_edit: LineEdit
var _custom_hint: Label
var _activate_dialog: ConfirmationDialog
var _reactivate_dialog: ConfirmationDialog
var _delete_dialog: ConfirmationDialog
var _scan_dialog: ScanDialog
var _add_device_popup: PopupMenu


func _ready() -> void:
	RobotClient.user_device_list_received.connect(_on_device_list)
	RobotClient.scan_result_received.connect(
		func(json: String) -> void: _scan_dialog.show_result(json)
	)
	RobotClient.configurations_changed.connect(_on_configs_changed)
	RobotClient.connection_changed.connect(_on_connection_changed)
	DeviceFilter.changed.connect(_apply_device_filter)
	%ScanButton.pressed.connect(_on_scan)
	%SaveButton.pressed.connect(_on_save)
	%SaveAsButton.pressed.connect(_on_save_as)
	%ActivateButton.pressed.connect(_on_activate)
	%DeleteButton.pressed.connect(_on_delete)

	_build_dialogs()
	RobotClient.request_user_device_types()
	_refresh_editor()


## --- Host API ---


func load_config(config: RobotConfig, meta: Dictionary) -> void:
	_config = config
	_meta = meta.duplicate()
	_baseline_xml = config.to_xml()
	_refresh_editor()


func load_new(meta: Dictionary) -> void:
	_config = _seed_new_config()
	_meta = meta.duplicate()
	_baseline_xml = ""
	_refresh_editor()


func clear() -> void:
	_config = null
	_meta = {}
	_baseline_xml = ""
	_refresh_editor()


func _seed_new_config() -> RobotConfig:
	var config := RobotConfig.new_empty()
	var usb := RobotConfig.element(
		TAG_LYNX_USB_DEVICE,
		{"name": "Control Hub Portal", "serialNumber": "(embedded)", "parentModuleAddress": "173"}
	)
	usb.children.append(
		RobotConfig.element(TAG_LYNX_MODULE, {"name": "Control Hub", "port": "173"})
	)
	config.root.children.append(usb)
	return config


## --- Editor rendering ---


func _refresh_editor() -> void:
	for child in %EditorTree.get_children():
		child.queue_free()
	%EditorTitle.text = _editor_title()
	_update_action_buttons()
	%EditorTree.modulate = Color(1, 1, 1, READ_ONLY_DIM if _is_read_only() else 1.0)
	if _config == null:
		var hint := Label.new()
		hint.text = "Select a configuration on the left, or press New."
		%EditorTree.add_child(hint)
		return
	for node: Dictionary in _config.root.children:
		if node.tag == TAG_LYNX_USB_DEVICE:
			_build_usb_block(node)
		else:
			_build_peripheral_row(%EditorTree, node)
	var add_row := HBoxContainer.new()
	var add_webcam := EditorRows.text_button("+ Webcam", _add_peripheral.bind(TAG_WEBCAM))
	add_webcam.tooltip_text = ADD_CAMERA_TOOLTIP
	add_row.add_child(add_webcam)
	var add_ethernet := EditorRows.text_button(
		"+ Ethernet / Limelight", _add_peripheral.bind(TAG_ETHERNET_DEVICE)
	)
	add_ethernet.tooltip_text = ADD_CAMERA_TOOLTIP
	add_row.add_child(add_ethernet)
	%EditorTree.add_child(add_row)
	if _is_read_only():
		_lock_controls(%EditorTree)


func _lock_controls(node: Node) -> void:
	for child in node.get_children():
		if child is LineEdit:
			(child as LineEdit).editable = false
		elif child is BaseButton:
			(child as BaseButton).disabled = true
		elif child is PortWheel:
			child.focus_mode = Control.FOCUS_NONE
			child.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_lock_controls(child)


func _build_usb_block(usb: Dictionary) -> void:
	var header := Label.new()
	header.text = "▸ %s" % usb.attrs.get("name", "USB Device")
	%EditorTree.add_child(header)
	for module: Dictionary in usb.children:
		if module.tag == TAG_LYNX_MODULE:
			_build_module_block(usb, module)
	var add_hub := EditorRows.text_button("    + Add hub", _add_hub.bind(usb))
	%EditorTree.add_child(add_hub)


func _build_module_block(usb: Dictionary, module: Dictionary) -> void:
	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = (
		"    %s  (port %s)" % [module.attrs.get("name", "Hub"), module.attrs.get("port", "?")]
	)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(EditorRows.text_button("Rename", _rename_node.bind(module)))
	header.add_child(EditorRows.delete_button(_delete_child.bind(usb, module)))
	%EditorTree.add_child(header)
	for dev: Dictionary in module.children:
		_build_device_row(module, dev)
	%EditorTree.add_child(
		EditorRows.text_button("        + Add device", _open_add_device.bind(module))
	)


func _build_device_row(module: Dictionary, dev: Dictionary) -> void:
	var row := HBoxContainer.new()
	var kind := Label.new()
	kind.text = "        " + dev.tag
	kind.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(kind)
	row.add_child(EditorRows.attr_line_edit(dev, "name", _on_attr_text))
	row.add_child(EditorRows.port_label("port"))
	row.add_child(
		EditorRows.attr_options(
			dev, "port", DeviceCatalog.port_count(str(_flavors.get(dev.tag, ""))), _on_attr_option
		)
	)
	if dev.attrs.has("bus"):
		row.add_child(EditorRows.port_label("bus"))
		row.add_child(EditorRows.attr_options(dev, "bus", DeviceCatalog.BUS_COUNT, _on_attr_option))
	row.add_child(EditorRows.delete_button(_delete_child.bind(module, dev)))
	%EditorTree.add_child(row)


func _build_peripheral_row(parent: Node, dev: Dictionary) -> void:
	var row := HBoxContainer.new()
	var kind := Label.new()
	kind.text = dev.tag
	kind.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(kind)
	row.add_child(EditorRows.attr_line_edit(dev, "name", _on_attr_text))
	if dev.tag == TAG_WEBCAM:
		row.add_child(EditorRows.port_label("serial"))
		var serial := EditorRows.attr_line_edit(dev, "serialNumber", _on_attr_text)
		serial.placeholder_text = "USB serial"
		serial.tooltip_text = ADD_CAMERA_TOOLTIP
		row.add_child(serial)
	if dev.attrs.has("ipAddress"):
		row.add_child(EditorRows.port_label("ip"))
		row.add_child(EditorRows.attr_line_edit(dev, "ipAddress", _on_attr_text))
	row.add_child(EditorRows.delete_button(_delete_child.bind(_config.root, dev)))
	parent.add_child(row)


## --- Row widget builders ---

## --- Edit handlers ---


func _on_attr_text(text: String, node: Dictionary, key: String) -> void:
	if _is_read_only():
		return
	node.attrs[key] = text
	_on_edited()


func _on_attr_option(value: int, node: Dictionary, key: String) -> void:
	if _is_read_only():
		return
	node.attrs[key] = str(value)
	_on_edited()


func _on_edited() -> void:
	%EditorTitle.text = _editor_title()
	_update_action_buttons()


func _delete_child(parent: Dictionary, child: Dictionary) -> void:
	if _is_read_only():
		return
	parent.children.erase(child)
	_refresh_editor()


func _add_hub(usb: Dictionary) -> void:
	usb.children.append(
		RobotConfig.element(
			TAG_LYNX_MODULE,
			{"name": DeviceNaming.unique_name(_config.root, "Expansion Hub"), "port": "2"}
		)
	)
	_refresh_editor()


func _add_peripheral(tag: String, serial := "") -> void:
	var attrs := {}
	match tag:
		TAG_WEBCAM:
			attrs = {
				"name": DeviceNaming.unique_name(_config.root, "Webcam 1"), "serialNumber": serial
			}
		TAG_ETHERNET_DEVICE:
			attrs = {
				"name": DeviceNaming.unique_name(_config.root, "limelight"),
				"serialNumber": serial,
				"port": "0",
				"ipAddress": DeviceNaming.ethernet_ip(serial)
			}
	_config.root.children.append(RobotConfig.element(tag, attrs))
	_refresh_editor()


func _rename_node(node: Dictionary) -> void:
	_add_device_target = node
	_custom_edit.text = str(node.attrs.get("name", ""))
	_custom_dialog.title = "Rename"
	_custom_dialog_mode = CustomDialogMode.RENAME
	_validate_custom(_custom_edit.text)
	_custom_dialog.popup_centered()


## --- Add device ---


func _open_add_device(module: Dictionary) -> void:
	_add_device_target = module
	_add_device_popup.clear()
	for i in _picker_entries.size():
		_add_device_popup.add_item(_picker_entries[i].label, i)
	if not _picker_entries.is_empty():
		_add_device_popup.add_separator()
	_add_device_popup.add_item("Custom tag", CUSTOM_ID)
	_add_device_popup.reset_size()
	_add_device_popup.position = DisplayServer.mouse_get_position()
	_add_device_popup.popup()


func _on_add_device_id(id: int) -> void:
	if _add_device_target.is_empty():
		return
	if id == CUSTOM_ID:
		_custom_edit.text = ""
		_custom_dialog.title = "Custom device tag"
		_custom_dialog_mode = CustomDialogMode.CUSTOM_TAG
		_validate_custom(_custom_edit.text)
		_custom_dialog.popup_centered()
		return
	var entry: Dictionary = _picker_entries[id]
	_append_device(_add_device_target, entry.tag, entry.needs_bus)


func _append_device(module: Dictionary, tag: String, needs_bus: bool) -> void:
	var attrs := {
		"name": DeviceNaming.unique_name(_config.root, "new_device"),
		"port": str(DeviceNaming.next_port(module, str(_flavors.get(tag, "")), _flavors))
	}
	if needs_bus:
		attrs["bus"] = "0"
	module.children.append(RobotConfig.element(tag, attrs))
	_refresh_editor()


func _on_custom_confirmed() -> void:
	var text := _custom_edit.text.strip_edges()
	if not _custom_error(text).is_empty() or _add_device_target.is_empty():
		return
	if _custom_dialog_mode == CustomDialogMode.RENAME:
		_add_device_target.attrs["name"] = text
		_refresh_editor()
	else:
		_append_device(_add_device_target, text, false)


func _custom_error(text: String) -> String:
	if text.strip_edges().is_empty():
		return " "
	if _custom_dialog_mode == CustomDialogMode.CUSTOM_TAG:
		return DeviceNaming.tag_error(text)
	return ""


func _validate_custom(text: String) -> void:
	var error := _custom_error(text)
	_custom_hint.text = error
	_custom_dialog.get_ok_button().disabled = not error.is_empty()


## --- Scan ---


func _on_scan() -> void:
	RobotClient.scan()


func _on_scan_result(json: String) -> void:
	if _config == null:
		return
	_scan_dialog.show_result(json)


func _has_serial(serial: String) -> bool:
	for existing: Dictionary in _config.root.children:
		if str(existing.attrs.get("serialNumber", "")) == serial:
			return true
	return false


## --- Save / Save As / Activate ---


func _on_save() -> void:
	if _config == null or _is_read_only():
		return
	var meta := _save_meta(
		_meta.get("name", ""),
		_meta.get("location", RobotClient.LOCATION_LOCAL),
		int(_meta.get("resourceId", 0))
	)
	RobotClient.save_configuration(meta, _config.to_xml())
	_baseline_xml = _config.to_xml()
	if _is_active(_meta):
		_reactivate_dialog.dialog_text = (
			'Saved. Re-activate "%s" now? This restarts the robot.' % _meta.get("name", "")
		)
		_reactivate_dialog.popup_centered()
	else:
		saved.emit(_meta, true)
		_refresh_editor()


func _on_save_as() -> void:
	if _config == null:
		return
	_saveas_edit.text = _meta.get("name", "new_config")
	_saveas_dialog.popup_centered()


func _on_save_as_confirmed() -> void:
	var name := _saveas_edit.text.strip_edges()
	if name.is_empty():
		return
	var meta := _save_meta(name, RobotClient.LOCATION_LOCAL, 0)
	RobotClient.save_configuration(meta, _config.to_xml())
	_meta = meta.duplicate()
	_baseline_xml = _config.to_xml()
	saved.emit(_meta, true)
	_refresh_editor()


func _on_activate() -> void:
	if _meta.is_empty():
		return
	_activate_dialog.dialog_text = 'Activate "%s" and restart the robot?' % _meta.get("name", "")
	_activate_dialog.popup_centered()


func _on_activate_confirmed() -> void:
	RobotClient.activate_configuration(_meta)
	activated.emit(_meta)


func _on_reactivate_yes() -> void:
	RobotClient.activate_configuration(_meta)
	saved.emit(_meta, false)
	activated.emit(_meta)
	_refresh_editor()


func _on_reactivate_no() -> void:
	saved.emit(_meta, true)
	_refresh_editor()


func _on_delete() -> void:
	if not _can_delete():
		return
	_delete_dialog.dialog_text = _delete_text()
	_delete_dialog.popup_centered()


func _delete_text() -> String:
	var text: String = 'Delete "%s" from the robot? This cannot be undone.' % _meta.get("name", "")
	if _is_active(_meta):
		text += (
			"\n\nThis is the active configuration; the robot keeps running it "
			+ "until you activate another."
		)
	return text


func _on_delete_confirmed() -> void:
	if not _can_delete():
		return
	var meta := _meta.duplicate()
	RobotClient.delete_configuration(meta)
	clear()
	deleted.emit(meta)


func _can_delete() -> bool:
	return not _meta.is_empty() and not _is_read_only() and not _is_new()


func _save_meta(name: String, location: String, resource_id: int) -> Dictionary:
	return {"isDirty": false, "location": location, "name": name, "resourceId": resource_id}


## --- State helpers ---


func _editor_title() -> String:
	if _config == null:
		return "Configuration"
	var title: String = _meta.get("name", "(unnamed)")
	if _is_read_only():
		title += "   ·   read-only; use Save As to edit a copy"
	if _is_dirty():
		title += "   ·   edited"
	return title


func _update_action_buttons() -> void:
	var loaded := _config != null
	%SaveButton.disabled = not loaded or _is_read_only() or not _is_dirty()
	%SaveAsButton.disabled = not loaded
	%ScanButton.disabled = not loaded or _is_read_only()
	%ActivateButton.disabled = not loaded or _is_new()
	%DeleteButton.disabled = not loaded or not _can_delete()


func _is_dirty() -> bool:
	return _config != null and _config.to_xml() != _baseline_xml


func _is_active(meta: Dictionary) -> bool:
	return RobotClient.config_is_active(meta)


func _is_read_only() -> bool:
	return RobotClient.location_is_read_only(str(_meta.get("location", "")))


func _is_new() -> bool:
	return not RobotClient.configurations.any(
		func(c: Dictionary) -> bool:
			return c.get("name") == _meta.get("name") and c.get("location") == _meta.get("location")
	)


## --- Catalog & connection ---


func _on_device_list(json: String) -> void:
	_catalog = DeviceCatalog.parse(json)
	_flavors = {}
	for entry: Dictionary in _catalog:
		_flavors[entry.tag] = entry.flavor
	_apply_device_filter()


func _apply_device_filter() -> void:
	_picker_entries = DeviceFilter.visible(_catalog)
	_refresh_editor()


## Action-button enablement tracks whether the loaded config exists in the
## saved list (Activate) — refresh it whenever that list changes.
func _on_configs_changed(_configs: Array) -> void:
	_update_action_buttons()


## The device-type catalog isn't auto-pushed, so (re)request it whenever the
## link comes up — _ready may run before the RC connects.
func _on_connection_changed(connected: bool) -> void:
	if connected:
		RobotClient.request_user_device_types()


## --- Dialogs ---


func _build_dialogs() -> void:
	_saveas_dialog = ConfirmationDialog.new()
	_saveas_dialog.title = "Save As"
	_saveas_edit = LineEdit.new()
	_saveas_edit.custom_minimum_size.x = 280
	_saveas_dialog.add_child(_saveas_edit)
	_saveas_dialog.register_text_enter(_saveas_edit)
	_saveas_dialog.confirmed.connect(_on_save_as_confirmed)
	add_child(_saveas_dialog)
	_wire_dialog_edit(_saveas_dialog, _saveas_edit)

	_custom_dialog = ConfirmationDialog.new()
	var custom_box := VBoxContainer.new()
	_custom_edit = LineEdit.new()
	_custom_edit.custom_minimum_size.x = 280
	_custom_edit.text_changed.connect(_validate_custom)
	custom_box.add_child(_custom_edit)
	_custom_hint = Label.new()
	_custom_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_custom_hint.custom_minimum_size.x = 280
	custom_box.add_child(_custom_hint)
	_custom_dialog.add_child(custom_box)
	_custom_dialog.register_text_enter(_custom_edit)
	_custom_dialog.confirmed.connect(_on_custom_confirmed)
	add_child(_custom_dialog)
	_wire_dialog_edit(_custom_dialog, _custom_edit)

	_activate_dialog = ConfirmationDialog.new()
	_activate_dialog.title = "Activate"
	_activate_dialog.ok_button_text = "Activate"
	_activate_dialog.confirmed.connect(_on_activate_confirmed)
	add_child(_activate_dialog)

	_reactivate_dialog = ConfirmationDialog.new()
	_reactivate_dialog.title = "Re-activate?"
	_reactivate_dialog.ok_button_text = "Re-activate"
	_reactivate_dialog.cancel_button_text = "Keep running"
	_reactivate_dialog.confirmed.connect(_on_reactivate_yes)
	_reactivate_dialog.canceled.connect(_on_reactivate_no)
	add_child(_reactivate_dialog)

	_delete_dialog = ConfirmationDialog.new()
	_delete_dialog.title = "Delete configuration?"
	_delete_dialog.ok_button_text = "Delete"
	_delete_dialog.cancel_button_text = "Keep"
	_delete_dialog.confirmed.connect(_on_delete_confirmed)
	add_child(_delete_dialog)

	_scan_dialog = ScanDialog.new()
	_scan_dialog.known_serials = _has_serial
	_scan_dialog.device_picked.connect(_add_peripheral)
	add_child(_scan_dialog)

	_add_device_popup = PopupMenu.new()
	_add_device_popup.id_pressed.connect(_on_add_device_id)
	add_child(_add_device_popup)


func _wire_dialog_edit(dialog: ConfirmationDialog, edit: LineEdit) -> void:
	var ok := dialog.get_ok_button()
	var cancel := dialog.get_cancel_button()
	edit.focus_neighbor_bottom = edit.get_path_to(ok)
	ok.focus_neighbor_top = ok.get_path_to(edit)
	cancel.focus_neighbor_top = cancel.get_path_to(edit)
	dialog.about_to_popup.connect(func() -> void: edit.call_deferred("grab_focus"))
