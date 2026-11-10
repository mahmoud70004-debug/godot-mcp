@tool
class_name ForestTrees
extends RefCounted
## Kingdom forest silhouettes for MultiMesh instancing (ForestBuilder): seven styles,
## each grown once as a low-poly NEAR mesh (bark and both-sided leaf cards in one
## alpha-cut surface: one draw per style) and an impostor painted into the shared
## ForestAtlas (two crossed cards, drawn by ForestBuilder for every style at once).
## All of it uses the forest shaders (assets/shaders/forest*.gdshader*): per-vertex lit,
## moonlit rim, vertex-colour bark / moss / rot (rot glows per instance), no shadows.
##
## Tree frame: origin on the ground at the trunk centre, +X the side it leans to; the
## trunk is buried to y = -0.9 so it sits on slopes. Physics is ForestBuilder's job.

enum Style { TALL, BROAD, BARE, ELDER, HOLLOW, SNAG, BIRCH }
const NAMES := ["Tall", "Broad", "Bare", "Elder", "Hollow", "Snag", "Birch"]
## Per-instance LOD bands (metres from the camera to the tree's origin): the mesh up to
## NEAR_END, then the impostor (fog has taken most of the tree by then) up to FAR_END.
## ForestBuilder adds the cell spread to the node ranges.
const NEAR_END := 26.0
const FAR_END := 78.0
const SOLID_SHADER := preload("res://assets/shaders/forest_solid.gdshader")
const CARD_SHADER := preload("res://assets/shaders/forest_card.gdshader")
const FLOOR_SHADER := preload("res://assets/shaders/forest_floor_card.gdshader")
const BARK_TEX := "res://assets/textures/world/bark_brown_02.png"
## Marker UV of solid (non-atlas) vertices: the shader maps the bark scan in world space.
const SOLID_UV := Vector2(-1.0, -1.0)
const MOSS := Color(0.2, 0.33, 0.28)
const VEIN := Color(0.36, 0.6, 0.1)
const VOID := Color(0.025, 0.025, 0.035)

## Per style: trunk radius r0, fork height, lean, wobble, flute twist, buttress roots
## [count, size], limbs [count, rise, droop, length range, radius fraction, rings below
## the fork], leaf tile + clump size range + lowest clump, trunk sides [near, mid],
## bark colour, moss height, rot veins on the foot, stems (birch clump), split (hollow).
const STYLES := {
	Style.TALL: {"r0": 0.42, "fork": 8.0, "lean": 0.3, "wob": 0.18, "twist": 0.6, "roots": 3, "root_size": 0.6,
		"limbs": 4, "rise": 0.93, "drop": 0.3, "len": Vector2(3.0, 4.4), "lrad": 0.5, "below": Vector2i(0, 2),
		"leaf": "leaf_dark", "leaf_size": Vector2(2.3, 3.2), "leaf_min": 5.2, "sides": Vector2i(7, 5),
		"bark": Color(0.4, 0.42, 0.48), "moss_h": 1.8},
	Style.BROAD: {"r0": 0.64, "fork": 4.4, "lean": 1.0, "wob": 0.35, "twist": 1.0, "roots": 4, "root_size": 1.1,
		"limbs": 4, "rise": 0.75, "drop": -0.15, "len": Vector2(5.5, 7.5), "lrad": 0.58, "below": Vector2i(0, 2),
		"leaf": "leaf_dark", "leaf_size": Vector2(2.5, 3.4), "leaf_min": 3.8, "sides": Vector2i(8, 5),
		"bark": Color(0.36, 0.37, 0.4), "moss_h": 2.4, "veins": true},
	Style.BARE: {"r0": 0.38, "fork": 5.4, "lean": 0.9, "wob": 0.6, "twist": 1.6, "roots": 3, "root_size": 0.7,
		"limbs": 3, "rise": 0.85, "drop": 0.1, "len": Vector2(4.0, 6.0), "lrad": 0.55, "below": Vector2i(0, 3),
		"leaf": "", "sides": Vector2i(6, 4), "bark": Color(0.36, 0.37, 0.42), "moss_h": 1.2},
	Style.ELDER: {"r0": 1.25, "fork": 5.2, "lean": 0.8, "wob": 0.4, "twist": 0.8, "roots": 6, "root_size": 1.5,
		"limbs": 5, "rise": 0.7, "drop": -0.2, "len": Vector2(8.5, 11.0), "lrad": 0.55, "below": Vector2i(0, 2),
		"leaf": "leaf_dark", "leaf_size": Vector2(3.2, 4.4), "leaf_min": 5.0, "sides": Vector2i(9, 6),
		"bark": Color(0.42, 0.42, 0.45), "moss_h": 3.2, "veins": true},
	Style.HOLLOW: {"r0": 0.62, "fork": 6.0, "lean": 0.6, "wob": 0.3, "twist": 1.2, "roots": 4, "root_size": 0.9,
		"limbs": 2, "rise": 0.85, "drop": 0.0, "len": Vector2(3.2, 4.6), "lrad": 0.6, "below": Vector2i(0, 1),
		"leaf": "leaf_dying", "leaf_size": Vector2(2.0, 2.8), "leaf_min": 4.5, "sides": Vector2i(8, 5),
		"bark": Color(0.33, 0.34, 0.37), "moss_h": 1.6, "veins": true, "split": 1.9},
	Style.SNAG: {"r0": 0.5, "fork": 3.8, "lean": 1.7, "wob": 0.4, "twist": 1.2, "roots": 3, "root_size": 0.8,
		"limbs": 2, "rise": 0.6, "drop": 0.2, "len": Vector2(1.2, 2.2), "lrad": 0.5, "below": Vector2i(1, 3),
		"leaf": "", "sides": Vector2i(6, 4), "bark": Color(0.3, 0.3, 0.33), "moss_h": 1.0, "broken": true},
	Style.BIRCH: {"r0": 0.15, "fork": 6.5, "lean": 0.5, "wob": 0.12, "twist": 0.3, "roots": 0, "root_size": 0.0,
		"limbs": 2, "rise": 0.9, "drop": 0.2, "len": Vector2(1.8, 2.6), "lrad": 0.6, "below": Vector2i(0, 2),
		"leaf": "leaf_birch", "leaf_size": Vector2(1.7, 2.3), "leaf_min": 3.4, "sides": Vector2i(4, 4),
		"bark": Color(0.72, 0.74, 0.76), "moss_h": 0.6, "stems": 3},
}

