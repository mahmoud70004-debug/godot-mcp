@tool
class_name WhisperingWoodBuilder
extends RefCounted
## Whispering Wood (reference 3): a night path through a tunnel of ancient
## twisted trees, mossy verges, faint moon shafts and blue mist at the far end.
##
## Contract C9 assumptions:
##  - terrain = TerrainBuilder over OverworldSpec.make(); every placement uses terrain.ground(x, z).
##  - The forest path is OverworldSpec.FOREST_PATH, a road on the terrain (pale dirt paint is the terrain's job).
##  - TerrainSpec.forests holds the zones Vector3(x, z, r) along the path (ground there is forest-painted).
##  - build() adds the returned Node3D "WhisperingWood" to `root` itself.
##  - Markers: Spawn_Enemy_1..3, Lore_1, Pickup_1, Light_1, Trigger (meta "radius" = 45, at the forest entrance).
##  - The preview/overworld moonlight shines along euler(-0.524, -2.634, 0); shafts slant the same way.
##  - All solid meshes use StandardMaterial3D (mergeable by MeshMerger); shafts and mist carry no_merge.

const SHAFT_SHADER := preload("res://assets/shaders/moon_shaft.gdshader")
const GRASS_MATERIAL := preload("res://assets/materials/grass_field.tres")
const PATH_STEP := 4.5
const MOON_EULER := Vector3(-0.524, -2.634, 0.0)
const MAX_SHAFTS := 18
const MAX_MIST := 5
const VERGE_GRASS := 2500


static func build(root: Node3D, terrain: TerrainBuilder, rng: RandomNumberGenerator) -> Node3D:
	var wood := Node3D.new()
	wood.name = "WhisperingWood"
	root.add_child(wood)
	var path := OverworldSpec.sample_path(OverworldSpec.FOREST_PATH, PATH_STEP)
	var clearing_i := path.size() / 2
	var clearing := path[clearing_i]
	_tunnel_trees(wood, terrain, rng, path, clearing)
	_filler_trees(wood, terrain, rng, clearing)
	_verge(wood, terrain, rng, path)
	_logs_and_mushrooms(wood, terrain, rng, path)
	_moon_shafts(wood, terrain, rng, path)
	_mist(wood, terrain, path)
	_markers(wood, terrain, rng, path, clearing_i)
	return wood


static func _group(parent: Node3D, group_name: String) -> Node3D:
	var node := Node3D.new()
	node.name = group_name
	parent.add_child(node)
	return node


static func _path_distance(p: Vector2) -> float:
	var best := INF
	var pts: Array = OverworldSpec.FOREST_PATH
	for k in pts.size() - 1:
		var a: Vector2 = pts[k]
		var b: Vector2 = pts[k + 1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t))
	return best


static func _tangent(path: PackedVector2Array, i: int) -> Vector2:
	var a := path[maxi(i - 1, 0)]
	var b := path[mini(i + 1, path.size() - 1)]
	return (b - a).normalized()


# --- Trees ---------------------------------------------------------------------

static func _tunnel_trees(wood: Node3D, terrain: TerrainBuilder, rng: RandomNumberGenerator, path: PackedVector2Array, clearing: Vector2) -> void:
	var trees := _group(wood, "TunnelTrees")
	for i in path.size():
		var t := _tangent(path, i)
		var n := Vector2(-t.y, t.x)
		for s in [-1.0, 1.0]:
			var off := rng.randf_range(3.5, 5.0)
			var pos := path[i] + n * (s as float) * off + t * rng.randf_range(-1.2, 1.2)
			if pos.distance_to(clearing) < 6.0:
				continue
			var lean := Vector3(-n.x * (s as float), 0.0, -n.y * (s as float))
			var tree := PropKit.gnarled_tree(rng.randf_range(9.0, 13.0), lean, rng)
			tree.position = terrain.ground(pos.x, pos.y)
			trees.add_child(tree)


static func _filler_trees(wood: Node3D, terrain: TerrainBuilder, rng: RandomNumberGenerator, clearing: Vector2) -> void:
	var filler := _group(wood, "FillerTrees")
	for zone in terrain.spec.forests:
		var z: Vector3 = zone
		var placed := 0
		var tries := 0
		while placed < 12 and tries < 200:
			tries += 1
			var ang := rng.randf() * TAU
			var rad := sqrt(rng.randf()) * z.z
			var pos := Vector2(z.x + cos(ang) * rad, z.y + sin(ang) * rad)
			var d := _path_distance(pos)
			if d < 8.0 or d > 25.0 or pos.distance_to(clearing) < 8.0:
				continue
			placed += 1
			var tree: Node3D
			if rng.randf() < 0.22:
				tree = PropKit.dead_tree(rng.randf_range(7.0, 11.0), rng)
			else:
				var toward := Vector2(0.0, 0.0)
				var pts: Array = OverworldSpec.FOREST_PATH
				var best := INF
				for k in pts.size():
					var q: Vector2 = pts[k]
					if q.distance_to(pos) < best:
						best = q.distance_to(pos)
						toward = q - pos
				tree = PropKit.gnarled_tree(rng.randf_range(8.0, 12.0), Vector3(toward.x, 0.0, toward.y), rng)
			tree.position = terrain.ground(pos.x, pos.y)
			filler.add_child(tree)


