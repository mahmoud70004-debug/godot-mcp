@tool
class_name ForestBuilder
extends RefCounted
## The forest that fills the kingdom inside the walls (world bible, Phase 4a inc 3-4).
## Data driven: res://data/world/kingdom_map.json gives the wall, roads, clearings,
## sites and deep zones; tier_at() ports the tier rules of tools/render_world_map.py
## (T0 clearing: no trees, T1 edge, T2 wood, T3 deep; densities from the map).
##
## Trees are ForestTrees styles (tall, broad, bare, elder, hollow, snag, birch clump)
## drawn as MultiMeshInstance3D on two grids, the LOD chosen per tree in the shader
## (ForestTrees.NEAR_END / FAR_END from the camera): "N_x_z" NEAR_CELL squares hold
## the meshes per style and the trunk colliders ("Trunks", one cylinder per trunk,
## layer 1), "F_x_z" FAR_CELL squares every tree's impostor card in one draw. Each zone
## grows its own few styles (fewer draws, and the zones read apart). No tree casts a
## shadow.
## Under them ForestFloor lays the floor, the understory and the green rot.
##
## Placement: a jittered lattice at the T3 spacing, thinned per tier to its density,
## keeps ROAD_CLEAR m (+ trunk radius) from every road centreline, SPACING m between
## trunks (SPACING_DEEP in T3) and at least PASS_GAP m of free ground between trunk
## surfaces, WALL_CLEAR m from the wall line, and stays off every solid thing the
## other builders made (colliders and landmark meshes, see _blockers()). Trees near a
## trail lean over it (the canopy closes in, the trunks stay clear).
## Seeded on its own (SEED), so the layout does not move when other builders change.
##
## Also: paint_ground() paints the forest floor and the narrow trails on the terrain
## (before it is built), fit_terrain() makes the terrain cover the wall rect, and
## build() adds the Forest/Markers the populator turns into enemies, lore, pickups
## and the region triggers (meta "box"; "region" names the region file).

const MAP_PATH := "res://data/world/kingdom_map.json"
const SEED := 4004
## Grid squares (m) of the near trees (+ colliders) and of the impostors.
const NEAR_CELL := 32.0
## Impostors cost 4 triangles each: two cells hold them all (one draw each).
const FAR_CELL := 1000.0
const ROAD_CLEAR := 3.5
const SPACING := 2.4
const SPACING_DEEP := 2.0
## Free ground between two trunk surfaces (the player's capsule is 0.8 m wide).
const PASS_GAP := 0.9
const WALL_CLEAR := 4.0
## Extra clearance around blockers (landmarks, colliders) beyond the trunk radius.
const BLOCK_PAD := 1.0
## Placement attempts per lattice cell before it stays empty.
const TRIES := 6
## Style weights per tier [TALL, BROAD, BARE, ELDER, HOLLOW, SNAG, BIRCH]; the deep zones
## (T3) have their own mix.
const TIER_STYLE := {
	1: [0.2, 0.0, 0.25, 0.0, 0.0, 0.15, 0.4],
	2: [0.34, 0.3, 0.08, 0.0, 0.12, 0.0, 0.16],
	3: [0.25, 0.4, 0.15, 0.0, 0.2, 0.0, 0.0],
}
const ZONE_STYLE := {
	"old_wood": [0.0, 0.42, 0.22, 0.1, 0.26, 0.0, 0.0],
	"weeping_hollow": [0.4, 0.3, 0.0, 0.0, 0.18, 0.12, 0.0],
	"cellar_hollow": [0.0, 0.18, 0.32, 0.0, 0.25, 0.25, 0.0],
}
const TIER_SCALE := {1: Vector2(0.75, 1.05), 2: Vector2(0.85, 1.2), 3: Vector2(0.95, 1.35)}
const STYLES := [ForestTrees.Style.TALL, ForestTrees.Style.BROAD, ForestTrees.Style.BARE, ForestTrees.Style.ELDER,
	ForestTrees.Style.HOLLOW, ForestTrees.Style.SNAG, ForestTrees.Style.BIRCH]