static var _cache: Dictionary = {}
static var _mats: Dictionary = {}
static var _impostor_size: Dictionary = {}


## One style, built on first use (`lod` 0; 1 is a coarser copy kept for experiments):
## {mesh: ArrayMesh (one "tree" surface), radius: collider radius at the foot, base:
##  Vector2 trunk centre offset at 1.6 m, hangs: PackedVector3Array (limb undersides),
##  face: {o, out, up, r} bark-face anchor (WoodProps.bark_face), tris: int}.
static func tree(style: int, lod: int) -> Dictionary:
	var key := "%d/%d" % [style, lod]
	if not _cache.has(key):
		_cache[key] = _build(style, lod)
	return _cache[key]


## Collider radius of a style at scale 1 (cheap: no mesh).
static func radius(style: int) -> float:
	var p: Dictionary = STYLES[style]
	if p.has("stems"):
		return 0.45
	return float(p["r0"]) * 0.95


## Size (width, height) of a style's impostor card at scale 1.
static func impostor_size(style: int) -> Vector2:
	if not _impostor_size.has(style):
		_impostor_size[style] = _extent(tree(style, 0)["mesh"] as ArrayMesh)
	return _impostor_size[style]


## Shared materials: "tree" (near trees), "far" (impostors), "floor" (tiled floor cards),
## "floor_solid" (large floor kits), "floor_small" (small kits). Each LOD band is its own
## material.
static func material(id: String) -> ShaderMaterial:
	if _mats.has(id):
		return _mats[id]
	var mat := ShaderMaterial.new()
	match id:
		"floor_solid", "floor_small":
			mat.shader = SOLID_SHADER
		"floor", "far":
			mat.shader = FLOOR_SHADER
		_:
			mat.shader = CARD_SHADER
	mat.set_shader_parameter("atlas", ForestAtlas.texture())
	mat.set_shader_parameter("bark_tex", load(BARK_TEX))
	match id:
		"tree":
			mat.set_shader_parameter("lod_end", NEAR_END)
		"far":
			mat.set_shader_parameter("lod_begin", NEAR_END)
			mat.set_shader_parameter("lod_end", FAR_END)
			mat.set_shader_parameter("rim_strength", 0.0)
			mat.set_shader_parameter("tile_size", Vector2(ForestAtlas.IMPOSTOR) / ForestAtlas.SIZE)
		"floor", "floor_solid":
			mat.set_shader_parameter("lod_end", ForestFloor.RANGE)
			if id == "floor":
				# Ground cards lie flat or stand low: no top light (they would glare).
				mat.set_shader_parameter("top_color", Color(0.04, 0.05, 0.08))
				mat.set_shader_parameter("rim_strength", 0.3)
		"floor_small":
			mat.set_shader_parameter("lod_end", ForestFloor.SMALL_RANGE)
	_mats[id] = mat
	return mat


