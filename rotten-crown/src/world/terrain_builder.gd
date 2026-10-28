@tool
class_name TerrainBuilder
extends RefCounted
## Heightfield terrain for the semi-open kingdom: gentle noise hills that fade
## to flat ground around the castle, flattened village plateaus, carved roads,
## and per-vertex paint masks (R road/mud, G dry field, B forest floor) read by
## terrain.gdshader. Output: chunked ArrayMeshes (lights stay local) and one
## HeightMapShape3D collider. Construct, then query height_at() to place props.

const SHADER := preload("res://assets/shaders/terrain.gdshader")

var spec: TerrainSpec
var cols := 0
var rows := 0
var heights := PackedFloat32Array()
var paint := PackedColorArray()

var _hills := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _edge := FastNoiseLite.new()


func _init(p_spec: TerrainSpec) -> void:
	spec = p_spec
	_hills.seed = spec.seed
	_hills.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_hills.fractal_type = FastNoiseLite.FRACTAL_FBM
	_hills.fractal_octaves = 4
	_hills.frequency = spec.hill_frequency
	_detail.seed = spec.seed + 11
	_detail.frequency = 0.05
	_edge.seed = spec.seed + 23
	_edge.frequency = 0.15
	var size := spec.max_corner - spec.min_corner
	cols = int(size.x / spec.cell) + 1
	rows = int(size.y / spec.cell) + 1
	_generate()


## Smoothly interpolated ground height at a world position.
func height_at(x: float, z: float) -> float:
	var gx := clampf((x - spec.min_corner.x) / spec.cell, 0.0, cols - 1.001)
	var gz := clampf((z - spec.min_corner.y) / spec.cell, 0.0, rows - 1.001)
	var ix := int(gx)
	var iz := int(gz)
	var fx := gx - ix
	var fz := gz - iz
	var h00 := heights[iz * cols + ix]
	var h10 := heights[iz * cols + ix + 1]
	var h01 := heights[(iz + 1) * cols + ix]
	var h11 := heights[(iz + 1) * cols + ix + 1]
	return lerpf(lerpf(h00, h10, fx), lerpf(h01, h11, fx), fz)


## Position on the ground under (x, z).
func ground(x: float, z: float) -> Vector3:
	return Vector3(x, height_at(x, z), z)


## Adds chunk meshes and the collider under `root`.
func build(root: Node3D) -> void:
	var container := Node3D.new()
	container.name = "Terrain"
	root.add_child(container)
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("grass_tex", RetroMaterials.dead_grass().albedo_texture)
	mat.set_shader_parameter("dry_tex", _dry_texture())
	mat.set_shader_parameter("road_tex", RetroMaterials.red_earth().albedo_texture)
	mat.set_shader_parameter("forest_tex", RetroMaterials.mossy_stone().albedo_texture)
	var cells_per_chunk := int(spec.chunk_size / spec.cell)
	for cz in range(0, rows - 1, cells_per_chunk):
		for cx in range(0, cols - 1, cells_per_chunk):
			var mi := MeshInstance3D.new()
			mi.name = "Chunk_%d_%d" % [cx, cz]
			mi.mesh = _chunk_mesh(cx, cz, mini(cx + cells_per_chunk, cols - 1), mini(cz + cells_per_chunk, rows - 1))
			mi.material_override = mat
			mi.visibility_range_end = 170.0
			container.add_child(mi)
	_build_collider(container)


## Pale, wind-bleached field texture (reference: the stormy farm field).
static func _dry_texture() -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_VALUE
	noise.frequency = 0.35
	noise.seed = 404
	var g := Gradient.new()
	g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	g.offsets = PackedFloat32Array([0.0, 0.3, 0.6, 0.85])
	g.colors = PackedColorArray([Color(0.09, 0.085, 0.06), Color(0.15, 0.14, 0.09), Color(0.21, 0.19, 0.12), Color(0.12, 0.11, 0.075)])
	var tex := NoiseTexture2D.new()
	tex.width = 32
	tex.height = 32
	tex.seamless = true
	tex.noise = noise
	tex.color_ramp = g
	return tex


