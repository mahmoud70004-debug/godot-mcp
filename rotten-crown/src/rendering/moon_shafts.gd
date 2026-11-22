class_name MoonShafts
extends MeshInstance3D
## V20: the volumetric moonlight shafts of the night (assets/shaders/moon_shafts.gdshader): a
## full-screen additive quad that follows the active camera and marches the haze from the baked canopy
## shade map. Steps follow the graphics quality, the strength follows the moon's brightness (thick
## clouds dim it), the camera's near / far plane feed the depth reconstruction.

const SHADER := preload("res://assets/shaders/moon_shafts.gdshader")
## Marching steps (Low, Medium, High).
const STEPS := [6, 10, 14]
@export var strength := 1.6

var _mat: ShaderMaterial
var _peak := 0.001
var _moon: DirectionalLight3D
# Last values pushed to the material (each set re-uploads it).
var _pushed_near := -1.0
var _pushed_far := -1.0
var _pushed_strength := -1.0


func _ready() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	mesh = quad
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The vertex shader pins the quad to the screen: never let culling drop it.
	extra_cull_margin = 16384.0
	top_level = true
	Events.quality_changed.connect(_on_quality_changed)
	_apply_quality()
	for node in get_parent().find_children("*", "DirectionalLight3D", true, false):
		_moon = node as DirectionalLight3D
		_peak = maxf(_moon.light_energy, 0.001)  # the level's own brightness, not a latched first frame
		break


## A method, not a lambda: the connection goes with this node.
func _on_quality_changed(_level: int) -> void:
	_apply_quality()


func _apply_quality() -> void:
	_mat.set_shader_parameter("steps", STEPS[clampi(Settings.quality, 0, 2)])
	_mat.set_shader_parameter("height_min", MoonShadeBaker.HEIGHT_MIN)
	_mat.set_shader_parameter("height_range", MoonShadeBaker.HEIGHT_RANGE)


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		visible = false
		return
	visible = true
	global_position = cam.global_position
	if not is_equal_approx(cam.near, _pushed_near):
		_pushed_near = cam.near
		_mat.set_shader_parameter("cam_near", cam.near)
	if not is_equal_approx(cam.far, _pushed_far):
		_pushed_far = cam.far
		_mat.set_shader_parameter("cam_far", cam.far)
	if _moon != null:
		_peak = maxf(_peak, _moon.light_energy)
		var k := strength * clampf(_moon.light_energy / _peak, 0.0, 1.0)
		if absf(k - _pushed_strength) > 0.002:
			_pushed_strength = k
			_mat.set_shader_parameter("strength", k)
