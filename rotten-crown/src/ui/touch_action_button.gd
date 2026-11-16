@tool
class_name TouchActionButton
extends Control
## Round on-screen button that emits a real InputEventAction, so gameplay
## code only ever listens to input actions.

@export var action: StringName = &"attack"
@export var label := "ATK"
@export var radius := 24.0
@export var color := Color(0.55, 0.12, 0.08, 0.45)
@export var label_color := Color(0.863, 0.835, 0.749, 0.95)
## The label is set in the display face (V24), a little under its native 24 px so it fits the disc.
@export var font_size := 21

const GOTHIC := preload("res://assets/fonts/Jacquard24-Regular.ttf")
## V24: the worn iron ring round the disc, and its lit rivets.
const IRON := Color(0.3, 0.28, 0.24, 0.95)
const RIVET := Color(0.55, 0.52, 0.43, 1.0)

var pressed := false


func contains_point(global_point: Vector2) -> bool:
	return (global_point - get_global_rect().get_center()).length() <= radius + 4.0


func press() -> void:
	if pressed:
		return
	pressed = true
	_send(true)
	queue_redraw()


func release() -> void:
	if not pressed:
		return
	pressed = false
	_send(false)
	queue_redraw()


func _send(is_pressed: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = is_pressed
	ev.strength = 1.0 if is_pressed else 0.0
	Input.parse_input_event(ev)


func _draw() -> void:
	var c := size * 0.5
	# A disc one tone step lighter while held, in an iron ring with a lit edge and four rivets.
	var fill := Color(color.lightened(0.25), minf(color.a + 0.25, 1.0)) if pressed else color
	draw_circle(c, radius, fill, true, -1.0, false)
	draw_arc(c, radius, 0.0, TAU, 40, Color(0.04, 0.04, 0.035, 0.8), 3.0, false)
	draw_arc(c, radius, 0.0, TAU, 40, IRON, 1.5, false)
	draw_arc(c, radius, PI * 0.95, PI * 1.55, 12, RIVET, 1.0, false)
	for a in [0.0, PI * 0.5, PI, PI * 1.5]:
		draw_circle(c + Vector2(cos(a), sin(a)) * radius, 1.6, RIVET, true, -1.0, false)
	if label != "":
		var text_w := GOTHIC.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var baseline := floorf(c.y - GOTHIC.get_height(font_size) * 0.5 + GOTHIC.get_ascent(font_size))
		draw_string(GOTHIC, Vector2(floorf(c.x - text_w * 0.5), baseline), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, label_color)
