@tool
class_name ForestBuilder
extends RefCounted
## The forest that fills the kingdom inside the walls (world bible, Phase 4a inc 3).
## Data driven: res://data/world/kingdom_map.json gives the wall, roads, clearings,
## sites and deep zones; tier_at() ports the tier rules of tools/render_world_map.py
## (T0 clearing: no trees, T1 edge, T2 wood, T3 deep; densities from the map).
##
## Trees are WoodProps.forest_tree() silhouettes (tall straight, broad gnarled, bare
## twisted) drawn as MultiMeshInstance3D chunks (CHUNK m squares): per chunk and
## style a detailed copy up to NEAR_END m (chunk centre) and a low-poly copy from
## there to FAR_END, so each chunk costs 2 draw calls per style either way. Trunks
## collide through one StaticBody3D per chunk (CylinderShape3D per trunk, layer 1).
## No tree casts a real-time shadow (the foot is darkened in the vertex colour).
##
## Placement: a jittered lattice at the T3 spacing, thinned per tier to its density,
## keeps ROAD_CLEAR m (+ trunk radius) from every road centreline, SPACING m between
## trunks (SPACING_DEEP in T3) and at least PASS_GAP m of free ground between trunk
## surfaces, WALL_CLEAR m from the wall line, and stays off every solid thing the
## other builders made (colliders and landmark meshes, see _blockers()).
## Seeded on its own (SEED), so the layout does not move when other builders change.
##
## Also: paint_ground() paints the forest floor and the new trails on the terrain
## (before it is built), fit_terrain() makes the terrain cover the wall rect, and
## build() adds the Forest/Markers the populator turns into enemies, lore, a pickup
## and the forest region trigger (meta "box": the whole interior).

const MAP_PATH := "res://data/world/kingdom_map.json"
const SEED := 4004
const CHUNK := 48.0
## Chunk-centre distances: detailed trunks up to NEAR_END, low-poly ones to FAR_END + spread.
const NEAR_END := 46.0
const FAR_END := 66.0
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
## Per tier: [style weights TALL, BROAD, BARE], scale range.
const TIER_STYLE := {1: [0.25, 0.2, 0.55], 2: [0.42, 0.33, 0.25], 3: [0.22, 0.5, 0.28]}
const TIER_SCALE := {1: Vector2(0.8, 1.1), 2: Vector2(0.85, 1.2), 3: Vector2(0.95, 1.35)}
const STYLES := [WoodProps.Style.TALL, WoodProps.Style.BROAD, WoodProps.Style.BARE]
const STYLE_NAMES := ["Tall", "Broad", "Bare"]
## Forest floor paint (terrain B) per tier, and the trail half width (paint R).
const FLOOR_PAINT := [0.0, 0.3, 0.8, 1.0]
const TRAIL_HALF := 1.4
## Per-tree brightness range (instance colour on bark and leaves).
const TINT := Vector2(0.55, 0.8)
## Roads painted on the terrain that kingdom_map.json does not list (old forest path).
const EXTRA_ROADS := [OverworldSpec.FOREST_PATH]

static var _map: Dictionary = {}
static var _tiers := PackedByteArray()


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


## Paints the forest floor (B, softened across tier borders) inside the wall, fades
## the pale dry field (G) where the wood is dense and lays the new trails (R) as pale
## dirt, outside the villages. Call before terrain.build(); T0 ground is left as it was.
static func paint_ground(terrain: TerrainBuilder) -> void:
	var spec := terrain.spec
	var wr := wall_rect()
	var m := map()
	var trails: Array = []
	for road: Dictionary in m["roads"]:
		if str(road["kind"]) == "new":
			trails.append(road["pts"])
	var wobble := FastNoiseLite.new()
	wobble.seed = SEED
	wobble.frequency = 0.15
	var taps := [Vector2.ZERO, Vector2(3.0, 0.0), Vector2(-3.0, 0.0), Vector2(0.0, 3.0), Vector2(0.0, -3.0)]
	for iz in terrain.rows:
		for ix in terrain.cols:
			var x := spec.min_corner.x + ix * spec.cell
			var z := spec.min_corner.y + iz * spec.cell
			if not wr.has_point(Vector2(x, z)):
				continue
			var tier := _tier_cached(x, z)
			var i := iz * terrain.cols + ix
			var c := terrain.paint[i]
			if tier > 0:
				var f := 0.0
				for t: Vector2 in taps:
					f += FLOOR_PAINT[maxi(_tier_cached(x + t.x, z + t.y), 0)]
				f /= taps.size()
				c.b = f
				c.g *= clampf(1.0 - (f - 0.3) * 2.5, 0.0, 1.0)
			if not _in_settlement(Vector2(x, z)):
				var d := INF
				for pts: Array in trails:
					d = minf(d, _polyline_distance(Vector2(x, z), pts))
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

