@tool
class_name MeadowBuilder
extends RefCounted
## The Moonlit Meadows outside the walls of Valdron and the plains between the
## villages (task U10). Two hero views from the spawn (WAKE, player feet):
##   - towards the castle (-Z): the meadow runs up to the cursed walls, the
##     feast spilling out of the smashed gate (OuterWardBlockout), a great dead
##     tree with crows framing the left, the planted swords of the fallen;
##   - down the road (+Z): long silver-green grass under the moon, the wayside
##     shrine with one candle still burning, a lone dead tree, the ruined
##     shepherd's hut, a ring of standing stones, low dry-stone field walls
##     leading the eye to the gibbet at the crossroads, low mist, and far beyond
##     the painted silhouettes of Hollowmere's spire and the Thornfield farm.
## The plains add believable fields (grass patches, rushes, weeds, walls and
## hedges) and landmarks along the roads: milestones, a cairn, broken carts.
## Output: Node3D "Meadow" with Landmarks (merged, culled at 110 m), Details
## (merged, 60 m), Props (colliders + loose kit pieces, merged by the caller),
## Grass (chunks, 60 m), Far (silhouette cards) and the lights ShrineCandle.

const WAKE := Vector2(1.2, 29.0)
const SHRINE := Vector2(3.9, 40.5)
const GREAT_TREE := Vector2(-8.5, 47.0)
const FRAME_TREE := Vector2(-11.5, 20.5)
const STONES := Vector2(17.5, 55.0)
const HUT := Vector2(-15.5, 70.0)
const GIBBET := Vector2(-5.6, 67.0)
const SWORDS := Vector2(-15.0, 22.0)
## Gate opening and the feast spill in front of it (sparse, trampled grass).
const GATE_AREA := Rect2(-9.0, 10.0, 18.0, 17.5)
const SMALL_RANGE := 60.0
const LANDMARK_RANGE := 110.0
const GRASS_RANGE := 60.0


static func build(root: Node3D, terrain: TerrainBuilder, rng: RandomNumberGenerator) -> Node3D:
	var meadow := Node3D.new()
	meadow.name = "Meadow"
	root.add_child(meadow)
	var landmarks := _group(meadow, "Landmarks")
	var details := _group(meadow, "Details")
	var props := _group(meadow, "Props")
	var keep_out: Array[Vector3] = []
	_build_wake_area(landmarks, details, props, terrain, rng, keep_out)
	_build_road_view(meadow, landmarks, details, props, terrain, rng, keep_out)
	_build_plains(landmarks, details, props, terrain, rng, keep_out)
	_build_road(details, terrain, rng)
	_build_far(meadow, terrain, rng)
	_build_grass(meadow, terrain, rng, keep_out)
	_merge(landmarks, LANDMARK_RANGE)
	_merge(details, SMALL_RANGE)
	return meadow


# --- Behind the knight: the meadow under the walls -------------------------------

