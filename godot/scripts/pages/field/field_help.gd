extends DocDialog

const TYPES := [
	[
		"robot",
		"An 18 in square centred on the pose, rotated to its heading.",
		"x, y, h, size, l, w"
	],
	["point", "A small dot, with a short heading arrow when h is given.", "x, y, h"],
	[
		"zone",
		(
			"A translucent polygon through the listed corners. A polygon has no "
			+ "heading, so a class of only zones gets no heading toggle."
		),
		"pts"
	],
	["vec", "An arrow from the pose, labelled with its magnitude.", "x, y, dx, dy, mag, h, unit"],
]

const ATTRIBUTES := [
	["x, y", "Position in field coordinates. Required by robot, point and vec."],
	[
		"h",
		(
			"Heading in degrees, counter-clockwise from the +x axis. Optional. Draws the "
			+ "heading arrow on robot and point; on vec it only aims a mag. Not used by zone."
		)
	],
	["size", "Robot square side, in field units. Defaults to 18."],
	["l, w", "Robot length (along the heading) and width, when it is not square."],
	["pts", "Zone corners as x,y pairs separated by semicolons: 0,0;24,0;24,24."],
	["dx, dy", "Vector components, from the tail at x,y."],
	["mag", "Vector magnitude along h, as an alternative to dx / dy."],
	["unit", "Suffix for the magnitude label an arrow carries, e.g. in/s."],
	["color", "Per-item colour override, #rrggbb. Otherwise the class colour is used."],
]

const EXAMPLE := [
	"// Java, inside your OpMode",
	'telemetry.addData("#f", "robot Robot x=72 y=36 h=90");',
	'telemetry.addData("#f", "zone Launch pts=0,0;48,0;48,24;0,24");',
	'telemetry.addData("#f", "vec Velocity x=72 y=36 dx=18 dy=6 unit=in/s");',
	'telemetry.addData("#f", "point Samples x=100 y=52 h=45");',
	'telemetry.addData("#f", "point Samples x=118 y=61 h=0");',
]

const GROUPING := [
	'telemetry.addData("#f", "point \\"Game Pieces\\" x=100 y=52");',
	'telemetry.addData("#f", "point \\"Game Pieces\\" x=118 y=61");',
]


func _ready() -> void:
	title = "Field Telemetry Format"
	super()


func _pages() -> Array:
	return [_format_page(), _reference_page()]


func _format_page() -> Control:
	var page := _page("Format")
	var box := _column(page)
	box.add_child(
		_block(
			"The line",
			(
				"The Field page draws whatever your OpMode says it should, over ordinary "
				+ "telemetry. Any line that starts with #f (or #field) is read as one drawing "
				+ "item and hidden from the telemetry text; every other line is untouched."
			),
			_code(["#f <type> <class> <attr>=<value> ..."])
		)
	)
	box.add_child(
		_block(
			"Example",
			(
				"Both addData and addLine work — the caption and separator are stripped before "
				+ "parsing, so only the payload matters."
			),
			_code(EXAMPLE)
		)
	)
	box.add_child(
		_block(
			"Grouping",
			(
				"The class is the second token, and it is what the page's toggles act on. Send "
				+ "many items under one class and they show, hide and drop their heading arrows "
				+ "together — which is how a variable number of detections stays manageable. "
				+ "Quote a class name that contains spaces."
			),
			_code(GROUPING)
		)
	)
	box.add_child(
		_block(
			"Coordinates",
			(
				"Values are in whatever frame the corners say they are. The default is the "
				+ "Pedro Pathing frame: 0,0 at the bottom-left corner and 144,144 at the "
				+ "top-right, in inches. Settings -> Field Frame changes both corners, and the "
				+ "Field page prints the resulting corner values just outside the field."
			),
			null
		)
	)
	return page


func _reference_page() -> Control:
	var page := _page("Reference")
	var box := _column(page)
	box.add_child(_section("Item types", ["Type", "Draws", "Attributes"], TYPES))
	box.add_child(_section("Attributes", ["Attribute", "Meaning"], ATTRIBUTES))
	box.add_child(
		_block(
			"Malformed lines",
			(
				"A line with an unknown type, a missing required attribute or an unparsable "
				+ "number is skipped silently rather than throwing, so a typo costs you one "
				+ "item and never the OpMode."
			),
			null
		)
	)
	return page


func _block(title_text: String, body: String, example: Control) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", DocTable.ROW_SEPARATION)
	box.add_child(_heading(title_text))
	box.add_child(_paragraph(body))
	if example:
		box.add_child(example)
	return box
