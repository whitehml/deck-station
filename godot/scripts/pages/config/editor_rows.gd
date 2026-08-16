class_name EditorRows


static func attr_line_edit(node: Dictionary, key: String, on_text: Callable) -> LineEdit:
	var edit := LineEdit.new()
	edit.text = str(node.attrs.get(key, ""))
	edit.custom_minimum_size.x = 150
	edit.text_changed.connect(on_text.bind(node, key))
	return edit


static func attr_options(node: Dictionary, key: String, count: int, on_pick: Callable) -> PortWheel:
	var current := int(str(node.attrs.get(key, "0")))
	var values: Array[int] = []
	for i in count:
		values.append(i)
	if not values.has(current):
		values.append(current)
		values.sort()
	var wheel := PortWheel.new()
	wheel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	wheel.setup(values, current)
	wheel.value_changed.connect(on_pick.bind(node, key))
	return wheel


static func port_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label


static func text_button(text: String, on_press: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(on_press)
	return button


static func delete_button(on_press: Callable) -> Button:
	var button := Button.new()
	button.text = "✕"
	button.pressed.connect(on_press)
	return button
