@tool
class_name KingdomWalls
extends RefCounted
## The kingdom's outer wall (data/world/kingdom_map.json "wall" and "gate"; from the
## Arena branch, commit 941b339): a curtain wall round the rect with corner and interval
## towers and the great gatehouse at the south gate, plus the Royal Keep's mass behind
## the Outer Ward (map "citadel.keep"). Structural scenery: existing castle materials and
## no lights. tools/test_kingdom_layout.gd checks the constants against the map.
##
## Cost (web / Compatibility): every merged (material, cell) is a draw call, so a run is
## a few long boxes (body, mossy foot, wall walk, parapet), crenellated with real merlons
## only on the south front near the gate (what the wake-up sees); the rest of the
## perimeter keeps a plain parapet profile. Merged in WALL_CELL squares, culled at
## WALL_RANGE (the region fogs hide the wall long before).

const WEST := -235.0
const EAST := 235.0
const SOUTH := 58.0
const NORTH := 490.0
const GAP := 8.0
const WALL_HEIGHT := 10.5
const THICKNESS := 3.2
const SEGMENT_LENGTH := 30.0
## Real merlons only on the south front within this distance of the gate.
const MERLON_REACH := 70.0
const WALL_CELL := 120.0
const WALL_RANGE := 150.0
## Interval towers along the east and west runs (map: z = 160, 270, 380).
const TOWER_Z := [160.0, 270.0, 380.0]


static func build(root: Node3D, terrain: TerrainBuilder) -> Node3D:
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
	for z: float in TOWER_Z:
		for x in [WEST, EAST]:
			_tower(walls, terrain.ground(x, z), 6.2, 19.0, stone, moss, true)
	_gatehouse(walls, terrain)
	_royal_keep(walls, terrain, stone, moss)
	# The colliders stay on the hidden originals; the stonework merges for the renderer.
	MeshMerger.merge_static(walls, WALL_CELL, WALL_RANGE)
	return walls


## Lowest and highest ground along a-b (2 m steps), so no dip opens a gap under the wall.
static func _ground_span(terrain: TerrainBuilder, a: Vector2, b: Vector2) -> Vector2:
	var lo := INF
	var hi := -INF
	var n := maxi(1, ceili(a.distance_to(b) / 2.0))
	for i in n + 1:
		var p := a.lerp(b, float(i) / n)
		var h := terrain.height_at(p.x, p.y)
		lo = minf(lo, h)
		hi = maxf(hi, h)
	return Vector2(lo, hi)


static func _wall_run(parent: Node3D, terrain: TerrainBuilder, a: Vector2, b: Vector2,
		stone: Material, moss: Material) -> void:
	var count := ceili(a.distance_to(b) / SEGMENT_LENGTH)
	for i in count:
		var p := a.lerp(b, float(i) / count)
		var q := a.lerp(b, float(i + 1) / count)
		var middle := (p + q) * 0.5
		var span := _ground_span(terrain, p, q)
		var base := span.x - 1.2
		var height := span.y - base + WALL_HEIGHT
		var group := Node3D.new()
		group.position = Vector3(middle.x, base, middle.y)
		group.rotation.y = atan2(-(q - p).y, (q - p).x)
		parent.add_child(group)
		var length := p.distance_to(q) + 0.3
		_box(group, Vector3(length, height, THICKNESS), Vector3(0.0, height * 0.5, 0.0), stone, true)
		# Mossy foot following the ground, the wall walk and a parapet on top.
		_box(group, Vector3(length, span.y - base + 1.4, THICKNESS + 0.6), Vector3(0.0, (span.y - base + 1.4) * 0.5, 0.0), moss)
		_box(group, Vector3(length, 0.6, THICKNESS + 0.6), Vector3(0.0, height, 0.0), stone)
		var near_gate := is_equal_approx(p.y, SOUTH) and is_equal_approx(q.y, SOUTH) \
			and minf(absf(p.x), absf(q.x)) < MERLON_REACH
		if not near_gate:
			_box(group, Vector3(length, 1.1, 0.9), Vector3(0.0, height + 0.85, -(THICKNESS + 0.6) * 0.5 + 0.45), stone)
			continue
		var merlons := maxi(1, floori(length / 4.3))
		for j in merlons:
			var x := -length * 0.5 + length * (float(j) + 0.5) / merlons
			_box(group, Vector3(2.1, 1.6, THICKNESS + 0.6), Vector3(x, height + 1.1, 0.0), stone)


