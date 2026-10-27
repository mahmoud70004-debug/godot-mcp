class_name PlayerWeapon
extends Node3D
## First-person view model: idle sway, procedural swing and guard poses,
## and the timing window in which the attack hitbox is live.

const REST_POS := Vector3(0.34, -0.36, -0.55)
const REST_ROT := Vector3(-0.6, 0.0, 0.35)
const WINDUP_POS := Vector3(0.46, -0.16, -0.46)
const WINDUP_ROT := Vector3(-0.1, 0.3, -0.75)
const SWING_POS := Vector3(-0.24, -0.46, -0.62)
const SWING_ROT := Vector3(-1.35, -0.2, 1.3)
const BLOCK_POS := Vector3(0.06, -0.24, -0.5)
const BLOCK_ROT := Vector3(-0.15, 0.0, 1.45)
const LOWERED_OFFSET := Vector3(0.0, -0.5, 0.1)
## View-model scale; the models are built at world size.
const MODEL_SCALE := 0.55

@export var hitbox: HitboxComponent

var is_blocking := false
var pose_position := REST_POS
var pose_rotation := REST_ROT

var _attacking := false
var _weapon: WeaponData
var _model: Node3D
var _tween: Tween
var _sway_time := 0.0
var _motion := 0.0


func _process(delta: float) -> void:
	_sway_time += delta * (1.4 + _motion * 7.0)
	var amp := 0.25 + _motion
	var bob := Vector3(cos(_sway_time) * 0.012, -absf(sin(_sway_time)) * 0.016, 0.0) * amp
	position = pose_position + bob
	rotation = pose_rotation


func set_motion(speed_ratio: float) -> void:
	_motion = clampf(speed_ratio, 0.0, 1.2)


func is_busy() -> bool:
	return _attacking


func equip(weapon: WeaponData) -> void:
	_weapon = weapon
	if _model:
		_model.queue_free()
		_model = null
	if weapon:
		_model = WeaponModelBuilder.build(weapon)
		_model.scale = Vector3.ONE * MODEL_SCALE
		add_child(_model)
		_set_reach(weapon.reach)
	_attacking = false
	is_blocking = false
	if hitbox:
		hitbox.deactivate()
	pose_position = REST_POS + LOWERED_OFFSET
	pose_rotation = REST_ROT
	_to_pose(REST_POS, REST_ROT, 0.35)


func attack(damage: float, knockback: float) -> void:
	if _attacking or _weapon == null:
		return
	_attacking = true
	is_blocking = false
	var d := _weapon.attack_duration
	_kill_tween()
	_tween = create_tween()
	_tween.tween_property(self, "pose_position", WINDUP_POS, d * 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.parallel().tween_property(self, "pose_rotation", WINDUP_ROT, d * 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.tween_callback(hitbox.activate.bind(damage, knockback, owner as Node3D))
	_tween.tween_property(self, "pose_position", SWING_POS, d * 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.parallel().tween_property(self, "pose_rotation", SWING_ROT, d * 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.tween_callback(hitbox.deactivate)
	_tween.tween_property(self, "pose_position", REST_POS, d * 0.52).set_trans(Tween.TRANS_SINE)
	_tween.parallel().tween_property(self, "pose_rotation", REST_ROT, d * 0.52).set_trans(Tween.TRANS_SINE)
	_tween.tween_callback(func() -> void: _attacking = false)


func set_blocking(blocking: bool) -> void:
	if _attacking or _weapon == null:
		blocking = false
	if blocking == is_blocking:
		return
	is_blocking = blocking
	if not _attacking:
		if blocking:
			_to_pose(BLOCK_POS, BLOCK_ROT, 0.12)
		else:
			_to_pose(REST_POS, REST_ROT, 0.18)


func on_block_impact() -> void:
	pose_position += Vector3(0.0, -0.03, 0.09)
	if is_blocking:
		_to_pose(BLOCK_POS, BLOCK_ROT, 0.2)


func _to_pose(pos: Vector3, rot: Vector3, duration: float) -> void:
	_kill_tween()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(self, "pose_position", pos, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "pose_rotation", rot, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _kill_tween() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()


func _set_reach(reach: float) -> void:
	if hitbox == null:
		return
	for child in hitbox.get_children():
		var cs := child as CollisionShape3D
		if cs and cs.shape is BoxShape3D:
			var box := cs.shape as BoxShape3D
			box.size.z = reach
			cs.position.z = -reach * 0.5
