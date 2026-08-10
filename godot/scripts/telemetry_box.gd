extends PanelContainer

var _entries: Array = []

@onready var _first_line: RichTextLabel = %FirstLine
@onready var _text: RichTextLabel = %Text
@onready var _system_toggle: Button = %SystemToggle


func _ready() -> void:
	_system_toggle.button_pressed = RobotClient.show_system_telemetry
	_system_toggle.toggled.connect(RobotClient.set_show_system_telemetry)
	RobotClient.system_telemetry_shown_changed.connect(_on_system_shown_changed)
	_render()


func set_entries(entries: Array) -> void:
	_entries = entries
	_render()


## The toggle shares the first line's row rather than a row of its own, so the
## only cost of showing it is a shorter right margin on that one line.
func _render() -> void:
	_system_toggle.visible = _entries.any(func(e: Dictionary) -> bool: return e.phase == "SYSTEM")
	var lines := RobotClient.format_telemetry(_entries).split("\n", true, 1)
	_first_line.text = lines[0] if lines.size() > 0 else ""
	_text.text = lines[1] if lines.size() > 1 else ""


func _on_system_shown_changed(shown: bool) -> void:
	_system_toggle.button_pressed = shown
	_render()
