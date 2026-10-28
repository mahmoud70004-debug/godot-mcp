class_name PrologueCutscene
extends Node3D
## Opening cinematic: the night of the victory feast. Warm, loud and alive -
## until the knight walks out of the walls to sleep under the stars. The last
## beat inverts everything (music warps and dies, cold wind) and hands over to
## gameplay, where the same knight wakes up in the cursed kingdom.

const NEXT_SCENE := "res://src/levels/valdron/valdron_overworld.tscn"
const FIREWORK_SFX := preload("res://assets/audio/sfx/firework.wav")
const BONFIRE := Vector3(0.0, 0.0, -18.5)
const KNIGHT_SHEET := preload("res://assets/sprites/knight/knight.tres")
const VILLAGER_SHEETS: Array[SpriteSheetData] = [
	preload("res://assets/sprites/villager_0/villager_0.tres"),
	preload("res://assets/sprites/villager_1/villager_1.tres"),
	preload("res://assets/sprites/villager_2/villager_2.tres"),
	preload("res://assets/sprites/villager_3/villager_3.tres"),
	preload("res://assets/sprites/villager_4/villager_4.tres"),
	preload("res://assets/sprites/villager_5/villager_5.tres"),
	preload("res://assets/sprites/villager_6/villager_6.tres"),
	preload("res://assets/sprites/villager_7/villager_7.tres"),
]

@export var camera: Camera3D
@export var music: AudioStreamPlayer3D
@export var wind: AudioStreamPlayer
@export var post_process: CanvasLayer

var _knight: PixelSprite3D
var _cheerers: Array[PixelSprite3D] = []
var _ring: Node3D
var _fireworks := false
var _firework_timer := 0.0
var _follow := false
var _skipped := false
var _finished := false
var _rng := RandomNumberGenerator.new()

var _fade: ColorRect
var _subtitle: Label
var _title: Label
var _bars: Array[ColorRect] = []


func _ready() -> void:
	_rng.seed = 1999
	_build_overlay()
	_spawn_crowd()
	_spawn_knight()
	_apply_festive_grade()
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_run()


func _process(delta: float) -> void:
	if _ring:
		_ring.rotation.y += delta * 0.35
	if _fireworks:
		_firework_timer -= delta
		if _firework_timer <= 0.0:
			_firework_timer = _rng.randf_range(0.6, 1.6)
			_launch_firework()
	if _follow and _knight:
		var k := _knight.global_position
		camera.global_position = camera.global_position.lerp(k + Vector3(0.0, 2.4, -4.8), minf(delta * 3.0, 1.0))
		camera.look_at(k + Vector3(0.0, 1.2, 6.0))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("interact"):
		_skip()


# --- Timeline ----------------------------------------------------------------

func _run() -> void:
	_fireworks = true
	_fade_to(0.0, 2.5)
	_say("The war was over. Loris had fallen.", 1.0, 5.0)
	await _shot(Vector3(10, 26, 40), Vector3(0, 2, -12), Vector3(1.5, 12.5, 5.0), Vector3(0, 1.0, -14), 8.0, 55.0)
	if _skipped:
		return

	_say("Valdron sang, and drank, and sang again,\nuntil the stars themselves grew tired.", 0.3, 6.0)
	await _shot(Vector3(-0.9, 1.7, 3.0), Vector3(0, 1.4, -8), Vector3(-0.5, 1.6, -5.0), Vector3(0.4, 1.5, -11), 7.0, 62.0)
	if _skipped:
		return

	_say("Among them was a young knight of the King's guard.", 0.5, 5.0)
	_knight.play(&"toast")
	for v in _cheerers:
		v.anim = &"cheer"
	await _shot(Vector3(2.4, 1.8, -7.4), Vector3(0.6, 1.65, -10.6), Vector3(1.5, 1.75, -8.4), Vector3(0.6, 1.7, -10.6), 6.0, 50.0)
	if _skipped:
		return

	_say("When the wine grew heavy, he slipped away from the noise...", 0.5, 5.5)
	_knight.play(&"cheer")
	_shot(Vector3(-2.6, 1.6, -5.5), Vector3(0.6, 1.5, -10.6), Vector3(-2.4, 1.6, -2.0), Vector3(0.0, 1.3, -4.0), 7.0, 58.0)
	await get_tree().create_timer(2.2).timeout
	if _skipped:
		return
	_knight.play(&"walk")
	var walk_in := create_tween()
	walk_in.tween_property(_knight, "rotation:y", PI, 0.6)
	walk_in.parallel().tween_property(_knight, "position", Vector3(0.0, 0.0, -1.5), 4.6)
	await get_tree().create_timer(4.8).timeout
	if _skipped:
		return

	_fireworks = false
	_knight.position = Vector3(0.0, 0.0, 8.0)
	camera.global_position = Vector3(0.0, 2.4, 3.2)
	_follow = true
	_say("...to rest beneath the stars, on the soft grass outside the walls.", 0.8, 6.0)
	var walk_out := create_tween()
	walk_out.tween_property(_knight, "position", Vector3(1.2, 0.0, 27.4), 10.0)
	await walk_out.finished
	if _skipped:
		return

	_follow = false
	_say("He closed his eyes. Only for a moment.", 2.5, 5.0)
	_lie_down()
	await _shot(camera.global_position, Vector3(1.2, 0.8, 27.4), Vector3(1.2, 2.6, 25.4), Vector3(1.2, 0.3, 26.6), 3.0, 55.0)
	await _shot(Vector3(1.2, 2.6, 25.4), Vector3(1.2, 0.3, 26.6), Vector3(1.0, 8.0, 25.8), Vector3(1.2, 0.0, 26.4), 6.0, 55.0)
	if _skipped:
		return
	await _invert_and_finish()


