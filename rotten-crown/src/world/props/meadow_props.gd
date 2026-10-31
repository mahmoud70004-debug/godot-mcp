@tool
class_name MeadowProps
extends RefCounted
## Props of the Moonlit Meadows and the plains between the villages (task U10):
## the long silver-green grass as merged quad chunks (meadow_grass.gdshader),
## scattered feast petals, dry-stone field walls and hedges, standing stones,
## the wayside shrine, the ruined shepherd's hut, the gibbet, milestones, low
## mist banks and the far village silhouettes (meadow_far.gdshader).
## Built like the other region kits: primitives (PartBuilder) and CC0 models
## (AssetKit) with shared materials, origin on the ground, local front +Z,
## explicit RNG, colliders never under scaled nodes.

const GRASS_SHADER := preload("res://assets/shaders/meadow_grass.gdshader")
const FAR_SHADER := preload("res://assets/shaders/meadow_far.gdshader")
const MIST_SHADER := preload("res://assets/shaders/wood_mist.gdshader")
const OOZE_SHADER := preload("res://assets/shaders/ooze.gdshader")
const GRASS_CHUNK := 12.0
## Chunks drawn together (3x3 per draw call; see MeshMerger.merge_grass_chunks).
const GRASS_MERGE := 3
## Grass tuft kinds (vertex COLOR.a, see meadow_grass.gdshader).
const KIND_GRASS := 1.0
const KIND_WEED := 0.66
const KIND_RUSH := 0.33

static var _mats: Dictionary = {}


# --------------------------------------------------------------------------
# Materials (own, cached; the rest reuses RetroMaterials / ThornfieldProps)
# --------------------------------------------------------------------------
static func grass_mat() -> ShaderMaterial:
	if not _mats.has("grass"):
		var mat := ShaderMaterial.new()
		mat.shader = GRASS_SHADER
		_mats["grass"] = mat
	return _mats["grass"]


## Far silhouette material. tone "haze": paler than the first backdrop ring
## (a card standing in front of it); "deep": between the first two rings (a
## card behind the first ring, against the second).
static func far_mat(tone: String) -> ShaderMaterial:
	var key := "far_" + tone
	if not _mats.has(key):
		var mat := ShaderMaterial.new()
		mat.shader = FAR_SHADER
		if tone == "haze":
			mat.set_shader_parameter("base_color", Color(0.07, 0.08, 0.068))
			mat.set_shader_parameter("top_color", Color(0.16, 0.17, 0.14))
		else:
			mat.set_shader_parameter("base_color", Color(0.04, 0.048, 0.04))
			mat.set_shader_parameter("top_color", Color(0.085, 0.095, 0.075))
		mat.set_shader_parameter("top_height", 22.0)
		_mats[key] = mat
	return _mats[key]


## Low mist banks lying over the meadow (shared wood_mist shader, own colours).
static func mist_mat() -> ShaderMaterial:
	if not _mats.has("mist"):
		var mat := ShaderMaterial.new()
		mat.shader = MIST_SHADER
		mat.set_shader_parameter("tint", Color(0.42, 0.47, 0.42))
		mat.set_shader_parameter("intensity", 0.2)
		mat.set_shader_parameter("billboard", 2)
		mat.set_shader_parameter("near_start", 5.0)
		mat.set_shader_parameter("near_end", 18.0)
		mat.set_shader_parameter("far_start", 70.0)
		mat.set_shader_parameter("far_end", 100.0)
		mat.set_shader_parameter("wisps", 2.4)
		mat.set_shader_parameter("speed", 0.02)
		mat.set_shader_parameter("bottom_soft", 0.55)
		_mats["mist"] = mat
	return _mats["mist"]


## Petals, flags and other small vertex-coloured litter (one material for all).
static func litter_mat() -> StandardMaterial3D:
	if not _mats.has("litter"):
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.roughness = 1.0
		_mats["litter"] = mat
	return _mats["litter"]


## Field stone for dry-stone walls, cairns and the hut (scanned cobbles, triplanar).
static func field_stone() -> StandardMaterial3D:
	return _scan("field_stone", "cobblestone_floor_04", 1.7, Color(0.34, 0.35, 0.33))


static func lichen_stone() -> StandardMaterial3D:
	return _scan("lichen_stone", "cobblestone_floor_04", 1.3, Color(0.27, 0.31, 0.25))


## Spilt wine: dark, glossy, a little purple (ooze splat shader).
static func wine_mat() -> ShaderMaterial:
	if not _mats.has("wine"):
		var mat := ShaderMaterial.new()
		mat.shader = OOZE_SHADER
		mat.set_shader_parameter("surface_color", Color(0.2, 0.02, 0.06))
		mat.set_shader_parameter("deep_color", Color(0.07, 0.0, 0.03))
		mat.set_shader_parameter("emission_strength", 0.0)
		mat.set_shader_parameter("bubble_amount", 0.0)
		mat.set_shader_parameter("roughness_value", 0.25)
		_mats["wine"] = mat
	return _mats["wine"]


static func wax_mat() -> StandardMaterial3D:
	return RetroMaterials.flat(Color(0.52, 0.49, 0.4))


static func flame_mat() -> StandardMaterial3D:
	return RetroMaterials.flat(Color(0.95, 0.78, 0.4), 2.6)


## Lantern glass gone dark.
static func dead_glass() -> StandardMaterial3D:
	return RetroMaterials.flat(Color(0.05, 0.055, 0.05))


static func _scan(key: String, tex: String, tile_metres: float, tint: Color) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load("res://assets/textures/world/%s.png" % tex) as Texture2D
	mat.albedo_color = tint
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3.ONE / tile_metres
	mat.roughness = 0.95
	mat.set_meta("swatch", tint)
	_mats[key] = mat
	return mat