const STYLE_NAMES := ForestTrees.NAMES
## Clearings that get an old giant (ForestTrees ELDER) standing at their edge.
const LANDMARK_ELDERS := ["hunters_camp", "ruined_cart", "scarecrow_ring", "lantern_grove", "standing_stones", "well_glade"]
## Forest floor paint (terrain B) per tier (T0: open clearings inside the wall, not the
## villages), and the trail half width (paint R).
const FLOOR_PAINT := [0.85, 0.9, 1.0, 1.0]
const TRAIL_HALF := 1.3
## Per-tree tints (instance colour on bark and leaves): cold blue-grey, moss green,
## near-black, and the dying rot-brown of the Cellar Hollow.
const TINTS := [Color(0.82, 0.88, 1.0), Color(0.76, 0.95, 0.78), Color(0.5, 0.51, 0.56)]
const TINT_AMBER := Color(0.95, 0.72, 0.52)
## Roads painted on the terrain that kingdom_map.json does not list (old forest path).
const EXTRA_ROADS := [OverworldSpec.FOREST_PATH]
## Trails S4 builds as real roads (not painted here).
const BUILT_ROADS := ["kings_road"]
## Extra encounter / pickup markers: [name, clearing or "" for a raw point, offset or point].
const EXTRA_MARKERS := [
	["Spawn_Enemy_4", "standing_stones", Vector2(3.0, -2.0)],
	["Spawn_Enemy_5", "lantern_grove", Vector2(-3.0, 2.5)],
	["Spawn_Enemy_6", "well_glade", Vector2(2.5, 3.0)],
	["Spawn_Enemy_7", "soldiers_hide", Vector2(-2.0, -3.0)],
	["Spawn_Enemy_8", "", Vector2(58.0, 384.0)],
	["Spawn_Enemy_9", "", Vector2(-80.0, 380.0)],
	["Spawn_Enemy_10", "", Vector2(104.0, 309.0)],
	["Spawn_Enemy_11", "crossroads", Vector2(5.0, 6.0)],
	["Pickup_2", "standing_stones", Vector2(-2.5, 1.5)],
	["Pickup_3", "well_glade", Vector2(-1.5, -2.0)],
	["Pickup_4", "soldiers_hide", Vector2(2.0, 1.0)],
	["Pickup_5", "scarecrow_ring", Vector2(-4.0, 3.0)],
	["Pickup_6", "ruined_cart", Vector2(3.0, -3.5)],
]
## Region files of the deep zones (the rest of the interior is the Kingswood).
const ZONE_REGIONS := {
	"old_wood": "res://data/regions/whispering_wood.tres",
	"weeping_hollow": "res://data/regions/whispering_wood.tres",
	"cellar_hollow": "res://data/regions/cellar_hollow.tres",
}
const KINGSWOOD_REGION := "res://data/regions/kingswood.tres"

static var _map: Dictionary = {}
static var _tiers := PackedByteArray()
static var _shapes := {}


# --- Map + tiers ---------------------------------------------------------------

static func map() -> Dictionary:
	if _map.is_empty():
		var text := FileAccess.get_file_as_string(MAP_PATH)
		var parsed: Variant = JSON.parse_string(text)
		if parsed is Dictionary:
			_map = parsed
		else:
			push_error("ForestBuilder: cannot read %s" % MAP_PATH)
	return _map


static func wall_rect() -> Rect2:
	var w: Dictionary = map()["wall"]
	var lo := _v2(w["min"])
	return Rect2(lo, _v2(w["max"]) - lo)


## Trees per square metre in a tier (0 outside the wall).
static func density(tier: int) -> float:
	if tier < 0:
		return 0.0
	return float(map()["tiers"]["T%d" % tier]["trees_per_100m2"]) / 100.0


## Tier at (x, z): -1 outside the wall, else 0..3 with the rules of
## tools/render_world_map.py tier_map(): deep zones are T3, then the T1 margins
## (wall ring, roads, clearings, sites, fields, gate, citadel), then T0 on top.
static func tier_at(x: float, z: float) -> int:
	var m := map()
	var wr := wall_rect()
	if not (x > wr.position.x and x < wr.end.x and z > wr.position.y and z < wr.end.y):
		return -1
	var p := Vector2(x, z)
	var mg: Dictionary = m["margins"]
	var t0 := false
	var t1 := false
	for c: Dictionary in m["clearings"]:
		var d := p.distance_to(_v2(c["pos"]))
		t0 = t0 or d < float(c["r"])
		t1 = t1 or d < float(c["r"]) + float(mg["clearing"])
	for c: Dictionary in (m["settlements"] as Array) + (m["future_sites"] as Array):
		var d := p.distance_to(_v2(c["pos"]))
		t0 = t0 or d < float(c["r"])
		t1 = t1 or d < float(c["r"]) + float(mg["site"])
	for s: Dictionary in m["settlements"]:
		for f: Array in s.get("fields", []):
			t0 = t0 or _in_rect(p, f, 0.0)
			t1 = t1 or _in_rect(p, f, float(mg["site"]))
	var g: Dictionary = m["gate"]
	var dg := p.distance_to(_v2(g["pos"]))
	t0 = t0 or dg < float(g["clearing_radius"])
	t1 = t1 or dg < float(g["clearing_radius"]) + float(mg["gate"])
	var cr: Array = m["citadel"]["rect"]
	t0 = t0 or _in_rect(p, cr, 0.0)
	t1 = t1 or _in_rect(p, cr, float(mg["citadel"]))
	if t0:
		return 0
	var d_wall := minf(minf(x - wr.position.x, wr.end.x - x), minf(z - wr.position.y, wr.end.y - z))
	t1 = t1 or d_wall < float(m["wall"]["ring_width"])
	if not t1:
		for road: Dictionary in m["roads"]:
			if _polyline_distance(p, road["pts"]) < float(mg["road"]):
				t1 = true
				break
	if t1:
		return 1
	for zone: Dictionary in m["deep_zones"]:
		if p.distance_to(_v2(zone["pos"])) < float(zone["r"]):
			return 3
	return 2


