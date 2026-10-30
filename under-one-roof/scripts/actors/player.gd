extends CharacterBody2D
## Gideon. Keyboard / gamepad / on-screen joystick movement, four-direction walk cycle
## and a reach area in front of him used to pick what to interact with.

signal target_changed(area: Area2D)

const WALK_SPEED := 72.0
const RUN_SPEED := 112.0
const DIRS := {"down": 0, "left": 1, "right": 2, "up": 3}
const ZOOM_MIN := 0.7
const ZOOM_MAX := 2.2
const REACH := {"down": Vector2(0, 10), "up": Vector2(0, -18), "left": Vector2(-13, -5), "right": Vector2(13, -5)}

@onready var sprite: Sprite2D = $Sprite
@onready var reach: Area2D = $Reach
@onready var camera: Camera2D = $Camera

var facing := "down"
var target: Area2D = null
var _action_frames: Array = []
var _action_t := 0.0
var _anim_t := 0.0
var _step_t := 0.0
var room_rect := Rect2()        # set indoors: the camera never zooms out past the room
var _touches := {}              # pinch-zoom: index -> position (touches the HUD did not take)
var _pinch_d := 0.0
var _zoom_save_t := -1.0        # saves the chosen zoom shortly after the player stops zooming


## Camera zoom the player chose (saved in the settings).
func zoom_level() -> float:
	return clampf(float(Game.settings.get("zoom", 1.0)), ZOOM_MIN, ZOOM_MAX)


func set_zoom_level(z: float) -> void:
	Game.settings["zoom"] = clampf(z, ZOOM_MIN, ZOOM_MAX)
	_zoom_save_t = 0.4


func zoom_step(dir: int) -> void:
	set_zoom_level(zoom_level() * (1.15 if dir > 0 else 1.0 / 1.15))


func _effective_zoom() -> float:
	var z := zoom_level()
	if room_rect.has_area():
		var view := get_viewport_rect().size
		z = maxf(z, maxf(view.x / room_rect.size.x, view.y / room_rect.size.y))
	return z


func _process(delta: float) -> void:
	if _zoom_save_t > 0.0:
		_zoom_save_t -= delta
		if _zoom_save_t <= 0.0:
			Game.save_settings()
	var z := _effective_zoom()
	var cur := camera.zoom.x
	if not is_equal_approx(cur, z):
		cur = lerpf(cur, z, 1.0 - exp(-delta * 10.0))
		if absf(cur - z) < 0.002:
			cur = z
		camera.zoom = Vector2(cur, cur)


func _ready() -> void:
	camera.zoom = Vector2.ONE * zoom_level()
	reach.area_entered.connect(func(_a): _pick_target())
	reach.area_exited.connect(func(_a): _pick_target())


func face(dir: String) -> void:
	facing = dir
	sprite.frame = DIRS[facing] * 4
	reach.position = REACH[facing]


## Plays the action row (row 4) of the sheet, e.g. [16, 17] for a hammer swing.
func play_action(frames: Array) -> void:
	_action_frames = frames
	_action_t = 0.0


func stop_action() -> void:
	_action_frames = []
	sprite.frame = DIRS[facing] * 4


func _physics_process(delta: float) -> void:
	if not _action_frames.is_empty():
		_action_t += delta * 5.0
		sprite.frame = _action_frames[int(_action_t) % _action_frames.size()]
		return
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
	_zoom_input(event)
	if Game.input_locked:
		return
	if event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		interact()


func interact() -> void:
	_pick_target()
	if target and not Game.input_locked:
		Director.interact(target)


## Mouse wheel, trackpad pinch, two-finger pinch on the world, +/- keys.
func _zoom_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			set_zoom_level(zoom_level() * 1.1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			set_zoom_level(zoom_level() / 1.1)
	elif event is InputEventMagnifyGesture:
		set_zoom_level(zoom_level() * event.factor)
	elif event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
		else:
			_touches.erase(event.index)
			if _touches.size() < 2:
				_pinch_d = 0.0
		if _touches.size() == 2:
			var v: Array = _touches.values()
			_pinch_d = (v[0] as Vector2).distance_to(v[1])
	elif event is InputEventScreenDrag and _touches.has(event.index):
		_touches[event.index] = event.position
		if _touches.size() == 2 and _pinch_d > 0.0:
			var v: Array = _touches.values()
			var d := (v[0] as Vector2).distance_to(v[1])
			if d > 8.0:
				set_zoom_level(zoom_level() * d / _pinch_d)
				_pinch_d = d
	elif event.is_action_pressed("zoom_in"):
		zoom_step(1)
	elif event.is_action_pressed("zoom_out"):
		zoom_step(-1)
