class_name DocDialog
extends AcceptDialog

const MIN_SIZE := Vector2i(900, 620)
const SCREEN_MARGIN := 48


class DocPage:
	extends ScrollPane

	signal stepped(step: int)
	signal dismissed

	func _gui_input(event: InputEvent) -> void:
		if event.is_action_pressed(&"ui_accept") or event.is_action_pressed(&"ui_cancel"):
			dismissed.emit()
			accept_event()
			return
		for step in [-1, 1]:
			if event.is_action_pressed(&"ui_left" if step < 0 else &"ui_right", true):
				stepped.emit(step)
				accept_event()
				return
		super(event)


var _tabs: TabContainer


func _ready() -> void:
	unresizable = false

	_tabs = TabContainer.new()
	_tabs.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for page: Control in _pages():
		_tabs.add_child(page)
	_tabs.tabs_visible = _tabs.get_tab_count() > 1
	_tabs.tab_changed.connect(func(_tab: int) -> void: focus_page())
	add_child(_tabs)

	about_to_popup.connect(_fit_to_screen)
	visibility_changed.connect(_on_visibility_changed)
	get_tree().root.size_changed.connect(_fit_to_screen)
	_fit_to_screen()


func _pages() -> Array:
	return []


## Gives the visible page's scroll pane focus, so held ui_up / ui_down scroll it
## as soon as the dialog opens — including gamepad input routed to the UI.
func focus_page() -> void:
	var page := _tabs.get_current_tab_control()
	if page:
		page.grab_focus()


func _step_tab(step: int) -> void:
	var count := _tabs.get_tab_count()
	if count > 1:
		_tabs.current_tab = (_tabs.current_tab + step + count) % count


func _on_visibility_changed() -> void:
	if visible:
		focus_page()


func _fit_to_screen() -> void:
	var margin := Vector2i(SCREEN_MARGIN, SCREEN_MARGIN)
	var limit := get_tree().root.size - margin * 2
	min_size = MIN_SIZE.min(limit)
	if visible:
		size = size.min(limit)
		position = position.clamp(margin, (get_tree().root.size - size - margin).max(margin))


func _page(page_name: String, always_show_bar := true) -> Control:
	var scroll := DocPage.new()
	scroll.auto_capture = true
	scroll.stepped.connect(_step_tab)
	scroll.dismissed.connect(hide)
	scroll.name = page_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = (
		ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
		if always_show_bar
		else ScrollContainer.SCROLL_MODE_AUTO
	)
	return scroll


func _column(parent: Control) -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in [&"margin_left", &"margin_right", &"margin_top", &"margin_bottom"]:
		margin.add_theme_constant_override(side, DocTable.ROW_SEPARATION * 2)
	parent.add_child(margin)

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override(&"separation", DocTable.ROW_SEPARATION * 3)
	margin.add_child(box)
	return box


func _section(title_text: String, headers: Array, rows: Array) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", DocTable.ROW_SEPARATION)
	box.add_child(_heading(title_text))
	box.add_child(_table(headers, rows))
	return box


func _applies(_host: int) -> bool:
	return true


func _host_text(text: String) -> String:
	return text


func _table(headers: Array, rows: Array) -> Control:
	return DocTable.table(headers, rows, _host_text, _applies)


func _heading(text: String) -> Label:
	return DocTable.heading(text)


func _paragraph(text: String) -> Control:
	return DocTable.paragraph(_host_text(text))


func _code(lines: Array) -> Control:
	return DocTable.code(lines)


func _label(text: String, color: Color, wrap := true) -> Label:
	return DocTable.label(text, color, wrap)
