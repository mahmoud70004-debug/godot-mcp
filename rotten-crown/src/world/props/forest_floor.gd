@tool
class_name ForestFloor
extends RefCounted
## The forest floor and understory of the kingdom forest (ForestBuilder): ground cover,
## ferns, bushes, dead weeds, brambles hugging the trails, hanging moss, fallen logs,
## stumps, mossy boulders and mounds, root tangles, mushrooms and the green rot (the
## curse made visible: glowing pustules and wet veins, densest in the deep zones and
## around the villages and clearings), plus a few rare "wrong" growths.
##
## Per CELL m square three MultiMeshInstance3D at most:
## "Cards" (every card: one tiled atlas card mesh, tile and mode per instance),
## "Small" and "Large" (one mesh each holding several solid kits; the instance picks its
## kit, the shader drops the others). Everything stops drawing past RANGE m (per
## instance, in the shader; fog hides the rest). Logs, boulders and big stumps of
## 0.6 m and more collide (StaticBody3D "Obstacles", layer 1), never on a road and never
## closing the gap between two obstacles (ForestBuilder rules).

const RANGE := 30.0
## The small kits (mushrooms, pustules, mounds...) stop sooner: they are many and small.
const SMALL_RANGE := 22.0
const CELL := 48.0
## Small kits (mesh "Small") and large kits (mesh "Large"): kit id = UV2.x.
enum Small { MOUND, MUSHROOMS, PUSTULES, ROOTS, STUMP }
enum Large { BOULDER, LOG, HOLLOW_LOG, BIG_STUMP }
const CARD_MODE_UPRIGHT := 0.0
const CARD_MODE_FLAT := 1.0
const CARD_MODE_HANG := 2.0
const PALE := Color(0.72, 0.76, 0.72)
const STONE := Color(0.3, 0.32, 0.36)
const WOOD := Color(0.42, 0.36, 0.3)

static var _meshes: Dictionary = {}


## Mesh of a family ("small", "large", "card"), built once.
static func mesh(family: String) -> ArrayMesh:
	if not _meshes.has(family):
		match family:
			"small":
				_meshes[family] = _small_mesh()
			"large":
				_meshes[family] = _large_mesh()
			_:
				_meshes[family] = _card_mesh()
	return _meshes[family]


## Footprint radius of a large kit at scale 1 (colliders and clearances).
static func large_radius(kit: int) -> float:
	match kit:
		Large.BOULDER:
			return 0.62
		Large.BIG_STUMP:
			return 0.7
	return 0.4


# --- Kit meshes --------------------------------------------------------------------------

static func _kit_acc() -> Dictionary:
	var acc := ForestTrees._acc()
	acc["uv2"] = PackedVector2Array()
	return acc


## Tags every vertex not tagged yet with kit id `kit` (UV2.x).
static func _tag(acc: Dictionary, kit: int) -> void:
	var uv2: PackedVector2Array = acc["uv2"]
	while uv2.size() < (acc["v"] as PackedVector3Array).size():
		uv2.append(Vector2(kit, 0.0))
	acc["uv2"] = uv2


static func _commit(acc: Dictionary, mat: Material) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = acc["v"]
	arrays[Mesh.ARRAY_NORMAL] = acc["n"]
	arrays[Mesh.ARRAY_COLOR] = acc["c"]
	arrays[Mesh.ARRAY_TEX_UV] = acc["uv"]
	arrays[Mesh.ARRAY_TEX_UV2] = acc["uv2"]
	arrays[Mesh.ARRAY_INDEX] = acc["i"]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, mat)
	return mesh


static func _flat(c: Color) -> Callable:
	return func(_a: float, h: float, ny: float) -> Color:
		var f := lerpf(0.55, 1.0, clampf(h * 2.0 + 0.5, 0.0, 1.0))
		var m := c.lerp(ForestTrees.MOSS, clampf(ny, 0.0, 1.0) * 0.6)
		return Color(m.r * f, m.g * f, m.b * f, 1.0)


