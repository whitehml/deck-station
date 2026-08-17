class_name ScrollPane
extends ScrollContainer

## Scroll areas come in two shapes. Content-driven panes (`capture` off) hold
## focusable rows and only follow focus. View-driven panes take focus themselves
## and hand ui_up / ui_down to the view while captured.

const SPEED := 900.0

@export var capture := true
@export var auto_capture := false

var _captured := false


func _ready() -> void:
	follow_focus = true
	focus_mode = Control.FOCUS_ALL if capture else Control.FOCUS_NONE
	set_process(false)
	ScrollFade.install(self)
	focus_entered.connect(func() -> void: _set_captured(auto_capture))
	focus_exited.connect(func() -> void: _set_captured(false))


func _set_captured(on: bool) -> void:
	if _captured == on:
		return
	_captured = on
	set_process(on)
	queue_redraw()


func _process(delta: float) -> void:
	var axis := Input.get_axis(&"ui_up", &"ui_down")
	if not is_zero_approx(axis):
		scroll_vertical += int(axis * SPEED * delta)


func _gui_input(event: InputEvent) -> void:
	if not capture:
		return
	match ViewCapture.verdict(event, _captured):
		ViewCapture.TOGGLE:
			_set_captured(not _captured)
			accept_event()
			return
		ViewCapture.RELEASE:
			_set_captured(false)
			accept_event()
			return
	if _captured and (event.is_action(&"ui_up") or event.is_action(&"ui_down")):
		accept_event()
	elif event.is_action_pressed(&"ui_page_up", true):
		scroll_vertical -= int(get_v_scroll_bar().page)
		accept_event()
	elif event.is_action_pressed(&"ui_page_down", true):
		scroll_vertical += int(get_v_scroll_bar().page)
		accept_event()


func _draw() -> void:
	if _captured and not auto_capture:
		ViewCapture.draw_border(self)