## Distance from (x, z) to the nearest road centreline (map roads + EXTRA_ROADS).
static func road_distance(p: Vector2) -> float:
	var best := INF
	for road: Dictionary in map()["roads"]:
		best = minf(best, _polyline_distance(p, road["pts"]))
	for pts: Array in EXTRA_ROADS:
		best = minf(best, _polyline_distance(p, pts))
	return best


## Id of the deep zone (kingdom_map.json deep_zones) at (x, z), or "".
static func zone_at(x: float, z: float) -> String:
	for zone: Dictionary in map()["deep_zones"]:
		if Vector2(x, z).distance_to(_v2(zone["pos"])) < float(zone["r"]):
			return str(zone["id"])
	return ""


## Narrow trails painted here (map roads of kind "new" that nobody else builds).
static func trails() -> Array:
	var out: Array = []
	for road: Dictionary in map()["roads"]:
		if str(road["kind"]) == "new" and not (str(road["id"]) in BUILT_ROADS):
			out.append(road["pts"])
	return out


## Tier per 1 m cell of the wall rect (cell centres, like the map renderer), cached.
static func tier_grid() -> PackedByteArray:
	if _tiers.is_empty():
		var wr := wall_rect()
		var w := int(wr.size.x)
		var h := int(wr.size.y)
		_tiers.resize(w * h)
		for iz in h:
			for ix in w:
				_tiers[iz * w + ix] = maxi(tier_at(wr.position.x + ix + 0.5, wr.position.y + iz + 0.5), 0)
	return _tiers


static func _tier_cached(x: float, z: float) -> int:
	var wr := wall_rect()
	var ix := int(floor(x - wr.position.x))
	var iz := int(floor(z - wr.position.y))
	if ix < 0 or iz < 0 or ix >= int(wr.size.x) or iz >= int(wr.size.y):
		return -1
	return tier_grid()[iz * int(wr.size.x) + ix]


# --- Terrain --------------------------------------------------------------------

## The terrain must reach the far wall (the default spec stops short of it).
static func fit_terrain(spec: TerrainSpec) -> void:
	var wr := wall_rect()
	spec.min_corner = spec.min_corner.min(wr.position - Vector2.ONE * 10.0)
	spec.max_corner = spec.max_corner.max(wr.end + Vector2.ONE * 10.0)


## Paints the forest floor inside the wall (B, softened across tier borders; open
## clearings too, not the villages or the citadel), fades the pale dry field (G), lays
## the narrow trails (R) as pale trampled dirt and marks the floor in the paint alpha
## (terrain.gdshader: more moss in the deep wood, amber leaf litter in the Cellar
## Hollow). Call before terrain.build().
static func paint_ground(terrain: TerrainBuilder) -> void:
	var spec := terrain.spec
	var wr := wall_rect()
	var paths := trails()
	var wobble := FastNoiseLite.new()
	wobble.seed = SEED
	wobble.frequency = 0.15
	var citadel: Array = map()["citadel"]["rect"]
	var cellar: Dictionary = {}
	for zone: Dictionary in map()["deep_zones"]:
		if str(zone["id"]) == "cellar_hollow":
			cellar = zone
	var taps := [Vector2.ZERO, Vector2(3.0, 0.0), Vector2(-3.0, 0.0), Vector2(0.0, 3.0), Vector2(0.0, -3.0)]
	for iz in terrain.rows:
		for ix in terrain.cols:
			var x := spec.min_corner.x + ix * spec.cell
			var z := spec.min_corner.y + iz * spec.cell
			var p := Vector2(x, z)
			if not wr.has_point(p) or _in_settlement(p) or _in_rect(p, citadel, 2.0):
				continue
			var i := iz * terrain.cols + ix
			var c := terrain.paint[i]
			var f := 0.0
			for t: Vector2 in taps:
				f += FLOOR_PAINT[maxi(_tier_cached(x + t.x, z + t.y), 0)]
			f /= taps.size()
			c.b = maxf(c.b, f)
			c.g *= clampf(1.0 - (f - 0.3) * 2.5, 0.0, 1.0)
			# Moss: some on the edges, a lot in the deep wood; amber litter in the Cellar Hollow.
			var tier := _tier_cached(x, z)
			var moss: float = [0.35, 0.45, 0.75, 1.0][maxi(tier, 0)]
			c.a = 1.0 - 0.5 * moss
			if not cellar.is_empty():
				var dc := p.distance_to(_v2(cellar["pos"]))
				var amber := 1.0 - smoothstep(float(cellar["r"]) * 0.7, float(cellar["r"]) * 1.05, dc)
				if amber > 0.0:
					c.a = lerpf(c.a, 0.1, amber)
			var d := INF
			for pts: Array in paths:
				d = minf(d, _polyline_distance(p, pts))
			var w := wobble.get_noise_2d(x, z) * 0.4
			var trail := 1.0 - smoothstep(TRAIL_HALF * 0.6 + w, TRAIL_HALF * 1.3 + w, d)
			c.r = maxf(c.r, trail)
			# Forest floor under the trail too: terrain.gdshader then draws it as the
			# pale moonlit dirt it uses under trees, the readable spine of the forest.
			c.b = maxf(c.b, trail)
			terrain.paint[i] = c


