class_name ThemeBuilder


static func _text_color(theme_spec: Dictionary) -> Color:
	if theme_spec.has(&"text"):
		return theme_spec[&"text"]
	return ColorMath.text_for(theme_spec[&"accent"], theme_spec[&"bg"])


static func default_theme() -> Theme:
	var theme := Theme.new()
	var default := ThemeDB.get_default_theme()
	var panel := _repadded(
		default.get_stylebox("panel", "PanelContainer"), ThemeTokens.PANEL_MARGIN
	)
	theme.set_stylebox("panel", "PanelContainer", panel)
	_register_bar_types(theme)
	theme.set_stylebox("panel", ThemeTokens.STATUSBAR_TYPE, panel.duplicate())
	for type in ThemeTokens.BUTTON_TYPES:
		for state in ["normal", "hover", "pressed", "focus", "disabled"]:
			theme.set_stylebox(
				state, type, _repadded(default.get_stylebox(state, type), ThemeTokens.BUTTON_MARGIN)
			)
	_set_colors(theme, ThemeTokens.STATUS_TYPE, ThemeTokens.STATUS_COLORS)
	_set_colors(theme, ThemeTokens.RADIAL_TYPE, ThemeTokens.DEFAULT_RADIAL_COLORS)
	return theme


static func _register_bar_types(theme: Theme) -> void:
	theme.set_type_variation(ThemeTokens.STATUSBAR_TYPE, &"PanelContainer")
	theme.set_type_variation(ThemeTokens.STATUSBAR_CARD_TYPE, &"PanelContainer")
	theme.set_stylebox("panel", ThemeTokens.STATUSBAR_CARD_TYPE, StyleBoxEmpty.new())
	for type: StringName in ThemeTokens.BAR_BUTTON_TYPES:
		theme.set_type_variation(type, ThemeTokens.BAR_BUTTON_TYPES[type])


static func _style_buttons(
	theme: Theme, types: Array, accent: Color, bg: Color, text: Color, dim: Color, highlight: Color
) -> void:
	var ink := ColorMath.ink(accent, bg, text)
	var on_accent := ColorMath.on_accent(accent, bg)
	var hover_pressed := (
		highlight if ColorMath.contrast(highlight, accent) >= ColorMath.AA_TEXT else on_accent
	)
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


static func apply_margins(box: StyleBox, margin: Vector4) -> void:
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
	apply_margins(box, margin)
	return box


static func accent_theme(theme_spec: Dictionary) -> Theme:
	var accent: Color = theme_spec[&"accent"]
	var bg: Color = theme_spec[&"bg"]
	var text := _text_color(theme_spec)
	var theme := Theme.new()
	var dim := Color(text.r, text.g, text.b, 0.35)

	var panel := StyleBoxFlat.new()
	panel.bg_color = bg
	apply_margins(panel, ThemeTokens.PANEL_MARGIN)
	for type in ["PanelContainer", "Panel"]:
		theme.set_stylebox("panel", type, panel.duplicate())

	_register_bar_types(theme)
	var pattern: Dictionary = theme_spec.get(&"pattern", {})
	theme.set_stylebox(
		"panel", ThemeTokens.STATUSBAR_TYPE, dot_box(pattern) if pattern else panel.duplicate()
	)
	if pattern:
		var card := StyleBoxFlat.new()
		card.bg_color = bg
		card.set_corner_radius_all(4)
		apply_margins(card, ThemeTokens.CARD_MARGIN)
		theme.set_stylebox("panel", ThemeTokens.STATUSBAR_CARD_TYPE, card)

	_style_buttons(theme, ThemeTokens.BUTTON_TYPES, accent, bg, text, dim, accent)
	if pattern:
		_style_buttons(
			theme, ThemeTokens.BAR_BUTTON_TYPES.keys(), pattern[&"dot"], bg, text, dim, accent
		)

	_style_popups(theme, accent, bg, text, dim)
	_style_inputs(theme, accent, bg, text, dim)
	_set_colors(theme, ThemeTokens.STATUS_TYPE, ColorMath.fit_all(ThemeTokens.STATUS_COLORS, bg))
	_set_colors(theme, ThemeTokens.RADIAL_TYPE, _radial_colors(accent, bg, text))
	return theme


static func _set_colors(theme: Theme, type: StringName, colors: Dictionary) -> void:
	for name: StringName in colors:
		theme.set_color(name, type, colors[name])


static func _radial_colors(accent: Color, bg: Color, text: Color) -> Dictionary:
	var slice := bg.lerp(accent, 0.12)
	var highlight := bg.lerp(accent, 0.55)
	var ink := ColorMath.ink(accent, bg, text)
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
	var ink := ColorMath.ink(accent, bg, text)
	var surface := _button_box(bg, ink.lerp(bg, 0.5))
	apply_margins(surface, ThemeTokens.PANEL_MARGIN)

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
	border.content_margin_top = ThemeTokens.WINDOW_BORDER_EXPAND.y
	_apply_expand(border, ThemeTokens.WINDOW_BORDER_EXPAND)
	theme.set_stylebox("embedded_border", "Window", border)
	var unfocused := border.duplicate()
	unfocused.border_color = ink.lerp(bg, 0.5)
	theme.set_stylebox("embedded_unfocused_border", "Window", unfocused)
	theme.set_color("title_color", "Window", text)


static func _set_check_icons(theme: Theme, accent: Color, dim: Color) -> void:
	var icons := {
		"radio_checked": IconFactory.bubble_icon(accent, true),
		"radio_unchecked": IconFactory.bubble_icon(accent, false),
		"radio_checked_disabled": IconFactory.bubble_icon(dim, true),
		"radio_unchecked_disabled": IconFactory.bubble_icon(dim, false),
		"checked": IconFactory.box_icon(accent, true),
		"unchecked": IconFactory.box_icon(accent, false),
		"checked_disabled": IconFactory.box_icon(dim, true),
		"unchecked_disabled": IconFactory.box_icon(dim, false),
	}
	for name in icons:
		theme.set_icon(name, "PopupMenu", icons[name])
		theme.set_icon(name, "CheckBox", icons[name])


static func _style_inputs(theme: Theme, accent: Color, bg: Color, text: Color, dim: Color) -> void:
	var ink := ColorMath.ink(accent, bg, text)
	var field := _button_box(bg.lerp(Color.BLACK, 0.25), ink.lerp(bg, 0.5))
	theme.set_stylebox("normal", "LineEdit", field)
	theme.set_stylebox("focus", "LineEdit", _button_box(bg.lerp(Color.BLACK, 0.25), ink))
	theme.set_stylebox("read_only", "LineEdit", _button_box(bg, dim))
	theme.set_color("font_color", "LineEdit", text)
	theme.set_color("font_selected_color", "LineEdit", ColorMath.on_accent(accent, bg))
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
		theme.set_icon("tick", type, IconFactory.tinted_icon(default.get_icon("tick", type), ink))
		for name in ["grabber", "grabber_highlight"]:
			theme.set_icon(name, type, IconFactory.tinted_icon(default.get_icon(name, type), ink))
		theme.set_icon(
			"grabber_disabled",
			type,
			IconFactory.tinted_icon(default.get_icon("grabber_disabled", type), dim)
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
	apply_margins(box, ThemeTokens.BUTTON_MARGIN)
	return box


static func dot_box(pattern: Dictionary) -> StyleBoxTexture:
	var box := StyleBoxTexture.new()
	box.texture = IconFactory.dot_tile(pattern[&"base"], pattern[&"dot"])
	box.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	box.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	apply_margins(box, ThemeTokens.PANEL_MARGIN)
	return box
