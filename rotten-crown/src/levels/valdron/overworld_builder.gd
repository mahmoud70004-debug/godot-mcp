@tool
class_name OverworldBuilder
extends RefCounted
## Assembles the walled kingdom (data/world/kingdom_map.json; layout contract C9):
## terrain, the kingdom wall and gate (KingdomWalls), the Outer Ward courtyard at the
## citadel (turned to face the kingdom gate), the region builders, signposts, the roads
## (KingdomRoads: the paved King's Road gate -> citadel, the pumpkin road), the empty
## plains outside the wall where the knight wakes (MeadowBuilder), invisible barriers
## round those plains, and the forest that fills the kingdom inside the walls
## (ForestBuilder). Used OFFLINE by tools/bake_world.gd; the game loads the baked result
## (src/levels/valdron/baked/overworld_world.scn).

## Region builder classes, looked up by name so a missing one doesn't break the bake.
## (The Whispering Wood pocket is gone: the kingdom forest replaces it, Phase 4a inc 3.)
const REGION_BUILDERS := ["ThornfieldBuilder", "HollowmereBuilder"]
## Merged region chunks are culled beyond this distance; fog makes them invisible already.
const REGION_RANGE := 100.0
## Invisible world-edge barriers round the plains: thickness and height.
const EDGE_THICKNESS := 2.0
const EDGE_HEIGHT := 60.0


static func build(root: Node3D) -> TerrainBuilder:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var spec := OverworldSpec.make()
	ForestBuilder.fit_terrain(spec)
	var terrain := TerrainBuilder.new(spec)
	# The ground meshes get the forest floor and trails; the other builders keep reading
	# the paint they were made for, so their layouts (and random streams) stay as they were.
	var builder_paint := terrain.paint.duplicate()
	ForestBuilder.paint_ground(terrain)
	KingdomRoads.paint(terrain)
	terrain.build(root)
	var ground_paint := terrain.paint
	terrain.paint = builder_paint
	var ward_y := terrain.height_at(OverworldSpec.WARD_ORIGIN.x, OverworldSpec.WARD_ORIGIN.y)
	var ward := OuterWardBlockout.new()
	ward.name = "OuterWard"
	ward.build_ground = false
	ward.build_horizon = false
	# The plains, their grass and the knight's lantern come from MeadowBuilder.
	ward.build_grass = false
	ward.build_meadow = false
	ward.build_dropped_lantern = false
	ward.position = Vector3(OverworldSpec.WARD_ORIGIN.x, ward_y, OverworldSpec.WARD_ORIGIN.y)
	ward.rotation.y = OverworldSpec.WARD_YAW
	root.add_child(ward)
	KingdomWalls.build(root, terrain)
	for class_id in REGION_BUILDERS:
		var script := _find_class(class_id)
		if script == null:
			push_warning("OverworldBuilder: %s not available, skipped" % class_id)
			continue
		var region: Node3D = script.call("build", root, terrain, rng)
		if region and region.get_parent() == null:
			root.add_child(region)
		if region:
			MeshMerger.merge_static(region, MeshMerger.cell_for(REGION_RANGE), REGION_RANGE)
	var shared := Node3D.new()
	shared.name = "Plains"
	root.add_child(shared)
	_signposts(shared, terrain, rng)
	MeadowBuilder.build(shared, terrain, rng)
	KingdomRoads.build(shared, terrain)
	_ward_grass(root, ward_y)
	_world_edge(root, terrain)
	# After everything solid is placed (the forest keeps clear of it), before the last merge.
	ForestBuilder.build(root, terrain, rng)
	MeshMerger.merge_static(shared, MeshMerger.cell_for(REGION_RANGE), REGION_RANGE)
	terrain.paint = ground_paint
	_split_overlit_terrain(root, terrain)
	return terrain


