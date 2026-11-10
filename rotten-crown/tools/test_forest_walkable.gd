extends SceneTree
## Checks the baked kingdom forest (ForestBuilder, ForestFloor) is walkable and matches
## the map.
##   $GODOT --headless --path . --script tools/test_forest_walkable.gd
## Reads the trees and the floor back from the baked overworld scene (MultiMesh buffers:
## instance transforms read through get_instance_transform() are identity under
## --headless), the trunk colliders and the floor obstacles (logs, boulders, stumps).
## Prints PASS/FAIL lines and FOREST_TEST_FAILURES <n>.
## (-s mode: no autoloads; only ForestBuilder / WoodProps statics are used.)

const SCENE := "res://src/levels/valdron/baked/overworld_world.scn"
const CAPSULE := 0.4
## Allowed deviation of the tree count per tier from area x density.
const COUNT_TOLERANCE := 0.15

var _failures := 0


func _initialize() -> void:
	var packed := load(SCENE) as PackedScene
	if packed == null:
		_check(false, "baked scene loads")
		_finish()
		return
	var root := packed.instantiate() as Node3D
	var forest := root.get_node_or_null("Forest") as Node3D
	_check(forest != null, "Forest node in the baked world")
	if forest == null:
		_finish()
		return
	var trees := _trees(forest)
	var trunks := _trunks(forest)
	var obstacles := _obstacles(forest)
	_check(trees.size() > 500, "trees read from the MultiMesh buffers (%d)" % trees.size())
	_check(trunks.size() == trees.size(), "one trunk collider per tree (%d colliders, %d trees)" % [trunks.size(), trees.size()])
	_check_floor(forest)
	_check_markers(forest)
	_check_roads(trees, trunks)
	_check_spacing(trees, trunks)
	_check_obstacles(trunks, obstacles)
	_check_tiers(trees)
	root.free()
	_finish()


func _finish() -> void:
	print("FOREST_TEST_FAILURES %d" % _failures)
	quit(1 if _failures > 0 else 0)


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_failures += 1


## [Vector2 foot, style index] per tree, from the Near_<style> copies in the N_ cells;
## also checks every buffer holds real (non-zero) transforms and that the impostor cells
## (F_) hold one card per tree.
func _trees(forest: Node3D) -> Array:
	var out: Array = []
	var zero := 0
	var cards := 0
	for cell in forest.get_node("Trees").get_children():
		var c := cell as Node3D
		if String(c.name).begins_with("F_"):
			var far := c.get_node_or_null("Far") as MultiMeshInstance3D
			if far:
				cards += far.multimesh.instance_count
				zero += _empty_instances(far.multimesh)
			continue
		for k in ForestBuilder.STYLE_NAMES.size():
			var near := c.get_node_or_null("Near_" + ForestBuilder.STYLE_NAMES[k]) as MultiMeshInstance3D
			if near == null:
				continue
			var mm := near.multimesh
			zero += _empty_instances(mm)
			var stride := _stride(mm)
			var buf := mm.buffer
			for i in mm.instance_count:
				var o := i * stride
				out.append([Vector2(c.position.x + buf[o + 3], c.position.z + buf[o + 11]), k])
	_check(zero == 0, "tree MultiMesh buffers hold real transforms (%d empty instances)" % zero)
	_check(cards == out.size(), "one impostor card per tree (%d cards, %d trees)" % [cards, out.size()])
	return out


func _stride(mm: MultiMesh) -> int:
	return 12 + (4 if mm.use_colors else 0) + (4 if mm.use_custom_data else 0)


func _empty_instances(mm: MultiMesh) -> int:
	var stride := _stride(mm)
	var buf := mm.buffer
	var n := 0
	if buf.size() < mm.instance_count * stride:
		return mm.instance_count
	for i in mm.instance_count:
		var o := i * stride
		if absf(buf[o]) + absf(buf[o + 1]) + absf(buf[o + 2]) + absf(buf[o + 5]) + absf(buf[o + 10]) < 0.001:
			n += 1
	return n


