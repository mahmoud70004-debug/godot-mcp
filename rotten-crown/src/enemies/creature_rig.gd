class_name CreatureRig
extends Node3D
## Procedural, deliberately *wrong* animation for the transformed citizens.
## The horror comes from small violations of how a body should move:
## a head that keeps turning past where a neck allows, arms that hang too
## long and sway out of step, sudden frozen twitches, a slow tremor before
## every strike - never from things jumping at the camera.

@export var spine: Node3D
@export var head: Node3D
@export var shoulder_left: Node3D
@export var shoulder_right: Node3D
@export var leg_left: Node3D
@export var leg_right: Node3D
@export var twitch_intensity := 1.0
@export var head_tilt_degrees := 22.0

var _flesh_meshes: Array[GeometryInstance3D] = []
var _look_target: Node3D
var _move_speed := 0.0
var _time := 0.0
var _arm_pose := 0.0
var _tremble := 0.0
var _pose_tween: Tween
var _base_spine_rotation := Vector3.ZERO
var _head_rotation := Quaternion.IDENTITY
var _twitch_offset := Vector3.ZERO
var _twitch_hold := 0.0
var _twitch_cooldown := 1.5
var _flash := 0.0
var _alive := true
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_time = _rng.randf() * 10.0
	for node in find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var mat: Material = mi.material_override
		if mat == null and mi.mesh:
			mat = mi.mesh.surface_get_material(0)
		if mat is ShaderMaterial:
			_flesh_meshes.append(mi)
			mi.set_instance_shader_parameter("time_offset", _rng.randf() * 100.0)
	if spine:
		_base_spine_rotation = spine.rotation
	if head:
		_head_rotation = head.basis.get_rotation_quaternion()


func setup(data: EnemyData) -> void:
	twitch_intensity = data.twitch_intensity
	head_tilt_degrees = data.head_tilt_degrees
	scale = data.body_scale


func set_look_target(target: Node3D) -> void:
	_look_target = target


func set_move_speed(speed: float) -> void:
	_move_speed = speed


func _process(delta: float) -> void:
	if not _alive:
		return
	_time += delta
	var breath := sin(_time * 1.7) * 0.035
	var gait := sin(_time * (3.5 + _move_speed * 1.8))
	var tremor := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * 0.05 * _tremble

	if spine:
		spine.rotation = _base_spine_rotation + Vector3(breath - _arm_pose * 0.22, 0.0, gait * 0.05 * minf(_move_speed, 2.5)) + tremor * 0.4
	var sway := sin(_time * (2.6 + _move_speed * 2.2)) * (0.07 + _move_speed * 0.12)
	if shoulder_left:
		shoulder_left.rotation = Vector3(sway + _arm_pose * 2.4, 0.0, -0.07 - _arm_pose * 0.25) + tremor
	if shoulder_right:
		# Out of phase and slightly slower: the arms never quite agree.
		var sway_r := sin(_time * (2.3 + _move_speed * 2.0) + 2.1) * (0.07 + _move_speed * 0.12)
		shoulder_right.rotation = Vector3(sway_r + _arm_pose * 2.4, 0.0, 0.07 + _arm_pose * 0.25) - tremor
	if leg_left and leg_right:
		var stride := gait * 0.4 * minf(_move_speed, 2.5)
		leg_left.rotation.x = stride
		leg_right.rotation.x = -stride
	_update_head(delta)
	_update_twitch(delta)
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 5.0, 0.0)
		_set_flash(_flash)


func _update_head(delta: float) -> void:
	if head == null:
		return
	var desired := Basis()
	if _look_target and is_instance_valid(_look_target):
		var parent := head.get_parent() as Node3D
		var target_pos := _look_target.global_position + Vector3.UP * 1.5
		var local_dir := parent.global_basis.orthonormalized().inverse() * (target_pos - head.global_position)
		if local_dir.length_squared() > 0.001:
			# No neck limits on purpose: it will turn all the way around.
			desired = Basis.looking_at(local_dir.normalized(), Vector3.UP)
	desired = desired * Basis.from_euler(Vector3(0.0, 0.0, deg_to_rad(head_tilt_degrees)))
	_head_rotation = _head_rotation.slerp(desired.get_rotation_quaternion(), minf(delta * 2.5, 1.0))
	head.basis = Basis(_head_rotation) * Basis.from_euler(_twitch_offset)


func _update_twitch(delta: float) -> void:
	if _twitch_hold > 0.0:
		_twitch_hold -= delta
		if _twitch_hold <= 0.0:
			_twitch_offset = Vector3.ZERO
		return
	_twitch_cooldown -= delta
	if _twitch_cooldown <= 0.0 and twitch_intensity > 0.0:
		_twitch(1.0)


func _twitch(strength: float) -> void:
	_twitch_offset = Vector3(_rng.randf_range(-0.5, 0.5), _rng.randf_range(-0.8, 0.8), _rng.randf_range(-0.7, 0.7)) * twitch_intensity * strength
	_twitch_hold = _rng.randf_range(0.05, 0.2)
	_twitch_cooldown = _rng.randf_range(0.8, 4.0) / maxf(twitch_intensity, 0.1)


# --- Poses -------------------------------------------------------------------

func play_windup(duration: float) -> void:
	_tween_pose(1.25, duration, Tween.TRANS_SINE, Tween.EASE_OUT)
	_tremble = 1.0


func play_strike() -> void:
	_tremble = 0.0
	_tween_pose(0.5, 0.1, Tween.TRANS_QUAD, Tween.EASE_IN)


func play_recover() -> void:
	_tween_pose(0.0, 0.7, Tween.TRANS_SINE, Tween.EASE_IN_OUT)


func play_stagger() -> void:
	_tremble = 0.0
	_twitch(2.5)
	_tween_pose(-0.2, 0.15, Tween.TRANS_QUAD, Tween.EASE_OUT)


func flash() -> void:
	_flash = 1.0
	_set_flash(_flash)


## Collapses forward. Await the returned signal to know when it settled.
func play_death() -> Signal:
	_alive = false
	_tremble = 0.0
	_set_flash(0.0)
	var tween := create_tween()
	tween.tween_property(self, "rotation:x", -1.5, 0.9).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(self, "position:y", 0.12, 0.9)
	# One last, wrong movement after it has already died.
	tween.tween_interval(1.6)
	if shoulder_right:
		tween.tween_property(shoulder_right, "rotation:x", 1.2, 0.07)
		tween.tween_property(shoulder_right, "rotation:x", 0.4, 0.6)
	return tween.finished


func _tween_pose(target: float, duration: float, trans: Tween.TransitionType, ease_type: Tween.EaseType) -> void:
	if _pose_tween and _pose_tween.is_valid():
		_pose_tween.kill()
	_pose_tween = create_tween()
	_pose_tween.tween_property(self, "_arm_pose", target, duration).set_trans(trans).set_ease(ease_type)


func _set_flash(value: float) -> void:
	for mi in _flesh_meshes:
		mi.set_instance_shader_parameter("hit_flash", value)
