class_name HumanoidRig
extends Node3D
## Shared pose/animation layer for the knight and the villagers. Subclasses
## build the body in _build() and assign the pivots; animation is procedural
## (gait, idle breathing) plus tweened poses for story beats.

enum Mode { IDLE, WALK, DANCE, CHEER, MUSIC, SIT }

var hips: Node3D
var spine: Node3D
var head: Node3D
var shoulder_l: Node3D
var shoulder_r: Node3D
var elbow_l: Node3D
var elbow_r: Node3D
var leg_l: Node3D
var leg_r: Node3D
var hand_r: Node3D

var mode: Mode = Mode.IDLE
var tempo := 1.0
var _time := 0.0
var _pose_lock := false
var _from_process := false
var _rest_known := false
var _rest_y := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_time = _rng.randf() * 10.0
	_build()
	MeshMerger.bake_character(self)


## Override: create meshes and assign the pivot variables.
func _build() -> void:
	pass


func _process(delta: float) -> void:
	_time += delta * tempo
	if _pose_lock:
		return
	_from_process = true
	pose_at(_anim_name(mode), _time)
	_from_process = false


## Name of the animation that corresponds to a runtime mode.
func _anim_name(m: Mode) -> StringName:
	match m:
		Mode.WALK:
			return &"walk"
		Mode.DANCE:
			return &"dance"
		Mode.CHEER:
			return &"cheer"
		Mode.MUSIC:
			return &"music"
		Mode.SIT:
			return &"sit"
	return &"idle"


## Deterministic pose for animation `anim` at time `t` (seconds). Resets every
## pivot to neutral first, so calls can be made in any order (offline baking).
## anim: idle, walk, dance, cheer, music, sit, toast, stretch, lie.
func pose_at(anim: StringName, t: float) -> void:
	if not _from_process:
		# Only offline sampling touches the node's own transform (lie).
		if not _rest_known:
			_rest_y = position.y
			_rest_known = true
		rotation.x = 0.0
		position.y = _rest_y
	_reset_pose()
	match anim:
		&"walk":
			var s := sin(t * 7.0)
			_set_limbs(-s * 0.45, s * 0.45, s * 0.5, -s * 0.5, 0.25, 0.25)
			hips.position.y = _hip_height() + absf(cos(t * 7.0)) * 0.04
			spine.rotation.x = -0.05
		&"dance":
			# A jig: hop on alternate feet, arms out, body twisting.
			var hop := absf(sin(t * 6.6))
			hips.position.y = _hip_height() + hop * 0.12
			_set_limbs(sin(t * 3.3) * 0.6, -sin(t * 3.3) * 0.6, 1.2 + sin(t * 6.6) * 0.4, 1.2 - sin(t * 6.6) * 0.4, 0.6, 0.6)
			shoulder_l.rotation.z = -0.9
			shoulder_r.rotation.z = 0.9
			spine.rotation.y = sin(t * 3.3) * 0.35
		&"cheer":
			var wave := sin(t * 5.0)
			_set_limbs(0.0, 0.0, 2.6 + wave * 0.25, 2.8 - wave * 0.25, 0.4, 0.3)
			hips.position.y = _hip_height() + absf(wave) * 0.05
			head.rotation.x = -0.25
		&"music":
			_set_limbs(0.0, 0.0, 0.9, 0.7 + sin(t * 10.0) * 0.25, 1.4, 1.2)
			spine.rotation.x = 0.08 * sin(t * 3.3)
			head.rotation.z = 0.15 * sin(t * 3.3)
		&"sit":
			hips.position.y = _hip_height() * 0.55
			_set_limbs(1.5, 1.5, 0.4, 0.4, 0.8, 0.8)
		&"toast":
			# Goblet held high in the right hand, a small sway; left arm relaxed.
			_set_limbs(0.0, 0.0, 0.05 * sin(t * 1.3), 2.7 + 0.08 * sin(t * 2.1), 0.1, 0.45)
			shoulder_r.rotation.z = 0.15 + 0.04 * sin(t * 1.7)
			spine.rotation.x = 0.03 * sin(t * 1.7)
			head.rotation.x = -0.18
		&"stretch":
			# A yawn: both arms up and back, head tilted back, slight back arch.
			var k := 0.5 + 0.5 * sin(t * 1.4)
			_set_limbs(0.0, 0.0, 2.9 + 0.2 * k, 2.9 + 0.2 * k, 0.15, 0.15)
			shoulder_l.rotation.z = -0.35 - 0.1 * k
			shoulder_r.rotation.z = 0.35 + 0.1 * k
			spine.rotation.x = -0.12 - 0.06 * k
			head.rotation.x = -0.5 - 0.1 * k
		&"lie":
			# End state of lie_down: on the back, resting on the ground, arms at the sides.
			rotation.x = PI * 0.5
			position.y = _rest_y + 0.22
			_set_limbs(0.0, 0.0, 0.15, 0.15, 0.0, 0.0)
			head.rotation.x = -0.2
		_:
			_set_limbs(0.05 * sin(t * 1.3), -0.05 * sin(t * 1.3), 0.0, 0.0, 0.1, 0.1)
			spine.rotation.x = 0.03 * sin(t * 1.7)
			hips.position.y = _hip_height()


