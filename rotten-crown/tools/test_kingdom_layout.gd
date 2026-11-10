extends SceneTree
## Structural validation against the baked overworld and the real scene colliders.
## Run from rotten-crown/ after importing with Godot 4.7.1:
##   godot --headless --fixed-fps 60 --path . --script res://tools/test_kingdom_layout.gd
## A zero exit code and LAYOUT_TEST_FAILURES 0 indicate success. The movement
## probes instantiate CharacterBody3D; other routes use a swept player capsule.

var failures := 0
var scene: Node3D
var terrain: TerrainBuilder
var space: PhysicsDirectSpaceState3D
var capsule: CapsuleShape3D
var query: PhysicsShapeQueryParameters3D
var grid: AStarGrid2D


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	print(("PASS " if ok else "FAIL ") + message)
	if not ok:
		failures += 1


func _run() -> void:
	var packed := load("res://src/levels/valdron/valdron_overworld.tscn") as PackedScene
	scene = packed.instantiate() as Node3D
	root.add_child(scene)
	await physics_frame
	await physics_frame
	terrain = TerrainBuilder.new(OverworldSpec.make())
	space = scene.get_world_3d().direct_space_state
	var ward := scene.get_node("World/OuterWard") as Node3D
	_check(ward.global_position.distance_to(Vector3(0.0, 2.880607, 420.0)) < 0.01, "Ward origin is on its plateau")
	_check(ward.global_basis.z.dot(Vector3.FORWARD) > 0.999, "Ward faces into the kingdom")
	var objects := {
		"Pickups/CooksNote": Vector3(3.2, 1.05, -3.0),
		"Pickups/WellScratching": Vector3(-6.75, 0.6, -18.0),
		"Pickups/FeastWine": Vector3(-3.2, 1.1, -2.4),
		"Pickups/GraveMossHouse": Vector3(-18.5, 0.35, 1.0),
		"Pickups/GraveMossHighTable": Vector3(1.5, 1.05, -11.5),
		"Pickups/WoodsmanAxe": Vector3(15.5, 1.1, -11.7),
		"Pickups/SaintOrsaEye": Vector3(-8.0, 1.1, -16.95),
		"Enemies/FeastGrinner": Vector3(0.0, 0.0, -7.5),
		"Enemies/HouseSteeple": Vector3(-19.6, 0.0, -12.4),
		"Enemies/DoorwayGrinner": Vector3(14.2, 0.0, 0.6),
		"Enemies/WellSteeple": Vector3(-8.0, 0.0, -20.6),
		"RegionTriggers/OuterWard": Vector3(0.0, 2.0, 7.0),
	}
	for path in objects:
		var node := scene.get_node(path) as Node3D
		_check(node.global_position.distance_to(ward.to_global(objects[path])) < 0.05,
			"%s preserves its position relative to the ward" % path)
	var invitation := scene.get_node("Pickups/TornInvitation") as Node3D
	_check(invitation.global_position.distance_to(Vector3(2.4, 0.25, 29.6)) < 0.01,
		"Wake invitation stays in place")
	var player := scene.get_node("Player") as CharacterBody3D
	var star := scene.get_node("Witnesses/StarEyed") as Node3D
	_check(player.global_position.distance_to(star.global_position) < 7.0, "Star witness is near the wake-up")
	_check(bool(star.call("_player_close_and_looking")), "Star witness is visible from the initial view")
	_check(scene.get_node_or_null("World/KingdomWalls") != null, "Kingdom perimeter is present")
	_check(scene.get_node_or_null("World/KingdomWalls/RoyalPalaceWings") != null,
		"Royal palace wings are present")
	_prepare_queries()
	_ray_test("south wall", Vector2(40, 48), Vector2(40, 68), true)
	_ray_test("east wall", Vector2(228, 200), Vector2(242, 200), true)
	_ray_test("west wall", Vector2(-228, 200), Vector2(-242, 200), true)
	_ray_test("north wall", Vector2(100, 482), Vector2(100, 498), true)
	_ray_test("outer gate", Vector2(0, 48), Vector2(0, 68), false)
	_perimeter_test()
	_build_grid()
	var goals := {
		"Thornfield": Vector2i(-111, 145),
		"Whispering Wood": Vector2i(139, 178),
		"Hollowmere": Vector2i(24, 343),
		"Outer Ward and feast": Vector2i(0, 416),
	}
	for name in goals:
		_route_test(name, Vector2i(1, 29), goals[name])
	await _walk_gate(player, "outer gate", Vector2(0, 48), Vector2(0, 68))
	await _walk_gate(player, "inner gate", Vector2(0, 401), Vector2(0, 416))
	print("LAYOUT_TEST_FAILURES ", failures)
	# End the audio playback started by the real scene before the test exits.
	for type in ["AudioStreamPlayer", "AudioStreamPlayer2D", "AudioStreamPlayer3D"]:
		for audio in root.find_children("*", type, true, false):
			audio.call("stop")
			audio.set("stream", null)
	scene.queue_free()
	await process_frame
	scene = null
	terrain = null
	space = null
	capsule = null
	query = null
	grid = null
	packed = null
	# The audio mixer runs on a real-time thread even with a fixed test FPS.
	OS.delay_msec(300)
	await process_frame
	quit(0 if failures == 0 else 1)


