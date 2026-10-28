@tool
class_name AssetKit
extends RefCounted
## CC0 scanned models from assets/models (Poly Haven, see assets/models/CREDITS.md) for the
## world builders. place() returns plain MeshInstance3D nodes, one per surface, each with its
## material as material_override, so MeshMerger.merge_static can batch them by material.
## Multi-piece models (rock sets, ferns, roots...) hold named pieces; pick one with `piece`.

const DIR := "res://assets/models/%s.glb"

## model -> {piece name -> Array of [Mesh, Material, Transform3D]}
static var _cache: Dictionary = {}


## Piece names of a model (a single-piece model has one).
static func pieces(model: String) -> PackedStringArray:
	return PackedStringArray(_parts(model).keys())


static func random_piece(model: String, rng: RandomNumberGenerator) -> String:
	var names := pieces(model)
	return names[rng.randi() % names.size()]


## Instance `model` (optionally one `piece`) at `pos` on `parent`, rotated by `yaw` and
## uniformly scaled. Pieces are re-centred on their own base, so they land at `pos`.
static func place(parent: Node3D, model: String, pos: Vector3, yaw := 0.0, scale := 1.0, piece := "") -> Node3D:
	var root := Node3D.new()
	root.name = model.to_pascal_case()
	root.position = pos
	root.rotation.y = yaw
	root.scale = Vector3.ONE * scale
	parent.add_child(root)
	var parts := _parts(model)
	var names: Array = [piece] if piece != "" else parts.keys()
	for n in names:
		for entry in parts[n]:
			var mi := MeshInstance3D.new()
			mi.mesh = entry[0]
			mi.material_override = entry[1]
			mi.transform = entry[2]
			if piece != "" or names.size() > 1:
				mi.name = str(n)
			root.add_child(mi)
	return root


## Height of a model (or piece) at scale 1, from its mesh bounds.
static func height(model: String, piece := "") -> float:
	var top := 0.0
	var parts := _parts(model)
	for n in ([piece] if piece != "" else parts.keys()):
		for entry in parts[n]:
			var box: AABB = (entry[2] as Transform3D) * (entry[0] as Mesh).get_aabb()
			top = maxf(top, box.end.y)
	return top


static func _parts(model: String) -> Dictionary:
	if _cache.has(model):
		return _cache[model]
	var scene := load(DIR % model) as PackedScene
	assert(scene != null, "AssetKit: missing model %s" % model)
	var inst := scene.instantiate()
	var meshes := inst.find_children("*", "MeshInstance3D", true, false)
	var parts := {}
	var single := meshes.size() == 1
	for node in meshes:
		var mi := node as MeshInstance3D
		var xf := Transform3D.IDENTITY
		if single:
			xf = Transform3D(mi.transform.basis, Vector3.ZERO)
		else:
			# Re-centre each piece on its base (the scans keep their layout offsets).
			var b := mi.transform * mi.mesh.get_aabb()
			var centre := Vector3(b.position.x + b.size.x * 0.5, b.position.y, b.position.z + b.size.z * 0.5)
			xf = Transform3D(mi.transform.basis, mi.transform.origin - centre)
		var entries: Array = []
		for s in mi.mesh.get_surface_count():
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mi.mesh.surface_get_arrays(s))
			var mat := mi.get_active_material(s)
			entries.append([mesh, mat, xf])
		parts[mi.name] = entries
	inst.free()
	_cache[model] = parts
	return parts
