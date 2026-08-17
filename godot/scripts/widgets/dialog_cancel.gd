class_name DialogCancel
extends Node

var _dialog: AcceptDialog


static func install(dialog: AcceptDialog) -> void:
	var relay := DialogCancel.new()
	relay._dialog = dialog
	dialog.add_child(relay)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey or not _dialog.visible:
		return
	if not event.is_action_pressed(&"ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	_dialog.hide()
	_dialog.canceled.emit()
