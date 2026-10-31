@tool
class_name ThornfieldBuilder
extends RefCounted
## Thornfield: the lonely farmstead at the end of the farm track (reference 1,
## task U7). Hero view from the track at HERO looking at the house: the worn
## track leads the eye through a sea of tall pale wind-bent grass to a lone
## two-storey clapboard farmhouse on the rise, the great dead tree breaking the
## sky to its left, a broken split-rail fence slanting in from the left.
## The curse is in the details: scarecrows that are a little too human, a drag
## trail of blood across the porch, claw marks, a crow-picked carcass in the
## grass, charms nailed to the fence posts, someone standing in a lit window.
##
## Assumptions (contract C9 / OverworldSpec):
##   - plateau Vector4(-122, 152, 16, 14) flattens the farmyard around the house
##   - dry field Vector3(-95, 128, 58) is painted (G) on the terrain
##   - farm track OverworldSpec.FARM_TRACK ends at (-116, 148), is painted (R)
## Output: Node3D "Thornfield" with
##   Landmarks (house, barn, tree; merged here, culled at 110 m),
##   Details (small kit props, debris, crows; merged here, culled at 60 m),
##   Props (fences, scarecrows, yard pieces; merged by OverworldBuilder),
##   Grass (wheat chunks, culled at 60 m) and the Marker3D children
##   Spawn_Enemy_1..3, Lore_1, Pickup_1, Light_1 and Trigger (meta "radius" = 40).
## Lights: FarmhouseGlow inside the house (range 5.5) and WindowGlow at the lit
## upstairs window (range 4.5); neither casts shadows.

const HOUSE := Vector2(-122.0, 152.0)
const FIELD := Vector3(-95.0, 128.0, 58.0)
## Hero camera on the track (player feet), looking at the house.
const HERO := Vector2(-84.0, 141.0)
const TREE := Vector2(-103.0, 156.0)
const BARN := Vector2(-139.0, 141.0)
const CARCASS := Vector2(-99.0, 136.5)
const SICK_LIGHT := Color(0.75, 0.9, 0.4)
## The storm wind (xz) the grass and the tree crown lean with.
const WIND := Vector2(-0.55, 0.83)
const SMALL_RANGE := 60.0
const LANDMARK_RANGE := 110.0


static func build(root: Node3D, terrain: TerrainBuilder, rng: RandomNumberGenerator) -> Node3D:
	var region := Node3D.new()
	region.name = "Thornfield"
	root.add_child(region)
	var landmarks := _group(region, "Landmarks")
	var details := _group(region, "Details")
	var props := _group(region, "Props")
	var keep_out: Array[Vector3] = []  # (x, z, radius) where no grass grows
	var house := _build_house(landmarks, details, terrain, rng, keep_out)
	_build_barn(landmarks, details, terrain, rng, keep_out)
	_build_tree(landmarks, details, terrain, rng, keep_out)
	_build_yard(props, details, terrain, rng, house, keep_out)
	_build_fences(props, terrain, rng)
	_build_curse(props, details, terrain, rng, keep_out)
	_build_ground_detail(props, details, terrain, rng, keep_out)
	_build_grass(region, terrain, rng, house, keep_out)
	_build_markers(region, terrain, house)
	_merge(landmarks, LANDMARK_RANGE)
	_merge(details, SMALL_RANGE)
	return region


# --- Buildings -----------------------------------------------------------------

