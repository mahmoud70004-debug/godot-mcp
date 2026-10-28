class_name WeatherController
extends Node
## Rain + lightning (decision D6): drives the retro_post `rain_amount` / `flash`
## uniforms, a looping rain bed, random lightning with delayed thunder, and a
## brief ambient boost on the WorldEnvironment. Set RC_FORCE_LIGHTNING=1 to
## trigger a strike at ~2.75 s (a value above 1 is the strike time in seconds).

const RAIN_STREAM: AudioStream = preload("res://assets/audio/ambience/rain.wav")
const THUNDER_STREAMS: Array[AudioStream] = [
	preload("res://assets/audio/sfx/thunder_roll.wav"),
	preload("res://assets/audio/sfx/thunder_crack.wav"),
]
## Flash pulses: [start time, duration, peak] (seconds from the strike).
const PULSES: Array[Vector3] = [
	Vector3(0.0, 0.14, 1.0),
	Vector3(0.16, 0.12, 0.6),
	Vector3(0.3, 0.1, 0.8),
]
const FLASH_LENGTH := 0.4
const AMBIENT_BOOST := 2.2
const RAIN_DB_QUIET := -34.0
const RAIN_DB_LOUD := -8.0

@export_range(0.0, 1.0) var rain := 0.0:
	set(value):
		rain = clampf(value, 0.0, 1.0)
		_apply_rain()
@export var lightning_interval := Vector2(14.0, 30.0)
@export var environment: WorldEnvironment
@export var post: CanvasLayer
@export var lightning_enabled := true
@export var rain_bus: StringName = &"Ambience"

var _material: ShaderMaterial
var _rain_player: AudioStreamPlayer
var _thunder_player: AudioStreamPlayer
var _next_strike := 0.0
var _strike_t := -1.0
var _thunder_in := -1.0
var _base_ambient := 0.0
var _have_base := false
var _fade_tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_setup_material()
	_rain_player = _make_player()
	_rain_player.stream = RAIN_STREAM
	_thunder_player = _make_player()
	_apply_rain()
	_next_strike = _roll_interval()
	var forced := OS.get_environment("RC_FORCE_LIGHTNING")
	if not forced.is_empty():
		_next_strike = forced.to_float() if forced.to_float() > 1.0 else 2.75


func _process(delta: float) -> void:
	if _thunder_in >= 0.0:
		_thunder_in -= delta
		if _thunder_in < 0.0:
			_thunder_player.stream = THUNDER_STREAMS[randi() % THUNDER_STREAMS.size()]
			_thunder_player.volume_db = lerpf(-14.0, -4.0, randf())
			_thunder_player.play()
	if _strike_t >= 0.0:
		_strike_t += delta
		_apply_flash(_strike_t)
		if _strike_t >= FLASH_LENGTH:
			_strike_t = -1.0
			_apply_flash(-1.0)
	if not lightning_enabled or rain <= 0.0:
		return
	_next_strike -= delta
	if _next_strike <= 0.0:
		strike()
		_next_strike = _roll_interval()


## Fade the rain to `amount` over `fade` seconds.
func set_rain(amount: float, fade: float = 2.0) -> void:
	if _fade_tween != null:
		_fade_tween.kill()
	if fade <= 0.0 or not is_inside_tree():
		rain = amount
		return
	_fade_tween = create_tween()
	_fade_tween.tween_property(self, "rain", clampf(amount, 0.0, 1.0), fade)


## Trigger one lightning strike now (flash, then thunder after a delay).
func strike() -> void:
	_strike_t = 0.0
	_thunder_in = randf_range(0.6, 2.5)


func _roll_interval() -> float:
	return randf_range(minf(lightning_interval.x, lightning_interval.y), maxf(lightning_interval.x, lightning_interval.y))


func _setup_material() -> void:
	if post == null:
		return
	var screen := post.get_node_or_null("Screen") as CanvasItem
	if screen == null or not (screen.material is ShaderMaterial):
		return
	_material = (screen.material as ShaderMaterial).duplicate() as ShaderMaterial
	screen.material = _material


func _make_player() -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.bus = rain_bus
	add_child(player)
	return player


func _apply_rain() -> void:
	if _material != null:
		_material.set_shader_parameter("rain_amount", rain)
	if _rain_player == null:
		return
	if rain <= 0.01:
		_rain_player.stop()
		return
	_rain_player.volume_db = lerpf(RAIN_DB_QUIET, RAIN_DB_LOUD, rain)
	if not _rain_player.playing:
		_rain_player.play()


func _apply_flash(t: float) -> void:
	var value := 0.0
	if t >= 0.0:
		for pulse in PULSES:
			var x := (t - pulse.x) / pulse.y
			if x >= 0.0 and x <= 1.0:
				# Sharp rise, slower decay.
				value = maxf(value, pulse.z * (x / 0.2 if x < 0.2 else 1.0 - (x - 0.2) / 0.8))
	if _material != null:
		_material.set_shader_parameter("flash", value * 0.8)
	_boost_environment(value)


func _boost_environment(value: float) -> void:
	if environment == null or environment.environment == null:
		return
	var env := environment.environment
	if value > 0.0 and not _have_base:
		_base_ambient = env.ambient_light_energy
		_have_base = true
	if _have_base:
		env.ambient_light_energy = _base_ambient + value * AMBIENT_BOOST
		if value <= 0.0:
			env.ambient_light_energy = _base_ambient
			_have_base = false
