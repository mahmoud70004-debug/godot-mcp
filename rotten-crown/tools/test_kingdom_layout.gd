extends SceneTree
## Structural validation of the walled kingdom against the baked overworld, the real
## scene colliders and res://data/world/kingdom_map.json (Phase 4a inc 4; first written on
## the Arena branch, commit 941b339). Run from rotten-crown/ after importing:
##   $GODOT --headless --fixed-fps 60 --path . --script res://tools/test_kingdom_layout.gd
## Prints PASS/FAIL lines and LAYOUT_TEST_FAILURES <n> (exit code 0 when n == 0).
## Checks: the layout constants match the map; the perimeter is continuous; a real
## CharacterBody3D walks through the kingdom gate and the citadel gate; the ward pickups,
## enemies and lights keep their places relative to the turned ward; the Outer Ward trigger
## covers the citadel; swept-capsule routes gate -> citadel along the King's Road, gate ->
## Thornfield and gate -> Hollowmere; the plains barriers hold; nothing of the meadow lies
## inside the wall; the Royal Keep cannot be entered.

const WARD_OBJECTS := {
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
}
## Ward lights in the blockout's own frame (lanterns hang 0.52 m out on their arm).
const WARD_LIGHTS := [Vector3(-8.0, 1.0, -18.0), Vector3(17.2, 1.4, -14.2)]
const GRID := Rect2i(-130, 20, 300, 340)

var failures := 0
var scene: Node3D
var terrain: TerrainBuilder
var space: PhysicsDirectSpaceState3D
var capsule: CapsuleShape3D
var query: PhysicsShapeQueryParameters3D
var grid: AStarGrid2D
var ground_rid: RID


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
	var spec := OverworldSpec.make()
	ForestBuilder.fit_terrain(spec)
	terrain = TerrainBuilder.new(spec)
	space = scene.get_world_3d().direct_space_state
	_map_constants()
	_ward_placement()
	_wake_up()
	_check(scene.get_node_or_null("World/KingdomWalls") != null, "Kingdom perimeter is present")
	_check(scene.get_node_or_null("World/KingdomWalls/RoyalKeep") != null, "Royal Keep mass is present")
	_check(scene.get_node_or_null("World/WorldEdge") != null, "World-edge barriers are present")
	_meadow_outside()
	_prepare_queries()
	_ray_test("south wall", Vector2(40, 48), Vector2(40, 68), true)
	_ray_test("east wall", Vector2(228, 200), Vector2(242, 200), true)
	_ray_test("west wall", Vector2(-228, 200), Vector2(-242, 200), true)
	_ray_test("north wall", Vector2(100, 482), Vector2(100, 498), true)
	_ray_test("kingdom gate", Vector2(0, 48), Vector2(0, 68), false)
	_keep_ray()
	_perimeter_test()
	_build_grid(func(_p: Vector2i) -> bool: return true)
	var start := Vector2i(1, 29)
	_route_test("gate -> Thornfield", start, Vector2i(-111, 145))
	_route_test("gate -> Hollowmere", start, Vector2i(24, 343))
	_route_test("gate -> citadel courtyard", start, Vector2i(125, 215))
	# The same, but only on the King's Road (4 m either side of the paving) and the courtyard.
	var line := KingdomRoads.pave_line()
	_build_grid(func(p: Vector2i) -> bool:
		var q := Vector2(p)
		return KingdomRoads._poly_dist(q, line) < 4.0 or OverworldSpec.WARD_RECT.grow(-2.0).has_point(q) \
			or (q.y < 62.0 and absf(q.x) < 3.0))
	_route_test("King's Road: kingdom gate -> citadel courtyard on the road", Vector2i(0, 50), Vector2i(125, 215))
	var player := scene.get_node("Player") as CharacterBody3D
	await _walk(player, "kingdom gate", Vector2(0, 48), Vector2(0, 68), true)
	await _walk(player, "citadel front gate", Vector2(125, 189), Vector2(125, 207), true)
	await _walk(player, "barrier south of the plains", Vector2(1.2, 29), Vector2(1.2, -90), false)
	await _walk(player, "barrier east of the plains", Vector2(1.2, 29), Vector2(140, 29), false)
	await _walk(player, "barrier west of the plains", Vector2(1.2, 29), Vector2(-140, 29), false)
	await _walk(player, "Royal Keep (from the gap behind the ward)", Vector2(125, 254), Vector2(125, 300), false)
	await _walk(player, "Royal Keep (from the courtyard)", Vector2(125, 240), Vector2(125, 300), false)
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