static func _tower(parent: Node3D, base: Vector3, width: float, height: float,
		stone: Material, moss: Material, collide: bool) -> void:
	var tower := Node3D.new()
	tower.position = base - Vector3(0.0, 1.5, 0.0)
	parent.add_child(tower)
	_box(tower, Vector3(width, height + 1.5, width), Vector3(0.0, (height + 1.5) * 0.5, 0.0), stone, collide)
	_box(tower, Vector3(width + 0.7, 2.4, width + 0.7), Vector3(0.0, 1.5, 0.0), moss)
	_box(tower, Vector3(width + 0.8, 1.0, width + 0.8), Vector3(0.0, height + 1.7, 0.0), stone)
	for side in [-1.0, 1.0]:
		for k in 2:
			var along := (float(k) - 0.5) * width * 0.55
			_box(tower, Vector3(1.4, 1.2, 0.8), Vector3(along, height + 2.8, side * width * 0.5), stone)
			_box(tower, Vector3(0.8, 1.2, 1.4), Vector3(side * width * 0.5, height + 2.8, along), stone)
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
	# remains open; its feast-spill light belongs to the ward, not to this gate.
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


## The Royal Keep's bulk behind the Outer Ward (the ward's own keep silhouette stands at its
## front, z ~ 264): a great hall block, rear towers and wings out to the keep rect, all on
## one collider so nobody walks in (the keep is sealed). One green window burns high up.
static func _royal_keep(parent: Node3D, terrain: TerrainBuilder, stone: Material, moss: Material) -> void:
	var rect := OverworldSpec.KEEP_RECT
	var c := rect.get_center()
	var y := terrain.height_at(c.x, rect.position.y)
	var keep := Node3D.new()
	keep.name = "RoyalKeep"
	keep.position = Vector3(c.x, y, c.y)
	parent.add_child(keep)
	var lo := INF
	for p in [rect.position, rect.end, Vector2(rect.position.x, rect.end.y), Vector2(rect.end.x, rect.position.y), c]:
		lo = minf(lo, terrain.height_at(p.x, p.y))
	var sink := y - lo + 2.0
	# Main hall and the two wings stepping down to the sides.
	_box(keep, Vector3(34.0, 26.0 + sink, 26.0), Vector3(0.0, 13.0 - sink * 0.5, 6.0), stone)
	_box(keep, Vector3(36.0, 2.4 + sink, 28.0), Vector3(0.0, 1.2 - sink * 0.5, 6.0), moss)
	for side in [-1.0, 1.0]:
		_box(keep, Vector3(13.0, 16.0 + sink, 36.0), Vector3(side * 23.5, 8.0 - sink * 0.5, 4.0), stone)
		_box(keep, Vector3(14.0, 2.4 + sink, 37.0), Vector3(side * 23.5, 1.2 - sink * 0.5, 4.0), moss)
		_tower(keep, Vector3(side * 17.0, -sink, 19.0), 8.0, 33.0, stone, moss, false)
		_tower(keep, Vector3(side * 27.0, -sink, -12.0), 6.0, 22.0, stone, moss, false)
	var roof := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(34.0, 9.0, 26.0)
	roof.mesh = prism
	roof.material_override = RetroMaterials.roof()
	roof.position = Vector3(0.0, 30.5, 6.0)
	keep.add_child(roof)
	var glow := RetroMaterials.flat(CastleProps.CURSED_LIGHT, 6.0)
	_box(keep, Vector3(1.0, 1.8, 0.3), Vector3(-6.0, 21.0, -7.1), glow)
	_box(keep, Vector3(0.8, 1.4, 0.3), Vector3(17.0, 27.5, 14.9), glow)
	# One collider for the whole keep rect (from just behind the ward's keep front).
	var body := StaticBody3D.new()
	body.name = "KeepCollider"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(rect.size.x, 34.0, rect.size.y + 4.0)
	shape.shape = box
	shape.position = Vector3(0.0, 17.0 - sink, -2.0)
	body.add_child(shape)
	keep.add_child(body)


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