## Puts every animated pivot back to neutral.
func _reset_pose() -> void:
	hips.position.y = _hip_height()
	spine.rotation = Vector3.ZERO
	head.rotation = Vector3.ZERO
	shoulder_l.rotation = Vector3(0.0, 0.0, -0.08)
	shoulder_r.rotation = Vector3(0.0, 0.0, 0.08)
	_set_limbs(0.0, 0.0, 0.0, 0.0, 0.0, 0.0)


func _hip_height() -> float:
	return 1.0


func _set_limbs(leg_left: float, leg_right: float, arm_left: float, arm_right: float, bend_left: float, bend_right: float) -> void:
	# Arms hang along -Y; positive X rotation swings them forward/up.
	leg_l.rotation.x = leg_left
	leg_r.rotation.x = leg_right
	shoulder_l.rotation.x = arm_left
	shoulder_r.rotation.x = arm_right
	if elbow_l:
		elbow_l.rotation.x = bend_left
	if elbow_r:
		elbow_r.rotation.x = bend_right


## Tween to a locked pose (story beats). Returns the tween to await.
func hold_pose(arm_left: float, arm_right: float, bend_left: float, bend_right: float, head_pitch: float, spine_pitch: float, duration: float) -> Tween:
	_pose_lock = true
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(shoulder_l, "rotation:x", arm_left, duration)
	tw.tween_property(shoulder_r, "rotation:x", arm_right, duration)
	tw.tween_property(shoulder_l, "rotation:z", -0.15, duration)
	tw.tween_property(shoulder_r, "rotation:z", 0.15, duration)
	if elbow_l:
		tw.tween_property(elbow_l, "rotation:x", bend_left, duration)
	if elbow_r:
		tw.tween_property(elbow_r, "rotation:x", bend_right, duration)
	tw.tween_property(head, "rotation:x", head_pitch, duration)
	tw.tween_property(spine, "rotation:x", spine_pitch, duration)
	tw.tween_property(leg_l, "rotation:x", 0.0, duration)
	tw.tween_property(leg_r, "rotation:x", 0.0, duration)
	return tw


func release_pose(new_mode: Mode) -> void:
	_pose_lock = false
	shoulder_l.rotation.z = 0.0
	shoulder_r.rotation.z = 0.0
	head.rotation = Vector3.ZERO
	spine.rotation = Vector3.ZERO
	mode = new_mode


## Lies down on the back (rotating about the feet), arms at the sides.
func lie_down(duration: float) -> Tween:
	_pose_lock = true
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(self, "rotation:x", PI * 0.5, duration)
	tw.tween_property(self, "position:y", position.y + 0.22, duration)
	tw.tween_property(shoulder_l, "rotation:x", 0.15, duration)
	tw.tween_property(shoulder_r, "rotation:x", 0.15, duration)
	tw.tween_property(head, "rotation:x", -0.2, duration)
	tw.tween_property(leg_l, "rotation:x", 0.0, duration)
	tw.tween_property(leg_r, "rotation:x", 0.0, duration)
	return tw