static func _build_house(parent: Node3D, details: Node3D, terrain: TerrainBuilder, rng: RandomNumberGenerator,
		keep_out: Array[Vector3]) -> Node3D:
	var house := ThornfieldProps.farmhouse(rng)
	house.position = terrain.ground(HOUSE.x, HOUSE.y)
	# Front gable looks down the track; turned so the porch side shows from the hero view.
	var to_hero := HERO - HOUSE
	house.rotation.y = atan2(to_hero.x, to_hero.y) - 0.55
	parent.add_child(house)
	keep_out.append(Vector3(HOUSE.x, HOUSE.y, 6.2))
	var porch := _world2(house, Vector3(4.0, 0, 0.3))
	keep_out.append(Vector3(porch.x, porch.y, 3.0))
	var glow := OmniLight3D.new()
	glow.name = "FarmhouseGlow"
	glow.light_color = SICK_LIGHT
	glow.light_energy = 0.8
	glow.omni_range = 5.5
	glow.shadow_enabled = false
	glow.position = Vector3(0.0, 1.5, 0.0)
	house.add_child(glow)
	var window := FlickerLight.new()
	window.name = "WindowGlow"
	window.light_color = Color(0.85, 0.82, 0.42)
	window.base_energy = 0.9
	window.flicker_amount = 0.25
	window.gutter_chance = 0.03
	window.omni_range = 4.5
	window.shadow_enabled = false
	window.position = Vector3(1.3, 3.9, 4.6)
	house.add_child(window)
	_blood_trail(details.get_parent().get_node("Props") as Node3D, terrain, house, rng)
	# Porch dressing and the room inside (kit models, house-local).
	var floor_y := 0.5
	var items := [
		["spinning_wheel_01", Vector3(3.6, floor_y, -2.2), 0.6, 1.0],
		["wooden_stool_01", Vector3(3.3, floor_y, -1.3), 0.3, 1.0],
		["wooden_bucket_01", Vector3(4.6, floor_y, 1.7), 0.0, 1.0],
		["wooden_crate_02", Vector3(3.5, floor_y, 2.9), 1.4, 1.0],
		["wine_barrel_01", Vector3(4.5, floor_y, -3.2), 0.0, 0.9],
		["WoodenTable_01", Vector3(-0.6, floor_y, -1.0), 1.2, 1.0],
		["wooden_stool_01", Vector3(0.8, floor_y + 0.2, 0.4), 0.0, 1.0],
		["Lantern_01", Vector3(-0.5, floor_y + 0.55, -1.1), 0.0, 1.0],
		["wooden_ladder", Vector3(-1.6, 0.0, 4.25), PI, 1.6],
		["wooden_barrels_01", Vector3(-3.6, 0.0, 3.0), 0.5, 1.0],
	]
	for it in items:
		var node := AssetKit.place(details, str(it[0]), house.transform * (it[1] as Vector3), house.rotation.y + float(it[2]), float(it[3]))
		if str(it[0]) == "wooden_stool_01" and (it[1] as Vector3).x < 2.0:
			node.rotation = Vector3(0.0, node.rotation.y, PI * 0.5)  # knocked over
		if str(it[0]) == "wooden_ladder":
			node.rotate_object_local(Vector3.RIGHT, -0.32)  # leaning on the gable
	return house


## Something was dragged out of the door, across the porch, down the steps and
## into the grass. A smeared hand on the door frame.
static func _blood_trail(parent: Node3D, terrain: TerrainBuilder, house: Node3D, rng: RandomNumberGenerator) -> void:
	var blood := ThornfieldProps.blood_mat()
	var trail: Array[Vector3] = [Vector3(2.95, 0.535, 0.3), Vector3(3.7, 0.535, 0.15), Vector3(4.45, 0.535, 0.35), Vector3(5.2, 0.445, 0.3),
		Vector3(5.5, 0.295, 0.22), Vector3(5.8, 0.145, 0.3), Vector3(6.7, 0.0, 0.7), Vector3(7.6, 0.0, 1.3), Vector3(8.6, 0.0, 2.1), Vector3(9.8, 0.0, 3.2)]
	for i in trail.size():
		var p := house.transform * trail[i]
		if trail[i].y <= 0.0:
			p = terrain.ground(p.x, p.z) + Vector3(0, 0.04, 0)
		var prev := house.transform * trail[maxi(i - 1, 0)]
		var nxt := house.transform * trail[mini(i + 1, trail.size() - 1)]
		var d := nxt - prev
		var fade := 1.0 - float(i) / trail.size() * 0.6
		ThornfieldProps.splat(parent, blood, p, rng.randf_range(0.45, 0.6) * fade, rng, rng.randf_range(2.0, 2.8), atan2(d.x, d.z))
	var hand := ThornfieldProps.splat(parent, blood, Vector3.ZERO, 0.42, rng, 1.6, 0.0)
	hand.transform = house.transform * Transform3D(Basis(Vector3.BACK, -PI * 0.5), Vector3(2.93, 1.25, 0.95))


