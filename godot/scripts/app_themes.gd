class_name AppThemes

const NAMES := ["Godot", "Mars", "M.A.R.S.", "Botsburgh"]

const PANEL_MARGIN := Vector4(8, 6, 8, 6)
const BUTTON_MARGIN := Vector4(10, 6, 10, 6)

const BUTTON_TYPES := ["Button", "MenuButton", "OptionButton", "CheckBox", "CheckButton"]

const ICON_SIZE := 16
const ICON_SUPERSAMPLE := 4
const ICON_STROKE := 1.6

const BACKGROUND_COLORS := [
	Color(0.2, 0.2, 0.2, 1),  # Godot: default grey
	Color(0.12, 0.22, 0.14, 1),  # Mars: dark green
	Color(0.22, 0.12, 0.14, 1),  # M.A.R.S.: dark red
	Color(0.1, 0.11, 0.13, 1),  # Botsburgh: steel black
]


static func for_index(index: int) -> Theme:
	match index:
		1:  # Mars: bright green on near-black
			return _accent_theme(
				Color(0.2, 1.0, 0.35), Color(0.03, 0.09, 0.04), Color(0.85, 1.0, 0.88)
			)
		2:  # M.A.R.S.: red on black
			return _accent_theme(
				Color(1.0, 0.2, 0.35), Color(0.09, 0.03, 0.04), Color(1.0, 0.85, 0.88)
			)
		3:  # Botsburgh: Pittsburgh gold on black
			return _accent_theme(
				Color(1.0, 0.714, 0.071), Color(0.035, 0.04, 0.05), Color(0.93, 0.95, 0.97)
			)
		_:
			return _default_theme()


static func background_color(index: int) -> Color:
	if index < 0 or index >= BACKGROUND_COLORS.size():
		return BACKGROUND_COLORS[0]
	return BACKGROUND_COLORS[index]


static func _default_theme() -> Theme:
	var theme := Theme.new()
	var default := ThemeDB.get_default_theme()
	theme.set_stylebox(
		"panel",
		"PanelContainer",
		_repadded(default.get_stylebox("panel", "PanelContainer"), PANEL_MARGIN)
	)
	for type in BUTTON_TYPES:
		for state in ["normal", "hover", "pressed", "focus", "disabled"]:
			theme.set_stylebox(
				state, type, _repadded(default.get_stylebox(state, type), BUTTON_MARGIN)
			)
	return theme


static func _apply_margins(box: StyleBox, margin: Vector4) -> void:
	box.content_margin_left = margin.x
	box.content_margin_top = margin.y
	box.content_margin_right = margin.z
	box.content_margin_bottom = margin.w


static func _repadded(source: StyleBox, margin: Vector4) -> StyleBox:
	var box: StyleBox = source.duplicate()
	_apply_margins(box, margin)
	return box


static func _accent_theme(accent: Color, bg: Color, text: Color) -> Theme:
	var theme := Theme.new()
	var dim := Color(text.r, text.g, text.b, 0.35)

	var panel := StyleBoxFlat.new()
	panel.bg_color = bg
	_apply_margins(panel, PANEL_MARGIN)
	for type in ["PanelContainer", "Panel"]:
		theme.set_stylebox("panel", type, panel.duplicate())

	for type in BUTTON_TYPES:
		theme.set_color("font_color", type, text)
		theme.set_color("font_hover_color", type, accent)
		theme.set_color("font_focus_color", type, accent)
		theme.set_color("font_pressed_color", type, bg)
		theme.set_color("font_disabled_color", type, dim)

		theme.set_stylebox("normal", type, _button_box(bg, accent.lerp(bg, 0.5)))
		theme.set_stylebox("hover", type, _button_box(bg.lerp(accent, 0.15), accent))
		theme.set_stylebox("focus", type, _button_box(bg.lerp(accent, 0.15), accent))
		theme.set_stylebox("pressed", type, _button_box(accent, accent))
		theme.set_stylebox("disabled", type, _button_box(bg, Color(text.r, text.g, text.b, 0.2)))

	_style_popups(theme, accent, bg, text, dim)
	_style_inputs(theme, accent, bg, text, dim)
	return theme


