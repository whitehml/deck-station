class_name DeviceNaming

const XML_TAG_PATTERN := "^[A-Za-z_:][A-Za-z_:0-9\\-.]*$"
const XML_TAG_HINT := "Start with a letter, _ or :, then letters, digits, _ : - or ."

static var _tag_regex := RegEx.create_from_string(XML_TAG_PATTERN)


static func is_valid_tag(tag: String) -> bool:
	return _tag_regex.search(tag.strip_edges()) != null


static func tag_error(tag: String) -> String:
	var trimmed := tag.strip_edges()
	if DeviceCatalog.is_structural(trimmed):
		return "%s is a container, not a device on a hub port." % trimmed
	if not is_valid_tag(trimmed):
		return "The RC will reject this tag. %s" % XML_TAG_HINT
	return ""


static func unique_name(root: Dictionary, base: String) -> String:
	var names := {}
	collect_names(root, names)
	if not names.has(base):
		return base
	var i := 2
	while names.has(base + str(i)):
		i += 1
	return base + str(i)


static func collect_names(node: Dictionary, names: Dictionary) -> void:
	if node.attrs.has("name"):
		names[node.attrs["name"]] = true
	for child: Dictionary in node.get("children", []):
		collect_names(child, names)


static func next_port(module: Dictionary, flavor: String, flavors: Dictionary) -> int:
	var used := {}
	for dev: Dictionary in module.children:
		if str(flavors.get(dev.tag, "")) == flavor:
			used[int(str(dev.attrs.get("port", "-1")))] = true
	for port in DeviceCatalog.port_count(flavor):
		if not used.has(port):
			return port
	return 0


static func ethernet_ip(serial: String) -> String:
	var octets := serial.get_slice(":", serial.get_slice_count(":") - 1).split(".")
	if octets.size() != 4:
		return ""
	octets[3] = "1"
	return ".".join(octets)
