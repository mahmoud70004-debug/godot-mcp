class_name Moonlight
extends Node
## The one night lighting model of the overworld (V7). Pushes the moon, the hemispheric sky
## ambient, the baked canopy shade map, the drifting cloud shadows and the wind into the
## global shader parameters (project.godot [shader_globals]) read by
## assets/shaders/moonlight.gdshaderinc, so ground, trees, impostors, floor kits, props and
## grass are all lit by the same moon.
##
## The project defaults of those globals are the "no model" look (no shade, no clouds, no
## wind) used by scenes without this node (prologue, tests). RenderingServer globals outlive
## the scene, so this node puts the defaults back when it leaves the tree.
## While a thick cloud passes over the camera the moon itself dims a little: the same cloud
## noise the shaders scroll is sampled on the CPU and eases the light energy (and so
## moon_color) between the base energy and (1 - cloud_strength * DIM_FRACTION) of it.
## Colours are pushed as they are (Compatibility renderer: global colours reach the shader
## unconverted).

## Where the canopy shade bake (tools/bake_world.gd) writes its map; used when shade_map is unset.
const SHADE_MAP_PATH := "res://assets/textures/world/moon_shade.png"
const CLOUD_NOISE_PATH := "res://assets/textures/cloud_noise.tres"
## Fraction of cloud_strength the moon itself loses under the thickest cloud.
const DIM_FRACTION := 0.6
## Time constant (s) of the moon following a cloud (~2 s to settle).
const DIM_SMOOTHING := 0.7
## The cloud shape (same band as moon_cloud() in the include).
const CLOUD_LOW := 0.45
const CLOUD_HIGH := 0.75
## Every global this node drives (reset to the project defaults on exit).
const GLOBALS: Array[StringName] = [
	&"moon_dir", &"moon_color", &"sky_ambient_top", &"sky_ambient_bottom", &"shade_map",
	&"shade_rect", &"cloud_tex", &"cloud_scroll", &"cloud_scale", &"cloud_strength", &"wind",
]

## The node currently driving the globals (a scene loaded over another must not be reset by it).
static var _active: Moonlight

## The moon; moon_dir / moon_color follow it, its energy dims under thick clouds.
@export var light: DirectionalLight3D
## Its ambient energy (WeatherController's lightning boost) scales the sky ambient.
@export var environment: WorldEnvironment
## How dark a thick cloud makes the moonlight (0..1).
@export_range(0.0, 1.0) var cloud_strength := 0.45
## Metres per second the cloud shadows drift (x, z).
@export var cloud_scroll := Vector2(0.6, 0.25)
## Cloud texture repeats per metre.
@export var cloud_scale := 0.012
## (dir.x, dir.z, strength in metres, speed).
@export var wind := Vector4(0.8, 0.6, 0.12, 1.0)
## Night sky ambient from above (linear, multiplied by albedo).
@export var ambient_top := Color(0.16, 0.2, 0.34)
## Bounce from the ground (darker).
@export var ambient_bottom := Color(0.05, 0.055, 0.07)
## Baked canopy shade (1 moon, 0 shade); falls back to SHADE_MAP_PATH, else no shade.
@export var shade_map: Texture2D
## World rect the shade map covers (x0, z0, x1, z1).
@export var shade_rect := Vector4(-260.0, 30.0, 260.0, 520.0)
## Tileable cloud noise (the sky's clouds, so they read as the same weather).
@export var cloud_texture: Texture2D

var _base_energy := 1.0
var _base_ambient := 1.0
var _dim := 1.0
var _cloud_image: Image
var _shader_time := 0.0
var _time_rollover := 3600.0
var _pushed_dir := Vector3.ZERO
var _pushed_color := Color(0, 0, 0, 0)
var _pushed_ambient := -1.0


func _ready() -> void:
	_active = self
	if shade_map == null and ResourceLoader.exists(SHADE_MAP_PATH):
		shade_map = load(SHADE_MAP_PATH) as Texture2D
	if cloud_texture == null:
		cloud_texture = load(CLOUD_NOISE_PATH) as Texture2D
	if light != null:
		_base_energy = light.light_energy
	if environment != null and environment.environment != null:
		_base_ambient = maxf(environment.environment.ambient_light_energy, 0.001)
	# Shader TIME is the engine's scaled frame time since start-up, wrapped at the rollover.
	_time_rollover = float(ProjectSettings.get_setting("rendering/limits/time/time_rollover_secs", 3600.0))
	_shader_time = fmod(Time.get_ticks_usec() / 1000000.0, _time_rollover)
	_push_static()
	_push_light(true)
	_fetch_cloud_image()


func _exit_tree() -> void:
	if light != null and is_instance_valid(light):
		light.light_energy = _base_energy
	if _active != self:
		return
	_active = null
	reset_globals()


