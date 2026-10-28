@tool
class_name RetroMaterials
extends RefCounted
## World materials with nearest filtering and world triplanar mapping, so any
## box gets a fixed texel density with no UVs. Most surfaces use small CC0
## scanned textures (assets/textures/world, see assets/models/CREDITS.md);
## the rest are tiny NoiseTexture2D textures with a banded palette.

const TEXTURE_SIZE := 32

static var _cache: Dictionary = {}


static func stone() -> StandardMaterial3D:
	return _textured("stone", "castle_brick_02_white", 3.0, Color(0.42, 0.42, 0.44))


static func mossy_stone() -> StandardMaterial3D:
	return _textured("mossy_stone", "castle_brick_02_white", 3.0, Color(0.3, 0.36, 0.28))


static func cobble() -> StandardMaterial3D:
	return _textured("cobble", "cobblestone_floor_04", 3.5, Color(0.55, 0.53, 0.5))


static func dead_grass() -> StandardMaterial3D:
	return _cached("dead_grass", [Color(0.055, 0.08, 0.04), Color(0.085, 0.12, 0.05), Color(0.125, 0.165, 0.07), Color(0.035, 0.05, 0.03)], FastNoiseLite.TYPE_SIMPLEX, 0.22, 0.35)


## Reddish cracked earth for roads (the red path of the gloom paintings).
static func red_earth() -> StandardMaterial3D:
	return _textured("red_earth", "brown_mud_leaves_01", 4.0, Color(0.55, 0.42, 0.36))


static func mud() -> StandardMaterial3D:
	return _textured("mud", "brown_mud_leaves_01", 4.0, Color(0.6, 0.55, 0.5))


static func wood() -> StandardMaterial3D:
	return _textured("wood", "brown_planks_05", 2.0, Color(0.55, 0.48, 0.42))


static func roof() -> StandardMaterial3D:
	return _textured("roof", "clay_roof_tiles", 3.0, Color(0.32, 0.3, 0.32))


static func bark() -> StandardMaterial3D:
	return _textured("bark", "bark_brown_02", 1.6, Color(0.42, 0.38, 0.36))


static func iron() -> StandardMaterial3D:
	var mat := _cached("iron", [Color(0.14, 0.14, 0.15), Color(0.22, 0.21, 0.2), Color(0.3, 0.15, 0.07)], FastNoiseLite.TYPE_SIMPLEX, 0.3, 1.0)
	mat.metallic = 0.6
	mat.roughness = 0.6
	return mat


static func valdron_cloth() -> StandardMaterial3D:
	var mat := _cached("valdron_cloth", [Color(0.22, 0.02, 0.03), Color(0.32, 0.04, 0.04), Color(0.4, 0.07, 0.05), Color(0.36, 0.28, 0.08)], FastNoiseLite.TYPE_VALUE, 0.25, 0.9)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


static func linen() -> StandardMaterial3D:
	var mat := _cached("linen", [Color(0.36, 0.33, 0.27), Color(0.42, 0.39, 0.32), Color(0.25, 0.3, 0.12), Color(0.3, 0.06, 0.05)], FastNoiseLite.TYPE_SIMPLEX, 0.2, 0.8)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


## --- Props palettes (PropKit) ---
static func clapboard() -> StandardMaterial3D:
	return _textured("clapboard", "damaged_plaster", 2.0, Color(0.78, 0.76, 0.7))


static func rust_roof() -> StandardMaterial3D:
	return _textured("rust_roof", "clay_roof_tiles", 3.0, Color(0.6, 0.38, 0.3))


static func pumpkin() -> StandardMaterial3D:
	return _cached("pumpkin", [Color(0.45, 0.17, 0.03), Color(0.58, 0.24, 0.04), Color(0.68, 0.3, 0.05), Color(0.5, 0.2, 0.03)], FastNoiseLite.TYPE_SIMPLEX, 0.3, 0.7)


static func moss() -> StandardMaterial3D:
	return _cached("moss", [Color(0.05, 0.1, 0.04), Color(0.08, 0.16, 0.05), Color(0.11, 0.21, 0.06), Color(0.06, 0.12, 0.04)], FastNoiseLite.TYPE_SIMPLEX, 0.35, 0.6)


static func straw() -> StandardMaterial3D:
	return _cached("straw", [Color(0.4, 0.3, 0.1), Color(0.5, 0.4, 0.15), Color(0.62, 0.5, 0.2)], FastNoiseLite.TYPE_VALUE, 0.5, 0.8)


static func skin() -> StandardMaterial3D:
	return _cached("skin", [Color(0.6, 0.46, 0.42), Color(0.68, 0.55, 0.48), Color(0.74, 0.62, 0.55)], FastNoiseLite.TYPE_SIMPLEX, 0.3, 0.8)


static func sack() -> StandardMaterial3D:
	return _cached("sack", [Color(0.3, 0.23, 0.15), Color(0.36, 0.29, 0.19), Color(0.42, 0.34, 0.22)], FastNoiseLite.TYPE_VALUE, 0.5, 0.9)


static func brick() -> StandardMaterial3D:
	return _textured("brick", "castle_brick_02_white", 2.5, Color(0.6, 0.36, 0.3))


static func rag() -> StandardMaterial3D:
	return _cached("rag", [Color(0.07, 0.05, 0.05), Color(0.12, 0.09, 0.07), Color(0.17, 0.12, 0.09)], FastNoiseLite.TYPE_SIMPLEX, 0.3, 0.8)


static func flat(color: Color, emission_energy: float = 0.0) -> StandardMaterial3D:
	var key := "flat_%s_%.2f" % [color.to_html(), emission_energy]
	if _cache.has(key):
		return _cache[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	if emission_energy > 0.0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = emission_energy
	_cache[key] = mat
	return mat


## Scanned texture `assets/textures/world/<tex>.png`, one repeat every `tile_metres`,
## multiplied by `tint` (the scans are bright daylight albedo; the night needs them darker).
static func _textured(key: String, tex: String, tile_metres: float, tint: Color) -> StandardMaterial3D:
	if _cache.has(key):
		return _cache[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load("res://assets/textures/world/%s.png" % tex) as Texture2D
	mat.albedo_color = tint
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3.ONE / tile_metres
	mat.roughness = 0.95
	mat.set_meta("swatch", tint)
	_cache[key] = mat
	return mat


static func _cached(key: String, palette: Array, noise_type: int, frequency: float, uv_scale: float) -> StandardMaterial3D:
	if _cache.has(key):
		return _cache[key]
	var noise := FastNoiseLite.new()
	noise.noise_type = noise_type
	noise.frequency = frequency
	noise.seed = hash(key)
	var gradient := Gradient.new()
	gradient.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	var offsets := PackedFloat32Array()
	var colors := PackedColorArray()
	for i in palette.size():
		offsets.append(float(i) / palette.size())
		colors.append(palette[i])
	gradient.offsets = offsets
	gradient.colors = colors
	var tex := NoiseTexture2D.new()
	tex.width = TEXTURE_SIZE
	tex.height = TEXTURE_SIZE
	tex.seamless = true
	tex.noise = noise
	tex.color_ramp = gradient
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3.ONE * uv_scale
	mat.roughness = 0.95
	# Representative colour for vertex-colour baking (MeshMerger.bake_character).
	mat.set_meta("swatch", palette[palette.size() / 2])
	_cache[key] = mat
	return mat
