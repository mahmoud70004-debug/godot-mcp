class_name ViewDistance
extends Node
## The grey night fog of the overworld and everything that depends on it (Phase 4a, V5).
##
## The fog is depth fog: complete at `distance` metres (RegionData.view_distance: ~34 m in
## the deep wood, ~42 m in the Kingswood, ~55 m in the villages, more on the open plains)
## plus a ground mist that pools below the player's feet. Because nothing is visible past
## the fog, nothing past it is drawn: every mesh under `world` gets a visibility range of
## (fog distance + its own half-size), and the forest / grass shaders get their per-instance
## cut-offs from the same number. The far tree cards dissolve (dither) into the fog before
## their cut-off and the near trees cross-dissolve into their cards, so nothing pops.
## The sky's horizon band and the painted far horizon take the fog colour, so whatever is
## culled at the fog line disappears into the same colour.
## Graphics quality changes ranges and density (grass, forest floor, detailed trees), not the
## look: the fog is the same at every level.
## Level drives it: set_region() on every region change (blended like the other fog values).

const DEFAULT_DISTANCE := 60.0
## Fog starts this far from the eye (fully clear before it).
const FOG_BEGIN := 4.0
## >1 keeps the near ground clearer and closes the fog late (pow of the smoothstep).
const FOG_CURVE := 1.3
## Dissolve band of the far tree cards before the fog line, and of the near/far tree swap.
const FAR_FADE := 7.0
const SWAP_FADE := 3.0
## Detailed tree meshes / forest floor / large floor kits up to (Low, Medium, High) metres.
const NEAR_TREES := [16.0, 20.0, 24.0]
const FLOOR := [13.0, 17.0, 21.0]
const FLOOR_LARGE := [18.0, 22.0, 26.0]
## Grass and wheat up to this fraction of the fog distance (Low, Medium, High).
const GRASS := [0.55, 0.68, 0.8]
## Half the diagonal of a grass chunk (GrassScatter.CHUNK / MeadowProps.GRASS_CHUNK, 12 m).
const GRASS_CHUNK_HALF := 8.5
## The ground mist sits this far below the eye.
const MIST_BELOW_EYE := 2.2

enum Kind { SCENERY, TERRAIN, NEAR_TREES, FAR_TREES, FLOOR, FLOOR_LARGE, GRASS }

@export var environment: WorldEnvironment
## Root of the baked world (its meshes get the ranges).
@export var world: Node3D
## Painted far horizon (HorizonBackdrop), veiled by the fog colour or hidden.
@export var horizon: Node3D
## The kingdom wall rect: the horizon behind it (seen from the plains) is fully veiled,
## so no painted hill ever shows between the fogged trees (x0, z0, x1, z1).
@export var veil_rect := Vector4(-235.0, 58.0, 235.0, 490.0)

var distance := DEFAULT_DISTANCE

var _entries: Array = []  # [GeometryInstance3D, kind, baked range, half size]
var _mats: Dictionary = {}  # Kind -> Array[ShaderMaterial]
var _grass_mats: Array[ShaderMaterial] = []
var _horizon_mats: Array[ShaderMaterial] = []
var _sky_mat: ShaderMaterial
var _applied_range := -1.0
var _range_floor := 0.0  # while blending: the larger of the old and new distance
var _haze := 1.0
var _tween: Tween
var _ready_done := false
var _last_color := Color(-1.0, 0.0, 0.0)
var _last_haze := -1.0
var _shader_key := Vector3(-1.0, -1.0, -1.0)


func _ready() -> void:
	add_to_group(&"view_distance")
	Events.quality_changed.connect(func(_level: int) -> void:
		_apply_ranges(true)
		_shader_key = Vector3(-1.0, -1.0, -1.0))
	var env := _env()
	if env:
		env.fog_mode = Environment.FOG_MODE_DEPTH
		env.fog_density = 1.0
		env.fog_depth_begin = FOG_BEGIN
		env.fog_depth_curve = FOG_CURVE
		if env.sky and env.sky.sky_material is ShaderMaterial:
			_sky_mat = env.sky.sky_material as ShaderMaterial
	_collect.call_deferred()


