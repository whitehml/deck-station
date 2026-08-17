class_name FocusEdit
extends LineEdit

## A LineEdit that lets go: plain LineEdit swallows ui_left / ui_right for
## the caret, which traps gamepad focus in a row of text fields. Here the
## caret keeps them only while it has somewhere to go, and hands them to
## focus at the ends.


func _gui_input(event: InputEvent) -> void:
	var side := SIDE_LEFT
	if event.is_action_pressed(&"ui_right", true):
		side = SIDE_RIGHT
	elif not event.is_action_pressed(&"ui_left", true):
		return
	var at_end := caret_column == (text.length() if side == SIDE_RIGHT else 0)
	if at_end and not has_selection():
		FocusWiring.step(self, side)
		accept_event()
