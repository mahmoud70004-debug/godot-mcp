extends SceneTree
## Checks the baked kingdom forest (ForestBuilder, ForestFloor) is walkable and matches
## the map.
##   $GODOT --headless --path . --script tools/test_forest_walkable.gd
## Reads the trees and the floor back from the baked overworld scene (MultiMesh buffers:
## instance transforms read through get_instance_transform() are identity under
## --headless), the trunk colliders and the floor obstacles (logs, boulders, stumps).
## Prints PASS/FAIL lines and FOREST_TEST_FAILURES <n>.
## (-s mode: no autoloads; only ForestBuilder / WoodProps statics are used.)
## FOREST_SCENE=<path> reads another baked scene (e.g. an older bake, for comparison).
##
## Nothing floats (V6): every hanging moss strand is baked into a tree mesh and hangs from
## one of its limbs (so it is drawn by its own tree instance: same LOD band, same range,
## same cull), no floor card hangs or stands in the air, and every floor card and kit
## stands on the terrain (or on the log it grows on).

const DEFAULT_SCENE := "res://src/levels/valdron/baked/overworld_world.scn"
const CAPSULE := 0.4
## Allowed deviation of the tree count per tier from area x density.
const COUNT_TOLERANCE := 0.15
## The corridors (trees lining the paths) are counted apart from the tiers: this far (m)
## past a path's clearance.
const CORRIDOR_BAND := ForestBuilder.CORRIDOR + 1.5
## Trunks per 10 m of path edge (both sides counted apart) the corridors must reach.
const CORRIDOR_MIN := 2.5
## A floor card or kit origin this close (m) to the terrain counts as standing on it.
const GROUND_TOLERANCE := 0.4
## A baked moss strand's top must be this close (m) to a bark vertex of its tree's limbs.
const LIMB_REACH := 0.6

var _failures := 0


func _initialize() -> void:
	var scene := OS.get_environment("FOREST_SCENE")
	var packed := load(scene if scene != "" else DEFAULT_SCENE) as PackedScene
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
	_check_corridors(trunks)
	_check_moss(forest)
	_check_grounded(root, forest)
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


