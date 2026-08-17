class_name PickList
extends ItemList

## An item list a gamepad can drive: focus steps past it until ui_accept hands
## ui_up / ui_down to the rows, and ui_accept or ui_cancel hands them back.

var _captured := false


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	ScrollFade.install(self)
	focus_exited.connect(func() -> void: _set_captured(false))


func _set_captured(on: bool) -> void:
	if _captured == on:
		return
	_captured = on
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	match ViewCapture.verdict(event, _captured):
		ViewCapture.TOGGLE:
			_set_captured(not _captured)
			accept_event()
			return
		ViewCapture.RELEASE:
			_set_captured(false)
			accept_event()
			return
	if _captured:
		for step in [-1, 1]:
			if event.is_action_pressed(&"ui_up" if step < 0 else &"ui_down", true):
				_move_selection(step)
				accept_event()
				return
		return
	for side: Side in FocusWiring.SIDE_ACTIONS:
		if event.is_action_pressed(FocusWiring.SIDE_ACTIONS[side], true):
			FocusWiring.step(self, side)
			accept_event()
			return


func _move_selection(step: int) -> void:
	if item_count == 0:
		return
	var selected := get_selected_items()
	var index := (selected[0] if not selected.is_empty() else 0) + step
	select(clampi(index, 0, item_count - 1))
	ensure_current_is_visible()
	item_selected.emit(get_selected_items()[0])


func _draw() -> void:
	if _captured:
		ViewCapture.draw_border(self)
