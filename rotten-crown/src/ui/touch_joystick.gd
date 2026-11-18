class_name TouchJoystick
extends Control
## On-screen stick (bottom-left, or bottom-right with swapped controls). TouchControls feeds it
## touches; it converts them into the analogue move_* input actions. A touch on the stick itself
## uses its home position; a touch elsewhere in the stick's half of the screen (V21) floats the stick
## to the thumb, so that whole side drives the character, not only the drawn disc.

@export var radius := 42.0
@export var knob_radius := 17.0
@export_range(0.0, 0.9) var dead_zone := 0.12
@export var base_color := Color(0.863, 0.835, 0.749, 0.12)
## Kept for compatibility; the stick is drawn as flat discs without outlines.
@export var ring_color := Color(0.863, 0.835, 0.749, 0.0)
@export var knob_color := Color(0.863, 0.835, 0.749, 0.42)

var output := Vector2.ZERO
var _knob := Vector2.ZERO
var _active := false
## Offset of the floating centre from the home position (zero while the stick is where it is drawn).
var _float := Vector2.ZERO


func contains_point(global_point: Vector2) -> bool:
	# Generous hit area so the thumb does not have to be precise.
	return (global_point - _global_center()).length() <= radius * 1.6


## `floating`: centre the stick on the touch instead of its home position.
func begin_touch(global_point: Vector2, floating := false) -> void:
	_active = true
	_float = (global_point - get_global_rect().get_center()) if floating else Vector2.ZERO
	update_touch(global_point)


func update_touch(global_point: Vector2) -> void:
	if not _active:
		return
	_knob = (global_point - _global_center()).limit_length(radius)
	output = _knob / radius
	if output.length() < dead_zone:
		output = Vector2.ZERO
	_apply()
	queue_redraw()


func end_touch() -> void:
	_active = false
	_float = Vector2.ZERO
	_knob = Vector2.ZERO
	output = Vector2.ZERO
	_apply()
	queue_redraw()


func _global_center() -> Vector2:
	return get_global_rect().get_center() + _float


func _apply() -> void:
	_set_axis(&"move_left", &"move_right", output.x)
	_set_axis(&"move_forward", &"move_back", output.y)


func _set_axis(negative: StringName, positive: StringName, value: float) -> void:
	if value < 0.0:
		Input.action_press(negative, -value)
		Input.action_release(positive)
	elif value > 0.0:
		Input.action_press(positive, value)
		Input.action_release(negative)
	else:
		Input.action_release(negative)
		Input.action_release(positive)


func _draw() -> void:
	var c := size * 0.5 + _float
	draw_circle(c, radius, base_color, true, -1.0, false)
	var knob := Color(knob_color, minf(knob_color.a + 0.2, 1.0)) if _active else knob_color
	draw_circle((c + _knob).round(), knob_radius, knob, true, -1.0, false)
	if ring_color.a > 0.0:
		draw_arc(c, radius, 0.0, TAU, 32, ring_color, 1.0)
