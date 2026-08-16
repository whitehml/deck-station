extends VBoxContainer

signal format_help_requested
signal frame_requested

const SWATCH_SIZE := Vector2(12, 12)
const HEADER_COLOR := Color(0.6, 0.64, 0.72)

var _checks: Dictionary = {}


func _ready() -> void:
	for index in FieldImages.count():
		%FieldPicker.add_item(FieldImages.display_name(index), index)
	%FieldPicker.select(clampi(FieldLog.image_index, 0, FieldImages.count() - 1))
	%FieldPicker.item_selected.connect(FieldLog.set_image_index)
	%FrameButton.pressed.connect(func() -> void: frame_requested.emit())
	%FormatButton.pressed.connect(func() -> void: format_help_requested.emit())
	%ClearButton.pressed.connect(FieldLog.clear)
	FieldLog.classes_changed.connect(_rebuild_classes)
	FieldLog.toggles_changed.connect(_sync_checks)
	_rebuild_classes(FieldLog.class_names())


func grip_tap(grip: StringName) -> void:
	var flag := "shown" if grip == &"L4" else "heading"
	FieldLog.set_all(flag, not _all_set(flag))


func _all_set(flag: String) -> bool:
	for cls: String in FieldLog.class_names():
		if flag == "shown":
			if not FieldLog.is_shown(cls):
				return false
		elif FieldLog.has_heading(cls) and not FieldLog.shows_heading(cls):
			return false
	return true


func _rebuild_classes(names: Array) -> void:
	_checks.clear()
	for child in %ClassList.get_children():
		child.queue_free()
	%EmptyHint.visible = names.is_empty()
	if names.is_empty():
		return
	%ClassList.add_child(_header("Class"))
	%ClassList.add_child(_header("Show"))
	%ClassList.add_child(_header("Head"))
	for cls: String in names:
		var name_of := cls
		%ClassList.add_child(_name_cell(cls))

		var show := _check(
			FieldLog.is_shown(cls), func(on: bool) -> void: FieldLog.set_shown(name_of, on)
		)
		%ClassList.add_child(show)

		var heading: CheckBox = null
		if FieldLog.has_heading(cls):
			heading = _check(
				FieldLog.shows_heading(cls),
				func(on: bool) -> void: FieldLog.set_heading(name_of, on)
			)
			%ClassList.add_child(heading)
		else:
			%ClassList.add_child(Control.new())
		_checks[cls] = [show, heading]


func _sync_checks() -> void:
	for cls: String in _checks:
		var row: Array = _checks[cls]
		row[0].set_pressed_no_signal(FieldLog.is_shown(cls))
		if row[1] != null:
			row[1].set_pressed_no_signal(FieldLog.shows_heading(cls))


func _header(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override(&"font_color", HEADER_COLOR)
	return label


func _name_cell(cls: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var swatch := ColorRect.new()
	swatch.color = FieldLog.class_color(cls)
	swatch.custom_minimum_size = SWATCH_SIZE
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(swatch)

	var label := Label.new()
	label.text = cls
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	return row


func _check(pressed: bool, setter: Callable) -> CheckBox:
	var box := CheckBox.new()
	box.button_pressed = pressed
	box.toggled.connect(setter)
	return box