# --- Ground cover --------------------------------------------------------------

static func _verge(wood: Node3D, terrain: TerrainBuilder, rng: RandomNumberGenerator, path: PackedVector2Array) -> void:
	var mat := GRASS_MATERIAL.duplicate() as ShaderMaterial
	mat.set_shader_parameter("base_color", Color(0.02, 0.05, 0.045))
	mat.set_shader_parameter("tip_color", Color(0.07, 0.16, 0.13))
	var verge := _group(wood, "Verge")
	var accept := func(p: Vector2) -> bool:
		var d := _path_distance(p)
		return d > 1.5 and d < 6.0
	var window := 3
	var windows := ceili(float(path.size()) / window)
	var per := int(float(VERGE_GRASS) / windows)
	for w in windows:
		var c := path[mini(w * window + 1, path.size() - 1)]
		var area := Rect2(c - Vector2(8.5, 8.5), Vector2(17.0, 17.0))
		GrassScatter.scatter(verge, terrain, area, per, mat, Vector2(0.9, 0.5), rng, accept, 45.0)


static func _logs_and_mushrooms(wood: Node3D, terrain: TerrainBuilder, rng: RandomNumberGenerator, path: PackedVector2Array) -> void:
	var props := _group(wood, "Debris")
	var bark := RetroMaterials.bark()
	var moss := RetroMaterials.moss()
	var cap := RetroMaterials.flat(Color(0.62, 0.6, 0.52))
	var stem := RetroMaterials.flat(Color(0.5, 0.48, 0.4))
	for i in 7:
		var c := _beside_path(path, rng, 2.5, 8.0)
		var dir := Vector2.from_angle(rng.randf() * TAU)
		var half := rng.randf_range(1.6, 3.0)
		var a := c - dir * half
		var b := c + dir * half
		var r := rng.randf_range(0.28, 0.5)
		var ga := terrain.ground(a.x, a.y) + Vector3(0.0, r * 0.7, 0.0)
		var gb := terrain.ground(b.x, b.y) + Vector3(0.0, r * 0.7, 0.0)
		PropKit._limb(props, ga, gb, r, r * 0.9, bark, 7)
		var m := PartBuilder.sphere(props, r * 1.3, (ga + gb) * 0.5 + Vector3(0.0, r * 0.55, 0.0), moss, false, 5)
		m.scale = Vector3(2.2, 0.3, 1.0)
		m.rotation.y = -dir.angle()
	for i in 6:
		var c := _beside_path(path, rng, 2.0, 7.0)
		var base := terrain.ground(c.x, c.y)
		for k in rng.randi_range(3, 5):
			var o := Vector3(rng.randf_range(-0.35, 0.35), 0.0, rng.randf_range(-0.35, 0.35))
			var h := rng.randf_range(0.1, 0.28)
			var rad := h * rng.randf_range(0.5, 0.8)
			PartBuilder.cylinder(props, rad * 0.25, rad * 0.3, h, base + o + Vector3(0.0, h * 0.5, 0.0), stem, 5)
			var head := PartBuilder.sphere(props, rad, base + o + Vector3(0.0, h, 0.0), cap, true, 6)
			head.scale = Vector3(1.0, 0.8, 1.0)


static func _beside_path(path: PackedVector2Array, rng: RandomNumberGenerator, d_min: float, d_max: float) -> Vector2:
	var i := rng.randi_range(2, path.size() - 3)
	var t := _tangent(path, i)
	var n := Vector2(-t.y, t.x)
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	return path[i] + n * side * rng.randf_range(d_min, d_max)


# --- Light and mist ------------------------------------------------------------

static func _moon_shafts(wood: Node3D, terrain: TerrainBuilder, rng: RandomNumberGenerator, path: PackedVector2Array) -> void:
	var group := _group(wood, "MoonShafts")
	var up := -(Basis.from_euler(MOON_EULER) * Vector3(0.0, 0.0, -1.0))
	var rot := Basis(Quaternion(Vector3.UP, up))
	var every := maxi(roundi(12.0 / PATH_STEP), int(ceil(float(path.size()) / MAX_SHAFTS)))
	var count := 0
	for i in range(2, path.size() - 1, every):
		if count >= MAX_SHAFTS:
			break
		count += 1
		var t := _tangent(path, i)
		var n := Vector2(-t.y, t.x)
		var c := path[i] + n * rng.randf_range(-2.5, 2.5)
		var mat := ShaderMaterial.new()
		mat.shader = SHAFT_SHADER
		mat.set_shader_parameter("tint", Color(0.62, 0.76, 1.0))
		mat.set_shader_parameter("intensity", rng.randf_range(0.07, 0.11))
		mat.set_shader_parameter("far_start", 55.0)
		mat.set_shader_parameter("far_end", 110.0)
		var mi := MeshInstance3D.new()
		mi.mesh = _shaft_mesh(rng.randf_range(1.3, 2.6), rng.randf_range(12.0, 15.0))
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.set_meta(MeshMerger.SKIP_META, true)
		mi.transform = Transform3D(rot * Basis(Vector3.UP, rng.randf() * PI), terrain.ground(c.x, c.y) - Vector3(0.0, 0.5, 0.0))
		group.add_child(mi)