static func _build_wake_area(landmarks: Node3D, details: Node3D, props: Node3D, terrain: TerrainBuilder,
		rng: RandomNumberGenerator, keep_out: Array[Vector3]) -> void:
	# The knight's sleeping place: flattened cloak, an empty jug, a goblet he took.
	var cloth := RetroMaterials.valdron_cloth()
	PartBuilder.box(details, Vector3(1.0, 0.03, 1.8), Vector3(1.2, 0.02, 30.0), cloth, Vector3(0.0, 0.3, 0.0))
	PartBuilder.box(details, Vector3(0.5, 0.06, 0.7), Vector3(1.55, 0.04, 29.1), cloth, Vector3(0.1, 0.9, 0.05))
	PartBuilder.cylinder(details, 0.08, 0.12, 0.3, Vector3(2.2, 0.1, 30.6), RetroMaterials.flat(Color(0.3, 0.22, 0.14)), 6, Vector3(PI * 0.5, 1.0, 0.0))
	var goblet := AssetKit.place(details, "brass_goblets", Vector3(0.35, 0.05, 27.9), 0.0, 1.0, "brass_goblet_01")
	goblet.rotation = Vector3(0.0, 0.7, PI * 0.5)
	ThornfieldProps.splat(details, MeadowProps.wine_mat(), Vector3(0.15, 0.025, 27.6), 0.55, rng, 1.6)
	keep_out.append(Vector3(1.2, 30.0, 1.3))
	# A great dead tree frames the castle on the left, crows on its low bough.
	var tree := MeadowProps.lone_tree(9.5, Vector2(-0.5, 0.2), rng)
	tree.position = terrain.ground(FRAME_TREE.x, FRAME_TREE.y)
	tree.rotation.y = 0.6
	landmarks.add_child(tree)
	keep_out.append(Vector3(FRAME_TREE.x, FRAME_TREE.y, 1.4))
	_crows_on(details, tree.transform * (tree.get_meta("bough") as Vector3), 3, rng)
	# Swords planted for the soldiers who fell against Loris, a few with helms.
	var iron := RetroMaterials.iron()
	for i in 16:
		var q := SWORDS + Vector2(rng.randf_range(-4.5, 4.5), rng.randf_range(-3.0, 3.0))
		var g := terrain.ground(q.x, q.y)
		var sword := PartBuilder.pivot(details, "Sword", g)
		sword.rotation = Vector3(rng.randf_range(-0.22, 0.22), rng.randf() * TAU, rng.randf_range(-0.22, 0.22))
		PartBuilder.box(sword, Vector3(0.06, 1.0, 0.018), Vector3(0, 0.38, 0), iron)
		PartBuilder.box(sword, Vector3(0.34, 0.05, 0.05), Vector3(0, 0.9, 0), iron)
		PartBuilder.box(sword, Vector3(0.04, 0.22, 0.04), Vector3(0, 1.03, 0), RetroMaterials.wood())
		PartBuilder.sphere(sword, 0.04, Vector3(0, 1.16, 0), iron, false, 5)
		if i % 4 == 0:
			var helm := PartBuilder.sphere(sword, 0.15, Vector3(0, 1.08, 0), iron, true, 7)
			helm.rotation.z = 0.3
		if i % 5 == 1:
			PartBuilder.box(sword, Vector3(0.12, 0.45, 0.01), Vector3(0.02, 0.85, 0.03), RetroMaterials.rag(), Vector3(0, 0, 0.1))
	keep_out.append(Vector3(SWORDS.x, SWORDS.y, 4.0))
	# The festival cart, overturned on the verge, sacks and straw spilled.
	var cart := PropKit.cart_wreck(rng)
	cart.position = terrain.ground(5.6, 19.5)
	cart.rotation.y = 0.4
	props.add_child(cart)
	keep_out.append(Vector3(5.6, 19.5, 2.4))
	# Rocks bedded in the grass at the wall foot and in the meadow.
	var rocks := [[Vector2(-21.0, 14.2), 0.9], [Vector2(13.5, 14.0), 0.7], [Vector2(24.0, 22.0), 1.1], [Vector2(-28.0, 30.0), 1.2],
		[Vector2(9.0, 25.0), 0.5], [Vector2(-6.0, 31.0), 0.45]]
	for r in rocks:
		var q: Vector2 = r[0]
		_rock(landmarks, props, terrain, q, float(r[1]), rng, keep_out)
	var side := PropKit.dead_tree(6.5, rng)
	side.position = terrain.ground(26.0, 17.0)
	landmarks.add_child(side)
	keep_out.append(Vector3(26.0, 17.0, 1.0))


# --- Down the road: the composed meadow view --------------------------------------

