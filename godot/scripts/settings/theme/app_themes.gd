class_name AppThemes

## Every theme lives here and nowhere else. A theme is `accent` + `bg` (panels
## and button fills) + `text`; drop `text` and it is filled in by the two-color
## rule in `ThemeBuilder`. `backdrop` is the root fill behind the panels and
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


static func spec(index: int) -> Dictionary:
	if index < 0 or index >= THEMES.size():
		return THEMES[0]
	return THEMES[index]


static func for_index(index: int) -> Theme:
	var theme_spec := spec(index)
	if not theme_spec.has(&"accent"):
		return ThemeBuilder.default_theme()
	return ThemeBuilder.accent_theme(theme_spec)


static func background_color(index: int) -> Color:
	var theme_spec := spec(index)
	if theme_spec.has(&"backdrop"):
		return theme_spec[&"backdrop"]
	return theme_spec[&"bg"]
