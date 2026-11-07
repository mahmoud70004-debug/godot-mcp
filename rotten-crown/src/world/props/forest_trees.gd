@tool
class_name ForestTrees
extends RefCounted
## Kingdom forest silhouettes for MultiMesh instancing (ForestBuilder): tall straight,
## broad gnarled and bare twisted trees grown with WoodProps' own trunk, root, limb and
## leaf-card generators (same bark, moss and leaf materials), so they belong to the
## Whispering Wood family. Each style has a detailed and a low-poly copy.

enum Style { TALL, BROAD, BARE }
## Per style: trunk radius, fork height, lean, wobble, flute twist, buttress roots
## [count, size], limbs [count, rise of the first direction, droop of the last,
## length range, radius fraction, rings below the fork], leaf clump size range and
## lowest clump height (no leaves: size 0).
const FOREST_STYLES := {
	Style.TALL: {"r0": 0.44, "fork": 8.4, "lean": 0.3, "wob": 0.18, "twist": 0.6, "roots": 3, "root_size": 0.6,
		"limbs": 4, "rise": 0.93, "drop": 0.3, "len": Vector2(3.2, 4.6), "lrad": 0.5, "below": Vector2i(0, 2),
		"leaf": Vector2(2.2, 3.2), "leaf_min": 5.5, "sides": 8},
	Style.BROAD: {"r0": 0.66, "fork": 4.4, "lean": 1.1, "wob": 0.35, "twist": 1.0, "roots": 5, "root_size": 1.2,
		"limbs": 4, "rise": 0.75, "drop": -0.15, "len": Vector2(6.0, 8.0), "lrad": 0.58, "below": Vector2i(0, 2),
		"leaf": Vector2(2.4, 3.4), "leaf_min": 4.0, "sides": 9},
	Style.BARE: {"r0": 0.4, "fork": 5.6, "lean": 0.9, "wob": 0.6, "twist": 1.6, "roots": 3, "root_size": 0.7,
		"limbs": 3, "rise": 0.85, "drop": 0.1, "len": Vector2(4.2, 6.2), "lrad": 0.55, "below": Vector2i(0, 3),
		"leaf": Vector2.ZERO, "leaf_min": 99.0, "sides": 7},
}

static var _cache: Dictionary = {}


## One forest silhouette for MultiMesh instancing (built on first use), grown by the
## same trunk / root / limb generators as WoodProps.tree():
## {trunk: ArrayMesh (bark + moss in one surface, moss and a darker foot as vertex
##  colour, material "forest_bark"), leaves: ArrayMesh or null ("forest_leaves"),
##  radius: trunk radius at the foot, base: Vector2 trunk centre offset at 1.6 m (xz)}.
## `far` is the low-poly copy (fewer sides and rings, no roots): same rng sequence,
## so the limbs and the leaves are exactly where the detailed one has them.
static func tree(style: Style, far: bool) -> Dictionary:
	var key := "forest/%d/%s" % [style, far]
	if not _cache.has(key):
		_cache[key] = _build_forest_tree(style, far)
	return _cache[key]