static func _build_road_view(meadow: Node3D, landmarks: Node3D, details: Node3D, props: Node3D, terrain: TerrainBuilder,
		rng: RandomNumberGenerator, keep_out: Array[Vector3]) -> void:
	# Wayside shrine facing the road, one candle still alight.
	var shrine := MeadowProps.shrine(rng)
	shrine.position = terrain.ground(SHRINE.x, SHRINE.y)
	var to_road := Vector2(0.4, SHRINE.y - 4.0) - SHRINE
	shrine.rotation.y = atan2(to_road.x, to_road.y)
	landmarks.add_child(shrine)
	keep_out.append(Vector3(SHRINE.x, SHRINE.y, 1.3))
	var candle := FlickerLight.new()
	candle.name = "ShrineCandle"
	candle.light_color = Color(0.95, 0.78, 0.45)
	candle.base_energy = 0.7
	candle.flicker_amount = 0.3
	candle.gutter_chance = 0.04
	candle.omni_range = 4.5
	candle.shadow_enabled = false
	candle.position = shrine.transform * (shrine.get_meta("flame") as Vector3)
	meadow.add_child(candle)
	_crows_on(details, shrine.transform * Vector3(0.0, 2.75, 0.0), 1, rng)
	# The lone great dead tree on the left of the road.
	var tree := ThornfieldProps.great_dead_tree(11.5, Vector2(-0.6, 0.4), rng)
	tree.position = terrain.ground(GREAT_TREE.x, GREAT_TREE.y)
	tree.rotation.y = 2.1
	landmarks.add_child(tree)
	keep_out.append(Vector3(GREAT_TREE.x, GREAT_TREE.y, 1.8))
	_crows_on(details, tree.transform * (tree.get_meta("low_bough") as Vector3), 2, rng)
	# Ring of standing stones on the rise to the right.
	MeadowProps.stone_circle(landmarks, terrain, STONES, 4.6, rng)
	keep_out.append(Vector3(STONES.x, STONES.y, 6.0))
	for i in 3:
		var a := TAU * i / 3.0 + 0.4
		_crows_on(details, terrain.ground(STONES.x + cos(a) * 4.6, STONES.y + sin(a) * 4.6) + Vector3(0, 2.9, 0), 1, rng)
	# The ruined shepherd's hut on the left, its door turned to the road.
	var hut := MeadowProps.shepherd_hut(rng)
	hut.position = terrain.ground(HUT.x, HUT.y)
	hut.rotation.y = atan2(-HUT.x, 2.0) + 0.3
	landmarks.add_child(hut)
	keep_out.append(Vector3(HUT.x, HUT.y, 3.2))
	_crows_on(details, hut.transform * Vector3(-1.4, 1.5, -1.6), 2, rng)
	# Gibbet at the crossroads, crows on the arm.
	var gibbet := MeadowProps.gibbet(rng)
	gibbet.position = terrain.ground(GIBBET.x, GIBBET.y)
	gibbet.rotation.y = 0.35
	landmarks.add_child(gibbet)
	keep_out.append(Vector3(GIBBET.x, GIBBET.y, 1.2))
	_crows_on(details, gibbet.transform * (gibbet.get_meta("perch") as Vector3), 2, rng)
	# Field walls leading the eye down the road; a hedge closes the hut's field.
	var walls := [
		[[Vector2(5.8, 33.5), Vector2(8.0, 44.0), Vector2(10.5, 52.0), Vector2(11.5, 60.0)], 0.15],
		[[Vector2(11.5, 60.0), Vector2(26.0, 64.0), Vector2(42.0, 66.0)], 0.25],
		[[Vector2(-4.2, 52.0), Vector2(-8.0, 58.0), Vector2(-10.5, 63.5)], 0.2],
		[[Vector2(-30.0, 40.0), Vector2(-17.0, 44.5), Vector2(-12.5, 52.0)], 0.3],
	]
	for w in walls:
		var pts := PackedVector2Array(w[0])
		landmarks.add_child(MeadowProps.dry_stone_wall(terrain, pts, float(w[1]), rng))
	landmarks.add_child(MeadowProps.hedge(terrain, PackedVector2Array([Vector2(-44.0, 52.0), Vector2(-32.0, 56.0), Vector2(-27.0, 70.0), Vector2(-24.0, 82.0)]), 0.15, rng))
	# Scattered rocks and two more lone trees in the middle distance.
	var rocks := [[Vector2(8.6, 37.0), 0.5], [Vector2(-6.5, 57.0), 0.8], [Vector2(22.0, 46.0), 1.0], [Vector2(-15.0, 33.0), 0.7],
		[Vector2(30.0, 54.0), 1.3], [Vector2(-38.0, 64.0), 1.4], [Vector2(3.5, 74.0), 0.8], [Vector2(-12.0, 80.0), 1.1]]
	for r in rocks:
		_rock(landmarks, props, terrain, r[0], float(r[1]), rng, keep_out)
	var t2 := MeadowProps.lone_tree(7.0, Vector2(0.3, -0.4), rng)
	t2.position = terrain.ground(27.0, 77.0)
	landmarks.add_child(t2)
	var t3 := MeadowProps.lone_tree(8.5, Vector2(0.5, 0.2), rng)
	t3.position = terrain.ground(-35.0, 86.0)
	t3.rotation.y = -0.7
	landmarks.add_child(t3)
	_crows_on(details, t3.transform * (t3.get_meta("bough") as Vector3), 2, rng)
	# Low mist lying in the hollows of the meadow.
	for m in [[Vector3(-22.0, 0, 62.0), Vector2(40, 3.0)], [Vector3(24.0, 0, 72.0), Vector2(46, 3.4)], [Vector3(-2.0, 0, 92.0), Vector2(64, 4.2)],
			[Vector3(-40.0, 0, 44.0), Vector2(30, 2.6)], [Vector3(34.0, 0, 44.0), Vector2(30, 2.4)], [Vector3(6.0, 0, 52.0), Vector2(26, 2.0)]]:
		var p: Vector3 = m[0]
		MeadowProps.mist_bank(meadow, terrain.ground(p.x, p.z), m[1])