## Signposts: [position, viewer to face, [label, direction to point]...]. None points to the
## old "Valdron Gate"; the one inside the kingdom gate sends the King's Road to the citadel.
static func _signposts(parent: Node3D, terrain: TerrainBuilder, rng: RandomNumberGenerator) -> void:
	var posts := [
		[Vector2(-4.2, 67.0), Vector2(0.0, 58.0), [["The Citadel", Vector2(45.0, 72.0)], ["Hollowmere", Vector2(-10.0, 120.0)],
			["Thornfield", Vector2(-60.0, 136.0)]]],
		[Vector2(-6.5, 124.0), Vector2(-10.0, 110.0), [["Thornfield", Vector2(-60.0, 136.0)], ["Hollowmere", Vector2(5.0, 200.0)],
			["Kingdom Gate", Vector2(0.0, 60.0)]]],
		[Vector2(14.0, 302.0), Vector2(10.0, 285.0), [["Hollowmere", Vector2(20.0, 322.0)], ["The Citadel", Vector2(82.0, 305.0)]]],
	]
	for p in posts:
		var at: Vector2 = p[0]
		var viewer: Vector2 = p[1]
		var labels: Array[String] = []
		var targets: Array[Vector2] = []
		for entry: Array in p[2]:
			labels.append(str(entry[0]))
			targets.append(entry[1] as Vector2)
		var post := PropKit.signpost(labels, rng)
		post.position = terrain.ground(at.x, at.y)
		_aim_signpost(post, at, viewer, targets)
		parent.add_child(post)


## Turns each board of a PropKit signpost so its arrow points at its target, and puts the
## lettering on the face turned towards `viewer` (the boards alternate sides).
static func _aim_signpost(post: Node3D, at: Vector2, viewer: Vector2, targets: Array[Vector2]) -> void:
	post.rotation.y = 0.0
	var to_viewer := (viewer - at).normalized()
	for i in targets.size():
		var board := post.get_node_or_null("Board%d" % i) as Node3D
		if board == null:
			continue
		var d := (targets[i] - at).normalized()
		# Board i's arrow is on local +X for even i, -X for odd i (PropKit.signpost).
		var arm := d if i % 2 == 0 else -d
		board.rotation.y = atan2(-arm.y, arm.x)
		# Local +Z of the board in world (x, z): (sin yaw, cos yaw).
		var face := Vector2(sin(board.rotation.y), cos(board.rotation.y))
		if face.dot(to_viewer) < 0.0:
			for child in board.get_children():
				if child is Label3D:
					var label := child as Label3D
					label.position.z = -label.position.z
					label.rotation.y = PI


