class_name Player
extends CharacterBody3D
## First-person player with flashlight, stamina, head bob, camera shake and
## procedural footsteps.

const WALK := 2.6
const RUN := 4.6
const LOOK_SENS := 0.0042
const GRAVITY := 18.0

var controls: TouchControls
var camera: Camera3D
var head: Node3D
var flashlight: SpotLight3D
var face_anchor: Node3D
var step_player: AudioStreamPlayer
var flash_click: AudioStreamPlayer

var yaw := 0.0
var pitch := 0.0
var stamina := 1.0
var battery := 1.0
var flashlight_on := true
var flicker_override := -1.0   # >0 : flashlight forced off for this many seconds
var shake := 0.0
var frozen := false
var forced_look_target = null  # Vector3 or null
var _bob := 0.0
var _step_acc := 0.0
var _turn_left := 0.0
var _flicker_t := 0.0
var fear := 0.0                # 0..1 fed by the game, affects breathing & sway

func setup(p_controls: TouchControls) -> void:
	controls = p_controls
	controls.flashlight_pressed.connect(toggle_flashlight)
	controls.turn_pressed.connect(func(): if not frozen: _turn_left = PI)

func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.75
	cs.shape = cap
	cs.position.y = 0.875
	add_child(cs)
	head = Node3D.new()
	head.position.y = 1.62
	add_child(head)
	camera = Camera3D.new()
	camera.fov = 82.0
	camera.near = 0.03
	camera.far = 60.0
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	head.add_child(camera)
	camera.make_current()
	flashlight = SpotLight3D.new()
	flashlight.light_color = Color(1.0, 0.93, 0.8)
	flashlight.light_energy = 4.0
	flashlight.spot_range = 20.0
	flashlight.spot_angle = 27.0
	flashlight.spot_attenuation = 0.7
	flashlight.spot_angle_attenuation = 0.9
	flashlight.shadow_enabled = true
	flashlight.shadow_bias = 0.05
	flashlight.position = Vector3(0.12, -0.12, 0.0)
	camera.add_child(flashlight)
	# faint fill so the void is not 100% black around the beam
	var fill := OmniLight3D.new()
	fill.light_energy = 0.12
	fill.omni_range = 3.0
	fill.light_color = Color(0.6, 0.65, 0.8)
	camera.add_child(fill)
	face_anchor = Node3D.new()
	camera.add_child(face_anchor)
	step_player = AudioStreamPlayer.new()
	step_player.stream = Sfx.get_sound("step")
	step_player.volume_db = -10.0
	add_child(step_player)
	flash_click = AudioStreamPlayer.new()
	flash_click.stream = Sfx.get_sound("click")
	flash_click.volume_db = -6.0
	add_child(flash_click)

func toggle_flashlight() -> void:
	if frozen:
		return
	flashlight_on = not flashlight_on
	flash_click.play()

func add_shake(a: float) -> void:
	shake = maxf(shake, a)

func is_light_visible() -> bool:
	return flashlight.visible and flashlight.light_energy > 0.3

func _physics_process(delta: float) -> void:
	if controls == null:
		return
	# ---------- look
	var look := controls.consume_look()
	if not frozen:
		yaw -= look.x * LOOK_SENS
		pitch = clampf(pitch - look.y * LOOK_SENS, -1.35, 1.35)
		if _turn_left > 0.0:
			var step := minf(_turn_left, delta * 9.0)
			yaw += step
			_turn_left -= step
	if forced_look_target != null:
		var dir: Vector3 = (forced_look_target - camera.global_position).normalized()
		var target_yaw := atan2(-dir.x, -dir.z)
		var target_pitch := asin(clampf(dir.y, -1.0, 1.0))
		yaw = lerp_angle(yaw, target_yaw, minf(delta * 25.0, 1.0))
		pitch = lerpf(pitch, target_pitch, minf(delta * 25.0, 1.0))
	rotation.y = yaw
	head.rotation.x = pitch
	# ---------- move
	var mv := Vector2.ZERO if frozen else controls.move_vector
	var running := controls.sprinting and stamina > 0.05 and mv.length() > 0.5
	if running:
		stamina = maxf(stamina - delta / 5.0, 0.0)
	else:
		stamina = minf(stamina + delta / (9.0 if mv.length() > 0.1 else 6.0), 1.0)
	var speed := (RUN if running else WALK) * mv.length()
	var wish := (transform.basis * Vector3(mv.x, 0, mv.y))
	wish.y = 0
	wish = wish.normalized() * speed
	velocity.x = lerpf(velocity.x, wish.x, minf(delta * 10.0, 1.0))
	velocity.z = lerpf(velocity.z, wish.z, minf(delta * 10.0, 1.0))
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = -0.5
	move_and_slide()
	# ---------- head bob & footsteps
	var hspeed := Vector2(velocity.x, velocity.z).length()
	if hspeed > 0.3:
		_bob += delta * hspeed * 2.6
		_step_acc += hspeed * delta
		var stride := 1.9 if running else 1.5
		if _step_acc > stride:
			_step_acc = 0.0
			step_player.pitch_scale = randf_range(0.85, 1.1)
			step_player.volume_db = -6.0 if running else -12.0
			step_player.play()
	else:
		_bob = lerpf(_bob, roundf(_bob / PI) * PI, delta * 4.0)
	var bob_y := sin(_bob * 2.0) * 0.045 * clampf(hspeed / WALK, 0.0, 1.6)
	var bob_x := cos(_bob) * 0.03 * clampf(hspeed / WALK, 0.0, 1.6)
	# fear sway
	var t := Time.get_ticks_msec() / 1000.0
	var sway := Vector2(sin(t * 1.3), sin(t * 1.7)) * 0.012 * fear
	# ---------- shake
	shake = maxf(shake - delta * 1.8, 0.0)
	var s := shake * shake
	camera.position = Vector3(bob_x + randf_range(-1, 1) * s * 0.12, bob_y + randf_range(-1, 1) * s * 0.12, 0)
	camera.rotation = Vector3(sway.y + randf_range(-1, 1) * s * 0.06, sway.x, randf_range(-1, 1) * s * 0.05)
	# ---------- flashlight / battery
	if flashlight_on:
		battery = maxf(battery - delta / 240.0, 0.0)
	_flicker_t -= delta
	var energy := 4.5 * clampf(battery * 4.0, 0.15, 1.0)
	var vis := flashlight_on and battery > 0.0
	if flicker_override > 0.0:
		flicker_override -= delta
		vis = false
	elif vis and (battery < 0.2 or fear > 0.85):
		# low battery / terror flicker
		if _flicker_t <= 0.0:
			_flicker_t = randf_range(0.03, 0.4)
			flashlight.set_meta("off", randf() < (0.35 if battery < 0.2 else 0.18))
		if flashlight.get_meta("off", false):
			vis = false
	flashlight.visible = vis
	flashlight.light_energy = energy * randf_range(0.93, 1.0)
	# slight lag of the light behind the view for a hand-held feel
	flashlight.rotation = flashlight.rotation.lerp(Vector3(-look.y * 0.002, -look.x * 0.002, 0), minf(delta * 6.0, 1.0))