## Blends to `region`'s fog distance, sky veil, ground mist and horizon veil.
func set_region(region: RegionData, blend_time: float) -> void:
	var target := region.view_distance if region.view_distance > 0.0 else DEFAULT_DISTANCE
	var env := _env()
	if _tween:
		_tween.kill()
	if blend_time <= 0.0 or not _ready_done:
		distance = target
		_haze = region.horizon_haze
		if env:
			env.fog_sky_affect = region.fog_sky
			env.fog_height_density = region.mist_density
		_range_floor = 0.0
		_apply()
		return
	# Draw for the farther of the two while the fog moves, settle on the new one after.
	_range_floor = maxf(distance, target)
	_apply_ranges(false)
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE)
	_tween.tween_property(self, "distance", target, blend_time)
	_tween.tween_property(self, "_haze", region.horizon_haze, blend_time)
	if env:
		_tween.tween_property(env, "fog_sky_affect", region.fog_sky, blend_time)
		_tween.tween_property(env, "fog_height_density", region.mist_density, blend_time)
	_tween.chain().tween_callback(func() -> void:
		_range_floor = 0.0
		_apply_ranges(true))


func _process(_delta: float) -> void:
	var env := _env()
	if env == null:
		return
	env.fog_depth_end = distance
	var cam := get_viewport().get_camera_3d()
	if cam:
		env.fog_height = cam.global_position.y - MIST_BELOW_EYE
	# Shader parameters only when they change (each set re-uploads the material).
	if env.fog_light_color != _last_color or not is_equal_approx(_haze, _last_haze):
		_last_color = env.fog_light_color
		_last_haze = _haze
		if _sky_mat:
			_sky_mat.set_shader_parameter("haze_color", env.fog_light_color)
		for mat in _horizon_mats:
			mat.set_shader_parameter("haze_color", env.fog_light_color)
			mat.set_shader_parameter("haze", _haze)
		if horizon:
			horizon.visible = _haze < 0.99
	var key := Vector3(snappedf(distance, 0.25), _range_floor, _quality())
	if _ready_done and key != _shader_key:
		_shader_key = key
		_apply_shader_ranges()


func _env() -> Environment:
	return environment.environment if environment else null


func _quality() -> int:
	return clampi(Settings.quality, 0, 2)


## Per kind: how far its meshes / instances are drawn for the current fog and quality.
func reach(kind: int) -> float:
	var d := maxf(distance, _range_floor)
	var q := _quality()
	match kind:
		Kind.NEAR_TREES:
			return minf(NEAR_TREES[q], d - 4.0)
		Kind.FLOOR:
			return minf(FLOOR[q], d - 4.0)
		Kind.FLOOR_LARGE:
			return minf(FLOOR_LARGE[q], d - 3.0)
		Kind.GRASS:
			return d * float(GRASS[q])
		Kind.TERRAIN:
			return d + 2.0
	return d + 1.0


func _collect() -> void:
	if world == null:
		return
	for node in world.find_children("*", "GeometryInstance3D", true, false):
		var gi := node as GeometryInstance3D
		if gi.visibility_range_end <= 0.0:
			continue
		var kind := _kind_of(gi)
		_entries.append([gi, kind, gi.visibility_range_end, _spread(gi, kind)])
	if horizon:
		for node in horizon.find_children("*", "MeshInstance3D", true, false):
			var mat := (node as MeshInstance3D).material_override as ShaderMaterial
			if mat and not _horizon_mats.has(mat):
				mat.set_shader_parameter("veil_rect", veil_rect)
				_horizon_mats.append(mat)
	_ready_done = true
	_apply()


## How much farther than its contents' own reach a node is drawn (its range is measured
## from its centre). Forest and grass chunks were baked as base + spread + margin with the
## base in their material; anything else gets half its bounding box (safe for merged cells).
func _spread(gi: GeometryInstance3D, kind: int) -> float:
	var r0 := gi.visibility_range_end
	var mat := _material_of(gi)
	match kind:
		Kind.NEAR_TREES, Kind.FAR_TREES, Kind.FLOOR, Kind.FLOOR_LARGE:
			return maxf(r0 - float(mat.get_meta(&"vd_lod_end")) - 2.0, 0.0)
		Kind.GRASS:
			if gi.has_meta(GrassScatter.RANGE_META):
				return maxf(r0 - float(gi.get_meta(GrassScatter.RANGE_META)) - 0.5, 0.0)
			var base := float(mat.get_meta(&"vd_chunk_range"))
			return maxf(r0 - base - 0.5, 0.0) if base > 0.0 else 0.0
	var box := gi.global_transform * gi.get_aabb()
	return box.size.length() * 0.5


