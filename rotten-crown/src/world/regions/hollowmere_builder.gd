@tool
class_name HollowmereBuilder
extends RefCounted
## Hollowmere (reference 2, "Over the Garden Wall": a pale dirt road curving out of a
## pumpkin patch towards a village of pale houses and a church spire), after the curse.
## Hero view: from the road in the fields (HERO) up the curving farm track to the
## half-timbered village and the chapel spire. The harvest grew into flesh: pumpkins
## with human teeth and eyes, villagers stitched to scarecrow posts, a house swallowed
## by a breathing pumpkin-flesh mass, blood trails into the houses, burnt and collapsed
## roofs, curse sigils on the doors, gibbet cages.
##
## Assumptions (contract C9, owned by the overworld assembler / OverworldSpec):
## - TerrainBuilder over OverworldSpec.make(); -Z is towards the castle.
## - Main road polyline OverworldSpec.MAIN_ROAD, road_width 3.2; it ends at (20, 322).
## - Village plateau Vector4(22, 338, 44, 24) is flat; FOREST_PATH ends at (34, 322).
## - Region node sits at the origin, so child positions are world positions.
## - Markers: Spawn_Enemy_1..5, Lore_1..2, Pickup_1..2, Light_1..4 and Trigger
##   (meta "radius"). OmniLight3D nodes: LanternLight (chapel), CandleLight (window),
##   WellLight (square), MawLight (the swallowed house); Light_N mark the same spots.
## - res://assets/materials/grass_field.tres exists (GrassScatter material).
## Performance: organic detail is batched per material and 16 m cell (HollowmereBatch,
## pumpkins with a near/far LOD); architecture and kit props are merged here per group
## with their own visibility range (small props 60 m, fields 90 m, buildings 115 m).

const GRASS_MAT := "res://assets/materials/grass_field.tres"
const FIELD_Z0 := 236.0
const FIELD_Z1 := 308.0
const SQUARE := Vector2(24.0, 343.0)
const CHAPEL_POS := Vector2(28.0, 366.0)
## Hero view: the reference composition (see docs, U8). RC_SHOT pose in the report.
const HERO := Vector2(8.2, 268.0)
## Curving farm track: leaves the road, sweeps east round the fields, back into the village.
const TRACK := [Vector2(9.6, 262.0), Vector2(14.0, 266.5), Vector2(20.5, 272.5), Vector2(26.0, 280.0), Vector2(29.5, 289.0),
	Vector2(30.5, 298.0), Vector2(28.5, 307.0), Vector2(25.5, 316.0), Vector2(23.4, 326.0), Vector2(23.0, 333.0)]
const LANE := [Vector2(20.0, 322.0), Vector2(23.0, 333.0), Vector2(24.0, 343.0), Vector2(26.0, 352.0), Vector2(28.0, 359.0)]
const LANE_WEST := [Vector2(24.0, 343.0), Vector2(14.0, 345.5), Vector2(3.0, 349.0)]
const LANE_EAST := [Vector2(25.0, 341.0), Vector2(30.5, 332.0), Vector2(34.0, 322.0)]
## [x, z, face_x, face_z, width, depth, storeys, ruin, opts]
const HOUSES := [
	[11.0, 339.0, 24.0, 343.0, 5.0, 6.0, 2, 0, {"lit": 2, "sigil": true, "door": "closed"}],
	[12.5, 354.0, 24.0, 345.0, 4.6, 5.6, 2, 1, {"sigil": true, "door": "torn", "rust": true}],
	[38.5, 329.5, 30.0, 333.0, 5.0, 6.0, 2, 2, {"door": "torn"}],
	[38.5, 348.0, 24.0, 344.0, 5.0, 6.2, 2, 0, {"lit": 1, "door": "open"}],
	[15.5, 365.0, 24.0, 350.0, 4.8, 5.8, 2, 2, {"door": "torn", "rust": true}],
	[3.5, 321.0, 18.0, 322.0, 6.0, 7.0, 2, 0, {"lit": 3, "door": "closed", "sigil": true}],
	[-5.0, 337.0, 10.0, 340.0, 4.4, 5.2, 1, 1, {"door": "open", "rust": true}],
	[34.5, 311.0, 25.0, 313.0, 4.6, 5.4, 1, 2, {"door": "open", "rust": true}],
	[46.5, 341.0, 30.0, 340.0, 4.4, 5.2, 1, 0, {"door": "closed", "sigil": true}],
	[2.0, 358.5, 14.0, 348.0, 4.8, 5.6, 2, 1, {"door": "open", "lit": 1}],
	[-6.5, 306.0, 10.0, 302.0, 7.0, 9.0, 1, 0, {"door": "closed", "rust": true}],
]
const SWALLOWED := 2
const CANDLE_HOUSE := 3
const SCARECROWS := [[Vector2(-5.5, 258.0), false], [Vector2(18.5, 257.0), true], [Vector2(21.5, 283.0), false],
	[Vector2(1.0, 285.0), true], [Vector2(35.5, 296.0), false], [Vector2(15.4, 313.0), false], [Vector2(23.0, 309.5), true]]
const TORSO_BEDS := [Vector2(-1.0, 249.0), Vector2(17.0, 289.0), Vector2(-4.5, 274.0), Vector2(31.0, 270.0)]
const DEAD_TREE := Vector2(-3.5, 290.0)
## A second bare tree in the island between road and track (left-middle of the hero view).
const DEAD_TREE_2 := Vector2(23.0, 292.5)
const MAWS := [Vector2(13.2, 276.0), Vector2(2.4, 262.0)]

static var _reserved: Array[Vector3] = []


static func build(root: Node3D, terrain: TerrainBuilder, rng: RandomNumberGenerator) -> Node3D:
	var region := Node3D.new()
	region.name = "Hollowmere"
	root.add_child(region)
	var organic := _group(region, "Organic")
	var fields := _group(region, "Fields")
	var village := _group(region, "Village")
	var small := _group(region, "SmallProps")
	var b := HollowmereBatch.new(20.0, true)
	var tf := HollowmereBatch.new(20.0, false)
	var tv := HollowmereBatch.new(20.0, false)
	_reserve_layout()
	_ground_paths(b, tv, tf, terrain, rng)
	var houses := _village(village, b, tv, terrain, rng)
	_chapel_and_graves(village, small, b, tv, terrain, rng)
	_square(village, small, b, tv, terrain, rng, houses)
	_field_horrors(fields, b, tf, terrain, rng)
	_pumpkin_fields(b, terrain, rng)
	_fences(tf, terrain, rng)
	_grass(region, terrain, rng)
	_markers(region, terrain)
	b.commit(organic, "HM_Organic")
	tf.commit(fields, "HM_Fields")
	tv.commit(village, "HM_Village")
	_merge(small, 60.0)
	_merge(fields, 90.0)
	_merge(village, 115.0)
	return region


