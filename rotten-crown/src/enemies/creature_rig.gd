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

## Offline sampling: when set, pose_at points the head straight at viewer_position (world space).
var look_at_viewer := false
var viewer_position := Vector3.ZERO

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
var _rest_y := 0.0
var _rest_known := false


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


# --- Deterministic sampling (offline baking) -----------------------------------

## Stateless hash of x into 0..1 (replaces the RNG so sampling is repeatable).
static func _hash01(x: float) -> float:
	return fposmod(sin(x * 12.9898 + 78.233) * 43758.5453, 1.0)


## Deterministic pose for `anim` at `t` seconds since the animation began.
## anim: idle, walk, windup, strike, stagger, death.
func pose_at(anim: StringName, t: float) -> void:
	if not _rest_known:
		_rest_y = position.y
		_rest_known = true
	rotation.x = 0.0
	position.y = _rest_y
	var speed := 0.0
	var arm := 0.0
	var tremble := 0.0
	var jolt := 0.0
	var twitch := Vector3.ZERO
	var amp := maxf(twitch_intensity, 0.0)
	match anim:
		&"walk":
			speed = 1.5
		&"windup":
			arm = Tween.interpolate_value(0.0, 1.25, minf(t, 0.75), 0.75, Tween.TRANS_SINE, Tween.EASE_OUT)
			tremble = 1.0
		&"strike":
			var k := clampf(t / 0.1, 0.0, 1.0)
			arm = lerpf(1.25, 0.5, k * k)
		&"stagger":
			arm = lerpf(0.0, -0.2, clampf(t / 0.15, 0.0, 1.0))
			jolt = exp(-maxf(t, 0.0) * 6.0)
			twitch = Vector3(0.4, 0.6, -0.5) * 2.5 * amp * (1.0 if t < 0.15 else 0.0)
		&"death":
			var fall := clampf(t / 0.9, 0.0, 1.0)
			rotation.x = Tween.interpolate_value(0.0, -1.5, fall * 0.9, 0.9, Tween.TRANS_BOUNCE, Tween.EASE_OUT)
			position.y = lerpf(_rest_y, 0.12, fall)
		_:
			# A frozen jolt of ~0.1 s every ~1.5 s.
			var cycle := floorf(t / 1.5)
			if t - cycle * 1.5 < 0.1:
				twitch = Vector3(_hash01(cycle * 3.1 + 1.0) - 0.5, (_hash01(cycle * 7.7 + 2.0) - 0.5) * 1.6, (_hash01(cycle * 5.3 + 3.0) - 0.5) * 1.4) * amp
	var dead := anim == &"death"
	var breath := 0.0 if dead else sin(t * 1.7) * 0.035
	var gait := sin(t * (3.5 + speed * 1.8))
	var tremor := Vector3.ZERO
	if tremble > 0.0:
		var n := floorf(t * 30.0)
		tremor = Vector3(_hash01(n + 0.1) * 2.0 - 1.0, _hash01(n + 0.2) * 2.0 - 1.0, _hash01(n + 0.3) * 2.0 - 1.0) * 0.05 * tremble
	if spine:
		spine.rotation = _base_spine_rotation + Vector3(breath - arm * 0.22 + jolt * 0.3, 0.0, gait * 0.05 * minf(speed, 2.5)) + tremor * 0.4
	var sway_amp := 0.0 if dead else 0.07 + speed * 0.12
	if shoulder_left:
		var sway := sin(t * (2.6 + speed * 2.2)) * sway_amp
		shoulder_left.rotation = Vector3(sway + arm * 2.4, 0.0, -0.07 - arm * 0.25) + tremor
	if shoulder_right:
		var sway_r := sin(t * (2.3 + speed * 2.0) + 2.1) * sway_amp
		shoulder_right.rotation = Vector3(sway_r + arm * 2.4, 0.0, 0.07 + arm * 0.25) - tremor
	if leg_left and leg_right:
		var stride := gait * 0.4 * minf(speed, 2.5)
		leg_left.rotation.x = stride
		leg_right.rotation.x = -stride
	if head:
		var desired := Basis()
		var parent := head.get_parent() as Node3D
		if look_at_viewer and parent and parent.is_inside_tree():
			var local_dir := parent.global_basis.orthonormalized().inverse() * (viewer_position - head.global_position)
			if local_dir.length_squared() > 0.001:
				desired = Basis.looking_at(local_dir.normalized(), Vector3.UP)
		desired = desired * Basis.from_euler(Vector3(0.0, 0.0, deg_to_rad(head_tilt_degrees)))
		head.basis = desired * Basis.from_euler(twitch)


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
