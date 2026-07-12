class_name AppThemes

const NAMES := ["Godot", "Mars", "M.A.R.S."]

const PANEL_MARGIN := Vector4(8, 6, 8, 6)
const BUTTON_MARGIN := Vector4(10, 6, 10, 6)

const BACKGROUND_COLORS := [
	Color(0.2, 0.2, 0.2, 1),  # Godot: default grey
	Color(0.12, 0.22, 0.14, 1),  # Mars: dark green
	Color(0.22, 0.12, 0.14, 1),  # M.A.R.S.: dark red
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
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		theme.set_stylebox(
			state, "Button", _repadded(default.get_stylebox(state, "Button"), BUTTON_MARGIN)
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

	var panel := StyleBoxFlat.new()
	panel.bg_color = bg
	_apply_margins(panel, PANEL_MARGIN)
	theme.set_stylebox("panel", "PanelContainer", panel)

	theme.set_color("font_color", "Button", text)
	theme.set_color("font_hover_color", "Button", accent)
	theme.set_color("font_focus_color", "Button", accent)
	theme.set_color("font_pressed_color", "Button", bg)
	theme.set_color("font_disabled_color", "Button", Color(text.r, text.g, text.b, 0.35))

	theme.set_stylebox("normal", "Button", _button_box(bg, accent.lerp(bg, 0.5)))
	theme.set_stylebox("hover", "Button", _button_box(bg.lerp(accent, 0.15), accent))
	theme.set_stylebox("focus", "Button", _button_box(bg.lerp(accent, 0.15), accent))
	theme.set_stylebox("pressed", "Button", _button_box(accent, accent))
	theme.set_stylebox("disabled", "Button", _button_box(bg, Color(text.r, text.g, text.b, 0.2)))
	return theme


static func _button_box(fill: Color, border: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(4)
	_apply_margins(box, BUTTON_MARGIN)
	return box