# --- The plains between the villages ---------------------------------------------

static func _build_plains(landmarks: Node3D, details: Node3D, props: Node3D, terrain: TerrainBuilder,
		rng: RandomNumberGenerator, keep_out: Array[Vector3]) -> void:
	# Milestones along the king's road, counting the miles from Valdron.
	var road := OverworldSpec.sample_path(OverworldSpec.MAIN_ROAD, 1.0)
	var marks := [36, 84, 132, 178, 224, 268]
	for i in marks.size():
		var k: int = mini(marks[i], road.size() - 2)
		var p: Vector2 = road[k]
		var dir := (road[k + 1] - p).normalized()
		var q := p + Vector2(dir.y, -dir.x) * 2.6
		var stone := MeadowProps.milestone(i + 1, rng)
		stone.position = terrain.ground(q.x, q.y)
		stone.rotation.y = atan2(dir.x, dir.y) + PI * 0.5
		landmarks.add_child(stone)
		keep_out.append(Vector3(q.x, q.y, 0.6))
	# Field boundaries: dry-stone walls and overgrown hedges (none cross a road).
	var walls := [
		[[Vector2(-6.0, 74.0), Vector2(-11.0, 100.0), Vector2(-16.5, 112.0)], 0.2],
		[[Vector2(-20.0, 140.0), Vector2(-12.0, 175.0), Vector2(-6.0, 215.0)], 0.25],
		[[Vector2(14.0, 200.0), Vector2(20.0, 220.0), Vector2(26.0, 240.0)], 0.2],
	]
	for w in walls:
		landmarks.add_child(MeadowProps.dry_stone_wall(terrain, PackedVector2Array(w[0]), float(w[1]), rng))
	var hedges := [
		[Vector2(8.0, 82.0), Vector2(12.0, 110.0), Vector2(16.0, 140.0), Vector2(14.0, 175.0)],
		[Vector2(-30.0, 100.0), Vector2(-24.0, 86.0)],
		[Vector2(30.0, 186.0), Vector2(22.0, 200.0), Vector2(14.0, 200.0)],
	]
	for h in hedges:
		landmarks.add_child(MeadowProps.hedge(terrain, PackedVector2Array(h), 0.2, rng))
	# Broken carts on the verge, a cairn, lone trees, rocks.
	for c in [[Vector2(-15.0, 106.0), 1.1], [Vector2(9.5, 186.0), -0.6]]:
		var q: Vector2 = c[0]
		var cart := PropKit.cart_wreck(rng)
		cart.position = terrain.ground(q.x, q.y)
		cart.rotation.y = float(c[1])
		props.add_child(cart)
		keep_out.append(Vector3(q.x, q.y, 2.4))
	var spill := terrain.ground(10.6, 184.5)
	AssetKit.place(details, "wooden_barrels_01", spill, 0.8, 1.0, "wooden_barrels_01_barrel01").rotation = Vector3(0, 0.8, PI * 0.5)
	AssetKit.place(details, "wooden_crate_01", spill + Vector3(1.2, 0, 1.4), 1.9)
	var cairn := MeadowProps.cairn(rng)
	cairn.position = terrain.ground(12.0, 150.0)
	landmarks.add_child(cairn)
	keep_out.append(Vector3(12.0, 150.0, 1.0))
	for t in [[Vector2(-24.0, 130.0), 8.0], [Vector2(24.0, 118.0), 6.5], [Vector2(-18.0, 228.0), 9.0]]:
		var q: Vector2 = t[0]
		var tree := MeadowProps.lone_tree(float(t[1]), Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)), rng)
		tree.position = terrain.ground(q.x, q.y)
		landmarks.add_child(tree)
		keep_out.append(Vector3(q.x, q.y, 1.0))
	for i in 7:
		var q := Vector2(rng.randf_range(-60.0, 60.0), rng.randf_range(90.0, 245.0))
		if _road_distance(q) < 5.0 or not _plain(terrain, q):
			continue
		_rock(landmarks, props, terrain, q, rng.randf_range(0.6, 1.4), rng, keep_out)


