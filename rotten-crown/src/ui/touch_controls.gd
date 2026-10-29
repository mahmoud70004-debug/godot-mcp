class_name TouchControls
extends Control
## Multi-touch router for the landscape layout:
##   left:  fixed virtual joystick
##   right: the whole right half drags the camera
##   right: action buttons (attack / block / interact) take priority
## Godot's GUI is single-pointer, so this node tracks each finger itself.
##
## Look deltas are computed here from each finger's own previous position.
## InputEventScreenDrag.relative is NOT used: Godot's web platform stores the
## previous position per slot of the browser's changedTouches list instead of
## per finger, so with two fingers down a tiny jitter of one finger can be
## reported relative to the *other* finger and fling the camera.

## Largest look movement accepted from a single drag event (viewport pixels).
const MAX_LOOK_STEP := 48.0

@export_range(0.2, 0.8) var look_zone_start := 0.4

@onready var joystick: VirtualJoystick = $Joystick

var _buttons: Array[TouchActionButton] = []
var _joystick_finger := -1
var _look_finger := -1
var _button_fingers: Dictionary = {}
var _last_positions: Dictionary = {}
## Fingers whose stored position predates a change of the UI coordinate space
## (Quality switches content_scale_size): their next drag re-anchors instead of
## producing a delta, otherwise a resting thumb would fling the camera.
var _reanchor: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	for node in find_children("*", "TouchActionButton", true, false):
		_buttons.append(node as TouchActionButton)
	visible = Settings.uses_touch_controls()
	get_viewport().size_changed.connect(_on_view_rescaled)
	Events.quality_changed.connect(_on_quality_changed)
	DebugBridge.register("touch", func() -> Dictionary:
		return {"joystick": _joystick_finger, "look": _look_finger, "buttons": _button_fingers.size(), "fingers": _last_positions.size()})


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		release_all()


func set_enabled(enabled: bool) -> void:
	if not enabled:
		release_all()
	visible = enabled and Settings.uses_touch_controls()


func release_all() -> void:
	for finger in _button_fingers:
		(_button_fingers[finger] as TouchActionButton).release()
	_button_fingers.clear()
	_last_positions.clear()
	_reanchor.clear()
	if joystick:
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
		_on_drag(drag.index, drag.position)


func _on_touch_down(finger: int, pos: Vector2) -> void:
	# A finger id we still hold means its release was lost: forget it first.
	_forget(finger)
	if get_tree().paused:
		return
	_last_positions[finger] = pos
	for button in _buttons:
		if button.is_visible_in_tree() and button.contains_point(pos):
			button.press()
			_button_fingers[finger] = button
			return
	if joystick.contains_point(pos):
		# Only one thumb fits on the stick: the newest touch always owns it.
		_joystick_finger = finger
		joystick.begin_touch(pos)
	elif pos.x >= size.x * look_zone_start:
		_look_finger = finger


func _on_drag(finger: int, pos: Vector2) -> void:
	if not _last_positions.has(finger):
		return
	if _reanchor.has(finger):
		_reanchor.erase(finger)
		_last_positions[finger] = pos
		return
	var delta: Vector2 = pos - (_last_positions[finger] as Vector2)
	_last_positions[finger] = pos
	if finger == _joystick_finger:
		joystick.update_touch(pos)
	elif finger == _look_finger:
		Events.look_input.emit(delta.limit_length(MAX_LOOK_STEP) * Settings.look_sensitivity_touch)


func _on_view_rescaled() -> void:
	for finger in _last_positions:
		_reanchor[finger] = true


func _on_touch_up(finger: int) -> void:
	_forget(finger)


func _forget(finger: int) -> void:
	_last_positions.erase(finger)
	_reanchor.erase(finger)
	if _button_fingers.has(finger):
		(_button_fingers[finger] as TouchActionButton).release()
		_button_fingers.erase(finger)
	if finger == _joystick_finger:
		_joystick_finger = -1
		joystick.end_touch()
	if finger == _look_finger:
		_look_finger = -1


## A method, not a lambda: Godot drops the connection when this node is freed.
func _on_quality_changed(_level: int) -> void:
	_on_view_rescaled()