func _process(delta: float) -> void:
	_shader_time = fmod(_shader_time + delta, _time_rollover)
	if light != null:
		var target := 1.0 - cloud_strength * DIM_FRACTION * _cloud_cover_at_camera()
		_dim = lerpf(_dim, target, 1.0 - exp(-delta / DIM_SMOOTHING))
		var energy := _base_energy * _dim
		if absf(light.light_energy - energy) > 0.0005:
			light.light_energy = energy
	_push_light(false)


## Pushes every global of the model (call after changing an export at runtime).
func apply() -> void:
	_push_static()
	_push_light(true)


## Puts every global this node drives back to its project default (the "no model" look).
static func reset_globals() -> void:
	for global_name in GLOBALS:
		var setting: Variant = ProjectSettings.get_setting("shader_globals/" + global_name)
		if not setting is Dictionary:
			continue
		var value: Variant = (setting as Dictionary).get("value")
		if value is String:
			# Sampler defaults are paths; "" (null) samples white.
			var path := value as String
			value = load(path) if not path.is_empty() and ResourceLoader.exists(path) else null
		RenderingServer.global_shader_parameter_set(global_name, value)


func _push_static() -> void:
	RenderingServer.global_shader_parameter_set(&"shade_map", shade_map)
	RenderingServer.global_shader_parameter_set(&"shade_rect", shade_rect)
	RenderingServer.global_shader_parameter_set(&"cloud_tex", cloud_texture)
	RenderingServer.global_shader_parameter_set(&"cloud_scroll", cloud_scroll)
	RenderingServer.global_shader_parameter_set(&"cloud_scale", cloud_scale)
	RenderingServer.global_shader_parameter_set(&"cloud_strength", cloud_strength)
	RenderingServer.global_shader_parameter_set(&"wind", wind)
	_pushed_ambient = -1.0


## moon_dir / moon_color from the light and the sky ambient, only when they changed.
func _push_light(force: bool) -> void:
	if light != null:
		var dir := light.global_basis.z.normalized()
		if force or not dir.is_equal_approx(_pushed_dir):
			_pushed_dir = dir
			RenderingServer.global_shader_parameter_set(&"moon_dir", dir)
		# Linear, like the renderer's own lighting (light_color is an sRGB colour).
		var c := light.light_color.srgb_to_linear()
		var e := light.light_energy
		var color := Color(c.r * e, c.g * e, c.b * e, 1.0)
		if force or not color.is_equal_approx(_pushed_color):
			_pushed_color = color
			RenderingServer.global_shader_parameter_set(&"moon_color", color)
	var ambient := 1.0
	if environment != null and environment.environment != null:
		ambient = environment.environment.ambient_light_energy / _base_ambient
	if force or absf(ambient - _pushed_ambient) > 0.001:
		_pushed_ambient = ambient
		RenderingServer.global_shader_parameter_set(&"sky_ambient_top", _scaled(ambient_top, ambient))
		RenderingServer.global_shader_parameter_set(&"sky_ambient_bottom", _scaled(ambient_bottom, ambient))


static func _scaled(c: Color, k: float) -> Color:
	return Color(c.r * k, c.g * k, c.b * k, 1.0)


## The CPU copy of the cloud noise (NoiseTexture2D generates on a thread: wait for it).
func _fetch_cloud_image() -> void:
	if cloud_texture == null:
		return
	var img := cloud_texture.get_image()
	if img == null:
		if not cloud_texture.changed.is_connected(_fetch_cloud_image):
			cloud_texture.changed.connect(_fetch_cloud_image, CONNECT_ONE_SHOT)
		return
	if img.is_compressed():
		img = img.duplicate() as Image
		img.decompress()
	_cloud_image = img


## 0 clear .. 1 thick cloud at the camera, the same shape as moon_cloud() in the include.
func _cloud_cover_at_camera() -> float:
	if _cloud_image == null or cloud_strength <= 0.0:
		return 0.0
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return 0.0
	var p := cam.global_position
	var uv := (Vector2(p.x, p.z) + cloud_scroll * _shader_time) * cloud_scale
	return smoothstep(CLOUD_LOW, CLOUD_HIGH, _sample_wrapped(uv))


## Bilinear, repeating sample of the cloud image's red channel at a uv.
func _sample_wrapped(uv: Vector2) -> float:
	var w := _cloud_image.get_width()
	var h := _cloud_image.get_height()
	var x := (uv.x - floorf(uv.x)) * w - 0.5
	var y := (uv.y - floorf(uv.y)) * h - 0.5
	var x0 := floori(x)
	var y0 := floori(y)
	var fx := x - x0
	var fy := y - y0
	var x0w := posmod(x0, w)
	var x1w := posmod(x0 + 1, w)
	var y0w := posmod(y0, h)
	var y1w := posmod(y0 + 1, h)
	var top := lerpf(_cloud_image.get_pixel(x0w, y0w).r, _cloud_image.get_pixel(x1w, y0w).r, fx)
	var bottom := lerpf(_cloud_image.get_pixel(x0w, y1w).r, _cloud_image.get_pixel(x1w, y1w).r, fx)
	return lerpf(top, bottom, fy)