## Stretch (slowed so the whole beat lasts about 2.4 s), then settle into the lying frame.
func _lie_down() -> void:
	_knight.speed_scale = 0.62
	_knight.play(&"stretch", true)
	await _knight.animation_finished
	_knight.speed_scale = 1.0
	_knight.play(&"lie")


## Everything turns: the music slows and groans into silence, cold wind rises.
func _invert_and_finish(fast: bool = false) -> void:
	if _finished:
		return
	_finished = true
	var k := 0.35 if fast else 1.0
	_fade_to(1.0, 2.5 * k)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(music, "pitch_scale", 0.3, 3.0 * k).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(music, "volume_db", -40.0, 3.5 * k).set_ease(Tween.EASE_IN)
	wind.volume_db = -40.0
	wind.play()
	tw.tween_property(wind, "volume_db", -6.0, 4.0 * k)
	await tw.finished
	music.stop()
	_title.modulate.a = 0.0
	var title_tw := create_tween()
	title_tw.tween_property(_title, "modulate:a", 1.0, 1.5 * k)
	title_tw.tween_interval(1.5 * k)
	title_tw.tween_property(_title, "modulate:a", 0.0, 1.2 * k)
	await title_tw.finished
	GameState.set_flag("prologue_seen")
	GameState.set_flag("waking_up")
	SceneLoader.change_scene(NEXT_SCENE, 0.2)


func _skip() -> void:
	if _skipped or _finished:
		return
	_skipped = true
	_fireworks = false
	_follow = false
	_subtitle.modulate.a = 0.0
	_invert_and_finish(true)


# --- Camera, text, fades -----------------------------------------------------

func _shot(from_pos: Vector3, from_look: Vector3, to_pos: Vector3, to_look: Vector3, duration: float, fov: float) -> void:
	camera.fov = fov
	_place_camera(0.0, from_pos, from_look, to_pos, to_look)
	var tw := create_tween()
	tw.tween_method(_place_camera.bind(from_pos, from_look, to_pos, to_look), 0.0, 1.0, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished


func _place_camera(t: float, a: Vector3, look_a: Vector3, b: Vector3, look_b: Vector3) -> void:
	if _follow:
		return
	camera.global_position = a.lerp(b, t)
	camera.look_at(look_a.lerp(look_b, t))


func _say(text: String, delay: float, duration: float) -> void:
	await get_tree().create_timer(delay).timeout
	if _skipped:
		return
	_subtitle.text = text
	var tw := create_tween()
	tw.tween_property(_subtitle, "modulate:a", 1.0, 0.6)
	tw.tween_interval(duration)
	tw.tween_property(_subtitle, "modulate:a", 0.0, 0.8)


func _fade_to(alpha: float, duration: float) -> void:
	create_tween().tween_property(_fade, "color:a", alpha, duration)


func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color.BLACK
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.anchor_right = 1.0
		if top:
			bar.offset_bottom = 34.0
		else:
			bar.anchor_top = 1.0
			bar.anchor_bottom = 1.0
			bar.offset_top = -34.0
		layer.add_child(bar)
		_bars.append(bar)
	_subtitle = Label.new()
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.anchor_left = 0.0
	_subtitle.anchor_right = 1.0
	_subtitle.anchor_top = 1.0
	_subtitle.anchor_bottom = 1.0
	_subtitle.offset_top = -33.0
	_subtitle.offset_bottom = -3.0
	_subtitle.add_theme_color_override("font_color", Color(0.92, 0.86, 0.7))
	_subtitle.modulate.a = 0.0
	layer.add_child(_subtitle)
	_title = Label.new()
	_title.text = "ROTTEN CROWN"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.set_anchors_preset(Control.PRESET_FULL_RECT)
	_title.add_theme_font_size_override("font_size", 36)
	_title.add_theme_color_override("font_color", Color(0.6, 0.08, 0.06))
	_title.modulate.a = 0.0
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 1)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_fade)
	layer.add_child(_title)
	var skip := Button.new()
	skip.text = "SKIP >>"
	skip.anchor_left = 1.0
	skip.anchor_right = 1.0
	skip.offset_left = -70.0
	skip.offset_right = -8.0
	skip.offset_top = 6.0
	skip.offset_bottom = 26.0
	skip.focus_mode = Control.FOCUS_NONE
	skip.pressed.connect(_skip)
	layer.add_child(skip)