# --- Building --------------------------------------------------------------------

static func _acc() -> Dictionary:
	return {"v": PackedVector3Array(), "n": PackedVector3Array(), "c": PackedColorArray(), "uv": PackedVector2Array(),
		"i": PackedInt32Array()}


static func _build(style: int, lod: int) -> Dictionary:
	var p: Dictionary = STYLES[style]
	var near := lod == 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 6151 * (style + 1) + 17
	var ctx := {"trunk": _acc(), "leaves": _acc(), "rng": rng, "near": near, "p": p, "clumps": [],
		"hangs": PackedVector3Array(), "face": {}}
	var r0: float = p["r0"]
	var stems := int(p.get("stems", 1))
	var base := Vector2.ZERO
	if stems > 1:
		for k in stems:
			var a := TAU * k / stems + rng.randf_range(-0.3, 0.3)
			var out := Vector3(cos(a), 0.0, -sin(a))
			var spine := _stem(ctx, out * 0.22, out, r0 * rng.randf_range(0.85, 1.15), float(p["fork"]) * rng.randf_range(0.8, 1.05))
			if k == 0:
				base = Vector2(spine[0].x, spine[0].z) * 0.0
	else:
		var spine := _stem(ctx, Vector3.ZERO, Vector3.RIGHT, r0, float(p["fork"]))
		var at := _ring_at(spine, 1.6)
		base = Vector2(at.x, at.z)
	var clumps: Array = ctx["clumps"]
	if not near:
		clumps = _thin(clumps, rng)
	for c: Array in clumps:
		_clump(ctx["leaves"], c[0], float(c[1]), String(p["leaf"]), rng, near)
	var mesh := ArrayMesh.new()
	var trunk: Dictionary = ctx["trunk"]
	_append(trunk, ctx["leaves"])
	_commit(mesh, trunk, material("tree"))
	var tris := (trunk["i"] as PackedInt32Array).size() / 3
	return {"mesh": mesh, "radius": radius(style), "base": base, "hangs": ctx["hangs"], "face": ctx["face"], "tris": tris}


