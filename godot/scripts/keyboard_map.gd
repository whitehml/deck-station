extends Control

## Scale-to-fit drawing of a 60%-plus-function-row keyboard, each cap tinted
## by the gamepad control it stands in for.

enum { PLAIN, LEFT_STICK, RIGHT_STICK, FACE, SHOULDER, SYSTEM, DPAD, STATION }

const ROLE_COLORS := {
	PLAIN: Color(0.42, 0.44, 0.5),
	LEFT_STICK: Color(0.38, 0.66, 0.98),
	RIGHT_STICK: Color(0.42, 0.82, 0.58),
	FACE: Color(0.98, 0.74, 0.32),
	SHOULDER: Color(0.78, 0.52, 0.92),
	SYSTEM: Color(0.62, 0.64, 0.88),
	DPAD: Color(0.36, 0.82, 0.86),
	STATION: Color(0.94, 0.44, 0.44),
}

const LEGEND := [
	[LEFT_STICK, "Left stick"],
	[RIGHT_STICK, "Right stick"],
	[DPAD, "D-pad"],
	[FACE, "Face buttons"],
	[SHOULDER, "Bumpers / triggers"],
	[SYSTEM, "Stick clicks, Start / Back"],
	[STATION, "Driver station"],
]

const UNITS_WIDE := 18.5
const UNITS_TALL := 6.0
const CLUSTER_X := 15.5
const GAP := 0.06

const ROWS := [
	[
		["Esc", 1.0, PLAIN, ""],
		["F1", 1.0, STATION, "L4"],
		["F2", 1.0, STATION, "L5"],
		["F3", 1.0, STATION, "R4"],
		["F4", 1.0, STATION, "R5"],
		["F5", 1.0, PLAIN, ""],
		["F6", 1.0, PLAIN, ""],
		["F7", 1.0, PLAIN, ""],
		["F8", 1.0, PLAIN, ""],
		["F9", 1.0, PLAIN, ""],
		["F10", 1.0, PLAIN, ""],
		["F11", 1.0, PLAIN, ""],
		["F12", 1.0, PLAIN, ""],
	],
	[
		["`", 1.0, PLAIN, ""],
		["1", 1.0, SHOULDER, "L1"],
		["2", 1.0, SHOULDER, "R1"],
		["3", 1.0, SHOULDER, "L2"],
		["4", 1.0, SHOULDER, "R2"],
		["5", 1.0, PLAIN, ""],
		["6", 1.0, PLAIN, ""],
		["7", 1.0, PLAIN, ""],
		["8", 1.0, PLAIN, ""],
		["9", 1.0, PLAIN, ""],
		["0", 1.0, PLAIN, ""],
		["-", 1.0, PLAIN, ""],
		["=", 1.0, PLAIN, ""],
		["Bksp", 2.0, SYSTEM, "Back"],
	],
	[
		["Tab", 1.5, PLAIN, ""],
		["Q", 1.0, LEFT_STICK, "↖"],
		["W", 1.0, LEFT_STICK, "↑"],
		["E", 1.0, LEFT_STICK, "↗"],
		["R", 1.0, PLAIN, ""],
		["T", 1.0, FACE, "Y"],
		["Y", 1.0, PLAIN, ""],
		["U", 1.0, RIGHT_STICK, "↖"],
		["I", 1.0, RIGHT_STICK, "↑"],
		["O", 1.0, RIGHT_STICK, "↗"],
		["P", 1.0, PLAIN, ""],
		["[", 1.0, STATION, "Slot 1"],
		["]", 1.0, STATION, "Slot 2"],
		["\\", 1.5, PLAIN, ""],
	],
	[
		["Caps", 1.75, PLAIN, ""],
		["A", 1.0, LEFT_STICK, "←"],
		["S", 1.0, LEFT_STICK, "50%"],
		["D", 1.0, LEFT_STICK, "→"],
		["F", 1.0, FACE, "X"],
		["G", 1.0, FACE, "A"],
		["H", 1.0, FACE, "B"],
		["J", 1.0, RIGHT_STICK, "←"],
		["K", 1.0, RIGHT_STICK, "50%"],
		["L", 1.0, RIGHT_STICK, "→"],
		[";", 1.0, PLAIN, ""],
		["'", 1.0, PLAIN, ""],
		["Enter", 2.25, SYSTEM, "Start"],
	],
	[
		["Shift", 2.25, PLAIN, ""],
		["Z", 1.0, LEFT_STICK, "↙"],
		["X", 1.0, LEFT_STICK, "↓"],
		["C", 1.0, LEFT_STICK, "↘"],
		["V", 1.0, PLAIN, ""],
		["B", 1.0, PLAIN, ""],
		["N", 1.0, PLAIN, ""],
		["M", 1.0, RIGHT_STICK, "↙"],
		[",", 1.0, RIGHT_STICK, "↓"],
		[".", 1.0, RIGHT_STICK, "↘"],
		["/", 1.0, PLAIN, ""],
		["Shift", 2.75, PLAIN, ""],
	],
	[
		["Ctrl", 1.25, SYSTEM, "L3"],
		["Win", 1.25, PLAIN, ""],
		["Alt", 1.25, SYSTEM, "R3"],
		["Space", 6.25, STATION, "Freeze graphs"],
		["Alt", 1.25, SYSTEM, "R3"],
		["Win", 1.25, PLAIN, ""],
		["Menu", 1.25, PLAIN, ""],
		["Ctrl", 1.25, SYSTEM, "L3"],
	],
]