static func _in_settlement(p: Vector2) -> bool:
	for s: Dictionary in map()["settlements"]:
		if p.distance_to(_v2(s["pos"])) < float(s["r"]):
			return true
		for f: Array in s.get("fields", []):
			if _in_rect(p, f, 0.0):
				return true
	return false


# --- Build ----------------------------------------------------------------------

## Adds Node3D "Forest" (Trees cells, Floor, Wrong, Markers) to `root`. `_shared_rng`
## is ignored: the forest has its own seed. Call after the other builders (it avoids
## their props).
static func build(root: Node3D, terrain: TerrainBuilder, _shared_rng: RandomNumberGenerator) -> Node3D:
	var forest := Node3D.new()
	forest.name = "Forest"
	root.add_child(forest)
	var blocked := _blockers(root)
	var trees := scatter(terrain, blocked)
	_markers(forest, terrain)
	_chunks(forest, trees)
	ForestFloor.build(forest, trees, terrain, blocked)
	var per_style := []
	per_style.resize(STYLES.size())
	per_style.fill(0)
	for t: Array in trees:
		per_style[int(t[3])] += 1
	print("ForestBuilder: %d trees %s" % [trees.size(), per_style])
	for k in STYLES.size():
		print("ForestBuilder: %s %d tris, impostor %s m" % [STYLE_NAMES[k], ForestTrees.tree(k, 0)["tris"],
			ForestTrees.impostor_size(k)])
	return forest


## Tree list, deterministic: [0 Vector3 foot, 1 yaw, 2 scale, 3 style, 4 tier,
## 5 Vector2 collider centre (on the leaning trunk at 1.6 m), 6 Basis (yaw, lean, height
## stretch; no scale), 7 Color tint, 8 rot glow (0 = none)].
## `blocked` is the 1 m occupancy grid over the wall rect (PackedByteArray, may be empty).
static func scatter(terrain: TerrainBuilder, blocked: PackedByteArray) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var wr := wall_rect()
	var lattice := sqrt(1.0 / density(3))
	var nx := int(ceil(wr.size.x / lattice))
	var nz := int(ceil(wr.size.y / lattice))
	var trees: Array = []
	var grid_hash := {}
	var paths := trails()
	for name: String in LANDMARK_ELDERS:
		_landmark(trees, grid_hash, terrain, blocked, name, rng)
	for gz in nz:
		for gx in nx:
			var origin := wr.position + Vector2(gx, gz) * lattice
			var first := origin + Vector2(rng.randf(), rng.randf()) * lattice
			var tier0 := tier_at(first.x, first.y)
			var keep := rng.randf()
			if tier0 <= 0 or keep > density(tier0) / density(3):
				continue
			var style := _pick_style(tier0, zone_at(first.x, first.y), rng.randf())
			var srange: Vector2 = TIER_SCALE[tier0]
			var scale := rng.randf_range(srange.x, srange.y)
			if style == ForestTrees.Style.ELDER:
				scale = rng.randf_range(0.85, 1.15)
			var yaw := rng.randf() * TAU
			var tilt := rng.randf_range(0.0, 0.09) + (0.12 if style == ForestTrees.Style.SNAG else 0.0)
			var stretch := rng.randf_range(0.92, 1.1)
			var extra := [rng.randf(), rng.randf(), rng.randf(), rng.randf()]
			for attempt in TRIES:
				var p := first if attempt == 0 else origin + Vector2(rng.randf(), rng.randf()) * lattice
				var tier := tier0 if attempt == 0 else tier_at(p.x, p.y)
				if tier <= 0:
					continue
				var y := yaw
				var t := tilt
				# Beside a trail the tree leans over it: the canopy closes in, the trunk stays clear.
				var to_trail := _towards(p, paths)
				if to_trail.z < 10.0 and float(extra[0]) < 0.7:
					y = atan2(-to_trail.y, to_trail.x) + (float(extra[1]) - 0.5) * 0.8
					t = maxf(t, 0.06 + 0.08 * float(extra[2]))
				var tree := _make_tree(terrain, p, y, scale, style, tier, t, stretch)
				if not _fits(tree, trees, grid_hash, blocked, wr):
					continue
				tree.append(_tint(rng, zone_at(p.x, p.y)))
				tree.append(_rot(rng, p, tier))
				_insert(trees, grid_hash, tree)
				break
	return trees