static func _build_barn(parent: Node3D, details: Node3D, terrain: TerrainBuilder, rng: RandomNumberGenerator,
		keep_out: Array[Vector3]) -> void:
	var barn := ThornfieldProps.collapsed_barn(rng)
	barn.position = terrain.ground(BARN.x, BARN.y)
	barn.rotation.y = 1.15
	parent.add_child(barn)
	keep_out.append(Vector3(BARN.x, BARN.y, 6.5))
	var wheel := AssetKit.place(details, "rusted_wheel_rim_01", barn.transform * Vector3(3.25, 0.0, 2.0), barn.rotation.y + PI * 0.5, 2.2)
	wheel.rotate_object_local(Vector3.RIGHT, 0.25)
	for i in 3:
		AssetKit.place(details, "wooden_crate_01", barn.transform * Vector3(-2.0 + i * 0.9, 0.0, 5.2 + i * 0.3), rng.randf() * TAU, 1.0)


static func _build_tree(parent: Node3D, details: Node3D, terrain: TerrainBuilder, rng: RandomNumberGenerator,
		keep_out: Array[Vector3]) -> void:
	var tree := ThornfieldProps.great_dead_tree(15.0, -WIND, rng)
	tree.position = terrain.ground(TREE.x, TREE.y) - Vector3(0, 0.2, 0)
	parent.add_child(tree)
	keep_out.append(Vector3(TREE.x, TREE.y, 2.2))
	AssetKit.place(details, "root_cluster_01", tree.position + Vector3(0.6, 0.0, 0.8), 0.7, 1.1)
	AssetKit.place(details, "root_cluster_02", tree.position + Vector3(-1.6, 0.0, -0.9), 2.4, 1.6, "root_cluster_02_a")
	for i in 5:
		var a := rng.randf() * TAU
		var r := rng.randf_range(2.5, 6.0)
		var p := terrain.ground(TREE.x + cos(a) * r, TREE.y + sin(a) * r)
		AssetKit.place(details, "dry_branches_medium_01", p, rng.randf() * TAU, rng.randf_range(1.6, 2.4), AssetKit.random_piece("dry_branches_medium_01", rng))
	# A cut rope still hangs from the low bough.
	var bough: Vector3 = tree.position + (tree.get_meta("low_bough") as Vector3)
	ThornfieldProps.limb(parent, bough, bough + Vector3(0.05, -1.7, 0.02), 0.018, 0.014, ThornfieldProps.rope_mat(), 4)
	ThornfieldProps.limb(parent, bough + Vector3(0.05, -1.7, 0.02), bough + Vector3(0.09, -1.85, 0.0), 0.014, 0.004, ThornfieldProps.rope_mat(), 3)
	# Crows on the lower limbs and in the grass under it.
	for i in 3:
		var c := ThornfieldFieldProps.crow(rng)
		var a := rng.randf() * TAU
		c.position = terrain.ground(TREE.x + cos(a) * rng.randf_range(2.0, 4.0), TREE.y + sin(a) * rng.randf_range(2.0, 4.0))
		details.add_child(c)


# --- Yard --------------------------------------------------------------------------

