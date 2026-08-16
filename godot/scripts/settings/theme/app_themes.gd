class_name AppThemes

const PANEL_MARGIN := Vector4(8, 6, 8, 6)
const BUTTON_MARGIN := Vector4(10, 6, 10, 6)

## Embedded windows draw their border over the client rect only, so the frame has
## to expand outward to reach the title bar strip above it.
const WINDOW_BORDER_EXPAND := Vector4(8, 32, 8, 6)

const BUTTON_TYPES := ["Button", "MenuButton", "OptionButton", "CheckBox", "CheckButton"]

const ICON_SIZE := 16
const ICON_SUPERSAMPLE := 4
const ICON_STROKE := 1.6

## Custom theme types carrying the app's semantic colors, so widgets that paint
## themselves resolve them through normal theme propagation instead of holding
## their own literals.
const STATUS_TYPE := &"Status"
const RADIAL_TYPE := &"RadialMenu"

const STATUSBAR_TYPE := &"StatusBar"
const STATUSBAR_CARD_TYPE := &"StatusBarCard"
const BAR_BUTTON_TYPES := {&"StatusBarButton": &"Button", &"StatusBarMenuButton": &"MenuButton"}
const CARD_MARGIN := Vector4(12, 4, 12, 4)

const DOT_TILE := 24
const DOT_RADIUS := 5.0

const AA_TEXT := 4.5
const FIT_STEPS := 40

## How far a fitted color may drift from the one it started as, measured as
## contrast between the two, before it counts as a different color entirely.
const HUE_DRIFT := 2.0

## Signal colors, shared by every theme so a phase reads the same regardless of
## palette. The hues are the contract; `_fit()` moves their lightness per theme
## so they survive a light or mid-luminance panel.
const STATUS_COLORS := {
	&"idle": Color(0.55, 0.75, 1.0),
	&"init": Color(0.4, 0.9, 0.4),
	&"running": Color(1, 0.3, 0.3),
	&"neutral": Color.WHITE,
	&"ok": Color.GREEN_YELLOW,
	&"warn": Color.ORANGE,
	&"connected": Color.GREEN_YELLOW,
	&"disconnected": Color.INDIAN_RED,
	&"endgame": Color.ORANGE_RED,
	&"slot1": Color.GREEN_YELLOW,
	&"slot2": Color.ORANGE,
}

const DEFAULT_RADIAL_COLORS := {
	&"slice": Color(0.16, 0.19, 0.24, 0.92),
	&"slice_disabled": Color(0.10, 0.11, 0.13, 0.92),
	&"slice_highlight": Color(0.20, 0.45, 0.60, 0.95),
	&"rim": Color(0.6, 0.75, 0.85, 0.5),
	&"center": Color(0.05, 0.06, 0.08, 0.9),
	&"label": Color(1, 1, 1),
	&"cursor": Color(1, 1, 1),
}

