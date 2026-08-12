class_name PhaseAction

## The one description of the phase-advance button, shared by the shell's STOP
## button and the OpModes page's action button.

const LABELS := {
	RobotClient.Phase.IDLE: "INIT",
	RobotClient.Phase.INIT: "START",
	RobotClient.Phase.RUNNING: "STOP",
}
const DEFAULT_LABEL := "STOP"

const STATUS_NAMES := {
	RobotClient.Phase.IDLE: &"idle",
	RobotClient.Phase.INIT: &"init",
	RobotClient.Phase.RUNNING: &"running",
}
const DEFAULT_STATUS := &"neutral"


static func apply(button: Button, phase: int) -> void:
	button.text = LABELS.get(phase, DEFAULT_LABEL)
	button.add_theme_color_override(
		&"font_color",
		button.get_theme_color(STATUS_NAMES.get(phase, DEFAULT_STATUS), AppThemes.STATUS_TYPE)
	)
	button.disabled = (
		phase == RobotClient.Phase.DISCONNECTED
		or (phase == RobotClient.Phase.IDLE and RobotClient.selected_opmode.is_empty())
	)
