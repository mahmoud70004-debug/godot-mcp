class_name TouchControls
extends Control
## Multi-touch router for the landscape layout:
##   left:  fixed virtual joystick
##   right: the whole right half drags the camera
##   right: action buttons (attack / block / interact) take priority
## Godot's GUI is single-pointer, so this node tracks each finger itself.

@export_range(0.2, 0.8) var look_zone_start := 0.4

@onready var joystick: VirtualJoystick = $Joystick

var _buttons: Array[TouchActionButton] = []
var _joystick_finger := -1
var _look_finger := -1
var _button_fingers: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	for node in find_children("*", "TouchActionButton", true, false):
		_buttons.append(node as TouchActionButton)
	visible = Settings.uses_touch_controls()


func set_enabled(enabled: bool) -> void:
	if not enabled:
		release_all()
	visible = enabled and Settings.uses_touch_controls()


func release_all() -> void:
	for finger in _button_fingers:
		(_button_fingers[finger] as TouchActionButton).release()
	_button_fingers.clear()
	joystick.end_touch()
	_joystick_finger = -1
	_look_finger = -1


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_on_touch_down(touch.index, touch.position)
		else:
			_on_touch_up(touch.index)
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == _joystick_finger:
			joystick.update_touch(drag.position)
		elif drag.index == _look_finger:
			Events.look_input.emit(drag.relative * Settings.look_sensitivity_touch)


func _on_touch_down(finger: int, pos: Vector2) -> void:
	if get_tree().paused:
		return
	for button in _buttons:
		if button.is_visible_in_tree() and button.contains_point(pos):
			button.press()
			_button_fingers[finger] = button
			return
	if _joystick_finger == -1 and joystick.contains_point(pos):
		_joystick_finger = finger
		joystick.begin_touch(pos)
	elif _look_finger == -1 and pos.x >= size.x * look_zone_start:
		_look_finger = finger


func _on_touch_up(finger: int) -> void:
	if _button_fingers.has(finger):
		(_button_fingers[finger] as TouchActionButton).release()
		_button_fingers.erase(finger)
	if finger == _joystick_finger:
		_joystick_finger = -1
		joystick.end_touch()
	if finger == _look_finger:
		_look_finger = -1