func _v2(a: Variant) -> Vector2:
	var arr: Array = a
	return Vector2(float(arr[0]), float(arr[1]))


func _rect(a: Variant) -> Rect2:
	var arr: Array = a
	return Rect2(float(arr[0]), float(arr[1]), float(arr[2]) - float(arr[0]), float(arr[3]) - float(arr[1]))


## Constants used by the builders against kingdom_map.json (the single source of truth).
func _map_constants() -> void:
	var m := ForestBuilder.map()
	var wall: Dictionary = m["wall"]
	var wmin := _v2(wall["min"])
	var wmax := _v2(wall["max"])
	_check(wmin == OverworldSpec.WALL_MIN and wmax == OverworldSpec.WALL_MAX
		and wmin == Vector2(KingdomWalls.WEST, KingdomWalls.SOUTH) and wmax == Vector2(KingdomWalls.EAST, KingdomWalls.NORTH),
		"wall rect matches the map (%s..%s)" % [wmin, wmax])
	var gate: Dictionary = m["gate"]
	_check(_v2(gate["pos"]) == OverworldSpec.GATE and float(gate["half_width"]) == KingdomWalls.GAP
		and KingdomWalls.GAP == OverworldSpec.GATE_HALF_WIDTH, "gate position and width match the map")
	var c: Dictionary = m["citadel"]
	_check(_rect(c["rect"]) == OverworldSpec.CITADEL_RECT, "citadel rect matches the map")
	_check(_rect(c["ward"]["rect"]) == OverworldSpec.WARD_RECT, "ward rect matches the map")
	_check(_rect(c["keep"]["rect"]) == OverworldSpec.KEEP_RECT, "keep rect matches the map")
	_check(_v2(c["front_gate"]) == OverworldSpec.WARD_GATE, "ward front gate matches the map")
	var kings: Array = []
	for road: Dictionary in m["roads"]:
		if road["id"] == "kings_road":
			for p: Array in road["pts"]:
				kings.append(_v2(p))
	_check(kings == OverworldSpec.KINGS_ROAD, "KINGS_ROAD matches the map road kings_road")
	_check(OverworldSpec.FOREST_PATH == OverworldSpec.KINGS_ROAD, "FOREST_PATH is the King's Road alias")
	var spec := OverworldSpec.make()
	var on_spec := false
	for r in spec.roads:
		on_spec = on_spec or Array(r) == OverworldSpec.KINGS_ROAD
	_check(on_spec, "King's Road is carved and painted as a terrain road")


func _ward_placement() -> void:
	var ward := scene.get_node("World/OuterWard") as Node3D
	var ward_y := terrain.height_at(OverworldSpec.WARD_ORIGIN.x, OverworldSpec.WARD_ORIGIN.y)
	var expect := Vector3(OverworldSpec.WARD_ORIGIN.x, ward_y, OverworldSpec.WARD_ORIGIN.y)
	_check(ward.global_position.distance_to(expect) < 0.01, "Ward origin %s at %s (citadel)" % [ward.global_position, expect])
	_check(ward.global_basis.z.dot(Vector3.FORWARD) > 0.999, "Ward gate faces south, towards the kingdom gate")
	var gate_world := ward.to_global(Vector3(0.0, 0.0, CastleProps.WALL_THICKNESS * 0.5 + 10.0 + 2.0))
	_check(Vector2(gate_world.x, gate_world.z).distance_to(OverworldSpec.WARD_GATE) < 1.5,
		"Ward gate front lands on the map's front gate (%s)" % gate_world)
	for path: String in WARD_OBJECTS:
		var node := scene.get_node(path) as Node3D
		var want := ward.to_global(WARD_OBJECTS[path] as Vector3)
		_check(node.global_position.distance_to(want) < 0.05, "%s keeps its place in the ward (%s)" % [path, node.global_position])
		if path.begins_with("Enemies/"):
			_check(OverworldSpec.WARD_RECT.has_point(Vector2(want.x, want.z)), "%s stands inside the ward rect" % path)
	var lights := (scene.get_node("World/OuterWard") as Node3D).find_children("*", "OmniLight3D", true, false)
	for local: Vector3 in WARD_LIGHTS:
		var want := ward.to_global(local)
		var found := false
		for l in lights:
			found = found or (l as Node3D).global_position.distance_to(want) < 0.3
		_check(found, "ward light at local %s moved with the ward (%s)" % [local, want])
	for l in lights:
		var p := (l as Node3D).global_position
		_check(OverworldSpec.CITADEL_RECT.grow(8.0).has_point(Vector2(p.x, p.z)), "ward light %s is at the citadel" % p)
	var trigger := scene.get_node("RegionTriggers/OuterWard") as Area3D
	var shape := trigger.get_node("CollisionShape3D") as CollisionShape3D
	var box := shape.global_transform * AABB(-(shape.shape as BoxShape3D).size * 0.5, (shape.shape as BoxShape3D).size)
	var r := OverworldSpec.CITADEL_RECT
	var covers := box.position.x <= r.position.x and box.end.x >= r.end.x and box.position.z <= r.position.y and box.end.z >= r.end.y \
		and box.position.y < ward_y - 2.0 and box.end.y > ward_y + 20.0
	_check(covers, "Outer Ward trigger covers the whole citadel rect (%s)" % box)