# --- Helpers ---------------------------------------------------------------------

static func _group(parent: Node3D, group_name: String) -> Node3D:
	var node := Node3D.new()
	node.name = group_name
	parent.add_child(node)
	return node


## Merges a group's static meshes per material and 20 m cell with its own range; the
## results are flagged so the overworld's merge leaves them alone.
static func _merge(group: Node3D, range_end: float) -> void:
	var before := {}
	for c in group.get_children():
		before[c] = true
	MeshMerger.merge_static(group, 20.0, range_end)
	for c in group.get_children():
		if not before.has(c) and c is MeshInstance3D:
			c.set_meta(MeshMerger.SKIP_META, true)
	for node in group.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.visible and mi.visibility_range_end <= 0.0:
			mi.visibility_range_end = range_end


## Main road centre x at world z (linear along the polyline).
static func _road_x(z: float) -> float:
	var pts := OverworldSpec.MAIN_ROAD
	for k in pts.size() - 1:
		var a: Vector2 = pts[k]
		var b: Vector2 = pts[k + 1]
		if z >= a.y and z <= b.y:
			return lerpf(a.x, b.x, (z - a.y) / (b.y - a.y))
	return (pts[pts.size() - 1] as Vector2).x


static func _poly_dist(p: Vector2, pts: Array) -> float:
	var best := INF
	for k in pts.size() - 1:
		var a: Vector2 = pts[k]
		var b: Vector2 = pts[k + 1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t))
	return best


## Distance to any walkable way (road, track, lanes, forest path end).
static func _path_dist(p: Vector2) -> float:
	var d := minf(_poly_dist(p, OverworldSpec.MAIN_ROAD), _poly_dist(p, TRACK))
	d = minf(d, minf(_poly_dist(p, LANE), _poly_dist(p, LANE_WEST)))
	d = minf(d, minf(_poly_dist(p, LANE_EAST), _poly_dist(p, OverworldSpec.FOREST_PATH)))
	return d


static func _free(p: Vector2, r: float) -> bool:
	for c in _reserved:
		if p.distance_to(Vector2(c.x, c.y)) < c.z + r:
			return false
	return true


static func _house_hit(p: Vector2, margin: float) -> bool:
	for h in HOUSES:
		var c := Vector2(h[0], h[1])
		var half := maxf(float(h[4]), float(h[5])) * 0.5 + 0.6
		if p.distance_to(c) < half + margin:
			return true
	return false


static func _reserve_layout() -> void:
	_reserved.clear()
	for s in SCARECROWS:
		var p: Vector2 = s[0]
		_reserved.append(Vector3(p.x, p.y, 1.3))
	for p: Vector2 in TORSO_BEDS:
		_reserved.append(Vector3(p.x, p.y, 1.9))
	for p: Vector2 in MAWS:
		_reserved.append(Vector3(p.x, p.y, 3.0))
	_reserved.append(Vector3(DEAD_TREE.x, DEAD_TREE.y, 2.6))
	_reserved.append(Vector3(DEAD_TREE_2.x, DEAD_TREE_2.y, 2.2))
	for m in _marker_spots().values():
		var q: Vector2 = m
		_reserved.append(Vector3(q.x, q.y, 1.3))


static func _marker_spots() -> Dictionary:
	return {"Spawn_Enemy_1": Vector2(19.0, 346.0), "Spawn_Enemy_2": Vector2(29.0, 341.0), "Spawn_Enemy_3": Vector2(24.0, 352.0),
		"Spawn_Enemy_4": Vector2(_road_x(262.0) + 8.0, 262.0), "Spawn_Enemy_5": Vector2(_road_x(282.0) - 8.0, 282.0),
		"Lore_1": Vector2(31.5, 357.0), "Lore_2": Vector2(_road_x(250.0) - 3.4, 250.0),
		"Pickup_1": Vector2(13.0, 333.0), "Pickup_2": Vector2(40.0, 340.0)}


## Terrain-hugging strip along `pts` (dirt track, cobbled lanes). Returns nothing; pieces go
## into `tb` (textured); ruts / puddles into `b`.
static func _ribbon(tb: HollowmereBatch, mat: Material, terrain: TerrainBuilder, pts: Array, width: float, lift: float, rng: RandomNumberGenerator) -> void:
	var samples := OverworldSpec.sample_path(pts, 1.2)
	var grid := PackedVector3Array()
	var cols := PackedColorArray()
	var hints := PackedVector3Array()
	var white := Color(1, 1, 1)
	for k in samples.size():
		var p := samples[k]
		var dir := (samples[mini(k + 1, samples.size() - 1)] - samples[maxi(k - 1, 0)]).normalized()
		var side := Vector2(-dir.y, dir.x)
		var w := width * 0.5 * (1.0 + 0.12 * sin(p.x * 0.9 + p.y * 0.7))
		for f: float in [-1.0, -0.5, 0.0, 0.5, 1.0]:
			var q := p + side * f * w * (1.0 if absf(f) < 1.0 else rng.randf_range(0.9, 1.1))
			grid.append(terrain.ground(q.x, q.y) + Vector3(0, lift - absf(f) * 0.015, 0))
			cols.append(white)
			hints.append(Vector3.UP)
	tb.at(terrain.ground(samples[0].x, samples[0].y), 100.0, false)
	# Commit in runs of ~16 m so each piece lands in its own merge cell.
	var run := 14
	var start := 0
	while start < samples.size() - 1:
		var end := mini(start + run, samples.size() - 1)
		var mid := samples[(start + end) / 2]
		tb.at(Vector3(mid.x, 0, mid.y), 100.0, false)
		var sub := grid.slice(start * 5, (end + 1) * 5)
		tb.grid(mat, sub, 5, end - start + 1, false, cols.slice(start * 5, (end + 1) * 5), hints.slice(start * 5, (end + 1) * 5))
		start = end


# --- Paths: farm track, cobbled lanes, the square -------------------------------