# --- The road itself: wheel ruts, puddles, edge stones ---------------------------

static func _build_road(details: Node3D, terrain: TerrainBuilder, rng: RandomNumberGenerator) -> void:
	var ruts := RetroMaterials.flat(Color(0.1, 0.085, 0.07))
	var path := OverworldSpec.sample_path(OverworldSpec.MAIN_ROAD, 1.2)
	for i in path.size() - 1:
		var p: Vector2 = path[i]
		if p.y < 12.5:
			continue
		var dir := (path[i + 1] - p).normalized()
		var nrm := Vector2(dir.y, -dir.x)
		var yaw := atan2(dir.x, dir.y)
		# Worn wheel ruts: broken dark streaks, not rails.
		for side: float in [-0.75, 0.75]:
			if rng.randf() < 0.45:
				continue
			var q := p + nrm * (side + rng.randf_range(-0.08, 0.08)) + dir * rng.randf_range(-0.2, 0.2)
			PartBuilder.box(details, Vector3(rng.randf_range(0.14, 0.24), 0.02, rng.randf_range(0.5, 1.0)), terrain.ground(q.x, q.y) - Vector3(0, 0.003, 0), ruts,
				Vector3(0, yaw + rng.randf_range(-0.08, 0.08), 0))
		if rng.randf() < 0.09:
			var q := p + nrm * rng.randf_range(-0.9, 0.9)
			ThornfieldProps.splat(details, ThornfieldProps.puddle_mat(), terrain.ground(q.x, q.y) + Vector3(0, 0.03, 0), rng.randf_range(0.8, 1.5), rng, rng.randf_range(1.2, 2.2), yaw)
		if rng.randf() < 0.16:
			var q := p + nrm * (2.0 if rng.randf() < 0.5 else -2.0) * rng.randf_range(0.9, 1.15)
			var s := rng.randf_range(0.18, 0.32)
			PartBuilder.box(details, Vector3(s * 1.4, s * 0.6, s), terrain.ground(q.x, q.y) + Vector3(0, s * 0.15, 0), MeadowProps.lichen_stone(),
				Vector3(rng.randf_range(-0.3, 0.3), rng.randf() * TAU, rng.randf_range(-0.3, 0.3)))