## Every theme lives here and nowhere else. A theme is `accent` + `bg` (panels
## and button fills) + `text`; drop `text` and it is filled in by the two-color
## rule in `ThemeBuilder`. `backdrop` is the root fill behind the panels and
## rule in `_text_color()`. `backdrop` is the root fill behind the panels and
## defaults to `bg`; `pattern` swaps the top bar for a tiled polka-dot fill.
## The entry with no `accent` is Godot's own theme, left alone.
## Order is persisted in settings.cfg as an index, so only append.
const THEMES := [
	{&"name": "Godot", &"backdrop": Color(0.2, 0.2, 0.2)},
	{
		&"name": "Mars",
		&"accent": Color(0.2, 1.0, 0.35),
		&"bg": Color(0.03, 0.09, 0.04),
		&"text": Color(0.85, 1.0, 0.88),
		&"backdrop": Color(0.12, 0.22, 0.14),
	},
	{
		&"name": "M.A.R.S.",
		&"accent": Color(1.0, 0.2, 0.35),
		&"bg": Color(0.09, 0.03, 0.04),
		&"text": Color(1.0, 0.85, 0.88),
		&"backdrop": Color(0.22, 0.12, 0.14),
	},
	{
		&"name": "Botsburgh",
		&"accent": Color(1.0, 0.714, 0.071),
		&"bg": Color(0.035, 0.04, 0.05),
		&"text": Color(0.93, 0.95, 0.97),
		&"backdrop": Color(0.1, 0.11, 0.13),
	},
	{
		&"name": "Hippo",
		&"accent": Color(0.16, 0.28, 0.62),
		&"bg": Color(0.86, 0.76, 0.79),
		&"text": Color(0.08, 0.13, 0.32),
		&"backdrop": Color(0.79, 0.69, 0.72),
	},
	{
		&"name": "Fayette",
		&"accent": Color(0.004, 0.639, 0.365),
		&"bg": Color.WHITE,
		&"backdrop": Color(0.88, 0.91, 0.89),
	},
	{
		&"name": "G.o.S.",
		&"accent": Color(0.784, 0.071, 0.106),
		&"bg": Color(0.106, 0.353, 0.451),
		&"text": Color.WHITE,
		&"backdrop": Color(0.0, 0.455, 0.656),
		&"pattern": {&"base": Color(0.784, 0.071, 0.106), &"dot": Color.WHITE},
	},
	{
		&"name": "Tiger",
		&"accent": Color(0.957, 0.482, 0.125),
		&"bg": Color.WHITE,
		&"backdrop": Color(0.93, 0.9, 0.87),
	},
	{
		&"name": "Titanium",
		&"accent": Color.WHITE,
		&"bg": Color(0.663, 0.682, 0.69),
		&"backdrop": Color(0.557, 0.58, 0.592),
	},
]

const MONO_THIRD := Color(0.5, 0.5, 0.5)


static func spec(index: int) -> Dictionary:
	if index < 0 or index >= THEMES.size():
		return THEMES[0]
	return THEMES[index]


static func for_index(index: int) -> Theme:
	var theme_spec := spec(index)
	if not theme_spec.has(&"accent"):
		return _default_theme()
	return _accent_theme(theme_spec)


static func background_color(index: int) -> Color:
	var theme_spec := spec(index)
	if theme_spec.has(&"backdrop"):
		return theme_spec[&"backdrop"]
	return theme_spec[&"bg"]


static func _text_color(theme_spec: Dictionary) -> Color:
	if theme_spec.has(&"text"):
		return theme_spec[&"text"]
	var accent: Color = theme_spec[&"accent"]
	var bg: Color = theme_spec[&"bg"]
	if _is_mono(accent) and _is_mono(bg):
		return MONO_THIRD
	return Color.BLACK if bg.get_luminance() > 0.5 else Color.WHITE


static func _is_mono(color: Color) -> bool:
	return color.get_luminance() > 0.97 or color.get_luminance() < 0.03


static func _luminance(color: Color) -> float:
	var lin := color.srgb_to_linear()
	return 0.2126 * lin.r + 0.7152 * lin.g + 0.0722 * lin.b


static func _contrast(a: Color, b: Color) -> float:
	var la := _luminance(a)
	var lb := _luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


static func _fit(color: Color, bg: Color, target := AA_TEXT) -> Color:
	if _contrast(color, bg) >= target:
		return color
	var anchor := Color.BLACK if _luminance(bg) > 0.18 else Color.WHITE
	for step in range(1, FIT_STEPS + 1):
		var moved := color.lerp(anchor, float(step) / FIT_STEPS)
		if _contrast(moved, bg) >= target:
			return moved
	return anchor


static func _fitted_status(bg: Color) -> Dictionary:
	var fitted := {}
	for name: StringName in STATUS_COLORS:
		fitted[name] = _fit(STATUS_COLORS[name], bg)
	return fitted