## [Vector2 centre, radius] of every trunk cylinder.
func _trunks(forest: Node3D) -> Array:
	var out: Array = []
	for chunk in forest.get_node("Trees").get_children():
		if not String(chunk.name).begins_with("N_"):
			continue
		var body := (chunk as Node3D).get_node_or_null("Trunks") as StaticBody3D
		if body == null:
			continue
		_check_layer(body)
		for cs in body.get_children():
			var shape := (cs as CollisionShape3D).shape as CylinderShape3D
			var p := (chunk as Node3D).position + (cs as Node3D).position
			out.append([Vector2(p.x, p.z), shape.radius])
	return out


var _layer_checked := false


func _check_layer(body: StaticBody3D) -> void:
	if _layer_checked:
		return
	_layer_checked = true
	_check(body.collision_layer & 1 == 1, "trunk colliders are on the world layer (1)")


func _check_markers(forest: Node3D) -> void:
	var markers := forest.get_node_or_null("Markers")
	var names: Array[String] = []
	if markers:
		for m in markers.get_children():
			names.append(String(m.name))
	var want: Array[String] = ["Lore_1", "Trigger"]
	for i in range(1, 12):
		want.append("Spawn_Enemy_%d" % i)
	for i in range(1, 7):
		want.append("Pickup_%d" % i)
	for zone: Dictionary in ForestBuilder.map()["deep_zones"]:
		want.append("Trigger_" + str(zone["id"]))
	var missing := want.filter(func(n: String) -> bool: return not names.has(n))
	_check(missing.is_empty(), "markers: %d spawns, 6 pickups, lore, Kingswood + deep zone triggers (missing %s)" % [11, missing])
	var trigger := markers.get_node_or_null("Trigger") if markers else null
	var box: Vector3 = trigger.get_meta("box", Vector3.ZERO) if trigger else Vector3.ZERO
	var wr := ForestBuilder.wall_rect()
	_check(box.x >= wr.size.x and box.z >= wr.size.y, "Kingswood trigger box covers the interior (%s)" % box)
	var bad_regions := 0
	var wall_ok := true
	for m in (markers.get_children() if markers else []):
		var n := String(m.name)
		if not n.begins_with("Trigger"):
			continue
		var path: String = m.get_meta("region", "")
		var region := load(path) as RegionData if ResourceLoader.exists(path) else null
		if region == null:
			bad_regions += 1
		if n != "Trigger":
			var b: Vector3 = m.get_meta("box", Vector3.ZERO)
			var p := (m as Node3D).position
			wall_ok = wall_ok and wr.has_point(Vector2(p.x, p.z) - Vector2(b.x, b.z) * 0.5) and wr.has_point(Vector2(p.x, p.z) + Vector2(b.x, b.z) * 0.49)
	_check(bad_regions == 0, "every trigger names a region file that loads (%d bad)" % bad_regions)
	_check(wall_ok, "deep zone trigger boxes stay inside the wall")
	var spot_bad := 0
	for m in (markers.get_children() if markers else []):
		var p := (m as Node3D).position
		if String(m.name).begins_with("Spawn") or String(m.name).begins_with("Pickup"):
			if ForestBuilder.tier_at(p.x, p.z) < 0:
				spot_bad += 1
	_check(spot_bad == 0, "spawn and pickup markers lie inside the wall (%d outside)" % spot_bad)


## Floor: cells with real instances (non-zero buffers), every kit family present.
func _check_floor(forest: Node3D) -> void:
	var floor_node := forest.get_node_or_null("Floor")
	_check(floor_node != null, "Floor node in the baked forest")
	if floor_node == null:
		return
	var counts := {"Cards": 0, "Small": 0, "Large": 0}
	var zero := 0
	for cell in floor_node.get_children():
		for fam: String in counts:
			var mmi := (cell as Node3D).get_node_or_null(fam) as MultiMeshInstance3D
			if mmi:
				counts[fam] = int(counts[fam]) + mmi.multimesh.instance_count
				zero += _empty_instances(mmi.multimesh)
	_check(zero == 0, "floor MultiMesh buffers hold real transforms (%d empty instances)" % zero)
	_check(int(counts["Cards"]) > 5000 and int(counts["Small"]) > 500 and int(counts["Large"]) > 100,
		"floor kits scattered (cards %d, small kits %d, large kits %d)" % [counts["Cards"], counts["Small"], counts["Large"]])


