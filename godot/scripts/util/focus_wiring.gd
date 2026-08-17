class_name FocusWiring

## Explicit focus neighbours for panes Godot's geometric search gets wrong.

const SIDE_ACTIONS := {
	SIDE_LEFT: &"ui_left", SIDE_TOP: &"ui_up", SIDE_RIGHT: &"ui_right", SIDE_BOTTOM: &"ui_down"
}

const OPPOSITE := {
	SIDE_LEFT: SIDE_RIGHT, SIDE_RIGHT: SIDE_LEFT, SIDE_TOP: SIDE_BOTTOM, SIDE_BOTTOM: SIDE_TOP
}


static func point(from: Control, side: Side, to: Control) -> void:
	from.set_focus_neighbor(side, from.get_path_to(to))


static func link(a: Control, side: Side, b: Control) -> void:
	point(a, side, b)
	point(b, OPPOSITE[side], a)


static func column(controls: Array[Control]) -> void:
	for i in controls.size() - 1:
		link(controls[i], SIDE_BOTTOM, controls[i + 1])


static func row(controls: Array[Control]) -> void:
	for i in controls.size() - 1:
		link(controls[i], SIDE_RIGHT, controls[i + 1])


static func out_of(controls: Array[Control], side: Side, target: Control) -> void:
	for control in controls:
		point(control, side, target)


static func enable(button: BaseButton, enabled: bool) -> void:
	button.disabled = not enabled
	button.focus_mode = Control.FOCUS_ALL if enabled else Control.FOCUS_NONE


static func step(from: Control, side: Side) -> void:
	var next := from.find_valid_focus_neighbor(side)
	if next != null:
		next.grab_focus()


static func first_focusable(node: Node, only_shown := true) -> Control:
	var found := focusables(node, only_shown)
	return found[0] if not found.is_empty() else null


static func focusables(node: Node, only_shown := true) -> Array[Control]:
	var found: Array[Control] = []
	_collect(node, only_shown, found)
	return found


static func _collect(node: Node, only_shown: bool, into: Array[Control]) -> void:
	if node.is_queued_for_deletion():
		return
	var control := node as Control
	if (
		control != null
		and control.focus_mode == Control.FOCUS_ALL
		and (control.is_visible_in_tree() or not only_shown)
		and not (control is BaseButton and (control as BaseButton).disabled)
	):
		into.append(control)
		return
	for child in node.get_children():
		_collect(child, only_shown, into)