## One trunk from `foot` leaning towards `out` (xz), with roots, limbs and leaf clumps.
## Returns the spine.
static func _stem(ctx: Dictionary, foot: Vector3, out: Vector3, r0: float, fork: float) -> PackedVector3Array:
	var p: Dictionary = ctx["p"]
	var rng: RandomNumberGenerator = ctx["rng"]
	var near: bool = ctx["near"]
	var lobes: Array = []
	var a0 := rng.randf() * TAU
	for j in int(p["roots"]):
		lobes.append([wrapf(a0 + TAU * j / int(p["roots"]) + rng.randf_range(-0.3, 0.3), -PI, PI),
			float(p["root_size"]) * rng.randf_range(0.7, 1.1)])
	var flute_n := float(rng.randi_range(5, 8))
	var twist := float(p["twist"]) * rng.randf_range(0.8, 1.2)
	var broken := bool(p.get("broken", false))
	var split := float(p.get("split", 0.0))
	var jag := [rng.randf(), rng.randf(), rng.randf()]
	var shape := func(a: float, h: float) -> float:
		var m := 1.0 + 0.08 * sin(a * flute_n + h * twist * 2.0)
		var hb := maxf(h, 0.0)
		for l: Array in lobes:
			var d := wrapf(a - float(l[0]), -PI, PI)
			m += float(l[1]) * exp(-d * d / 0.09) * exp(-hb / 0.65)
		if broken and h > fork - 0.6:
			m *= 0.75 + 0.35 * sin(a * 3.0 + float(jag[0]) * 6.0)
		return m
	# Rings: dense at the foot (roots, moss), coarser up the trunk; the mid copy keeps few.
	var hs := PackedFloat32Array([-0.9, 0.0, 0.35, 0.9, 1.7]) if near else PackedFloat32Array([-0.9, 0.2, 1.6])
	var step := 1.6 if near else 2.6
	var h := hs[hs.size() - 1]
	while h < fork - 0.01:
		h = minf(h + step, fork)
		hs.append(h)
	var fork_i := hs.size() - 1
	var lead_len := 0.0 if broken else rng.randf_range(2.5, 4.0)
	if not broken:
		for k in (2 if near else 1):
			hs.append(fork + lead_len * float(k + 1) / (2 if near else 1))
	var ph := rng.randf() * TAU
	var ph2 := rng.randf() * TAU
	var wob: float = p["wob"]
	var lean: float = p["lean"]
	var side := Vector3(-out.z, 0.0, out.x)
	var spine := PackedVector3Array()
	var rads := PackedFloat32Array()
	for hh in hs:
		var u := hh / fork
		var uc := clampf(u, 0.0, 1.0)
		var x := lean * pow(uc, 1.5) + wob * (sin(u * 2.4 + ph) - sin(ph))
		if u > 1.0:
			x += lean * 0.7 * (u - 1.0)
		spine.append(foot + out * x + side * wob * 0.8 * (sin(u * 3.1 + ph2) - sin(ph2)) + Vector3(0.0, hh, 0.0))
		var r := r0 * lerpf(1.0, 0.62, uc)
		if u > 1.0:
			r = r0 * 0.62 * lerpf(1.0, 0.05, (hh - fork) / lead_len)
		if broken and hh >= fork - 0.01:
			r = r0 * 0.6
		rads.append(r)
	var sides: Vector2i = p["sides"]
	var n_sides := sides.x if near else sides.y
	var colour := _bark_colour(p, split)
	if split > 0.0:
		# Hollow: the shared foot up to the split, then two leaders leaning apart.
		var cut := 0
		while cut < hs.size() - 1 and hs[cut] < split:
			cut += 1
		_tube(ctx["trunk"], spine.slice(0, cut + 1), rads.slice(0, cut + 1), n_sides, colour, out, shape)
		for s: float in [-1.0, 1.0]:
			var lead := PackedVector3Array()
			var lr := PackedFloat32Array()
			for k in range(cut, spine.size()):
				var t := (hs[k] - split) / maxf(fork - split, 0.1)
				lead.append(spine[k] + side * s * (r0 * 0.38 + t * 1.1))
				lr.append(rads[k] * 0.62)
			_tube(ctx["trunk"], lead, lr, maxi(n_sides - 2, 4), colour, out)
			_limbs(ctx, lead, lr, maxi(lead.size() - 1, 1), 1)
	else:
		_tube(ctx["trunk"], spine, rads, n_sides, colour, out, shape)
		_limbs(ctx, spine, rads, fork_i, int(p["limbs"]))
	if near:
		for l: Array in lobes:
			_root(ctx, foot, float(l[0]), r0 * (0.75 + 0.15 * float(l[1])))
	if (ctx["face"] as Dictionary).is_empty() and spine.size() > 5:
		var fi := 4
		var up := (spine[fi + 1] - spine[fi - 1]).normalized()
		var fo := (out - up * out.dot(up)).normalized()
		ctx["face"] = {"o": spine[fi], "out": fo, "up": up, "r": rads[fi] * float(shape.call(0.0, spine[fi].y))}
	return spine


## Limbs from the spine below the fork, sweeping out and drooping; leaf clumps on them.
static func _limbs(ctx: Dictionary, spine: PackedVector3Array, rads: PackedFloat32Array, fork_i: int, count: int) -> void:
	var p: Dictionary = ctx["p"]
	var rng: RandomNumberGenerator = ctx["rng"]
	var below: Vector2i = p["below"]
	var length: Vector2 = p["len"]
	var az := rng.randf_range(-0.5, 0.5)
	for k in count:
		var dx := cos(az)
		var dz := -sin(az)
		var si := clampi(fork_i - rng.randi_range(below.x, below.y), 1, spine.size() - 1)
		_limb(ctx, spine[si], Vector3(dx * 0.5, float(p["rise"]), dz * 0.5), Vector3(dx * 0.9, float(p["drop"]), dz * 0.9),
			rng.randf_range(length.x, length.y), rads[si] * float(p["lrad"]))
		az += TAU / count + rng.randf_range(-0.5, 0.5)
	# The leader's tip carries a clump too.
	if String(p["leaf"]) != "" and not bool(p.get("broken", false)):
		var size: Vector2 = p["leaf_size"]
		var clumps: Array = ctx["clumps"]
		clumps.append([spine[spine.size() - 1], rng.randf_range(size.x, size.y)])