## Roads (map roads + the painted old forest path): every trunk collider keeps its whole
## width outside the clearance (ROAD_CLEAR m from a road centreline, TRAIL_CLEAR from a
## narrow trail's), and a 0.4 m capsule walked along each centreline in 1 m steps touches
## no trunk collider.
func _check_roads(trees: Array, trunks: Array) -> void:
	var worst_road := INF
	var worst_trail := INF
	var inside := 0
	for tr: Array in trunks:
		var c: Vector2 = tr[0]
		for line: Array in ForestBuilder.road_lines():
			var d := ForestBuilder._polyline_distance(c, line[0])
			if float(line[1]) >= ForestBuilder.ROAD_CLEAR:
				worst_road = minf(worst_road, d)
			else:
				worst_trail = minf(worst_trail, d)
			if d - float(tr[1]) < float(line[1]) - 0.05:
				inside += 1
	_check(inside == 0 and worst_road >= ForestBuilder.ROAD_CLEAR and worst_trail >= ForestBuilder.TRAIL_CLEAR,
		"trunk colliders stay outside the clearances: roads >= %.1f m (closest centre %.2f m), trails >= %.1f m (closest %.2f m), %d inside" % [
		ForestBuilder.ROAD_CLEAR, worst_road, ForestBuilder.TRAIL_CLEAR, worst_trail, inside])
	var feet_ok := true
	for t: Array in trees:
		feet_ok = feet_ok and ForestBuilder.road_margin(t[0]) >= 0.0
	_check(feet_ok, "every tree foot lies outside every road / trail clearance")
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
	var t0_trees := 0
	for t: Array in trees:
		var tier := ForestBuilder.tier_at(t[0].x, t[0].y)
		if tier < 0:
			outside += 1
		elif tier == 0:
			t0_trees += 1
		elif ForestBuilder.road_margin(t[0]) >= CORRIDOR_BAND:
			counts[tier] += 1
	_check(outside == 0, "no tree outside the wall (%d)" % outside)
	_check(t0_trees == 0, "T0 areas are empty (%d trees)" % t0_trees)
	# Area per tier outside the corridor bands (the corridors are checked on their own).
	var area := [0, 0, 0, 0]
	var wr := ForestBuilder.wall_rect()
	var w := int(wr.size.x)
	var grid := ForestBuilder.tier_grid()
	for i in grid.size():
		var tier: int = grid[i]
		if tier == 0:
			continue
		var p := wr.position + Vector2(i % w + 0.5, i / w + 0.5)
		if _near_any_path(p) and ForestBuilder.road_margin(p) < CORRIDOR_BAND:
			continue
		area[tier] += 1
	for tier in [1, 2, 3]:
		var expected: float = area[tier] * ForestBuilder.density(tier)
		var dev: float = (counts[tier] - expected) / maxf(expected, 1.0)
		_check(absf(dev) <= COUNT_TOLERANCE, "T%d count %d vs expected %.0f (%d m2 outside the corridors x %.1f/100 m2) deviation %+.1f%%" % [
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


## Cheap pre-test: within CORRIDOR_BAND + clearance of a path's bounding box.
var _path_boxes: Array = []


func _near_any_path(p: Vector2) -> bool:
	if _path_boxes.is_empty():
		for line: Array in ForestBuilder.road_lines():
			var box := Rect2(ForestBuilder._v2(line[0][0]), Vector2.ZERO)
			for q: Variant in line[0]:
				box = box.expand(ForestBuilder._v2(q))
			_path_boxes.append(box.grow(float(line[1]) + CORRIDOR_BAND + 1.0))
	for box: Rect2 in _path_boxes:
		if box.has_point(p):
			return true
	return false


## Corridors: along every road and trail where both edges are forest ground, the band just
## outside the clearance holds at least CORRIDOR_MIN trunks per 10 m of edge.
func _check_corridors(trunks: Array) -> void:
	var hash := _hash(trunks)
	var edge_m := 0.0
	var count := 0
	var thin := 0.0
	for line: Array in ForestBuilder.road_lines():
		var pts: Array = line[0]
		var clear: float = line[1]
		for k in pts.size() - 1:
			var a := ForestBuilder._v2(pts[k])
			var b := ForestBuilder._v2(pts[k + 1])
			var dir := (b - a).normalized()
			var side := Vector2(-dir.y, dir.x)
			var n := int(a.distance_to(b) / 10.0)
			for i in n:
				var c := a + dir * (10.0 * i + 5.0)
				for sgn: float in [-1.0, 1.0]:
					var probe := c + side * sgn * (clear + 3.0)
					var deep := c + side * sgn * (clear + ForestBuilder.CORRIDOR)
					if ForestBuilder.tier_at(probe.x, probe.y) <= 0 or ForestBuilder.tier_at(deep.x, deep.y) <= 0 \
							or ForestBuilder.road_margin(probe) < 2.0:
						continue
					edge_m += 10.0
					var here := 0
					var seen := {}
					for q: Vector2 in [c + side * sgn * (clear + 2.0), c + side * sgn * (clear + 5.5)]:
						for idx: int in _near_wide(hash, q):
							if seen.has(idx):
								continue
							var tc: Vector2 = trunks[idx][0]
							var rel := tc - c
							var along := rel.dot(dir)
							var across := rel.dot(side) * sgn
							if absf(along) <= 5.0 and across > clear and across <= clear + CORRIDOR_BAND:
								seen[idx] = true
								here += 1
					count += here
					if here < 2:
						thin += 10.0
	var per10 := 10.0 * count / maxf(edge_m, 1.0)
	_check(per10 >= CORRIDOR_MIN, "paths read as corridors: %.1f trunks per 10 m of path edge in the %.1f m band past the clearance (need >= %.1f; %.0f m of edge sampled, %.0f m with < 2)" % [
		per10, CORRIDOR_BAND, CORRIDOR_MIN, edge_m, thin])


func _near_wide(h: Dictionary, p: Vector2) -> Array:
	var out: Array = []
	var key := Vector2i((p / 4.0).floor())
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			out.append_array(h.get(key + Vector2i(dx, dz), []))
	return out


## Hanging moss: baked into the tree meshes as strands (UV2.y > 0, 8 vertices each) whose
## tops sit on a limb (within LIMB_REACH of a bark vertex), so each strand is drawn by its
## own tree instance; the impostor material has none; the moss amount per instance is 0..1
## and nothing hangs on the edge (T1).
func _check_moss(forest: Node3D) -> void:
	var strands := 0
	var off_limb := 0
	var worst := 0.0
	var styles_checked := {}
	var mossy := 0
	var t1_mossy := 0
	var bad_amount := 0
	for cell in forest.get_node("Trees").get_children():
		if not String(cell.name).begins_with("N_"):
			continue
		for k in ForestBuilder.STYLE_NAMES.size():
			var near := (cell as Node3D).get_node_or_null("Near_" + ForestBuilder.STYLE_NAMES[k]) as MultiMeshInstance3D
			if near == null:
				continue
			var mm := near.multimesh
			var stride := _stride(mm)
			var buf := mm.buffer
			for i in mm.instance_count:
				var o := i * stride
				var amount: float = buf[o + 17]
				if amount < 0.0 or amount > 1.0:
					bad_amount += 1
				if amount > 0.0:
					mossy += 1
					var foot := Vector2((cell as Node3D).position.x + buf[o + 3], (cell as Node3D).position.z + buf[o + 11])
					if ForestBuilder.tier_at(foot.x, foot.y) == 1:
						t1_mossy += 1
			if styles_checked.has(k):
				continue
			styles_checked[k] = true
			var arr := mm.mesh.surface_get_arrays(0)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
			var uv2: Variant = arr[Mesh.ARRAY_TEX_UV2]
			if not (uv2 is PackedVector2Array):
				continue
			var bark := PackedVector3Array()
			var tops := PackedVector3Array()
			var strand_verts := 0
			for j in v.size():
				if (uv2 as PackedVector2Array)[j].y > 0.0:
					strand_verts += 1
				elif uv[j].x < -0.5:
					bark.append(v[j])
			# Each strand: two quads of 4 vertices, corners 0 and 1 of a quad are its top.
			var first := -1
			for j in v.size():
				if (uv2 as PackedVector2Array)[j].y > 0.0:
					first = j
					break
			if first >= 0:
				for q in range(first, v.size(), 4):
					tops.append((v[q] + v[q + 1]) * 0.5)
			strands += strand_verts / 8
			for top in tops:
				var best := INF
				for bv in bark:
					best = minf(best, top.distance_to(bv))
				worst = maxf(worst, best)
				if best > LIMB_REACH:
					off_limb += 1
	_check(strands > 0 and off_limb == 0, "hanging moss: %d strands baked into the tree meshes, every one on a limb (farthest %.2f m from bark, %d off a limb)" % [
		strands, worst, off_limb])
	_check(bad_amount == 0 and mossy > 0 and t1_mossy == 0, "moss per tree instance: %d mossy trees, none on the edge (T1: %d), amounts in 0..1 (%d bad)" % [
		mossy, t1_mossy, bad_amount])
	var far_mesh_strands := 0
	for cell in forest.get_node("Trees").get_children():
		var far := (cell as Node3D).get_node_or_null("Far") as MultiMeshInstance3D
		if far:
			var a2: Variant = far.multimesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV2]
			# The card mesh tags only its flat quad (UV2.x); no strand ranks.
			if a2 is PackedVector2Array:
				for t in (a2 as PackedVector2Array):
					if t.y > 0.0:
						far_mesh_strands += 1
	_check(far_mesh_strands == 0, "impostor cards carry no moss strands (%d)" % far_mesh_strands)


## Terrain height at (x, z) from the baked HeightMapShape3D (bilinear), or NAN.
var _hm: HeightMapShape3D
var _hm_xf: Transform3D


func _ground_y(x: float, z: float) -> float:
	if _hm == null:
		return NAN
	var cell := _hm_xf.basis.x.length()
	var gx := (x - _hm_xf.origin.x) / cell + (_hm.map_width - 1) * 0.5
	var gz := (z - _hm_xf.origin.z) / cell + (_hm.map_depth - 1) * 0.5
	gx = clampf(gx, 0.0, _hm.map_width - 1.001)
	gz = clampf(gz, 0.0, _hm.map_depth - 1.001)
	var ix := int(gx)
	var iz := int(gz)
	var fx := gx - ix
	var fz := gz - iz
	var d := _hm.map_data
	var w := _hm.map_width
	var h00 := d[iz * w + ix]
	var h10 := d[iz * w + ix + 1]
	var h01 := d[(iz + 1) * w + ix]
	var h11 := d[(iz + 1) * w + ix + 1]
	return (lerpf(lerpf(h00, h10, fx), lerpf(h01, h11, fx), fz)) * cell + _hm_xf.origin.y


## Every floor card and kit stands on the terrain (small kits may sit on a fallen log);
## no card is a hanging strip (mode 2 / hang tile) or floats over a path.
func _check_grounded(root: Node3D, forest: Node3D) -> void:
	for node in root.find_children("*", "CollisionShape3D", true, false):
		var cs := node as CollisionShape3D
		if cs.shape is HeightMapShape3D:
			_hm = cs.shape as HeightMapShape3D
			var xf := cs.transform
			var n: Node = cs.get_parent()
			while n != null and n != root:
				if n is Node3D:
					xf = (n as Node3D).transform * xf
				n = n.get_parent()
			_hm_xf = xf
	_check(_hm != null, "terrain height map found in the baked world")
	if _hm == null:
		return
	var floor_node := forest.get_node_or_null("Floor")
	if floor_node == null:
		return
	var logs: Array = []
	for cell in floor_node.get_children():
		var large := (cell as Node3D).get_node_or_null("Large") as MultiMeshInstance3D
		if large == null:
			continue
		var stride := _stride(large.multimesh)
		var buf := large.multimesh.buffer
		for i in large.multimesh.instance_count:
			var o := i * stride
			var kit := int(round(buf[o + 16]))
			if kit == ForestFloor.Large.LOG or kit == ForestFloor.Large.HOLLOW_LOG:
				logs.append(Vector2((cell as Node3D).position.x + buf[o + 3], (cell as Node3D).position.z + buf[o + 11]))
	var hang_uv := ForestAtlas.hang_uv_rect().position
	var floating := 0
	var hanging := 0
	var worst := 0.0
	var checked := 0
	for cell in floor_node.get_children():
		var c := cell as Node3D
		for fam: String in ["Cards", "Small", "Large"]:
			var mmi := c.get_node_or_null(fam) as MultiMeshInstance3D
			if mmi == null:
				continue
			var stride := _stride(mmi.multimesh)
			var buf := mmi.multimesh.buffer
			for i in mmi.multimesh.instance_count:
				var o := i * stride
				var p := c.position + Vector3(buf[o + 3], buf[o + 7], buf[o + 11])
				checked += 1
				if fam == "Cards":
					var mode := fmod(buf[o + 19], 10.0)
					if buf[o + 19] > 9.5 or (mode > 1.5 and mode < 2.5) or Vector2(buf[o + 16], buf[o + 17]).distance_to(hang_uv) < 0.001:
						hanging += 1
				var rise := p.y - _ground_y(p.x, p.z)
				if absf(rise) <= GROUND_TOLERANCE:
					continue
				if fam == "Small" and rise > 0.0 and rise < 1.6 and _near_log(logs, Vector2(p.x, p.z)):
					continue
				floating += 1
				worst = maxf(worst, absf(rise))
	_check(hanging == 0, "no hanging cards on the floor (moss is part of the trees) (%d)" % hanging)
	_check(floating == 0, "every floor card and kit stands on the ground: %d checked, %d off it (worst %.2f m)" % [checked, floating, worst])


func _near_log(logs: Array, p: Vector2) -> bool:
	for q: Vector2 in logs:
		if q.distance_to(p) < 3.0:
			return true
	return false