static func _small_mesh() -> ArrayMesh:
	var acc := _kit_acc()
	var rng := RandomNumberGenerator.new()
	rng.seed = 911
	# Mossy mound: a low dome, unit radius.
	var rings := PackedVector3Array([Vector3(0, -0.15, 0), Vector3(0, 0.2, 0), Vector3(0, 0.36, 0)])
	ForestTrees._tube(acc, rings, PackedFloat32Array([1.05, 0.72, 0.02]), 5, _flat(Color(0.16, 0.3, 0.24)), Vector3.RIGHT)
	_tag(acc, Small.MOUND)
	# Mushrooms: pale caps (glowing when the instance glows), on 0.4 m.
	for k in 3:
		var a := TAU * k / 3.0 + rng.randf_range(-0.4, 0.4)
		var o := Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(0.06, 0.16)
		var h := rng.randf_range(0.1, 0.22)
		var r := h * rng.randf_range(0.5, 0.75)
		ForestTrees._tube(acc, PackedVector3Array([o, o + Vector3(0, h, 0)]), PackedFloat32Array([r * 0.22, r * 0.2]), 3,
			func(_a: float, _h: float, _ny: float) -> Color: return Color(0.55, 0.55, 0.5, 1.0))
		ForestTrees._tube(acc, PackedVector3Array([o + Vector3(0, h - r * 0.15, 0), o + Vector3(0, h + r * 0.15, 0), o + Vector3(0, h + r * 0.45, 0)]),
			PackedFloat32Array([r, r * 0.8, 0.01]), 4, func(_a: float, _h: float, _ny: float) -> Color: return Color(PALE.r, PALE.g, PALE.b, 0.0))
	_tag(acc, Small.MUSHROOMS)
	# Rot pustules: swollen glowing blisters on a dark wet base, unit 0.8 m.
	for k in 4:
		var a := rng.randf() * TAU
		var o := Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(0.0, 0.32)
		var r := rng.randf_range(0.07, 0.16) * (1.4 if k == 0 else 1.0)
		var vein := ForestTrees.VEIN.lerp(Color(0.6, 0.85, 0.3), rng.randf() * 0.5)
		ForestTrees._tube(acc, PackedVector3Array([o + Vector3(0, -r * 0.4, 0), o + Vector3(0, r * 0.6, 0), o + Vector3(0, r * 1.5, 0)]),
			PackedFloat32Array([r, r * 0.95, 0.01]), 4, func(_a: float, hh: float, _ny: float) -> Color:
				return Color(vein.r, vein.g, vein.b, 0.0) if hh > r * 0.2 else Color(0.08, 0.14, 0.04, 0.4))
	_tag(acc, Small.PUSTULES)
	# Root tangle: three roots arching out of the ground and back in, unit 2 m.
	for k in 3:
		var a := TAU * k / 3.0 + rng.randf_range(-0.5, 0.5)
		var d := Vector3(cos(a), 0.0, sin(a))
		var s := Vector3(-d.z, 0.0, d.x) * rng.randf_range(-0.3, 0.3)
		ForestTrees._tube(acc, PackedVector3Array([-d * 0.2 + Vector3(0, -0.2, 0), d * 0.35 + s + Vector3(0, 0.22, 0),
			d * 0.75 + s * 2.0 + Vector3(0, 0.12, 0), d * 1.0 + s * 2.4 + Vector3(0, -0.2, 0)]),
			PackedFloat32Array([0.11, 0.09, 0.06, 0.03]), 3, _flat(Color(0.22, 0.22, 0.25)))
	_tag(acc, Small.ROOTS)
	# Small stump: rough top, unit 0.5 m radius.
	var top := func(a: float, h: float, ny: float) -> Color:
		return WOOD if h > 0.5 and ny > 0.7 else (_flat(Color(0.24, 0.24, 0.28)).call(a, h, ny) as Color)
	ForestTrees._tube(acc, PackedVector3Array([Vector3(0, -0.3, 0), Vector3(0, 0.25, 0), Vector3(0, 0.55, 0.0), Vector3(0, 0.6, 0.0)]),
		PackedFloat32Array([0.55, 0.45, 0.42, 0.02]), 5, top, Vector3.RIGHT)
	_tag(acc, Small.STUMP)
	return _commit(acc, ForestTrees.material("floor_small"))


static func _large_mesh() -> ArrayMesh:
	var acc := _kit_acc()
	var rng := RandomNumberGenerator.new()
	rng.seed = 912
	# Mossy boulder: a lumpy rock, unit 0.62 m footprint (moss on top).
	var lumps := [rng.randf(), rng.randf(), rng.randf()]
	var stone := func(a: float, h: float, ny: float) -> Color:
		var c := STONE.lerp(ForestTrees.MOSS, clampf(ny * 1.4 - 0.2, 0.0, 1.0))
		var f := lerpf(0.5, 1.0, clampf(h * 1.6 + 0.4, 0.0, 1.0)) * (0.85 + 0.15 * sin(a * 3.0 + float(lumps[0]) * 5.0))
		return Color(c.r * f, c.g * f, c.b * f, 1.0)
	ForestTrees._tube(acc, PackedVector3Array([Vector3(0, -0.25, 0), Vector3(0.05, 0.2, 0), Vector3(-0.04, 0.55, 0.03), Vector3(0, 0.78, 0)]),
		PackedFloat32Array([0.6, 0.62, 0.45, 0.04]), 6, stone, Vector3.RIGHT, func(a: float, h: float) -> float:
			return 1.0 + 0.18 * sin(a * 2.0 + float(lumps[1]) * 6.0 + h * 3.0) + 0.1 * sin(a * 5.0 + float(lumps[2]) * 4.0))
	_tag(acc, Large.BOULDER)
	# Fallen log along X, unit radius 0.4 m and 4 m long, moss on its back, a branch stub.
	var log_col := func(_a: float, _h: float, ny: float) -> Color:
		var c := Color(0.26, 0.26, 0.29).lerp(ForestTrees.MOSS, clampf(ny * 1.3, 0.0, 1.0))
		return Color(c.r, c.g, c.b, 1.0)
	var lpts := PackedVector3Array([Vector3(-2.0, 0.3, 0), Vector3(-0.7, 0.33, 0.05), Vector3(0.7, 0.32, -0.05), Vector3(2.0, 0.28, 0)])
	ForestTrees._tube(acc, lpts, PackedFloat32Array([0.38, 0.42, 0.4, 0.36]), 6, log_col, Vector3.UP)
	_cap(acc, Vector3(-2.0, 0.3, 0), Vector3.LEFT, 0.38, 6, WOOD)
	_cap(acc, Vector3(2.0, 0.28, 0), Vector3.RIGHT, 0.36, 6, WOOD.darkened(0.3))
	ForestTrees._tube(acc, PackedVector3Array([Vector3(0.6, 0.6, 0.1), Vector3(0.9, 1.0, 0.35)]), PackedFloat32Array([0.1, 0.03]), 3, log_col)
	_tag(acc, Large.LOG)
	# Hollow log: an open shell, black inside, rot glowing in the dark end.
	var inner := func(_a: float, h: float, _ny: float) -> Color:
		return Color(ForestTrees.VEIN.r * 0.5, ForestTrees.VEIN.g * 0.5, ForestTrees.VEIN.b * 0.5, 0.0) if h < 0.12 else ForestTrees.VOID
	var hpts := PackedVector3Array([Vector3(-2.0, 0.34, 0), Vector3(0.0, 0.36, 0.06), Vector3(2.0, 0.32, 0)])
	ForestTrees._tube(acc, hpts, PackedFloat32Array([0.44, 0.46, 0.42]), 6, log_col, Vector3.UP)
	var start := (acc["v"] as PackedVector3Array).size()
	ForestTrees._tube(acc, hpts, PackedFloat32Array([0.34, 0.36, 0.32]), 6, inner, Vector3.UP)
	_flip(acc, start)
	_tag(acc, Large.HOLLOW_LOG)
	# Big stump with root flares, unit radius 0.7 m.
	var flare := [rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU]
	var big := func(a: float, h: float, ny: float) -> Color:
		return WOOD.darkened(0.15) if h > 0.75 and ny > 0.7 else (_flat(Color(0.24, 0.25, 0.28)).call(a, h, ny) as Color)
	ForestTrees._tube(acc, PackedVector3Array([Vector3(0, -0.4, 0), Vector3(0, 0.15, 0), Vector3(0, 0.8, 0), Vector3(0, 0.88, 0)]),
		PackedFloat32Array([0.7, 0.62, 0.55, 0.03]), 7, big, Vector3.RIGHT, func(a: float, h: float) -> float:
			var m := 1.0
			for f: float in flare:
				var d := wrapf(a - f, -PI, PI)
				m += 0.5 * exp(-d * d / 0.08) * exp(-maxf(h, 0.0) / 0.3)
			return m)
	_tag(acc, Large.BIG_STUMP)
	return _commit(acc, ForestTrees.material("floor_solid"))


