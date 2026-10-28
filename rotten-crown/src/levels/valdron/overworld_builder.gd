@tool
class_name OverworldBuilder
extends RefCounted
## Assembles the semi-open kingdom (layout contract C9): terrain, the Outer
## Ward courtyard at the origin, the region builders, signposts and the plains
## grass between them. Used OFFLINE by tools/bake_world.gd; the game loads the
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
	_plains_grass(shared, terrain, rng)
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


## Sparse field grass on the open plains between the regions.
static func _plains_grass(parent: Node3D, terrain: TerrainBuilder, rng: RandomNumberGenerator) -> void:
	var field := load("res://assets/materials/grass_field.tres") as Material
	var accept := func(p: Vector2) -> bool:
		if p.distance_to(terrain.spec.flat_center) < terrain.spec.flat_radius + 10.0:
			return false  # the meadow has its own grass
		var i := terrain.cols * int((p.y - terrain.spec.min_corner.y) / terrain.spec.cell) + int((p.x - terrain.spec.min_corner.x) / terrain.spec.cell)
		var c: Color = terrain.paint[clampi(i, 0, terrain.paint.size() - 1)]
		return c.r < 0.3 and c.g < 0.5 and c.b < 0.5
	GrassScatter.scatter(parent, terrain, Rect2(-70.0, 60.0, 140.0, 180.0), 2600, field, Vector2(0.75, 0.5), rng, accept)


static func _find_class(class_id: String) -> Script:
	for c in ProjectSettings.get_global_class_list():
		if c["class"] == class_id:
			return load(c["path"]) as Script
	return null
