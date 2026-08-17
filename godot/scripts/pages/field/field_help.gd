extends DocDialog

const TYPES := [
	[
		"robot",
		"An 18 in square centered on the pose, rotated to its heading.",
		"x, y, h, size, l, w"
	],
	["point", "A small dot, with a short heading arrow when h is given.", "x, y, h"],
	["zone", "A translucent polygon through the listed vertices.", "pts"],
	["vec", "An arrow from the pose, labelled with its magnitude.", "x, y, dx, dy, mag, h, unit"],
]

const ATTRIBUTES := [
	["x, y", "Position in field coordinates. Required by robot, point and vec."],
	[
		"h",
		(
			"Heading in degrees, counter-clockwise from the +x axis. Optional. Draws the "
			+ "heading arrow on robot and point; on vec it aims a mag and cannot be given "
			+ "with dx / dy."
		)
	],
	["size", "Robot square side, in field units. Defaults to 18."],
	[
		"l, w",
		(
			"Robot length (along the heading) and width, when it is not square. Each one "
			+ "replaces size on its own axis, so either can be given alone, but neither can "
			+ "be given alongside size."
		)
	],
	[
		"pts",
		(
			"Zone vertices as x,y pairs separated by semicolons: 0,0;24,0;24,24, in order "
			+ "around the shape. The polygon closes itself, so the first vertex is not "
			+ "repeated at the end."
		)
	],
	["dx, dy", "Vector components, from the tail at x,y. Give both or neither."],
	["mag", "Vector magnitude along h. Takes the place of dx / dy, and needs h to aim it."],
	["unit", "Suffix for the magnitude label an arrow carries, e.g. in/s."],
	["color", "Per-item color override, #rrggbb. Otherwise the class color is used."],
]

const EXAMPLE := [
	"// Java, inside your OpMode",
	'telemetry.addData("#f", "robot Robot x=%.1f y=%.1f h=%.1f", x, y, heading);',
	'telemetry.addData("#f", "zone Launch pts=0,0;48,0;48,24;24,36;0,24");',
	'telemetry.addData("#f", "vec Vel x=%.1f y=%.1f dx=%.1f dy=%.1f unit=in/s", x, y, vx, vy);',
	'telemetry.addData("#f", "point Target x=%.1f y=%.1f h=%.0f", tx, ty, ta);',
]

const GROUPING := [
	"for (Sample s : samples) {",
	'    telemetry.addData("#f", "point \\"Game Pieces\\" x=%.1f y=%.1f", s.x, s.y);',
	"}",
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
			"Drawing positional telemetry",
			(
				"The Field page draws annotations based on keys sent over ordinary "
				+ "telemetry. A line that starts with #f (or #field) is read as one drawing "
				+ "item and hidden from the displayed telemetry text."
			),
			_code(["#f <type> <class> <attr>=<value> ..."])
		)
	)
	box.add_child(
		_block(
			"Example",
			"Both addData and addLine work; the parser ignores the caption.",
			_code(EXAMPLE)
		)
	)
	box.add_child(
		_block(
			"Grouping",
			(
				"The class is the second token. Send like items under one class to show, "
				+ "hide and drop their heading arrows together. Quote a class name that "
				+ "contains spaces."
			),
			_code(GROUPING)
		)
	)
	box.add_child(
		_block(
			"Coordinates",
			(
				"Coordinate values are determined by the corners. The default places 0,0 "
				+ "at the bottom-left corner and 144,144 at the top-right, in inches. "
				+ "Settings -> Field Frame lets you edit the corner definitions."
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
			"Over-determined items",
			(
				"An item has to say what it is exactly once. Giving an attribute twice on a "
				+ "line, giving size together with l or w, or giving mag or h on a vec that "
				+ "already has dx and dy, is malformed."
			),
			null
		)
	)
	box.add_child(
		_block(
			"Malformed lines",
			(
				"A malformed line is skipped and displayed in regular telemetry instead. A "
				+ "line is malformed when it has an unknown type, a token that is not "
				+ "attribute=value, an unclosed quote, an attribute the type does not use, a "
				+ "repeated attribute, a missing required attribute, an unparsable number, a "
				+ "color that is not #rrggbb, or only one of dx and dy."
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
