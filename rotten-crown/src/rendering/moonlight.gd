class_name Moonlight
extends Node
## The one night lighting model of a scene (V7). Pushes the moon, the hemispheric sky
## ambient, the baked canopy shade map, the drifting cloud shadows and the wind into the
## global shader parameters (project.godot [shader_globals]) read by
## assets/shaders/moonlight.gdshaderinc, so ground, trees, impostors, floor kits, props and
## grass are all lit by the same moon.
##
## One sky ambient: the Environment's ambient light (the colour the Level blends per region,
## the energy WeatherController boosts for lightning) is the only knob. Every frame this node
## derives the globals from it:
##   sky_ambient_top    = srgb_to_linear(ambient_light_color) x ambient_light_energy x ambient_gain
##   sky_ambient_bottom = sky_ambient_top x ambient_bottom_factor
## The renderer itself applies srgb_to_linear(colour) x energy (measured, V7-R) to lit
## StandardMaterial props (houses, walls) - the one family that keeps the plain, flat
## Environment ambient (PLAN.md V7 decisions). The terrain switches the renderer's ambient off
## and takes moon_ambient() in its light() instead.
##
## The project defaults of the globals are the "no model" look (no shade, no clouds, no wind)
## used by scenes without this node (tests). RenderingServer globals outlive the scene, so this
## node puts the defaults back when it leaves the tree.
## While a thick cloud passes over the camera the moon itself dims a little: the same cloud
## noise the shaders scroll is sampled on the CPU and eases the light energy (and so
## moon_color) between the base energy and (1 - cloud_strength * DIM_FRACTION) of it.
## Colours are pushed linear (moon_color, the sky ambient); the shaders' helpers convert.
##
## Cloud clock: the drift is pushed as an offset (`cloud_offset`, metres) that this node
## accumulates from 0 on its first frame, with process_mode ALWAYS (the clouds keep drifting
## in the pause menu like the shader TIME-driven wind; only the moon dimming pauses). The
## shaders never read TIME for the clouds, so the CPU cover estimate and the drawn shadows are
## the same clouds whatever the engine's TIME origin (engine start) or frame pacing.

## Where the canopy shade bake (tools/bake_world.gd) writes its map; used when shade_map is unset
## and use_shade_map is on.
const SHADE_MAP_PATH := "res://assets/textures/world/moon_shade.png"
const CLOUD_NOISE_PATH := "res://assets/textures/cloud_noise.tres"
## Fraction of cloud_strength the moon itself loses under the thickest cloud.
const DIM_FRACTION := 0.6
## Time constant (s) of the moon following a cloud (~2 s to settle).
const DIM_SMOOTHING := 0.7
## The cloud shape (same band as moon_cloud() in the include).
const CLOUD_LOW := 0.45
const CLOUD_HIGH := 0.75
## Wrapped lambert of the grass family (moon_light_ratio() in moonlight.gdshaderinc): the reference
## irradiance is taken for an up normal with this wrap.
const GRASS_WRAP := 0.5
## Every global this node drives (reset to the project defaults on exit).
const GLOBALS: Array[StringName] = [
	&"moon_dir", &"moon_color", &"sky_ambient_top", &"sky_ambient_bottom", &"moon_ref_irr",
	&"shade_map", &"shade_rect", &"cloud_tex", &"cloud_offset", &"cloud_scale", &"cloud_strength",
	&"wind", &"wind_ref",
]

## The node currently driving the globals (a scene loaded over another must not be reset by it).
static var _active: Moonlight

## The moon; moon_dir / moon_color follow it, its energy dims under thick clouds.
@export var light: DirectionalLight3D
## Its ambient light (colour and energy) is the sky ambient of every family.
@export var environment: WorldEnvironment
## Linear gain from the Environment ambient to the moon model's sky ambient from above (the
## lit props keep the plain Environment ambient).
@export var ambient_gain := 1.0
## The bounce from the ground (normals facing down) as a fraction of the sky ambient.
@export_range(0.0, 1.0) var ambient_bottom_factor := 0.33
## How dark a thick cloud makes the moonlight (0..1). 0: no clouds, no dimming.
@export_range(0.0, 1.0) var cloud_strength := 0.45
## Metres per second the cloud shadows drift (x, z).
@export var cloud_scroll := Vector2(0.6, 0.25)
## Cloud texture repeats per metre.
@export var cloud_scale := 0.012
## (dir.x, dir.z, strength in metres, speed). Strength 0: plants keep their own authored sway.
@export var wind := Vector4(0.8, 0.6, 0.12, 1.0)
## Use the baked canopy shade (shade_map, else SHADE_MAP_PATH). Off: no shade map at all
## (scenes the bake does not cover, e.g. the prologue).
@export var use_shade_map := true
## Baked canopy shade (1 moon, 0 shade); falls back to SHADE_MAP_PATH, else no shade.
@export var shade_map: Texture2D
## World rect the shade map covers (x0, z0, x1, z1).
@export var shade_rect := MoonShadeBaker.RECT
## Tileable cloud noise (the sky's clouds, so they read as the same weather).
@export var cloud_texture: Texture2D

var _base_energy := 1.0
var _dim := 1.0
var _cloud_image: Image
var _cloud_offset := Vector2.ZERO
var _pushed_dir := Vector3.ZERO
var _pushed_color := Color(0, 0, 0, 0)
var _pushed_top := Color(-1, 0, 0, 0)