static func _ink(accent: Color, bg: Color, text: Color) -> Color:
	if _contrast(accent, bg) >= AA_TEXT:
		return accent
	var fitted := _fit(accent, bg)
	return fitted if _contrast(fitted, accent) <= HUE_DRIFT else text


static func _on_accent(accent: Color, bg: Color) -> Color:
	if _contrast(bg, accent) >= AA_TEXT:
		return bg
	if _contrast(Color.WHITE, accent) >= _contrast(Color.BLACK, accent):
		return Color.WHITE
	return Color.BLACK


static func _default_theme() -> Theme:
	var theme := Theme.new()
	var default := ThemeDB.get_default_theme()
	var panel := _repadded(default.get_stylebox("panel", "PanelContainer"), PANEL_MARGIN)
	theme.set_stylebox("panel", "PanelContainer", panel)
	_register_bar_types(theme)
	theme.set_stylebox("panel", STATUSBAR_TYPE, panel.duplicate())
	for type in BUTTON_TYPES:
		for state in ["normal", "hover", "pressed", "focus", "disabled"]:
			theme.set_stylebox(
				state, type, _repadded(default.get_stylebox(state, type), BUTTON_MARGIN)
			)
	_set_colors(theme, STATUS_TYPE, STATUS_COLORS)
	_set_colors(theme, RADIAL_TYPE, DEFAULT_RADIAL_COLORS)
	return theme


static func _register_bar_types(theme: Theme) -> void:
	theme.set_type_variation(STATUSBAR_TYPE, &"PanelContainer")
	theme.set_type_variation(STATUSBAR_CARD_TYPE, &"PanelContainer")
	theme.set_stylebox("panel", STATUSBAR_CARD_TYPE, StyleBoxEmpty.new())
	for type: StringName in BAR_BUTTON_TYPES:
		theme.set_type_variation(type, BAR_BUTTON_TYPES[type])


static func _style_buttons(
	theme: Theme, types: Array, accent: Color, bg: Color, text: Color, dim: Color, highlight: Color
) -> void:
	var ink := _ink(accent, bg, text)
	var on_accent := _on_accent(accent, bg)
	var hover_pressed := highlight if _contrast(highlight, accent) >= AA_TEXT else on_accent
	for type in types:
		theme.set_color("font_color", type, text)
		theme.set_color("font_hover_color", type, ink)
		theme.set_color("font_focus_color", type, ink)
		theme.set_color("font_pressed_color", type, on_accent)
		theme.set_color("font_hover_pressed_color", type, hover_pressed)
		theme.set_color("font_disabled_color", type, dim)

		theme.set_stylebox("normal", type, _button_box(bg, ink.lerp(bg, 0.5)))
		theme.set_stylebox("hover", type, _button_box(bg.lerp(accent, 0.15), ink))
		theme.set_stylebox("focus", type, _button_box(bg.lerp(accent, 0.15), ink))
		theme.set_stylebox("pressed", type, _button_box(accent, accent))
		theme.set_stylebox("disabled", type, _button_box(bg, Color(text.r, text.g, text.b, 0.2)))


static func _apply_margins(box: StyleBox, margin: Vector4) -> void:
	box.content_margin_left = margin.x
	box.content_margin_top = margin.y
	box.content_margin_right = margin.z
	box.content_margin_bottom = margin.w


static func _apply_expand(box: StyleBoxFlat, margin: Vector4) -> void:
	box.expand_margin_left = margin.x
	box.expand_margin_top = margin.y
	box.expand_margin_right = margin.z
	box.expand_margin_bottom = margin.w


static func _repadded(source: StyleBox, margin: Vector4) -> StyleBox:
	var box: StyleBox = source.duplicate()
	_apply_margins(box, margin)
	return box