func _generate() -> void:
	heights.resize(cols * rows)
	paint.resize(cols * rows)
	for iz in rows:
		for ix in cols:
			var x := spec.min_corner.x + ix * spec.cell
			var z := spec.min_corner.y + iz * spec.cell
			heights[iz * cols + ix] = _raw_height(x, z)
	# Plateaus (villages) flatten towards the height at their centre.
	for p in spec.plateaus:
		var target := _raw_height(p.x, p.y)
		_apply_radial(Vector2(p.x, p.y), p.z, p.w, func(i: int, w: float) -> void:
			heights[i] = lerpf(heights[i], target, w))
	# Roads: carve slightly and level across their width; paint R.
	for iz in rows:
		for ix in cols:
			var i := iz * cols + ix
			var x := spec.min_corner.x + ix * spec.cell
			var z := spec.min_corner.y + iz * spec.cell
			var c := Color(0.0, 0.0, 0.0, 1.0)
			var wobble := _edge.get_noise_2d(x, z) * 0.6
			var road := _road_distance(Vector2(x, z))
			if road.x < spec.road_width * 1.6:
				var level := 1.0 - smoothstep(spec.road_width * 0.6, spec.road_width * 1.6, road.x)
				heights[i] = lerpf(heights[i], road.y - 0.12, level)
				c.r = 1.0 - smoothstep(spec.road_width * 0.35 + wobble, spec.road_width * 0.6 + wobble, road.x)
			for r in spec.mud_rects:
				if r.grow(1.0).has_point(Vector2(x, z)):
					c.r = maxf(c.r, 0.85)
			for f in spec.dry_fields:
				var d := Vector2(x, z).distance_to(Vector2(f.x, f.y))
				c.g = maxf(c.g, 1.0 - smoothstep(f.z * 0.8 + wobble * 6.0, f.z + wobble * 6.0, d))
			for f in spec.forests:
				var d := Vector2(x, z).distance_to(Vector2(f.x, f.y))
				c.b = maxf(c.b, 1.0 - smoothstep(f.z * 0.75 + wobble * 6.0, f.z + wobble * 6.0, d))
			paint[i] = c


func _raw_height(x: float, z: float) -> float:
	var h := _hills.get_noise_2d(x, z) * spec.hill_amplitude + _detail.get_noise_2d(x, z) * spec.detail_amplitude
	var d := Vector2(x, z).distance_to(spec.flat_center)
	return h * smoothstep(spec.flat_radius, spec.flat_radius + spec.flat_falloff, d)


func _apply_radial(center: Vector2, radius: float, falloff: float, fn: Callable) -> void:
	var reach := radius + falloff
	var ix0 := maxi(0, int((center.x - reach - spec.min_corner.x) / spec.cell))
	var ix1 := mini(cols - 1, int((center.x + reach - spec.min_corner.x) / spec.cell) + 1)
	var iz0 := maxi(0, int((center.y - reach - spec.min_corner.y) / spec.cell))
	var iz1 := mini(rows - 1, int((center.y + reach - spec.min_corner.y) / spec.cell) + 1)
	for iz in range(iz0, iz1 + 1):
		for ix in range(ix0, ix1 + 1):
			var p := spec.min_corner + Vector2(ix, iz) * spec.cell
			var w := 1.0 - smoothstep(radius, reach, p.distance_to(center))
			if w > 0.0:
				fn.call(iz * cols + ix, w)


## Returns Vector2(distance to nearest road centreline, raw height there).
func _road_distance(p: Vector2) -> Vector2:
	var best := INF
	var best_h := 0.0
	for line in spec.roads:
		for k in line.size() - 1:
			var a := line[k]
			var b := line[k + 1]
			var margin := spec.road_width * 2.0
			if p.x < minf(a.x, b.x) - margin or p.x > maxf(a.x, b.x) + margin \
					or p.y < minf(a.y, b.y) - margin or p.y > maxf(a.y, b.y) + margin:
				continue
			var ab := b - a
			var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
			var q := a + ab * t
			var d := p.distance_to(q)
			if d < best:
				best = d
				best_h = _raw_height(q.x, q.y)
	return Vector2(best, best_h)


func _chunk_mesh(x0: int, z0: int, x1: int, z1: int) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var w := x1 - x0 + 1
	for iz in range(z0, z1 + 1):
		for ix in range(x0, x1 + 1):
			var i := iz * cols + ix
			var x := spec.min_corner.x + ix * spec.cell
			var z := spec.min_corner.y + iz * spec.cell
			verts.append(Vector3(x, heights[i], z))
			var hl := heights[iz * cols + maxi(ix - 1, 0)]
			var hr := heights[iz * cols + mini(ix + 1, cols - 1)]
			var hd := heights[maxi(iz - 1, 0) * cols + ix]
			var hu := heights[mini(iz + 1, rows - 1) * cols + ix]
			normals.append(Vector3(hl - hr, 2.0 * spec.cell, hd - hu).normalized())
			colors.append(paint[i])
			uvs.append(Vector2(x, z))
	for r in z1 - z0:
		for c in w - 1:
			var a := r * w + c
			indices.append_array(PackedInt32Array([a, a + 1, a + w, a + 1, a + w + 1, a + w]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _build_collider(parent: Node3D) -> void:
	var shape := HeightMapShape3D.new()
	shape.map_width = cols
	shape.map_depth = rows
	var data := PackedFloat32Array()
	data.resize(cols * rows)
	for i in heights.size():
		data[i] = heights[i] / spec.cell  # uniform scale = cell restores metres
	shape.map_data = data
	var body := StaticBody3D.new()
	body.name = "TerrainCollider"
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.scale = Vector3.ONE * spec.cell
	var size := spec.max_corner - spec.min_corner
	cs.position = Vector3(spec.min_corner.x + size.x * 0.5, 0.0, spec.min_corner.y + size.y * 0.5)
	body.add_child(cs)
	parent.add_child(body)