# --------------------------------------------------------------------------
# Grass (merged quad chunks)
# --------------------------------------------------------------------------
## tufts: Array of [Vector3 foot, float yaw, float width, float height, float brightness, float kind].
## One ArrayMesh per GRASS_CHUNK cell (identity basis, see meadow_grass.gdshader),
## culled beyond range_end. Returns the "Grass" group (RC_PERF=nograss hides it).
static func grass_chunks(parent: Node3D, tufts: Array, range_end: float) -> Node3D:
	var group := Node3D.new()
	group.name = "Grass"
	parent.add_child(group)
	var cells: Dictionary = {}
	for tuft in tufts:
		var p: Vector3 = tuft[0]
		var cell := Vector2i(floori(p.x / GRASS_CHUNK), floori(p.z / GRASS_CHUNK))
		if not cells.has(cell):
			cells[cell] = []
		(cells[cell] as Array).append(tuft)
	var mat := grass_mat()
	for cell in cells:
		var list: Array = cells[cell]
		var origin := Vector3(cell.x * GRASS_CHUNK, 0.0, cell.y * GRASS_CHUNK)
		var first: Vector3 = list[0][0]
		origin.y = first.y
		var verts := PackedVector3Array()
		var uvs := PackedVector2Array()
		var colors := PackedColorArray()
		var normals := PackedVector3Array()
		var indices := PackedInt32Array()
		for tuft in list:
			var foot: Vector3 = (tuft[0] as Vector3) - origin
			var yaw: float = tuft[1]
			var half: float = tuft[2] * 0.5
			var h: float = tuft[3]
			var right := Vector3(cos(yaw), 0.0, -sin(yaw)) * half
			var c := Color(seed_from(foot + origin), h * 0.5, tuft[4], tuft[5])
			var base := verts.size()
			verts.append_array(PackedVector3Array([foot - right, foot + right, foot + right + Vector3(0, h, 0), foot - right + Vector3(0, h, 0)]))
			uvs.append_array(PackedVector2Array([Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]))
			for k in 4:
				colors.append(c)
				normals.append(Vector3.UP)
			indices.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_INDEX] = indices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		# The wind pushes blades up to ~0.5 m out of their rest box.
		mesh.custom_aabb = mesh.get_aabb().grow(0.8)
		var mi := MeshInstance3D.new()
		mi.name = "Chunk_%d_%d" % [cell.x, cell.y]
		mi.mesh = mesh
		mi.material_override = mat
		mi.position = origin
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = range_end
		mi.set_meta(MeshMerger.SKIP_META, true)
		group.add_child(mi)
	MeshMerger.merge_grass_chunks(group, GRASS_CHUNK, GRASS_MERGE)
	return group


## Stable 0..1 seed from a position (tuft variety without another RNG stream).
static func seed_from(p: Vector3) -> float:
	return fposmod(sin(p.x * 12.9898 + p.z * 78.233) * 43758.5453, 1.0)


# --------------------------------------------------------------------------
# Litter: petals, fallen bunting flags (one merged vertex-coloured mesh)
# --------------------------------------------------------------------------
## items: Array of [Vector3 centre, Vector2 size, Color colour, float yaw, float tilt].
## Small quads lying on the ground, merged into a single mesh (litter_mat).
static func litter(parent: Node3D, items: Array, range_end: float) -> MeshInstance3D:
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for it in items:
		var c: Vector3 = it[0]
		var size: Vector2 = it[1]
		var col: Color = it[2]
		var basis := Basis(Vector3.UP, float(it[3])) * Basis(Vector3.RIGHT, float(it[4]))
		var ax := basis.x * size.x * 0.5
		var az := basis.z * size.y * 0.5
		var base := verts.size()
		verts.append_array(PackedVector3Array([c - ax - az, c + ax - az, c + ax + az, c - ax + az]))
		for k in 4:
			colors.append(col)
			normals.append(basis.y)
		indices.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.name = "Litter"
	mi.mesh = mesh
	mi.material_override = litter_mat()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = range_end
	mi.set_meta(MeshMerger.SKIP_META, true)
	parent.add_child(mi)
	return mi


## Petal colours of the victory feast: faded rose, cream, gold, a few blue.
static func petal_color(rng: RandomNumberGenerator) -> Color:
	var r := rng.randf()
	var c := Color(0.42, 0.07, 0.08)
	if r > 0.55:
		c = Color(0.55, 0.52, 0.44)
	if r > 0.8:
		c = Color(0.5, 0.4, 0.15)
	if r > 0.93:
		c = Color(0.16, 0.2, 0.34)
	return c.darkened(rng.randf_range(0.0, 0.35))


