class_name Enemy
extends CharacterBody3D
## Base AI for the transformed citizens of Valdron. Variants are mostly
## data (EnemyData) plus a SpriteCreatureVisual; override the virtual hooks for
## unique behaviour (ranged spit, bosses, swarms) in later phases.

enum State { IDLE, CHASE, WINDUP, ATTACK, RECOVER, STAGGER, DEAD }

const PICKUP_SCENE := preload("res://src/interaction/item_pickup.tscn")
const OOZE_SHADER := preload("res://assets/shaders/ooze.gdshader")

@export var data: EnemyData
## Starts motionless (back turned, mid-feast...) until the player is close or attacks.
@export var start_dormant := false

@onready var health: HealthComponent = $HealthComponent
@onready var hurtbox: HurtboxComponent = $Hurtbox
@onready var attack_hitbox: HitboxComponent = $AttackHitbox
@onready var rig: SpriteCreatureVisual = $Visual

var state: State = State.IDLE
var _state_time := 0.0
var _cooldown := 0.0
var _target: Node3D
var _dormant := false
var _knockback := Vector3.ZERO
var _los_timer := 0.0
var _has_los := false
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _ready() -> void:
	assert(data != null, "%s has no EnemyData assigned" % name)
	add_to_group("enemies")
	_dormant = start_dormant
	health.set_max_health(data.max_health, true)
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)
	rig.setup(data)


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	_state_time += delta
	_cooldown = maxf(_cooldown - delta, 0.0)
	if not is_on_floor():
		velocity.y -= _gravity * delta
	_update_target(delta)

	var desired := Vector3.ZERO
	var to_target := _flat_to_target()
	var dist := to_target.length()
	match state:
		State.IDLE:
			if _should_wake(dist):
				_change_state(State.CHASE)
		State.CHASE:
			if _target == null or dist > data.lose_interest_range:
				_change_state(State.IDLE)
			elif dist <= data.attack_range and _cooldown <= 0.0:
				_change_state(State.WINDUP)
			else:
				if not (data.freezes_when_watched and _is_watched()):
					desired = to_target.normalized() * data.chase_speed
					_face(to_target, delta, data.turn_speed)
		State.WINDUP:
			_face(to_target, delta, data.turn_speed * 0.4)
			if _state_time >= data.attack_windup:
				_change_state(State.ATTACK)
		State.ATTACK:
			desired = -global_basis.z * data.lunge_speed
			if _state_time >= data.attack_active_time:
				_change_state(State.RECOVER)
		State.RECOVER:
			if _state_time >= data.attack_recovery:
				_change_state(State.CHASE)
		State.STAGGER:
			if _state_time >= data.stagger_duration:
				_change_state(State.CHASE)

	var horizontal := Vector3(velocity.x, 0.0, velocity.z).move_toward(desired, data.acceleration * delta)
	velocity.x = horizontal.x + _knockback.x
	velocity.z = horizontal.z + _knockback.z
	_knockback = _knockback.move_toward(Vector3.ZERO, 10.0 * delta)
	move_and_slide()
	rig.set_move_speed(horizontal.length())


func _change_state(new_state: State) -> void:
	if state == State.ATTACK:
		attack_hitbox.deactivate()
	state = new_state
	_state_time = 0.0
	match new_state:
		State.IDLE:
			rig.set_look_target(null)
		State.CHASE:
			_dormant = false
			rig.set_look_target(_target)
		State.WINDUP:
			rig.play_windup(data.attack_windup)
		State.ATTACK:
			attack_hitbox.activate(data.damage, data.knockback, self)
			rig.play_strike()
		State.RECOVER:
			_cooldown = data.attack_cooldown
			rig.play_recover()
		State.STAGGER:
			rig.play_stagger()


# --- Senses ----------------------------------------------------------------

func _update_target(delta: float) -> void:
	if _target == null or not is_instance_valid(_target):
		_target = get_tree().get_first_node_in_group("player") as Node3D
	_los_timer -= delta
	if _los_timer <= 0.0:
		_los_timer = 0.25
		_has_los = _check_line_of_sight()


func _should_wake(dist: float) -> bool:
	if _target == null or dist > data.detection_range:
		return false
	if _dormant and dist > data.dormant_wake_range:
		return false
	return _has_los


func _check_line_of_sight() -> bool:
	if _target == null:
		return false
	var from := global_position + Vector3.UP * 1.6
	var to := _target.global_position + Vector3.UP * 1.4
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


## True while the player's camera is pointed at this creature.
func _is_watched() -> bool:
	var cam := get_viewport().get_camera_3d()
	if cam == null or not _has_los:
		return false
	var to_me := (global_position + Vector3.UP * 1.2 - cam.global_position).normalized()
	return (-cam.global_basis.z).dot(to_me) > 0.8


func _flat_to_target() -> Vector3:
	if _target == null:
		return Vector3.ZERO
	var v := _target.global_position - global_position
	v.y = 0.0
	return v


func _face(direction: Vector3, delta: float, speed: float) -> void:
	if direction.length_squared() < 0.0001:
		return
	var yaw := atan2(-direction.x, -direction.z)
	rotation.y = lerp_angle(rotation.y, yaw, minf(speed * delta, 1.0))


# --- Damage ----------------------------------------------------------------

func _on_damaged(info: DamageInfo) -> void:
	rig.flash()
	if health.is_dead:
		return
	_knockback += info.direction_to(self) * info.knockback * (1.0 - data.knockback_resistance)
	if info.source:
		_target = info.source
	if info.amount >= data.stagger_threshold:
		_change_state(State.STAGGER)
	elif state == State.IDLE:
		_change_state(State.CHASE)


func _on_died() -> void:
	_change_state(State.DEAD)
	attack_hitbox.deactivate()
	collision_layer = 0
	collision_mask = 1
	hurtbox.set_deferred("monitorable", false)
	velocity = Vector3.ZERO
	Events.enemy_killed.emit(data)
	_spawn_ooze()
	_drop_loot()
	await rig.play_death()


func _spawn_ooze() -> void:
	var puddle := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(2.4, 2.4)
	puddle.mesh = plane
	var mat := ShaderMaterial.new()
	mat.shader = OOZE_SHADER
	puddle.material_override = mat
	puddle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_parent().add_child(puddle)
	puddle.global_position = global_position + Vector3(0.0, 0.02, 0.0) - global_basis.z * 0.8
	puddle.set_instance_shader_parameter("seed", randf() * 50.0)
	puddle.scale = Vector3(0.2, 1.0, 0.2)
	puddle.create_tween().tween_property(puddle, "scale", Vector3.ONE, 3.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _drop_loot() -> void:
	if data.drop_item == null or randf() > data.drop_chance:
		return
	var pickup := PICKUP_SCENE.instantiate() as ItemPickup
	pickup.item = data.drop_item
	get_parent().add_child(pickup)
	pickup.global_position = global_position + Vector3(0.0, 0.5, 0.0)
