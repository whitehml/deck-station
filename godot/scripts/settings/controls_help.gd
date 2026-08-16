extends DocDialog

## Read-only controls reference, opened from Settings -> Controls. Two pages:
## the driver-station bindings, and a keyboard map of the gamepad emulation.

enum { ANY, DECK, DESKTOP }

const KeyboardMap := preload("res://scripts/settings/keyboard_map.gd")

## Braced text is the Deck's grip name for the same key — dropped off the Deck.
const DRIVER_STATION := [
	["F3 {R4} tap", "E-STOP", DECK],
	[["F3 tap", "Delete"], "E-STOP", DESKTOP],
	["F3 {R4} hold", "Send gamepad output to the UI instead of the robot.", ANY],
	["Space", "Freeze / unfreeze the telemetry graph and the field overlay.", ANY],
	["F1 / F2 {L4 / L5}", "Page-contextual — see the table below.", ANY],
	["F4 {R5} tap", "Swap gamepad slots.", DECK],
	["F4 {R5} hold", "Slot-swap radial: 1 left, 2 right.", DECK],
	["Trackpads", "Cursor; either pad clicks as left-click.", DECK],
	["Touchscreen", "Full interaction.", DECK],
]

const NAVIGATION := [
	["Sticks / D-pad", "Move focus.", ANY],
	["L2 / R2 triggers", "Step the page tabs left / right.", DECK],
	[["L2 / R2 triggers", "Keyboard Q / E"], "Step the page tabs left / right.", DESKTOP],
	["Gamepad A / X", "Confirm / cancel.", ANY],
	["Start + A / Start + B", "Claim robot slot 1 / 2 for that controller.", DESKTOP],
	["[ / ]", "Claim robot slot 1 / 2 for the keyboard.", DESKTOP],
]

const BY_PAGE := [
	[
		"Drive",
		"Step the left pane's source; hold for its radial.",
		"Same, for the right pane.",
		ANY
	],
	["Graphs", "Shrink the graph's time window.", "Grow the time window.", ANY],
	["Field", "Show / hide every overlay class.", "Show / hide every heading arrow.", ANY],
	[
		"OpModes",
		"Advance the run phase (INIT → START → STOP).",
		"Cycle the group filter; hold for the group radial.",
		ANY
	],
	["Config", "Select the previous config.", "Select the next config.", ANY],
]


func _ready() -> void:
	title = "Controls"
	super()


func _pages() -> Array:
	var pages: Array = [_driver_station_page()]
	if not GamepadBridge.is_steam_deck():
		pages.append(_keyboard_page())
	return pages


func _driver_station_page() -> Control:
	var page := _page("Driver Station")
	var box := _column(page)
	box.add_child(_section("Driver station", ["Input", "Action"], DRIVER_STATION))
	box.add_child(_section("Navigating the UI", ["Input", "Action"], NAVIGATION))
	box.add_child(_section("F1 / F2 by page", ["Page", "F1 {L4}", "F2 {L5}"], BY_PAGE))
	return page


func _keyboard_page() -> Control:
	var page := _page("Keyboard", false)
	var box := _column(page)

	var map := KeyboardMap.new()
	map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map.custom_minimum_size = Vector2(0, 260)
	box.add_child(map)

	box.add_child(_legend())
	return page


func _legend() -> Control:
	var row := HFlowContainer.new()
	row.add_theme_constant_override(&"h_separation", COLUMN_SEPARATION)
	row.add_theme_constant_override(&"v_separation", ROW_SEPARATION)
	row.alignment = FlowContainer.ALIGNMENT_CENTER
	for entry: Array in KeyboardMap.LEGEND:
		var item := HBoxContainer.new()
		item.add_theme_constant_override(&"separation", ROW_SEPARATION)

		var swatch := ColorRect.new()
		swatch.color = KeyboardMap.ROLE_COLORS[entry[0]]
		swatch.custom_minimum_size = Vector2(14, 14)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		item.add_child(swatch)

		var label := Label.new()
		label.text = str(entry[1])
		item.add_child(label)
		row.add_child(item)
	return row


func _applies(host: int) -> bool:
	return host == ANY or (host == DECK) == GamepadBridge.is_steam_deck()


func _host_text(text: String) -> String:
	if GamepadBridge.is_steam_deck():
		return text.replace("{", "(").replace("}", ")")
	return RegEx.create_from_string(" ?\\{[^}]*\\}").sub(text, "", true)
