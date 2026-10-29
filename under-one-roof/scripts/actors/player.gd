extends CharacterBody2D
## Gideon. Keyboard / gamepad / on-screen joystick movement, four-direction walk cycle
## and a reach area in front of him used to pick what to interact with.

signal target_changed(area: Area2D)

const WALK_SPEED := 72.0
const RUN_SPEED := 112.0
const DIRS := {"down": 0, "left": 1, "right": 2, "up": 3}
const REACH := {"down": Vector2(0, 10), "up": Vector2(0, -16), "left": Vector2(-12, -4), "right": Vector2(12, -4)}

@onready var sprite: Sprite2D = $Sprite
@onready var reach: Area2D = $Reach
@onready var camera: Camera2D = $Camera

var facing := "down"
var target: Area2D = null
var _anim_t := 0.0
var _step_t := 0.0


func _ready() -> void:
	reach.area_entered.connect(func(_a): _pick_target())
	reach.area_exited.connect(func(_a): _pick_target())


func face(dir: String) -> void:
	facing = dir
	sprite.frame = DIRS[facing] * 4
	reach.position = REACH[facing]


func _physics_process(delta: float) -> void:
	var input := Vector2.ZERO
	if not Game.input_locked:
		input = Input.get_vector("move_left", "move_right", "move_up", "move_down")
		if input == Vector2.ZERO:
			input = Game.touch_vector
	var running := Input.is_action_pressed("run") or Game.touch_run
	var speed := RUN_SPEED if running else WALK_SPEED
	if Game.count("boots") > 0:
		speed *= 1.15
	velocity = input.limit_length(1.0) * speed
	move_and_slide()

	if input.length() > 0.1:
		if abs(input.x) > abs(input.y) * 1.1:
			facing = "right" if input.x > 0 else "left"
		else:
			facing = "down" if input.y > 0 else "up"
		reach.position = REACH[facing]
		_anim_t += delta * (speed / 9.0)
		var f := int(_anim_t) % 4
		sprite.frame = DIRS[facing] * 4 + f
		_step_t += delta * (speed / 9.0)
		if _step_t >= 2.0:
			_step_t = 0.0
			Audio.sfx("step", randf_range(0.85, 1.15))
		_pick_target()
	else:
		_anim_t = 0.0
		sprite.frame = DIRS[facing] * 4


func _pick_target() -> void:
	var best: Area2D = null
	var best_d := INF
	var origin := global_position + reach.position
	for a in reach.get_overlapping_areas():
		if not a.is_visible_in_tree() and not a.has_meta("npc"):
			continue
		if a.has_meta("npc") and not a.get_meta("npc").visible:
			continue
		if not Director.can_interact(a.get_meta("iid")):
			continue
		var d := origin.distance_squared_to(_area_center(a))
		if a.has_meta("npc"):
			d *= 0.5  # people first
		if d < best_d:
			best_d = d
			best = a
	if best != target:
		target = best
		target_changed.emit(target)


func _area_center(a: Area2D) -> Vector2:
	for c in a.get_children():
		if c is CollisionShape2D:
			return c.global_position
	return a.global_position


func _unhandled_input(event: InputEvent) -> void:
	if Game.input_locked:
		return
	if event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		interact()


func interact() -> void:
	_pick_target()
	if target and not Game.input_locked:
		Director.interact(target)
