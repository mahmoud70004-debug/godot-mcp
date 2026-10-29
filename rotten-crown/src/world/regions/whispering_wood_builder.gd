@tool
class_name WhisperingWoodBuilder
extends RefCounted
## Whispering Wood (reference 3): a night path through a tunnel of ancient,
## gnarled trees whose limbs arch and interlock overhead, mossy roots, ferns and
## fallen trunks on the verges, moon shafts through the canopy, blue mist pooling
## where the path dips, drifting motes. Beyond the path the forest goes on in
## depth layers (detailed trunks, mid trunks, dark far silhouettes) with two
## clearings: the Saint's glade on the path bend (statue, Light_1) and, off the
## path to the east, a stone circle under a hanged lantern beside a tree grown
## around a skeleton. Faces in the bark and ribbons tied to the limbs.
##
## Contract C9 assumptions:
##  - terrain = TerrainBuilder over OverworldSpec.make(); every placement uses terrain.ground(x, z).
##  - The forest path is OverworldSpec.FOREST_PATH (pale dirt paint is the terrain's job).
##  - build() adds the returned Node3D "WhisperingWood" to `root` itself.
##  - Markers: Spawn_Enemy_1..3, Lore_1, Pickup_1, Light_1 (+ Light_2, the lantern),
##    Trigger (meta "radius" = 45, at the forest entrance) and more "Trigger" markers
##    in Zone_k nodes so the region atmosphere holds along the whole path.
##  - The overworld moonlight shines along euler(-0.524, -2.634, 0); shafts slant the same way.
##  - Groups are merged here with their own visibility ranges (trunks 110 m, small
##    props 60 m); the merged chunks carry no_merge so the overworld merge skips them.

const SHAFT_SHADER := preload("res://assets/shaders/moon_shaft.gdshader")
const GRASS_MATERIAL := preload("res://assets/materials/grass_field.tres")
const MOON_EULER := Vector3(-0.524, -2.634, 0.0)
## Tunnel trees: one every STEP metres along the path, alternating sides.
const STEP := 3.3
## The Saint's glade on the path bend, and the stone circle off the path.
const GLADE := Vector2(139.0, 178.0)
const GLADE_R := 8.0
const CIRCLE := Vector2(157.0, 201.0)
const CIRCLE_R := 9.5
const TRAIL_W := 2.6
## Trunks stop drawing at 95 m: the wood fog hides 94 % of them there.
const RANGE_TREES := 95.0
const RANGE_PROPS := 60.0
const RANGE_POI := 80.0
const SEED := 3003

static var _cum := PackedFloat32Array()


## `_shared_rng` is ignored: the wood uses its own seed so its layout (and the
## hero view) does not shift when other region builders draw more numbers.
static func build(root: Node3D, terrain: TerrainBuilder, _shared_rng: RandomNumberGenerator) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var wood := Node3D.new()
	wood.name = "WhisperingWood"
	root.add_child(wood)
	_cum = PackedFloat32Array()
	var ctx := {
		"terrain": terrain, "rng": rng, "wood": wood,
		"trees": [], "occupied": [], "keep_out": [], "tunnel": [],
	}
	var markers := _markers(wood, terrain, rng)
	for m in markers.find_children("*", "Marker3D", true, false):
		var p := (m as Node3D).position
		(ctx["keep_out"] as Array).append(Vector2(p.x, p.z))
	var trunks := _group(wood, "Trunks")
	var far := _group(wood, "FarTrees")
	var floor_props := _group(wood, "Undergrowth")
	var poi := _group(wood, "Clearings")
	var air := _group(wood, "Atmosphere")
	_tunnel(ctx, trunks)
	_canopy(ctx, trunks)
	_glade(ctx, poi)
	_stone_circle(ctx, poi, markers)
	_forest_depth(ctx, trunks, far)
	_underbrush(ctx, trunks, far)
	_uncanny(ctx, trunks)
	_undergrowth(ctx, floor_props)
	_verge_grass(ctx, floor_props)
	_moon_shafts(ctx, air)
	_mist(ctx, air)
	_path_light(ctx, air)
	_motes(ctx, air)
	_night_tint(floor_props)
	_night_tint(poi)
	_small_no_shadow(floor_props, 1.6)
	_small_no_shadow(poi, 1.0)
	_merge(trunks, RANGE_TREES, 30.0)
	_merge(far, RANGE_TREES, 60.0)
	_merge(poi, RANGE_POI, 30.0)
	_merge(floor_props, RANGE_PROPS, 30.0)
	return wood


static func _group(parent: Node3D, group_name: String) -> Node3D:
	var node := Node3D.new()
	node.name = group_name
	parent.add_child(node)
	return node


## Small props cast no moon shadow (a shadow-pass draw each, for a speck).
static func _small_no_shadow(group: Node3D, size: float) -> void:
	for node in group.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var scale := mi.global_transform.basis.get_scale() if mi.is_inside_tree() else Vector3.ONE
		var box := mi.get_aabb().size * scale
		if maxf(box.x, maxf(box.y, box.z)) < size:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func _merge(group: Node3D, range_end: float, cell: float) -> void:
	var before := group.get_children()
	MeshMerger.merge_static(group, cell, range_end)
	for child in group.get_children():
		if child is MeshInstance3D and not before.has(child):
			child.set_meta(MeshMerger.SKIP_META, true)
	for node in group.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.visible and mi.visibility_range_end <= 0.0:
			mi.visibility_range_end = range_end