static func _build_yard(props: Node3D, details: Node3D, terrain: TerrainBuilder, rng: RandomNumberGenerator, house: Node3D,
		keep_out: Array[Vector3]) -> void:
	var yaw := house.rotation.y
	var well := ThornfieldProps.well(rng)
	var wp := _world2(house, Vector3(8.0, 0, 6.0))
	well.position = terrain.ground(wp.x, wp.y)
	well.rotation.y = yaw + 0.4
	props.add_child(well)
	keep_out.append(Vector3(wp.x, wp.y, 1.8))
	AssetKit.place(details, "wooden_bucket_01", well.transform * Vector3(0.7, 0.94, 0.5), 0.3, 1.0)
	var tipped := AssetKit.place(details, "wooden_bucket_01", well.transform * Vector3(-1.4, 0.15, 0.6), 1.0, 1.0)
	tipped.rotation.x = PI * 0.5
	var garden := ThornfieldProps.dead_garden(Vector2(5.5, 4.2), rng)
	var gp := _world2(house, Vector3(-6.5, 0, 6.5))
	garden.position = terrain.ground(gp.x, gp.y)
	garden.rotation.y = yaw + 0.1
	props.add_child(garden)
	keep_out.append(Vector3(gp.x, gp.y, 3.4))
	for i in 3:
		var pk := PropKit.pumpkin(rng.randf_range(0.28, 0.4), rng)
		pk.position = garden.transform * Vector3(rng.randf_range(-2.4, 2.4), 0.05, rng.randf_range(-1.8, 1.8))
		pk.rotation.z = rng.randf_range(-0.6, 0.6)  # rotten, slumped
		details.add_child(pk)
	var line := ThornfieldProps.clothesline(rng)
	var lp := _world2(house, Vector3(8.5, 0, -5.0))
	line.position = terrain.ground(lp.x, lp.y)
	line.rotation.y = yaw + 0.25
	props.add_child(line)
	var hay := ThornfieldProps.haystack(rng)
	var hp := _world2(house, Vector3(-9.0, 0, -6.5))
	hay.position = terrain.ground(hp.x, hp.y) - Vector3(0, 0.1, 0)
	props.add_child(hay)
	keep_out.append(Vector3(hp.x, hp.y, 2.0))
	# Chopping stump with the axe still in it, beside the woodpile of the lean-to.
	var sp := _world2(house, Vector3(-5.5, 0, 1.5))
	var stump := AssetKit.place(details, "tree_stump_02", terrain.ground(sp.x, sp.y) - Vector3(0, 0.12, 0), 0.4, 0.55)
	var axe := AssetKit.place(details, "wooden_axe", stump.position + Vector3(0.0, 0.3, 0.0), yaw, 1.0)
	axe.rotation = Vector3(0.0, yaw, 0.55)
	for i in 4:
		var q := _world2(house, Vector3(-5.0 + rng.randf_range(-1.5, 1.5), 0, 1.5 + rng.randf_range(-1.5, 1.5)))
		AssetKit.place(details, "bark_debris_01", terrain.ground(q.x, q.y), rng.randf() * TAU, 2.0, AssetKit.random_piece("bark_debris_01", rng))
	# Crates, barrels and a wheel rim left about the yard.
	var yard_items := [["wine_barrel_01", Vector3(6.0, 0, -2.0), 1.0], ["wooden_crate_01", Vector3(6.4, 0, -3.0), 1.0],
		["wooden_crate_02", Vector3(-3.6, 0, -4.8), 1.0], ["wine_barrel_01", Vector3(-4.2, 0, -4.0), 0.9],
		["rusted_wheel_rim_01", Vector3(5.6, 0, 4.0), 2.0], ["wooden_stool_01", Vector3(7.2, 0, 4.6), 1.0]]
	for it in yard_items:
		var q := _world2(house, it[1] as Vector3)
		var node := AssetKit.place(details, str(it[0]), terrain.ground(q.x, q.y), rng.randf() * TAU, float(it[2]))
		if str(it[0]) == "rusted_wheel_rim_01":
			node.rotation.x = PI * 0.5 - 0.05  # lying flat
	# Rain-filled mud puddles in the yard and in the ruts where the track ends.
	var puddles := [Vector3(6.5, 0, 0.8), Vector3(7.5, 0, 2.2), Vector3(3.5, 0, 6.0), Vector3(5.0, 0, 8.0),
		Vector3(1.0, 0, 7.5), Vector3(-2.0, 0, 9.5), Vector3(9.5, 0, -1.0)]
	for p in puddles:
		var q := _world2(house, p)
		ThornfieldProps.splat(props, ThornfieldProps.puddle_mat(), terrain.ground(q.x, q.y) + Vector3(0, 0.04, 0), rng.randf_range(1.2, 2.4), rng, rng.randf_range(0.6, 1.0))
		keep_out.append(Vector3(q.x, q.y, 0.7))


# --- Fences --------------------------------------------------------------------