## Sparse short grass in the courtyard between the cobbles and the walls (in the ward's
## own frame, as it was when the ward stood at the origin), own random stream.
static func _ward_grass(root: Node3D, ward_y: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150
	var tufts: Array = []
	var tries := 0
	while tufts.size() < 520 and tries < 4000:
		tries += 1
		var p := Vector2(rng.randf_range(-38.0, 38.0), rng.randf_range(-38.0, 8.0))
		if absf(p.x) < 9.0 and p.y > -22.0:
			continue  # trampled feast grounds
		var at := OverworldSpec.ward_to_world(Vector3(p.x, -0.03, p.y), ward_y)
		tufts.append([at, rng.randf() * TAU, rng.randf_range(0.5, 0.8), rng.randf_range(0.2, 0.42), rng.randf_range(0.25, 0.5),
			MeadowProps.KIND_WEED if rng.randf() < 0.2 else MeadowProps.KIND_GRASS])
	var group := Node3D.new()
	group.name = "WardGrass"
	root.add_child(group)
	MeadowProps.grass_chunks(group, tufts, MeadowBuilder.GRASS_RANGE)


## Invisible colliders (layer 1) round the walkable plains outside the wall; they meet the
## wall's south run, so the kingdom gate is the only way on. Nothing is drawn: the plain
## thins out and the fog closes before the line.
static func _world_edge(root: Node3D, terrain: TerrainBuilder) -> void:
	var r := OverworldSpec.PLAINS_RECT
	var body := StaticBody3D.new()
	body.name = "WorldEdge"
	root.add_child(body)
	var t := EDGE_THICKNESS
	var north := KingdomWalls.SOUTH + KingdomWalls.THICKNESS
	var boxes := [
		[Vector3(r.position.x - t * 0.5, 0.0, (r.position.y + north) * 0.5), Vector3(t, EDGE_HEIGHT, north - r.position.y + t * 2.0)],
		[Vector3(r.end.x + t * 0.5, 0.0, (r.position.y + north) * 0.5), Vector3(t, EDGE_HEIGHT, north - r.position.y + t * 2.0)],
		[Vector3(r.get_center().x, 0.0, r.position.y - t * 0.5), Vector3(r.size.x + t * 4.0, EDGE_HEIGHT, t)],
	]
	for b: Array in boxes:
		var at: Vector3 = b[0]
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = b[1]
		shape.shape = box
		shape.position = Vector3(at.x, terrain.height_at(at.x, at.z), at.z)
		body.add_child(shape)


## Lights near the citadel can make one 64 m source terrain chunk touch more than the
## light budget (from the Arena branch). Split only such chunks, before the bake's normal
## terrain merge, leaving the rest of the ground partition unchanged.
static func _split_overlit_terrain(root: Node3D, terrain: TerrainBuilder) -> void:
	var ground := root.get_node("Terrain") as Node3D
	var lights := root.find_children("*", "OmniLight3D", true, false)
	var splits := 0
	for child in ground.get_children():
		if child is MeshInstance3D:
			splits += _split_terrain_chunk(ground, terrain, child as MeshInstance3D, lights)
	if splits > 0:
		print("terrain light-budget splits: %d" % splits)


static func _split_terrain_chunk(parent: Node3D, terrain: TerrainBuilder, chunk: MeshInstance3D, lights: Array) -> int:
	var world_box := chunk.global_transform * chunk.get_aabb()
	var touching := 0
	for item in lights:
		var light := item as OmniLight3D
		var at := light.global_position
		if at.clamp(world_box.position, world_box.end).distance_to(at) < light.omni_range:
			touching += 1
	if touching <= MeshMerger.LIGHT_BUDGET:
		return 0
	var bounds := chunk.get_aabb()
	var cell := terrain.spec.cell
	var minimum := terrain.spec.min_corner
	var x0 := roundi((bounds.position.x - minimum.x) / cell)
	var x1 := roundi((bounds.end.x - minimum.x) / cell)
	var z0 := roundi((bounds.position.z - minimum.y) / cell)
	var z1 := roundi((bounds.end.z - minimum.y) / cell)
	if x1 - x0 < 2 or z1 - z0 < 2:
		push_warning("Terrain chunk still touches %d lights after subdivision" % touching)
		return 0
	var xs := [x0, floori((x0 + x1) * 0.5), x1]
	var zs := [z0, floori((z0 + z1) * 0.5), z1]
	var splits := 1
	parent.remove_child(chunk)
	for ix in 2:
		for iz in 2:
			var part := MeshInstance3D.new()
			part.name = "Chunk_%d_%d" % [xs[ix], zs[iz]]
			part.mesh = terrain._chunk_mesh(xs[ix], zs[iz], xs[ix + 1], zs[iz + 1])
			part.material_override = chunk.material_override
			part.cast_shadow = chunk.cast_shadow
			part.visibility_range_end = chunk.visibility_range_end
			parent.add_child(part)
			splits += _split_terrain_chunk(parent, terrain, part, lights)
	chunk.free()
	return splits


static func _find_class(class_id: String) -> Script:
	for c in ProjectSettings.get_global_class_list():
		if c["class"] == class_id:
			return load(c["path"]) as Script
	return null