## [foot, yaw, scale, style, tier, collider centre, basis] of a tree at p.
static func _make_tree(terrain: TerrainBuilder, p: Vector2, yaw: float, scale: float, style: int, tier: int, tilt: float,
		stretch: float) -> Array:
	var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, -tilt) * Basis.from_scale(Vector3(1.0, stretch, 1.0))
	var base: Vector2 = ForestTrees.tree(style, 0)["base"]
	var at := basis * Vector3(base.x, 1.6, base.y) * scale
	return [terrain.ground(p.x, p.y), yaw, scale, style, tier, p + Vector2(at.x, at.z), basis]


static func _fits(tree: Array, trees: Array, grid_hash: Dictionary, blocked: PackedByteArray, wr: Rect2) -> bool:
	var foot: Vector3 = tree[0]
	var p := Vector2(foot.x, foot.z)
	var col: Vector2 = tree[5]
	var radius := ForestTrees.radius(int(tree[3])) * float(tree[2])
	for q: Vector2 in [p, col]:
		if road_distance(q) < ROAD_CLEAR + radius:
			return false
		var d_wall := minf(minf(q.x - wr.position.x, wr.end.x - q.x), minf(q.y - wr.position.y, wr.end.y - q.y))
		if d_wall < WALL_CLEAR + radius:
			return false
		if _is_blocked(blocked, q, radius + BLOCK_PAD):
			return false
	return _spaced(trees, grid_hash, p, col, radius, int(tree[4]))


static func _insert(trees: Array, grid_hash: Dictionary, tree: Array) -> void:
	var foot: Vector3 = tree[0]
	var key := Vector2i((Vector2(foot.x, foot.z) / 4.0).floor())
	if not grid_hash.has(key):
		grid_hash[key] = []
	(grid_hash[key] as Array).append(trees.size())
	trees.append(tree)


## An old giant at the edge of a clearing, on the side farthest from the roads.
static func _landmark(trees: Array, grid_hash: Dictionary, terrain: TerrainBuilder, blocked: PackedByteArray, id: String,
		rng: RandomNumberGenerator) -> void:
	for c: Dictionary in map()["clearings"]:
		if str(c["id"]) != id:
			continue
		var best := Vector2.ZERO
		var best_d := -1.0
		for k in 12:
			var a := TAU * k / 12.0
			var p := _v2(c["pos"]) + Vector2(cos(a), sin(a)) * (float(c["r"]) + 6.0)
			var d := road_distance(p)
			if tier_at(p.x, p.y) > 0 and d > best_d:
				best_d = d
				best = p
		if best_d < 0.0:
			return
		var to_c := _v2(c["pos"]) - best
		var tree := _make_tree(terrain, best, atan2(-to_c.y, to_c.x), rng.randf_range(1.05, 1.2), ForestTrees.Style.ELDER,
			tier_at(best.x, best.y), 0.04, 1.0)
		if _fits(tree, trees, grid_hash, blocked, wall_rect()):
			tree.append(TINTS[0])
			tree.append(0.6)
			_insert(trees, grid_hash, tree)


## (direction x, direction z, distance) to the nearest narrow trail.
static func _towards(p: Vector2, paths: Array) -> Vector3:
	var best := INF
	var at := p
	for pts: Array in paths:
		for k in pts.size() - 1:
			var a := _v2(pts[k])
			var b := _v2(pts[k + 1])
			var ab := b - a
			var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0)
			var q := a + ab * t
			if p.distance_to(q) < best:
				best = p.distance_to(q)
				at = q
	var dir := (at - p).normalized() if best > 0.01 else Vector2.RIGHT
	return Vector3(dir.x, dir.y, best)


static func _pick_style(tier: int, zone: String, roll: float) -> int:
	var w: Array = ZONE_STYLE[zone] if tier == 3 and ZONE_STYLE.has(zone) else TIER_STYLE[tier]
	var total := 0.0
	for x: float in w:
		total += x
	var acc := 0.0
	for k in w.size():
		acc += float(w[k]) / total
		if roll < acc:
			return k
	return w.size() - 1


static func _tint(rng: RandomNumberGenerator, zone: String) -> Color:
	var a: Color = TINTS[rng.randi() % TINTS.size()]
	var b: Color = TINTS[rng.randi() % TINTS.size()]
	var c := a.lerp(b, rng.randf())
	if zone == "cellar_hollow":
		c = c.lerp(TINT_AMBER, rng.randf_range(0.4, 0.9))
	var v := rng.randf_range(0.85, 1.1)
	return Color(c.r * v, c.g * v, c.b * v)


## Rot glow of a tree: common in the deep wood and around villages and clearings.
static func _rot(rng: RandomNumberGenerator, p: Vector2, tier: int) -> float:
	var chance: float = [0.0, 0.04, 0.08, 0.45][tier]
	for c: Dictionary in (map()["clearings"] as Array) + (map()["settlements"] as Array):
		if p.distance_to(_v2(c["pos"])) < float(c["r"]) + 26.0:
			chance = maxf(chance, 0.35)
	return rng.randf_range(0.35, 1.0) if rng.randf() < chance else 0.0