func _wake_up() -> void:
	var invitation := scene.get_node("Pickups/TornInvitation") as Node3D
	_check(invitation.global_position.distance_to(Vector3(2.4, 0.25, 29.6)) < 0.01, "Wake invitation stays in place")
	var player := scene.get_node("Player") as CharacterBody3D
	_check((-player.global_basis.z).dot(Vector3.BACK) > 0.999, "Player wakes facing the kingdom gate (+Z)")
	var cam := player.get_viewport().get_camera_3d()
	_check(cam != null and (-cam.global_basis.z).dot(Vector3.BACK) > 0.9, "Camera rig (View) looks towards the gate too")
	var star := scene.get_node("Witnesses/StarEyed") as Node3D
	_check(player.global_position.distance_to(star.global_position) < 7.0, "Star witness is near the wake-up")
	_check(bool(star.call("_player_close_and_looking")), "Star witness is visible from the initial view")


## Everything MeadowBuilder made (meshes, lights) lies outside the wall, south of z = 58.
func _meadow_outside() -> void:
	var meadow := scene.get_node_or_null("World/Plains/Meadow") as Node3D
	_check(meadow != null, "Meadow (plains outside the wall) is present")
	if meadow == null:
		return
	var inside: Array[String] = []
	var count := 0
	for node in meadow.find_children("*", "VisualInstance3D", true, false):
		var vi := node as VisualInstance3D
		var box := vi.global_transform * vi.get_aabb()
		count += 1
		if box.end.z > OverworldSpec.WALL_MIN.y - 1.0 or not OverworldSpec.PLAINS_RECT.grow(2.0).has_point(Vector2(box.get_center().x, box.get_center().z)):
			inside.append("%s %s" % [meadow.get_path_to(vi), box])
	_check(count > 10 and inside.is_empty(), "nothing of the meadow inside the wall or beyond the plains (%d pieces; %s)" % [count, inside.slice(0, 5)])


func _prepare_queries() -> void:
	capsule = CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	query = PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = 1
	query.margin = 0.01
	var ground := scene.get_node("World/Terrain/TerrainCollider") as StaticBody3D
	ground_rid = ground.get_rid()
	query.exclude = [ground_rid]


func _ray_test(label: String, a: Vector2, b: Vector2, should_hit: bool) -> void:
	var y := maxf(terrain.height_at(a.x, a.y), terrain.height_at(b.x, b.y)) + 1.2
	var line := PhysicsRayQueryParameters3D.create(Vector3(a.x, y, a.y), Vector3(b.x, y, b.y), 1)
	line.exclude = [ground_rid]
	var hit := space.intersect_ray(line)
	var is_wall := false
	if not hit.is_empty():
		is_wall = "/KingdomWalls/" in str((hit["collider"] as Node).get_path())
	_check(is_wall if should_hit else hit.is_empty(), "%s collision: %s" % [label, hit])