# --------------------------------------------------------------------------
# Field boundaries
# --------------------------------------------------------------------------
## Low dry-stone wall along the xz polyline `pts`: two courses of rough stones
## and an on-edge coping, slumped in places; `gap` is the chance a 2 m stretch
## has collapsed into a heap of tumbled stones (and lets the player through).
static func dry_stone_wall(terrain: TerrainBuilder, pts: PackedVector2Array, gap: float, rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	root.name = "DryStoneWall"
	var stone := field_stone()
	var lichen := lichen_stone()
	var body := ThornfieldProps.new_body(root)
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var length := a.distance_to(b)
		var dir := (b - a) / maxf(length, 0.01)
		var yaw := atan2(-dir.y, dir.x)
		var stretches := maxi(1, roundi(length / 2.0))
		for k in stretches:
			var t0 := float(k) / stretches
			var t1 := float(k + 1) / stretches
			var p0 := a.lerp(b, t0)
			var p1 := a.lerp(b, t1)
			var mid := (p0 + p1) * 0.5
			var seg := p0.distance_to(p1)
			var g := terrain.ground(mid.x, mid.y)
			if rng.randf() < gap:
				_tumbled(root, terrain, p0, p1, stone, rng)
				continue
			var slump := rng.randf_range(0.75, 1.0)
			var along := 0.0
			while along < seg - 0.05:
				var l := minf(rng.randf_range(0.7, 1.1), seg - along)
				var q := p0 + dir * (along + l * 0.5)
				var y := terrain.height_at(q.x, q.y)
				var h0 := rng.randf_range(0.34, 0.46) * slump
				PartBuilder.box(root, Vector3(l * 0.98, h0, rng.randf_range(0.6, 0.72)), Vector3(q.x, y + h0 * 0.45, q.y),
					stone if rng.randf() < 0.7 else lichen, Vector3(rng.randf_range(-0.05, 0.05), yaw + rng.randf_range(-0.08, 0.08), rng.randf_range(-0.06, 0.06)))
				var l2 := l * rng.randf_range(0.7, 1.0)
				var q2 := q + dir * rng.randf_range(-0.2, 0.2)
				var h1 := rng.randf_range(0.26, 0.36) * slump
				PartBuilder.box(root, Vector3(l2, h1, rng.randf_range(0.46, 0.56)), Vector3(q2.x, y + h0 * 0.9 + h1 * 0.45, q2.y),
					stone, Vector3(rng.randf_range(-0.07, 0.07), yaw + rng.randf_range(-0.12, 0.12), rng.randf_range(-0.08, 0.08)))
				if rng.randf() < 0.45:
					# Coping stones set on edge along the top.
					var n := rng.randi_range(1, 2)
					for c in n:
						var qc := q + dir * (l * (float(c) + 0.5) / n - l * 0.5)
						PartBuilder.box(root, Vector3(0.16, rng.randf_range(0.22, 0.3), 0.42), Vector3(qc.x, y + (h0 + h1) * 0.88 + 0.1, qc.y),
							lichen, Vector3(0.0, yaw, rng.randf_range(-0.35, 0.35)))
				along += l
			ThornfieldProps.add_box(body, Vector3(seg, 0.95 * slump, 0.66), g + Vector3(0, 0.45, 0))
			(body.get_child(body.get_child_count() - 1) as Node3D).rotation.y = yaw
	return root


## A collapsed stretch: stones tumbled to both sides of the line.
static func _tumbled(root: Node3D, terrain: TerrainBuilder, p0: Vector2, p1: Vector2, stone: Material, rng: RandomNumberGenerator) -> void:
	var dir := (p1 - p0).normalized()
	var nrm := Vector2(-dir.y, dir.x)
	for i in rng.randi_range(3, 5):
		var q := p0.lerp(p1, rng.randf()) + nrm * rng.randf_range(-0.9, 0.9)
		var s := rng.randf_range(0.3, 0.55)
		PartBuilder.box(root, Vector3(s * 1.4, s * 0.7, s), terrain.ground(q.x, q.y) + Vector3(0, s * 0.25, 0), stone,
			Vector3(rng.randf_range(-0.4, 0.4), rng.randf() * TAU, rng.randf_range(-0.4, 0.4)))


## Overgrown hedge along `pts`: dark lumpy bushes with dead twigs, a collider
## per stretch. Gaps where `gap` hits.
static func hedge(terrain: TerrainBuilder, pts: PackedVector2Array, gap: float, rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	root.name = "Hedge"
	var leaf := RetroMaterials.moss()
	var bark := RetroMaterials.bark()
	var body := ThornfieldProps.new_body(root)
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var length := a.distance_to(b)
		var dir := (b - a) / maxf(length, 0.01)
		var stretches := maxi(1, roundi(length / 3.0))
		for k in stretches:
			if rng.randf() < gap:
				continue
			var p0 := a.lerp(b, float(k) / stretches)
			var p1 := a.lerp(b, float(k + 1) / stretches)
			var n := maxi(2, roundi(p0.distance_to(p1) / 1.25))
			for j in n:
				var q := p0.lerp(p1, (float(j) + rng.randf_range(0.2, 0.8)) / n) + Vector2(-dir.y, dir.x) * rng.randf_range(-0.25, 0.25)
				var r := rng.randf_range(0.7, 0.95)
				var blob := PartBuilder.sphere(root, r, terrain.ground(q.x, q.y) + Vector3(0, r * 0.7, 0), leaf, false, 6)
				blob.scale = Vector3(rng.randf_range(1.1, 1.5), rng.randf_range(0.9, 1.4), rng.randf_range(1.0, 1.3))
				blob.rotation.y = rng.randf() * TAU
				if rng.randf() < 0.35:
					var top := terrain.ground(q.x, q.y) + Vector3(0, r * 1.6, 0)
					ThornfieldProps.limb(root, top - Vector3(0, 0.5, 0), top + Vector3(rng.randf_range(-0.4, 0.4), rng.randf_range(0.4, 0.8), rng.randf_range(-0.4, 0.4)),
						0.03, 0.008, bark, 3)
			var mid := (p0 + p1) * 0.5
			var cs := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = Vector3(p0.distance_to(p1), 1.6, 1.1)
			cs.shape = shape
			cs.position = terrain.ground(mid.x, mid.y) + Vector3(0, 0.8, 0)
			cs.rotation.y = atan2(-dir.y, dir.x)
			body.add_child(cs)
	return root


# --------------------------------------------------------------------------
# Landmarks
# --------------------------------------------------------------------------
## A scanned model stood on end (standing stones from boulders): tilted by
## `tilt` (x, z radians) after the yaw, then dropped so its lowest point sits
## `sink` metres under `pos`. Returns the model root.
static func place_upright(parent: Node3D, model: String, pos: Vector3, yaw: float, scale: float, tilt: Vector2, sink := 0.2) -> Node3D:
	var node := AssetKit.place(parent, model, pos, yaw, scale)
	node.rotation = Vector3(tilt.x, yaw, tilt.y)
	var low := INF
	for child in node.get_children():
		var mi := child as MeshInstance3D
		if mi == null:
			continue
		var box: AABB = node.transform * mi.transform * mi.mesh.get_aabb()
		low = minf(low, box.position.y)
	if low < INF:
		node.position.y += pos.y - low - sink
	return node


## A ring of standing stones (a few fallen, one capstone across two uprights).
static func stone_circle(parent: Node3D, terrain: TerrainBuilder, centre: Vector2, radius: float, rng: RandomNumberGenerator) -> void:
	var count := 6
	var body := ThornfieldProps.new_body(parent)
	body.name = "StoneCircle"
	for i in count:
		var a := TAU * i / count + rng.randf_range(-0.15, 0.15)
		var q := centre + Vector2(cos(a), sin(a)) * radius * rng.randf_range(0.92, 1.08)
		var g := terrain.ground(q.x, q.y)
		if i == 3:
			# Fallen, half sunk in the grass.
			var fallen := AssetKit.place(parent, "boulder_01", g + Vector3(0, -0.15, 0), a + PI * 0.5, 1.4)
			fallen.rotation.x = 0.1
			continue
		var h := rng.randf_range(1.5, 2.0)
		var stone := place_upright(parent, "boulder_01", g, -a + rng.randf_range(-0.4, 0.4), h, Vector2(PI * 0.5 + rng.randf_range(-0.12, 0.12), rng.randf_range(-0.1, 0.1)))
		# Slim monoliths, not boulders (visual scale only; the collider is separate).
		stone.scale = Vector3(h * 0.5, h * 0.62, h)
		ThornfieldProps.add_cyl(body, 0.4 * h, 1.8 * h, g + Vector3(0, 0.9 * h, 0))
	# The heart stone: a low flat altar with old wax and a dark stain.
	var altar := terrain.ground(centre.x, centre.y)
	AssetKit.place(parent, "namaqualand_boulder_02", altar + Vector3(0, -0.25, 0), rng.randf() * TAU, 0.9)
	ThornfieldProps.add_box(body, Vector3(2.0, 0.7, 1.0), altar + Vector3(0, 0.35, 0))
	ThornfieldProps.splat(parent, ThornfieldProps.blood_mat(), altar + Vector3(0.1, 0.55, 0.05), 0.9, rng)


## Wayside shrine: stepped plinth, a pillar with a gabled niche holding a small
## weathered saint, guttered candles, wilted offerings and a red ribbon. One
## candle still burns (the plains' pale yellow accent) - its light is added by
## the builder. Meta "flame" (local Vector3) marks that candle.
static func shrine(rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	root.name = "WaysideShrine"
	var stone := RetroMaterials.stone()
	var field := field_stone()
	var lichen := lichen_stone()
	var body := ThornfieldProps.new_body(root)
	PartBuilder.box(root, Vector3(1.5, 0.22, 1.3), Vector3(0, 0.08, 0), field, Vector3(0, 0.04, 0.02))
	PartBuilder.box(root, Vector3(1.1, 0.22, 0.95), Vector3(0, 0.3, 0), field)
	PartBuilder.box(root, Vector3(0.5, 1.25, 0.45), Vector3(0, 1.03, 0), stone)
	PartBuilder.box(root, Vector3(0.62, 0.12, 0.56), Vector3(0, 1.7, 0), lichen)
	ThornfieldProps.add_box(body, Vector3(1.1, 1.8, 0.95), Vector3(0, 0.9, 0))
	# Niche: back, sides, floor, a steep stone gable and a cross.
	var top := 1.76
	PartBuilder.box(root, Vector3(0.7, 0.9, 0.1), Vector3(0, top + 0.45, -0.2), stone)
	for sx: float in [-1.0, 1.0]:
		PartBuilder.box(root, Vector3(0.1, 0.9, 0.45), Vector3(sx * 0.3, top + 0.45, 0.0), stone)
		PartBuilder.box(root, Vector3(0.12, 0.62, 0.62), Vector3(sx * 0.2, top + 1.08, 0.0), lichen, Vector3(0, 0, sx * -0.95))
	PartBuilder.box(root, Vector3(0.05, 0.4, 0.05), Vector3(0, top + 1.55, 0.0), RetroMaterials.iron())
	PartBuilder.box(root, Vector3(0.24, 0.05, 0.05), Vector3(0, top + 1.62, 0.0), RetroMaterials.iron())
	AssetKit.place(root, "gothic_statue", Vector3(0, top, -0.05), PI, 0.42)
	# Candles: guttered stubs, one still alight.
	var wax := wax_mat()
	var spots := [Vector3(-0.2, top, 0.16), Vector3(0.18, top, 0.17), Vector3(-0.38, 0.41, 0.36), Vector3(0.32, 0.41, 0.38), Vector3(0.05, 0.41, 0.42)]
	for i in spots.size():
		var h := rng.randf_range(0.04, 0.16)
		PartBuilder.cylinder(root, 0.025, 0.035, h, spots[i] + Vector3(0, h * 0.5, 0), wax, 5)
		PartBuilder.cylinder(root, 0.05, 0.07, 0.015, spots[i] + Vector3(0, 0.008, 0), wax, 6)
		if i == 1:
			PartBuilder.box(root, Vector3(0.02, 0.045, 0.02), spots[i] + Vector3(0, h + 0.03, 0), flame_mat())
			root.set_meta("flame", spots[i] + Vector3(0, h + 0.12, 0))
	# Offerings: a goblet, a wilted posy, a ribbon tied to the pillar.
	AssetKit.place(root, "brass_goblets", Vector3(-0.05, 0.41, 0.33), 0.4, 0.8, "brass_goblet_02")
	var dead := RetroMaterials.flat(Color(0.12, 0.1, 0.07))
	for i in 5:
		var tip := Vector3(0.28 + rng.randf_range(-0.08, 0.08), 0.41 + 0.05, 0.2 + rng.randf_range(-0.05, 0.05)) + Vector3(rng.randf_range(-0.15, 0.15), 0.25, rng.randf_range(0.0, 0.2))
		ThornfieldProps.limb(root, Vector3(0.26, 0.42, 0.25), tip, 0.008, 0.006, dead, 3)
		PartBuilder.sphere(root, 0.025, tip, RetroMaterials.flat(Color(0.3, 0.12, 0.14)), false, 4)
	var cloth := RetroMaterials.valdron_cloth()
	PartBuilder.box(root, Vector3(0.52, 0.05, 0.47), Vector3(0, 1.32, 0), cloth)
	PartBuilder.box(root, Vector3(0.06, 0.55, 0.01), Vector3(0.18, 1.02, 0.235), cloth, Vector3(0, 0, 0.12))
	PartBuilder.box(root, Vector3(0.05, 0.42, 0.01), Vector3(0.24, 1.08, 0.236), cloth, Vector3(0, 0, -0.08))
	return root


## The ruined shepherd's hut: a round dry-stone wall broken down on one side,
## roof timbers fallen in, a heap of rotten thatch, a wattle hurdle against the
## wall, a cold hearth and the bones of the last sheep. Door faces local +Z.
static func shepherd_hut(rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	root.name = "ShepherdHut"
	var stone := field_stone()
	var lichen := lichen_stone()
	var wood := RetroMaterials.wood()
	var bark := RetroMaterials.bark()
	var straw := RetroMaterials.straw()
	var body := ThornfieldProps.new_body(root)
	var radius := 2.3
	var count := 22
	for i in count:
		var a := TAU * (float(i) + 0.5) / count
		var dir := Vector3(sin(a), 0, cos(a))
		if absf(wrapf(a, -PI, PI)) < 0.24:
			continue  # doorway (+Z)
		# The wall stands to ~1.6 m on the back, broken down to one course at the front left.
		var broken := clampf((cos(a - 0.9) + 0.2) * 1.4, 0.0, 1.0)
		var courses := 1 + int(round((1.0 - broken) * 3.0))
		var y := 0.0
		for c in courses:
			var h := rng.randf_range(0.34, 0.46)
			PartBuilder.box(root, Vector3(0.7, h, 0.6), dir * (radius + rng.randf_range(-0.05, 0.05)) + Vector3(0, y + h * 0.5, 0),
				stone if (i + c) % 3 else lichen, Vector3(rng.randf_range(-0.06, 0.06), a + rng.randf_range(-0.1, 0.1), rng.randf_range(-0.05, 0.05)))
			y += h * 0.95
		if broken > 0.5:
			for k in 2:
				var off := dir * rng.randf_range(radius + 0.5, radius + 1.6) + Vector3(rng.randf_range(-0.4, 0.4), 0, rng.randf_range(-0.4, 0.4))
				PartBuilder.box(root, Vector3(0.55, 0.32, 0.45), off + Vector3(0, 0.1, 0), stone, Vector3(rng.randf_range(-0.5, 0.5), rng.randf() * TAU, rng.randf_range(-0.4, 0.4)))
		if i % 2 == 0:
			var cs := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = Vector3(1.3, maxf(y, 0.4), 0.6)
			cs.shape = shape
			cs.position = dir * radius + Vector3(0, maxf(y, 0.4) * 0.5, 0)
			cs.rotation.y = a
			body.add_child(cs)
	# Door jambs: two upright slabs and a fallen lintel.
	for sx: float in [-1.0, 1.0]:
		PartBuilder.box(root, Vector3(0.28, 1.5, 0.5), Vector3(sx * 0.62, 0.75, radius), lichen, Vector3(0, 0, sx * 0.04))
	PartBuilder.box(root, Vector3(1.5, 0.28, 0.4), Vector3(0.4, 0.14, radius + 0.7), stone, Vector3(0.1, 0.5, 0.05))
	# Roof timbers: two still leaning on the back wall, the rest fallen in.
	var apex := Vector3(0.2, 2.6, -0.3)
	ThornfieldProps.limb(root, Vector3(-1.6, 1.5, -1.6), apex, 0.08, 0.06, bark, 5)
	ThornfieldProps.limb(root, Vector3(1.7, 1.5, -1.5), apex + Vector3(0.1, -0.05, 0), 0.08, 0.06, bark, 5)
	ThornfieldProps.limb(root, Vector3(-2.0, 1.2, 0.8), Vector3(0.6, 0.15, -0.2), 0.07, 0.05, bark, 5)
	ThornfieldProps.limb(root, Vector3(1.9, 0.9, 1.2), Vector3(-0.4, 0.1, 0.9), 0.07, 0.05, bark, 5)
	ThornfieldProps.beam(root, Vector3(-1.9, 1.55, -1.0), Vector3(1.9, 1.5, -1.0), 0.12, 0.1, wood)
	for i in 3:
		var p := Vector3(rng.randf_range(-0.8, 0.6), 0.25 + i * 0.12, rng.randf_range(-0.9, 0.3))
		PartBuilder.box(root, Vector3(rng.randf_range(1.2, 1.8), 0.16, rng.randf_range(0.9, 1.3)), p, straw,
			Vector3(rng.randf_range(-0.3, 0.3), rng.randf() * TAU, rng.randf_range(-0.3, 0.3)))
	# Thatch still hanging on the leaning timbers.
	PartBuilder.box(root, Vector3(1.4, 0.12, 1.1), Vector3(-0.7, 2.05, -0.9), straw, Vector3(0.5, 0.6, -0.55))
	# Cold hearth.
	for i in 6:
		var a := TAU * i / 6.0
		PartBuilder.box(root, Vector3(0.22, 0.14, 0.18), Vector3(0.8 + cos(a) * 0.32, 0.06, 0.5 + sin(a) * 0.32), stone, Vector3(0, a, 0))
	PartBuilder.cylinder(root, 0.26, 0.28, 0.03, Vector3(0.8, 0.02, 0.5), ThornfieldProps.void_mat(), 6)
	# Wattle hurdle leaning on the outer wall (right side).
	var hurdle := PartBuilder.pivot(root, "Hurdle", Vector3(2.75, 0, -0.6))
	hurdle.rotation = Vector3(0, PI * 0.5 + 0.2, -0.25)
	for k in 5:
		PartBuilder.box(hurdle, Vector3(0.05, 1.1, 0.05), Vector3(-0.8 + k * 0.4, 0.55, 0), bark)
	for k in 5:
		PartBuilder.box(hurdle, Vector3(1.7, 0.05, 0.06), Vector3(0, 0.2 + k * 0.2, 0.02 if k % 2 else -0.02), wood)
	# The last sheep: a skull and a scatter of ribs in the grass by the door.
	var bone := ThornfieldProps.bone_mat()
	var skull := PartBuilder.pivot(root, "SheepSkull", Vector3(-1.1, 0.1, radius + 1.4))
	skull.rotation = Vector3(0.3, 2.2, 0.9)
	PartBuilder.frustum(skull, 0.16, 0.09, 0.3, 0.13, Vector3.ZERO, bone)
	for sx: float in [-1.0, 1.0]:
		ThornfieldProps.limb(skull, Vector3(sx * 0.07, 0.1, -0.03), Vector3(sx * 0.18, 0.06, 0.08), 0.03, 0.015, bone, 4)
	for i in 6:
		var p := Vector3(-0.6 + i * 0.13, 0.03, radius + 1.0)
		ThornfieldProps.limb(root, p, p + Vector3(rng.randf_range(-0.1, 0.1), 0.02, 0.35), 0.016, 0.012, bone, 3)
	return root


## Roadside gibbet: tall post, arm and brace, a chain and an iron cage with
## what is left of a hanged thief; crows sit on the arm (builder adds them).
## Meta "perch" (local Vector3) is the arm's tip.
static func gibbet(rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	root.name = "Gibbet"
	var wood := RetroMaterials.wood()
	var bark := RetroMaterials.bark()
	var iron := RetroMaterials.iron()
	var bone := ThornfieldProps.bone_mat()
	var h := 4.6
	PartBuilder.box(root, Vector3(0.26, h, 0.26), Vector3(0, h * 0.5 - 0.3, 0), wood, Vector3(0, 0, 0.03))
	ThornfieldProps.beam(root, Vector3(-0.1, h - 0.45, 0), Vector3(1.75, h - 0.4, 0), 0.2, 0.18, wood)
	ThornfieldProps.beam(root, Vector3(0.05, h - 1.5, 0), Vector3(0.95, h - 0.5, 0), 0.12, 0.12, bark)
	PartBuilder.box(root, Vector3(0.5, 0.3, 0.5), Vector3(0, 0.1, 0), field_stone())
	root.set_meta("perch", Vector3(1.6, h - 0.3, 0))
	# Chain and cage.
	var hang := Vector3(1.5, h - 0.5, 0)
	PartBuilder.box(root, Vector3(0.03, 0.9, 0.03), hang - Vector3(0, 0.45, 0), iron)
	var cage := PartBuilder.pivot(root, "Cage", hang - Vector3(0, 0.9, 0))
	cage.rotation = Vector3(rng.randf_range(-0.08, 0.08), rng.randf() * TAU, rng.randf_range(-0.12, 0.12))
	var r := 0.36
	var ch := 1.65
	for i in 8:
		var a := TAU * i / 8.0
		PartBuilder.box(cage, Vector3(0.03, ch, 0.03), Vector3(cos(a) * r, -ch * 0.5, sin(a) * r), iron)
	for y: float in [-0.02, -ch * 0.55, -ch]:
		for i in 8:
			var a := TAU * (i + 0.5) / 8.0
			PartBuilder.box(cage, Vector3(0.03, 0.03, r * 0.8), Vector3(cos(a) * r * 0.93, y, sin(a) * r * 0.93), iron, Vector3(0, -a, 0))
	PartBuilder.box(cage, Vector3(0.03, 0.03, r * 2.0), Vector3(0, 0.05, 0), iron)
	PartBuilder.box(cage, Vector3(r * 2.0, 0.03, 0.03), Vector3(0, 0.05, 0), iron)
	# Remains: skull slumped forward, spine, a few ribs, rags.
	var skull := PartBuilder.sphere(cage, 0.11, Vector3(0.04, -0.38, 0.08), bone, false, 6)
	skull.scale = Vector3(0.9, 1.05, 1.1)
	PartBuilder.box(cage, Vector3(0.1, 0.05, 0.06), Vector3(0.05, -0.47, 0.17), bone)
	PartBuilder.box(cage, Vector3(0.09, 0.04, 0.03), Vector3(0.05, -0.36, 0.18), ThornfieldProps.void_mat())
	ThornfieldProps.limb(cage, Vector3(0, -0.5, 0), Vector3(-0.04, -1.25, -0.06), 0.03, 0.03, bone, 4)
	for i in 5:
		var y := -0.65 - i * 0.1
		for sx: float in [-1.0, 1.0]:
			ThornfieldProps.limb(cage, Vector3(0, y, -0.04), Vector3(sx * 0.15, y - 0.08, 0.1), 0.012, 0.01, bone, 3)
	PartBuilder.box(cage, Vector3(0.34, 0.6, 0.02), Vector3(0.05, -0.95, 0.2), RetroMaterials.rag(), Vector3(0.1, 0, 0.08))
	PartBuilder.box(cage, Vector3(0.3, 0.04, 0.3), Vector3(0, -ch + 0.03, 0), RetroMaterials.rag())
	ThornfieldProps.limb(cage, Vector3(0.06, -1.6, 0.05), Vector3(0.2, -1.62, 0.25), 0.025, 0.02, bone, 3)
	var body := ThornfieldProps.new_body(root)
	ThornfieldProps.add_box(body, Vector3(0.5, h, 0.5), Vector3(0, h * 0.5, 0))
	return root


## Weathered milestone: a squat stone with a rounded head, a carved mark
## (`mark` notches) and a cap of lichen. Leans a little.
static func milestone(mark: int, rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	root.name = "Milestone"
	var lichen := lichen_stone()
	var stone := RetroMaterials.stone()
	var lean := Vector3(rng.randf_range(-0.08, 0.08), 0, rng.randf_range(-0.12, 0.12))
	var p := PartBuilder.pivot(root, "Stone", Vector3.ZERO)
	p.rotation = lean
	PartBuilder.box(p, Vector3(0.5, 0.7, 0.28), Vector3(0, 0.3, 0), stone)
	PartBuilder.cylinder(p, 0.25, 0.25, 0.28, Vector3(0, 0.65, 0), stone, 8, Vector3(PI * 0.5, 0, 0))
	PartBuilder.box(p, Vector3(0.34, 0.06, 0.3), Vector3(0, 0.88, 0), lichen, Vector3(0, 0, 0.08))
	var groove := ThornfieldProps.void_mat()
	for i in mark:
		PartBuilder.box(p, Vector3(0.035, 0.22, 0.02), Vector3(-0.12 + i * 0.08, 0.48, 0.14), groove)
	PartBuilder.box(p, Vector3(0.28, 0.03, 0.02), Vector3(0, 0.28, 0.14), groove)
	var body := ThornfieldProps.new_body(root)
	ThornfieldProps.add_box(body, Vector3(0.5, 0.9, 0.3), Vector3(0, 0.45, 0))
	return root


## A lone dead tree of the meadow: a leaning trunk with buttress roots, three
## gnarled limbs that fork twice into bare twigs (a lighter cousin of
## ThornfieldProps.great_dead_tree, ~3k triangles). Meta "bough" (local
## Vector3) is a perch on the lowest limb.
static func lone_tree(height: float, lean: Vector2, rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	root.name = "LoneTree"
	var bark := RetroMaterials.bark()
	var l := Vector3(lean.x, 0, lean.y).normalized() if lean.length() > 0.01 else Vector3.RIGHT
	var r0 := height * 0.05
	var trunk_h := height * 0.42
	var p := Vector3.ZERO
	var r := r0 * 1.3
	for i in 4:
		var dir := (Vector3.UP + l * 0.18 + Vector3(rng.randf_range(-0.15, 0.15), 0, rng.randf_range(-0.15, 0.15))).normalized()
		var np := p + dir * (trunk_h / 4.0)
		var nr := r0 * lerpf(1.0, 0.7, float(i + 1) / 4.0)
		ThornfieldProps.limb(root, p - dir * 0.1, np, r, nr, bark, 7)
		p = np
		r = nr
	for i in 4:
		var a := TAU * i / 4.0 + rng.randf_range(-0.4, 0.4)
		var out := Vector3(cos(a), 0, sin(a))
		ThornfieldProps.limb(root, out * r0 * 0.2 + Vector3(0, r0 * 1.8, 0), out * r0 * rng.randf_range(2.4, 3.4) + Vector3(0, -0.1, 0), r0 * 0.5, r0 * 0.12, bark, 5)
	var phase := rng.randf() * TAU
	var bough := Vector3.ZERO
	for i in 3:
		var a := phase + TAU * i / 3.0 + rng.randf_range(-0.4, 0.4)
		var out := Vector3(cos(a), 0, sin(a))
		var dir := (Vector3.UP * (0.8 + i * 0.25) + out * rng.randf_range(0.6, 1.0) + l * 0.4).normalized()
		var tip := _bough(root, p - Vector3(0, 0.2 + i * 0.35, 0), dir, height * rng.randf_range(0.3, 0.38), r0 * 0.62, 2, rng, bark, l)
		if i == 0:
			bough = tip
	var body := ThornfieldProps.new_body(root)
	ThornfieldProps.add_cyl(body, r0 * 1.1, trunk_h, Vector3(0, trunk_h * 0.5, 0))
	root.set_meta("bough", bough)
	return root


## One kinked limb; forks `depth` more times, ends in bare twigs. Returns the
## point where the first limb kinks (a perch).
static func _bough(parent: Node3D, origin: Vector3, dir: Vector3, length: float, radius: float, depth: int,
		rng: RandomNumberGenerator, mat: Material, lean: Vector3) -> Vector3:
	var kink := (dir + Vector3(rng.randf_range(-0.4, 0.4), rng.randf_range(-0.2, 0.2), rng.randf_range(-0.4, 0.4))).normalized()
	var mid := origin + kink * length * 0.5
	var tip := mid + (dir * 1.2 + lean * 0.25).normalized() * length * 0.5
	var sides := 6 if radius > 0.2 else (4 if radius > 0.06 else 3)
	ThornfieldProps.limb(parent, origin, mid, radius, radius * 0.8, mat, sides)
	ThornfieldProps.limb(parent, mid - kink * 0.03, tip, radius * 0.8, radius * 0.6, mat, sides)
	if depth <= 0:
		for i in 3:
			var td := (dir + Vector3(rng.randf_range(-0.9, 0.9), rng.randf_range(-0.1, 0.7), rng.randf_range(-0.9, 0.9))).normalized()
			ThornfieldProps.limb(parent, tip, tip + td * length * rng.randf_range(0.45, 0.8), radius * 0.45, 0.008, mat, 3)
		return mid
	for i in 2:
		var axis := dir.cross(Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)))
		if axis.length() < 0.01:
			axis = Vector3.RIGHT
		var nd := (dir.rotated(axis.normalized(), rng.randf_range(0.4, 0.9)) + lean * 0.1).normalized()
		var from := tip if i == 0 else mid.lerp(tip, rng.randf_range(0.3, 0.8))
		_bough(parent, from, nd, length * rng.randf_range(0.62, 0.78), radius * 0.6, depth - 1, rng, mat, lean)
	# A short dead side twig off the kink.
	var side := (kink + Vector3(rng.randf_range(-1, 1), 0.4, rng.randf_range(-1, 1))).normalized()
	ThornfieldProps.limb(parent, mid, mid + side * length * 0.35, radius * 0.35, 0.008, mat, 3)
	return mid


## A small roadside cairn of piled field stones.
static func cairn(rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	root.name = "Cairn"
	var y := 0.0
	var r := 0.6
	for layer in 4:
		var n := 5 - layer
		for i in n:
			var a := TAU * i / n + layer * 0.6
			var s := rng.randf_range(0.28, 0.4) * (1.0 - layer * 0.15)
			PartBuilder.box(root, Vector3(s * 1.3, s * 0.75, s), Vector3(cos(a) * r, y + s * 0.35, sin(a) * r),
				field_stone() if i % 2 else lichen_stone(), Vector3(rng.randf_range(-0.2, 0.2), rng.randf() * TAU, rng.randf_range(-0.2, 0.2)))
		y += 0.24
		r *= 0.62
	var body := ThornfieldProps.new_body(root)
	ThornfieldProps.add_cyl(body, 0.7, 1.0, Vector3(0, 0.5, 0))
	return root


## A long low mist bank (camera-facing around Y, fades near and far).
static func mist_bank(parent: Node3D, pos: Vector3, size: Vector2) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = size
	var mi := MeshInstance3D.new()
	mi.name = "MistBank"
	mi.mesh = quad
	mi.material_override = mist_mat()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta(MeshMerger.SKIP_META, true)
	mi.visibility_range_end = 105.0
	mi.position = pos + Vector3(0, size.y * 0.5 - 0.3, 0)
	parent.add_child(mi)
	return mi


# --------------------------------------------------------------------------
# Far village silhouettes
# --------------------------------------------------------------------------
## Flat painted silhouette of a far place, built in true metres in the local
## XY plane (facing +Z), meant to be scaled down and stood ~110 m from the
## meadow. kind: "village" (Hollowmere: roofs and the church spire), "farm"
## (Thornfield: the lone farmhouse and its dead tree), "wood" (a tree line).
static func far_card(kind: String, tone: String, rng: RandomNumberGenerator) -> MeshInstance3D:
	var v := PackedVector3Array()
	var c := PackedColorArray()
	match kind:
		"village":
			var x := -30.0
			while x < 30.0:
				var w := rng.randf_range(5.0, 8.5)
				var h := rng.randf_range(3.5, 6.5)
				var cx := x + w * 0.5
				if absf(cx - 4.0) < 5.0:
					x += w * 0.6
					continue
				_rect(v, c, cx - w * 0.5, 0.0, cx + w * 0.5, h)
				var ridge := h + w * rng.randf_range(0.45, 0.7)
				_tri(v, c, Vector2(cx - w * 0.55, h), Vector2(cx + w * 0.55, h), Vector2(cx + rng.randf_range(-0.4, 0.4), ridge))
				if rng.randf() < 0.6:
					var chx := cx + w * rng.randf_range(-0.3, 0.3)
					_rect(v, c, chx - 0.4, h, chx + 0.4, ridge + 0.8)
				if rng.randf() < 0.35:
					var wx := cx + rng.randf_range(-w * 0.3, w * 0.3)
					_rect(v, c, wx - 0.9, h * 0.4, wx + 0.9, h * 0.4 + 1.6, true)
				if rng.randf() < 0.3:
					_bare_tree(v, c, Vector2(x + rng.randf_range(0.0, w), 0.0), rng.randf_range(7.0, 11.0), rng)
				x += w * rng.randf_range(0.75, 1.05)
			# The church: nave, tower, spire, pinnacles; one window lit.
			_rect(v, c, -1.0, 0.0, 9.0, 8.0)
			_tri(v, c, Vector2(-1.4, 8.0), Vector2(9.4, 8.0), Vector2(4.0, 13.0))
			_rect(v, c, 1.6, 0.0, 6.4, 19.0)
			_tri(v, c, Vector2(1.3, 19.0), Vector2(6.7, 19.0), Vector2(4.0, 33.0))
			for px: float in [1.6, 6.4]:
				_tri(v, c, Vector2(px - 0.5, 19.0), Vector2(px + 0.5, 19.0), Vector2(px, 22.5))
			_rect(v, c, 3.2, 11.5, 4.8, 14.0, true)
		"farm":
			_rect(v, c, -4.0, 0.0, 4.0, 7.0)
			_tri(v, c, Vector2(-4.6, 7.0), Vector2(4.6, 7.0), Vector2(0.0, 11.5))
			_rect(v, c, 2.2, 7.0, 3.1, 12.0)
			_rect(v, c, 4.0, 0.0, 9.0, 3.5)
			_tri(v, c, Vector2(4.0, 3.5), Vector2(9.0, 3.5), Vector2(4.0, 6.0))
			_rect(v, c, -2.0, 4.0, -0.6, 5.6, true)
			# Collapsed barn to the left, the great dead tree to the right.
			_rect(v, c, -19.0, 0.0, -10.0, 4.0)
			_tri(v, c, Vector2(-19.5, 4.0), Vector2(-12.0, 4.0), Vector2(-17.0, 7.0))
			_bare_tree(v, c, Vector2(14.0, 0.0), 17.0, rng)
		_:
			var x := -40.0
			while x < 40.0:
				var h := rng.randf_range(12.0, 22.0)
				if rng.randf() < 0.25:
					_bare_tree(v, c, Vector2(x, 0.0), h * 0.8, rng)
				else:
					_rect(v, c, x - 0.4, 0.0, x + 0.4, h * 0.3)
					for tier in 4:
						var y0 := h * (0.2 + tier * 0.19)
						var hw := (1.0 - tier * 0.22) * h * 0.2
						_tri(v, c, Vector2(x - hw, y0), Vector2(x + hw, y0), Vector2(x, y0 + h * 0.32))
				x += rng.randf_range(2.5, 5.5)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_COLOR] = c
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.name = "FarCard"
	mi.mesh = mesh
	mi.material_override = far_mat(tone)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta(MeshMerger.SKIP_META, true)
	return mi


static func _rect(v: PackedVector3Array, c: PackedColorArray, x0: float, y0: float, x1: float, y1: float, lit := false) -> void:
	var z := 0.05 if lit else 0.0
	var col := Color(1, 0, 0) if lit else Color(0, 0, 0)
	v.append_array(PackedVector3Array([Vector3(x0, y0, z), Vector3(x1, y0, z), Vector3(x1, y1, z), Vector3(x0, y0, z), Vector3(x1, y1, z), Vector3(x0, y1, z)]))
	for i in 6:
		c.append(col)


static func _tri(v: PackedVector3Array, c: PackedColorArray, a: Vector2, b: Vector2, t: Vector2) -> void:
	v.append_array(PackedVector3Array([Vector3(a.x, a.y, 0), Vector3(b.x, b.y, 0), Vector3(t.x, t.y, 0)]))
	for i in 3:
		c.append(Color(0, 0, 0))


## A bare tree as thin tapering triangles (trunk and forking limbs).
static func _bare_tree(v: PackedVector3Array, c: PackedColorArray, base: Vector2, height: float, rng: RandomNumberGenerator) -> void:
	var w := height * 0.045
	var fork := base + Vector2(rng.randf_range(-0.5, 0.5), height * 0.45)
	_limb2(v, c, base, fork, w, w * 0.7)
	for i in 4:
		var a := lerpf(-1.1, 1.1, (float(i) + rng.randf_range(0.2, 0.8)) / 4.0)
		var tip := fork + Vector2(sin(a), cos(a) * 0.9 + 0.2).normalized() * height * rng.randf_range(0.4, 0.6)
		_limb2(v, c, fork, tip, w * 0.6, w * 0.08)
		var mid := fork.lerp(tip, 0.55)
		var twig := mid + Vector2(sin(a * 1.8 + 0.6), 0.8).normalized() * height * 0.2
		_limb2(v, c, mid, twig, w * 0.25, w * 0.04)


static func _limb2(v: PackedVector3Array, c: PackedColorArray, a: Vector2, b: Vector2, wa: float, wb: float) -> void:
	var d := (b - a).normalized()
	var n := Vector2(-d.y, d.x)
	v.append_array(PackedVector3Array([Vector3(a.x - n.x * wa, a.y - n.y * wa, 0), Vector3(a.x + n.x * wa, a.y + n.y * wa, 0), Vector3(b.x + n.x * wb, b.y + n.y * wb, 0),
		Vector3(a.x - n.x * wa, a.y - n.y * wa, 0), Vector3(b.x + n.x * wb, b.y + n.y * wb, 0), Vector3(b.x - n.x * wb, b.y - n.y * wb, 0)]))
	for i in 6:
		c.append(Color(0, 0, 0))