## Feet at least the tier spacing apart (the smaller one of the two trees' tiers) and
## the trunk colliders at least PASS_GAP apart.
static func _spaced(trees: Array, grid_hash: Dictionary, p: Vector2, col: Vector2, radius: float, tier: int) -> bool:
	var spacing := SPACING_DEEP if tier == 3 else SPACING
	var key := Vector2i((p / 4.0).floor())
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			for idx: int in grid_hash.get(key + Vector2i(dx, dz), []):
				var t: Array = trees[idx]
				var q: Vector3 = t[0]
				var other := ForestTrees.radius(int(t[3])) * float(t[2])
				var need := minf(spacing, SPACING_DEEP if int(t[4]) == 3 else SPACING)
				var gap := radius + other + PASS_GAP
				if p.distance_squared_to(Vector2(q.x, q.z)) < need * need or col.distance_squared_to(t[5]) < gap * gap:
					return false
	return true


static func _is_blocked(blocked: PackedByteArray, p: Vector2, r: float) -> bool:
	if blocked.is_empty():
		return false
	var wr := wall_rect()
	var w := int(wr.size.x)
	var h := int(wr.size.y)
	var q := p - wr.position
	for iz in range(maxi(int(floor(q.y - r)), 0), mini(int(floor(q.y + r)), h - 1) + 1):
		for ix in range(maxi(int(floor(q.x - r)), 0), mini(int(floor(q.x + r)), w - 1) + 1):
			if blocked[iz * w + ix] == 0:
				continue
			# Nearest point of the cell to p.
			var cx := clampf(q.x, ix, ix + 1.0)
			var cz := clampf(q.y, iz, iz + 1.0)
			if Vector2(cx, cz).distance_squared_to(q) < r * r:
				return true
	return false


## 1 m occupancy grid over the wall rect of everything solid other builders placed:
## every collision shape (not the terrain, not areas) and every landmark-sized mesh
## (merged-away originals included; ground decals, grass, far cards and merged chunks
## skipped). Meshes lying entirely in T0 ground are skipped (no tree goes there).
static func _blockers(root: Node3D) -> PackedByteArray:
	var wr := wall_rect()
	var w := int(wr.size.x)
	var h := int(wr.size.y)
	var grid := PackedByteArray()
	grid.resize(w * h)
	var marked := 0
	for node in root.find_children("*", "CollisionShape3D", true, false):
		var cs := node as CollisionShape3D
		if cs.shape == null or cs.shape is HeightMapShape3D or cs.shape is WorldBoundaryShape3D or cs.disabled:
			continue
		if not (cs.get_parent() is PhysicsBody3D):
			continue
		var box := cs.global_transform * cs.shape.get_debug_mesh().get_aabb()
		if _all_t0(box):
			continue
		marked += _mark_box(grid, box)
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or mi.has_meta(MeshMerger.SKIP_META) or not _solid_owner(root, mi):
			continue
		var xf := mi.global_transform
		var box := xf * mi.get_aabb()
		if box.size.y < 0.35 or box.size.x > 60.0 or box.size.z > 60.0 or _all_t0(box):
			continue
		if not box.intersects(AABB(Vector3(wr.position.x, -100.0, wr.position.y), Vector3(wr.size.x, 200.0, wr.size.y))):
			continue
		var faces := mi.mesh.get_faces()
		for f in range(0, faces.size(), 3):
			var a := xf * faces[f]
			var b := xf * faces[f + 1]
			var c := xf * faces[f + 2]
			var tri := AABB(a, Vector3.ZERO).expand(b).expand(c)
			# Only what stands up from the ground: skip faces lying flat at foot level.
			if tri.end.y - tri.position.y < 0.05 and tri.end.y < mi.global_position.y + 0.3:
				continue
			marked += _mark_box(grid, tri)
	print("ForestBuilder: %d blocked cells" % marked)
	return grid


## Scenery that should push trees away: not the terrain, the forest itself, the far
## silhouette cards or ground-hugging grass; merged chunks stand in for originals
## that are still there (hidden), so the originals are used instead.
static func _solid_owner(root: Node3D, mi: MeshInstance3D) -> bool:
	var n: Node = mi
	while n != null and n != root:
		if n.name in [&"Terrain", &"Far", &"Grass", &"Forest", &"OuterWard"]:
			return false
		n = n.get_parent()
	var nm := String(mi.name)
	return not (nm.contains("Merged") or nm.contains("ShadowProxy") or nm.begins_with("Chunk_"))


static func _all_t0(box: AABB) -> bool:
	for corner: Vector2 in [Vector2(box.position.x, box.position.z), Vector2(box.end.x, box.position.z),
			Vector2(box.position.x, box.end.z), Vector2(box.end.x, box.end.z), Vector2(box.get_center().x, box.get_center().z)]:
		if tier_at(corner.x, corner.y) != 0:
			return false
	return true