static func _build_fences(parent: Node3D, terrain: TerrainBuilder, rng: RandomNumberGenerator) -> void:
	var fences := _group(parent, "Fences")
	var a: Vector2 = OverworldSpec.FARM_TRACK[1]
	var b: Vector2 = OverworldSpec.FARM_TRACK[2]
	var dir := (b - a).normalized()
	var left := Vector2(-dir.y, dir.x)
	if left.y < 0.0:
		left = -left
	# Hero fence: slants in from the bottom-left of the hero view, broken, charmed.
	var runs := [
		[-84.5, -97.0, 5.6, 1.7, 0.35, 0.5], [-99.5, -108.0, 2.4, 3.2, 0.75, 0.4],
		[-63.0, -70.0, 3.0, 3.0, 0.4, 0.15], [-73.0, -81.0, 3.0, 3.0, 0.5, 0.2],
	]
	for r in runs:
		var pts := PackedVector2Array()
		var x0: float = r[0]
		var x1: float = r[1]
		var steps := maxi(2, int(absf(x1 - x0) / 4.0))
		for k in steps + 1:
			var x := lerpf(x0, x1, float(k) / steps)
			var t := (x - a.x) / (b.x - a.x)
			var on := a.lerp(b, t)
			pts.append(on + left * (lerpf(float(r[2]), float(r[3]), float(k) / steps) + rng.randf_range(-0.15, 0.15)))
		fences.add_child(ThornfieldFieldProps.split_rail(terrain, pts, float(r[4]), float(r[5]), -1.0, rng))
	# Right side only where the hero view does not look.
	for r in [[-62.0, -72.0], [-75.0, -80.0]]:
		var pts := PackedVector2Array()
		for x: float in [float(r[0]), (float(r[0]) + float(r[1])) * 0.5, float(r[1])]:
			var on := a.lerp(b, (x - a.x) / (b.x - a.x))
			pts.append(on - left * 3.0)
		fences.add_child(ThornfieldFieldProps.split_rail(terrain, pts, 0.5, 0.2, 1.0, rng))
	# Paddock beside the barn, one side fallen away.
	var paddock := PackedVector2Array([Vector2(-147.0, 152.0), Vector2(-148.0, 163.0), Vector2(-135.0, 162.0), Vector2(-133.0, 156.0)])
	fences.add_child(ThornfieldFieldProps.split_rail(terrain, paddock, 0.6, 0.2, 1.0, rng))


# --- Curse ---------------------------------------------------------------------

static func _build_curse(props: Node3D, details: Node3D, terrain: TerrainBuilder, rng: RandomNumberGenerator,
		keep_out: Array[Vector3]) -> void:
	# Scarecrows: one watching the track over its shoulder, one in the field,
	# one slipped down its pole near the garden, one far out on the edge.
	var crows := [[Vector2(-101.5, 139.0), 1, 1.6], [Vector2(-110.0, 146.2), 0, -0.4],
		[Vector2(-91.0, 121.0), 2, 0.9], [Vector2(-76.0, 152.0), 0, 2.8]]
	for s in crows:
		var at: Vector2 = s[0]
		var sc := ThornfieldFieldProps.scarecrow(int(s[1]), rng)
		sc.position = terrain.ground(at.x, at.y)
		sc.rotation.y = float(s[2])
		props.add_child(sc)
		keep_out.append(Vector3(at.x, at.y, 0.6))
	# A crow on the scarecrow watching the track.
	var perch := ThornfieldFieldProps.crow(rng)
	perch.position = terrain.ground(-101.5, 139.0) + Vector3(-0.5, 1.92, -0.1)
	details.add_child(perch)
	# Crow-picked carcass in a crushed clearing in the grass, crows at it.
	var carcass := ThornfieldFieldProps.carcass(rng)
	carcass.position = terrain.ground(CARCASS.x, CARCASS.y)
	carcass.rotation.y = 0.5
	props.add_child(carcass)
	keep_out.append(Vector3(CARCASS.x, CARCASS.y, 2.3))
	for i in 4:
		var c := ThornfieldFieldProps.crow(rng)
		c.position = carcass.transform * Vector3(rng.randf_range(-1.6, 1.6), 0.0, rng.randf_range(-0.2, 1.2))
		if i == 0:
			c.position = carcass.transform * Vector3(0.15, 0.66, 0.15)
		details.add_child(c)