## Disc closing a tube end (normal `dir`).
static func _cap(acc: Dictionary, c: Vector3, dir: Vector3, r: float, sides: int, col: Color) -> void:
	var base := (acc["v"] as PackedVector3Array).size()
	var u := dir.cross(Vector3.UP if absf(dir.y) < 0.9 else Vector3.RIGHT).normalized()
	var w := dir.cross(u)
	ForestTrees._vert(acc, c, dir, col.lightened(0.15), ForestTrees.SOLID_UV)
	for j in sides:
		var a := TAU * j / sides
		ForestTrees._vert(acc, c + (u * cos(a) + w * sin(a)) * r, dir, col, ForestTrees.SOLID_UV)
	var idx: PackedInt32Array = acc["i"]
	for j in sides:
		var a := base + 1 + j
		var b := base + 1 + (j + 1) % sides
		if dir.dot(u.cross(w)) > 0.0:
			idx.append_array([base, b, a])
		else:
			idx.append_array([base, a, b])


## Turns the faces made since vertex `start` inside out (inner walls).
static func _flip(acc: Dictionary, start: int) -> void:
	var idx: PackedInt32Array = acc["i"]
	var n: PackedVector3Array = acc["n"]
	for i in range(start, n.size()):
		n[i] = -n[i]
	acc["n"] = n
	for f in range(0, idx.size(), 3):
		if idx[f] >= start:
			var t := idx[f + 1]
			idx[f + 1] = idx[f + 2]
			idx[f + 2] = t
	acc["i"] = idx


## The card: two crossed upright quads (x -0.5..0.5, y 0..1) and one flat quad
## (UV2.x = 1), tile-local UVs; upright normals lean up so the moon lights them evenly.
static func _card_mesh() -> ArrayMesh:
	var acc := _kit_acc()
	var quads := [
		[Vector3(-0.5, 1, 0), Vector3(0.5, 1, 0), Vector3(0.5, 0, 0), Vector3(-0.5, 0, 0)],
		[Vector3(0, 1, -0.5), Vector3(0, 1, 0.5), Vector3(0, 0, 0.5), Vector3(0, 0, -0.5)],
	]
	var uvs := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	for q: Array in quads:
		var base := (acc["v"] as PackedVector3Array).size()
		for k in 4:
			ForestTrees._vert(acc, q[k], Vector3(0.0, 0.8, 0.6).normalized(), Color.WHITE, uvs[k])
		var idx: PackedInt32Array = acc["i"]
		idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	_tag(acc, 0)
	var base := (acc["v"] as PackedVector3Array).size()
	for k in 4:
		var c: Vector2 = [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)][k]
		ForestTrees._vert(acc, Vector3(c.x, 0.04, c.y), Vector3.UP, Color.WHITE, uvs[k])
	_tag(acc, 1)
	var flat_idx: PackedInt32Array = acc["i"]
	flat_idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	return _commit(acc, ForestTrees.material("floor"))


# --- Scatter -----------------------------------------------------------------------------

## Ground kinds: instances per m2 in [T1, T2, T3].
const GROUND := {
	"moss": [0.012, 0.03, 0.04], "litter": [0.02, 0.025, 0.02], "rot": [0.0, 0.003, 0.012],
	"fern": [0.01, 0.07, 0.08], "bush": [0.025, 0.025, 0.008], "weeds": [0.03, 0.004, 0.0],
	"mound": [0.002, 0.007, 0.01], "roots": [0.0, 0.003, 0.006], "stump": [0.002, 0.003, 0.002],
	"pustules": [0.0, 0.001, 0.006], "boulder": [0.002, 0.003, 0.004], "log": [0.0015, 0.003, 0.004],
	"big_stump": [0.001, 0.002, 0.002],
}
## Rot is thicker this close (m) to a village, clearing or site edge.
const ROT_NEAR_SITE := 26.0
const SEED := 4040

var _terrain: TerrainBuilder
var _blocked: PackedByteArray
var _rng := RandomNumberGenerator.new()
## Vector2i cell -> {"cards": [[xf, custom, colour]], "small": [...], "large": [...], "shapes": [[xf, shape]]}
var _cells := {}
## Obstacle circles [Vector2 centre, radius] (trunks + colliding floor kits), hashed by 4 m.
var _obs: Array = []
var _obs_hash := {}
var _tree_hash := {}
var _trees: Array = []
var _stats := {"cards": 0, "small": 0, "large": 0, "colliders": 0, "wrong": 0}


## Adds Forest/Floor (cells of cards and kits, their colliders, the rare growths) for
## the scattered `trees` (ForestBuilder.scatter()); returns counts.
static func build(forest: Node3D, trees: Array, terrain: TerrainBuilder, blocked: PackedByteArray) -> Dictionary:
	var f := ForestFloor.new()
	f._terrain = terrain
	f._blocked = blocked
	f._trees = trees
	f._rng.seed = SEED
	for i in trees.size():
		var t: Array = trees[i]
		var r := ForestTrees.radius(int(t[3])) * float(t[2])
		f._add_obstacle(t[5] as Vector2, r)
		var key := Vector2i(((t[5] as Vector2) / 8.0).floor())
		if not f._tree_hash.has(key):
			f._tree_hash[key] = []
		(f._tree_hash[key] as Array).append(i)
	f._dress_trees()
	f._ground()
	f._trails()
	var node := Node3D.new()
	node.name = "Floor"
	forest.add_child(node)
	f._output(node)
	f._wrong(forest)
	print("ForestFloor: %s" % f._stats)
	return f._stats