static func _build_forest_tree(style: Style, far: bool) -> Dictionary:
	var p: Dictionary = FOREST_STYLES[style]
	var rng := RandomNumberGenerator.new()
	rng.seed = 6151 * (style + 1) + 17
	var r0: float = p["r0"]
	var fork: float = p["fork"]
	var lean: float = p["lean"]
	var ctx := {
		"acc": WoodProps._acc(), "shadow": WoodProps._acc(), "rng": rng, "leaves": [], "hangs": PackedVector3Array(),
		"hero": false, "far": false,
		"limb_sides": 3 if far else 5, "sub_sides": 2 if far else 4,
		"leaf": p["leaf"], "leaf_min": p["leaf_min"],
	}
	var lobes: Array = []
	var n_roots: int = p["roots"]
	var a0 := rng.randf() * TAU
	for j in n_roots:
		lobes.append([wrapf(a0 + TAU * j / n_roots + rng.randf_range(-0.3, 0.3), -PI, PI), float(p["root_size"]) * rng.randf_range(0.7, 1.1)])
	var flute_n := float(rng.randi_range(5, 8))
	var twist := float(p["twist"]) * rng.randf_range(0.8, 1.2)
	var shape := func(a: float, h: float) -> float:
		var m := 1.0 + 0.07 * sin(a * flute_n + h * twist * 2.0)
		var hb := maxf(h, 0.0)
		for l: Array in lobes:
			var d := wrapf(a - float(l[0]), -PI, PI)
			m += float(l[1]) * exp(-d * d / 0.09) * exp(-hb / 0.65)
		return m
	var hs := PackedFloat32Array([-0.9, -0.35, 0.0, 0.18, 0.4, 0.68, 1.0, 1.4, 1.9])
	var h := hs[hs.size() - 1]
	while h < fork - 0.01:
		h = minf(h + 0.8, fork)
		hs.append(h)
	var fork_i := hs.size() - 1
	var lead_len := rng.randf_range(2.5, 4.0)
	for k in 3:
		hs.append(fork + lead_len * float(k + 1) / 3.0)
	var ph := rng.randf() * TAU
	var ph2 := rng.randf() * TAU
	var wob: float = p["wob"]
	var spine := PackedVector3Array()
	var rads := PackedFloat32Array()
	var moss := PackedFloat32Array()
	for hh in hs:
		var u := hh / fork
		var uc := clampf(u, 0.0, 1.0)
		var x := lean * pow(uc, 1.5) + wob * (sin(u * 2.4 + ph) - sin(ph))
		if u > 1.0:
			x += lean * 0.7 * (u - 1.0)
		spine.append(Vector3(x, hh, wob * 0.8 * (sin(u * 3.1 + ph2) - sin(ph2))))
		rads.append(r0 * (lerpf(1.0, 0.66, uc) if u <= 1.0 else 0.66 * lerpf(1.0, 0.05, (hh - fork) / lead_len)))
		moss.append(1.0 if hh < 1.7 else 0.0)
	if far:
		# Every other ring above the foot (the limbs still start on the full spine).
		var fs := PackedVector3Array()
		var fr := PackedFloat32Array()
		var fm := PackedFloat32Array()
		for k in spine.size():
			if k in [0, 2, 5, 8] or (k > 8 and (k % 2 == 0 or k == spine.size() - 1)):
				fs.append(spine[k])
				fr.append(rads[k])
				fm.append(moss[k])
		WoodProps._tube(ctx["acc"], fs, fr, 5, fm, Vector3.RIGHT, shape)
	else:
		WoodProps._tube(ctx["acc"], spine, rads, int(p["sides"]), moss, Vector3.RIGHT, shape)
	var trunk_acc: Dictionary = ctx["acc"]
	if far:
		ctx["acc"] = WoodProps._acc()
	for l: Array in lobes:
		WoodProps._root(ctx, float(l[0]), r0 * (0.75 + 0.15 * float(l[1])))
	ctx["acc"] = trunk_acc
	var az := rng.randf_range(-0.5, 0.5)
	var n_limbs: int = p["limbs"]
	var below: Vector2i = p["below"]
	var length: Vector2 = p["len"]
	for k in n_limbs:
		var dx := cos(az)
		var dz := -sin(az)
		var si := clampi(fork_i - rng.randi_range(below.x, below.y), 3, fork_i)
		WoodProps._limb(ctx, spine[si], Vector3(dx * 0.5, float(p["rise"]), dz * 0.5), Vector3(dx * 0.9, float(p["drop"]), dz * 0.9),
			rng.randf_range(length.x, length.y), rads[si] * float(p["lrad"]))
		az += TAU / n_limbs + rng.randf_range(-0.5, 0.5)
	var leaves: Array = ctx["leaves"]
	# A fuller crown than the path trees: a second, smaller clump beside each one.
	for lf: Array in leaves.duplicate():
		var off := Vector3(rng.randf_range(-1.4, 1.4), rng.randf_range(-0.6, 0.4), rng.randf_range(-1.4, 1.4))
		leaves.append([(lf[0] as Vector3) + off, float(lf[1]) * rng.randf_range(0.75, 0.95)])
	var leaf_mesh: ArrayMesh = WoodProps._leaf_mesh(leaves, rng) if float((p["leaf"] as Vector2).x) > 0.0 and not leaves.is_empty() else null
	var base := spine[7]
	return {
		"trunk": _colored_trunk(WoodProps._finish(ctx["acc"], 0.45)), "leaves": leaf_mesh,
		"radius": r0 * 0.95, "base": Vector2(base.x, base.z),
	}


## [bark, moss] meshes -> one surface; vertex colour turns the moss-tinted
## forest_bark albedo back into bark on bark faces, and darkens every face
## towards the ground (fake contact shadow; trees cast no real-time shadow).
static func _colored_trunk(parts: Array) -> ArrayMesh:
	var bark_lin := WoodProps.FOREST_BARK.srgb_to_linear()
	var moss_lin := WoodProps.FOREST_MOSS.srgb_to_linear()
	var bark_col := Color(bark_lin.r / moss_lin.r, bark_lin.g / moss_lin.g, bark_lin.b / moss_lin.b)
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var idx := PackedInt32Array()
	for k in parts.size():
		var mesh := parts[k] as ArrayMesh
		if mesh == null:
			continue
		var arrays := mesh.surface_get_arrays(0)
		var base := v.size()
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for vtx in verts:
			var foot := lerpf(0.4, 1.0, smoothstep(-0.2, 1.8, vtx.y))
			var tint := bark_col if k == 0 else Color.WHITE
			c.append(Color(tint.r * foot, tint.g * foot, tint.b * foot))
		v.append_array(verts)
		n.append_array(arrays[Mesh.ARRAY_NORMAL])
		for i in (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array):
			idx.append(base + i)
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = v
	out[Mesh.ARRAY_NORMAL] = n
	out[Mesh.ARRAY_COLOR] = c
	out[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	return mesh