static func _mark_box(grid: PackedByteArray, box: AABB) -> int:
	var wr := wall_rect()
	var w := int(wr.size.x)
	var h := int(wr.size.y)
	var x0 := maxi(int(floor(box.position.x - wr.position.x)), 0)
	var x1 := mini(int(floor(box.end.x - wr.position.x)), w - 1)
	var z0 := maxi(int(floor(box.position.z - wr.position.y)), 0)
	var z1 := mini(int(floor(box.end.z - wr.position.y)), h - 1)
	var n := 0
	for iz in range(z0, z1 + 1):
		for ix in range(x0, x1 + 1):
			if grid[iz * w + ix] == 0:
				grid[iz * w + ix] = 1
				n += 1
	return n


# --- Output ---------------------------------------------------------------------

## Trees under Forest/Trees on two grids (see the class comment): per NEAR_CELL square
## "N_x_z" (Near_<Style> + "Trunks"), per FAR_CELL square "F_x_z" ("Far": every
## impostor). Each cell node sits at its trees' centroid; its visibility range covers
## the farthest tree's LOD band plus the spread.
static func _chunks(forest: Node3D, trees: Array) -> void:
	var group := Node3D.new()
	group.name = "Trees"
	forest.add_child(group)
	var reach := []
	for k in STYLES.size():
		reach.append(ForestTrees.impostor_size(k) * 0.5 * 1.4)
	for grid: Array in [["N_", NEAR_CELL, 0], ["F_", FAR_CELL, 2]]:
		var cells := {}
		for i in trees.size():
			var foot: Vector3 = trees[i][0]
			var cell := Vector2i(floori(foot.x / float(grid[1])), floori(foot.z / float(grid[1])))
			if not cells.has(cell):
				cells[cell] = []
			(cells[cell] as Array).append(i)
		var keys := cells.keys()
		keys.sort()
		for cell: Vector2i in keys:
			var members: Array = cells[cell]
			var centre := Vector3.ZERO
			for i: int in members:
				centre += trees[i][0] as Vector3
			centre /= members.size()
			var node := Node3D.new()
			node.name = "%s%d_%d" % [grid[0], cell.x, cell.y]
			node.position = centre
			group.add_child(node)
			if int(grid[2]) == 0:
				_style_set(node, trees, members, reach)
				_trunks(node, trees, members)
			else:
				_impostors(node, trees, members, reach)


## One MultiMeshInstance3D per style present: "Near_<Style>".
static func _style_set(node: Node3D, trees: Array, members: Array, reach: Array) -> void:
	for k in STYLES.size():
		var items: Array = []
		for i: int in members:
			var t: Array = trees[i]
			if int(t[3]) == k:
				items.append([_xf(t, node.position), Color(0.0, 0.0, float(t[8]), 0.0), t[7]])
		if items.is_empty():
			continue
		var mmi := _multimesh(ForestTrees.tree(k, 0)["mesh"] as Mesh, items, reach[k] as Vector2)
		mmi.name = "Near_" + STYLE_NAMES[k]
		mmi.visibility_range_end = ForestTrees.NEAR_END + _spread(items) + 2.0
		node.add_child(mmi)


## Every tree's impostor in one MultiMesh: the card scaled to the style's size, its
## atlas cell in the custom data.
static func _impostors(node: Node3D, trees: Array, members: Array, reach: Array) -> void:
	var items: Array = []
	var big := Vector2.ONE
	for i: int in members:
		var t: Array = trees[i]
		var k: int = t[3]
		var size := ForestTrees.impostor_size(k)
		var xf := _xf(t, node.position)
		xf.basis = xf.basis * Basis.from_scale(Vector3(size.x, size.y, size.x))
		var cell := ForestAtlas.impostor_rect(k)
		items.append([xf, Color(float(cell.position.x) / ForestAtlas.SIZE, float(cell.position.y) / ForestAtlas.SIZE, 0.0, 0.0), t[7]])
		big = big.max(reach[k] as Vector2)
	var mmi := _multimesh(ForestFloor.mesh("card"), items, big)
	mmi.name = "Far"
	mmi.material_override = ForestTrees.material("far")
	mmi.visibility_range_end = ForestTrees.FAR_END + _spread(items) + 2.0
	node.add_child(mmi)


## Instance transform of a tree relative to its cell node.
static func _xf(t: Array, origin: Vector3) -> Transform3D:
	return Transform3D((t[6] as Basis).scaled(Vector3.ONE * float(t[2])), (t[0] as Vector3) - origin)


static func _spread(items: Array) -> float:
	var spread := 0.0
	for it: Array in items:
		var o := (it[0] as Transform3D).origin
		spread = maxf(spread, Vector2(o.x, o.z).length())
	return spread