## Scanned kit models are daylight albedo; under this wood's cold moon they
## get a darker blue-shifted copy of their material (one copy per source
## material, so MeshMerger still batches them).
static func _night_tint(group: Node3D) -> void:
	var copies := {}
	for node in group.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var src := mi.material_override as StandardMaterial3D
		if src == null or src.albedo_texture == null or not src.albedo_texture.resource_path.contains(".glb"):
			continue
		if not copies.has(src):
			var mat := src.duplicate() as StandardMaterial3D
			var fern := src.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			mat.albedo_color = src.albedo_color * (Color(0.42, 0.6, 0.72) if fern else Color(0.5, 0.56, 0.72))
			copies[src] = mat
		mi.material_override = copies[src]


# --- Path geometry -------------------------------------------------------------

static func _points() -> Array:
	return OverworldSpec.FOREST_PATH


static func _length() -> float:
	if _cum.is_empty():
		var pts := _points()
		_cum.append(0.0)
		for k in pts.size() - 1:
			_cum.append(_cum[k] + (pts[k] as Vector2).distance_to(pts[k + 1] as Vector2))
	return _cum[_cum.size() - 1]


## Point at arc length s along the path.
static func _at(s: float) -> Vector2:
	_length()
	var pts := _points()
	s = clampf(s, 0.0, _cum[_cum.size() - 1])
	for k in pts.size() - 1:
		if s <= _cum[k + 1]:
			var t := (s - _cum[k]) / maxf(_cum[k + 1] - _cum[k], 0.001)
			return (pts[k] as Vector2).lerp(pts[k + 1] as Vector2, t)
	return pts[pts.size() - 1]


static func _tangent(s: float) -> Vector2:
	return (_at(s + 1.5) - _at(s - 1.5)).normalized()


static func _path_distance(p: Vector2) -> float:
	var best := INF
	var pts := _points()
	for k in pts.size() - 1:
		var a: Vector2 = pts[k]
		var b: Vector2 = pts[k + 1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t))
	return best


