class_name ColorMath

const AA_TEXT := 4.5
const FIT_STEPS := 40
const HUE_DRIFT := 2.0
const MONO_THIRD := Color(0.5, 0.5, 0.5)


static func is_mono(color: Color) -> bool:
	return color.get_luminance() > 0.97 or color.get_luminance() < 0.03


static func luminance(color: Color) -> float:
	var lin := color.srgb_to_linear()
	return 0.2126 * lin.r + 0.7152 * lin.g + 0.0722 * lin.b


static func contrast(a: Color, b: Color) -> float:
	var la := luminance(a)
	var lb := luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


static func fit(color: Color, bg: Color, target := AA_TEXT) -> Color:
	if contrast(color, bg) >= target:
		return color
	var anchor := Color.BLACK if luminance(bg) > 0.18 else Color.WHITE
	for step in range(1, FIT_STEPS + 1):
		var moved := color.lerp(anchor, float(step) / FIT_STEPS)
		if contrast(moved, bg) >= target:
			return moved
	return anchor


static func fit_all(colors: Dictionary, bg: Color) -> Dictionary:
	var fitted := {}
	for name: StringName in colors:
		fitted[name] = fit(colors[name], bg)
	return fitted


static func ink(accent: Color, bg: Color, text: Color) -> Color:
	if contrast(accent, bg) >= AA_TEXT:
		return accent
	var fitted := fit(accent, bg)
	return fitted if contrast(fitted, accent) <= HUE_DRIFT else text


static func on_accent(accent: Color, bg: Color) -> Color:
	if contrast(bg, accent) >= AA_TEXT:
		return bg
	if contrast(Color.WHITE, accent) >= contrast(Color.BLACK, accent):
		return Color.WHITE
	return Color.BLACK


static func text_for(accent: Color, bg: Color) -> Color:
	if is_mono(accent) and is_mono(bg):
		return MONO_THIRD
	return Color.BLACK if bg.get_luminance() > 0.5 else Color.WHITE