## [row, column-offset within the cluster, label, width, role, sub-label]
const CLUSTER := [
	[1, 0.0, "Del", 1.0, STATION, "E-STOP"],
	[4, 1.0, "↑", 1.0, DPAD, ""],
	[5, 0.0, "←", 1.0, DPAD, ""],
	[5, 1.0, "↓", 1.0, DPAD, ""],
	[5, 2.0, "→", 1.0, DPAD, ""],
]

var _font: Font = ThemeDB.fallback_font


func _ready() -> void:
	resized.connect(queue_redraw)


func _draw() -> void:
	var unit := minf(size.x / UNITS_WIDE, size.y / UNITS_TALL)
	var origin := Vector2((size.x - unit * UNITS_WIDE) * 0.5, (size.y - unit * UNITS_TALL) * 0.5)

	for row_index in ROWS.size():
		var x := 0.0
		for key: Array in ROWS[row_index]:
			_draw_key(origin, unit, x, row_index, key[1], key[0], key[2], key[3])
			x += key[1]

	for key: Array in CLUSTER:
		_draw_key(origin, unit, CLUSTER_X + key[1], key[0], key[3], key[2], key[4], key[5])


func _draw_key(
	origin: Vector2,
	unit: float,
	units_x: float,
	row: int,
	units_w: float,
	label: String,
	role: int,
	sub: String
) -> void:
	var color: Color = ROLE_COLORS[role]
	var rect := Rect2(
		origin + Vector2(units_x + GAP, row + GAP) * unit,
		Vector2(units_w - GAP * 2.0, 1.0 - GAP * 2.0) * unit
	)
	draw_rect(rect, color * Color(1.0, 1.0, 1.0, 0.16 if role == PLAIN else 0.3))
	draw_rect(rect, color.darkened(0.1 if role == PLAIN else 0.0), false, maxf(1.0, unit * 0.03))

	var label_size := int(maxf(9.0, unit * (0.3 if sub.is_empty() else 0.26)))
	var label_y := rect.position.y + (rect.size.y * (0.62 if sub.is_empty() else 0.44))
	draw_string(
		_font,
		Vector2(rect.position.x, label_y),
		label,
		HORIZONTAL_ALIGNMENT_CENTER,
		rect.size.x,
		label_size,
		Color(0.94, 0.95, 0.97) if role != PLAIN else Color(0.72, 0.74, 0.78)
	)
	if not sub.is_empty():
		draw_string(
			_font,
			Vector2(rect.position.x, rect.position.y + rect.size.y * 0.86),
			sub,
			HORIZONTAL_ALIGNMENT_CENTER,
			rect.size.x,
			int(maxf(8.0, unit * 0.2)),
			color
		)
