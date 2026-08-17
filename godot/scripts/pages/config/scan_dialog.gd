class_name ScanDialog
extends AcceptDialog

signal device_picked(tag: String, serial: String)

const SCAN_TYPE_TAGS := {
	"WEBCAM": DeviceCatalog.TAG_WEBCAM,
	"ETHERNET_DEVICE": DeviceCatalog.TAG_ETHERNET_DEVICE,
}

const SCAN_TYPE_LABELS := {
	"WEBCAM": "Webcam",
	"ETHERNET_DEVICE": "Ethernet / Limelight",
	"LYNX_USB_DEVICE": "Control / Expansion Hub",
}

const SCAN_LIST_MIN := Vector2(560, 320)
const SCAN_ROW_SEPARATION := 12
const SCAN_ROW_GAP := 16
const SCAN_SUBTLE_ALPHA := 0.7
const ADDED_TEXT := "already configured"

var known_serials: Callable

var _list: VBoxContainer


func _init() -> void:
	title = "Scan results"
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = SCAN_LIST_MIN
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", SCAN_ROW_SEPARATION)
	scroll.add_child(_list)
	add_child(scroll)


func show_result(json: String) -> void:
	for child in _list.get_children():
		child.queue_free()
	var parsed: Variant = JSON.parse_string(json)
	if parsed is not Dictionary:
		_list.add_child(_message("Could not read the scan result."))
		popup_centered()
		return
	var error := str(parsed.get("errorMessage", ""))
	if not error.is_empty():
		_list.add_child(_message(error))
	var any := false
	for entry: Variant in parsed.get("map", []):
		if entry is not Dictionary:
			continue
		if _row(str(entry.get("key", "")), str(entry.get("value", ""))):
			any = true
	if not any:
		_list.add_child(_message("No new devices detected."))
	popup_centered()


func _row(serial: String, kind: String) -> bool:
	var tag: String = SCAN_TYPE_TAGS.get(kind, "")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", SCAN_ROW_GAP)

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 2)
	var title := Label.new()
	title.text = SCAN_TYPE_LABELS.get(kind, kind)
	text.add_child(title)
	var subtitle := Label.new()
	subtitle.text = serial
	subtitle.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	subtitle.modulate.a = SCAN_SUBTLE_ALPHA
	text.add_child(subtitle)
	row.add_child(text)

	var addable := false
	if known_serials.call(serial):
		row.add_child(_status(ADDED_TEXT))
	elif tag.is_empty():
		row.add_child(_status("not added here"))
	else:
		addable = true
		var add := Button.new()
		add.text = "Add"
		add.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		add.pressed.connect(func() -> void: _on_add(add, row, tag, serial))
		row.add_child(add)
	_list.add_child(row)
	return addable


func _on_add(button: Button, row: HBoxContainer, tag: String, serial: String) -> void:
	button.queue_free()
	row.add_child(_status(ADDED_TEXT))
	device_picked.emit(tag, serial)


func _status(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.modulate.a = SCAN_SUBTLE_ALPHA
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return label


func _message(text: String) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.text = text
	return label
