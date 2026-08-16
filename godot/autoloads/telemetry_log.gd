extends Node

signal keys_changed(keys: Array)
signal paused_changed(paused: bool)
signal samples_added(samples: Array)

const MAX_POINTS := 1200

## "12.4 V", "-3e-2 m/s": a number, whitespace, then the rest is the unit.
static var _value_unit := RegEx.create_from_string(
	"^([+-]?(?:[0-9]+\\.?[0-9]*|\\.[0-9]+)(?:[eE][+-]?[0-9]+)?)\\s+(\\S.*)$"
)

## Global freeze, owned here so a graph that is built or keyed later still comes
## up matching the rest instead of missing the toggle that flipped them.
var paused := false:
	set(value):
		if value == paused:
			return
		paused = value
		paused_changed.emit(paused)

var _series: Dictionary = {}  # key -> TelemetrySeries
var _t0_ms := 0
var _t0_unix := 0.0


func _ready() -> void:
	_t0_ms = Time.get_ticks_msec()
	_t0_unix = Time.get_unix_time_from_system()
	RobotClient.telemetry_received.connect(_on_telemetry)


func keys() -> Array:
	return DisplayOrder.sorted(_series.keys())


func series(key: String) -> TelemetrySeries:
	return _series.get(key)


func clear() -> void:
	_series.clear()
	keys_changed.emit(keys())


func unix_time(t: float) -> float:
	return _t0_unix + t


func snapshot() -> Array:
	var out: Array = []
	for key in _series:
		var s: TelemetrySeries = _series[key]
		for i in range(s.t.size()):
			out.append({"key": key, "t": s.t[i], "value": s.v[i], "unit": s.unit})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["t"] < b["t"])
	return out


func _on_telemetry(entries: Array) -> void:
	var now := (Time.get_ticks_msec() - _t0_ms) / 1000.0
	var added_key := false
	var batch: Array = []
	for e in entries:
		if e.phase == "SYSTEM":
			continue
		var key: String = e.key
		var value := 0.0
		var unit := ""
		var parsed := _parse_value(e.value)
		if parsed.is_empty():
			parsed = _parse_caption(e.key)
			if parsed.is_empty():
				continue
			key = parsed[2]
		value = parsed[0]
		unit = parsed[1]
		if not _series.has(key):
			_series[key] = TelemetrySeries.new()
			added_key = true
		var s: TelemetrySeries = _series[key]
		if s.unit.is_empty() and not unit.is_empty():
			s.unit = unit
		s.t.push_back(now)
		s.v.push_back(value)
		if s.t.size() > MAX_POINTS:
			s.t = s.t.slice(s.t.size() - MAX_POINTS)
			s.v = s.v.slice(s.v.size() - MAX_POINTS)
		batch.append({"key": key, "t": now, "value": value, "unit": s.unit})
	if added_key:
		keys_changed.emit(keys())
	if not batch.is_empty():
		samples_added.emit(batch)


func _parse_value(value: Variant) -> Array:
	match typeof(value):
		TYPE_FLOAT, TYPE_INT:
			return [float(value), ""]
		TYPE_STRING:
			return _parse_text(value)
		_:
			return []


func _parse_text(text: String) -> Array:
	var s := text.strip_edges()
	if s.is_valid_float():
		return [float(s), ""]
	var m := _value_unit.search(s)
	if m == null:
		return []
	return [float(m.get_string(1)), m.get_string(2).strip_edges()]


func _parse_caption(text: String) -> Array:
	var idx := text.rfind(":")
	if idx < 0:
		return []
	var caption := text.substr(0, idx).strip_edges()
	var parsed := _parse_text(text.substr(idx + 1))
	if caption.is_empty() or parsed.is_empty():
		return []
	return [parsed[0], parsed[1], caption]