# --- Placement helpers ---

func _cell(p: Vector2) -> Dictionary:
	var key := Vector2i((p / CELL).floor())
	if not _cells.has(key):
		_cells[key] = {"cards": [], "small": [], "large": [], "shapes": []}
	return _cells[key]


func _add_obstacle(c: Vector2, r: float) -> void:
	var key := Vector2i((c / 4.0).floor())
	if not _obs_hash.has(key):
		_obs_hash[key] = []
	(_obs_hash[key] as Array).append(_obs.size())
	_obs.append([c, r])


## Free ground of at least `gap` m between a circle and every obstacle.
func _clear_of_obstacles(c: Vector2, r: float, gap: float) -> bool:
	var key := Vector2i((c / 4.0).floor())
	var reach := int(ceil((r + gap + 1.6) / 4.0))
	for dz in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			for i: int in _obs_hash.get(key + Vector2i(dx, dz), []):
				var o: Array = _obs[i]
				if c.distance_to(o[0]) < r + float(o[1]) + gap:
					return false
	return true


## Ground normal (from the terrain heights) as a basis Y with `yaw` around it.
func _ground_basis(p: Vector2, yaw: float) -> Basis:
	var n := Vector3(_terrain.height_at(p.x - 0.5, p.y) - _terrain.height_at(p.x + 0.5, p.y), 1.0,
		_terrain.height_at(p.x, p.y - 0.5) - _terrain.height_at(p.x, p.y + 0.5)).normalized()
	var b := Basis(Vector3.UP, yaw)
	var axis := Vector3.UP.cross(n)
	if axis.length() > 0.001:
		b = Basis(axis.normalized(), Vector3.UP.angle_to(n)) * b
	return b


func _card(pos: Vector3, tile: String, size: Vector2, mode: float, glow: float, tint: Color, yaw := -1.0) -> void:
	var r := ForestAtlas.uv_rect(tile) if tile != "hang" else Rect2(Vector2(ForestAtlas.HANG.position) / ForestAtlas.SIZE, Vector2.ZERO)
	if yaw < 0.0:
		yaw = _rng.randf() * TAU
	var p2 := Vector2(pos.x, pos.z)
	var b := _ground_basis(p2, yaw) if mode == CARD_MODE_FLAT else Basis(Vector3.UP, yaw)
	var xf := Transform3D(b.scaled(Vector3(size.x, size.y if mode != CARD_MODE_FLAT else 1.0, size.x)), pos)
	var w := mode + (10.0 if tile == "hang" else 0.0)
	(_cell(p2)["cards"] as Array).append([xf, Color(r.position.x, r.position.y, glow, w), tint])
	_stats["cards"] += 1


func _kit(family: String, kit: int, pos: Vector3, basis: Basis, glow: float, tint: Color) -> void:
	(_cell(Vector2(pos.x, pos.z))[family] as Array).append([Transform3D(basis, pos), Color(kit, 0.0, glow, 0.0), tint])
	_stats[family] += 1


func _tint(lo: float, hi: float) -> Color:
	var v := _rng.randf_range(lo, hi)
	return Color(v, v * _rng.randf_range(0.95, 1.05), v * _rng.randf_range(0.95, 1.08))


func _density(kind: String, tier: int) -> float:
	return float((GROUND[kind] as Array)[tier - 1]) if tier >= 1 else 0.0


func _near_site(p: Vector2) -> bool:
	var m := ForestBuilder.map()
	for c: Dictionary in (m["clearings"] as Array) + (m["settlements"] as Array):
		if p.distance_to(ForestBuilder._v2(c["pos"])) < float(c["r"]) + ROT_NEAR_SITE:
			return true
	return false


func _usable(p: Vector2, clear: float) -> int:
	var tier := ForestBuilder._tier_cached(p.x, p.y)
	if tier <= 0 or ForestBuilder.road_distance(p) < clear:
		return 0
	return tier


# --- Kinds ---

## Around every tree foot: mushrooms, rot (pustules + veins) on rotting trees, ferns,
## root tangles by the old giants, hanging moss from the limbs.
func _dress_trees() -> void:
	for t: Array in _trees:
		var foot: Vector3 = t[0]
		var tier: int = t[4]
		var style: int = t[3]
		var s: float = t[2]
		var rot: float = t[8]
		var zone := ForestBuilder.zone_at(foot.x, foot.z)
		var r := ForestTrees.radius(style) * s
		var col: Vector2 = t[5]
		var mush: float = [0.04, 0.1, 0.2][tier - 1]
		if zone == "weeping_hollow":
			mush = 0.4
		if _rng.randf() < mush:
			var a := _rng.randf() * TAU
			var at := col + Vector2(cos(a), sin(a)) * (r + _rng.randf_range(0.05, 0.35))
			var pale := zone == "weeping_hollow" or _rng.randf() < 0.2
			_kit("small", Small.MUSHROOMS, _terrain.ground(at.x, at.y), Basis(Vector3.UP, a).scaled(Vector3.ONE * _rng.randf_range(0.9, 1.6)),
				_rng.randf_range(0.7, 1.3) if pale else 0.0, _tint(0.75, 1.0))
		if rot > 0.0:
			if _rng.randf() < 0.5:
				var a := _rng.randf() * TAU
				var at := col + Vector2(cos(a), sin(a)) * (r * 0.8)
				_kit("small", Small.PUSTULES, _terrain.ground(at.x, at.y), Basis(Vector3.UP, a).scaled(Vector3.ONE * _rng.randf_range(0.8, 1.5) * s),
					rot, _tint(0.85, 1.0))
			if _rng.randf() < 0.8:
				_card(_terrain.ground(col.x, col.y), "rot", Vector2.ONE * _rng.randf_range(1.6, 2.8) * s, CARD_MODE_FLAT, rot, Color.WHITE)
		if tier >= 2 and _rng.randf() < 0.45:
			var a := _rng.randf() * TAU
			var at := col + Vector2(cos(a), sin(a)) * (r + _rng.randf_range(0.3, 1.0))
			_card(_terrain.ground(at.x, at.y), "fern", Vector2(_rng.randf_range(1.0, 1.6), _rng.randf_range(0.7, 1.2)), CARD_MODE_UPRIGHT, 0.0, _tint(0.7, 1.0))
		if tier == 3 and style in [ForestTrees.Style.ELDER, ForestTrees.Style.BROAD] and _rng.randf() < 0.3:
			var a := _rng.randf() * TAU
			var at := col + Vector2(cos(a), sin(a)) * (r + 0.8)
			_kit("small", Small.ROOTS, _terrain.ground(at.x, at.y), Basis(Vector3.UP, a).scaled(Vector3.ONE * _rng.randf_range(1.0, 1.6) * s), 0.0, _tint(0.7, 0.95))
		var hang: float = [0.0, 0.12, 0.45][tier - 1]
		if zone == "weeping_hollow":
			hang = 0.85
		elif zone == "cellar_hollow":
			hang *= 0.5
		if hang <= 0.0:
			continue
		var b: Basis = t[6]
		for h: Vector3 in (ForestTrees.tree(style, 0)["hangs"] as PackedVector3Array):
			if _rng.randf() < hang:
				_card(foot + b * h * s, "hang", Vector2(_rng.randf_range(0.6, 1.2), _rng.randf_range(1.2, 3.0) * (1.4 if zone == "weeping_hollow" else 1.0)),
					CARD_MODE_HANG, 0.0, _tint(0.65, 0.95))