# --- Ground detail -----------------------------------------------------------------

static func _build_ground_detail(props: Node3D, details: Node3D, terrain: TerrainBuilder, rng: RandomNumberGenerator,
		keep_out: Array[Vector3]) -> void:
	var center := Vector2(FIELD.x, FIELD.y)
	# Field-edge clearance cairns: big mossy rocks, stumps, a fallen trunk.
	for i in 26:
		var a := rng.randf() * TAU
		var p := center + Vector2(cos(a), sin(a)) * FIELD.z * rng.randf_range(0.85, 1.02)
		if _near_track(p, 4.0) or p.distance_to(HOUSE) < 14.0:
			continue
		var g := terrain.ground(p.x, p.y)
		var pick := rng.randi() % 5
		match pick:
			0, 1:
				var model := "rock_moss_set_01" if pick == 0 else "rock_moss_set_02"
				AssetKit.place(props, model, g - Vector3(0, 0.15, 0), rng.randf() * TAU, rng.randf_range(0.4, 0.75), AssetKit.random_piece(model, rng))
			2:
				AssetKit.place(props, "tree_stump_01" if rng.randf() < 0.5 else "tree_stump_02", g - Vector3(0, 0.1, 0), rng.randf() * TAU, rng.randf_range(0.7, 1.0))
			3:
				AssetKit.place(props, "boulder_01", g - Vector3(0, 0.3, 0), rng.randf() * TAU, rng.randf_range(0.6, 1.0))
			_:
				AssetKit.place(details, "dry_branches_medium_01", g, rng.randf() * TAU, 2.0, AssetKit.random_piece("dry_branches_medium_01", rng))
		keep_out.append(Vector3(p.x, p.y, 1.0))
	var log_at := terrain.ground(-118.0, 126.0)
	AssetKit.place(props, "dead_tree_trunk_02", log_at - Vector3(0, 0.25, 0), 0.4, 1.0)
	keep_out.append(Vector3(-118.0, 126.0, 2.5))
	AssetKit.place(props, "namaqualand_boulder_02", terrain.ground(-128.0, 167.0) - Vector3(0, 0.2, 0), 1.1, 1.0)
	# Stones and bark along the track edges, a rock where the hero fence starts.
	var track := OverworldSpec.sample_path(OverworldSpec.FARM_TRACK, 3.0)
	for i in track.size():
		var p: Vector2 = track[i]
		if p.x > -60.0 or rng.randf() < 0.55:
			continue
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var q := p + Vector2(rng.randf_range(-1.0, 1.0), side * rng.randf_range(1.7, 2.6))
		if rng.randf() < 0.5:
			AssetKit.place(details, "rock_moss_set_02", terrain.ground(q.x, q.y) - Vector3(0, 0.1, 0), rng.randf() * TAU, rng.randf_range(0.18, 0.3), AssetKit.random_piece("rock_moss_set_02", rng))
		else:
			AssetKit.place(details, "bark_debris_01", terrain.ground(q.x, q.y), rng.randf() * TAU, 2.2, AssetKit.random_piece("bark_debris_01", rng))
	AssetKit.place(props, "rock_moss_set_01", terrain.ground(-86.5, 145.0) - Vector3(0, 0.2, 0), 0.8, 0.45, "rock_moss_set_01_rock04")
	# The cart that never made it out, by the track nearer the road.
	var cart := PropKit.cart_wreck(rng)
	cart.position = terrain.ground(-67.0, 133.0)
	cart.rotation.y = 0.7
	props.add_child(cart)
	keep_out.append(Vector3(-67.0, 133.0, 2.6))


# --- Grass ---------------------------------------------------------------------

static func _track_distance(p: Vector2) -> float:
	var pts := OverworldSpec.FARM_TRACK
	var best := INF
	for k in pts.size() - 1:
		var a: Vector2 = pts[k]
		var b: Vector2 = pts[k + 1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t))
	return best


static func _near_track(p: Vector2, clear: float) -> bool:
	return _track_distance(p) < clear


