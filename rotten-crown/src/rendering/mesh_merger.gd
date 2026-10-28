@tool
class_name MeshMerger
extends RefCounted
## Draw-call reduction for primitive-built scenes.
##
## The web build uses the Compatibility renderer, which draws every object
## once more for each light touching it. Hundreds of tiny boxes x several
## lights is what makes the procedural scenes slow, so:
##  - merge_static(): bakes static meshes into one mesh per (material, cell);
##    cells keep lights local, so a lantern only re-draws its own chunk.
##  - bake_character(): bakes the pieces under each animated pivot into one
##    vertex-coloured mesh (one matte + one metal material for all characters).
## Original nodes are hidden, not freed, so their colliders keep working.

const SKIP_META := "no_merge"
## ShaderMaterial splats store their variation seed here; it is baked into
## vertex colour (COLOR.r) because merged meshes share one instance.
const SEED_META := "seed01"

static var _character_matte: StandardMaterial3D
static var _character_metal: StandardMaterial3D


## range_end > 0 culls merged chunks beyond that distance (fog hides them anyway).
static func merge_static(root: Node3D, cell_size: float = 20.0, range_end: float = 0.0) -> int:
	var groups: Dictionary = {}
	var inverse_root := root.global_transform.affine_inverse() if root.is_inside_tree() else Transform3D.IDENTITY
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if not _mergeable(mi):
			continue
		var xf := _relative_transform(root, mi, inverse_root)
		var cell := Vector3i((xf.origin / cell_size).floor())
		var key := "%d|%s" % [mi.material_override.get_instance_id(), cell]
		if not groups.has(key):
			groups[key] = {"material": mi.material_override, "acc": _new_acc(), "nodes": []}
		var seed_color := Color(float(mi.get_meta(SEED_META, 1.0)), 1.0, 1.0)
		_append(groups[key]["acc"], mi.mesh, xf, seed_color)
		(groups[key]["nodes"] as Array).append(mi)
	var merged := 0
	for key in groups:
		var g: Dictionary = groups[key]
		if (g["nodes"] as Array).size() < 2:
			continue
		var out := MeshInstance3D.new()
		out.name = "Merged"
		out.mesh = _commit(g["acc"])
		out.material_override = g["material"]
		var first := (g["nodes"] as Array)[0] as MeshInstance3D
		out.cast_shadow = first.cast_shadow
		out.visibility_range_end = range_end
		root.add_child(out)
		for n in g["nodes"]:
			(n as MeshInstance3D).visible = false
			merged += 1
	return merged


static func bake_character(root: Node3D) -> void:
	if _character_matte == null:
		_character_matte = StandardMaterial3D.new()
		_character_matte.vertex_color_use_as_albedo = true
		_character_matte.roughness = 0.85
		_character_metal = StandardMaterial3D.new()
		_character_metal.vertex_color_use_as_albedo = true
		_character_metal.metallic = 0.75
		_character_metal.roughness = 0.35
	var pivots: Array[Node3D] = [root]
	for node in root.find_children("*", "Node3D", true, false):
		if not node is MeshInstance3D:
			pivots.append(node as Node3D)
	for pivot in pivots:
		var accs := {"matte": _new_acc(), "metal": _new_acc()}
		var used := {"matte": [], "metal": []}
		for child in pivot.get_children():
			var mi := child as MeshInstance3D
			if mi == null or mi.mesh == null or not mi.material_override is StandardMaterial3D:
				continue
			var mat := mi.material_override as StandardMaterial3D
			var kind := "metal" if mat.metallic > 0.3 else "matte"
			var color: Color = mat.get_meta("swatch", mat.albedo_color)
			_append(accs[kind], mi.mesh, mi.transform, color)
			(used[kind] as Array).append(mi)
		for kind in ["matte", "metal"]:
			if (used[kind] as Array).is_empty():
				continue
			var out := MeshInstance3D.new()
			out.name = "Baked_" + kind
			out.mesh = _commit(accs[kind])
			out.material_override = _character_metal if kind == "metal" else _character_matte
			pivot.add_child(out)
			for mi in used[kind]:
				(mi as MeshInstance3D).queue_free()


static func _mergeable(mi: MeshInstance3D) -> bool:
	if mi.mesh == null or not mi.visible or mi.has_meta(SKIP_META):
		return false
	if mi.material_override is StandardMaterial3D:
		return true
	return mi.material_override is ShaderMaterial and mi.has_meta(SEED_META)


static func _relative_transform(root: Node3D, node: Node3D, inverse_root: Transform3D) -> Transform3D:
	if node.is_inside_tree() and root.is_inside_tree():
		return inverse_root * node.global_transform
	var xf := node.transform
	var p := node.get_parent() as Node3D
	while p and p != root:
		xf = p.transform * xf
		p = p.get_parent() as Node3D
	return xf


static func _new_acc() -> Dictionary:
	return {"v": PackedVector3Array(), "n": PackedVector3Array(), "uv": PackedVector2Array(), "c": PackedColorArray(), "i": PackedInt32Array()}


static func _append(acc: Dictionary, mesh: Mesh, xf: Transform3D, color: Color) -> void:
	var normal_basis := xf.basis.inverse().transposed()
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		# Take the arrays out of the dictionary first: packed arrays are
		# copy-on-write, and a second reference would copy them on every append.
		var v_out: PackedVector3Array = acc["v"]
		var n_out: PackedVector3Array = acc["n"]
		var uv_out: PackedVector2Array = acc["uv"]
		var c_out: PackedColorArray = acc["c"]
		var i_out: PackedInt32Array = acc["i"]
		for key in ["v", "n", "uv", "c", "i"]:
			acc[key] = null
		var base := v_out.size()
		for k in verts.size():
			v_out.append(xf * verts[k])
			n_out.append((normal_basis * normals[k]).normalized() if k < normals.size() else Vector3.UP)
			uv_out.append(uvs[k] if k < uvs.size() else Vector2.ZERO)
			c_out.append(color)
		if indices.is_empty():
			for k in verts.size():
				i_out.append(base + k)
		else:
			for idx in indices:
				i_out.append(base + idx)
		acc["v"] = v_out
		acc["n"] = n_out
		acc["uv"] = uv_out
		acc["c"] = c_out
		acc["i"] = i_out


static func _commit(acc: Dictionary) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = acc["v"]
	arrays[Mesh.ARRAY_NORMAL] = acc["n"]
	arrays[Mesh.ARRAY_TEX_UV] = acc["uv"]
	arrays[Mesh.ARRAY_COLOR] = acc["c"]
	arrays[Mesh.ARRAY_INDEX] = acc["i"]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