## Random ground kinds per cell, by the tier under each candidate.
func _ground() -> void:
	var wr := ForestBuilder.wall_rect()
	var cell := CELL
	var kinds := GROUND.keys()
	kinds.sort()
	for gz in range(int(floor(wr.position.y / cell)), int(ceil(wr.end.y / cell))):
		for gx in range(int(floor(wr.position.x / cell)), int(ceil(wr.end.x / cell))):
			var origin := Vector2(gx, gz) * cell
			for kind: String in kinds:
				var top: float = (GROUND[kind] as Array).max()
				var n := _count(top * cell * cell)
				for i in n:
					var p := origin + Vector2(_rng.randf(), _rng.randf()) * cell
					var roll := _rng.randf()
					var tier := _usable(p, ForestBuilder.ROAD_CLEAR - 0.2)
					if tier == 0 or roll * top > _density(kind, tier):
						continue
					_place(kind, p, tier)


func _count(mean: float) -> int:
	return int(floor(mean + _rng.randf()))


func _place(kind: String, p: Vector2, tier: int) -> void:
	var zone := ForestBuilder.zone_at(p.x, p.y)
	var pos := _terrain.ground(p.x, p.y)
	var near_site := _near_site(p)
	match kind:
		"moss":
			_card(pos, "moss", Vector2.ONE * _rng.randf_range(1.6, 3.2), CARD_MODE_FLAT, 0.0, _tint(0.7, 1.0))
		"litter":
			var amber := zone == "cellar_hollow"
			_card(pos, "litter_amber" if amber else "litter", Vector2.ONE * _rng.randf_range(1.4, 2.6), CARD_MODE_FLAT, 0.0, _tint(0.75, 1.0))
			if amber:
				_card(pos + Vector3(1.2, 0.0, 0.6), "litter_amber", Vector2.ONE * _rng.randf_range(1.4, 2.6), CARD_MODE_FLAT, 0.0, _tint(0.75, 1.0))
		"rot":
			_card(pos, "rot", Vector2.ONE * _rng.randf_range(1.2, 2.6), CARD_MODE_FLAT, _rng.randf_range(0.6, 1.2), Color.WHITE)
		"fern", "bush", "weeds":
			if not _clear_of_obstacles(p, 0.2, 0.0):
				return
			var size := {"fern": Vector2(_rng.randf_range(0.9, 1.5), _rng.randf_range(0.6, 1.1)),
				"bush": Vector2.ONE * _rng.randf_range(1.0, 1.8), "weeds": Vector2(_rng.randf_range(1.0, 1.6), _rng.randf_range(1.0, 1.8))}
			var tile := kind
			if kind == "bush" and zone == "cellar_hollow":
				tile = "bramble"
			_card(pos, tile, size[kind] as Vector2, CARD_MODE_UPRIGHT, 0.0, _tint(0.65, 1.0))
		"mound", "roots", "stump", "pustules":
			if not _clear_of_obstacles(p, 0.3, 0.0):
				return
			var kit: int = {"mound": Small.MOUND, "roots": Small.ROOTS, "stump": Small.STUMP, "pustules": Small.PUSTULES}[kind]
			var s := _rng.randf_range(0.8, 1.8) if kind == "mound" else _rng.randf_range(0.8, 1.3)
			var glow := _rng.randf_range(0.6, 1.2) if kind == "pustules" else 0.0
			_kit("small", kit, pos, _ground_basis(p, _rng.randf() * TAU).scaled(Vector3(s, s * _rng.randf_range(0.7, 1.2), s)), glow, _tint(0.75, 1.0))
		"boulder", "log", "big_stump":
			_large(kind, p, tier)
	if near_site and tier >= 1 and kind == "moss" and _rng.randf() < 0.35:
		_card(pos + Vector3(_rng.randf_range(-1.0, 1.0), 0.0, _rng.randf_range(-1.0, 1.0)), "rot", Vector2.ONE * _rng.randf_range(1.2, 2.2),
			CARD_MODE_FLAT, _rng.randf_range(0.5, 1.0), Color.WHITE)


