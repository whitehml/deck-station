class_name Graph
extends Control

const GROUP := &"graphs"
const GRID_LINES := 4
const GRID_COLOR := Color(1.0, 1.0, 1.0, 0.08)
const SERIES_COLORS := [
	Color(0.35, 0.8, 1.0),
	Color(1.0, 0.6, 0.3),
	Color(0.5, 0.9, 0.5),
	Color(1.0, 0.5, 0.7),
	Color(0.8, 0.7, 1.0),
	Color(1.0, 0.85, 0.4),
]

var keys := PackedStringArray():
	set(value):
		keys = value
		_frozen_t_max = _latest_time() if _paused else NAN
		queue_redraw()

var window_seconds := 10.0:
	set(value):
		window_seconds = value
		queue_redraw()

var _hover := false
var _mouse := Vector2.ZERO
var _paused := false
var _frozen_t_max := NAN


func _ready() -> void:
	add_to_group(GROUP)
	mouse_entered.connect(func() -> void: _hover = true)
	mouse_exited.connect(func() -> void: _hover = false)
	TelemetryLog.paused_changed.connect(set_paused)
	set_paused(TelemetryLog.paused)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse = event.position
	elif (
		event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed
	):
		_toggle_pause()
		accept_event()


func _toggle_pause() -> void:
	set_paused(not _paused)


## Freezing captures the current time axis. A graph with no data yet still takes
## the pause; it grabs its axis in _process once the first sample lands.
func set_paused(value: bool) -> void:
	if value == _paused:
		return
	_paused = value
	_frozen_t_max = _latest_time() if value else NAN
	queue_redraw()


func _legend(key: String) -> String:
	var s: TelemetrySeries = TelemetryLog.series(key)
	if s == null or s.unit.is_empty():
		return key
	return "%s (%s)" % [key, s.unit]


func _latest_time() -> float:
	var t_max := -INF
	for key in keys:
		var s: TelemetrySeries = TelemetryLog.series(key)
		if s and not s.t.is_empty():
			t_max = maxf(t_max, s.t[s.t.size() - 1])
	return t_max if t_max > -INF else NAN


func _process(_delta: float) -> void:
	if keys.is_empty():
		return
	if _paused and is_nan(_frozen_t_max):
		_frozen_t_max = _latest_time()
		queue_redraw()
	if not _paused or _hover:
		queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	if keys.is_empty():
		draw_string(
			font,
			Vector2(12, 24),
			"Select a signal to graph",
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			16,
			Color.GRAY
		)
		return

	var t_max := _frozen_t_max if _paused and not is_nan(_frozen_t_max) else _latest_time()
	if is_nan(t_max):
		draw_string(
			font, Vector2(12, 24), "waiting for data", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.GRAY
		)
		return
	var t_min := t_max - window_seconds

	var v_min := INF
	var v_max := -INF
	for key in keys:
		var s: TelemetrySeries = TelemetryLog.series(key)
		if not s:
			continue
		var times: PackedFloat32Array = s.t
		var values: PackedFloat32Array = s.v
		for i in range(times.size()):
			if times[i] < t_min or times[i] > t_max:
				continue
			v_min = minf(v_min, values[i])
			v_max = maxf(v_max, values[i])
	if v_min > v_max:
		draw_string(
			font, Vector2(12, 24), "waiting for data", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.GRAY
		)
		return
	var span := v_max - v_min
	if span < 0.001:
		span = 1.0
	v_min -= span * 0.1
	v_max += span * 0.1
	span = v_max - v_min

	for g in range(GRID_LINES + 1):
		var y := size.y * g / GRID_LINES
		draw_line(Vector2(0, y), Vector2(size.x, y), GRID_COLOR)

	var nearest := Vector2.INF
	var nearest_v := 0.0
	var nearest_dist := INF
	for ki in range(keys.size()):
		var color: Color = SERIES_COLORS[ki % SERIES_COLORS.size()]
		var s: TelemetrySeries = TelemetryLog.series(keys[ki])
		if not s:
			continue
		var times: PackedFloat32Array = s.t
		var values: PackedFloat32Array = s.v
		var points := PackedVector2Array()
		for i in range(times.size()):
			if times[i] < t_min or times[i] > t_max:
				continue
			var x := (times[i] - t_min) / window_seconds * size.x
			var y := size.y - (values[i] - v_min) / span * size.y
			points.append(Vector2(x, y))
		if points.size() >= 2:
			draw_polyline(points, color, 2.0, true)
		if _hover:
			for p in points:
				var d := p.distance_squared_to(_mouse)
				if d < nearest_dist:
					nearest_dist = d
					nearest = p
					nearest_v = v_max - p.y / size.y * span

	if _hover and nearest != Vector2.INF:
		draw_circle(nearest, 4.0, Color.WHITE)
		draw_string(
			font,
			nearest + Vector2(8, -8),
			"%0.2f" % nearest_v,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			12,
			Color.WHITE
		)

	for ki in range(keys.size()):
		var color: Color = SERIES_COLORS[ki % SERIES_COLORS.size()]
		draw_string(
			font,
			Vector2(12, 24 + ki * 18),
			_legend(keys[ki]),
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			16,
			color
		)
	if _paused:
		draw_string(
			font,
			Vector2(0, 24),
			"PAUSED",
			HORIZONTAL_ALIGNMENT_RIGHT,
			size.x - 12,
			12,
			Color(1.0, 0.75, 0.3)
		)
	draw_string(
		font,
		Vector2(0, 44),
		"%0.2f" % v_max,
		HORIZONTAL_ALIGNMENT_RIGHT,
		size.x - 12,
		12,
		Color.GRAY
	)
	draw_string(
		font,
		Vector2(0, size.y - 8),
		"%0.2f" % v_min,
		HORIZONTAL_ALIGNMENT_RIGHT,
		size.x - 12,
		12,
		Color.GRAY
	)
	draw_string(
		font,
		Vector2(12, size.y - 8),
		"%ds" % window_seconds,
		HORIZONTAL_ALIGNMENT_LEFT,
		40,
		12,
		Color.GRAY
	)
