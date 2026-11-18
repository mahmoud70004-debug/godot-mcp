@tool
class_name GothicEntrance
extends RefCounted
## V28 - the kingdom's gothic face as the knight first sees it: from the meadow, the curtain wall is no
## longer one plain slab. Great octagonal towers with spires rise out of it every few dozen metres, slim
## turrets flank the gate, tall stepped buttresses crowned with pinnacles and rows of blind pointed windows
## march along both runs (GothicKit). All of it hangs on the OUTER face of the south wall (z = SOUTH -
## THICKNESS / 2); the gate, the wall and its colliders are untouched. Merged by MeshMerger; a few boxes
## of collision where the player can reach (towers and buttress feet).

const FACE_Z := KingdomWalls.SOUTH - KingdomWalls.THICKNESS * 0.5
const GATE_CLEAR := 11.0
## [x, radius, shaft height, spire height]: the great towers on the wall (mirrored to both sides).
const TOWERS := [[30.0, 5.4, 27.0, 26.0], [104.0, 5.0, 23.0, 22.0], [172.0, 5.6, 31.0, 28.0]]
## Slim turrets flanking the gate: [x, radius, height, spire height].
const TURRETS := [[13.5, 2.3, 17.0, 13.0]]
const BUTTRESS_STEP := 14.0
const BUTTRESS_FIRST := 52.0
const BUTTRESS_LAST := 225.0
const BUTTRESS_H := 13.5


static func build(root: Node3D, terrain: TerrainBuilder) -> Node3D:
	var node := Node3D.new()
	node.name = "GothicEntrance"
	root.add_child(node)
	var b := GothicKit.Builder.new()
	var out_basis := Basis(Vector3.UP, PI)  # the kit's +z (away from the wall) points out to the meadow (-z)
	for side in [-1.0, 1.0]:
		for t: Array in TOWERS:
			_at(b, terrain, side * float(t[0]), -1.5 - float(t[1]) * 0.7, out_basis)
			GothicKit.great_tower(b, float(t[1]), float(t[2]), float(t[3]))
			_solid(node, terrain, Vector3(side * float(t[0]), 0.0, FACE_Z - 1.5 - float(t[1]) * 0.7), float(t[1]) * 1.7, float(t[2]) * 0.8)
		for t: Array in TURRETS:
			_at(b, terrain, side * float(t[0]), -0.4 - float(t[1]) * 0.6, out_basis)
			GothicKit.great_tower(b, float(t[1]), float(t[2]), float(t[3]))
			_solid(node, terrain, Vector3(side * float(t[0]), 0.0, FACE_Z - 0.4 - float(t[1]) * 0.6), float(t[1]) * 1.7, float(t[2]) * 0.8)
		var x := BUTTRESS_FIRST
		while x <= BUTTRESS_LAST:
			if _clear_of_towers(x):
				_at(b, terrain, side * x, 0.0, out_basis)
				GothicKit.buttress(b, 1.5, 2.4, BUTTRESS_H)
				_solid(node, terrain, Vector3(side * x, 0.0, FACE_Z - 1.1), 1.5, BUTTRESS_H * 0.5)
			var wx := x + BUTTRESS_STEP * 0.5
			if wx <= BUTTRESS_LAST and _clear_of_towers(wx):
				_at(b, terrain, side * wx, 3.2, out_basis, 0.04)
				GothicKit.window(b, Vector3.ZERO, Vector3.BACK, 2.3, 6.4, false)
			x += BUTTRESS_STEP
	b.xf = Transform3D.IDENTITY
	b.commit(node, CastleProps.front_stone(), CastleProps.front_mossy())
	print("GothicEntrance: %d triangles" % b.tris)
	MeshMerger.merge_static(node, 120.0, 200.0)
	return node


## Puts the builder's origin on the wall face at world x, `dz` metres off it (negative = out), `up` above the ground.
static func _at(b: GothicKit.Builder, terrain: TerrainBuilder, x: float, dz: float, basis: Basis, up := -0.8) -> void:
	var y := terrain.height_at(x, FACE_Z + dz)
	b.xf = Transform3D(basis, Vector3(x, y + up, FACE_Z + dz * -1.0 * -1.0))
	# dz is measured in the kit frame (negative = out of the face), i.e. world z grows with dz.
	b.xf.origin.z = FACE_Z + dz


static func _clear_of_towers(x: float) -> bool:
	for t: Array in TOWERS:
		if absf(x - float(t[0])) < float(t[1]) + 3.4 or absf(x - float(t[0])) < 8.0:
			return false
	for t: Array in TURRETS:
		if absf(x - float(t[0])) < float(t[1]) + 2.5:
			return false
	return x > GATE_CLEAR


static func _solid(parent: Node3D, terrain: TerrainBuilder, at: Vector3, width: float, half_height: float) -> void:
	var body := StaticBody3D.new()
	body.name = "GothicCollider"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(width, half_height * 2.0, width)
	shape.shape = box
	body.position = Vector3(at.x, terrain.height_at(at.x, at.z) + half_height - 0.8, at.z)
	body.add_child(shape)
	parent.add_child(body)