static func _ground_paths(b: HollowmereBatch, tv: HollowmereBatch, tf: HollowmereBatch, terrain: TerrainBuilder, rng: RandomNumberGenerator) -> void:
	_ribbon(tf, RetroMaterials.mud(), terrain, TRACK, 2.7, 0.05, rng)
	# Wheel ruts and puddles along the track.
	var org := HollowmereProps.organic()
	var samples := OverworldSpec.sample_path(TRACK, 1.5)
	for k in samples.size() - 1:
		var a := samples[k]
		var c := samples[k + 1]
		var dir := (c - a).normalized()
		var side := Vector2(-dir.y, dir.x)
		b.at(Vector3(a.x, 0, a.y), 70.0)
		for s: float in [-0.55, 0.55]:
			var p0 := a + side * s
			var p1 := c + side * s
			b.beam(org, terrain.ground(p0.x, p0.y) + Vector3(0, 0.065, 0), terrain.ground(p1.x, p1.y) + Vector3(0, 0.065, 0), 0.02, 0.22, Color(0.16, 0.11, 0.08))
		if rng.randf() < 0.12:
			HollowmereProps.ground_pool(b, org, terrain, a + side * rng.randf_range(-0.5, 0.5), rng.randf_range(0.35, 0.7), Color(0.07, 0.06, 0.06), Color(0.14, 0.11, 0.09), rng, 0.075)
	var cobble := RetroMaterials.cobble()
	for lane: Array in [LANE, LANE_WEST, LANE_EAST]:
		_ribbon(tv, cobble, terrain, lane, 3.0, 0.06, rng)
	# Cobbled square: rings round the well.
	var segs := 18
	var rings := [0.0, 2.0, 4.5, 7.5]
	var pts := PackedVector3Array()
	var cols := PackedColorArray()
	var hints := PackedVector3Array()
	for r: float in rings:
		for k in segs:
			var a := TAU * k / segs
			var rr := r * (1.0 + (0.12 * sin(a * 3.0 + 1.0) if r > 7.0 else 0.0))
			var q := SQUARE + Vector2(cos(a), sin(a)) * rr
			pts.append(terrain.ground(q.x, q.y) + Vector3(0, 0.07, 0))
			cols.append(Color(1, 1, 1))
			hints.append(Vector3.UP)
	tv.at(Vector3(SQUARE.x, 0, SQUARE.y), 115.0, false)
	tv.grid(cobble, pts, segs, rings.size(), true, cols, hints)
	# Mud and puddles over the cobbles.
	b.at(Vector3(SQUARE.x, 0, SQUARE.y), 70.0)
	for k in 14:
		var a := rng.randf() * TAU
		var q := SQUARE + Vector2(cos(a), sin(a)) * rng.randf_range(2.0, 9.0)
		HollowmereProps.ground_pool(b, org, terrain, q, rng.randf_range(0.5, 1.3), Color(0.11, 0.08, 0.06), Color(0.16, 0.12, 0.08), rng, 0.085)


# --- Pumpkin fields ---------------------------------------------------------------

static func _field_ok(p: Vector2, side: float) -> bool:
	var z_end := 300.0 if side < 0.0 else FIELD_Z1
	if p.y < FIELD_Z0 or p.y > z_end:
		return false
	if _poly_dist(p, OverworldSpec.MAIN_ROAD) < 2.5 or _poly_dist(p, TRACK) < 2.1:
		return false
	if _house_hit(p, 0.8):
		return false
	return _free(p, 0.6)


static func _pumpkin_fields(b: HollowmereBatch, terrain: TerrainBuilder, rng: RandomNumberGenerator) -> void:
	var org := HollowmereProps.organic()
	var counts := {"pumpkins": 0, "leaves": 0}
	for side: float in [-1.0, 1.0]:
		var rows := 7 if side < 0.0 else 9
		for row in rows:
			var off := (2.9 if side < 0.0 else 3.6) + row * 2.35
			var t := float(row) / (rows - 1)
			var step_lo := lerpf(0.95, 1.5, t)
			var step_hi := lerpf(1.3, 2.3, t)
			var z := FIELD_Z0 + rng.randf_range(0.0, 1.5)
			var furrow := PackedVector3Array()
			while z < FIELD_Z1 + 1.0:
				var x := _road_x(z) + side * (off + sin(z * 0.09 + off) * 0.5)
				var p := Vector2(x, z)
				var ok := _field_ok(p, side)
				if ok:
					furrow.append(terrain.ground(x, z))
				if (not ok or z + step_lo >= FIELD_Z1 + 1.0) and furrow.size() > 1:
					_furrow(b, furrow, rng)
					furrow = PackedVector3Array()
				elif not ok:
					furrow = PackedVector3Array()
				if ok and rng.randf() > 0.13:
					var g := terrain.ground(x + rng.randf_range(-0.25, 0.25), z)
					var pk := HollowmereProps.roll_pumpkin(rng, 0.09)
					b.at(g, 34.0, true)
					HollowmereProps.pumpkin(b, g, pk, 0)
					b.at(g, 95.0, false, 34.0)
					HollowmereProps.pumpkin(b, g, pk, 1)
					counts["pumpkins"] = int(counts["pumpkins"]) + 1
					b.at(g, 70.0)
					for k in rng.randi_range(2, 3):
						var a := rng.randf() * TAU
						var lp := g + Vector3(cos(a), 0, sin(a)) * (float(pk["size"]) * 0.5 + rng.randf_range(0.15, 0.45))
						lp.y = terrain.height_at(lp.x, lp.z) + 0.06
						var dead := rng.randf() < 0.35
						var col := HollowmereProps.jit(HollowmereProps.pick(HollowmereProps.LEAF_DEAD if dead else HollowmereProps.LEAF_GREEN, rng), rng)
						HollowmereProps.leaf(b, lp, rng.randf_range(0.28, 0.5), rng.randf() * TAU, rng.randf_range(-0.35, 0.35), col, col.darkened(0.35))
						counts["leaves"] = int(counts["leaves"]) + 1
				elif ok and rng.randf() < 0.5:
					b.at(terrain.ground(x, z), 70.0)
					HollowmereProps.ground_pool(b, org, terrain, p, 0.35, Color(0.13, 0.09, 0.06), HollowmereProps.SOIL, rng, 0.11)
				z += rng.randf_range(step_lo, step_hi)
	print("Hollowmere fields: %d pumpkins, %d leaves" % [counts["pumpkins"], counts["leaves"]])