## Two crossed quads (origin at the bottom centre, extends along +Y).
static func _shaft_mesh(width: float, height: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 2:
		var ax := Vector3.RIGHT if k == 0 else Vector3.BACK
		var a := -ax * width * 0.5
		var b := ax * width * 0.5
		var tl := a + Vector3(0.0, height, 0.0)
		var tr := b + Vector3(0.0, height, 0.0)
		for v: Array in [[tl, Vector2(0, 0)], [tr, Vector2(1, 0)], [b, Vector2(1, 1)], [tl, Vector2(0, 0)], [b, Vector2(1, 1)], [a, Vector2(0, 1)]]:
			st.set_normal(Vector3.UP)
			st.set_uv(v[1] as Vector2)
			st.add_vertex(v[0] as Vector3)
	return st.commit()


static func _mist(wood: Node3D, terrain: TerrainBuilder, path: PackedVector2Array) -> void:
	var group := _group(wood, "BlueMist")
	var fractions := [0.5, 0.64, 0.78, 0.9, 1.0]
	for k in MAX_MIST:
		var i := mini(int(float(path.size() - 1) * (fractions[k] as float)), path.size() - 1)
		var c := path[i]
		var mat := ShaderMaterial.new()
		mat.shader = SHAFT_SHADER
		mat.set_shader_parameter("tint", Color(0.3, 0.45, 0.95))
		mat.set_shader_parameter("intensity", 0.7)
		mat.set_shader_parameter("radial", 1.0)
		mat.set_shader_parameter("billboard", true)
		mat.set_shader_parameter("shimmer", 0.05)
		mat.set_shader_parameter("near_start", 6.0)
		mat.set_shader_parameter("near_end", 24.0)
		mat.set_shader_parameter("far_start", 400.0)
		mat.set_shader_parameter("far_end", 500.0)
		var quad := QuadMesh.new()
		quad.size = Vector2(54.0, 24.0)
		var mi := MeshInstance3D.new()
		mi.mesh = quad
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.set_meta(MeshMerger.SKIP_META, true)
		mi.position = terrain.ground(c.x, c.y) + Vector3(0.0, 4.5, 0.0)
		group.add_child(mi)


# --- Markers -------------------------------------------------------------------

static func _marker(parent: Node3D, marker_name: String, pos: Vector3) -> Marker3D:
	var m := Marker3D.new()
	m.name = marker_name
	m.position = pos
	parent.add_child(m)
	return m


static func _markers(wood: Node3D, terrain: TerrainBuilder, rng: RandomNumberGenerator, path: PackedVector2Array, clearing_i: int) -> void:
	var markers := _group(wood, "Markers")
	var entrance := Vector2(45.0, 72.0)
	var trigger := _marker(markers, "Trigger", terrain.ground(entrance.x, entrance.y))
	trigger.set_meta("radius", 45.0)
	var spots := [0.3, 0.62, 0.85]
	for k in 3:
		var i := int(float(path.size() - 1) * (spots[k] as float))
		var t := _tangent(path, i)
		var c := path[i] + Vector2(-t.y, t.x) * rng.randf_range(-1.5, 1.5)
		_marker(markers, "Spawn_Enemy_%d" % (k + 1), terrain.ground(c.x, c.y))
	var li := int(float(path.size() - 1) * 0.4)
	var lt := _tangent(path, li)
	var lp := path[li] + Vector2(-lt.y, lt.x) * 2.2
	_marker(markers, "Lore_1", terrain.ground(lp.x, lp.y))
	var pick_i := int(float(path.size() - 1) * 0.72)
	var pt := _tangent(path, pick_i)
	var pp := path[pick_i] + Vector2(-pt.y, pt.x) * -2.4
	_marker(markers, "Pickup_1", terrain.ground(pp.x, pp.y))
	var cp := path[clearing_i]
	var lm := _marker(markers, "Light_1", terrain.ground(cp.x, cp.y) + Vector3(0.0, 2.6, 0.0))
	var light := OmniLight3D.new()
	light.name = "ClearingLight"
	light.light_color = Color(0.5, 0.65, 1.0)
	light.light_energy = 0.55
	light.omni_range = 7.0
	light.shadow_enabled = false
	lm.add_child(light)
