@tool
class_name GrassScatter
extends RefCounted
## Scatters grass tufts over the terrain as chunked MultiMeshes (12 m chunks,
## culled beyond `range_end`) — the only cheap way to draw lots of grass on the
## web renderer. `accept` decides per sample point whether grass grows there.

const CHUNK := 12.0


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
		mmi.add_to_group(&"grass_chunks")
		group.add_child(mmi)
	return group
