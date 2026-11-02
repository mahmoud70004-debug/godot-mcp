@tool
class_name OverworldBuilder
extends RefCounted
## Assembles the semi-open kingdom (layout contract C9): terrain, the Outer
## Ward courtyard deeper inside the kingdom, the region builders, signposts and the
## Moonlit Meadows + plains between them (MeadowBuilder: grass, field walls,
## landmarks, far village silhouettes). Used OFFLINE by tools/bake_world.gd; the game loads the
## baked result (src/levels/valdron/baked/overworld_world.scn).

## Region builder classes, looked up by name so a missing one doesn't break the bake.
const REGION_BUILDERS := ["ThornfieldBuilder", "HollowmereBuilder", "WhisperingWoodBuilder"]
## Merged region chunks are culled beyond this distance; fog makes them invisible already.
const REGION_RANGE := 100.0


static func build(root: Node3D) -> TerrainBuilder:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var terrain := TerrainBuilder.new(OverworldSpec.make())
	terrain.build(root)
	var ward := OuterWardBlockout.new()
	ward.name = "OuterWard"
	ward.build_ground = false
	ward.build_horizon = false
	# MeadowBuilder supplies the overworld meadows and grass.
	ward.build_grass = false
	ward.build_meadow = false
	ward.position = terrain.ground(OverworldSpec.WARD_CENTER.x, OverworldSpec.WARD_CENTER.y)
	ward.rotation.y = PI
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
	MeshMerger.merge_static(shared, MeshMerger.cell_for(REGION_RANGE), REGION_RANGE)
	_split_overlit_terrain(root, terrain)
	return terrain


## The relocated ward can make a single 64 m source terrain chunk touch too
## many existing lights. Split only such chunks before the normal terrain merge,
## leaving the rest of the world's draw-call partition and all lights unchanged.
static func _split_overlit_terrain(root: Node3D, terrain: TerrainBuilder) -> void:
	var ground := root.get_node("Terrain") as Node3D
	var lights := root.find_children("*", "OmniLight3D", true, false)
	var splits := 0
	for child in ground.get_children():
		if child is MeshInstance3D:
			splits += _split_terrain_chunk(ground, terrain, child as MeshInstance3D, lights)
	if splits > 0:
		print("terrain light-budget splits: %d" % splits)


static func _split_terrain_chunk(parent: Node3D, terrain: TerrainBuilder, chunk: MeshInstance3D,
		lights: Array) -> int:
	var world_box := chunk.global_transform * chunk.get_aabb()
	var touching := 0
	for item in lights:
		var light := item as OmniLight3D
		var position := light.global_position
		if position.clamp(world_box.position, world_box.end).distance_to(position) < light.omni_range:
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


static func _signposts(parent: Node3D, terrain: TerrainBuilder, rng: RandomNumberGenerator) -> void:
	var posts := [
		[Vector2(3.2, 62.0), ["Whispering Wood", "Hollowmere", "Valdron Gate"]],
		[Vector2(-6.5, 124.0), ["Thornfield", "Hollowmere", "Valdron Gate"]],
		[Vector2(14.0, 302.0), ["Hollowmere", "Whispering Wood"]],
	]
	for p in posts:
		var at: Vector2 = p[0]
		var labels: Array[String] = []
		for l in p[1]:
			labels.append(str(l))
		var post := PropKit.signpost(labels, rng)
		post.position = terrain.ground(at.x, at.y)
		post.rotation.y = rng.randf_range(-0.4, 0.4)
		parent.add_child(post)


static func _find_class(class_id: String) -> Script:
	for c in ProjectSettings.get_global_class_list():
		if c["class"] == class_id:
			return load(c["path"]) as Script
	return null
