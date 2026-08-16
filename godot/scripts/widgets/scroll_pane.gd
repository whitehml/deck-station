class_name ScrollPane
extends ScrollContainer

const SPEED := 900.0


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	set_process(false)
	focus_entered.connect(func() -> void: set_process(true))
	focus_exited.connect(func() -> void: set_process(false))


func _process(delta: float) -> void:
	var axis := Input.get_axis(&"ui_up", &"ui_down")
	if not is_zero_approx(axis):
		scroll_vertical += int(axis * SPEED * delta)


func _gui_input(event: InputEvent) -> void:
	if event.is_action(&"ui_up") or event.is_action(&"ui_down"):
		accept_event()
	elif event.is_action_pressed(&"ui_page_up", true):
		scroll_vertical -= int(get_v_scroll_bar().page)
		accept_event()
	elif event.is_action_pressed(&"ui_page_down", true):
		scroll_vertical += int(get_v_scroll_bar().page)
		accept_event()