static func _limb(ctx: Dictionary, start: Vector3, d0: Vector3, d1: Vector3, length: float, radius: float) -> void:
	var p: Dictionary = ctx["p"]
	var rng: RandomNumberGenerator = ctx["rng"]
	var near: bool = ctx["near"]
	var steps := 3 if near else 2
	var a := d0.normalized()
	var b := d1.normalized()
	var pts := PackedVector3Array([start])
	var rads := PackedFloat32Array([radius])
	var pos := start
	var dir := a
	var wig := Vector3.ZERO
	for k in steps:
		var t := float(k + 1) / steps
		wig = (wig + Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.6, 0.6), rng.randf_range(-1.0, 1.0)) * 0.22) * 0.65
		dir = (a.slerp(b, t) + wig).normalized()
		pos += dir * length / steps
		pts.append(pos)
		rads.append(radius * lerpf(1.0, 0.18, pow(t, 0.9)))
	pts.append(pos + dir * 0.6)
	rads.append(0.015)
	var colour := _bark_colour(p, 0.0)
	_tube(ctx["trunk"], pts, rads, 4 if radius > 0.2 else 3, colour)
	var hangs: PackedVector3Array = ctx["hangs"]
	var leafy := String(p["leaf"]) != ""
	var size: Vector2 = p.get("leaf_size", Vector2.ONE)
	var clumps: Array = ctx["clumps"]
	for k in range(1, pts.size()):
		var t := float(k) / steps
		if t > 0.25 and t < 0.95 and pts[k].y > 3.2:
			hangs.append(pts[k] - Vector3(0.0, rads[mini(k, rads.size() - 1)], 0.0))
		if leafy and t >= 0.6 and pts[k].y > float(p["leaf_min"]):
			clumps.append([pts[k] + Vector3(0.0, 0.4, 0.0), rng.randf_range(size.x, size.y)])
	ctx["hangs"] = hangs
	# One side branch (near copy only; the mid copy keeps the same rng stream short).
	var kb := clampi(int(steps * 0.5), 1, steps - 1)
	var ldir := (pts[kb + 1] - pts[kb]).normalized()
	var perp := ldir.cross(Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.3, 1.0), rng.randf_range(-1.0, 1.0))).normalized()
	var sd := (ldir + perp * rng.randf_range(0.7, 1.2) + Vector3.UP * 0.35).normalized()
	var sl := rng.randf_range(1.8, 3.2)
	var tip := pts[kb] + sd * sl + Vector3(0.0, -0.4, 0.0)
	if near:
		var mid := pts[kb] + sd * sl * 0.5
		_tube(ctx["trunk"], PackedVector3Array([pts[kb], mid, tip]), PackedFloat32Array([rads[kb] * 0.5, rads[kb] * 0.28, 0.01]), 3, colour)
	if leafy and tip.y > float(p["leaf_min"]) - 0.5:
		clumps.append([tip, rng.randf_range(size.x, size.y) * 0.85])


## A buttress root running out from the foot and down into the ground (near only).
static func _root(ctx: Dictionary, foot: Vector3, ang: float, r0: float) -> void:
	var rng: RandomNumberGenerator = ctx["rng"]
	var dir := Vector3(cos(ang), 0.0, -sin(ang))
	var side := Vector3(-dir.z, 0.0, dir.x)
	var reach := r0 * rng.randf_range(3.6, 5.2)
	var w := rng.randf_range(-0.6, 0.6) * r0
	var pts := PackedVector3Array([
		foot + dir * r0 * 0.6 + Vector3(0.0, 0.9, 0.0),
		foot + dir * r0 * 1.7 + Vector3(0.0, 0.3, 0.0),
		foot + dir * reach * 0.7 + side * w * 0.6 + Vector3(0.0, 0.02, 0.0),
		foot + dir * reach + side * w + Vector3(0.0, -0.3, 0.0),
		foot + dir * reach * 1.15 + side * w * 1.3 + Vector3(0.0, -0.7, 0.0),
	])
	var rads := PackedFloat32Array([r0 * 0.5, r0 * 0.34, r0 * 0.2, r0 * 0.1, r0 * 0.04])
	var p: Dictionary = ctx["p"]
	var moss := MOSS.lerp(_bark_base(p), 0.35)
	_tube(ctx["trunk"], pts, rads, 4, func(_a: float, h: float, _ny: float) -> Color: return _foot_dark(moss, h, 1.0))