# --- Far silhouettes ---------------------------------------------------------------

## Painted cards of Hollowmere and the Thornfield farm on their true bearings
## from the spawn: the farm ~106 m out, between the first two rings of the
## horizon backdrop (95 / 120 m) so the near hills hide its feet; Hollowmere
## (behind a tall ridge of the first ring) in front of it at ~93 m, painted in
## a paler haze. A little larger than the real places would appear. They
## dissolve as the player walks closer.
static func _build_far(meadow: Node3D, terrain: TerrainBuilder, rng: RandomNumberGenerator) -> void:
	var far := _group(meadow, "Far")
	# [kind, real place, card distance, enlargement over the true angular size, tone]
	var places := [["village", Vector2(22.0, 338.0), 93.0, 2.2, "haze"], ["farm", Vector2(-122.0, 152.0), 106.0, 1.5, "deep"]]
	for p in places:
		var target: Vector2 = p[1]
		var dist: float = p[2]
		var to := target - WAKE
		var at := WAKE + to.normalized() * dist
		var card := MeadowProps.far_card(str(p[0]), str(p[4]), rng)
		card.position = Vector3(at.x, _skyline(terrain, at) - 0.8, at.y)
		card.rotation.y = atan2(-to.x, -to.y)
		card.scale = Vector3.ONE * (dist / to.length() * float(p[3]))
		card.visibility_range_end = 165.0
		far.add_child(card)


## Height at `at` of the skyline seen from the spawn: the highest terrain
## elevation angle along that bearing out to the far plane, projected to `at`
## (the card's foot then sits on the far ridge line, a place beyond the hills).
static func _skyline(terrain: TerrainBuilder, at: Vector2) -> float:
	var eye := 1.6
	var dir := (at - WAKE).normalized()
	var best := -INF
	for k in range(2, 34):
		var d := k * 5.0
		var q := WAKE + dir * d
		best = maxf(best, (terrain.height_at(q.x, q.y) - eye) / d)
	return eye + best * WAKE.distance_to(at)


# --- Grass -------------------------------------------------------------------------

