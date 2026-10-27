@tool
class_name TouchActionButton
extends Control
## Round on-screen button that emits a real InputEventAction, so gameplay
## code only ever listens to input actions.

@export var action: StringName = &"attack"
@export var label := "ATK"
@export var radius := 24.0
@export var color := Color(0.55, 0.12, 0.08, 0.45)
@export var label_color := Color(0.92, 0.85, 0.7, 0.9)
@export var font_size := 8

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
	var fill := color.lightened(0.3) if pressed else color
	draw_circle(c, radius, fill)
	draw_arc(c, radius, 0.0, TAU, 28, Color(color.r, color.g, color.b, 0.9).lightened(0.4), 1.0)
	var font := get_theme_default_font()
	if font and label != "":
		var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		draw_string(font, c + Vector2(-text_size.x * 0.5, text_size.y * 0.3), label, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, label_color)
