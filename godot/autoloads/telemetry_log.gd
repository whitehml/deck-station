extends Node

signal keys_changed(keys: Array)

const MAX_POINTS := 1200

var _series: Dictionary = {}  # key -> TelemetrySeries
var _t0_ms := 0


func _ready() -> void:
	_t0_ms = Time.get_ticks_msec()
	RobotClient.telemetry_received.connect(_on_telemetry)


func keys() -> Array:
	var out := _series.keys()
	out.sort()
	return out


func series(key: String) -> TelemetrySeries:
	return _series.get(key)


func clear() -> void:
	_series.clear()
	keys_changed.emit(keys())


func _on_telemetry(entries: Array) -> void:
	var now := (Time.get_ticks_msec() - _t0_ms) / 1000.0
	var added_key := false
	for e in entries:
		if e.phase == "SYSTEM":
			continue
		var key: String = e.key
		var num = _as_number(e.value)
		if num == null:
			var parsed := _caption_number(e.key)
			if parsed.is_empty():
				continue
			key = parsed[0]
			num = parsed[1]
		if not _series.has(key):
			_series[key] = TelemetrySeries.new()
			added_key = true
		var s: TelemetrySeries = _series[key]
		s.t.push_back(now)
		s.v.push_back(num)
		if s.t.size() > MAX_POINTS:
			s.t = s.t.slice(s.t.size() - MAX_POINTS)
			s.v = s.v.slice(s.v.size() - MAX_POINTS)
	if added_key:
		keys_changed.emit(keys())


func _as_number(value: Variant):
	match typeof(value):
		TYPE_FLOAT, TYPE_INT:
			return float(value)
		TYPE_STRING:
			return float(value) if value.is_valid_float() else null
		_:
			return null


func _caption_number(text: String) -> Array:
	var idx := text.rfind(":")
	if idx < 0:
		return []
	var caption := text.substr(0, idx).strip_edges()
	var data := text.substr(idx + 1).strip_edges()
	if caption.is_empty() or not data.is_valid_float():
		return []
	return [caption, float(data)]