## Mounded soil row with the vine running along its crest.
static func _furrow(b: HollowmereBatch, pts: PackedVector3Array, rng: RandomNumberGenerator) -> void:
	var org := HollowmereProps.organic()
	var grid := PackedVector3Array()
	var cols := PackedColorArray()
	var hints := PackedVector3Array()
	var vine := PackedVector3Array()
	var radii := PackedFloat32Array()
	for k in pts.size():
		var dir := (pts[mini(k + 1, pts.size() - 1)] - pts[maxi(k - 1, 0)])
		dir.y = 0.0
		dir = dir.normalized()
		var side := Vector3(-dir.z, 0, dir.x)
		for f: float in [-1.0, 0.0, 1.0]:
			grid.append(pts[k] + side * f * 0.75 + Vector3(0, 0.03 + (0.13 if f == 0.0 else 0.0), 0))
			cols.append(HollowmereProps.SOIL.lightened(0.08) if f == 0.0 else HollowmereProps.SOIL.darkened(0.25))
			hints.append(Vector3.UP)
		vine.append(pts[k] + side * sin(k * 1.7) * 0.25 + Vector3(0, 0.17, 0))
		radii.append(0.035)
	b.at(pts[pts.size() / 2], 95.0)
	b.grid(org, grid, 3, pts.size(), false, cols, hints)
	b.at(pts[pts.size() / 2], 70.0)
	b.tube(org, vine, radii, 3, HollowmereProps.VINE)
	for k in pts.size():
		if rng.randf() < 0.5:
			var lp := vine[k] + Vector3(rng.randf_range(-0.3, 0.3), -0.04, rng.randf_range(-0.3, 0.3))
			var col := HollowmereProps.jit(HollowmereProps.pick(HollowmereProps.LEAF_GREEN, rng), rng)
			HollowmereProps.leaf(b, lp, rng.randf_range(0.22, 0.38), rng.randf() * TAU, rng.randf_range(-0.3, 0.3), col, col.darkened(0.3))


static func _field_horrors(fields: Node3D, b: HollowmereBatch, tf: HollowmereBatch, terrain: TerrainBuilder, rng: RandomNumberGenerator) -> void:
	# The dead tree at the field edge with a cage hanging from it.
	var tree_base := terrain.ground(DEAD_TREE.x, DEAD_TREE.y)
	tf.at(tree_base, 110.0)
	var hangs := HollowmereProps.dead_tree(tf, tree_base, 9.5, Vector3(1, 0, 0.4), rng)
	var tree_body := HollowmereProps.body(fields, "DeadTreeCollider")
	HollowmereProps.shape_cyl(tree_body, 0.6, 4.0, tree_base + Vector3(0, 2.0, 0))
	var best := hangs[0]
	for h in hangs:
		if Vector2(h.x - tree_base.x, h.z - tree_base.z).length() > Vector2(best.x - tree_base.x, best.z - tree_base.z).length():
			best = h
	b.at(tree_base, 115.0)
	HollowmereProps.gibbet_cage(tf, b, best, maxf(best.y - tree_base.y - 2.4, 0.6), rng)
	var tree2 := terrain.ground(DEAD_TREE_2.x, DEAD_TREE_2.y)
	tf.at(tree2, 110.0)
	HollowmereProps.dead_tree(tf, tree2, 7.5, Vector3(-0.6, 0, 1), rng)
	HollowmereProps.shape_cyl(tree_body, 0.45, 3.0, tree2 + Vector3(0, 1.5, 0))
	# Villagers stitched to the scarecrow posts.
	for s in SCARECROWS:
		var p: Vector2 = s[0]
		var to_road := Vector2(_road_x(p.y), p.y) - p
		var yaw := atan2(to_road.x, to_road.y) + rng.randf_range(-0.5, 0.5)
		tf.at(terrain.ground(p.x, p.y), 90.0)
		b.at(terrain.ground(p.x, p.y), 70.0)
		HollowmereProps.stitched_scarecrow(fields, tf, b, terrain, p, yaw, rng, bool(s[1]))
	for p: Vector2 in TORSO_BEDS:
		b.at(terrain.ground(p.x, p.y), 70.0)
		HollowmereProps.torso_bed(b, terrain, p, rng)
	# Giant maws: pumpkins grown into gaping human mouths by the road.
	for p: Vector2 in MAWS:
		var g := terrain.ground(p.x, p.y)
		var to_road := Vector2(_road_x(p.y), p.y - 6.0) - p
		var pk := {"kind": 4, "size": rng.randf_range(2.1, 2.5), "tint": HollowmereProps.PUMPKINS[0], "ribs": 9, "squash": 0.72, "rot": 0.25,
			"seed": rng.randi(), "yaw": atan2(to_road.x, to_road.y), "tilt": -0.12}
		b.at(g, 115.0)
		HollowmereProps.pumpkin(b, g, pk, 0)
		HollowmereProps.ground_pool(b, HollowmereProps.flesh(), terrain, p + to_road.normalized() * 1.3, 0.9,
				HollowmereProps.wa(HollowmereProps.BLOOD_DARK, 0.0), HollowmereProps.wa(HollowmereProps.BLOOD, 0.0), rng)
	# Blood dragged from the field to the road.
	b.at(terrain.ground(TORSO_BEDS[2].x, TORSO_BEDS[2].y), 70.0)
	HollowmereProps.blood_trail(b, terrain, TORSO_BEDS[2], Vector2(_road_x(279.0) - 1.0, 279.0), rng)
	b.at(terrain.ground(TORSO_BEDS[1].x, TORSO_BEDS[1].y), 70.0)
	HollowmereProps.blood_trail(b, terrain, TORSO_BEDS[1], Vector2(_road_x(293.0) + 0.5, 293.0), rng)
	# Carved lanterns glowing along the road into the village.
	for z: float in [246.0, 259.0, 271.0, 284.0, 297.0, 309.0, 316.0]:
		for s: float in [-1.0, 1.0]:
			if rng.randf() < 0.4:
				continue
			var p := Vector2(_road_x(z) + s * rng.randf_range(2.3, 2.8), z + rng.randf_range(-1.0, 1.0))
			if _poly_dist(p, TRACK) < 1.6:
				continue
			_jack(b, terrain.ground(p.x, p.y), atan2(-s, 0.0) + rng.randf_range(-0.4, 0.4), rng)