static func _trail_distance(p: Vector2) -> float:
	var ab := CIRCLE - GLADE
	var t := clampf((p - GLADE).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(GLADE + ab * t)


## Forest-floor paint (TerrainSpec.forests) at p, 0..1.
static func _forest(terrain: TerrainBuilder, p: Vector2) -> float:
	var spec := terrain.spec
	var ix := clampi(int((p.x - spec.min_corner.x) / spec.cell), 0, terrain.cols - 1)
	var iz := clampi(int((p.y - spec.min_corner.y) / spec.cell), 0, terrain.rows - 1)
	return terrain.paint[iz * terrain.cols + ix].b


## True where nothing big may stand: clearings, the trail, markers.
static func _open(ctx: Dictionary, p: Vector2, margin: float) -> bool:
	if p.distance_to(GLADE) < GLADE_R + margin or p.distance_to(CIRCLE) < CIRCLE_R + margin:
		return true
	if _trail_distance(p) < TRAIL_W + margin:
		return true
	for k: Vector2 in ctx["keep_out"]:
		if p.distance_to(k) < 1.4 + margin:
			return true
	return false


## Keeps the wood's dark outer band off the main road and Hollowmere.
static func _wood_side(p: Vector2) -> bool:
	return p.x > 20.0 and p.distance_to(Vector2(22.0, 338.0)) > 62.0


static func _free(ctx: Dictionary, p: Vector2, spacing: float) -> bool:
	for o: Vector3 in ctx["occupied"]:
		if p.distance_to(Vector2(o.x, o.y)) < maxf(spacing, o.z):
			return false
	return true


static func _yaw_towards(dir: Vector2) -> float:
	return atan2(-dir.y, dir.x)


# --- Trees ---------------------------------------------------------------------

## Two rows of huge leaning trees along the path; their limbs meet overhead.
static func _tunnel(ctx: Dictionary, parent: Node3D) -> void:
	var terrain: TerrainBuilder = ctx["terrain"]
	var rng: RandomNumberGenerator = ctx["rng"]
	var side := 1.0
	var s := 0.0
	var last := [-1, -1]
	var total := _length()
	while s < total - 2.0:
		s += STEP * rng.randf_range(0.85, 1.15)
		side = -side
		var p := _at(s)
		var t := _tangent(s)
		var n := Vector2(-t.y, t.x)
		var pos := p + n * side * rng.randf_range(4.2, 5.3) + t * rng.randf_range(-0.6, 0.6)
		if _forest(terrain, pos) < 0.3 or _path_distance(pos) < 3.9 or _open(ctx, pos, 1.0) or not _free(ctx, pos, 3.6):
			continue
		var si := 0 if side < 0.0 else 1
		var variant := rng.randi() % 5
		if variant == last[si]:
			variant = (variant + 1 + rng.randi() % 4) % 5
		last[si] = variant
		var sc := rng.randf_range(0.9, 1.15)
		var yaw := _yaw_towards(-n * side) + rng.randf_range(-0.3, 0.3)
		var tree := WoodProps.place_tree(parent, WoodProps.Kind.HERO, variant, terrain.ground(pos.x, pos.y), yaw, sc)
		(ctx["occupied"] as Array).append(Vector3(pos.x, pos.y, 3.6))
		(ctx["tunnel"] as Array).append({"node": tree, "variant": variant, "s": s, "pos": pos, "side": side, "scale": sc})


## Leaf clumps high over the path so the sky only shows through small gaps.
static func _canopy(ctx: Dictionary, parent: Node3D) -> void:
	var terrain: TerrainBuilder = ctx["terrain"]
	var rng: RandomNumberGenerator = ctx["rng"]
	var s := 25.0
	var total := _length()
	while s < total - 25.0:
		var clumps: Array = []
		var end := minf(s + 20.0, total - 25.0)
		while s < end:
			var t := _tangent(s)
			var n := Vector2(-t.y, t.x)
			for k in 5:
				if rng.randf() < 0.12:
					continue
				var c := _at(s) + n * (-9.0 + 4.5 * k + rng.randf_range(-1.5, 1.5))
				if c.distance_to(GLADE) < GLADE_R - 1.0:
					continue
				var high := rng.randf() < 0.4
				var h := rng.randf_range(15.0, 18.0) if high else rng.randf_range(12.0, 14.5)
				clumps.append([terrain.ground(c.x, c.y) + Vector3(0.0, h, 0.0), rng.randf_range(5.0, 7.5)])
			s += 2.9
		if not clumps.is_empty():
			WoodProps.canopy(parent, clumps, rng)


## Mid trunks behind the rows and dark far silhouettes, so the wood reads wide.
static func _forest_depth(ctx: Dictionary, trunks: Node3D, far: Node3D) -> void:
	var terrain: TerrainBuilder = ctx["terrain"]
	var rng: RandomNumberGenerator = ctx["rng"]
	var area := Rect2(20.0, 45.0, 165.0, 290.0)
	var layers := [
		[WoodProps.Kind.MID, 8.5, 22.0, 5.6, 54, trunks, 0.2],
		[WoodProps.Kind.FAR, 20.0, 44.0, 5.5, 120, far, -1.0],
	]
	for layer: Array in layers:
		var kind: WoodProps.Kind = layer[0]
		var placed := 0
		var tries := 0
		while placed < int(layer[4]) and tries < 4000:
			tries += 1
			var p := Vector2(rng.randf_range(area.position.x, area.end.x), rng.randf_range(area.position.y, area.end.y))
			var d := _path_distance(p)
			if d < float(layer[1]) or d > float(layer[2]) or _forest(terrain, p) < float(layer[6]) or not _wood_side(p):
				continue
			if _open(ctx, p, 1.5) or not _free(ctx, p, float(layer[3])):
				continue
			placed += 1
			var toward := _nearest_path_dir(p)
			var yaw := _yaw_towards(toward) + rng.randf_range(-1.1, 1.1)
			var sc := rng.randf_range(0.95, 1.3) if kind == WoodProps.Kind.MID else rng.randf_range(1.1, 1.6)
			WoodProps.place_tree(layer[5] as Node3D, kind, rng.randi() % 3, terrain.ground(p.x, p.y), yaw, sc)
			(ctx["occupied"] as Array).append(Vector3(p.x, p.y, float(layer[3])))


## Bushy undergrowth behind the rows (lit) and a dark wall far out, so the eye
## never runs out of forest to the horizon.
static func _underbrush(ctx: Dictionary, near_parent: Node3D, far_parent: Node3D) -> void:
	var terrain: TerrainBuilder = ctx["terrain"]
	var rng: RandomNumberGenerator = ctx["rng"]
	var total := _length()
	# [min, max distance from the path, step, clump size, height/spread, dark far material, parent]
	var bands := [
		[2.8, 5.5, 2.6, Vector2(1.0, 1.6), 0.25, false, near_parent],
		[6.5, 15.0, 2.2, Vector2(1.8, 3.2), 0.6, false, near_parent],
		[24.0, 42.0, 2.6, Vector2(4.0, 6.5), 1.5, true, far_parent],
	]
	for band: Array in bands:
		var s := 20.0
		while s < total - 20.0:
			var clumps: Array = []
			var end := minf(s + 24.0, total - 20.0)
			while s < end:
				var t := _tangent(s)
				var n := Vector2(-t.y, t.x)
				for side: float in [-1.0, 1.0]:
					var c := _at(s) + n * side * rng.randf_range(float(band[0]), float(band[1]))
					var outside := _forest(terrain, c) < 0.05 and not bool(band[5])
					if _path_distance(c) < float(band[0]) - 0.5 or outside or not _wood_side(c) or _open(ctx, c, 0.5):
						continue
					var sz: Vector2 = band[3]
					for k in 3:
						var o := Vector2(rng.randf_range(-1.5, 1.5), rng.randf_range(-1.5, 1.5)) * float(band[4])
						var h := rng.randf_range(0.6, 2.2) * float(band[4])
						clumps.append([terrain.ground(c.x + o.x, c.y + o.y) + Vector3(0.0, h, 0.0), rng.randf_range(sz.x, sz.y)])
				s += float(band[2]) * rng.randf_range(0.8, 1.2)
			if not clumps.is_empty():
				WoodProps.canopy(band[6] as Node3D, clumps, rng, bool(band[5]))


static func _nearest_path_dir(p: Vector2) -> Vector2:
	var best := INF
	var q := p
	var total := _length()
	var s := 0.0
	while s < total:
		var c := _at(s)
		if c.distance_squared_to(p) < best:
			best = c.distance_squared_to(p)
			q = c
		s += 4.0
	return (q - p).normalized() if best > 0.01 else Vector2.RIGHT


## Faces in the bark and ribbons tied under the arches.
static func _uncanny(ctx: Dictionary, parent: Node3D) -> void:
	var rng: RandomNumberGenerator = ctx["rng"]
	var tunnel: Array = ctx["tunnel"]
	for want: float in [62.0, 158.0, 236.0, 300.0]:
		var e := _tunnel_near(tunnel, want)
		if not e.is_empty() and not e.has("special"):
			e["special"] = "face"
			WoodProps.bark_face(e["node"] as Node3D, WoodProps.tree(WoodProps.Kind.HERO, int(e["variant"])), rng)
	for want: float in [88.0, 133.0, 146.0, 205.0, 262.0, 318.0]:
		var e := _tunnel_near(tunnel, want)
		if e.is_empty():
			continue
		var node := e["node"] as Node3D
		var hangs: PackedVector3Array = WoodProps.tree(WoodProps.Kind.HERO, int(e["variant"]))["hangs"]
		var picked := 0
		for i in hangs.size():
			var h := hangs[(i * 7) % hangs.size()]
			if h.x < 1.5 or h.x > 7.0:
				continue
			_tie(parent, node.transform * h, rng)
			picked += 1
			if picked >= rng.randi_range(3, 5):
				break


static func _tie(parent: Node3D, top: Vector3, rng: RandomNumberGenerator) -> void:
	for k in rng.randi_range(1, 2):
		var off := Vector3(rng.randf_range(-0.15, 0.15), 0.0, rng.randf_range(-0.15, 0.15))
		WoodProps.ribbon(parent, top + off, rng.randf_range(0.6, 1.6), rng.randf_range(0.07, 0.12), rng.randf() < 0.3, rng)


static func _tunnel_near(tunnel: Array, s: float) -> Dictionary:
	var best: Dictionary = {}
	var bd := INF
	for e: Dictionary in tunnel:
		var d := absf(float(e["s"]) - s)
		if d < bd and not e.has("special"):
			bd = d
			best = e
	return best


# --- Clearings -----------------------------------------------------------------

## The Saint's glade on the path bend: a weathered statue on a mossy plinth,
## watched over by the blue Light_1, a moon shaft and low mist.
static func _glade(ctx: Dictionary, parent: Node3D) -> void:
	var terrain: TerrainBuilder = ctx["terrain"]
	var rng: RandomNumberGenerator = ctx["rng"]
	var spot := GLADE + Vector2(5.2, -1.0)
	var base := terrain.ground(spot.x, spot.y)
	var plinth := AssetKit.place(parent, "rock_moss_set_02", base + Vector3(0.0, -0.25, 0.0), 0.4, 0.9, "rock_moss_set_02_rock10")
	var top := AssetKit.height("rock_moss_set_02", "rock_moss_set_02_rock10") * 0.9 - 0.3
	AssetKit.place(parent, "gothic_statue", base + Vector3(0.0, top, 0.0), _yaw_towards(GLADE - spot) - PI * 0.5, 1.15)
	plinth.name = "Plinth"
	_body_box(parent, base + Vector3(0.0, 0.9, 0.0), Vector3(1.6, 1.8, 1.4), 0.4)
	for k in 6:
		var a := TAU * k / 6.0 + rng.randf_range(-0.3, 0.3)
		var p := spot + Vector2(cos(a), sin(a)) * rng.randf_range(1.6, 2.4)
		WoodProps.mushrooms(parent, terrain.ground(p.x, p.y), rng)
	for k in 5:
		var a := rng.randf_range(0.0, TAU)
		var p := GLADE + Vector2(cos(a), sin(a)) * rng.randf_range(GLADE_R - 1.0, GLADE_R + 0.5)
		if _path_distance(p) > 2.5:
			AssetKit.place(parent, "rock_moss_set_02", terrain.ground(p.x, p.y) - Vector3(0.0, 0.1, 0.0), rng.randf() * TAU, rng.randf_range(0.4, 0.7), AssetKit.random_piece("rock_moss_set_02", rng))


## Off the path: seven standing stones around a flat altar stone, a tree grown
## around a skeleton on the far side and a lantern hung where no one could reach.
static func _stone_circle(ctx: Dictionary, parent: Node3D, markers: Node3D) -> void:
	var terrain: TerrainBuilder = ctx["terrain"]
	var rng: RandomNumberGenerator = ctx["rng"]
	var stones := ["rock_moss_set_01_rock01", "rock_moss_set_01_rock02", "rock_moss_set_01_rock05"]
	var long_axis := [3.36, 3.27, 3.01]  # Z extent of each scanned piece (m)
	for k in 7:
		var a := TAU * k / 7.0 + 0.3 + rng.randf_range(-0.12, 0.12)
		var p := CIRCLE + Vector2(cos(a), sin(a)) * 5.6
		var g := terrain.ground(p.x, p.y)
		var piece: String = stones[k % stones.size()]
		var sc := rng.randf_range(0.85, 1.05)
		var stone := AssetKit.place(parent, "rock_moss_set_01", g, 0.0, sc, piece)
		var half: float = float(long_axis[k % stones.size()]) * 0.5
		var fallen := k == 4
		if fallen:
			stone.basis = Basis(Vector3.UP, a + PI * 0.5).scaled(Vector3.ONE * sc)
		else:
			# Stand the boulder on its end (its long axis is Z); bury the foot.
			stone.basis = (Basis(Vector3.UP, a + PI * 0.5) * Basis(Vector3.RIGHT, PI * 0.5 + rng.randf_range(-0.1, 0.1))).scaled(Vector3.ONE * sc)
			stone.position = g + Vector3(0.0, half * sc - 0.4, 0.0)
		_body_box(parent, g + Vector3(0.0, 1.0, 0.0), Vector3(1.3, 2.0, 0.9) * (sc / 0.7), a)
	var altar_g := terrain.ground(CIRCLE.x, CIRCLE.y)
	AssetKit.place(parent, "rock_moss_set_02", altar_g - Vector3(0.0, 0.15, 0.0), 0.7, 1.0, "rock_moss_set_02_rock10")
	_body_box(parent, altar_g + Vector3(0.0, 0.3, 0.0), Vector3(2.0, 0.6, 1.4), 0.7)
	for k in 5:
		var a := rng.randf() * TAU
		var p := CIRCLE + Vector2(cos(a), sin(a)) * rng.randf_range(1.6, 4.0)
		WoodProps.mushrooms(parent, terrain.ground(p.x, p.y), rng)
	# The swallowed one, facing the circle from its east side.
	var sk_pos := CIRCLE + Vector2(CIRCLE_R + 1.2, 1.5)
	var sk_tree := WoodProps.place_tree(parent, WoodProps.Kind.HERO, 2, terrain.ground(sk_pos.x, sk_pos.y), _yaw_towards(CIRCLE - sk_pos), 1.05)
	WoodProps.skeleton(sk_tree, WoodProps.tree(WoodProps.Kind.HERO, 2), rng)
	(ctx["occupied"] as Array).append(Vector3(sk_pos.x, sk_pos.y, 4.0))
	# The lantern tree on the west side reaches over the stones.
	var lt_pos := CIRCLE + Vector2(-CIRCLE_R - 1.0, -2.0)
	var lt_tree := WoodProps.place_tree(parent, WoodProps.Kind.HERO, 0, terrain.ground(lt_pos.x, lt_pos.y), _yaw_towards(CIRCLE - lt_pos), 1.1)
	(ctx["occupied"] as Array).append(Vector3(lt_pos.x, lt_pos.y, 4.0))
	var hangs: PackedVector3Array = WoodProps.tree(WoodProps.Kind.HERO, 0)["hangs"]
	var anchor := lt_tree.transform * hangs[0]
	var best := INF
	for h in hangs:
		var w := lt_tree.transform * h
		var score := Vector2(w.x, w.z).distance_to(CIRCLE) - w.y * 0.6
		if score < best:
			best = score
			anchor = w
	var drop := clampf(anchor.y - terrain.ground(anchor.x, anchor.z).y - 4.6, 1.2, 5.0)
	WoodProps.hanged_lantern(parent, anchor, drop)
	for k in 6:
		_tie(parent, lt_tree.transform * hangs[(k * 5 + 3) % hangs.size()], rng)
	var light_m := _marker(markers, "Light_2", anchor + Vector3(0.0, -drop - 0.5, 0.0))
	var light := OmniLight3D.new()
	light.name = "LanternLight"
	light.light_color = Color(1.0, 0.7, 0.42)
	light.light_energy = 2.2
	light.omni_range = 7.0
	light.omni_attenuation = 1.0
	light.shadow_enabled = false
	light_m.add_child(light)


static func _body_box(parent: Node3D, pos: Vector3, size: Vector3, yaw: float) -> void:
	var body := StaticBody3D.new()
	body.name = "Collider"
	parent.add_child(body)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.transform = Transform3D(Basis(Vector3.UP, yaw), pos)
	body.add_child(cs)


# --- Ground cover --------------------------------------------------------------

## Ferns, scanned roots, fallen trunks, stumps, rocks, bark and twigs.
static func _undergrowth(ctx: Dictionary, parent: Node3D) -> void:
	var terrain: TerrainBuilder = ctx["terrain"]
	var rng: RandomNumberGenerator = ctx["rng"]
	var total := _length()
	var start := 28.0
	var finish := total - 30.0
	var place := func(model: String, d_min: float, d_max: float, sc: Vector2, sink: float, piece_name: String) -> Dictionary:
		for _attempt in 12:
			var s := rng.randf_range(start, finish)
			var t := _tangent(s)
			var n := Vector2(-t.y, t.x)
			var p := _at(s) + n * (1.0 if rng.randf() < 0.5 else -1.0) * rng.randf_range(d_min, d_max)
			if _path_distance(p) < d_min - 0.3 or _forest(terrain, p) < 0.3 or _open(ctx, p, -0.5):
				continue
			var piece := piece_name if piece_name != "" else AssetKit.random_piece(model, rng)
			var scale := rng.randf_range(sc.x, sc.y)
			var node := AssetKit.place(parent, model, terrain.ground(p.x, p.y) - Vector3(0.0, sink * scale, 0.0), rng.randf() * TAU, scale, piece)
			return {"node": node, "p": p, "t": t, "scale": scale}
		return {}
	for k in 150:
		var f: Dictionary = place.call("fern_02", 2.3, 6.5, Vector2(1.0, 1.7), 0.05, ["fern_02_b", "fern_02_c", "fern_02_b", "fern_02_d"][k % 4])
		if not f.is_empty():
			_shadow_off(f["node"] as Node3D)
	for k in 14:
		place.call("rock_moss_set_02", 2.8, 11.0, Vector2(0.35, 0.8), 0.15, "")
	for k in 6:
		place.call("rock_moss_set_01", 7.0, 16.0, Vector2(0.5, 0.8), 0.25, "")
	for k in 22:
		place.call("bark_debris_01", 2.0, 6.0, Vector2(1.2, 2.0), 0.0, "")
	for k in 14:
		place.call("dry_branches_medium_01", 2.2, 8.0, Vector2(1.3, 2.2), 0.0, "")
	for k in 5:
		place.call(["tree_stump_01", "tree_stump_02"][k % 2], 5.0, 14.0, Vector2(1.0, 1.4), 0.1, "")
	for k in 3:
		place.call("dead_tree_trunk", 3.5, 9.0, Vector2(1.2, 1.6), 0.05, "")
	# Big fallen trunks lying roughly along the path, with a collider each.
	for k in 5:
		var e: Dictionary = place.call("dead_tree_trunk_02", 6.5, 13.0, Vector2(1.4, 2.0), 0.12, "")
		if e.is_empty():
			continue
		var node := e["node"] as Node3D
		var t: Vector2 = e["t"]
		var yaw := _yaw_towards(t) + rng.randf_range(-0.45, 0.45)
		node.rotation.y = yaw
		var sc: float = e["scale"]
		_body_box(parent, node.position + Vector3(0.0, 0.45 * sc, 0.0), Vector3(3.8 * sc, 0.9 * sc, 0.9 * sc), yaw)
		var p: Vector2 = e["p"]
		WoodProps.mushrooms(parent, terrain.ground(p.x, p.y) + Vector3(0.0, 0.6 * sc, 0.0), rng)
	# Scanned roots crawling from the tunnel trees towards the path; moss and
	# glowing mushrooms in their crooks.
	var tunnel: Array = ctx["tunnel"]
	for i in tunnel.size():
		var e: Dictionary = tunnel[i]
		var pos: Vector2 = e["pos"]
		var to_path := -(Vector2(-_tangent(float(e["s"])).y, _tangent(float(e["s"])).x) * float(e["side"]))
		if i % 3 == 0:
			var rp := pos + to_path * 1.7
			var model := "root_cluster_02" if i % 2 == 0 else "single_root"
			var ryaw := _yaw_towards(to_path) + PI * 0.5 + rng.randf_range(-0.4, 0.4)
			var rg := terrain.ground(rp.x, rp.y) - Vector3(0.0, 0.04, 0.0)
			AssetKit.place(parent, model, rg, ryaw, rng.randf_range(1.2, 1.7), AssetKit.random_piece(model, rng))
		if i % 4 == 1:
			var mp := pos + to_path * 1.4 + Vector2(-to_path.y, to_path.x) * rng.randf_range(-1.0, 1.0)
			WoodProps.mushrooms(parent, terrain.ground(mp.x, mp.y), rng)
	# Ferns in the deeper wood and around the clearings.
	var area := Rect2(25.0, 50.0, 160.0, 280.0)
	var placed := 0
	var tries := 0
	while placed < 40 and tries < 2000:
		tries += 1
		var p := Vector2(rng.randf_range(area.position.x, area.end.x), rng.randf_range(area.position.y, area.end.y))
		var d := _path_distance(p)
		if d < 7.0 or d > 26.0 or _forest(terrain, p) < 0.3:
			continue
		if p.distance_to(CIRCLE) < CIRCLE_R - 1.0 or p.distance_to(GLADE) < GLADE_R - 1.0:
			continue
		placed += 1
		var fern := AssetKit.place(parent, "fern_02", terrain.ground(p.x, p.y), rng.randf() * TAU, rng.randf_range(1.1, 1.9), "fern_02_c" if placed % 2 == 0 else "fern_02_b")
		_shadow_off(fern)


static func _shadow_off(node: Node3D) -> void:
	for n in node.find_children("*", "MeshInstance3D", true, false):
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Deep teal moss-grass on the verges and the clearing floors (chunked MultiMesh).
static func _verge_grass(ctx: Dictionary, parent: Node3D) -> void:
	var terrain: TerrainBuilder = ctx["terrain"]
	var rng: RandomNumberGenerator = ctx["rng"]
	var mat := GRASS_MATERIAL.duplicate() as ShaderMaterial
	mat.set_shader_parameter("base_color", Color(0.02, 0.06, 0.055))
	mat.set_shader_parameter("tip_color", Color(0.16, 0.36, 0.29))
	mat.set_shader_parameter("dry_color", Color(0.1, 0.24, 0.2))
	mat.set_shader_parameter("blades", 21.0)
	mat.set_shader_parameter("pixel_size", 30.0)
	var verge := _group(parent, "Verge")
	var accept := func(p: Vector2) -> bool:
		var d := _path_distance(p)
		return (d > 1.5 and d < 7.5 and _forest(terrain, p) > 0.25) or p.distance_to(GLADE) < GLADE_R or p.distance_to(CIRCLE) < CIRCLE_R
	# One scatter per 12 m tile aligned to GrassScatter's chunk grid: one
	# MultiMesh per tile instead of overlapping windows (fewer draw calls).
	var tile := GrassScatter.CHUNK
	for tx in range(floori(20.0 / tile), ceili(185.0 / tile)):
		for tz in range(floori(45.0 / tile), ceili(335.0 / tile)):
			var rect := Rect2(tx * tile, tz * tile, tile, tile)
			var hits := 0
			for k in 48:
				if accept.call(rect.position + Vector2(rng.randf(), rng.randf()) * tile):
					hits += 1
			if hits == 0:
				continue
			var f := hits / 48.0
			var want := roundi(2.2 * tile * tile * f)
			GrassScatter.scatter(verge, terrain, rect, maxi(want, ceili(want / (4.0 * f))), mat, Vector2(1.0, 0.3), rng, accept, 32.0)


# --- Light and mist ------------------------------------------------------------

static func _moon_shafts(ctx: Dictionary, parent: Node3D) -> void:
	var terrain: TerrainBuilder = ctx["terrain"]
	var rng: RandomNumberGenerator = ctx["rng"]
	var group := _group(parent, "MoonShafts")
	var spots: Array = []
	var s := 40.0
	while s < _length() - 30.0:
		var t := _tangent(s)
		spots.append([_at(s) + Vector2(-t.y, t.x) * rng.randf_range(-2.5, 2.5), rng.randf_range(1.4, 2.6), rng.randf_range(0.1, 0.15)])
		s += rng.randf_range(30.0, 40.0)
	spots.append([GLADE + Vector2(3.5, -1.0), 4.5, 0.13])
	spots.append([CIRCLE + Vector2(1.0, 1.0), 6.0, 0.17])
	var up := -(Basis.from_euler(MOON_EULER) * Vector3(0.0, 0.0, -1.0))
	var rot := Basis(Quaternion(Vector3.UP, up))
	for sp: Array in spots:
		var c: Vector2 = sp[0]
		var mat := ShaderMaterial.new()
		mat.shader = SHAFT_SHADER
		mat.set_shader_parameter("tint", Color(0.62, 0.76, 1.0))
		mat.set_shader_parameter("intensity", float(sp[2]))
		mat.set_shader_parameter("far_start", 50.0)
		mat.set_shader_parameter("far_end", 95.0)
		var mi := MeshInstance3D.new()
		mi.name = "Shaft"
		mi.mesh = _shaft_mesh(float(sp[1]), rng.randf_range(13.0, 16.0))
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.set_meta(MeshMerger.SKIP_META, true)
		mi.visibility_range_end = 100.0
		mi.transform = Transform3D(rot * Basis(Vector3.UP, rng.randf() * PI), terrain.ground(c.x, c.y) - Vector3(0.0, 0.5, 0.0))
		group.add_child(mi)


## Two crossed quads (origin at the bottom centre, extends along +Y).
static func _shaft_mesh(width: float, height: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 2:
		var ax := Vector3.RIGHT if k == 0 else Vector3.BACK
		var a := -ax * width * 0.5
		var b := ax * width * 0.5
		var tl := a + Vector3(0.0, height, 0.0)
		var tr := b + Vector3(0.0, height, 0.0)
		for v: Array in [[tl, Vector2(0, 0)], [tr, Vector2(1, 0)], [b, Vector2(1, 1)], [tl, Vector2(0, 0)], [b, Vector2(1, 1)], [a, Vector2(0, 1)]]:
			st.set_normal(Vector3.UP)
			st.set_uv(v[1] as Vector2)
			st.add_vertex(v[0] as Vector3)
	return st.commit()


## Blue glow where the path dips (the misty opening at the end of the tunnel)
## and low banks along the path; all fade as you walk into them.
static func _mist(ctx: Dictionary, parent: Node3D) -> void:
	var terrain: TerrainBuilder = ctx["terrain"]
	var rng: RandomNumberGenerator = ctx["rng"]
	var group := _group(parent, "BlueMist")
	var glows := [Vector2(101.0, 113.0), Vector2(94.0, 107.0), Vector2(138.5, 190.0), Vector2(130.0, 242.0), Vector2(60.0, 80.0), CIRCLE]
	for k in glows.size():
		var c: Vector2 = glows[k]
		WoodProps.mist(group, terrain.ground(c.x, c.y) + Vector3(0.0, 3.6, 0.0), Vector2(30.0, 11.0), {
			"tint": Color(0.3, 0.46, 1.0), "intensity": 0.5 if c == CIRCLE else 1.1, "billboard": 2, "wisps": 1.4, "seed": float(k),
			"near_start": 10.0, "near_end": 34.0, "far_start": 85.0, "far_end": 115.0, "bottom_soft": 0.35,
		})
	var s := 30.0
	var k := 0
	while s < _length() - 20.0:
		var t := _tangent(s)
		var c := _at(s) + Vector2(-t.y, t.x) * rng.randf_range(-3.0, 3.0)
		WoodProps.mist(group, terrain.ground(c.x, c.y) + Vector3(0.0, 0.9, 0.0), Vector2(rng.randf_range(10.0, 15.0), 2.6), {
			"tint": Color(0.36, 0.5, 0.9), "intensity": 0.22, "billboard": 2, "wisps": 3.0, "seed": float(k) + 10.0,
			"near_start": 3.0, "near_end": 11.0, "far_start": 45.0, "far_end": 70.0, "bottom_soft": 0.6,
		})
		s += rng.randf_range(24.0, 32.0)
		k += 1
	for c: Vector2 in [GLADE, CIRCLE]:
		WoodProps.mist(group, terrain.ground(c.x, c.y) + Vector3(0.0, 0.8, 0.0), Vector2(16.0, 2.4), {
			"tint": Color(0.4, 0.55, 0.95), "intensity": 0.3, "billboard": 2, "wisps": 3.0, "seed": 40.0 + c.x,
			"near_start": 3.0, "near_end": 10.0, "far_start": 45.0, "far_end": 70.0, "bottom_soft": 0.6,
		})


static func _path_light(ctx: Dictionary, parent: Node3D) -> void:
	var terrain: TerrainBuilder = ctx["terrain"]
	var group := _group(parent, "MoonOnPath")
	var s := 26.0
	var k := 0
	var total := _length() - 26.0
	while s < total:
		var lefts := PackedVector3Array()
		var rights := PackedVector3Array()
		var end := minf(s + 40.0, total)
		while s <= end:
			var t := _tangent(s)
			var n := Vector2(-t.y, t.x) * 1.8
			var l := _at(s) + n
			var r := _at(s) - n
			lefts.append(terrain.ground(l.x, l.y))
			rights.append(terrain.ground(r.x, r.y))
			s += 2.0
		if lefts.size() < 2:
			break
		s -= 2.0
		WoodProps.ground_light(group, lefts, rights, {
			"tint": Color(0.55, 0.62, 0.85), "intensity": 0.16, "billboard": 0, "wisps": 2.5, "seed": float(k) * 1.7,
			"near_start": 0.5, "near_end": 3.0, "far_start": 40.0, "far_end": 60.0, "bottom_soft": 0.0, "speed": 0.004,
			"strip": true,
		})
		k += 1
		if end >= total:
			break


static func _motes(ctx: Dictionary, parent: Node3D) -> void:
	var terrain: TerrainBuilder = ctx["terrain"]
	var rng: RandomNumberGenerator = ctx["rng"]
	var group := _group(parent, "Motes")
	var s := 25.0
	while s < _length() - 20.0:
		var pts := PackedVector3Array()
		for k in 50:
			var ss := s + rng.randf_range(0.0, 40.0)
			var t := _tangent(ss)
			var c := _at(ss) + Vector2(-t.y, t.x) * rng.randf_range(-6.0, 6.0)
			pts.append(terrain.ground(c.x, c.y) + Vector3(0.0, rng.randf_range(0.4, 3.5), 0.0))
		WoodProps.motes(group, pts, 0.35, rng)
		s += 40.0
	for c: Vector2 in [GLADE, CIRCLE]:
		var pts := PackedVector3Array()
		for k in 45:
			var a := rng.randf() * TAU
			var p := c + Vector2(cos(a), sin(a)) * sqrt(rng.randf()) * 8.0
			pts.append(terrain.ground(p.x, p.y) + Vector3(0.0, rng.randf_range(0.3, 3.0), 0.0))
		WoodProps.motes(group, pts, 0.5, rng)


# --- Markers -------------------------------------------------------------------

static func _marker(parent: Node3D, marker_name: String, pos: Vector3) -> Marker3D:
	var m := Marker3D.new()
	m.name = marker_name
	m.position = pos
	parent.add_child(m)
	return m


static func _markers(wood: Node3D, terrain: TerrainBuilder, rng: RandomNumberGenerator) -> Node3D:
	var markers := _group(wood, "Markers")
	var total := _length()
	var entrance := Vector2(45.0, 72.0)
	var trigger := _marker(markers, "Trigger", terrain.ground(entrance.x, entrance.y))
	trigger.set_meta("radius", 45.0)
	# More zones along the path (each its own parent so all keep the name Trigger).
	var zone_k := 1
	var zs := 95.0
	while zs < total - 40.0:
		var c := _at(zs)
		var zone := _group(markers, "Zone_%d" % zone_k)
		_marker(zone, "Trigger", terrain.ground(c.x, c.y)).set_meta("radius", 40.0)
		zs += 52.0
		zone_k += 1
	var cz := _group(markers, "Zone_%d" % zone_k)
	_marker(cz, "Trigger", terrain.ground(CIRCLE.x, CIRCLE.y)).set_meta("radius", 22.0)
	var spots := [0.3, 0.62, 0.85]
	for k in 3:
		var s: float = total * float(spots[k])
		var t := _tangent(s)
		var c := _at(s) + Vector2(-t.y, t.x) * rng.randf_range(-1.5, 1.5)
		_marker(markers, "Spawn_Enemy_%d" % (k + 1), terrain.ground(c.x, c.y))
	var ls := total * 0.4
	var lt := _tangent(ls)
	var lp := _at(ls) + Vector2(-lt.y, lt.x) * 2.2
	_marker(markers, "Lore_1", terrain.ground(lp.x, lp.y))
	var ps := total * 0.72
	var pt := _tangent(ps)
	var pp := _at(ps) + Vector2(-pt.y, pt.x) * -2.4
	_marker(markers, "Pickup_1", terrain.ground(pp.x, pp.y))
	var lm := _marker(markers, "Light_1", terrain.ground(GLADE.x + 3.0, GLADE.y - 0.5) + Vector3(0.0, 3.2, 0.0))
	var light := OmniLight3D.new()
	light.name = "ClearingLight"
	light.light_color = Color(0.5, 0.65, 1.0)
	light.light_energy = 0.7
	light.omni_range = 7.0
	light.shadow_enabled = false
	lm.add_child(light)
	return markers