## Leaf clump: crossed upright quads (+ one tilted flat quad on the near copy), normals
## pointing out of the clump and down (seen from below the canopy is its dark side).
static func _clump(acc: Dictionary, c: Vector3, s: float, tile: String, rng: RandomNumberGenerator, near: bool) -> void:
	var r := ForestAtlas.uv_rect(tile)
	var corners := [Vector2(-0.5, 0.5), Vector2(0.5, 0.5), Vector2(0.5, -0.5), Vector2(-0.5, -0.5)]
	var uvs := [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0)]
	var yaw0 := rng.randf() * TAU
	for q in (3 if near else 2):
		var tilt := PI * 0.5 + rng.randf_range(-0.35, 0.35) if q == 2 else rng.randf_range(-0.3, 0.3)
		var b := Basis(Vector3.UP, yaw0 + q * PI * 0.5) * Basis(Vector3.RIGHT, tilt)
		var centre := c + Vector3(rng.randf_range(-0.2, 0.2), rng.randf_range(-0.15, 0.15), rng.randf_range(-0.2, 0.2)) * s
		var v: PackedVector3Array = acc["v"]
		var base := v.size()
		var flip := rng.randf() < 0.5
		for k in 4:
			var cv: Vector2 = corners[k]
			var pos := centre + b * Vector3(cv.x * s, cv.y * s, 0.0)
			var t: Vector2 = uvs[k]
			if flip:
				t.x = 1.0 - t.x
			_vert(acc, pos, (pos - c - Vector3(0.0, s * 0.3, 0.0)).normalized(), Color.WHITE, r.position + t * r.size)
		var idx: PackedInt32Array = acc["i"]
		# Both sides (the tree shader culls back faces: the trunks are closed).
		idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3, base, base + 2, base + 1, base, base + 3, base + 2])