static func _jack(b: HollowmereBatch, g: Vector3, yaw: float, rng: RandomNumberGenerator) -> void:
	var pk := HollowmereProps.roll_pumpkin(rng, 0.0)
	pk["kind"] = 0
	pk["rot"] = 0.1
	pk["yaw"] = yaw
	pk["tilt"] = 0.0
	pk["size"] = rng.randf_range(0.6, 0.85)
	pk["squash"] = 0.78
	b.at(g, 115.0)
	HollowmereProps.pumpkin(b, g, pk, 0)
	var size: float = pk["size"]
	var hy := size * 0.5 * 0.78
	HollowmereProps.carve_face(b, g + Vector3(0, hy * 0.86 - size * 0.03, 0), Basis(Vector3.UP, yaw), size * 0.5 * 0.93, hy)


static func _fences(tf: HollowmereBatch, terrain: TerrainBuilder, rng: RandomNumberGenerator) -> void:
	# Right of the road up to the track junction, then round the outside of the track curve.
	var runs: Array = []
	var east := PackedVector2Array()
	var z := FIELD_Z0 - 2.0
	while z < 258.0:
		east.append(Vector2(_road_x(z) + 2.75, z))
		z += 2.7
	runs.append(east)
	var outer := PackedVector2Array()
	var samples := OverworldSpec.sample_path(TRACK.slice(0, 7), 2.7)
	for k in samples.size():
		var a := samples[maxi(k - 1, 0)]
		var c := samples[mini(k + 1, samples.size() - 1)]
		var dir := (c - a).normalized()
		outer.append(samples[k] + Vector2(dir.y, -dir.x) * 2.3)
	runs.append(outer)
	# Left of the road beyond the hero, broken, and the western field edge.
	var west := PackedVector2Array()
	z = 275.0
	while z < 312.0:
		west.append(Vector2(_road_x(z) - 2.75, z))
		z += 2.7
	runs.append(west)
	var edge := PackedVector2Array()
	z = FIELD_Z0
	while z < 298.0:
		edge.append(Vector2(_road_x(z) - 19.5, z))
		z += 2.7
	runs.append(edge)
	var skip := func(p: Vector2) -> bool:
		return _house_hit(p, 0.5) or not _free(p, 0.3) or _poly_dist(p, OverworldSpec.MAIN_ROAD) < 1.9
	for k in runs.size():
		var pts: PackedVector2Array = runs[k]
		var mid := pts[pts.size() / 2]
		tf.at(terrain.ground(mid.x, mid.y), 90.0)
		HollowmereProps.zigzag_fence(tf, terrain, pts, 0.12 if k < 2 else 0.35, rng, skip)


# --- Village --------------------------------------------------------------------------

