class_name RobotConfig
extends RefCounted

const HEADER := "<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>"

var root: Dictionary = element("Robot", {"type": "FirstInspires-FTC"})


static func element(tag: String, attrs: Dictionary = {}) -> Dictionary:
	return {"tag": tag, "attrs": attrs.duplicate(), "children": []}


static func parse(xml: String) -> RobotConfig:
	var config := RobotConfig.new()
	var parsed := _parse_root(xml)
	if not parsed.is_empty():
		config.root = parsed
	return config


static func new_empty() -> RobotConfig:
	return RobotConfig.new()


func to_xml() -> String:
	return HEADER + "\n" + _serialize(root, 0)


static func _parse_root(xml: String) -> Dictionary:
	var parser := XMLParser.new()
	if parser.open_buffer(xml.to_utf8_buffer()) != OK:
		return {}
	var stack: Array = []
	var found: Dictionary = {}
	while parser.read() == OK:
		match parser.get_node_type():
			XMLParser.NODE_ELEMENT:
				var tag := parser.get_node_name()
				if tag.begins_with("?"):  # skip the <?xml …?> declaration
					continue
				var node := {"tag": tag, "attrs": _read_attrs(parser), "children": []}
				if stack.is_empty():
					if found.is_empty():
						found = node
				else:
					stack.back()["children"].append(node)
				if not parser.is_empty():
					stack.push_back(node)
			XMLParser.NODE_ELEMENT_END:
				if not stack.is_empty():
					stack.pop_back()
	return found


static func _read_attrs(parser: XMLParser) -> Dictionary:
	var attrs := {}
	for i in parser.get_attribute_count():
		attrs[parser.get_attribute_name(i)] = parser.get_attribute_value(i)
	return attrs


static func _serialize(node: Dictionary, depth: int) -> String:
	var indent := "    ".repeat(depth)
	var tag := str(node.tag)
	var line := indent + "<" + tag
	for key in node.attrs:
		line += ' %s="%s"' % [key, _escape(str(node.attrs[key]))]
	var children: Array = node.get("children", [])
	if children.is_empty():
		return line + " />\n"
	line += ">\n"
	for child: Dictionary in children:
		line += _serialize(child, depth + 1)
	return line + indent + "</" + tag + ">\n"


static func _escape(value: String) -> String:
	return value.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace(
		'"', "&quot;"
	)
