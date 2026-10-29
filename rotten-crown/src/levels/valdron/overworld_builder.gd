@tool
class_name OverworldBuilder
extends RefCounted
## Assembles the semi-open kingdom (layout contract C9): terrain, the Outer
## Ward courtyard at the origin, the region builders, signposts and the
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
	# The meadow outside the walls and its grass come from MeadowBuilder.
	ward.build_grass = false
	ward.build_meadow = false
	root.add_child(ward)
	for class_id in REGION_BUILDERS:
		var script := _find_class(class_id)
		if script == null:
			push_warning("OverworldBuilder: %s not available, skipped" % class_id)
			continue
		var region: Node3D = script.call("build", root, terrain, rng)
		if region and region.get_parent() == null:
			root.add_child(region)
		if region:
			MeshMerger.merge_static(region, 20.0, REGION_RANGE)
	var shared := Node3D.new()
	shared.name = "Plains"
	root.add_child(shared)
	_signposts(shared, terrain, rng)
	MeadowBuilder.build(shared, terrain, rng)
	MeshMerger.merge_static(shared, 20.0, REGION_RANGE)
	return terrain


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