static func _style_popups(theme: Theme, accent: Color, bg: Color, text: Color, dim: Color) -> void:
	var surface := _button_box(bg, accent.lerp(bg, 0.5))
	_apply_margins(surface, PANEL_MARGIN)

	for type in ["PopupMenu", "PopupPanel", "AcceptDialog", "TooltipPanel"]:
		theme.set_stylebox("panel", type, surface.duplicate())

	theme.set_stylebox("hover", "PopupMenu", _button_box(bg.lerp(accent, 0.15), accent))
	theme.set_color("font_color", "PopupMenu", text)
	theme.set_color("font_hover_color", "PopupMenu", accent)
	theme.set_color("font_accelerator_color", "PopupMenu", dim)
	theme.set_color("font_disabled_color", "PopupMenu", dim)
	theme.set_color("font_separator_color", "PopupMenu", accent)

	var separator := StyleBoxLine.new()
	separator.color = accent.lerp(bg, 0.5)
	theme.set_stylebox("separator", "PopupMenu", separator)
	theme.set_stylebox("labeled_separator_left", "PopupMenu", separator.duplicate())
	theme.set_stylebox("labeled_separator_right", "PopupMenu", separator.duplicate())

	_set_check_icons(theme, accent, dim)

	theme.set_color("font_color", "TooltipLabel", text)

	var border := _button_box(bg, accent)
	border.content_margin_top = 28
	theme.set_stylebox("embedded_border", "Window", border)
	var unfocused := border.duplicate()
	unfocused.border_color = accent.lerp(bg, 0.5)
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


static func _icon_canvas(color: Color) -> Image:
	var size := ICON_SIZE * ICON_SUPERSAMPLE
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(color.r, color.g, color.b, 0.0))
	return img


static func _icon_texture(img: Image) -> ImageTexture:
	img.resize(ICON_SIZE, ICON_SIZE, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(img)


static func _style_inputs(theme: Theme, accent: Color, bg: Color, text: Color, dim: Color) -> void:
	var field := _button_box(bg.lerp(Color.BLACK, 0.25), accent.lerp(bg, 0.5))
	theme.set_stylebox("normal", "LineEdit", field)
	theme.set_stylebox("focus", "LineEdit", _button_box(bg.lerp(Color.BLACK, 0.25), accent))
	theme.set_stylebox("read_only", "LineEdit", _button_box(bg, dim))
	theme.set_color("font_color", "LineEdit", text)
	theme.set_color("font_selected_color", "LineEdit", bg)
	theme.set_color("font_uneditable_color", "LineEdit", dim)
	theme.set_color("font_placeholder_color", "LineEdit", dim)
	theme.set_color("caret_color", "LineEdit", accent)
	theme.set_color("selection_color", "LineEdit", accent)

	theme.set_color("font_color", "Label", text)
	theme.set_color("default_color", "RichTextLabel", text)

	var track := StyleBoxFlat.new()
	track.bg_color = bg.lerp(Color.BLACK, 0.25)
	track.set_corner_radius_all(3)
	var grabber := StyleBoxFlat.new()
	grabber.bg_color = accent.lerp(bg, 0.4)
	grabber.set_corner_radius_all(3)
	var grabber_hot := grabber.duplicate() as StyleBoxFlat
	grabber_hot.bg_color = accent
	for type in ["VScrollBar", "HScrollBar"]:
		theme.set_stylebox("scroll", type, track.duplicate())
		theme.set_stylebox("grabber", type, grabber.duplicate())
		theme.set_stylebox("grabber_highlight", type, grabber_hot.duplicate())
		theme.set_stylebox("grabber_pressed", type, grabber_hot.duplicate())
	for type in ["VSlider", "HSlider"]:
		theme.set_stylebox("slider", type, track.duplicate())
		theme.set_stylebox("grabber_area", type, grabber.duplicate())
		theme.set_stylebox("grabber_area_highlight", type, grabber_hot.duplicate())

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