## Builds the houses (HollowmereProps.house); returns their info dictionaries.
static func _village(village: Node3D, b: HollowmereBatch, tv: HollowmereBatch, terrain: TerrainBuilder, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	for i in HOUSES.size():
		var h: Array = HOUSES[i]
		var c := Vector2(h[0], h[1])
		var face := Vector2(h[2], h[3]) - c
		var yaw := atan2(face.x, face.y) + rng.randf_range(-0.12, 0.12)
		var w: float = h[4]
		var d: float = h[5]
		var low := INF
		for cx: float in [-1.0, 1.0]:
			for cz: float in [-1.0, 1.0]:
				var q := c + Vector2(cx * w * 0.5, cz * d * 0.5).rotated(-yaw)
				low = minf(low, terrain.height_at(q.x, q.y))
		var pos := Vector3(c.x, low, c.y)
		var node := _group(village, "House_%d" % (i + 1))
		tv.at(pos, 115.0)
		b.at(pos, 115.0)
		var info := HollowmereProps.house(node, tv, b, pos, yaw, w, d, int(h[6]), int(h[7]), rng, h[8])
		out.append(info)
		# Curse growths swelling out of walls and roofs (not on the untouched houses).
		var spots: Array = (info["anchors"] as Array) + (info["roof"] as Array)
		var growths := 0 if i == 0 or i == 8 else (3 if int(h[7]) > 0 else 1)
		if i == SWALLOWED:
			growths = 4
		for k in growths:
			var s: Array = spots[rng.randi() % spots.size()]
			b.at(pos, 115.0)
			HollowmereProps.flesh_growth(b, s[0], s[1], rng.randf_range(0.6, 1.1), rng)
		if i == SWALLOWED:
			_swallowed(village, b, terrain, info, w, d, rng)
	# The candle in one window of the house across the square.
	var cinfo: Dictionary = out[CANDLE_HOUSE]
	var cxf: Transform3D = cinfo["xf"]
	var cp := cxf * Vector3(0.0, 4.2, 3.55)
	var candle := OmniLight3D.new()
	candle.name = "CandleLight"
	candle.position = cp + Vector3(0, 0.1, 0)
	candle.light_color = Color(1.0, 0.6, 0.25)
	candle.light_energy = 0.9
	candle.omni_range = 4.0
	candle.shadow_enabled = false
	village.add_child(candle)
	return out


static func _swallowed(village: Node3D, b: HollowmereBatch, terrain: TerrainBuilder, info: Dictionary, w: float, d: float, rng: RandomNumberGenerator) -> void:
	var xf: Transform3D = info["xf"]
	var centre := xf * Vector3(w * 0.62, 2.0, d * 0.3)
	var lane_pt := Vector3(30.5, centre.y, 332.0)
	var grips: Array = []
	for r in info["roof"]:
		grips.append((r as Array)[0])
	for a in info["anchors"]:
		grips.append((a as Array)[0])
	grips = grips.slice(0, 6)
	b.at(centre, 115.0)
	HollowmereProps.flesh_mass(village, b, terrain, centre, 4.3, lane_pt - centre, grips, rng)
	var dir := (lane_pt - centre)
	dir.y = 0.0
	var light := OmniLight3D.new()
	light.name = "MawLight"
	light.position = centre + dir.normalized() * 5.0 + Vector3(0, -0.6, 0)
	light.light_color = Color(1.0, 0.35, 0.15)
	light.light_energy = 1.1
	light.omni_range = 6.0
	light.shadow_enabled = false
	village.add_child(light)


static func _chapel_and_graves(village: Node3D, small: Node3D, b: HollowmereBatch, tv: HollowmereBatch, terrain: TerrainBuilder, rng: RandomNumberGenerator) -> void:
	var chapel := PropKit.chapel(rng, false)
	var cpos := terrain.ground(CHAPEL_POS.x, CHAPEL_POS.y)
	chapel.position = cpos
	chapel.rotation.y = PI  # door faces the village (-Z)
	village.add_child(chapel)
	var cxf := chapel.transform
	# Flesh creeping up the tower and out of the nave; the crown sigil over the door.
	b.at(cpos, 115.0)
	HollowmereProps.flesh_growth(b, cxf * Vector3(1.5, 5.2, 6.9), cxf.basis * Vector3(0.6, 0, 1).normalized(), 1.3, rng)
	HollowmereProps.flesh_growth(b, cxf * Vector3(-2.7, 2.2, -1.0), cxf.basis * Vector3.LEFT, 1.0, rng)
	HollowmereProps.flesh_growth(b, cxf * Vector3(2.7, 1.0, 2.5), cxf.basis * Vector3.RIGHT, 0.9, rng)
	HollowmereProps.curse_sigil(b, cxf * HollowmereProps.xfm(Basis.IDENTITY, Vector3(0, 3.4, 6.92)), 1.0, rng)
	HollowmereProps.blood_trail(b, terrain, Vector2(28.0, 357.5), Vector2(27.2, 352.0), rng, 0.3)
	# Sickly green lantern by the door (light + mesh, pos in region space).
	var lp := cxf * Vector3(1.1, 2.4, 7.2)
	tv.at(lp, 115.0)
	tv.box(RetroMaterials.iron(), HollowmereProps.xfm(Basis.IDENTITY, lp + Vector3(0, 0.45, 0)), Vector3(0.06, 0.5, 0.06), Color(1, 1, 1))
	PartBuilder.box(village, Vector3(0.22, 0.3, 0.22), lp, RetroMaterials.flat(Color(0.4, 0.9, 0.35), 1.6))
	var light := OmniLight3D.new()
	light.name = "LanternLight"
	light.position = lp
	light.light_color = Color(0.45, 0.9, 0.4)
	light.light_energy = 1.3
	light.omni_range = 6.5
	light.shadow_enabled = false
	village.add_child(light)
	# Graveyard east of the chapel and behind it: leaning stones, crosses, statues, open graves.
	var graves: Array[Vector2] = []
	for row in 4:
		for k in 5:
			graves.append(Vector2(33.0 + k * 2.1 + rng.randf_range(-0.4, 0.4), 361.0 + row * 3.3 + rng.randf_range(-0.5, 0.5)))
	for k in 6:
		graves.append(Vector2(21.0 + k * 2.3 + rng.randf_range(-0.4, 0.4), 375.5 + rng.randf_range(-0.6, 0.6)))
	var wood := RetroMaterials.wood()
	for i in graves.size():
		var p := graves[i]
		if not _free(p, 0.6) or _path_dist(p) < 1.6:
			continue
		var g := terrain.ground(p.x, p.y)
		tv.at(g, 115.0)
		b.at(g, 70.0)
		var kind := rng.randi_range(0, 3)
		if kind == 3:
			var lean := Basis(Vector3.UP, rng.randf_range(-0.3, 0.3)) * Basis(Vector3(0, 0, 1), rng.randf_range(-0.35, 0.35))
			tv.box(wood, HollowmereProps.xfm(lean, g + lean * Vector3(0, 0.6, 0)), Vector3(0.1, 1.3, 0.1), Color(1, 1, 1))
			tv.box(wood, HollowmereProps.xfm(lean, g + lean * Vector3(0, 0.95, 0)), Vector3(0.6, 0.1, 0.08), Color(1, 1, 1))
		else:
			HollowmereVillage.gravestone(tv, g, PI + rng.randf_range(-0.2, 0.2), kind, rng)
		# Grave mound, some dug open from below.
		var mound := g + Vector3(0, 0, 1.1)
		if i % 6 == 2:
			HollowmereProps.ground_pool(b, HollowmereProps.organic(), terrain, Vector2(mound.x, mound.z), 0.7, Color(0.02, 0.015, 0.01), Color(0.12, 0.08, 0.05), rng, 0.05, Vector2(0.7, 1.4))
			b.blob(HollowmereProps.organic(), mound + Vector3(0.9, 0.0, 0), Basis.IDENTITY, Vector3(0.45, 0.3, 0.8), 7, 4, HollowmereProps.SOIL, 0.2, rng.randf())
			var hand := mound + Vector3(-0.1, 0.05, -0.3)
			b.tube(HollowmereProps.flesh(), PackedVector3Array([hand - Vector3(0, 0.2, 0), hand + Vector3(0.05, 0.35, 0.05), hand + Vector3(0.12, 0.55, 0.0)]),
				PackedFloat32Array([0.05, 0.04, 0.03]), 4, HollowmereProps.wa(HollowmereProps.SKIN_GREY, 0.3))
		else:
			b.blob(HollowmereProps.organic(), mound + Vector3(0, -0.12, 0), Basis.IDENTITY, Vector3(0.45, 0.22, 0.9), 7, 3, HollowmereProps.SOIL.lightened(0.05), 0.15, rng.randf())
	for p: Vector2 in [Vector2(32.2, 359.6), Vector2(27.5, 378.5)]:
		var st := AssetKit.place(small, "gothic_statue", terrain.ground(p.x, p.y), rng.randf_range(2.6, 3.6), 1.05)
		st.name = "GothicStatue"
		var sb := HollowmereProps.body(village, "StatueCollider")
		HollowmereProps.shape_box(sb, Vector3(1.1, 1.8, 1.1), HollowmereProps.xfm(Basis.IDENTITY, terrain.ground(p.x, p.y) + Vector3(0, 0.9, 0)))
	# Iron railing along the graveyard's lane side, half fallen.
	var iron := RetroMaterials.iron()
	for k in 16:
		var p := Vector2(31.6, 357.5) + Vector2(0.75 * k, 0.0)
		if rng.randf() < 0.18 or not _free(p, 0.2):
			continue
		var g := terrain.ground(p.x, p.y)
		var tilt := Basis(Vector3.RIGHT, rng.randf_range(-0.1, 0.1) + (0.9 if k > 11 else 0.0))
		tv.at(g, 115.0)
		for q in 3:
			var x := float(q) * 0.25 - 0.25
			tv.box(iron, HollowmereProps.xfm(tilt, g + tilt * Vector3(x, 0.65, 0)), Vector3(0.035, 1.3, 0.035), Color(1, 1, 1))
		tv.box(iron, HollowmereProps.xfm(tilt, g + tilt * Vector3(0, 1.1, 0)), Vector3(0.78, 0.04, 0.04), Color(1, 1, 1))
		tv.box(iron, HollowmereProps.xfm(tilt, g + tilt * Vector3(0, 0.25, 0)), Vector3(0.78, 0.04, 0.04), Color(1, 1, 1))


static func _square(village: Node3D, small: Node3D, b: HollowmereBatch, tv: HollowmereBatch, terrain: TerrainBuilder, rng: RandomNumberGenerator, houses: Array) -> void:
	var white := Color(1, 1, 1)
	var g := terrain.ground(SQUARE.x, SQUARE.y)
	tv.at(g, 115.0)
	b.at(g, 70.0)
	var bucket := HollowmereVillage.blood_well(village, tv, b, g, 0.4, rng)
	AssetKit.place(small, "wooden_bucket_01", bucket - Vector3(0, 0.5, 0), 0.3, 1.0)
	# Warm lantern on a post at the well (the square's one light).
	var post := g + Vector3(2.0, 0, -1.6)
	tv.box(HollowmereProps.timber(), HollowmereProps.xfm(Basis.IDENTITY, post + Vector3(0, 1.3, 0)), Vector3(0.14, 2.6, 0.14), white)
	tv.beam(HollowmereProps.timber(), post + Vector3(0, 2.5, 0), post + Vector3(0.6, 2.5, 0), 0.1, 0.1, white)
	AssetKit.place(small, "wooden_lantern_01", post + Vector3(0.55, 1.95, 0), 0.0, 1.0)
	tv.box(HollowmereProps.glow(), HollowmereProps.xfm(Basis.IDENTITY, post + Vector3(0.55, 2.18, 0)), Vector3(0.09, 0.14, 0.09), white)
	var wl := OmniLight3D.new()
	wl.name = "WellLight"
	wl.position = post + Vector3(0.55, 2.2, 0)
	wl.light_color = Color(1.0, 0.66, 0.32)
	wl.light_energy = 1.0
	wl.omni_range = 6.5
	wl.shadow_enabled = false
	village.add_child(wl)
	# Market stalls: produce, and the butcher's hooks.
	var counter := HollowmereVillage.market_stall(village, tv, b, terrain.ground(17.0, 337.0), atan2(SQUARE.x - 17.0, SQUARE.y - 337.0), rng)
	for k in 5:
		var pk := HollowmereProps.roll_pumpkin(rng, 0.2)
		pk["size"] = rng.randf_range(0.3, 0.45)
		HollowmereProps.pumpkin(b, counter + Vector3(rng.randf_range(-0.9, 0.9), 0.0, rng.randf_range(-0.2, 0.2)), pk, 0)
	var bpos := terrain.ground(31.0, 349.0)
	tv.at(bpos, 115.0)
	b.at(bpos, 70.0)
	HollowmereVillage.market_stall(village, tv, b, bpos, atan2(SQUARE.x - 31.0, SQUARE.y - 349.0), rng, true)
	HollowmereProps.ground_pool(b, HollowmereProps.flesh(), terrain, Vector2(30.6, 348.4), 1.0,
			HollowmereProps.wa(HollowmereProps.BLOOD_DARK, 0.0), HollowmereProps.wa(HollowmereProps.BLOOD, 0.0), rng)
	# Gibbet cages: one in the square, one at the village gate.
	for spot: Array in [[Vector2(32.5, 343.5), 0.3], [Vector2(15.8, 318.5), PI]]:
		var p: Vector2 = spot[0]
		var gp := terrain.ground(p.x, p.y)
		tv.at(gp, 115.0)
		b.at(gp, 115.0)
		var hang := HollowmereProps.gallows(village, tv, gp, float(spot[1]))
		HollowmereProps.gibbet_cage(tv, b, hang, 0.5, rng)
		HollowmereProps.ground_pool(b, HollowmereProps.flesh(), terrain, Vector2(hang.x, hang.z), 0.6,
				HollowmereProps.wa(HollowmereProps.BLOOD_DARK, 0.0), HollowmereProps.wa(HollowmereProps.BLOOD, 0.0), rng)
	# The smashed cart, its load of pumpkins burst across the lane.
	var cart := PropKit.cart_wreck(rng)
	cart.position = terrain.ground(15.0, 329.5)
	cart.rotation.y = 0.9
	small.add_child(cart)
	b.at(cart.position, 70.0)
	for k in 7:
		var p := Vector2(16.5, 330.5) + Vector2(rng.randf_range(-1.5, 2.0), rng.randf_range(-1.5, 1.5))
		if _path_dist(p) < 1.0:
			continue
		var pk := HollowmereProps.roll_pumpkin(rng, 0.15)
		pk["size"] = rng.randf_range(0.45, 0.8)
		pk["kind"] = 3 if k % 2 == 0 else int(pk["kind"])
		HollowmereProps.pumpkin(b, terrain.ground(p.x, p.y), pk, 0)
	HollowmereProps.blood_trail(b, terrain, Vector2(16.0, 331.0), Vector2(19.5, 335.0), rng)
	AssetKit.place(small, "rusted_wheel_rim_01", terrain.ground(13.6, 331.6) + Vector3(0, 0.03, 0), 0.6, 1.4).rotation.x = PI * 0.5
	# Blood from the square into the houses, pools, the clothes of the vanished.
	for hi: int in [0, 3, 1]:
		var door: Vector3 = (houses[hi] as Dictionary)["door"]
		var from := SQUARE + (Vector2(door.x, door.z) - SQUARE).normalized() * 2.5
		b.at(door, 70.0)
		HollowmereProps.blood_trail(b, terrain, from, Vector2(door.x, door.z), rng)
	for k in 10:
		var a := rng.randf() * TAU
		var p := SQUARE + Vector2(cos(a), sin(a)) * rng.randf_range(2.0, 10.0)
		b.at(terrain.ground(p.x, p.y), 70.0)
		HollowmereProps.ground_pool(b, HollowmereProps.flesh(), terrain, p, rng.randf_range(0.3, 1.0),
				HollowmereProps.wa(HollowmereProps.BLOOD_DARK, 0.0), HollowmereProps.wa(HollowmereProps.BLOOD, 0.0), rng, 0.09)
	b.at(g, 70.0)
	for k in 9:
		var a := TAU * k / 9.0 + rng.randf_range(-0.2, 0.2)
		var p := SQUARE + Vector2(cos(a), sin(a)) * rng.randf_range(2.2, 3.5)
		if not _free(p, 0.5):
			continue
		_clothes(b, terrain.ground(p.x, p.y), rng)
	_kit_props(small, tv, terrain, rng, houses)


static func _clothes(b: HollowmereBatch, pos: Vector3, rng: RandomNumberGenerator) -> void:
	var col: Color = HollowmereProps.CLOTH[rng.randi() % HollowmereProps.CLOTH.size()]
	for i in 3:
		var off := Vector3(rng.randf_range(-0.3, 0.3), 0.07 + i * 0.04, rng.randf_range(-0.3, 0.3))
		var basis := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3(0, 0, 1), rng.randf_range(-0.1, 0.1))
		b.box(HollowmereProps.organic(), HollowmereProps.xfm(basis, pos + off), Vector3(rng.randf_range(0.5, 0.9), 0.05, rng.randf_range(0.4, 0.75)), col.darkened(i * 0.15))
	b.box(HollowmereProps.organic(), HollowmereProps.xfm(Basis(Vector3.UP, rng.randf() * TAU), pos + Vector3(0.4, 0.08, 0.1)), Vector3(0.12, 0.1, 0.26), Color(0.12, 0.08, 0.05))


