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
## 19 px is the text face's native pixel size (one font pixel per screen pixel).
@export var font_size := 19

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
	# Flat disc, one tone step lighter while held; no outline.
	var fill := Color(color.lightened(0.25), minf(color.a + 0.25, 1.0)) if pressed else color
	draw_circle(c, radius, fill, true, -1.0, false)
	var font := get_theme_default_font()
	if font and label != "":
		var text_w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var baseline := floorf(c.y - font.get_height(font_size) * 0.5 + font.get_ascent(font_size))
		draw_string(font, Vector2(floorf(c.x - text_w * 0.5), baseline), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, label_color)