## Roads (map roads + the painted old forest path): every trunk centre keeps
## ROAD_CLEAR m from every centreline, and a 0.4 m capsule walked along each
## centreline in 1 m steps touches no trunk collider.
func _check_roads(trees: Array, trunks: Array) -> void:
	var worst := INF
	for t: Array in trees:
		worst = minf(worst, ForestBuilder.road_distance(t[0]))
	_check(worst >= ForestBuilder.ROAD_CLEAR, "trunks keep >= %.1f m from road centrelines (closest %.2f m)" % [ForestBuilder.ROAD_CLEAR, worst])
	var hash := _hash(trunks)
	var lines: Array = []
	for road: Dictionary in ForestBuilder.map()["roads"]:
		lines.append(road["pts"])
	for pts: Array in ForestBuilder.EXTRA_ROADS:
		lines.append(pts)
	var hits := 0
	var samples := 0
	for pts: Array in lines:
		for k in pts.size() - 1:
			var a := ForestBuilder._v2(pts[k])
			var b := ForestBuilder._v2(pts[k + 1])
			var n := maxi(1, int(a.distance_to(b)))
			for i in n + 1:
				var p := a.lerp(b, float(i) / n)
				samples += 1
				for idx: int in _near(hash, p):
					var tr: Array = trunks[idx]
					if p.distance_to(tr[0]) < float(tr[1]) + CAPSULE:
						hits += 1
	_check(hits == 0, "roads walkable: 0.4 m capsule swept along all roads hits no trunk (%d samples, %d hits)" % [samples, hits])


## Tree feet at least SPACING apart (SPACING_DEEP when one of the two stands in T3) and
## always a gap the 0.8 m wide player fits through between the trunk colliders.
func _check_spacing(trees: Array, trunks: Array) -> void:
	var fhash := _hash(trees)
	var closest := INF
	var bad := 0
	for i in trees.size():
		var a: Vector2 = trees[i][0]
		var ta := ForestBuilder.tier_at(a.x, a.y)
		for j: int in _near(fhash, a):
			if j <= i:
				continue
			var b: Vector2 = trees[j][0]
			var d := a.distance_to(b)
			var need := ForestBuilder.SPACING_DEEP if ta == 3 or ForestBuilder.tier_at(b.x, b.y) == 3 else ForestBuilder.SPACING
			closest = minf(closest, d)
			if d < need:
				bad += 1
	_check(bad == 0, "min spacing holds: feet >= 2.4 m apart (2.0 m in T3) (closest %.2f m, %d violations)" % [closest, bad])
	var hash := _hash(trunks)
	var worst_gap := INF
	var tight := 0
	for i in trunks.size():
		var a: Array = trunks[i]
		for j: int in _near(hash, a[0]):
			if j <= i:
				continue
			var b: Array = trunks[j]
			var gap := (a[0] as Vector2).distance_to(b[0]) - float(a[1]) - float(b[1])
			worst_gap = minf(worst_gap, gap)
			if gap < CAPSULE * 2.0:
				tight += 1
	_check(tight == 0, "player fits between every two trunks: collider gap >= 0.8 m (smallest %.2f m, %d too tight)" % [worst_gap, tight])


## Footprint circles [Vector2 centre, radius, obstacle id] of every floor obstacle: a
## log box gives circles along its length, a sphere or upright cylinder one circle.
func _obstacles(forest: Node3D) -> Array:
	var out: Array = []
	var floor_node := forest.get_node_or_null("Floor")
	if floor_node == null:
		return out
	for cell in floor_node.get_children():
		var body := (cell as Node3D).get_node_or_null("Obstacles") as StaticBody3D
		if body == null:
			continue
		_check_layer(body)
		for child in body.get_children():
			var id := out.size()
			var cs := child as CollisionShape3D
			var xf := (cell as Node3D).transform * cs.transform
			var c := Vector2(xf.origin.x, xf.origin.z)
			if cs.shape is BoxShape3D:
				var size := (cs.shape as BoxShape3D).size
				var axis := Vector2(xf.basis.x.x, xf.basis.x.z).normalized()
				var r := size.z * 0.5
				var n := maxi(2, int(ceil(size.x / r)))
				for k in n + 1:
					out.append([c + axis * lerpf(-size.x * 0.5 + r, size.x * 0.5 - r, float(k) / n), r, id])
			elif cs.shape is SphereShape3D:
				out.append([c, (cs.shape as SphereShape3D).radius, id])
			elif cs.shape is CylinderShape3D:
				out.append([c, (cs.shape as CylinderShape3D).radius, id])
	return out