## Adds Node3D "Forest" (Trees chunks + Markers) to `root`. `_shared_rng` is ignored:
## the forest has its own seed. Call after the other builders (it avoids their props).
static func build(root: Node3D, terrain: TerrainBuilder, _shared_rng: RandomNumberGenerator) -> Node3D:
	var forest := Node3D.new()
	forest.name = "Forest"
	root.add_child(forest)
	var trees := scatter(terrain, _blockers(root))
	_markers(forest, terrain)
	_chunks(forest, trees)
	print("ForestBuilder: %d trees" % trees.size())
	return forest


## Tree list [[Vector3 foot, yaw, scale, style index, tier, Vector2 collider centre], ...]
## (deterministic; the collider sits on the leaning trunk, a little off the foot).
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
	var radii: Array[float] = []
	var bases: Array[Vector2] = []
	for st in STYLES:
		radii.append(float(WoodProps.forest_tree(st, false)["radius"]))
		bases.append(WoodProps.forest_tree(st, false)["base"] as Vector2)
	for gz in nz:
		for gx in nx:
			var origin := wr.position + Vector2(gx, gz) * lattice
			var first := origin + Vector2(rng.randf(), rng.randf()) * lattice
			var tier0 := tier_at(first.x, first.y)
			var keep := rng.randf()
			if tier0 <= 0 or keep > density(tier0) / density(3):
				continue
			var style := _pick_style(tier0, rng.randf())
			var srange: Vector2 = TIER_SCALE[tier0]
			var scale := rng.randf_range(srange.x, srange.y)
			var yaw := rng.randf() * TAU
			var radius := radii[style] * scale
			var lean := (bases[style] * scale).rotated(-yaw)
			for attempt in TRIES:
				var p := first if attempt == 0 else origin + Vector2(rng.randf(), rng.randf()) * lattice
				var tier := tier0 if attempt == 0 else tier_at(p.x, p.y)
				if tier <= 0:
					continue
				if road_distance(p) < ROAD_CLEAR + radius:
					continue
				var d_wall := minf(minf(p.x - wr.position.x, wr.end.x - p.x), minf(p.y - wr.position.y, wr.end.y - p.y))
				if d_wall < WALL_CLEAR + radius:
					continue
				if _is_blocked(blocked, p, radius + BLOCK_PAD):
					continue
				if not _spaced(trees, grid_hash, radii, p, p + lean, radius, tier):
					continue
				var key := Vector2i((p / 4.0).floor())
				if not grid_hash.has(key):
					grid_hash[key] = []
				(grid_hash[key] as Array).append(trees.size())
				trees.append([terrain.ground(p.x, p.y), yaw, scale, style, tier, p + lean])
				break
	return trees


static func _pick_style(tier: int, roll: float) -> int:
	var w: Array = TIER_STYLE[tier]
	var acc := 0.0
	for k in w.size():
		acc += float(w[k])
		if roll < acc:
			return k
	return w.size() - 1


## Feet at least the tier spacing apart (the smaller one of the two trees' tiers) and
## the trunk colliders at least PASS_GAP apart.
static func _spaced(trees: Array, grid_hash: Dictionary, radii: Array[float], p: Vector2, col: Vector2, radius: float,
		tier: int) -> bool:
	var spacing := SPACING_DEEP if tier == 3 else SPACING
	var key := Vector2i((p / 4.0).floor())
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			for idx: int in grid_hash.get(key + Vector2i(dx, dz), []):
				var t: Array = trees[idx]
				var q: Vector3 = t[0]
				var other := radii[int(t[3])] * float(t[2])
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