static func _build_grass(meadow: Node3D, terrain: TerrainBuilder, rng: RandomNumberGenerator, keep_out: Array[Vector3]) -> void:
	var patch := FastNoiseLite.new()
	patch.seed = 9091
	patch.frequency = 0.035
	var damp := FastNoiseLite.new()
	damp.seed = 313
	damp.frequency = 0.06
	var tufts: Array = []
	# Meadow outside the walls (dense, long) and the plains beyond (patchier).
	_scatter(tufts, terrain, rng, patch, damp, keep_out, Rect2(-72.0, 12.5, 144.0, 60.0), 0.9, true)
	_scatter(tufts, terrain, rng, patch, damp, keep_out, Rect2(-80.0, 72.5, 160.0, 177.5), 1.15, false)
	# The road: a frayed fringe along both edges and a low crown between the ruts.
	for line in [OverworldSpec.MAIN_ROAD, OverworldSpec.FOREST_PATH]:
		var walk := OverworldSpec.sample_path(line, 0.7)
		for i in walk.size() - 1:
			var p: Vector2 = walk[i]
			if p.y < 12.5 or p.y > 250.0 or GATE_AREA.has_point(p):
				continue
			var dir := (walk[i + 1] - p).normalized()
			var nrm := Vector2(dir.y, -dir.x)
			var yaw := atan2(-dir.y, dir.x)
			for side: float in [-1.0, 1.0]:
				if rng.randf() < 0.85:
					var q := p + nrm * side * rng.randf_range(1.55, 2.1) + dir * rng.randf_range(-0.3, 0.3)
					tufts.append([terrain.ground(q.x, q.y) - Vector3(0, 0.03, 0), yaw + rng.randf_range(-0.6, 0.6), rng.randf_range(0.6, 0.9),
						rng.randf_range(0.3, 0.55), rng.randf_range(0.35, 0.6), MeadowProps.KIND_GRASS])
			if rng.randf() < 0.45:
				var q := p + dir * rng.randf_range(-0.3, 0.3) + nrm * rng.randf_range(-0.15, 0.15)
				tufts.append([terrain.ground(q.x, q.y) - Vector3(0, 0.02, 0), yaw + rng.randf_range(-0.4, 0.4), rng.randf_range(0.45, 0.7),
					rng.randf_range(0.14, 0.28), 0.35, MeadowProps.KIND_GRASS])
	# Courtyard: sparse short grass between the cobbles and the walls.
	var placed := 0
	var tries := 0
	while placed < 520 and tries < 4000:
		tries += 1
		var p := Vector2(rng.randf_range(-38.0, 38.0), rng.randf_range(-38.0, 8.0))
		if absf(p.x) < 9.0 and p.y > -22.0:
			continue  # trampled feast grounds
		tufts.append([Vector3(p.x, -0.03, p.y), rng.randf() * TAU, rng.randf_range(0.5, 0.8), rng.randf_range(0.2, 0.42), rng.randf_range(0.25, 0.5),
			MeadowProps.KIND_WEED if rng.randf() < 0.2 else MeadowProps.KIND_GRASS])
		placed += 1
	MeadowProps.grass_chunks(meadow, tufts, GRASS_RANGE)
	print("Meadow grass: %d tufts" % tufts.size())


## Jittered-grid scatter over `area` with spacing `step`. Long grass in swathes,
## shorter cropped patches, dark rushes in the damp hollows, sparse weeds.
static func _scatter(tufts: Array, terrain: TerrainBuilder, rng: RandomNumberGenerator, patch: FastNoiseLite, damp: FastNoiseLite,
		keep_out: Array[Vector3], area: Rect2, step: float, meadow: bool) -> void:
	var nx := int(area.size.x / step)
	var nz := int(area.size.y / step)
	for iz in nz:
		for ix in nx:
			var p := area.position + Vector2((ix + rng.randf()) * step, (iz + rng.randf()) * step)
			var n := patch.get_noise_2d(p.x, p.y)
			var wet := damp.get_noise_2d(p.x, p.y)
			var keep := 0.85 + n * 0.25
			if meadow:
				# Denser around the spawn so the first view is full of grass.
				keep *= 1.0 + 0.5 * exp(-p.distance_to(WAKE) / 14.0)
				if GATE_AREA.has_point(p):
					keep *= 0.2 + 0.4 * smoothstep(19.0, 27.5, p.y)
			else:
				keep *= 0.55 + 0.45 * smoothstep(-0.3, 0.4, n)
				if not _plain(terrain, p):
					continue
			if rng.randf() > keep:
				continue
			var rd := _road_distance(p)
			if rd < 2.0 + n * 0.4 or _blocked(p, keep_out):
				continue
			var tall := 0.6 + 0.45 * smoothstep(-0.35, 0.45, n)
			var kind := MeadowProps.KIND_GRASS
			var h := rng.randf_range(0.75, 1.05) * tall
			var w := rng.randf_range(0.85, 1.2)
			if wet > 0.38 and rng.randf() < 0.75:
				kind = MeadowProps.KIND_RUSH
				h = rng.randf_range(0.55, 0.85)
				w = rng.randf_range(0.5, 0.75)
			elif rng.randf() < 0.07:
				kind = MeadowProps.KIND_WEED
				h = rng.randf_range(0.65, 0.95)
			if meadow and GATE_AREA.has_point(p):
				h *= 0.5  # trampled by the crowd that fled the feast
			var bright := clampf(0.5 + n * 0.45 - maxf(wet, 0.0) * 0.3 + rng.randf_range(-0.12, 0.12), 0.15, 1.0)
			# Most tufts face across the road so the road views see them full on.
			var yaw := rng.randf_range(-0.8, 0.8) if rng.randf() < 0.6 else rng.randf() * TAU
			tufts.append([terrain.ground(p.x, p.y) - Vector3(0, 0.05, 0), yaw, w, h, bright, kind])
			if meadow and rng.randf() < 0.035:
				# A pale flowering weed standing above the grass.
				tufts.append([terrain.ground(p.x + 0.3, p.y + 0.2) - Vector3(0, 0.05, 0), rng.randf() * TAU, 0.5, h * 1.25, 0.7, MeadowProps.KIND_WEED])