## A colliding kit: clear of the roads, the walls, other builders' props and with a
## free PASS_GAP to every trunk and other obstacle; logs lie along the slope.
func _large(kind: String, p: Vector2, tier: int) -> void:
	var yaw := _rng.randf() * TAU
	var s := _rng.randf_range(0.9, 2.0) if kind == "boulder" else _rng.randf_range(0.8, 1.25)
	var kit: int = {"boulder": Large.BOULDER, "log": Large.LOG, "big_stump": Large.BIG_STUMP}[kind]
	if kind == "log" and _rng.randf() < 0.35:
		kit = Large.HOLLOW_LOG
	var r := large_radius(kit) * s
	var circles: Array = []
	var axis := Vector2(cos(yaw), -sin(yaw))
	if kind == "log":
		for k in 4:
			circles.append(p + axis * s * lerpf(-1.6, 1.6, k / 3.0))
	else:
		circles.append(p)
	var wr := ForestBuilder.wall_rect()
	for c: Vector2 in circles:
		if ForestBuilder.road_distance(c) < ForestBuilder.ROAD_CLEAR + r or ForestBuilder.tier_at(c.x, c.y) <= 0:
			return
		if minf(minf(c.x - wr.position.x, wr.end.x - c.x), minf(c.y - wr.position.y, wr.end.y - c.y)) < ForestBuilder.WALL_CLEAR + r:
			return
		if ForestBuilder._is_blocked(_blocked, c, r + ForestBuilder.BLOCK_PAD):
			return
		if not _clear_of_obstacles(c, r, ForestBuilder.PASS_GAP):
			return
	var pos := _terrain.ground(p.x, p.y)
	var basis := Basis(Vector3.UP, yaw)
	var shape: Shape3D
	var shape_xf: Transform3D
	match kind:
		"log":
			var a := _terrain.ground(p.x + axis.x * 2.0 * s, p.y + axis.y * 2.0 * s)
			var b := _terrain.ground(p.x - axis.x * 2.0 * s, p.y - axis.y * 2.0 * s)
			var pitch := atan2(a.y - b.y, 4.0 * s)
			basis = basis * Basis(Vector3.BACK, pitch)
			var box := BoxShape3D.new()
			box.size = Vector3(4.0 * s, 0.8 * s, 0.8 * s)
			shape = box
			shape_xf = Transform3D(basis, pos + basis * Vector3(0.0, 0.32 * s, 0.0))
			# Mushrooms along its back now and then.
			if _rng.randf() < 0.5:
				var at := pos + basis * Vector3(_rng.randf_range(-1.4, 1.4) * s, 0.7 * s, 0.0)
				_kit("small", Small.MUSHROOMS, at, Basis(Vector3.UP, yaw), _rng.randf_range(0.5, 1.0) if _rng.randf() < 0.4 else 0.0, _tint(0.8, 1.0))
		"boulder":
			var sphere := SphereShape3D.new()
			sphere.radius = snappedf(0.62 * s, 0.05)
			shape = sphere
			shape_xf = Transform3D(Basis.IDENTITY, pos + Vector3(0.0, 0.2 * s, 0.0))
		_:
			var cyl := CylinderShape3D.new()
			cyl.radius = snappedf(0.62 * s, 0.05)
			cyl.height = snappedf(1.2 * s, 0.1)
			shape = cyl
			shape_xf = Transform3D(Basis.IDENTITY, pos + Vector3(0.0, cyl.height * 0.5 - 0.3, 0.0))
	for c: Vector2 in circles:
		_add_obstacle(c, r)
	var cell := _cell(p)
	(cell["shapes"] as Array).append([shape_xf, shape])
	_stats["colliders"] += 1
	_kit("large", kit, pos, basis.scaled(Vector3.ONE * s), 0.6 if tier == 3 and kit == Large.HOLLOW_LOG else 0.0, _tint(0.75, 1.0))


## The trails as tunnels: brambles and trampled tufts along both edges of the narrow
## trails, and leaves and moss reaching over every road from the trees beside it.
func _trails() -> void:
	for road: Dictionary in ForestBuilder.map()["roads"]:
		var narrow := str(road["kind"]) == "new" and str(road["id"]) != "kings_road"
		var pts: Array = road["pts"]
		for k in pts.size() - 1:
			var a := ForestBuilder._v2(pts[k])
			var b := ForestBuilder._v2(pts[k + 1])
			var dir := (b - a).normalized()
			var side := Vector2(-dir.y, dir.x)
			var length := a.distance_to(b)
			var d := 0.0
			while d < length:
				var c := a + dir * d
				d += 1.4
				for sgn: float in [-1.0, 1.0]:
					var out := side * sgn
					if narrow:
						_edge(c + out * _rng.randf_range(1.8, 2.8), "bramble", Vector2(_rng.randf_range(0.8, 1.3), _rng.randf_range(0.6, 1.0)), 0.5)
						_edge(c + out * _rng.randf_range(1.1, 1.7), "tuft", Vector2(_rng.randf_range(0.5, 0.8), _rng.randf_range(0.35, 0.6)), 0.45)
					# The walls of the tunnel: bushes and ferns crowding in behind the edge.
					var wall := _rng.randf_range(3.2, 6.5) if narrow else _rng.randf_range(4.5, 8.0)
					var tile := "fern" if _rng.randf() < 0.35 else "bush"
					_edge(c + out * wall, tile, Vector2(_rng.randf_range(1.3, 2.2), _rng.randf_range(1.0, 2.0)), 0.5)
					if _rng.randf() < 0.55:
						_overhang(c, out, narrow)


func _edge(p: Vector2, tile: String, size: Vector2, chance: float) -> void:
	if _rng.randf() > chance or ForestBuilder._tier_cached(p.x, p.y) <= 0 or ForestBuilder._in_settlement(p):
		return
	if ForestBuilder.road_distance(p) < 1.0 or not _clear_of_obstacles(p, 0.1, 0.0):
		return
	_card(_terrain.ground(p.x, p.y), tile, size, CARD_MODE_UPRIGHT, 0.0, _tint(0.6, 0.95))


