extends CharacterBody2D
## A villager. Placement is driven by Story.NPCS rules (see world.gd);
## cutscenes can take control with `scripted = true` and walk_to().

const DIRS := {"down": 0, "left": 1, "right": 2, "up": 3}

var npc_id := ""
var sheet := ""
var wander_radius := 0.0
var current_spot := ""
var scripted := false
var facing := "down"

var _sprite: Sprite2D
var _shape: CollisionShape2D
var _area: Area2D
var _home := Vector2.ZERO
var _anim_t := 0.0
var _walking := false
var _wander_target := Vector2.ZERO
var _wander_wait := 2.0


func _ready() -> void:
	collision_layer = 4
	collision_mask = 1
	_sprite = Sprite2D.new()
	_sprite.texture = load("res://assets/chars/%s.png" % sheet)
	_sprite.hframes = 4
	_sprite.vframes = 4
	_sprite.centered = false
	_sprite.position = Vector2(-8, -26)
	add_child(_sprite)
	var shadow := Sprite2D.new()
	shadow.texture = load("res://assets/sprites/char_shadow.png")
	shadow.centered = false
	shadow.position = Vector2(-7, -3)
	shadow.show_behind_parent = true
	add_child(shadow)
	move_child(shadow, 0)
	_shape = CollisionShape2D.new()
	var c := CapsuleShape2D.new()
	c.radius = 5
	c.height = 12
	_shape.shape = c
	_shape.rotation = PI / 2
	_shape.position = Vector2(0, -2)
	add_child(_shape)
	_area = Area2D.new()
	_area.collision_layer = 8
	_area.collision_mask = 0
	_area.monitoring = false
	_area.set_meta("iid", npc_id)
	_area.set_meta("npc", self)
	var acs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(18, 26)
	acs.shape = rect
	acs.position = Vector2(0, -10)
	_area.add_child(acs)
	add_child(_area)
	visible = false


func set_present(on: bool) -> void:
	if visible == on:
		return
	visible = on
	_shape.set_deferred("disabled", not on)
	for c in _area.get_children():
		c.set_deferred("disabled", not on)


func teleport(pos: Vector2, dir := "down") -> void:
	position = pos
	_home = pos
	_wander_target = pos
	face(dir)


func face(dir: String) -> void:
	facing = dir
	_update_frame(0)


func face_towards(p: Vector2) -> void:
	var d := p - global_position
	if abs(d.x) > abs(d.y):
		face("right" if d.x > 0 else "left")
	else:
		face("down" if d.y > 0 else "up")


func _update_frame(step: int) -> void:
	if _sprite:
		_sprite.frame = DIRS.get(facing, 0) * 4 + step


## Walk to a point (cutscenes). Ignores collisions so it never gets stuck.
func walk_to(target: Vector2, speed := 45.0) -> void:
	if Game.fast:
		position = target
		await get_tree().process_frame
		return
	_walking = true
	while is_inside_tree() and position.distance_to(target) > 1.5:
		var d := target - position
		if abs(d.x) > abs(d.y):
			facing = "right" if d.x > 0 else "left"
		else:
			facing = "down" if d.y > 0 else "up"
		var step := minf(speed * get_physics_process_delta_time(), d.length())
		position += d.normalized() * step
		await get_tree().physics_frame
	position = target
	_walking = false
	_update_frame(0)


func _physics_process(delta: float) -> void:
	if not visible:
		return
	if _walking:
		_anim_t += delta * 8.0
		_update_frame(int(_anim_t) % 4)
		return
	if scripted or wander_radius <= 0.0 or Game.input_locked:
		return
	# gentle wandering around the home spot
	if position.distance_to(_wander_target) < 2.0:
		_wander_wait -= delta
		_update_frame(0)
		if _wander_wait <= 0.0:
			_wander_wait = randf_range(2.0, 5.0)
			_wander_target = _home + Vector2(randf_range(-wander_radius, wander_radius), randf_range(-wander_radius, wander_radius) * 0.5)
		return
	var d := _wander_target - position
	velocity = d.normalized() * 22.0
	if abs(d.x) > abs(d.y):
		facing = "right" if d.x > 0 else "left"
	else:
		facing = "down" if d.y > 0 else "up"
	var before := position
	move_and_slide()
	if position.distance_to(before) < 0.1:
		_wander_target = position
	_anim_t += delta * 6.0
	_update_frame(int(_anim_t) % 4)
