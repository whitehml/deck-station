class_name DeviceFilterDialog
extends AcceptDialog

const LIST_SIZE := Vector2(260, 320)

var _shown_list: ItemList
var _hidden_list: ItemList
var _catalog: Array = []


func _init() -> void:
	title = "Device Filter"
	ok_button_text = "Save"
	add_cancel_button("Cancel")
	_build()


func _ready() -> void:
	RobotClient.user_device_list_received.connect(_on_device_list)
	confirmed.connect(_on_save)


func open() -> void:
	RobotClient.request_user_device_types()
	_populate()
	popup_centered()


func _build() -> void:
	var root := VBoxContainer.new()
	add_child(root)

	var columns := HBoxContainer.new()
	root.add_child(columns)
	_shown_list = _column(columns, "Shown")
	_shown_list.item_activated.connect(_on_activated.bind(_shown_list))

	var buttons := VBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_child(_move_button("Hide  →", _hide_selected))
	buttons.add_child(_move_button("←  Show", _show_selected))
	columns.add_child(buttons)

	_hidden_list = _column(columns, "Hidden")
	_hidden_list.item_activated.connect(_on_activated.bind(_hidden_list))

	var hint := Label.new()
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = LIST_SIZE.x * 2
	hint.text = (
		"Hidden types stay available under Add device ▸ Custom tag….\nSaved to %s"
		% DeviceFilter.path()
	)
	root.add_child(hint)


func _column(parent: Node, label_text: String) -> ItemList:
	var column := VBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	column.add_child(label)
	var list := ItemList.new()
	list.select_mode = ItemList.SELECT_MULTI
	list.custom_minimum_size = LIST_SIZE
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(list)
	parent.add_child(column)
	return list


func _move_button(text: String, on_press: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(on_press)
	return button


func _on_device_list(json: String) -> void:
	_catalog = DeviceCatalog.parse(json)
	if visible:
		_populate()


func _populate() -> void:
	var labels := {}
	for entry: Dictionary in _catalog:
		labels[entry.tag] = entry.label
	_shown_list.clear()
	_hidden_list.clear()
	for tag: String in DeviceFilter.hidden_tags():
		_add_row(_hidden_list, tag, labels.get(tag, tag))
	for entry: Dictionary in _catalog:
		if not DeviceFilter.is_hidden(entry.tag):
			_add_row(_shown_list, entry.tag, entry.label)


func _add_row(list: ItemList, tag: String, label: String) -> void:
	var index := list.add_item(label)
	list.set_item_metadata(index, tag)
	list.set_item_tooltip(index, tag)


func _on_activated(index: int, list: ItemList) -> void:
	list.deselect_all()
	list.select(index)
	if list == _shown_list:
		_hide_selected()
	else:
		_show_selected()


func _hide_selected() -> void:
	_move(_shown_list, _hidden_list)


func _show_selected() -> void:
	_move(_hidden_list, _shown_list)


func _move(from: ItemList, to: ItemList) -> void:
	var selected := from.get_selected_items()
	selected.reverse()
	for index in selected:
		_add_row(to, str(from.get_item_metadata(index)), from.get_item_text(index))
		from.remove_item(index)
	_sort(to)


func _sort(list: ItemList) -> void:
	var rows: Array = []
	for i in list.item_count:
		rows.append({"tag": str(list.get_item_metadata(i)), "label": list.get_item_text(i)})
	rows.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool: return a.label.naturalnocasecmp_to(b.label) < 0
	)
	list.clear()
	for row: Dictionary in rows:
		_add_row(list, row.tag, row.label)


func _on_save() -> void:
	var tags: Array = []
	for i in _hidden_list.item_count:
		tags.append(str(_hidden_list.get_item_metadata(i)))
	DeviceFilter.set_hidden_tags(tags)
