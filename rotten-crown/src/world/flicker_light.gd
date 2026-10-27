@tool
class_name FlickerLight
extends OmniLight3D
## Sickly candle / lantern flicker driven by 1D noise. Occasionally gutters.

@export var base_energy := 1.2
@export var flicker_amount := 0.45
@export var flicker_speed := 6.0
## Chance per second that the flame nearly dies for a moment.
@export var gutter_chance := 0.08

var _noise := FastNoiseLite.new()
var _t := 0.0
var _gutter := 0.0


func _ready() -> void:
	_noise.frequency = 0.5
	_noise.seed = randi()
	_t = randf() * 100.0
	light_energy = base_energy


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_t += delta * flicker_speed
	if _gutter <= 0.0 and randf() < gutter_chance * delta:
		_gutter = randf_range(0.15, 0.5)
	var gutter_mul := 1.0
	if _gutter > 0.0:
		_gutter -= delta
		gutter_mul = 0.2
	light_energy = maxf(base_energy + _noise.get_noise_1d(_t) * flicker_amount * base_energy, 0.0) * gutter_mul