## Per CHUNK square: a Node3D at the chunk centre (ground height) holding per style a
## "Near_<style>" and a "Far_<style>" MultiMeshInstance3D with the same instances
## (complementary visibility ranges from the chunk centre) and a "Trunks" StaticBody3D.
static func _chunks(forest: Node3D, trees: Array) -> void:
	var group := Node3D.new()
	group.name = "Trees"
	forest.add_child(group)
	var meshes := []
	for k in STYLES.size():
		meshes.append([_style_mesh(k, false), _style_mesh(k, true)])
	var cells := {}
	for i in trees.size():
		var foot: Vector3 = trees[i][0]
		var cell := Vector2i(floori(foot.x / CHUNK), floori(foot.z / CHUNK))
		if not cells.has(cell):
			cells[cell] = []
		(cells[cell] as Array).append(i)
	var shapes := {}
	var keys := cells.keys()
	keys.sort()
	var color_rng := RandomNumberGenerator.new()
	color_rng.seed = SEED + 1
	for cell: Vector2i in keys:
		var members: Array = cells[cell]
		var centre := Vector3.ZERO
		for i: int in members:
			centre += trees[i][0] as Vector3
		centre /= members.size()
		var chunk := Node3D.new()
		chunk.name = "Chunk_%d_%d" % [cell.x, cell.y]
		chunk.position = centre
		group.add_child(chunk)
		var body := StaticBody3D.new()
		body.name = "Trunks"
		chunk.add_child(body)
		for k in STYLES.size():
			var xfs: Array[Transform3D] = []
			var tints: Array[Color] = []
			for i: int in members:
				var t: Array = trees[i]
				if int(t[3]) != k:
					continue
				var s: float = t[2]
				var basis := Basis(Vector3.UP, float(t[1])).scaled(Vector3(s, s * color_rng.randf_range(0.92, 1.1), s))
				xfs.append(Transform3D(basis, (t[0] as Vector3) - centre))
				# Darker than the moonlit haze they fade into (near trunks read as silhouettes).
				var v := color_rng.randf_range(TINT.x, TINT.y)
				tints.append(Color(v, v * color_rng.randf_range(0.96, 1.04), v * color_rng.randf_range(0.96, 1.06)))
			if xfs.is_empty():
				continue
			var spread := 0.0
			for xf in xfs:
				spread = maxf(spread, Vector2(xf.origin.x, xf.origin.z).length())
			for far in [false, true]:
				var mmi := _multimesh(meshes[k][1 if far else 0], xfs, tints)
				mmi.name = ("Far_" if far else "Near_") + STYLE_NAMES[k]
				if far:
					mmi.visibility_range_begin = NEAR_END
					mmi.visibility_range_end = FAR_END + spread + 0.5
				else:
					mmi.visibility_range_end = NEAR_END
				chunk.add_child(mmi)
		for i: int in members:
			var t: Array = trees[i]
			var data := WoodProps.forest_tree(STYLES[int(t[3])], false)
			var s: float = t[2]
			var radius := snappedf(float(data["radius"]) * s, 0.05)
			var height := snappedf(3.2 * s, 0.2)
			var key := "%.2f/%.1f" % [radius, height]
			if not shapes.has(key):
				var cyl := CylinderShape3D.new()
				cyl.radius = radius
				cyl.height = height
				shapes[key] = cyl
			var cs := CollisionShape3D.new()
			cs.shape = shapes[key]
			var base: Vector2 = data["base"]
			var off := Basis(Vector3.UP, float(t[1])) * Vector3(base.x * s, 0.0, base.y * s)
			cs.position = (t[0] as Vector3) - centre + off + Vector3(0.0, height * 0.5 - 0.3, 0.0)
			body.add_child(cs)


## Detailed or low-poly mesh of a style: trunk surface (+ leaves surface), materials set.
static func _style_mesh(k: int, far: bool) -> ArrayMesh:
	var data := WoodProps.forest_tree(STYLES[k], far)
	var near := WoodProps.forest_tree(STYLES[k], false)
	var mesh := ArrayMesh.new()
	var trunk := data["trunk"] as ArrayMesh
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, trunk.surface_get_arrays(0))
	mesh.surface_set_material(0, WoodProps.material("forest_bark"))
	# Leaves are shared by both copies (identical clumps): no pop at the switch.
	var leaves := near["leaves"] as ArrayMesh
	if leaves:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, leaves.surface_get_arrays(0))
		mesh.surface_set_material(1, WoodProps.material("forest_leaves"))
	return mesh


static func _multimesh(mesh: Mesh, xfs: Array[Transform3D], tints: Array[Color]) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	# Centred on the chunk node, so the visibility ranges count from the chunk centre
	# (the spread is added by the caller) and both copies switch at the same distance.
	var half := 8.0
	for xf in xfs:
		half = maxf(half, maxf(absf(xf.origin.x), absf(xf.origin.z)) + 8.0)
	mm.custom_aabb = AABB(Vector3(-half, -10.8, -half), Vector3(half * 2.0, 24.8, half * 2.0))
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
		mm.set_instance_color(i, tints[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi


## Markers for the populator (re-homed from the old Whispering Wood pocket).
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
	for s: Array in spots:
		var at: Vector2 = clear[s[1]] + (s[2] as Vector2)
		_marker(markers, str(s[0]), terrain.ground(at.x, at.y))
	var wr := wall_rect()
	var mid := wr.get_center()
	var trigger := _marker(markers, "Trigger", Vector3(mid.x, terrain.height_at(mid.x, mid.y), mid.y))
	trigger.set_meta("box", Vector3(wr.size.x, 120.0, wr.size.y))


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
