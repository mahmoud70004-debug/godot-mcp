@tool
class_name PartBuilder
extends RefCounted
## Tiny helpers for assembling characters out of primitive meshes.


static func pivot(parent: Node3D, node_name: String, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = node_name
	n.position = pos
	parent.add_child(n)
	return n


static func box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var m := BoxMesh.new()
	m.size = size
	return _instance(parent, m, pos, mat, rot)


static func cylinder(parent: Node3D, top: float, bottom: float, height: float, pos: Vector3, mat: Material, segments: int = 8, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = height
	m.radial_segments = segments
	m.rings = 1
	return _instance(parent, m, pos, mat, rot)


static func sphere(parent: Node3D, radius: float, pos: Vector3, mat: Material, hemisphere: bool = false, segments: int = 8) -> MeshInstance3D:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius if hemisphere else radius * 2.0
	m.is_hemisphere = hemisphere
	m.radial_segments = segments
	m.rings = 4
	return _instance(parent, m, pos, mat)


static func steel(color: Color = Color(0.55, 0.56, 0.6)) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = 0.75
	mat.roughness = 0.35
	return mat


static func _instance(parent: Node3D, mesh: Mesh, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi
