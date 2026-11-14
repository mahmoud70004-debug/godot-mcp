@tool
class_name FlickerLight
extends OmniLight3D
## Sickly candle / lantern flicker driven by 1D noise. Occasionally gutters.

@export var base_energy := 1.2
@export var flicker_amount := 0.45
@export var flicker_speed := 6.0
## Chance per second that the flame nearly dies for a moment.
@export var gutter_chance := 0.08
## The player's carried lantern: also drives the forest shaders' lantern globals
## (moonlight.gdshaderinc lantern_pos / lantern_light) every frame, 0 while hidden or gone.
@export var drives_shader_lantern := false

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
	if drives_shader_lantern:
		_push_lantern(is_visible_in_tree() and light_energy > 0.0)


func _exit_tree() -> void:
	if drives_shader_lantern and not Engine.is_editor_hint():
		_push_lantern(false)


## Position (w: attenuation) and linear colour x energy (a: range; 0 = no lantern).
func _push_lantern(on: bool) -> void:
	if not on:
		RenderingServer.global_shader_parameter_set(&"lantern_light", Vector4.ZERO)
		return
	var p := global_position
	var c := light_color.srgb_to_linear()
	RenderingServer.global_shader_parameter_set(&"lantern_pos", Vector4(p.x, p.y, p.z, omni_attenuation))
	RenderingServer.global_shader_parameter_set(&"lantern_light",
		Vector4(c.r * light_energy, c.g * light_energy, c.b * light_energy, omni_range))