## Floor obstacles: clear of every road centreline by ROAD_CLEAR + radius, a 0.4 m
## capsule fits between each of them and every trunk or other obstacle, none in T0.
func _check_obstacles(trunks: Array, obstacles: Array) -> void:
	_check(obstacles.size() > 100, "floor obstacles read (%d footprint circles)" % obstacles.size())
	var road_bad := 0
	var t0 := 0
	for o: Array in obstacles:
		var c: Vector2 = o[0]
		if ForestBuilder.road_distance(c) < ForestBuilder.ROAD_CLEAR + float(o[1]) - 0.05:
			road_bad += 1
		if ForestBuilder.tier_at(c.x, c.y) <= 0:
			t0 += 1
	_check(road_bad == 0, "floor obstacles keep ROAD_CLEAR + radius from road centrelines (%d too close)" % road_bad)
	_check(t0 == 0, "no floor obstacle in T0 or outside the wall (%d)" % t0)
	var all := trunks.duplicate()
	var first := all.size()
	all.append_array(obstacles)
	var hash := _hash(all)
	var tight := 0
	var worst := INF
	for i in range(first, all.size()):
		var a: Array = all[i]
		for j: int in _near(hash, a[0]):
			if j == i or (j >= first and j < i):
				continue
			var b: Array = all[j]
			if j >= first and int(a[2]) == int(b[2]):
				continue
			var gap := (a[0] as Vector2).distance_to(b[0]) - float(a[1]) - float(b[1])
			worst = minf(worst, gap)
			if gap < CAPSULE * 2.0:
				tight += 1
	_check(tight == 0, "player fits between every obstacle and its neighbours: gap >= 0.8 m (smallest %.2f m, %d too tight)" % [worst, tight])


## No tree in T0 or outside the wall; per tier the count is within 15 % of area x
## density (the tier's 1 m cells, as tools/render_world_map.py counts them). A cell whose
## first spot is taken (road strip, spacing, a landmark) retries inside its lattice cell,
## so the road and wall clearances move trees rather than drop them.
func _check_tiers(trees: Array) -> void:
	var counts := [0, 0, 0, 0]
	var outside := 0
	for t: Array in trees:
		var tier := ForestBuilder.tier_at(t[0].x, t[0].y)
		if tier < 0:
			outside += 1
		else:
			counts[tier] += 1
	_check(outside == 0, "no tree outside the wall (%d)" % outside)
	_check(counts[0] == 0, "T0 areas are empty (%d trees)" % counts[0])
	var area := [0, 0, 0, 0]
	for tier: int in ForestBuilder.tier_grid():
		area[tier] += 1
	for tier in [1, 2, 3]:
		var expected: float = area[tier] * ForestBuilder.density(tier)
		var dev: float = (counts[tier] - expected) / maxf(expected, 1.0)
		_check(absf(dev) <= COUNT_TOLERANCE, "T%d count %d vs expected %.0f (%d m2 x %.1f/100 m2) deviation %+.1f%%" % [
			tier, counts[tier], expected, area[tier], ForestBuilder.density(tier) * 100.0, dev * 100.0])


func _hash(items: Array) -> Dictionary:
	var h := {}
	for i in items.size():
		var key := Vector2i(((items[i][0] as Vector2) / 4.0).floor())
		if not h.has(key):
			h[key] = []
		(h[key] as Array).append(i)
	return h


func _near(h: Dictionary, p: Vector2) -> Array:
	var out: Array = []
	var key := Vector2i((p / 4.0).floor())
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			out.append_array(h.get(key + Vector2i(dx, dz), []))
	return out
