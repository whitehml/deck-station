extends MenuButton

signal theme_selected(index: int)

const UPDATE_ID := 1000
const QUIT_ID := 1001
const CONTROLS_ID := 1002
const DEVICE_FILTER_ID := 1003
const FIELD_FORMAT_ID := 1004
const FIELD_FRAME_ID := 1005

const UPDATER := preload("res://scripts/settings/update/updater.gd")
const CONTROLS_HELP := preload("res://scripts/settings/controls_help.gd")
const FIELD_HELP := preload("res://scripts/pages/field/field_help.gd")

var theme_index := 0

var _quit_dialog: ConfirmationDialog
var _updater: Node
var _controls_help: AcceptDialog
var _field_help: AcceptDialog
var _field_frame_dialog: FieldFrameDialog
var _device_filter_dialog: DeviceFilterDialog


func _ready() -> void:
	theme_index = clampi(
		int(AppSettings.get_value("ui", "theme", 0)), 0, AppThemes.THEMES.size() - 1
	)
	_build_menu()
	_build_dialogs()


func show_field_help() -> void:
	_field_help.popup_centered_ratio(0.8)


func show_field_frame() -> void:
	_field_frame_dialog.open()


func controls_help_visible() -> bool:
	return _controls_help.visible


func focus_controls_help() -> void:
	_controls_help.focus_page()


func _build_menu() -> void:
	var popup := get_popup()
	var themes := PopupMenu.new()
	themes.name = "ThemesMenu"
	for i in AppThemes.THEMES.size():
		themes.add_radio_check_item(AppThemes.spec(i)[&"name"], i)
	themes.set_item_checked(theme_index, true)
	themes.id_pressed.connect(_select_theme)
	popup.add_child(themes)
	popup.add_submenu_item("Themes", "ThemesMenu")

	popup.add_separator()
	popup.add_item("Controls", CONTROLS_ID)
	popup.add_item("Device Filter", DEVICE_FILTER_ID)
	popup.add_item("Field Frame", FIELD_FRAME_ID)
	popup.add_item("Field Telemetry Format", FIELD_FORMAT_ID)
	popup.add_item("Check for Updates", UPDATE_ID)
	popup.add_item("Quit", QUIT_ID)
	popup.id_pressed.connect(_on_id_pressed)


func _build_dialogs() -> void:
	_controls_help = CONTROLS_HELP.new()
	add_child(_controls_help)

	_field_help = FIELD_HELP.new()
	add_child(_field_help)

	_field_frame_dialog = FieldFrameDialog.new()
	add_child(_field_frame_dialog)

	_device_filter_dialog = DeviceFilterDialog.new()
	add_child(_device_filter_dialog)

	_updater = UPDATER.new()
	add_child(_updater)

	_quit_dialog = ConfirmationDialog.new()
	_quit_dialog.title = "Quit"
	_quit_dialog.dialog_text = "Quit the Driver Station?"
	_quit_dialog.ok_button_text = "Quit"
	_quit_dialog.confirmed.connect(func() -> void: get_tree().quit())
	add_child(_quit_dialog)


func _on_id_pressed(id: int) -> void:
	if id == QUIT_ID:
		_quit_dialog.popup_centered()
	elif id == UPDATE_ID:
		_updater.run()
	elif id == CONTROLS_ID:
		_controls_help.popup_centered_ratio(0.8)
	elif id == DEVICE_FILTER_ID:
		_device_filter_dialog.open()
	elif id == FIELD_FORMAT_ID:
		show_field_help()
	elif id == FIELD_FRAME_ID:
		show_field_frame()


func _select_theme(index: int) -> void:
	theme_index = index
	var themes: PopupMenu = get_popup().get_node("ThemesMenu")
	for i in AppThemes.THEMES.size():
		themes.set_item_checked(i, i == index)
	AppSettings.store("ui", {"theme": index})
	theme_selected.emit(index)