## Open plain: not road, pale dry field or forest floor on the terrain paint.
static func _plain(terrain: TerrainBuilder, p: Vector2) -> bool:
	var spec := terrain.spec
	var i := terrain.cols * int((p.y - spec.min_corner.y) / spec.cell) + int((p.x - spec.min_corner.x) / spec.cell)
	var c: Color = terrain.paint[clampi(i, 0, terrain.paint.size() - 1)]
	return c.r < 0.3 and c.g < 0.45 and c.b < 0.45


# --- Helpers -----------------------------------------------------------------------

static func _rock(landmarks: Node3D, props: Node3D, terrain: TerrainBuilder, q: Vector2, size: float, rng: RandomNumberGenerator,
		keep_out: Array[Vector3]) -> void:
	var g := terrain.ground(q.x, q.y)
	var model := "rock_moss_set_01" if rng.randf() < 0.5 else "rock_moss_set_02"
	if size > 1.2 and rng.randf() < 0.4:
		model = "namaqualand_boulder_02"
	var piece := AssetKit.random_piece(model, rng)
	var node := AssetKit.place(landmarks, model, g - Vector3(0, 0.12 * size, 0), rng.randf() * TAU, size, piece)
	node.name = "Rock"
	var body := ThornfieldProps.new_body(props)
	body.position = g
	ThornfieldProps.add_cyl(body, 0.7 * size, 1.0 * size, Vector3(0, 0.4 * size, 0))
	keep_out.append(Vector3(q.x, q.y, 1.0 * size))


static func _crows_on(parent: Node3D, at: Vector3, count: int, rng: RandomNumberGenerator) -> void:
	for i in count:
		var crow := ThornfieldFieldProps.crow(rng)
		crow.position = at + Vector3(rng.randf_range(-0.35, 0.35), 0.0, rng.randf_range(-0.35, 0.35)) * float(mini(i, 1))
		parent.add_child(crow)


static func _road_distance(p: Vector2) -> float:
	var best := INF
	for line in [OverworldSpec.MAIN_ROAD, OverworldSpec.FARM_TRACK, OverworldSpec.FOREST_PATH]:
		for k in line.size() - 1:
			var a: Vector2 = line[k]
			var b: Vector2 = line[k + 1]
			var ab := b - a
			var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
			best = minf(best, p.distance_to(a + ab * t))
	return best


static func _blocked(p: Vector2, keep_out: Array[Vector3]) -> bool:
	for k in keep_out:
		if p.distance_squared_to(Vector2(k.x, k.y)) < k.z * k.z:
			return true
	return false


## Merges a group here (so it keeps its own cull distance) and shields the
## result from the merge the caller runs over the whole Plains node.
static func _merge(group: Node3D, range_end: float) -> void:
	MeshMerger.merge_static(group, MeshMerger.cell_for(range_end), range_end)
	for node in group.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.visible:
			mi.set_meta(MeshMerger.SKIP_META, true)
			if mi.visibility_range_end <= 0.0:
				mi.visibility_range_end = range_end


static func _group(parent: Node3D, group_name: String) -> Node3D:
	var node := Node3D.new()
	node.name = group_name
	parent.add_child(node)
	return node