func _prepare_queries() -> void:
	capsule = CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	query = PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = 1
	query.margin = 0.01
	var ground := scene.get_node("World/Terrain/TerrainCollider") as StaticBody3D
	query.exclude = [ground.get_rid()]


func _ray_test(name: String, a: Vector2, b: Vector2, should_hit: bool) -> void:
	var y := maxf(terrain.height_at(a.x, a.y), terrain.height_at(b.x, b.y)) + 1.2
	var line := PhysicsRayQueryParameters3D.create(Vector3(a.x, y, a.y), Vector3(b.x, y, b.y), 1)
	var hit := space.intersect_ray(line)
	var is_wall := false
	if not hit.is_empty():
		var collider := hit["collider"] as Node
		is_wall = "/KingdomWalls/" in str(collider.get_path())
	_check(is_wall if should_hit else hit.is_empty(), "%s collision: %s" % [name, hit])


func _perimeter_test() -> void:
	# Check the collider just above the ground every 8 m along all four walls.
	# Ignore the terrain and unrelated props when looking specifically for wall.
	var ground := scene.get_node("World/Terrain/TerrainCollider") as StaticBody3D
	var missed: Array[String] = []
	var samples := 0
	for side in ["south", "north", "west", "east"]:
		var values := range(-232, 233, 8) if side in ["south", "north"] else range(64, 489, 8)
		for value in values:
			if side == "south" and absf(float(value)) <= 10.0:
				continue  # the actual, deliberately open gate
			var x := float(value) if side in ["south", "north"] else (-235.0 if side == "west" else 235.0)
			var z := (58.0 if side == "south" else 490.0) if side in ["south", "north"] else float(value)
			var normal := Vector3.FORWARD if side in ["south", "north"] else Vector3.RIGHT
			var middle := Vector3(x, terrain.height_at(x, z) + 0.45, z)
			var line := PhysicsRayQueryParameters3D.create(middle - normal * 4.0, middle + normal * 4.0, 1)
			var ignored: Array[RID] = [ground.get_rid()]
			var found := false
			for attempt in 20:
				line.exclude = ignored
				var hit := space.intersect_ray(line)
				if hit.is_empty():
					break
				var collider := hit["collider"] as Node
				if "/KingdomWalls/" in str(collider.get_path()):
					found = true
					break
				ignored.append(hit["rid"])
			samples += 1
			if not found:
				missed.append("%s(%s,%s)" % [side, x, z])
	_check(missed.is_empty(), "Perimeter colliders continuous in %d ground-level samples; missing: %s" % [samples, missed])


func _body_query_at(p: Vector2i) -> void:
	query.transform = Transform3D(Basis.IDENTITY, Vector3(float(p.x), terrain.height_at(p.x, p.y) + 1.1, float(p.y)))
	query.motion = Vector3.ZERO


