@tool
class_name PixelBar
extends Control
## Crisp pixel stat bar with a lagging "ghost" segment that shows
## recent damage, souls-style.

@export var fill_color := Color(0.62, 0.141, 0.098)
@export var ghost_color := Color(0.863, 0.835, 0.749)
@export var back_color := Color(0.043, 0.055, 0.047, 0.85)
## Optional 1px frame; transparent by default (the plate alone separates the bar from the world).
@export var border_color := Color(0, 0, 0, 0)
@export var ghost_delay := 0.5
@export var ghost_speed := 0.6

var ratio := 1.0
var _ghost := 1.0
var _ghost_wait := 0.0


func set_values(current: float, maximum: float) -> void:
	var new_ratio := clampf(current / maximum, 0.0, 1.0) if maximum > 0.0 else 0.0
	if new_ratio < ratio:
		_ghost_wait = ghost_delay
	else:
		_ghost = maxf(_ghost, new_ratio)
	ratio = new_ratio
	queue_redraw()


func _process(delta: float) -> void:
	if _ghost <= ratio:
		_ghost = ratio
		return
	if _ghost_wait > 0.0:
		_ghost_wait -= delta
		return
	_ghost = maxf(_ghost - ghost_speed * delta, ratio)
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size).abs()
	draw_rect(r, back_color)
	var inner := r.grow(-1.0)
	draw_rect(Rect2(inner.position, Vector2(floorf(inner.size.x * _ghost), inner.size.y)), ghost_color)
	draw_rect(Rect2(inner.position, Vector2(floorf(inner.size.x * ratio), inner.size.y)), fill_color)
	draw_rect(Rect2(inner.position, Vector2(floorf(inner.size.x * ratio), 1.0)), fill_color.lightened(0.25))
	if border_color.a > 0.0:
		draw_rect(r, border_color, false, 1.0)