func _apply_festive_grade() -> void:
	if post_process == null:
		return
	var screen := post_process.get_node_or_null("Screen") as ColorRect
	if screen == null or screen.material == null:
		return
	# Duplicate so the warm grade does not leak into the gameplay scenes.
	var mat := screen.material.duplicate() as ShaderMaterial
	mat.set_shader_parameter("desaturation", 0.08)
	mat.set_shader_parameter("tint", Color(1.0, 0.97, 0.93))
	mat.set_shader_parameter("grain_strength", 0.035)
	mat.set_shader_parameter("contrast", 1.1)
	mat.set_shader_parameter("lift", Color(0.01, 0.012, 0.025))
	mat.set_shader_parameter("vignette_strength", 0.45)
	screen.material = mat


# --- Population ----------------------------------------------------------------

func _spawn_crowd() -> void:
	var crowd := Node3D.new()
	crowd.name = "Crowd"
	add_child(crowd)
	var seed_i := 10
	# Revellers along the feast tables.
	for side in [-1.0, 1.0]:
		var z := -8.6
		while z < -1.0:
			var v := _villager(crowd, seed_i, Vector3(side * 4.65, 0.0, z + _rng.randf_range(-0.2, 0.2)), side * PI * 0.5)
			var cheering := _rng.randf() < 0.35
			v.anim = &"cheer" if cheering else &"idle"
			v.speed_scale = _rng.randf_range(0.8, 1.2)
			if not cheering:
				_cheerers.append(v)
			seed_i += 1
			z += 1.45
	# Ring dance around the bonfire.
	_ring = Node3D.new()
	_ring.name = "DanceRing"
	_ring.position = BONFIRE
	crowd.add_child(_ring)
	for i in 10:
		var a := TAU * i / 10.0
		var p := Vector3(cos(a) * 3.3, 0.0, sin(a) * 3.3)
		var v := _villager(_ring, seed_i, p, atan2(p.x, p.z) + PI * 0.5)
		v.anim = &"dance"
		v.speed_scale = _rng.randf_range(0.9, 1.1)
		seed_i += 1
	# Musicians and a few guests around the high table.
	for x in [-5.2, 5.2]:
		var m := _villager(crowd, seed_i, BONFIRE + Vector3(x, 0.0, 1.5), atan2(x, 1.5))
		m.anim = &"music"
		seed_i += 1
	for p in [Vector3(-1.6, 0, -10.4), Vector3(2.1, 0, -10.2), Vector3(3.2, 0, -10.8), Vector3(-2.8, 0, -10.0)]:
		var g := _villager(crowd, seed_i, p, PI + _rng.randf_range(-0.6, 0.6))
		g.anim = &"idle"
		_cheerers.append(g)
		seed_i += 1


func _villager(parent: Node3D, seed_value: int, pos: Vector3, yaw: float) -> PixelSprite3D:
	var v := PixelSprite3D.new()
	v.sheet = VILLAGER_SHEETS[seed_value % VILLAGER_SHEETS.size()]
	v.position = pos
	v.rotation.y = yaw
	v.speed_scale = _rng.randf_range(0.85, 1.15)
	parent.add_child(v)
	# Desynchronise the crowd: start each at a random point of the loop.
	v._time = _rng.randf_range(0.0, 3.0)
	return v


func _spawn_knight() -> void:
	_knight = PixelSprite3D.new()
	_knight.sheet = KNIGHT_SHEET
	_knight.anim = &"idle"
	_knight.name = "Knight"
	_knight.position = Vector3(0.6, 0.0, -10.6)
	_knight.rotation.y = PI
	add_child(_knight)


func _launch_firework() -> void:
	var pos := Vector3(_rng.randf_range(-28.0, 28.0), _rng.randf_range(17.0, 28.0), _rng.randf_range(-34.0, -6.0))
	var colors := [Color(1.0, 0.75, 0.3), Color(1.0, 0.3, 0.25), Color(0.6, 0.8, 1.0), Color(1.0, 0.95, 0.8)]
	var color: Color = colors[_rng.randi() % colors.size()]
	var burst := CPUParticles3D.new()
	burst.position = pos
	burst.amount = 70
	burst.lifetime = 1.8
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.direction = Vector3.UP
	burst.spread = 180.0
	burst.initial_velocity_min = 5.0
	burst.initial_velocity_max = 8.0
	burst.gravity = Vector3(0.0, -2.5, 0.0)
	burst.damping_min = 1.5
	burst.damping_max = 2.5
	var quad := QuadMesh.new()
	quad.size = Vector2(0.35, 0.35)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.disable_fog = true
	quad.material = mat
	burst.mesh = quad
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray([Color(1, 1, 1, 1), color, Color(color.r, color.g, color.b, 0.0)])
	ramp.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	burst.color_ramp = ramp
	add_child(burst)
	burst.emitting = true
	var sfx := AudioStreamPlayer3D.new()
	sfx.stream = FIREWORK_SFX
	sfx.bus = &"SFX"
	sfx.unit_size = 25.0
	sfx.position = pos
	add_child(sfx)
	sfx.play()
	get_tree().create_timer(3.5).timeout.connect(func() -> void:
		burst.queue_free()
		sfx.queue_free())
