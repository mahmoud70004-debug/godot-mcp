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


static func steel(color: Color = Color(0.55, 0.56, 0.6), metallic: float = 0.75, roughness: float = 0.35) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metallic
	mat.roughness = roughness
	return mat


## Four-sided tapered slab (wider at the bottom when bottom_w > top_w): cloak
## panels, tassets, plume feathers. Hangs along -Y from its centre.
static func frustum(parent: Node3D, top_w: float, bottom_w: float, height: float, thick: float, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var hy := height * 0.5
	var t := top_w * 0.5
	var b := bottom_w * 0.5
	var d := thick * 0.5
	var v := [
		Vector3(-t, hy, -d), Vector3(t, hy, -d), Vector3(t, hy, d), Vector3(-t, hy, d),
		Vector3(-b, -hy, -d), Vector3(b, -hy, -d), Vector3(b, -hy, d), Vector3(-b, -hy, d),
	]
	var quads := [[0, 1, 2, 3], [7, 6, 5, 4], [0, 4, 5, 1], [1, 5, 6, 2], [2, 6, 7, 3], [3, 7, 4, 0]]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for q in quads:
		for i in [0, 1, 2, 0, 2, 3]:
			st.add_vertex(v[q[i]])
	st.generate_normals()
	return _instance(parent, st.commit(), pos, mat, rot)


static func _instance(parent: Node3D, mesh: Mesh, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi
