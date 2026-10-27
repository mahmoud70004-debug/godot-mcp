class_name Player
extends CharacterBody3D
## First-person knight. Movement, look, stamina, melee, blocking and
## interaction. Touch, mouse and gamepad all feed the same input actions.

@export_group("Movement")
@export var walk_speed := 3.4
@export var block_speed_multiplier := 0.45
@export var acceleration := 14.0
@export var deceleration := 12.0

@export_group("Look")
@export var min_pitch := -80.0
@export var max_pitch := 80.0

@export_group("Stamina")
@export var stamina_regen := 24.0
@export var stamina_regen_delay := 0.9
## Stamina lost per point of damage absorbed by the guard.
@export var block_stamina_per_damage := 1.2

@export_group("Feel")
@export var bob_frequency := 2.2
@export var bob_amplitude := 0.035
@export var eye_height := 1.6

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var weapon: PlayerWeapon = $Head/Camera3D/WeaponPivot
@onready var interact_ray: RayCast3D = $Head/Camera3D/InteractRay
@onready var health: HealthComponent = $HealthComponent
@onready var hurtbox: HurtboxComponent = $Hurtbox

var stamina := 100.0
var max_stamina := 100.0
var input_enabled := true

var _pitch := 0.0
var _bob_time := 0.0
var _regen_cooldown := 0.0
var _shake := 0.0
var _current_interactable: Interactable
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _ready() -> void:
	add_to_group("player")
	max_stamina = GameState.get_max_stamina()
	stamina = max_stamina
	health.set_max_health(GameState.get_max_health(), true)
	if GameState.player_health > 0.0:
		health.set_current_health(GameState.player_health)
	health.health_changed.connect(_on_health_changed)
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)
	hurtbox.damage_modifier = _modify_incoming_damage
	weapon.hitbox.hit_landed.connect(_on_hit_landed)
	Events.look_input.connect(_apply_look)
	Events.consumable_used.connect(_on_consumable_used)
	Events.menu_state_changed.connect(_on_menu_state_changed)
	GameState.equipped_weapon_changed.connect(weapon.equip)
	GameState.stats_changed.connect(_on_stats_changed)
	weapon.equip(GameState.equipped_weapon)
	if not Settings.uses_touch_controls():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_emit_initial_stats.call_deferred()
	DebugBridge.register("player", func() -> Dictionary:
		return {"yaw": snappedf(rotation_degrees.y, 0.01), "pitch": snappedf(_pitch, 0.01),
			"pos": [snappedf(global_position.x, 0.01), snappedf(global_position.y, 0.01), snappedf(global_position.z, 0.01)],
			"hp": health.current_health})