static func _accent_theme(theme_spec: Dictionary) -> Theme:
	var accent: Color = theme_spec[&"accent"]
	var bg: Color = theme_spec[&"bg"]
	var text := _text_color(theme_spec)
	var theme := Theme.new()
	var dim := Color(text.r, text.g, text.b, 0.35)

	var panel := StyleBoxFlat.new()
	panel.bg_color = bg
	_apply_margins(panel, PANEL_MARGIN)
	for type in ["PanelContainer", "Panel"]:
		theme.set_stylebox("panel", type, panel.duplicate())

	_register_bar_types(theme)
	var pattern: Dictionary = theme_spec.get(&"pattern", {})
	theme.set_stylebox("panel", STATUSBAR_TYPE, _dot_box(pattern) if pattern else panel.duplicate())
	if pattern:
		var card := StyleBoxFlat.new()
		card.bg_color = bg
		card.set_corner_radius_all(4)
		_apply_margins(card, CARD_MARGIN)
		theme.set_stylebox("panel", STATUSBAR_CARD_TYPE, card)

	_style_buttons(theme, BUTTON_TYPES, accent, bg, text, dim, accent)
	if pattern:
		_style_buttons(theme, BAR_BUTTON_TYPES.keys(), pattern[&"dot"], bg, text, dim, accent)

	_style_popups(theme, accent, bg, text, dim)
	_style_inputs(theme, accent, bg, text, dim)
	_set_colors(theme, STATUS_TYPE, _fitted_status(bg))
	_set_colors(theme, RADIAL_TYPE, _radial_colors(accent, bg, text))
	return theme


static func _set_colors(theme: Theme, type: StringName, colors: Dictionary) -> void:
	for name: StringName in colors:
		theme.set_color(name, type, colors[name])


static func _radial_colors(accent: Color, bg: Color, text: Color) -> Dictionary:
	var slice := bg.lerp(accent, 0.12)
	var highlight := bg.lerp(accent, 0.55)
	var ink := _ink(accent, bg, text)
	return {
		&"slice": Color(slice.r, slice.g, slice.b, 0.92),
		&"slice_disabled": Color(bg.r, bg.g, bg.b, 0.92),
		&"slice_highlight": Color(highlight.r, highlight.g, highlight.b, 0.95),
		&"rim": Color(ink.r, ink.g, ink.b, 0.5),
		&"center": Color(bg.r, bg.g, bg.b, 0.9),
		&"label": text,
		&"cursor": ink,
	}


static func _style_popups(theme: Theme, accent: Color, bg: Color, text: Color, dim: Color) -> void:
	var ink := _ink(accent, bg, text)
	var surface := _button_box(bg, ink.lerp(bg, 0.5))
	_apply_margins(surface, PANEL_MARGIN)

	for type in ["PopupMenu", "PopupPanel", "TooltipPanel"]:
		theme.set_stylebox("panel", type, surface.duplicate())

	var dialog_panel := surface.duplicate() as StyleBoxFlat
	dialog_panel.set_border_width_all(0)
	dialog_panel.set_corner_radius_all(0)
	theme.set_stylebox("panel", "AcceptDialog", dialog_panel)

	theme.set_stylebox("hover", "PopupMenu", _button_box(bg.lerp(accent, 0.15), accent))
	theme.set_color("font_color", "PopupMenu", text)
	theme.set_color("font_hover_color", "PopupMenu", ink)
	theme.set_color("font_accelerator_color", "PopupMenu", dim)
	theme.set_color("font_disabled_color", "PopupMenu", dim)
	theme.set_color("font_separator_color", "PopupMenu", ink)

	var separator := StyleBoxLine.new()
	separator.color = ink.lerp(bg, 0.5)
	theme.set_stylebox("separator", "PopupMenu", separator)
	theme.set_stylebox("labeled_separator_left", "PopupMenu", separator.duplicate())
	theme.set_stylebox("labeled_separator_right", "PopupMenu", separator.duplicate())

	_set_check_icons(theme, ink, dim)

	theme.set_color("font_color", "TooltipLabel", text)

	var border := _button_box(bg, ink)
	border.content_margin_top = WINDOW_BORDER_EXPAND.y
	_apply_expand(border, WINDOW_BORDER_EXPAND)
	theme.set_stylebox("embedded_border", "Window", border)
	var unfocused := border.duplicate()
	unfocused.border_color = ink.lerp(bg, 0.5)
	theme.set_stylebox("embedded_unfocused_border", "Window", unfocused)
	theme.set_color("title_color", "Window", text)