## Scanned kit props round the houses and the square.
static func _kit_props(small: Node3D, tv: HollowmereBatch, terrain: TerrainBuilder, rng: RandomNumberGenerator, houses: Array) -> void:
	var picks := ["wine_barrel_01", "wooden_crate_01", "wooden_crate_02", "wooden_bucket_01", "wine_barrel_01", "wooden_crate_02"]
	for i in houses.size():
		var info: Dictionary = houses[i]
		var xf: Transform3D = info["xf"]
		var h: Array = HOUSES[i]
		var w: float = h[4]
		var d: float = h[5]
		for k in rng.randi_range(1, 3):
			var lp := Vector3((1.0 if k % 2 == 0 else -1.0) * (w * 0.5 + 0.55), 0.0, rng.randf_range(-d * 0.3, d * 0.4))
			var wp := xf * lp
			if _path_dist(Vector2(wp.x, wp.z)) < 1.7 or not _free(Vector2(wp.x, wp.z), 0.6):
				continue
			var model: String = picks[(i + k) % picks.size()]
			var node := AssetKit.place(small, model, terrain.ground(wp.x, wp.z), rng.randf() * TAU, rng.randf_range(0.95, 1.1))
			if model == "wine_barrel_01" and rng.randf() < 0.35:
				node.rotation = Vector3(PI * 0.5, rng.randf() * TAU, 0)
				node.position.y += 0.38
	# Square furniture: benches (one kicked over), a table on its side, stools, a spinning wheel.
	var bench := AssetKit.place(small, "painted_wooden_bench", terrain.ground(20.5, 340.0), 1.1, 1.0)
	bench.rotation.z = 0.0
	var tipped := AssetKit.place(small, "painted_wooden_bench", terrain.ground(27.6, 346.4) + Vector3(0, 0.25, 0), 2.4, 1.0)
	tipped.rotation.x = PI * 0.5
	var table := AssetKit.place(small, "WoodenTable_01", terrain.ground(19.6, 333.8) + Vector3(0, 0.33, 0), 0.4, 1.0)
	table.rotation.x = -PI * 0.5
	AssetKit.place(small, "wooden_stool_01", terrain.ground(21.0, 335.2), 0.8, 1.0)
	AssetKit.place(small, "spinning_wheel_01", terrain.ground(8.4, 338.0), 1.4, 1.0)
	AssetKit.place(small, "wooden_ladder", terrain.ground(15.0, 351.0), 0.8, 1.6).rotation.x = -0.3
	for p: Vector2 in [Vector2(34.0, 345.0), Vector2(35.0, 346.0), Vector2(18.5, 324.5), Vector2(8.0, 327.5)]:
		if _path_dist(p) > 1.5 and _free(p, 0.5):
			AssetKit.place(small, picks[rng.randi() % picks.size()], terrain.ground(p.x, p.y), rng.randf() * TAU, 1.0)
	# Lantern posts at the village gate.
	for p: Vector2 in [Vector2(17.6, 320.5), Vector2(23.0, 321.5)]:
		var g := terrain.ground(p.x, p.y)
		tv.at(g, 115.0)
		tv.box(HollowmereProps.timber(), HollowmereProps.xfm(Basis.IDENTITY, g + Vector3(0, 1.1, 0)), Vector3(0.14, 2.2, 0.14), Color(1, 1, 1))
		AssetKit.place(small, "wooden_lantern_01", g + Vector3(0, 2.2, 0), rng.randf() * TAU, 1.0)