## "Trunks": one upright cylinder per tree on its leaning trunk (layer 1, unscaled).
static func _trunks(node: Node3D, trees: Array, members: Array) -> void:
	var body := StaticBody3D.new()
	body.name = "Trunks"
	node.add_child(body)
	for i: int in members:
		var t: Array = trees[i]
		var s: float = t[2]
		var radius := snappedf(ForestTrees.radius(int(t[3])) * s, 0.05)
		var height := snappedf(3.2 * s, 0.2)
		var key := "%.2f/%.1f" % [radius, height]
		if not _shapes.has(key):
			var cyl := CylinderShape3D.new()
			cyl.radius = radius
			cyl.height = height
			_shapes[key] = cyl
		var cs := CollisionShape3D.new()
		cs.shape = _shapes[key]
		var col: Vector2 = t[5]
		var foot: Vector3 = t[0]
		cs.position = Vector3(col.x, foot.y, col.y) - node.position + Vector3(0.0, height * 0.5 - 0.3, 0.0)
		body.add_child(cs)


static func _multimesh(mesh: Mesh, items: Array, reach: Vector2) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	# Centred on the cell node, so the visibility ranges count from the cell centre.
	var half := 8.0
	for it: Array in items:
		var o := (it[0] as Transform3D).origin
		half = maxf(half, maxf(absf(o.x), absf(o.z)) + reach.x)
	var top := reach.y * 2.0 + 12.0
	mm.custom_aabb = AABB(Vector3(-half, -top, -half), Vector3(half * 2.0, top * 2.0, half * 2.0))
	mm.mesh = mesh
	mm.instance_count = items.size()
	for i in items.size():
		var it: Array = items[i]
		mm.set_instance_transform(i, it[0])
		mm.set_instance_custom_data(i, it[1])
		mm.set_instance_color(i, it[2])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi


## Markers for the populator: encounters and pickups in the clearings and along the
## trails, the hunter's note, and the region triggers: "Trigger" (the Kingswood, the
## whole interior) and "Trigger_<zone>" per deep zone (a box inside its circle). Each
## trigger names its region file in meta "region" and its size in meta "box".
static func _markers(forest: Node3D, terrain: TerrainBuilder) -> void:
	var markers := Node3D.new()
	markers.name = "Markers"
	forest.add_child(markers)
	var clear := {}
	for c: Dictionary in map()["clearings"]:
		clear[str(c["id"])] = _v2(c["pos"])
	var spots := [
		["Spawn_Enemy_1", "hunters_camp", Vector2(4.0, 3.0)],
		["Spawn_Enemy_2", "ruined_cart", Vector2(-3.0, 2.0)],
		["Spawn_Enemy_3", "scarecrow_ring", Vector2(2.0, -4.0)],
		["Lore_1", "hunters_camp", Vector2(-3.5, -2.5)],
		["Pickup_1", "lantern_grove", Vector2(1.5, 0.5)],
	]
	spots.append_array(EXTRA_MARKERS)
	for s: Array in spots:
		var at: Vector2 = (clear[s[1]] as Vector2) + (s[2] as Vector2) if str(s[1]) != "" else s[2] as Vector2
		_marker(markers, str(s[0]), terrain.ground(at.x, at.y))
	var wr := wall_rect()
	var mid := wr.get_center()
	var trigger := _marker(markers, "Trigger", Vector3(mid.x, terrain.height_at(mid.x, mid.y), mid.y))
	trigger.set_meta("box", Vector3(wr.size.x, 120.0, wr.size.y))
	trigger.set_meta("region", KINGSWOOD_REGION)
	for zone: Dictionary in map()["deep_zones"]:
		var c := _v2(zone["pos"])
		# The square of the same area as the circle: a little outside on the axes,
		# a little inside on the diagonals.
		var side := float(zone["r"]) * sqrt(PI)
		var z := _marker(markers, "Trigger_" + str(zone["id"]), Vector3(c.x, terrain.height_at(c.x, c.y), c.y))
		z.set_meta("box", Vector3(side, 120.0, side))
		z.set_meta("region", ZONE_REGIONS[str(zone["id"])])


static func _marker(parent: Node3D, marker_name: String, pos: Vector3) -> Marker3D:
	var m := Marker3D.new()
	m.name = marker_name
	m.position = pos
	parent.add_child(m)
	return m


# --- Geometry helpers -------------------------------------------------------------

static func _v2(a: Variant) -> Vector2:
	if a is Vector2:
		return a
	var arr: Array = a
	return Vector2(float(arr[0]), float(arr[1]))


## Inside rect [x0, z0, x1, z1] grown by `grow` (open bounds, like the renderer).
static func _in_rect(p: Vector2, r: Array, grow: float) -> bool:
	return p.x > float(r[0]) - grow and p.x < float(r[2]) + grow and p.y > float(r[1]) - grow and p.y < float(r[3]) + grow


static func _polyline_distance(p: Vector2, pts: Array) -> float:
	var best := INF
	for k in pts.size() - 1:
		var a := _v2(pts[k])
		var b := _v2(pts[k + 1])
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t))
	return best