func _build_grid() -> void:
	# One metre samples include the player capsule's full width and height. The
	# selected corridors cover the four destinations without filling the empty
	# corners of the 520 m wide terrain with unnecessary collision tests.
	grid = AStarGrid2D.new()
	grid.region = Rect2i(-150, 28, 316, 390)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.update()
	var checked := 0
	var blocked := 0
	for z in range(28, 418):
		for x in range(-150, 166):
			var inside := (x >= -40 and x <= 45) or (x < -40 and z >= 85 and z <= 175) \
				or (x > 45 and z >= 52 and z <= 250)
			var p := Vector2i(x, z)
			if not inside:
				grid.set_point_solid(p)
				continue
			_body_query_at(p)
			checked += 1
			if not space.intersect_shape(query, 1).is_empty():
				grid.set_point_solid(p)
				blocked += 1
	print("GRID_COLLISION_SAMPLES ", checked, " BLOCKED ", blocked)


func _nearest_free(p: Vector2i) -> Vector2i:
	if not grid.is_point_solid(p):
		return p
	for radius in range(1, 9):
		for z in range(-radius, radius + 1):
			for x in range(-radius, radius + 1):
				var candidate := p + Vector2i(x, z)
				if grid.is_in_boundsv(candidate) and not grid.is_point_solid(candidate):
					return candidate
	return p


func _route_test(name: String, start: Vector2i, finish: Vector2i) -> void:
	start = _nearest_free(start)
	finish = _nearest_free(finish)
	var valid := false
	var last_path := 0
	var reason := ""
	for attempt in 80:
		var path := grid.get_id_path(start, finish)
		last_path = path.size()
		if path.is_empty():
			reason = "no connected route"
			break
		var obstruction := Vector2i(2147483647, 2147483647)
		for i in range(1, path.size()):
			var a: Vector2i = path[i - 1]
			var b: Vector2i = path[i]
			var h0 := terrain.height_at(a.x, a.y)
			var h1 := terrain.height_at(b.x, b.y)
			var horizontal := Vector2(a - b).length()
			_body_query_at(a)
			query.motion = Vector3(float(b.x - a.x), h1 - h0, float(b.y - a.y))
			var motion := space.cast_motion(query)
			if absf(h1 - h0) > horizontal or motion[0] < 0.995:
				obstruction = b
				reason = "sweep or slope at %s (fraction %.3f, height %.3f)" % [b, motion[0], h1 - h0]
				break
		if obstruction.x == 2147483647:
			valid = true
			reason = "clear after %d refinement(s)" % attempt
			break
		if obstruction == finish or obstruction == start:
			break
		grid.set_point_solid(obstruction)
	_check(valid, "%s reachable with swept player capsule (%d points): %s" % [name, last_path, reason])


func _walk_gate(player: CharacterBody3D, name: String, a: Vector2, b: Vector2) -> void:
	player.set_physics_process(false)
	player.set_process(false)
	player.call("teleport_to", Vector3(a.x, terrain.height_at(a.x, a.y) + 0.08, a.y))
	await physics_frame
	var direction := (b - a).normalized()
	var target_distance := a.distance_to(b)
	var speed := float(player.get("walk_speed"))
	var steps := ceili(target_distance / speed * 60.0) + 90
	var previous := player.global_position
	for i in steps:
		var velocity_y := player.velocity.y - 9.8 / 60.0
		player.velocity = Vector3(direction.x * speed, maxf(velocity_y, -25.0), direction.y * speed)
		player.move_and_slide()
		await physics_frame
		if Vector2(player.global_position.x - a.x, player.global_position.z - a.y).dot(direction) >= target_distance:
			break
	var progress := Vector2(player.global_position.x - a.x, player.global_position.z - a.y).dot(direction)
	_check(progress >= target_distance - 0.5,
		"%s: actual CharacterBody3D walks through (%.2f/%.2f m; from %s to %s)" % [name, progress, target_distance, previous, player.global_position])