func _kind_of(gi: GeometryInstance3D) -> int:
	var mat := _material_of(gi)
	var path := mat.shader.resource_path.get_file() if mat and mat.shader else ""
	var kind := Kind.SCENERY
	match path:
		"terrain.gdshader":
			kind = Kind.TERRAIN
		"forest_card.gdshader":
			kind = Kind.NEAR_TREES
		"forest_far.gdshader":
			kind = Kind.FAR_TREES
		"forest_floor_card.gdshader":
			kind = Kind.FLOOR
		"forest_solid.gdshader":
			# Small kits are cut nearer than the large ones (logs, boulders) when baked.
			kind = Kind.FLOOR if float(mat.get_shader_parameter("lod_end")) < 25.0 else Kind.FLOOR_LARGE
		"meadow_grass.gdshader", "thornfield_wheat.gdshader", "grass.gdshader":
			kind = Kind.GRASS
	if mat and kind != Kind.SCENERY and kind != Kind.TERRAIN:
		if not _mats.has(kind):
			_mats[kind] = []
		if not (_mats[kind] as Array).has(mat):
			(_mats[kind] as Array).append(mat)
			if kind == Kind.GRASS:
				_grass_mats.append(mat)
				_remember(mat, ["chunk_range"])
			else:
				_remember(mat, ["lod_end"])
	return kind


func _material_of(gi: GeometryInstance3D) -> ShaderMaterial:
	if gi.material_override is ShaderMaterial:
		return gi.material_override as ShaderMaterial
	var mesh: Mesh = null
	if gi is MeshInstance3D:
		mesh = (gi as MeshInstance3D).mesh
	elif gi is MultiMeshInstance3D and (gi as MultiMeshInstance3D).multimesh:
		mesh = (gi as MultiMeshInstance3D).multimesh.mesh
	if mesh and mesh.get_surface_count() > 0:
		return mesh.surface_get_material(0) as ShaderMaterial
	return null


func _remember(mat: ShaderMaterial, params: Array) -> void:
	for p: String in params:
		var key := StringName("vd_" + p)
		if not mat.has_meta(key):
			var v: Variant = mat.get_shader_parameter(p)
			mat.set_meta(key, float(v) if v != null else 0.0)


func _apply() -> void:
	_apply_ranges(true)
	_apply_shader_ranges()


## Node ranges: a mesh is drawn while any part of it can be inside its reach (its centre
## within reach + half its size), never farther than it was baked for.
func _apply_ranges(force: bool) -> void:
	if not _ready_done:
		return
	var key := maxf(distance, _range_floor) * 10.0 + _quality() * 10000.0
	if not force and absf(key - _applied_range) < 5.0:
		return
	_applied_range = key
	var reaches := {}
	for k in Kind.values():
		reaches[k] = reach(k)
	for e: Array in _entries:
		var gi := e[0] as GeometryInstance3D
		if not is_instance_valid(gi):
			continue
		var end := minf(float(e[2]), float(reaches[e[1]]) + float(e[3]))
		if not is_equal_approx(gi.visibility_range_end, end):
			gi.visibility_range_end = end


## Per-instance cut-offs in the forest and grass shaders (follow the fog every frame).
func _apply_shader_ranges() -> void:
	var near := reach(Kind.NEAR_TREES)
	var far := maxf(distance, near + FAR_FADE)
	for mat: ShaderMaterial in _mats.get(Kind.NEAR_TREES, []):
		mat.set_shader_parameter("lod_end", near)
		mat.set_shader_parameter("fade_out", SWAP_FADE)
	for mat: ShaderMaterial in _mats.get(Kind.FAR_TREES, []):
		mat.set_shader_parameter("lod_begin", near - SWAP_FADE)
		mat.set_shader_parameter("fade_in", SWAP_FADE)
		mat.set_shader_parameter("lod_end", far)
		mat.set_shader_parameter("fade_out", FAR_FADE)
	for kind in [Kind.FLOOR, Kind.FLOOR_LARGE]:
		var r := reach(kind)
		for mat: ShaderMaterial in _mats.get(kind, []):
			mat.set_shader_parameter("lod_end", r)
			mat.set_shader_parameter("fade_out", 3.0)
	# Grass chunks (12 m) are cut by their centre at `grass`: every tuft has sunk into the
	# ground (shader fade) before the nearest corner of a chunk can reach that line.
	var grass := reach(Kind.GRASS)
	var sunk := grass - GRASS_CHUNK_HALF
	for mat in _grass_mats:
		var base_range := float(mat.get_meta(&"vd_chunk_range"))
		if base_range > 0.0:
			mat.set_shader_parameter("chunk_range", minf(base_range, grass))
		mat.set_shader_parameter("fade_end", sunk)
		mat.set_shader_parameter("fade_start", sunk - minf(12.0, sunk * 0.4))