func _emit_initial_stats() -> void:
	Events.player_health_changed.emit(health.current_health, health.max_health)
	Events.player_stamina_changed.emit(stamina, max_stamina)


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	# Desktop testing only: touch never captures the mouse, so emulated
	# mouse events from the touchscreen are ignored here.
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if event is InputEventMouseMotion:
			_apply_look((event as InputEventMouseMotion).relative * Settings.look_sensitivity_mouse)
		elif event is InputEventMouseButton and event.is_pressed():
			var mb := event as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT:
				try_attack()
	elif event is InputEventMouseButton and event.is_pressed() and not Settings.uses_touch_controls():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta

	var input_dir := Vector2.ZERO
	if input_enabled:
		input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		# Right-stick look only with a real gamepad: some phones report phantom
		# axes, and touch look arrives through Events.look_input instead.
		var look := Vector2.ZERO
		if not Input.get_connected_joypads().is_empty():
			look = Input.get_vector("look_left", "look_right", "look_up", "look_down")
		if look != Vector2.ZERO:
			_apply_look(look * Settings.look_speed_gamepad * delta)

	var direction := transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)
	var speed := walk_speed * (block_speed_multiplier if weapon.is_blocking else 1.0)
	var target := direction * speed
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var rate := acceleration if target.length_squared() > 0.0 else deceleration
	horizontal = horizontal.move_toward(target, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	move_and_slide()

	var speed_ratio := horizontal.length() / walk_speed if is_on_floor() else 0.0
	_update_head_bob(delta, speed_ratio)
	weapon.set_motion(speed_ratio)
	_update_stamina(delta)
	_update_interaction()
	_handle_combat_input()


func _process(delta: float) -> void:
	if _shake > 0.0:
		_shake = maxf(_shake - delta * 2.5, 0.0)
		var s := _shake * _shake
		camera.h_offset = randf_range(-1.0, 1.0) * 0.06 * s
		camera.v_offset = randf_range(-1.0, 1.0) * 0.06 * s
	else:
		camera.h_offset = 0.0
		camera.v_offset = 0.0


# --- Look ------------------------------------------------------------------

func _apply_look(delta_degrees: Vector2) -> void:
	if not input_enabled:
		return
	rotate_y(deg_to_rad(-delta_degrees.x))
	var y := -delta_degrees.y if not Settings.invert_y else delta_degrees.y
	_pitch = clampf(_pitch + y, min_pitch, max_pitch)
	head.rotation.x = deg_to_rad(_pitch)


func _update_head_bob(delta: float, speed_ratio: float) -> void:
	if not input_enabled:
		return  # cinematic head motion (waking, dying) owns the head
	if speed_ratio > 0.05:
		_bob_time += delta * bob_frequency * TAU * clampf(speed_ratio, 0.3, 1.2) * 0.5
	var target_y := eye_height + sin(_bob_time * 2.0) * bob_amplitude * speed_ratio
	head.position.y = lerpf(head.position.y, target_y, minf(delta * 12.0, 1.0))
	head.position.x = cos(_bob_time) * bob_amplitude * 0.5 * speed_ratio


# --- Stamina ---------------------------------------------------------------

func consume_stamina(amount: float) -> void:
	stamina = maxf(stamina - amount, 0.0)
	_regen_cooldown = stamina_regen_delay
	Events.player_stamina_changed.emit(stamina, max_stamina)


func _update_stamina(delta: float) -> void:
	if _regen_cooldown > 0.0:
		_regen_cooldown -= delta
		return
	if stamina < max_stamina and not weapon.is_blocking and not weapon.is_busy():
		stamina = minf(stamina + stamina_regen * delta, max_stamina)
		Events.player_stamina_changed.emit(stamina, max_stamina)


# --- Combat ----------------------------------------------------------------

func _handle_combat_input() -> void:
	if not input_enabled:
		weapon.set_blocking(false)
		return
	if Input.is_action_just_pressed("attack"):
		try_attack()
	weapon.set_blocking(Input.is_action_pressed("block") and stamina > 1.0)
	if Input.is_action_just_pressed("interact") and _current_interactable:
		_current_interactable.interact(self)


func try_attack() -> void:
	var w := GameState.equipped_weapon
	if w == null or weapon.is_busy() or stamina < w.stamina_cost * 0.5:
		return
	consume_stamina(w.stamina_cost)
	weapon.attack(GameState.get_attack_damage(), w.knockback)


func _modify_incoming_damage(info: DamageInfo) -> DamageInfo:
	if not weapon.is_blocking or info.source == null:
		return info
	var to_source := info.source.global_position - global_position
	to_source.y = 0.0
	var forward := -global_basis.z
	if to_source.length_squared() < 0.0001 or forward.dot(to_source.normalized()) < 0.3:
		return info
	var w := GameState.equipped_weapon
	var reduction := w.block_reduction if w else 0.3
	var absorbed := info.amount * reduction
	consume_stamina(absorbed * block_stamina_per_damage)
	if stamina <= 0.0:
		reduction *= 0.4  # guard broken
		weapon.set_blocking(false)
	info.amount *= 1.0 - reduction
	info.knockback *= 0.5
	info.blocked = true
	weapon.on_block_impact()
	return info


func _on_hit_landed(_hurtbox: HurtboxComponent) -> void:
	_shake = maxf(_shake, 0.35)


func _on_damaged(info: DamageInfo) -> void:
	_shake = maxf(_shake, 0.5 if info.blocked else 1.0)
	var push := info.direction_to(self) * info.knockback
	velocity.x += push.x
	velocity.z += push.z
	Events.player_damaged.emit(info.amount)


func _on_health_changed(current: float, maximum: float) -> void:
	GameState.player_health = current
	Events.player_health_changed.emit(current, maximum)


func _on_consumable_used(item: ConsumableData) -> void:
	health.heal(item.heal_amount)
	if item.stamina_restore > 0.0:
		stamina = minf(stamina + item.stamina_restore, max_stamina)
		Events.player_stamina_changed.emit(stamina, max_stamina)
	if item.use_message != "":
		Events.show_message(item.use_message)


func _on_stats_changed() -> void:
	max_stamina = GameState.get_max_stamina()
	stamina = minf(stamina, max_stamina)
	health.set_max_health(GameState.get_max_health())
	Events.player_stamina_changed.emit(stamina, max_stamina)


## Opening of gameplay: lying in the grass, staring at the sky, then rising.
func play_wake_up(duration: float = 7.0) -> void:
	input_enabled = false
	Events.wake_up_started.emit(duration)
	head.position.y = 0.35
	head.rotation = Vector3(deg_to_rad(72.0), 0.0, deg_to_rad(-14.0))
	weapon.visible = false
	var tw := create_tween()
	tw.tween_interval(duration * 0.45)
	# Sit up...
	tw.tween_property(head, "rotation", Vector3(deg_to_rad(18.0), 0.0, deg_to_rad(-4.0)), duration * 0.2).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(head, "position:y", 0.9, duration * 0.2).set_trans(Tween.TRANS_SINE)
	tw.tween_interval(duration * 0.1)
	# ...and stand, unsteady.
	tw.tween_property(head, "position:y", eye_height, duration * 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(head, "rotation", Vector3.ZERO, duration * 0.25).set_trans(Tween.TRANS_SINE)
	await tw.finished
	_pitch = 0.0
	weapon.visible = true
	weapon.equip(GameState.equipped_weapon)
	input_enabled = true


func kill() -> void:
	if not health.is_dead:
		health.take_damage(DamageInfo.new(health.current_health + 1.0))


func _on_died() -> void:
	input_enabled = false
	weapon.set_blocking(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Events.interaction_prompt_changed.emit("")
	var tween := create_tween().set_parallel(true)
	tween.tween_property(head, "position:y", 0.35, 1.2).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tween.tween_property(head, "rotation:z", deg_to_rad(75.0), 1.0).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(weapon, "pose_position:y", -1.2, 0.6)
	Events.player_died.emit()


func _on_menu_state_changed(is_open: bool) -> void:
	if health.is_dead or Settings.uses_touch_controls():
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if is_open else Input.MOUSE_MODE_CAPTURED


# --- Interaction -----------------------------------------------------------

func _update_interaction() -> void:
	var found: Interactable = null
	if input_enabled and interact_ray.is_colliding():
		var hit := interact_ray.get_collider() as Interactable
		if hit and hit.can_interact(self):
			found = hit
	if found != _current_interactable:
		_current_interactable = found
		Events.interaction_prompt_changed.emit(found.get_prompt() if found else "")
