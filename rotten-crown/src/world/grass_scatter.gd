@tool
class_name GrassScatter
extends RefCounted
## Scatters grass tufts over the terrain as chunked MultiMeshes (12 m chunks,
## culled beyond `range_end`) — the only cheap way to draw lots of grass on the
## web renderer. `accept` decides per sample point whether grass grows there.

const CHUNK := 12.0
## Meta on merged chunks: the visibility range of the chunks they replace (QualityManager
## scales it into the material's `chunk_range` together with the node's own range).
const RANGE_META := &"chunk_range"


## area: Rect2 in world xz. accept: Callable(Vector2) -> bool (null = everywhere).
static func scatter(root: Node3D, terrain: TerrainBuilder, area: Rect2, count: int, material: Material,
		quad_size: Vector2, rng: RandomNumberGenerator, accept: Callable = Callable(), range_end: float = 40.0) -> Node3D:
	var quad := QuadMesh.new()
	quad.size = quad_size
	quad.center_offset = Vector3(0.0, quad_size.y * 0.5, 0.0)
	quad.material = material
	var chunks: Dictionary = {}
	var placed := 0
	var attempts := 0
	while placed < count and attempts < count * 4:
		attempts += 1
		var p := Vector2(rng.randf_range(area.position.x, area.end.x), rng.randf_range(area.position.y, area.end.y))
		if accept.is_valid() and not bool(accept.call(p)):
			continue
		var s := rng.randf_range(0.75, 1.35)
		var basis := Basis(Vector3.UP, rng.randf() * PI).scaled(Vector3(s, s * rng.randf_range(0.8, 1.3), s))
		var cell := Vector2i(floori(p.x / CHUNK), floori(p.y / CHUNK))
		if not chunks.has(cell):
			chunks[cell] = []
		(chunks[cell] as Array).append(Transform3D(basis, terrain.ground(p.x, p.y) - Vector3(0.0, 0.05, 0.0)))
		placed += 1
	var group := Node3D.new()
	group.name = "Grass"
	root.add_child(group)
	for cell in chunks:
		var list: Array = chunks[cell]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = quad
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = range_end
		mmi.add_to_group(&"grass_chunks", true)  # persistent: survives the world bake
		group.add_child(mmi)
	return group


## Draw calls: joins the grass chunks (group "grass_chunks") under `root` that share a
## mesh and range into chunks `factor` x `factor` wider. Every instance keeps the cull
## centre of its old chunk in INSTANCE_CUSTOM.xyz and grass.gdshader hides it beyond the
## material's `chunk_range`, exactly where that chunk was culled. Instance order keeps
## QualityManager's Low setting (first half of each multimesh) on the same tufts: the
## first halves of all old chunks come first, odd ones padded with an empty instance.
static func merge_chunks(root: Node3D, factor: int) -> int:
	var groups: Dictionary = {}
	for node in root.find_children("*", "MultiMeshInstance3D", true, false):
		var mmi := node as MultiMeshInstance3D
		if not mmi.is_in_group(&"grass_chunks") or mmi.multimesh == null or mmi.multimesh.instance_count == 0:
			continue
		var mm := mmi.multimesh
		if mm.use_custom_data or mm.use_colors or mm.transform_format != MultiMesh.TRANSFORM_3D \
				or not mmi.global_transform.is_equal_approx(Transform3D.IDENTITY):
			continue
		var center := (mmi.global_transform * mmi.get_aabb()).get_center()
		var span := CHUNK * factor
		# Each scatter() call makes its own quad: same material + quad = same tufts.
		var quad := mm.mesh as QuadMesh
		var mesh_key := "%d|%s|%s" % [quad.material.get_instance_id(), quad.size, quad.center_offset] if quad \
			else str(mm.mesh.get_instance_id())
		var key := "%s|%d|%d|%d" % [mesh_key, roundi(mmi.visibility_range_end * 10.0),
			floori(center.x / span), floori(center.z / span)]
		if not groups.has(key):
			groups[key] = {"mesh_key": mesh_key, "parts": []}
		(groups[key]["parts"] as Array).append([mmi, center])
	var made := 0
	# Merged chunks get their own copy of the tuft mesh and material, so `chunk_range`
	# never reaches unmerged users of a shared material (they have no INSTANCE_CUSTOM).
	var meshes: Dictionary = {}
	for key in groups:
		var parts: Array = groups[key]["parts"]
		var source_key: String = groups[key]["mesh_key"]
		if parts.size() < 2:
			continue
		var first: MultiMeshInstance3D = parts[0][0]
		var range_end := first.visibility_range_end
		var heads: Array = []
		var tails: Array = []
		var box := AABB()
		for k in parts.size():
			var mmi: MultiMeshInstance3D = parts[k][0]
			var center: Vector3 = parts[k][1]
			var own := mmi.global_transform * mmi.get_aabb()
			box = own if k == 0 else box.merge(own)
			var mm := mmi.multimesh
			var half := mm.instance_count / 2
			for i in mm.instance_count:
				(heads if i < half else tails).append([mm.get_instance_transform(i), center])
			if mm.instance_count % 2 == 1:
				heads.append([Transform3D(Basis.from_scale(Vector3.ZERO), center), center])
		var all := heads + tails
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		var source := first.multimesh.mesh
		if not meshes.has(source_key):
			var copy := source.duplicate() as Mesh
			var source_mat := source.surface_get_material(0) as ShaderMaterial
			if copy is PrimitiveMesh and source_mat:
				var mat_copy := source_mat.duplicate() as ShaderMaterial
				mat_copy.set_shader_parameter("chunk_range", range_end)
				(copy as PrimitiveMesh).material = mat_copy
			meshes[source_key] = copy
		mm.mesh = meshes[source_key]
		mm.instance_count = all.size()
		for i in all.size():
			var c: Vector3 = all[i][1]
			mm.set_instance_transform(i, all[i][0])
			mm.set_instance_custom_data(i, Color(c.x, c.y, c.z, 0.0))
		var out := MultiMeshInstance3D.new()
		out.name = "GrassChunk"
		out.multimesh = mm
		out.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Drawn while any of its old chunks would be.
		var spread := 0.0
		for part in parts:
			spread = maxf(spread, box.get_center().distance_to(part[1] as Vector3))
		out.visibility_range_end = range_end + spread + 0.5
		out.set_meta(RANGE_META, range_end)
		out.add_to_group(&"grass_chunks", true)
		first.get_parent().add_child(out)
		for part in parts:
			(part[0] as Node).queue_free()
		made += 1
	return made