## Every other clump, grown to cover the dropped one (mid copy).
static func _thin(clumps: Array, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	for k in range(0, clumps.size(), 2):
		var c: Array = clumps[k]
		var pos: Vector3 = c[0]
		if k + 1 < clumps.size():
			pos = pos.lerp(clumps[k + 1][0] as Vector3, 0.5)
		out.append([pos, float(c[1]) * rng.randf_range(1.3, 1.5)])
	return out


# --- Colour ----------------------------------------------------------------------------

static func _bark_base(p: Dictionary) -> Color:
	return p["bark"]


## Vertex colour of bark at (angle, height, normal y): moss creeping up the foot on the
## upper faces, a darker foot (contact shadow), green rot veins (alpha 0: they glow when
## the instance has rot), birch marks, and the black hollow of a split trunk.
static func _bark_colour(p: Dictionary, split: float) -> Callable:
	var bark := _bark_base(p)
	var moss_h: float = p["moss_h"]
	var veins := bool(p.get("veins", false))
	var birch := p.has("stems")
	return func(a: float, h: float, ny: float) -> Color:
		var c := bark
		var m := clampf((moss_h - h) / maxf(moss_h, 0.1), 0.0, 1.0) * (0.45 + 0.45 * sin(a * 2.0 + h * 1.7))
		c = c.lerp(MOSS, clampf(m + maxf(ny, 0.0) * 0.4, 0.0, 1.0) * 0.55)
		if birch and sin(h * 4.1 + a * 2.0) > 0.86:
			c = c.darkened(0.75)
		if split > 0.0 and h > 0.25 and h < split + 0.2 and absf(wrapf(a - PI * 0.5, -PI, PI)) < 0.7:
			c = VOID
			if h < 0.7:
				return Color(VEIN.r * 0.6, VEIN.g * 0.6, VEIN.b * 0.6, 0.0)
		if veins and h < 1.8 and h > -0.3 and sin(a * 2.0 + h * 0.9) > 0.5:
			return Color(VEIN.r, VEIN.g, VEIN.b, 0.0)
		return _foot_dark(c, h, 1.0)


static func _foot_dark(c: Color, h: float, alpha: float) -> Color:
	var f := lerpf(0.45, 1.0, smoothstep(-0.2, 1.8, h))
	return Color(c.r * f, c.g * f, c.b * f, alpha)


# --- Mesh helpers ------------------------------------------------------------------------

## Packed arrays live in `acc` by reference: typed locals append in place (an `as` cast
## would append to a temporary copy).
static func _vert(acc: Dictionary, pos: Vector3, nrm: Vector3, col: Color, uv: Vector2) -> void:
	var v: PackedVector3Array = acc["v"]
	var n: PackedVector3Array = acc["n"]
	var c: PackedColorArray = acc["c"]
	var t: PackedVector2Array = acc["uv"]
	v.append(pos)
	n.append(nrm)
	c.append(col)
	t.append(uv)


## Tube along `pts` with parallel-transported rings, radial normals, a vertex colour
## from `colour.call(angle, height, normal_y)` and the solid UV marker. Angle 0 points
## along `first` (projected), so on an upright trunk angle a is (cos a, 0, -sin a).
static func _tube(acc: Dictionary, pts: PackedVector3Array, rads: PackedFloat32Array, sides: int, colour: Callable,
		first := Vector3.ZERO, shape := Callable()) -> void:
	var n := pts.size()
	if n < 2:
		return
	var v: PackedVector3Array = acc["v"]
	var base := v.size()
	var t0 := (pts[1] - pts[0]).normalized()
	var nrm := first
	if nrm == Vector3.ZERO or absf(nrm.normalized().dot(t0)) > 0.95:
		nrm = t0.cross(Vector3.UP if absf(t0.y) < 0.9 else Vector3.RIGHT)
	for k in n:
		var t: Vector3
		if k == 0:
			t = pts[1] - pts[0]
		elif k == n - 1:
			t = pts[k] - pts[k - 1]
		else:
			t = pts[k + 1] - pts[k - 1]
		t = t.normalized()
		nrm = (nrm - t * nrm.dot(t)).normalized()
		var bin := t.cross(nrm)
		for j in sides:
			var a := TAU * j / sides
			var r := rads[k]
			if shape.is_valid():
				r *= float(shape.call(a, pts[k].y))
			var radial := nrm * cos(a) + bin * sin(a)
			_vert(acc, pts[k] + radial * r, radial, colour.call(a, pts[k].y, radial.y), SOLID_UV)
	var idx: PackedInt32Array = acc["i"]
	for k in n - 1:
		for j in sides:
			var p00 := base + k * sides + j
			var p01 := base + k * sides + (j + 1) % sides
			idx.append_array([p00, p00 + sides, p01, p01, p00 + sides, p01 + sides])


static func _append(dst: Dictionary, src: Dictionary) -> void:
	var v: PackedVector3Array = dst["v"]
	var n: PackedVector3Array = dst["n"]
	var c: PackedColorArray = dst["c"]
	var t: PackedVector2Array = dst["uv"]
	var base := v.size()
	v.append_array(src["v"])
	n.append_array(src["n"])
	c.append_array(src["c"])
	t.append_array(src["uv"])
	var idx: PackedInt32Array = dst["i"]
	for i in (src["i"] as PackedInt32Array):
		idx.append(base + i)


static func _commit(mesh: ArrayMesh, acc: Dictionary, mat: Material) -> void:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = acc["v"]
	arrays[Mesh.ARRAY_NORMAL] = acc["n"]
	arrays[Mesh.ARRAY_COLOR] = acc["c"]
	arrays[Mesh.ARRAY_TEX_UV] = acc["uv"]
	arrays[Mesh.ARRAY_INDEX] = acc["i"]
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(mesh.get_surface_count() - 1, mat)


static func _ring_at(spine: PackedVector3Array, h: float) -> Vector3:
	for k in range(1, spine.size()):
		if spine[k].y >= h:
			var t := (h - spine[k - 1].y) / maxf(spine[k].y - spine[k - 1].y, 0.001)
			return spine[k - 1].lerp(spine[k], t)
	return spine[spine.size() - 1]


# --- Impostors -----------------------------------------------------------------------------

## Width (twice the largest sideways reach) and height of a mesh above the ground.
static func _extent(mesh: ArrayMesh) -> Vector2:
	var reach := 0.5
	var top := 1.0
	for s in mesh.get_surface_count():
		var verts: PackedVector3Array = mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
		for v in verts:
			reach = maxf(reach, maxf(absf(v.x), absf(v.z)))
			top = maxf(top, v.y)
	return Vector2(reach * 2.0, top)


## Paints every style's impostor into its 32 x 64 cell of `img`: the near mesh seen from
## the side (orthographic, depth-tested), bark shaded by a soft moon from the upper left,
## leaves sampled from their atlas tile.
static func paint_impostors(img: Image) -> void:
	var src := img.duplicate() as Image
	var light := Vector3(-0.4, 0.8, 0.45).normalized()
	for style in NAMES.size():
		var cell := ForestAtlas.impostor_rect(style)
		var mesh := tree(style, 0)["mesh"] as ArrayMesh
		var ext := impostor_size(style)
		var zbuf := PackedFloat32Array()
		zbuf.resize(cell.size.x * cell.size.y)
		zbuf.fill(-INF)
		for s in mesh.get_surface_count():
			var arr := mesh.surface_get_arrays(s)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var nr: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var col: PackedColorArray = arr[Mesh.ARRAY_COLOR]
			var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			var scr := PackedVector2Array()
			for p in v:
				scr.append(Vector2((p.x / ext.x + 0.5) * cell.size.x, (1.0 - p.y / ext.y) * cell.size.y))
			for f in range(0, idx.size(), 3):
				_raster(img, src, cell, zbuf, [idx[f], idx[f + 1], idx[f + 2]], scr, v, nr, col, uv, light)


static func _raster(img: Image, src: Image, cell: Rect2i, zbuf: PackedFloat32Array, tri: Array, scr: PackedVector2Array,
		v: PackedVector3Array, nr: PackedVector3Array, col: PackedColorArray, uv: PackedVector2Array, light: Vector3) -> void:
	var a := scr[tri[0]]
	var b := scr[tri[1]]
	var c := scr[tri[2]]
	var area := (b - a).cross(c - a)
	if absf(area) < 1e-6:
		return
	var x0 := maxi(int(floor(minf(a.x, minf(b.x, c.x)))), 0)
	var x1 := mini(int(ceil(maxf(a.x, maxf(b.x, c.x)))), cell.size.x - 1)
	var y0 := maxi(int(floor(minf(a.y, minf(b.y, c.y)))), 0)
	var y1 := mini(int(ceil(maxf(a.y, maxf(b.y, c.y)))), cell.size.y - 1)
	var solid := uv[tri[0]].x < -0.5
	var shade := 0.45 + 0.55 * maxf((nr[tri[0]] + nr[tri[1]] + nr[tri[2]]).normalized().dot(light), 0.0)
	for py in range(y0, y1 + 1):
		for px in range(x0, x1 + 1):
			var q := Vector2(px + 0.5, py + 0.5)
			var w0 := (b - q).cross(c - q) / area
			var w1 := (c - q).cross(a - q) / area
			var w2 := 1.0 - w0 - w1
			if w0 < 0.0 or w1 < 0.0 or w2 < 0.0:
				continue
			var z := v[tri[0]].z * w0 + v[tri[1]].z * w1 + v[tri[2]].z * w2
			var zi := py * cell.size.x + px
			if z <= zbuf[zi]:
				continue
			var c3 := col[tri[0]] * w0 + col[tri[1]] * w1 + col[tri[2]] * w2
			var out: Color
			if solid:
				out = Color(c3.r * 0.75 * shade, c3.g * 0.75 * shade, c3.b * 0.75 * shade)
			else:
				var t := uv[tri[0]] * w0 + uv[tri[1]] * w1 + uv[tri[2]] * w2
				var tx := src.get_pixel(clampi(int(t.x * ForestAtlas.SIZE), 0, ForestAtlas.SIZE - 1),
					clampi(int(t.y * ForestAtlas.SIZE), 0, ForestAtlas.SIZE - 1))
				if tx.a < 0.5:
					continue
				out = Color(tx.r * c3.r * shade, tx.g * c3.g * shade, tx.b * c3.b * shade)
			zbuf[zi] = z
			img.set_pixel(cell.position.x + px, cell.position.y + py, Color(out.r, out.g, out.b, 1.0))