static func _grass(region: Node3D, terrain: TerrainBuilder, rng: RandomNumberGenerator) -> void:
	var mat := load(GRASS_MAT) as Material
	if mat == null:
		return
	var accept := func(p: Vector2) -> bool:
		if _path_dist(p) <= 2.0 or p.distance_to(SQUARE) < 8.0 or _house_hit(p, 0.0):
			return false
		if p.distance_to(CHAPEL_POS) < 7.0:
			return false
		if p.y > FIELD_Z0 - 2.0 and p.y < FIELD_Z1 + 2.0 and absf(p.x - _road_x(p.y)) < 25.0:
			return false  # the furrows are bare soil
		return true
	GrassScatter.scatter(region, terrain, Rect2(-34.0, 226.0, 100.0, 170.0), 1500, mat, Vector2(0.8, 0.6), rng, accept)


static func _markers(region: Node3D, terrain: TerrainBuilder) -> void:
	var markers := _group(region, "Markers")
	var spots := _marker_spots()
	for id: String in spots:
		_marker(markers, id, terrain, spots[id])
	var village := region.get_node("Village")
	var i := 1
	for light_name: String in ["LanternLight", "CandleLight", "WellLight", "MawLight"]:
		var l := village.get_node_or_null(light_name) as Node3D
		if l:
			var m := Marker3D.new()
			m.name = "Light_%d" % i
			m.position = l.position
			markers.add_child(m)
		i += 1
	# Covers the fields (the hero view) and the village.
	var trig := _marker(markers, "Trigger", terrain, Vector2(20.0, 305.0))
	trig.set_meta("radius", 66.0)


static func _marker(parent: Node3D, marker_name: String, terrain: TerrainBuilder, xz: Vector2) -> Marker3D:
	var m := Marker3D.new()
	m.name = marker_name
	m.position = terrain.ground(xz.x, xz.y) + Vector3(0, 0.1, 0)
	parent.add_child(m)
	return m
