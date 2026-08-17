class_name ViewCapture

## The shared contract for widgets that take ui_up / ui_down away from focus
## navigation: ui_accept captures and releases, ui_cancel always releases.

enum { NONE, TOGGLE, RELEASE }

const BORDER := 2.0


static func verdict(event: InputEvent, captured: bool) -> int:
	if event.is_action_pressed(&"ui_accept"):
		return TOGGLE
	if captured and event.is_action_pressed(&"ui_cancel"):
		return RELEASE
	return NONE


static func draw_border(control: Control) -> void:
	control.draw_rect(
		Rect2(Vector2.ZERO, control.size),
		control.get_theme_color(&"font_focus_color", &"Button"),
		false,
		BORDER
	)
