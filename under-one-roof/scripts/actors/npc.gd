extends CharacterBody2D
## A villager. Placement is driven by Story.NPCS rules (see world.gd);
## cutscenes can take control with `scripted = true` and walk_to().

const DIRS := {"down": 0, "left": 1, "right": 2, "up": 3}

var npc_id := ""
var sheet := ""
var wander_radius := 0.0
var idle_action: Array = []     # action-row frames played while standing still (work)
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
var world: Node = null          # set by world.gd (path finding)
var patrol: Array = []          # world positions walked in a loop (daily errands)
var _patrol_i := 0
var _travel_id := 0             # bumps to cancel a running travel()


func _ready() -> void:
	collision_layer = 4
	collision_mask = 1
	_sprite = Sprite2D.new()
	_sprite.texture = load("res://assets/chars/%s.png" % sheet)
	_sprite.hframes = 4
	_sprite.vframes = 5
	_sprite.centered = false
	_sprite.position = Vector2(-16, -30)
	_sprite.scale = Vector2(0.5, 0.5)   # sheets are painted at 2x
	add_child(_sprite)
	var shadow := Sprite2D.new()
	shadow.texture = load("res://assets/sprites/char_shadow.png")
	shadow.centered = false
	shadow.position = Vector2(-8, -3)
	shadow.scale = Vector2(0.5, 0.5)
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
	rect.size = Vector2(20, 30)
	acs.shape = rect
	acs.position = Vector2(0, -12)
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
	_travel_id += 1
	_walking = false
	position = pos
	reset_physics_interpolation()
	_home = pos
	_wander_target = pos
	face(dir)


## A little hop while saying a line.
func talk_bounce() -> void:
	if _sprite == null:
		return
	var tw := create_tween()
	tw.tween_property(_sprite, "position:y", -33.0, 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_sprite, "position:y", -30.0, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


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


## Walks along a path of world points (daily routines). Unlike walk_to() it can be
## cancelled by a teleport or a cutscene taking control.
func travel(points: PackedVector2Array, dir := "down", speed := 34.0) -> void:
	_travel_id += 1
	var my := _travel_id
	_walking = true
	for target in points:
		while position.distance_to(target) > 1.0:
			if my != _travel_id or not is_inside_tree() or scripted:
				return
			if Game.input_locked:
				await get_tree().physics_frame
				continue
			var d := target - position
			if abs(d.x) > abs(d.y):
				facing = "right" if d.x > 0 else "left"
			else:
				facing = "down" if d.y > 0 else "up"
			position += d.normalized() * minf(speed * get_physics_process_delta_time(), d.length())
			await get_tree().physics_frame
	if my != _travel_id:
		return
	_walking = false
	_home = position
	_wander_target = position
	face(dir)


func _physics_process(delta: float) -> void:
	if not visible:
		return
	if _walking:
		_anim_t += delta * 8.0
		_update_frame(int(_anim_t) % 4)
		return
	if scripted or Game.input_locked:
		return
	if not patrol.is_empty() and world != null:
		_wander_wait -= delta
		_update_frame(0)
		if _wander_wait <= 0.0:
			_wander_wait = randf_range(3.0, 7.0)
			_patrol_i = (_patrol_i + 1) % patrol.size()
			travel(world.find_path(position, patrol[_patrol_i]))
		return
	if not idle_action.is_empty() and current_spot != "":
		# working at their post: alternate between the work pose and looking around
		_anim_t += delta * 2.5
		var cycle := int(_anim_t) % (idle_action.size() * 3 + 2)
		if cycle < idle_action.size() * 3:
			_sprite.frame = idle_action[cycle % idle_action.size()]
		else:
			_update_frame(0)
		return
	if wander_radius <= 0.0:
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
