extends SceneTree
## Checks the baked kingdom forest (ForestBuilder) is walkable and matches the map.
##   $GODOT --headless --path . --script tools/test_forest_walkable.gd
## Reads the trees back from the baked overworld scene (MultiMesh buffers: instance
## transforms read through get_instance_transform() are identity under --headless) and
## the trunk colliders. Prints PASS/FAIL lines and FOREST_TEST_FAILURES <n>.
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
	_check(trees.size() > 500, "trees read from the MultiMesh buffers (%d)" % trees.size())
	_check(trunks.size() == trees.size(), "one trunk collider per tree (%d colliders, %d trees)" % [trunks.size(), trees.size()])
	_check_markers(forest)
	_check_roads(trees, trunks)
	_check_spacing(trees, trunks)
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


## [Vector2 foot, style index] per tree, from the Near_<style> copies (the Far ones repeat
## them); also checks every buffer holds real (non-zero) transforms and Far == Near.
func _trees(forest: Node3D) -> Array:
	var out: Array = []
	var zero := 0
	var mismatched := 0
	for chunk in forest.get_node("Trees").get_children():
		var c := chunk as Node3D
		for k in ForestBuilder.STYLE_NAMES.size():
			var near := c.get_node_or_null("Near_" + ForestBuilder.STYLE_NAMES[k]) as MultiMeshInstance3D
			var far := c.get_node_or_null("Far_" + ForestBuilder.STYLE_NAMES[k]) as MultiMeshInstance3D
			if near == null:
				continue
			if far == null or far.multimesh.buffer != near.multimesh.buffer:
				mismatched += 1
			var mm := near.multimesh
			var stride := 12 + (4 if mm.use_colors else 0) + (4 if mm.use_custom_data else 0)
			var buf := mm.buffer
			for i in mm.instance_count:
				var o := i * stride
				if absf(buf[o]) + absf(buf[o + 5]) + absf(buf[o + 10]) < 0.01:
					zero += 1
				out.append([Vector2(c.position.x + buf[o + 3], c.position.z + buf[o + 11]), k])
	_check(zero == 0, "tree MultiMesh buffers hold real transforms (%d empty instances)" % zero)
	_check(mismatched == 0, "detailed and low-poly copies hold the same instances (%d mismatched)" % mismatched)
	return out


## [Vector2 centre, radius] of every trunk cylinder.
func _trunks(forest: Node3D) -> Array:
	var out: Array = []
	for chunk in forest.get_node("Trees").get_children():
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
	for want in ["Spawn_Enemy_1", "Spawn_Enemy_2", "Spawn_Enemy_3", "Lore_1", "Pickup_1", "Trigger"]:
		_check(names.has(want), "marker %s" % want)
	var trigger := markers.get_node_or_null("Trigger") if markers else null
	var box: Vector3 = trigger.get_meta("box", Vector3.ZERO) if trigger else Vector3.ZERO
	var wr := ForestBuilder.wall_rect()
	_check(box.x >= wr.size.x and box.z >= wr.size.y, "forest trigger box covers the interior (%s)" % box)


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