static func _blocked(p: Vector2, keep_out: Array[Vector3]) -> bool:
	for k in keep_out:
		if p.distance_squared_to(Vector2(k.x, k.y)) < k.z * k.z:
			return true
	return false


static func _build_grass(region: Node3D, terrain: TerrainBuilder, rng: RandomNumberGenerator, house: Node3D,
		keep_out: Array[Vector3]) -> void:
	var noise := FastNoiseLite.new()
	noise.seed = 4711
	noise.frequency = 0.05
	var tufts: Array = []
	var center := Vector2(FIELD.x, FIELD.y)
	var across := PI * 0.5  # quads face along the track (x) so the track views see them full on
	# The sea: denser and taller towards the track, thinning to the field edge.
	var target := 15500
	var tries := 0
	while tufts.size() < target and tries < target * 6:
		tries += 1
		var p := Vector2(rng.randf_range(center.x - FIELD.z, center.x + FIELD.z), rng.randf_range(center.y - FIELD.z, center.y + FIELD.z))
		var n := noise.get_noise_2d(p.x, p.y)
		var edge_d := p.distance_to(center) - FIELD.z * (0.92 + n * 0.12)
		if edge_d > 0.0 or p.distance_to(HOUSE) < 12.5:
			continue
		var td := _track_distance(p)
		if td < 1.55 + n * 0.45:
			continue
		var keep := 0.45 + 0.55 * exp(-maxf(td - 2.0, 0.0) / 7.0)
		keep *= clampf(-edge_d / 8.0, 0.25, 1.0)
		if rng.randf() > keep or _blocked(p, keep_out):
			continue
		var tall := 1.0 + 0.32 * exp(-maxf(td - 2.0, 0.0) / 5.0)
		var h := rng.randf_range(0.9, 1.3) * tall * (1.0 + n * 0.15)
		var yaw := across + rng.randf_range(-0.9, 0.9) if rng.randf() < 0.8 else rng.randf() * TAU
		tufts.append([terrain.ground(p.x, p.y) - Vector3(0, 0.06, 0), yaw, rng.randf_range(1.0, 1.4), h, clampf(0.55 + n * 0.5 + rng.randf_range(-0.15, 0.15), 0.2, 1.0)])
	# The trodden track: a frayed fringe at its edges, a low grassy crown between
	# the ruts, short trampled tufts scattered over the rest of it.
	var walk := OverworldSpec.sample_path(OverworldSpec.FARM_TRACK, 0.5)
	for p in walk:
		if p.x < -40.0 and p.distance_to(HOUSE) > 8.0 and rng.randf() < 0.7:
			var q: Vector2 = p + Vector2(rng.randf_range(-1.3, 1.3), rng.randf_range(-1.3, 1.3))
			tufts.append([terrain.ground(q.x, q.y) - Vector3(0, 0.02, 0), rng.randf() * TAU, rng.randf_range(0.4, 0.7), rng.randf_range(0.14, 0.3), 0.35])
	var track := OverworldSpec.sample_path(OverworldSpec.FARM_TRACK, 0.6)
	for i in track.size() - 1:
		var p: Vector2 = track[i]
		if p.x > -40.0:
			continue
		var dir := (track[i + 1] - p).normalized()
		var nrm := Vector2(-dir.y, dir.x)
		if rng.randf() < 0.75:
			var q := p + nrm * rng.randf_range(-0.2, 0.2) + dir * rng.randf_range(-0.3, 0.3)
			tufts.append([terrain.ground(q.x, q.y) - Vector3(0, 0.03, 0), atan2(dir.y, dir.x) + rng.randf_range(-0.5, 0.5), rng.randf_range(0.5, 0.8), rng.randf_range(0.28, 0.5), 0.45])
		for side: float in [-1.0, 1.0]:
			if rng.randf() < 0.85:
				var q: Vector2 = p + nrm * side * rng.randf_range(1.15, 1.7) + dir * rng.randf_range(-0.3, 0.3)
				if not _blocked(q, keep_out) and q.distance_to(HOUSE) > 7.0:
					tufts.append([terrain.ground(q.x, q.y) - Vector3(0, 0.04, 0), across + rng.randf_range(-0.8, 0.8), rng.randf_range(0.7, 1.1), rng.randf_range(0.5, 0.95), 0.5])
	# Yard: short ragged grass between the buildings, tall weeds against the walls.
	var yard_tries := 0
	var yard := 0
	while yard < 1300 and yard_tries < 9000:
		yard_tries += 1
		var p := HOUSE + Vector2(rng.randf_range(-17.0, 17.0), rng.randf_range(-17.0, 17.0))
		var d := p.distance_to(HOUSE)
		if d > 17.0 or d < 6.0 or _blocked(p, keep_out) or _near_track(p, 1.4):
			continue
		var h := rng.randf_range(0.3, 0.7) * (1.0 + clampf((d - 11.0) / 6.0, 0.0, 1.0) * 0.6)
		tufts.append([terrain.ground(p.x, p.y) - Vector3(0, 0.04, 0), rng.randf() * TAU, rng.randf_range(0.6, 1.0), h, rng.randf_range(0.3, 0.6)])
		yard += 1
	for i in 70:
		var side := rng.randi() % 3
		var local := Vector3(rng.randf_range(-3.0, 3.0), 0, 4.0 if side == 0 else -4.0)
		if side == 2:
			local = Vector3(-3.0, 0, rng.randf_range(-3.8, 3.8))
		local += Vector3(rng.randf_range(-0.2, 0.25), 0, rng.randf_range(-0.2, 0.2)).rotated(Vector3.UP, 0.0)
		var q := _world2(house, local)
		tufts.append([terrain.ground(q.x, q.y) - Vector3(0, 0.04, 0), rng.randf() * TAU, rng.randf_range(0.6, 0.9), rng.randf_range(0.6, 1.1), 0.35])
	ThornfieldFieldProps.grass_chunks(region, tufts, SMALL_RANGE)


