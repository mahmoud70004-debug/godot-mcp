class_name AmbientDrone
extends AudioStreamPlayer
## Procedural ambience placeholder: gusting brown-noise wind over a low,
## slowly beating drone. Replace with recorded ambience in the audio phase.

@export var wind_volume := 0.35
@export var drone_volume := 0.1
@export var drone_frequency := 55.0
@export var mix_rate := 22050.0

var _playback: AudioStreamGeneratorPlayback
var _brown := 0.0
var _phase_a := 0.0
var _phase_b := 0.0
var _t := 0.0


func _ready() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = mix_rate
	gen.buffer_length = 0.4
	stream = gen
	bus = &"Ambience"
	play()
	_playback = get_stream_playback() as AudioStreamGeneratorPlayback


func _process(_delta: float) -> void:
	if _playback == null:
		return
	var frames := _playback.get_frames_available()
	var dt := 1.0 / mix_rate
	for i in frames:
		_t += dt
		_brown = clampf(_brown + randf_range(-1.0, 1.0) * 0.02, -1.0, 1.0) * 0.998
		var gust := 0.55 + 0.45 * sin(_t * 0.23) * sin(_t * 0.071 + 1.3)
		_phase_a = fmod(_phase_a + drone_frequency * dt, 1.0)
		_phase_b = fmod(_phase_b + (drone_frequency * 1.007) * dt, 1.0)
		var drone := (sin(_phase_a * TAU) + sin(_phase_b * TAU)) * 0.5
		var s := _brown * wind_volume * gust * 3.0 + drone * drone_volume
		_playback.push_frame(Vector2(s, s))