## A leaf clump (and moss) high over the road edge, where a tree's limbs reach over it.
func _overhang(c: Vector2, out: Vector2, narrow: bool) -> void:
	var p := c + out * (_rng.randf_range(1.4, 3.2) if narrow else _rng.randf_range(3.5, 5.0))
	var tier := ForestBuilder._tier_cached(p.x, p.y)
	if tier <= 0 or ForestBuilder._in_settlement(p):
		return
	var owner := _nearest_tree(c + out * 7.0, 9.0)
	if owner < 0:
		return
	var t: Array = _trees[owner]
	var style: int = t[3]
	# Only where the owner's limbs really reach over the spot: a clump or a moss strand
	# anywhere else hangs from nothing (V5: the "floating grass" over the roads).
	var limbs: Vector2 = ForestTrees.STYLES[style]["len"]
	if (t[5] as Vector2).distance_to(p) > limbs.y * float(t[2]) * 0.8:
		return
	if style in [ForestTrees.Style.BARE, ForestTrees.Style.SNAG]:
		var g := _terrain.ground(p.x, p.y)
		_card(g + Vector3(0.0, _rng.randf_range(3.6, 5.0), 0.0), "hang", Vector2(_rng.randf_range(0.6, 1.0), _rng.randf_range(1.2, 2.4)), CARD_MODE_HANG, 0.0, _tint(0.6, 0.9))
		return
	var tile := "leaf_birch" if style == ForestTrees.Style.BIRCH else ("leaf_dying" if style == ForestTrees.Style.HOLLOW else "leaf_dark")
	var size := _rng.randf_range(2.8, 4.2)
	var g := _terrain.ground(p.x, p.y)
	_card(g + Vector3(0.0, _rng.randf_range(3.8, 5.4), 0.0), tile, Vector2.ONE * size, CARD_MODE_UPRIGHT, 0.0, t[7] as Color)
	if tier >= 2 and _rng.randf() < 0.5:
		_card(g + Vector3(0.0, _rng.randf_range(4.2, 5.4), 0.0), "hang", Vector2(_rng.randf_range(0.6, 1.1), _rng.randf_range(1.4, 2.8)), CARD_MODE_HANG, 0.0, _tint(0.6, 0.9))


func _nearest_tree(p: Vector2, within: float) -> int:
	var key := Vector2i((p / 8.0).floor())
	var best := -1
	var best_d := within
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			for i: int in _tree_hash.get(key + Vector2i(dx, dz), []):
				var d := p.distance_to(_trees[i][5])
				if d < best_d:
					best_d = d
					best = i
	return best


# --- Output ---

## Per cell: "Cards", "Small", "Large" MultiMeshInstance3D (centred on what the cell
## holds, drawn up to RANGE m from each instance) and an "Obstacles" StaticBody3D.
func _output(node: Node3D) -> void:
	var lights := node.get_parent().get_parent().find_children("*", "OmniLight3D", true, false) if node.get_parent() else []
	var keys := _cells.keys()
	keys.sort()
	for key: Vector2i in keys:
		var data: Dictionary = _cells[key]
		var base_name := "F_%d_%d" % [key.x, key.y]
		if _lights_on(data, lights) <= MeshMerger.LIGHT_BUDGET:
			_emit(node, base_name, data)
			continue
		# Lanterns close by (the King's Road, the ward): quarter the cell so no part is lit
		# by more lights than the Compatibility renderer shades per object.
		var mid := (Vector2(key) + Vector2(0.5, 0.5)) * CELL
		var parts := [{}, {}, {}, {}]
		for part: Dictionary in parts:
			for family: String in ["cards", "small", "large", "shapes"]:
				part[family] = []
		for family: String in ["cards", "small", "large", "shapes"]:
			for it: Array in data[family]:
				var o := (it[0] as Transform3D).origin
				(parts[(1 if o.x > mid.x else 0) + (2 if o.z > mid.y else 0)][family] as Array).append(it)
		for q in 4:
			_emit(node, "%s_%d" % [base_name, q], parts[q])


## Lights whose range reaches the cell's MultiMesh box (as _emit / _multimesh size it).
func _lights_on(data: Dictionary, lights: Array) -> int:
	var centre := Vector3.ZERO
	var items: Array = []
	for family: String in ["cards", "small", "large"]:
		items.append_array(data[family])
	if items.is_empty():
		return 0
	for it: Array in items:
		centre += (it[0] as Transform3D).origin
	centre /= items.size()
	var half := 4.0
	for it: Array in items:
		var o := (it[0] as Transform3D).origin - centre
		half = maxf(half, maxf(absf(o.x), absf(o.z)) + 4.0)
	var box := AABB(centre - Vector3(half, 10.0, half), Vector3(half * 2.0, 20.0, half * 2.0))
	var n := 0
	for l in lights:
		var light := l as OmniLight3D
		var p := light.global_position
		if p.clamp(box.position, box.end).distance_to(p) < light.omni_range:
			n += 1
	return n


func _emit(node: Node3D, cell_name: String, data: Dictionary) -> void:
	# At the centroid of what it holds: the visibility ranges count from there.
	var centre := Vector2.ZERO
	var n := 0
	for family: String in ["cards", "small", "large"]:
		for it: Array in data[family]:
			var o := (it[0] as Transform3D).origin
			centre += Vector2(o.x, o.z)
			n += 1
	var shapes: Array = data["shapes"]
	if n == 0 and shapes.is_empty():
		return
	if n == 0:
		var o := (shapes[0][0] as Transform3D).origin
		centre = Vector2(o.x, o.z)
		n = 1
	centre /= n
	var cell := Node3D.new()
	cell.name = cell_name
	cell.position = _terrain.ground(centre.x, centre.y)
	node.add_child(cell)
	for family: String in ["cards", "small", "large"]:
		var items: Array = data[family]
		if items.is_empty():
			continue
		var mmi := _multimesh(mesh("card" if family == "cards" else family), items, cell.position,
			SMALL_RANGE if family == "small" else RANGE)
		mmi.name = family.capitalize()
		cell.add_child(mmi)
	if shapes.is_empty():
		return
	var body := StaticBody3D.new()
	body.name = "Obstacles"
	cell.add_child(body)
	for s: Array in shapes:
		var cs := CollisionShape3D.new()
		cs.shape = s[1]
		var xf: Transform3D = s[0]
		cs.transform = Transform3D(xf.basis, xf.origin - cell.position)
		body.add_child(cs)