static func _set_check_icons(theme: Theme, accent: Color, dim: Color) -> void:
	var icons := {
		"radio_checked": _bubble_icon(accent, true),
		"radio_unchecked": _bubble_icon(accent, false),
		"radio_checked_disabled": _bubble_icon(dim, true),
		"radio_unchecked_disabled": _bubble_icon(dim, false),
		"checked": _box_icon(accent, true),
		"unchecked": _box_icon(accent, false),
		"checked_disabled": _box_icon(dim, true),
		"unchecked_disabled": _box_icon(dim, false),
	}
	for name in icons:
		theme.set_icon(name, "PopupMenu", icons[name])
		theme.set_icon(name, "CheckBox", icons[name])


static func _bubble_icon(color: Color, filled: bool) -> ImageTexture:
	var img := _icon_canvas(color)
	var size := ICON_SIZE * ICON_SUPERSAMPLE
	var center := Vector2(size, size) * 0.5
	var outer := 6.0 * ICON_SUPERSAMPLE
	var half_stroke := ICON_STROKE * ICON_SUPERSAMPLE * 0.5
	var inner := 3.0 * ICON_SUPERSAMPLE
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(center)
			if absf(d - outer) <= half_stroke or (filled and d <= inner):
				img.set_pixel(x, y, Color(color.r, color.g, color.b, 1.0))
	return _icon_texture(img)


static func _box_icon(color: Color, checked: bool) -> ImageTexture:
	var img := _icon_canvas(color)
	var size := ICON_SIZE * ICON_SUPERSAMPLE
	var half_stroke := ICON_STROKE * ICON_SUPERSAMPLE * 0.5
	var lo := 2.5 * ICON_SUPERSAMPLE
	var hi := 13.5 * ICON_SUPERSAMPLE
	var tick := (
		PackedVector2Array([Vector2(4.5, 8.0), Vector2(7.0, 10.5), Vector2(11.5, 5.0)])
		if checked
		else PackedVector2Array()
	)
	for y in size:
		for x in size:
			var p := Vector2(x + 0.5, y + 0.5)
			var edge := maxf(absf(p.x - (lo + hi) * 0.5), absf(p.y - (lo + hi) * 0.5))
			var on := absf(edge - (hi - lo) * 0.5) <= half_stroke
			for i in range(tick.size() - 1):
				var a := tick[i] * ICON_SUPERSAMPLE
				var b := tick[i + 1] * ICON_SUPERSAMPLE
				on = (
					on
					or (
						Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p)
						<= (half_stroke * 1.4)
					)
				)
			if on:
				img.set_pixel(x, y, Color(color.r, color.g, color.b, 1.0))
	return _icon_texture(img)


static func _dot_box(pattern: Dictionary) -> StyleBoxTexture:
	var box := StyleBoxTexture.new()
	box.texture = _dot_tile(pattern[&"base"], pattern[&"dot"])
	box.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	box.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	_apply_margins(box, PANEL_MARGIN)
	return box


