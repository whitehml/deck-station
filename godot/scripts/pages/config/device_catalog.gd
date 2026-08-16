class_name DeviceCatalog
extends RefCounted

const CUSTOM_TAG := "__custom__"

const TAG_LYNX_USB_DEVICE := "LynxUsbDevice"
const TAG_LYNX_MODULE := "LynxModule"
const TAG_WEBCAM := "Webcam"
const TAG_ETHERNET_DEVICE := "EthernetDevice"

const BUILT_IN_I2C_TAGS := [
	"Gyro", "IrSeekerV3", "AdafruitColorSensor", "ColorSensor", "LynxColorSensor"
]

const FLAVOR_I2C := "I2C"

const PORT_COUNTS := {
	"MOTOR": 4,
	"SERVO": 6,
	"ANALOG_SENSOR": 4,
	"DIGITAL_IO": 8,
	FLAVOR_I2C: 4,
}

const DEFAULT_PORT_COUNT := 26
const BUS_COUNT := 4

const STRUCTURAL_TAGS := [
	TAG_LYNX_USB_DEVICE,
	TAG_LYNX_MODULE,
	TAG_WEBCAM,
	TAG_ETHERNET_DEVICE,
	"ServoHub",
	"Robot",
	"Nothing",
]


static func parse(json: String) -> Array:
	var entries: Array = []
	var seen := {}
	_collect(JSON.parse_string(json), entries, seen)
	return DisplayOrder.sorted_by(entries, "label")


static func is_structural(tag: String) -> bool:
	return tag.begins_with("<") or STRUCTURAL_TAGS.has(tag)


static func port_count(flavor: String) -> int:
	return PORT_COUNTS.get(flavor, DEFAULT_PORT_COUNT)


static func _collect(value: Variant, entries: Array, seen: Dictionary) -> void:
	if value is Array:
		for item in value:
			_collect(item, entries, seen)
	elif value is Dictionary and value.has("xmlTag"):
		var tag := str(value["xmlTag"])
		if tag.is_empty() or is_structural(tag) or seen.has(tag):
			return
		seen[tag] = true
		var flavor := _flavor(tag, str(value.get("flavor", "")))
		(
			entries
			. append(
				{
					"tag": tag,
					"label": str(value.get("name", tag)),
					"flavor": flavor,
					"needs_bus": flavor == FLAVOR_I2C,
				}
			)
		)


static func _flavor(tag: String, flavor: String) -> String:
	return FLAVOR_I2C if BUILT_IN_I2C_TAGS.has(tag) else flavor.to_upper()