static func _multimesh(m: Mesh, items: Array, origin: Vector3, reach: float) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = m
	mm.instance_count = items.size()
	var half := 4.0
	var spread := 0.0
	for i in items.size():
		var it: Array = items[i]
		var xf: Transform3D = it[0]
		xf.origin -= origin
		half = maxf(half, maxf(absf(xf.origin.x), absf(xf.origin.z)) + 4.0)
		spread = maxf(spread, Vector2(xf.origin.x, xf.origin.z).length())
		mm.set_instance_transform(i, xf)
		mm.set_instance_custom_data(i, it[1])
		mm.set_instance_color(i, it[2])
	mm.custom_aabb = AABB(Vector3(-half, -8.0, -half), Vector3(half * 2.0, 16.0, half * 2.0))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The shader drops each instance past `reach` m; the node stops drawing once all are.
	mmi.visibility_range_end = reach + spread + 2.0
	return mmi


# --- The wrong things (rare, deep in the forest, far from the first trail) ---

## A few growths that look almost like hands reaching out of the ground beside a tree,
## and bark that almost forms a face (WoodProps.bark_face) on some old giants.
func _wrong(forest: Node3D) -> void:
	var node := Node3D.new()
	node.name = "Wrong"
	forest.add_child(node)
	var hands := {"old_wood": 2, "weeping_hollow": 3, "cellar_hollow": 2}
	var faces := {"old_wood": 2, "weeping_hollow": 1, "cellar_hollow": 1}
	var hand_mat := ForestTrees.material("floor_solid").duplicate() as ShaderMaterial
	hand_mat.set_shader_parameter("glow_base", 0.7)
	var hand := _hand_mesh()
	var face_mat := ForestTrees.material("floor_solid").duplicate() as ShaderMaterial
	face_mat.set_shader_parameter("tint", Color(0.3, 0.32, 0.36))
	face_mat.set_shader_parameter("force_bark", true)
	var order := range(_trees.size())
	for i in order.size():
		var j := _rng.randi_range(i, order.size() - 1)
		var tmp: int = order[i]
		order[i] = order[j]
		order[j] = tmp
	for i: int in order:
		var t: Array = _trees[i]
		var foot: Vector3 = t[0]
		var zone := ForestBuilder.zone_at(foot.x, foot.z)
		if zone == "" or ForestBuilder.road_distance(Vector2(foot.x, foot.z)) < 7.0:
			continue
		var style: int = t[3]
		if int(faces.get(zone, 0)) > 0 and style in [ForestTrees.Style.ELDER, ForestTrees.Style.BROAD]:
			faces[zone] = int(faces[zone]) - 1
			var holder := Node3D.new()
			holder.name = "Face_%d" % (int(_stats["wrong"]) + 1)
			holder.transform = Transform3D((t[6] as Basis).scaled(Vector3.ONE * float(t[2])), foot)
			node.add_child(holder)
			WoodProps.bark_face(holder, ForestTrees.tree(style, 0), _rng)
			for part in holder.find_children("*", "MeshInstance3D", true, false):
				var mi := part as MeshInstance3D
				mi.visibility_range_end = 32.0
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				# Not a pale mask: the relief in the tree's own bark, only the hollows dark.
				if mi.name == &"Relief":
					mi.material_override = face_mat
			_stats["wrong"] += 1
		elif int(hands.get(zone, 0)) > 0:
			hands[zone] = int(hands[zone]) - 1
			var col: Vector2 = t[5]
			var a := _rng.randf() * TAU
			var at := col + Vector2(cos(a), sin(a)) * (ForestTrees.radius(style) * float(t[2]) + 0.45)
			var mi := MeshInstance3D.new()
			mi.name = "Hand_%d" % (int(_stats["wrong"]) + 1)
			mi.mesh = hand
			mi.material_override = hand_mat
			mi.transform = Transform3D(Basis(Vector3.UP, -a).scaled(Vector3.ONE * _rng.randf_range(1.3, 1.7)), _terrain.ground(at.x, at.y))
			mi.visibility_range_end = 30.0
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.add_child(mi)
			_stats["wrong"] += 1


## A pale, rot-veined growth that is almost a hand: a swollen palm half in the ground and
## five long jointed fingers curling up and back towards the tree (+X away from it).
static func _hand_mesh() -> ArrayMesh:
	var acc := _kit_acc()
	var flesh := Color(0.5, 0.54, 0.48)
	var skin := func(a: float, h: float, _ny: float) -> Color:
		if sin(a * 3.0 + h * 9.0) > 0.86:
			return Color(ForestTrees.VEIN.r, ForestTrees.VEIN.g, ForestTrees.VEIN.b, 0.0)
		var f := lerpf(0.5, 1.0, clampf(h * 2.0 + 0.4, 0.0, 1.0))
		return Color(flesh.r * f, flesh.g * f, flesh.b * f, 1.0)
	ForestTrees._tube(acc, PackedVector3Array([Vector3(-0.05, -0.2, 0), Vector3(0.0, 0.08, 0), Vector3(0.06, 0.2, 0), Vector3(0.1, 0.24, 0)]),
		PackedFloat32Array([0.16, 0.17, 0.12, 0.02]), 6, skin, Vector3.RIGHT)
	for k in 5:
		var a := lerpf(-0.9, 0.9, k / 4.0) + (0.0 if k != 0 else -0.5)
		var d := Vector3(cos(a) * 0.5, 0.0, sin(a))
		var base := Vector3(0.05, 0.18, 0.0) + d * 0.1
		var length := 0.42 if k in [1, 2, 3] else 0.3
		var pts := PackedVector3Array([base, base + d * length * 0.35 + Vector3(0.05, length * 0.45, 0.0),
			base + d * length * 0.6 + Vector3(0.12, length * 0.85, 0.0), base + d * length * 0.7 + Vector3(0.24, length * 1.0, 0.0)])
		ForestTrees._tube(acc, pts, PackedFloat32Array([0.035, 0.03, 0.024, 0.008]), 4, skin)
	_tag(acc, 0)
	return _commit(acc, ForestTrees.material("floor_solid"))
