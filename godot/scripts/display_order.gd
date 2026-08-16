class_name DisplayOrder


static func before(a: String, b: String) -> bool:
	return a.naturalnocasecmp_to(b) < 0


static func sorted(values: Array) -> Array:
	values.sort_custom(before)
	return values


static func sorted_by(rows: Array, key: String) -> Array:
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return before(a[key], b[key]))
	return rows