## Two dots on opposite quarters, so the tile repeats as a staggered grid. Both
## stay clear of the tile edge, which keeps the seams flat base color.
static func _dot_tile(base: Color, dot: Color) -> ImageTexture:
	var size := DOT_TILE * ICON_SUPERSAMPLE
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	img.fill(base)
	var radius := DOT_RADIUS * ICON_SUPERSAMPLE
	var blended := base.blend(dot)
	var centers := [Vector2(size, size) * 0.25, Vector2(size, size) * 0.75]
	for y in size:
		for x in size:
			var p := Vector2(x + 0.5, y + 0.5)
			for center: Vector2 in centers:
				if p.distance_to(center) <= radius:
					img.set_pixel(x, y, blended)
	img.resize(DOT_TILE, DOT_TILE, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(img)


static func _tinted_icon(source: Texture2D, color: Color) -> ImageTexture:
	var img: Image = source.get_image().duplicate()
	img.convert(Image.FORMAT_RGBA8)
	for y in img.get_height():
		for x in img.get_width():
			var alpha := img.get_pixel(x, y).a * color.a
			img.set_pixel(x, y, Color(color.r, color.g, color.b, alpha))
	return ImageTexture.create_from_image(img)


static func _icon_canvas(color: Color) -> Image:
	var size := ICON_SIZE * ICON_SUPERSAMPLE
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(color.r, color.g, color.b, 0.0))
	return img


static func _icon_texture(img: Image) -> ImageTexture:
	img.resize(ICON_SIZE, ICON_SIZE, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(img)


static func _style_inputs(theme: Theme, accent: Color, bg: Color, text: Color, dim: Color) -> void:
	var ink := _ink(accent, bg, text)
	var field := _button_box(bg.lerp(Color.BLACK, 0.25), ink.lerp(bg, 0.5))
	theme.set_stylebox("normal", "LineEdit", field)
	theme.set_stylebox("focus", "LineEdit", _button_box(bg.lerp(Color.BLACK, 0.25), ink))
	theme.set_stylebox("read_only", "LineEdit", _button_box(bg, dim))
	theme.set_color("font_color", "LineEdit", text)
	theme.set_color("font_selected_color", "LineEdit", _on_accent(accent, bg))
	theme.set_color("font_uneditable_color", "LineEdit", dim)
	theme.set_color("font_placeholder_color", "LineEdit", dim)
	theme.set_color("caret_color", "LineEdit", ink)
	theme.set_color("selection_color", "LineEdit", accent)

	theme.set_color("font_color", "Label", text)
	theme.set_color("default_color", "RichTextLabel", text)

	var track := StyleBoxFlat.new()
	track.bg_color = bg.lerp(Color.BLACK, 0.25)
	track.set_corner_radius_all(3)
	var grabber := StyleBoxFlat.new()
	grabber.bg_color = ink.lerp(bg, 0.4)
	grabber.set_corner_radius_all(3)
	var grabber_hot := grabber.duplicate() as StyleBoxFlat
	grabber_hot.bg_color = ink
	for type in ["VScrollBar", "HScrollBar"]:
		theme.set_stylebox("scroll", type, track.duplicate())
		theme.set_stylebox("grabber", type, grabber.duplicate())
		theme.set_stylebox("grabber_highlight", type, grabber_hot.duplicate())
		theme.set_stylebox("grabber_pressed", type, grabber_hot.duplicate())
	var default := ThemeDB.get_default_theme()
	for type in ["VSlider", "HSlider"]:
		theme.set_stylebox("slider", type, track.duplicate())
		theme.set_stylebox("grabber_area", type, grabber.duplicate())
		theme.set_stylebox("grabber_area_highlight", type, grabber_hot.duplicate())
		theme.set_icon("tick", type, _tinted_icon(default.get_icon("tick", type), ink))
		for name in ["grabber", "grabber_highlight"]:
			theme.set_icon(name, type, _tinted_icon(default.get_icon(name, type), ink))
		theme.set_icon(
			"grabber_disabled", type, _tinted_icon(default.get_icon("grabber_disabled", type), dim)
		)

	theme.set_constant("modulate_arrow", "OptionButton", 1)

	theme.set_stylebox("background", "ProgressBar", track.duplicate())
	theme.set_stylebox("fill", "ProgressBar", grabber_hot.duplicate())
	theme.set_color("font_color", "ProgressBar", text)


static func _button_box(fill: Color, border: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(4)
	_apply_margins(box, BUTTON_MARGIN)
	return box
