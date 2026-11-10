@tool
class_name KingdomWalls
extends RefCounted
## The outer kingdom boundary is structural scenery, not a progression gate.
## All inhabited regions lie inside it; the existing ward remains a separate
## inner enclosure. Uses the existing castle materials and no new lights.

const WEST := -235.0
const EAST := 235.0
const SOUTH := 58.0
const NORTH := 490.0
const GAP := 8.0
const WALL_HEIGHT := 10.5
const SEGMENT_LENGTH := 18.0


static func build(root: Node3D, terrain: TerrainBuilder) -> void:
	var walls := Node3D.new()
	walls.name = "KingdomWalls"
	root.add_child(walls)
	var stone := CastleProps.front_stone()
	var moss := CastleProps.front_mossy()
	_wall_run(walls, terrain, Vector2(WEST, SOUTH), Vector2(-GAP, SOUTH), stone, moss)
	_wall_run(walls, terrain, Vector2(GAP, SOUTH), Vector2(EAST, SOUTH), stone, moss)
	_wall_run(walls, terrain, Vector2(WEST, SOUTH), Vector2(WEST, NORTH), stone, moss)
	_wall_run(walls, terrain, Vector2(EAST, SOUTH), Vector2(EAST, NORTH), stone, moss)
	_wall_run(walls, terrain, Vector2(WEST, NORTH), Vector2(EAST, NORTH), stone, moss)
	for p in [Vector2(WEST, SOUTH), Vector2(EAST, SOUTH), Vector2(WEST, NORTH), Vector2(EAST, NORTH)]:
		_tower(walls, terrain.ground(p.x, p.y), 7.0, 21.0, stone, moss, true)
	for z in [160.0, 270.0, 380.0]:
		for x in [WEST, EAST]:
			_tower(walls, terrain.ground(x, z), 6.2, 19.0, stone, moss, true)
	_gatehouse(walls, terrain)
	_palace_wings(walls, terrain, stone, moss)
	# Keep the original collision bodies; merge the stonework for the mobile renderer.
	MeshMerger.merge_static(walls, 64.0, 150.0)


static func _wall_run(parent: Node3D, terrain: TerrainBuilder, a: Vector2, b: Vector2,
		stone: Material, moss: Material) -> void:
	var count := ceili(a.distance_to(b) / SEGMENT_LENGTH)
	for i in count:
		var p := a.lerp(b, float(i) / count)
		var q := a.lerp(b, float(i + 1) / count)
		var middle := (p + q) * 0.5
		var base := minf(terrain.height_at(p.x, p.y), terrain.height_at(q.x, q.y)) - 1.8
		var group := Node3D.new()
		group.position = Vector3(middle.x, base, middle.y)
		group.rotation.y = atan2(-(q - p).y, (q - p).x)
		parent.add_child(group)
		var length := p.distance_to(q) + 0.3
		_box(group, Vector3(length, WALL_HEIGHT + 1.8, 3.2),
			Vector3(0.0, (WALL_HEIGHT + 1.8) * 0.5, 0.0), stone, true)
		_box(group, Vector3(length, 1.0, 3.8), Vector3(0.0, 2.0, 0.0), moss)
		_box(group, Vector3(length, 0.6, 3.8), Vector3(0.0, WALL_HEIGHT + 1.8, 0.0), stone)
		var merlons := maxi(1, floori(length / 4.3))
		for j in merlons:
			var x := -length * 0.5 + length * (float(j) + 0.5) / merlons
			_box(group, Vector3(2.1, 1.6, 3.8), Vector3(x, WALL_HEIGHT + 2.8, 0.0), stone)


static func _tower(parent: Node3D, base: Vector3, width: float, height: float,
		stone: Material, moss: Material, collide: bool) -> void:
	var tower := Node3D.new()
	tower.position = base - Vector3(0.0, 1.5, 0.0)
	parent.add_child(tower)
	_box(tower, Vector3(width, height + 1.5, width), Vector3(0.0, (height + 1.5) * 0.5, 0.0), stone, collide)
	_box(tower, Vector3(width + 0.7, 1.4, width + 0.7), Vector3(0.0, 2.0, 0.0), moss)
	_box(tower, Vector3(width + 0.8, 1.0, width + 0.8), Vector3(0.0, height + 1.7, 0.0), stone)
	for side in [-1.0, 1.0]:
		for k in 3:
			var along := (float(k) - 1.0) * width * 0.32
			_box(tower, Vector3(1.2, 1.2, 0.8),
				Vector3(along, height + 2.8, side * width * 0.5), stone)
			_box(tower, Vector3(0.8, 1.2, 1.2),
				Vector3(side * width * 0.5, height + 2.8, along), stone)
	var roof := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = width * 0.68
	cone.height = width * 0.9
	cone.radial_segments = 4
	cone.rings = 1
	roof.mesh = cone
	roof.material_override = RetroMaterials.roof()
	roof.position.y = height + 2.6 + cone.height * 0.5
	roof.rotation.y = PI * 0.25
	tower.add_child(roof)


static func _gatehouse(parent: Node3D, terrain: TerrainBuilder) -> void:
	# Reuse the established Gothic gate, its broken doors and tattered banners so
	# the new perimeter keeps the original artistic language. The gate passage
	# remains open; its temporary feast-spill light is not part of this setting.
	var scale_factor := 1.25
	var gate := Node3D.new()
	gate.name = "KingdomGatehouse"
	gate.position = Vector3(0.0, terrain.height_at(0.0, SOUTH), SOUTH + 10.0 * scale_factor)
	gate.rotation.y = PI
	gate.scale = Vector3.ONE * scale_factor
	parent.add_child(gate)
	var rng := RandomNumberGenerator.new()
	rng.seed = 704
	var castle := CastleProps.new(false, rng, null)
	castle.gatehouse(gate)
	castle.gate_banners(gate)
	var spill_glow := gate.get_node_or_null("SpillGlow")
	if spill_glow:
		spill_glow.free()


static func _palace_wings(parent: Node3D, terrain: TerrainBuilder, stone: Material, moss: Material) -> void:
	var y := terrain.height_at(0.0, 475.0)
	var palace := Node3D.new()
	palace.name = "RoyalPalaceWings"
	parent.add_child(palace)
	# Behind the preserved keep, flanking towers make the royal residence read as
	# a much larger castle without modifying the original prologue set.
	_box(palace, Vector3(48.0, 21.0, 5.0), Vector3(0.0, y + 10.5, 478.0), stone)
	for side in [-1.0, 1.0]:
		_tower(palace, Vector3(side * 24.0, y, 475.0), 8.0, 31.0, stone, moss, false)


static func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, collide := false) -> void:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.material_override = mat
	instance.position = pos
	parent.add_child(instance)
	if collide:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		body.add_child(shape)
		instance.add_child(body)