# --- Markers ---------------------------------------------------------------------

static func _build_markers(region: Node3D, terrain: TerrainBuilder, house: Node3D) -> void:
	var spawns: Array[Vector2] = [Vector2(-106.0, 140.5), Vector2(-112.0, 164.0), Vector2(-128.0, 131.0)]
	for i in spawns.size():
		_marker(region, "Spawn_Enemy_%d" % (i + 1), terrain.ground(spawns[i].x, spawns[i].y))
	var floor_at := terrain.ground(HOUSE.x, HOUSE.y) + Vector3(0.0, 0.5, 0.0)
	_marker(region, "Lore_1", floor_at + Vector3(0.0, 0.1, 0.0))
	var pickup := _world2(house, Vector3(7.2, 0, 4.8))
	_marker(region, "Pickup_1", terrain.ground(pickup.x, pickup.y) + Vector3(0.0, 0.5, 0.0))
	_marker(region, "Light_1", terrain.ground(HOUSE.x, HOUSE.y) + Vector3(0.0, 1.5, 0.0))
	var trig := _marker(region, "Trigger", terrain.ground(HOUSE.x, HOUSE.y))
	trig.set_meta("radius", 40.0)


# --- Helpers ---------------------------------------------------------------------

## House-local point (y ignored) to world xz.
static func _world2(house: Node3D, local: Vector3) -> Vector2:
	var p := house.transform * Vector3(local.x, 0.0, local.z)
	return Vector2(p.x, p.z)


## Merges a group here (so it keeps its own cull distance) and shields the result
## from the region-wide merge in OverworldBuilder.
static func _merge(group: Node3D, range_end: float) -> void:
	MeshMerger.merge_static(group, MeshMerger.cell_for(range_end), range_end)
	for node in group.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.visible:
			mi.set_meta(MeshMerger.SKIP_META, true)
			if mi.visibility_range_end <= 0.0:
				mi.visibility_range_end = range_end


static func _marker(parent: Node3D, marker_name: String, pos: Vector3) -> Marker3D:
	var m := Marker3D.new()
	m.name = marker_name
	m.position = pos
	parent.add_child(m)
	return m


static func _group(parent: Node3D, group_name: String) -> Node3D:
	var node := Node3D.new()
	node.name = group_name
	parent.add_child(node)
	return node
