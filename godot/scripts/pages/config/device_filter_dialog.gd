class_name DeviceFilterDialog
extends AcceptDialog

const LIST_SIZE := Vector2(260, 320)

var _shown_list: PickList
var _hidden_list: PickList
var _hide_button: Button
var _show_button: Button
var _cancel_button: Button
var _catalog: Array = []


func _init() -> void:
	title = "Device Filter"
	ok_button_text = "Save"
	_cancel_button = add_cancel_button("Cancel")
	_build()


func _ready() -> void:
	RobotClient.user_device_list_received.connect(_on_device_list)
	confirmed.connect(_on_save)
	about_to_popup.connect(func() -> void: _shown_list.call_deferred(&"grab_focus"))
	DialogCancel.install(self)
	_update_move_buttons()


## The dialog's own buttons are the only thing Godot's geometric search reaches
## from the lists, so name every neighbour.
func _wire_focus() -> void:
	var ok := get_ok_button()
	for list: Control in [_shown_list, _hidden_list]:
		FocusWiring.point(list, SIDE_BOTTOM, ok)
	FocusWiring.point(
		_shown_list, SIDE_RIGHT, _hidden_list if _hide_button.disabled else _hide_button
	)
	FocusWiring.point(
		_hidden_list, SIDE_LEFT, _shown_list if _show_button.disabled else _show_button
	)
	for button: Button in [_hide_button, _show_button]:
		FocusWiring.point(button, SIDE_LEFT, _shown_list)
		FocusWiring.point(button, SIDE_RIGHT, _hidden_list)
	FocusWiring.link(_hide_button, SIDE_BOTTOM, _show_button)
	FocusWiring.point(_show_button, SIDE_BOTTOM, ok)
	var above: Control = _shown_list if _show_button.disabled else _show_button
	for button: Button in [ok, _cancel_button]:
		FocusWiring.point(button, SIDE_TOP, above)


func _update_move_buttons() -> void:
	_set_live(_hide_button, not _shown_list.get_selected_items().is_empty())
	_set_live(_show_button, not _hidden_list.get_selected_items().is_empty())
	_wire_focus()


func _set_live(button: Button, live: bool) -> void:
	button.disabled = not live
	button.focus_mode = Control.FOCUS_ALL if live else Control.FOCUS_NONE


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
	_hide_button = _move_button("Hide  →", _hide_selected)
	_show_button = _move_button("←  Show", _show_selected)
	buttons.add_child(_hide_button)
	buttons.add_child(_show_button)
	columns.add_child(buttons)

	_hidden_list = _column(columns, "Hidden")
	_hidden_list.item_activated.connect(_on_activated.bind(_hidden_list))

	var hint := Label.new()
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = LIST_SIZE.x * 2
	hint.text = (
		"Hidden types stay available under Add device ▸ Custom tag.\nSaved to %s"
		% DeviceFilter.path()
	)
	root.add_child(hint)


func _column(parent: Node, label_text: String) -> PickList:
	var column := VBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	column.add_child(label)
	var list := PickList.new()
	list.select_mode = ItemList.SELECT_MULTI
	list.custom_minimum_size = LIST_SIZE
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.item_selected.connect(func(_index: int) -> void: _on_selection(list))
	list.multi_selected.connect(func(_index: int, _picked: bool) -> void: _on_selection(list))
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
	_update_move_buttons()


func _on_selection(list: PickList) -> void:
	var other := _hidden_list if list == _shown_list else _shown_list
	other.deselect_all()
	_update_move_buttons()


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
	_update_move_buttons()
	from.grab_focus()


func _sort(list: ItemList) -> void:
	var rows: Array = []
	for i in list.item_count:
		rows.append({"tag": str(list.get_item_metadata(i)), "label": list.get_item_text(i)})
	DisplayOrder.sorted_by(rows, "label")
	list.clear()
	for row: Dictionary in rows:
		_add_row(list, row.tag, row.label)


func _on_save() -> void:
	var tags: Array = []
	for i in _hidden_list.item_count:
		tags.append(str(_hidden_list.get_item_metadata(i)))
	DeviceFilter.set_hidden_tags(tags)
