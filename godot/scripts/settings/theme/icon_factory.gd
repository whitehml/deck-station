class_name IconFactory


static func bubble_icon(outline: Color, mark: Color, filled: bool) -> ImageTexture:
	var img := _icon_canvas(outline)
	var size := ThemeTokens.ICON_SIZE * ThemeTokens.ICON_SUPERSAMPLE
	var center := Vector2(size, size) * 0.5
	var outer := 6.0 * ThemeTokens.ICON_SUPERSAMPLE
	var half_stroke := ThemeTokens.ICON_STROKE * ThemeTokens.ICON_SUPERSAMPLE * 0.5
	var inner := 3.0 * ThemeTokens.ICON_SUPERSAMPLE
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(center)
			if absf(d - outer) <= half_stroke:
				img.set_pixel(x, y, _opaque(outline))
			elif filled and d <= inner:
				img.set_pixel(x, y, _opaque(mark))
	return _icon_texture(img)


static func box_icon(outline: Color, mark: Color, checked: bool) -> ImageTexture:
	var img := _icon_canvas(outline)
	var size := ThemeTokens.ICON_SIZE * ThemeTokens.ICON_SUPERSAMPLE
	var half_stroke := ThemeTokens.ICON_STROKE * ThemeTokens.ICON_SUPERSAMPLE * 0.5
	var lo := 2.5 * ThemeTokens.ICON_SUPERSAMPLE
	var hi := 13.5 * ThemeTokens.ICON_SUPERSAMPLE
	var tick := (
		PackedVector2Array([Vector2(4.5, 8.0), Vector2(7.0, 10.5), Vector2(11.5, 5.0)])
		if checked
		else PackedVector2Array()
	)
	for y in size:
		for x in size:
			var p := Vector2(x + 0.5, y + 0.5)
			var edge := maxf(absf(p.x - (lo + hi) * 0.5), absf(p.y - (lo + hi) * 0.5))
			if absf(edge - (hi - lo) * 0.5) <= half_stroke:
				img.set_pixel(x, y, _opaque(outline))
				continue
			for i in range(tick.size() - 1):
				var a := tick[i] * ThemeTokens.ICON_SUPERSAMPLE
				var b := tick[i + 1] * ThemeTokens.ICON_SUPERSAMPLE
				if (
					Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p)
					<= half_stroke * 1.4
				):
					img.set_pixel(x, y, _opaque(mark))
					break
	return _icon_texture(img)


## Two dots on opposite quarters, so the tile repeats as a staggered grid. Both
## stay clear of the tile edge, which keeps the seams flat base color.
static func dot_tile(base: Color, dot: Color) -> ImageTexture:
	var size := ThemeTokens.DOT_TILE * ThemeTokens.ICON_SUPERSAMPLE
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	img.fill(base)
	var radius := ThemeTokens.DOT_RADIUS * ThemeTokens.ICON_SUPERSAMPLE
	var blended := base.blend(dot)
	var centers := [Vector2(size, size) * 0.25, Vector2(size, size) * 0.75]
	for y in size:
		for x in size:
			var p := Vector2(x + 0.5, y + 0.5)
			for center: Vector2 in centers:
				if p.distance_to(center) <= radius:
					img.set_pixel(x, y, blended)
	img.resize(ThemeTokens.DOT_TILE, ThemeTokens.DOT_TILE, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(img)


static func tinted_icon(source: Texture2D, color: Color) -> ImageTexture:
	var img: Image = source.get_image().duplicate()
	img.convert(Image.FORMAT_RGBA8)
	for y in img.get_height():
		for x in img.get_width():
			var alpha := img.get_pixel(x, y).a * color.a
			img.set_pixel(x, y, Color(color.r, color.g, color.b, alpha))
	return ImageTexture.create_from_image(img)


static func _icon_canvas(color: Color) -> Image:
	var size := ThemeTokens.ICON_SIZE * ThemeTokens.ICON_SUPERSAMPLE
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(color.r, color.g, color.b, 0.0))
	return img


static func _opaque(color: Color) -> Color:
	return Color(color.r, color.g, color.b, 1.0)


static func _icon_texture(img: Image) -> ImageTexture:
	img.resize(ThemeTokens.ICON_SIZE, ThemeTokens.ICON_SIZE, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(img)