func _ready() -> void:
	_active = self
	# The cloud clock runs in the pause menu too (see the class notes); the dimming does not.
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not use_shade_map:
		shade_map = null
	elif shade_map == null and ResourceLoader.exists(SHADE_MAP_PATH):
		shade_map = load(SHADE_MAP_PATH) as Texture2D
	if cloud_texture == null and cloud_strength > 0.0:
		cloud_texture = load(CLOUD_NOISE_PATH) as Texture2D
	if light != null:
		_base_energy = light.light_energy
		if shade_map != null and light.global_basis.z.normalized().dot(MoonShadeBaker.moon_dir()) < 0.9999:
			push_warning("Moonlight: %s does not point along MoonShadeBaker.MOON_ROTATION; the baked canopy shade falls the wrong way (re-bake or align them)." % light.name)
	_push_static()
	_push_light(true)
	_push_reference()
	_fetch_cloud_image()


func _exit_tree() -> void:
	if light != null and is_instance_valid(light):
		light.light_energy = _base_energy
	if _active != self:
		return
	_active = null
	reset_globals()


func _process(delta: float) -> void:
	if cloud_strength > 0.0:
		# Wrapped at one texture repeat (1 / cloud_scale m): the same uv, no precision loss.
		var period := 1.0 / maxf(cloud_scale, 0.000001)
		_cloud_offset = (_cloud_offset + cloud_scroll * delta).posmodv(Vector2(period, period))
		RenderingServer.global_shader_parameter_set(&"cloud_offset", _cloud_offset)
	if light != null and not get_tree().paused:
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
	_push_reference()


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


## The moon model's sky ambient from above for an Environment (linear, see the class notes).
static func sky_ambient(env: Environment, gain: float) -> Color:
	if env == null:
		return Color(0, 0, 0, 1)
	var c := env.ambient_light_color.srgb_to_linear()
	var k := env.ambient_light_energy * gain
	return Color(c.r * k, c.g * k, c.b * k, 1.0)


## Linear moon colour x energy, as the shaders get it (light_color is an sRGB colour).
static func moon_color_of(moon: DirectionalLight3D, energy: float) -> Color:
	var c := moon.light_color.srgb_to_linear()
	return Color(c.r * energy, c.g * energy, c.b * energy, 1.0)


func _env() -> Environment:
	return environment.environment if environment != null else null


func _push_static() -> void:
	RenderingServer.global_shader_parameter_set(&"shade_map", shade_map)
	RenderingServer.global_shader_parameter_set(&"shade_rect", shade_rect)
	RenderingServer.global_shader_parameter_set(&"cloud_tex", cloud_texture)
	RenderingServer.global_shader_parameter_set(&"cloud_offset", _cloud_offset)
	RenderingServer.global_shader_parameter_set(&"cloud_scale", cloud_scale)
	RenderingServer.global_shader_parameter_set(&"cloud_strength", cloud_strength)
	RenderingServer.global_shader_parameter_set(&"wind", wind)
	# The grass families' authored sway belongs to this node's own wind strength.
	RenderingServer.global_shader_parameter_set(&"wind_ref", maxf(wind.z, 0.0001))


## The grass families' reference light (moonlight.gdshaderinc moon_ref_irr): what an up
## normal receives in the open under this node's base moon and the scene's own ambient (as
## the scene starts, before any region blend). Their painted colours are the look under it.
func _push_reference() -> void:
	var ref := sky_ambient(_env(), ambient_gain)
	if light != null:
		var n := Vector3.UP
		var ndl := maxf((n.dot(light.global_basis.z.normalized()) + GRASS_WRAP) / (1.0 + GRASS_WRAP), 0.0)
		var key := moon_color_of(light, _base_energy)
		ref = Color(ref.r + key.r * ndl, ref.g + key.g * ndl, ref.b + key.b * ndl, 1.0)
	RenderingServer.global_shader_parameter_set(&"moon_ref_irr",
		Vector3(maxf(ref.r, 0.0001), maxf(ref.g, 0.0001), maxf(ref.b, 0.0001)))


## moon_dir / moon_color from the light and the sky ambient from the Environment, only when
## they changed.
func _push_light(force: bool) -> void:
	if light != null:
		var dir := light.global_basis.z.normalized()
		if force or not dir.is_equal_approx(_pushed_dir):
			_pushed_dir = dir
			RenderingServer.global_shader_parameter_set(&"moon_dir", dir)
		var color := moon_color_of(light, light.light_energy)
		if force or not color.is_equal_approx(_pushed_color):
			_pushed_color = color
			RenderingServer.global_shader_parameter_set(&"moon_color", color)
	var top := sky_ambient(_env(), ambient_gain)
	if force or not top.is_equal_approx(_pushed_top):
		_pushed_top = top
		var k := ambient_bottom_factor
		RenderingServer.global_shader_parameter_set(&"sky_ambient_top", top)
		RenderingServer.global_shader_parameter_set(&"sky_ambient_bottom", Color(top.r * k, top.g * k, top.b * k, 1.0))


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
	var uv := (Vector2(p.x, p.z) + _cloud_offset) * cloud_scale
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