func _keep_ray() -> void:
	var y := terrain.height_at(125.0, 256.0) + 1.2
	var line := PhysicsRayQueryParameters3D.create(Vector3(125.0, y, 254.0), Vector3(125.0, y, 300.0), 1)
	line.exclude = [ground_rid]
	var hit := space.intersect_ray(line)
	var ok := not hit.is_empty() and "KeepCollider" in str((hit["collider"] as Node).get_path())
	_check(ok, "Royal Keep is sealed: a ray from behind the ward hits the keep collider (%s)" % hit.get("position", "nothing"))


func _perimeter_test() -> void:
	# Check the collider just above the ground every 8 m along all four walls.
	var missed: Array[String] = []
	var samples := 0
	for side in ["south", "north", "west", "east"]:
		var values := range(-232, 233, 8) if side in ["south", "north"] else range(64, 489, 8)
		for value in values:
			if side == "south" and absf(float(value)) <= 10.0:
				continue  # the actual, deliberately open gate
			var x := float(value) if side in ["south", "north"] else (KingdomWalls.WEST if side == "west" else KingdomWalls.EAST)
			var z := (KingdomWalls.SOUTH if side == "south" else KingdomWalls.NORTH) if side in ["south", "north"] else float(value)
			var normal := Vector3.FORWARD if side in ["south", "north"] else Vector3.RIGHT
			var middle := Vector3(x, terrain.height_at(x, z) + 0.45, z)
			var line := PhysicsRayQueryParameters3D.create(middle - normal * 4.0, middle + normal * 4.0, 1)
			var ignored: Array[RID] = [ground_rid]
			var found := false
			for attempt in 20:
				line.exclude = ignored
				var hit := space.intersect_ray(line)
				if hit.is_empty():
					break
				if "/KingdomWalls/" in str((hit["collider"] as Node).get_path()):
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


## 1 m grid over GRID: a cell is open when `allowed` says so and the player capsule
## standing there touches nothing on the world layer but the ground.
func _build_grid(allowed: Callable) -> void:
	grid = AStarGrid2D.new()
	grid.region = GRID
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.update()
	var checked := 0
	var blocked := 0
	for z in range(GRID.position.y, GRID.end.y):
		for x in range(GRID.position.x, GRID.end.x):
			var p := Vector2i(x, z)
			if not allowed.call(p):
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


func _route_test(label: String, start: Vector2i, finish: Vector2i) -> void:
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
	_check(valid, "%s reachable with swept player capsule (%d points): %s" % [label, last_path, reason])


## Walks the real player body from a to b. pass_through: it must arrive; otherwise it must
## be stopped before b (a barrier) and still stand on the ground.
func _walk(player: CharacterBody3D, label: String, a: Vector2, b: Vector2, pass_through: bool) -> void:
	player.set_physics_process(false)
	player.set_process(false)
	player.call("teleport_to", Vector3(a.x, terrain.height_at(a.x, a.y) + 0.08, a.y))
	await physics_frame
	var direction := (b - a).normalized()
	var target_distance := a.distance_to(b)
	var speed := float(player.get("walk_speed"))
	var steps := ceili(target_distance / speed * 60.0) + 90
	var stuck := 0
	var last := player.global_position
	for i in steps:
		var velocity_y := player.velocity.y - 9.8 / 60.0
		player.velocity = Vector3(direction.x * speed, maxf(velocity_y, -25.0), direction.y * speed)
		player.move_and_slide()
		await physics_frame
		if Vector2(player.global_position.x - a.x, player.global_position.z - a.y).dot(direction) >= target_distance:
			break
		stuck = stuck + 1 if player.global_position.distance_to(last) < 0.01 else 0
		last = player.global_position
		if not pass_through and stuck > 30:
			break
	var at := player.global_position
	var progress := Vector2(at.x - a.x, at.z - a.y).dot(direction)
	if pass_through:
		_check(progress >= target_distance - 0.5, "%s: a CharacterBody3D walks through (%.2f/%.2f m, now %s)" % [label, progress, target_distance, at])
	else:
		var grounded := at.y > terrain.height_at(at.x, at.z) - 1.0
		_check(progress < target_distance - 2.0 and grounded, "%s: a CharacterBody3D is stopped (%.2f/%.2f m, now %s)" % [label, progress, target_distance, at])
