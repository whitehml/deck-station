class_name TelemetryRecorder
extends RefCounted

## Long-format rows: one sample per line. Series are sampled independently, so
## a wide layout would be mostly holes; pivot in pandas instead.
##   df = pd.read_csv(path, parse_dates=["timestamp"])
##   wide = df.pivot_table(index="timestamp", columns="key", values="value")
const COLUMNS := ["timestamp", "elapsed_s", "key", "value", "unit"]
const FLUSH_ROWS := 256

var path := ""
var row_count := 0
var last_error := OK

var _file: FileAccess
var _pending: Array[PackedStringArray] = []


func start(target_path: String) -> Error:
	var file := FileAccess.open(target_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	_file = file
	path = target_path
	row_count = 0
	last_error = OK
	_pending.clear()
	_file.store_csv_line(PackedStringArray(COLUMNS))
	write(TelemetryLog.snapshot())
	flush()
	return OK


func is_recording() -> bool:
	return _file != null


func write(samples: Array) -> void:
	if _file == null:
		return
	for s in samples:
		_pending.append(_row(s))
		row_count += 1
	if _pending.size() >= FLUSH_ROWS:
		flush()


func flush() -> void:
	if _file == null or _pending.is_empty():
		return
	for row in _pending:
		_file.store_csv_line(row)
	_pending.clear()
	_file.flush()
	var err := _file.get_error()
	if err != OK and last_error == OK:
		last_error = err


func stop() -> void:
	if _file == null:
		return
	flush()
	_file.close()
	_file = null


func _row(sample: Dictionary) -> PackedStringArray:
	var t: float = sample["t"]
	return PackedStringArray(
		[
			_iso8601(TelemetryLog.unix_time(t)),
			String.num(t, 3),
			sample["key"],
			String.num(sample["value"], 6),
			sample["unit"],
		]
	)


## ISO-8601 UTC with milliseconds, which pandas parses without a format hint.
static func _iso8601(unix_time: float) -> String:
	var whole := int(floor(unix_time))
	var ms := int(round((unix_time - float(whole)) * 1000.0))
	if ms >= 1000:
		whole += 1
		ms = 0
	return "%s.%03dZ" % [Time.get_datetime_string_from_unix_time(whole), ms]
