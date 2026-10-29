@tool
class_name WoodProps
extends RefCounted
## Whispering Wood set pieces (reference 3): ancient gnarled trees built ONCE per
## variant (bark, moss and leaf-card meshes shared by every instance, then merged
## by MeshMerger), bark faces, a tree grown around a skeleton, ribbons, a hanged
## lantern, glowing mushrooms, drifting motes and mist cards.
##
## Tree frame: origin on the ground at the trunk centre, +X is the side the tree
## leans and reaches towards (the path); the trunk is buried down to y = -0.9 so
## it sits on slopes. Solid meshes use StandardMaterial3D (mergeable); mist and
## motes carry MeshMerger.SKIP_META. Physics shapes are never placed under
## scaled nodes: place_tree() adds its collider next to the tree, unscaled.

enum Kind { HERO, MID, FAR }

const MIST_SHADER := preload("res://assets/shaders/wood_mist.gdshader")
const MOTE_SHADER := preload("res://assets/shaders/wood_motes.gdshader")
const VARIANTS := {Kind.HERO: 5, Kind.MID: 3, Kind.FAR: 3}
const LEAF_TEX_SIZE := 128

static var _mats: Dictionary = {}
static var _trees: Dictionary = {}


# --- Palette (region specific; the shared RetroMaterials stay untouched) -------

static func material(id: String) -> Material:
	if _mats.has(id):
		return _mats[id]
	var mat: StandardMaterial3D
	match id:
		"bark":
			mat = _scan("bark_brown_02", 2.2, Color(0.22, 0.23, 0.29))
			mat.rim_enabled = true
			mat.rim = 0.45
			mat.rim_tint = 0.25
		"moss":
			mat = _scan("aerial_grass_rock", 2.5, Color(0.24, 0.44, 0.47))
		"bark_pale":
			# Faintly self-lit, like fungus light: the face reads in the dark
			# by its black hollows, without any sudden reveal.
			mat = _scan("bark_brown_02", 0.9, Color(0.5, 0.53, 0.6))
			mat.emission_enabled = true
			mat.emission = Color(0.2, 0.25, 0.34)
			mat.emission_texture = mat.albedo_texture
			mat.emission_energy_multiplier = 0.4
		"leaves":
			mat = _leaf_material(Color(0.22, 0.38, 0.48), false)
		"far_bark":
			mat = _flat(Color(0.03, 0.04, 0.065))
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		"far_leaves":
			mat = _leaf_material(Color(0.25, 0.32, 0.42), true)
		"shadow":
			mat = _flat(Color(0.0, 0.0, 0.0))
		"bone":
			mat = _flat(Color(0.46, 0.44, 0.37))
		"void":
			mat = _flat(Color(0.006, 0.006, 0.01))
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		"rag_pale":
			mat = _flat(Color(0.5, 0.5, 0.48))
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		"rag_red":
			mat = _flat(Color(0.32, 0.05, 0.05))
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		"glow_cap":
			mat = _flat(Color(0.35, 0.62, 0.7))
			mat.emission_enabled = true
			mat.emission = Color(0.3, 0.75, 0.85)
			mat.emission_energy_multiplier = 1.1
		"lantern_glow":
			mat = _flat(Color(1.0, 0.75, 0.4))
			mat.emission_enabled = true
			mat.emission = Color(1.0, 0.68, 0.32)
			mat.emission_energy_multiplier = 4.0
		"iron":
			mat = _flat(Color(0.07, 0.07, 0.08))
			mat.metallic = 0.6
		_:
			push_error("WoodProps: unknown material %s" % id)
			mat = _flat(Color.MAGENTA)
	_mats[id] = mat
	return mat


static func _scan(tex: String, tile_metres: float, tint: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load("res://assets/textures/world/%s.png" % tex) as Texture2D
	mat.albedo_color = tint
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3.ONE / tile_metres
	mat.roughness = 1.0
	mat.set_meta("swatch", tint)
	return mat


static func _flat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.95
	mat.set_meta("swatch", color)
	return mat


static func _leaf_material(tint: Color, unshaded: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _leaf_texture()
	mat.albedo_color = tint
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.45
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.roughness = 1.0
	if unshaded:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat


## A ragged clump of small leaves (cut-out alpha), lighter towards the top where
## the moon catches it. Generated once; the bake stores it in the world scene.
static func _leaf_texture() -> Texture2D:
	if _mats.has("_leaf_tex"):
		return _mats["_leaf_tex"]
	var size := LEAF_TEX_SIZE
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 0.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 314
	var shades := [Color(0.04, 0.075, 0.07), Color(0.06, 0.11, 0.1), Color(0.09, 0.16, 0.13), Color(0.13, 0.22, 0.18)]
	var centre := Vector2(size, size) * 0.5
	for k in 9:
		var a := rng.randf() * TAU
		var reach := rng.randf_range(0.2, 0.42) * size
		for s in int(reach):
			var p := centre + Vector2(cos(a), sin(a)) * s + Vector2(sin(s * 0.3), cos(s * 0.23)) * 1.5
			img.set_pixel(clampi(int(p.x), 0, size - 1), clampi(int(p.y), 0, size - 1), Color(0.05, 0.045, 0.04, 1.0))
	for i in 1700:
		var a := rng.randf() * TAU
		var rad := pow(rng.randf(), 0.62) * size * 0.46 * (0.8 + 0.2 * sin(a * 5.0 + 1.3))
		var c := centre + Vector2(cos(a), sin(a)) * rad
		var top := 1.0 - c.y / size
		var col: Color = shades[clampi(int(top * 2.4 + rng.randf() * 1.7 - 0.4), 0, 3)]
		var la := a + rng.randf_range(-0.9, 0.9)
		var ll := rng.randf_range(2.4, 4.2)
		var lw := rng.randf_range(1.1, 1.9)
		var dx := Vector2(cos(la), sin(la))
		var dy := Vector2(-dx.y, dx.x)
		for py in range(int(c.y - ll), int(c.y + ll) + 1):
			for px in range(int(c.x - ll), int(c.x + ll) + 1):
				if px < 0 or py < 0 or px >= size or py >= size:
					continue
				var q := Vector2(px + 0.5, py + 0.5) - c
				var lx := q.dot(dx) / ll
				var ly := q.dot(dy) / lw
				if lx * lx + ly * ly <= 1.0:
					var cc := col.darkened(0.3) if ly > 0.35 else col
					img.set_pixel(px, py, Color(cc.r, cc.g, cc.b, 1.0))
	# No mipmaps: averaged alpha in small mips turns far cut-out cards into squares.
	var tex := ImageTexture.create_from_image(img)
	_mats["_leaf_tex"] = tex
	return tex


# --- Trees ---------------------------------------------------------------------

## The shared meshes and anchors of one tree variant (built on first use):
## {bark, moss, leaves: ArrayMesh (moss may be null), radius, height: collider,
##  hangs: PackedVector3Array (limb undersides, tree frame), face: Dictionary}.
static func tree(kind: Kind, variant: int) -> Dictionary:
	var key := "%d/%d" % [kind, variant]
	if not _trees.has(key):
		var rng := RandomNumberGenerator.new()
		rng.seed = 7919 * (variant + 1) + 104729 * kind
		_trees[key] = _build_tree(kind, rng)
	return _trees[key]


## Instance a tree variant on `parent`; returns the (scaled) tree node. The
## collider is a sibling so it is never scaled.
static func place_tree(parent: Node3D, kind: Kind, variant: int, pos: Vector3, yaw: float, scale: float, collide := true) -> Node3D:
	var data := tree(kind, variant)
	var root := Node3D.new()
	root.name = "Tree"
	root.transform = Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale), pos)
	parent.add_child(root)
	# Moon shadows (the most expensive pass): hero trees cast through a low-poly
	# shadow-only proxy plus their leaves; mid and far trees cast none.
	for part: String in ["bark", "moss", "leaves", "shadow"]:
		var mesh := data.get(part) as ArrayMesh
		if mesh == null or (part == "shadow" and kind != Kind.HERO):
			continue
		var mi := MeshInstance3D.new()
		mi.name = part.capitalize()
		mi.mesh = mesh
		mi.material_override = material(("far_" + part) if kind == Kind.FAR else part)
		var casts := kind == Kind.HERO and part == "leaves"
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if casts else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if part == "shadow":
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		root.add_child(mi)
	if collide:
		var body := StaticBody3D.new()
		body.name = "TreeCollider"
		parent.add_child(body)
		var cs := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = float(data["radius"]) * scale
		shape.height = 3.2 * scale
		cs.shape = shape
		var lean := Basis(Vector3.UP, yaw) * Vector3(float(data["lean"]) * 0.12 * scale, 0.0, 0.0)
		cs.position = pos + lean + Vector3(0.0, shape.height * 0.5, 0.0)
		body.add_child(cs)
	return root


static func _build_tree(kind: Kind, rng: RandomNumberGenerator) -> Dictionary:
	var hero := kind == Kind.HERO
	var far := kind == Kind.FAR
	var r0 := rng.randf_range(0.78, 1.02) if hero else (rng.randf_range(0.42, 0.58) if far else rng.randf_range(0.5, 0.72))
	var fork := rng.randf_range(4.8, 6.2) if hero else rng.randf_range(5.2, 7.2)
	var lean := rng.randf_range(1.1, 2.0) if hero else rng.randf_range(0.4, 1.2)
	var ctx := {
		"acc": _acc(), "shadow": _acc(), "rng": rng, "leaves": [], "hangs": PackedVector3Array(),
		"hero": hero, "far": far,
		"limb_sides": 8 if hero else (4 if far else 5),
		"sub_sides": 5 if hero else (3 if far else 5),
		"leaf": Vector2(1.7, 2.7) if hero else (Vector2(4.0, 5.5) if far else Vector2(2.4, 3.4)),
		"leaf_min": 6.0 if hero else 4.0,
	}
	# Buttress lobes (never on the path side, so roots stay off the path and a
	# bark face has a clean surface there).
	var lobes: Array = []
	var n_roots := 0 if far else (rng.randi_range(5, 6) if hero else 4)
	var a0 := rng.randf() * TAU
	for j in n_roots:
		var ang := wrapf(a0 + TAU * j / n_roots + rng.randf_range(-0.3, 0.3), -PI, PI)
		if absf(ang) < 0.5:
			ang = 0.5 * signf(ang + 0.001)
		lobes.append([ang, rng.randf_range(1.1, 2.0) if hero else rng.randf_range(0.6, 1.1)])
	var flute := 0.0 if far else 0.07
	var flute_n := float(rng.randi_range(5, 8))
	var twist := rng.randf_range(0.5, 1.2)
	var burls: Array = []
	if hero:
		for b in rng.randi_range(2, 3):
			burls.append([rng.randf_range(0.8, TAU - 0.8), rng.randf_range(1.0, 3.4), rng.randf_range(0.16, 0.3)])
	var shape := func(a: float, h: float) -> float:
		var m := 1.0 + flute * sin(a * flute_n + h * twist * 2.0)
		var hb := maxf(h, 0.0)
		for l: Array in lobes:
			var d := wrapf(a - float(l[0]), -PI, PI)
			m += float(l[1]) * exp(-d * d / 0.09) * exp(-hb / 0.65)
		for b: Array in burls:
			var d := wrapf(a - float(b[0]), -PI, PI)
			var dh := h - float(b[1])
			m += float(b[2]) * exp(-d * d / 0.12 - dh * dh / 0.1)
		return m
	# Trunk spine: serpentine, leaning to +X, continuing as the tapering leader.
	var hs := PackedFloat32Array([-0.9, -0.35, 0.0, 0.18, 0.4, 0.68, 1.0, 1.4, 1.9]) if not far else PackedFloat32Array([-0.6, 0.0, 1.6])
	var h := hs[hs.size() - 1]
	var ring_step := 1.6 if far else 0.65
	while h < fork - 0.01:
		h = minf(h + ring_step, fork)
		hs.append(h)
	var fork_i := hs.size() - 1
	var lead_len := rng.randf_range(3.0, 4.5)
	var lead_n := 2 if far else 4
	for k in lead_n:
		hs.append(fork + lead_len * float(k + 1) / lead_n)
	var ph := rng.randf() * TAU
	var ph2 := rng.randf() * TAU
	var wob_a := rng.randf_range(0.2, 0.45)
	var wob_b := rng.randf_range(0.2, 0.5)
	var spine := PackedVector3Array()
	var rads := PackedFloat32Array()
	var moss := PackedFloat32Array()
	for hh in hs:
		var u := hh / fork
		var uc := clampf(u, 0.0, 1.0)
		var x := lean * pow(uc, 1.5) + wob_a * (sin(u * 2.4 + ph) - sin(ph))
		if u > 1.0:
			x += lean * 0.7 * (u - 1.0)
		spine.append(Vector3(x, hh, wob_b * (sin(u * 3.1 + ph2) - sin(ph2))))
		var r := r0 * lerpf(1.0, 0.66, uc)
		if u > 1.0:
			r = r0 * 0.66 * lerpf(1.0, 0.05, (hh - fork) / lead_len)
		rads.append(r)
		moss.append(1.0 if hh < 1.7 else 0.0)
	_tube(ctx["acc"], spine, rads, 14 if hero else (6 if far else 8), moss, Vector3.RIGHT, shape)
	if hero:
		_tube(ctx["shadow"], spine, rads, 6, moss)
	# Roots: continue each buttress outwards and down into the ground.
	for l: Array in lobes:
		_root(ctx, float(l[0]), r0 * (0.75 + 0.15 * float(l[1])))
	# Limbs: d0 -> d1 direction sweep, length, radius fraction of the trunk.
	var s1 := 1.0 if rng.randf() < 0.5 else -1.0
	var limbs: Array = []
	if hero:
		limbs = [
			[Vector3(0.35, 0.93, 0.3 * s1), Vector3(0.95, -0.15, 0.2 * s1), rng.randf_range(10.0, 12.0), 0.6, 0],
			[Vector3(0.3, 0.93, -0.4 * s1), Vector3(0.8, -0.2, -0.5 * s1), rng.randf_range(9.0, 11.0), 0.55, 1],
			[Vector3(0.05, 0.9, 0.55 * s1), Vector3(0.25, -0.15, 0.95 * s1), rng.randf_range(7.0, 9.0), 0.5, 1],
			[Vector3(-0.4, 0.9, -0.3 * s1), Vector3(-0.9, 0.0, -0.35 * s1), rng.randf_range(6.0, 8.0), 0.48, 2],
			[Vector3(0.2, 0.7, -0.7 * s1), Vector3(0.35, 0.1, -0.95 * s1), rng.randf_range(5.0, 7.0), 0.4, 4],
		]
	else:
		var n_limbs := 2 if far else 3
		var az := rng.randf_range(-0.5, 0.5)
		for k in n_limbs:
			var dx := cos(az)
			var dz := -sin(az)
			limbs.append([Vector3(dx * 0.5, 0.85, dz * 0.5), Vector3(dx * 0.9, -0.2, dz * 0.9), rng.randf_range(5.0, 7.5), 0.55, rng.randi_range(0, 2)])
			az += TAU / n_limbs + rng.randf_range(-0.5, 0.5)
	for l: Array in limbs:
		var si := clampi(fork_i - int(l[4]), 3 if not far else 1, fork_i)
		_limb(ctx, spine[si], l[0] as Vector3, l[1] as Vector3, float(l[2]), rads[si] * float(l[3]))
	var acc: Dictionary = ctx["acc"]
	var parts := _finish(acc, 2.0 if far else 0.45)
	# Bark-face anchor: the trunk ring near 1.9 m on the +X (path) side.
	var fi := mini(8, spine.size() - 2) if not far else 1
	var up := (spine[fi + 1] - spine[fi - 1]).normalized()
	var out := (Vector3.RIGHT - up * Vector3.RIGHT.dot(up)).normalized()
	var face := {"o": spine[fi], "out": out, "up": up, "r": rads[fi] * float(shape.call(0.0, spine[fi].y))}
	return {
		"bark": parts[0], "moss": parts[1], "leaves": _leaf_mesh(ctx["leaves"], rng),
		"shadow": _finish(ctx["shadow"], 2.0)[0] if hero else null,
		"radius": r0 * 0.95, "lean": lean, "hangs": ctx["hangs"], "face": face,
	}


static func _root(ctx: Dictionary, ang: float, r0: float) -> void:
	var rng: RandomNumberGenerator = ctx["rng"]
	var dir := Vector3(cos(ang), 0.0, -sin(ang))
	var side := Vector3(-dir.z, 0.0, dir.x)
	var reach := r0 * rng.randf_range(3.8, 5.4)
	var w1 := rng.randf_range(-0.5, 0.5) * r0
	var w2 := rng.randf_range(-0.8, 0.8) * r0
	var pts := PackedVector3Array([
		dir * r0 * 0.6 + Vector3(0.0, 1.1, 0.0),
		dir * r0 * 1.6 + Vector3(0.0, 0.42, 0.0),
		dir * r0 * 2.5 + side * w1 * 0.5 + Vector3(0.0, 0.1, 0.0),
		dir * reach * 0.75 + side * w1 + Vector3(0.0, -0.02, 0.0),
		dir * reach + side * w2 + Vector3(0.0, -0.28, 0.0),
		dir * reach * 1.15 + side * w2 * 1.3 + Vector3(0.0, -0.7, 0.0),
	])
	var rads := PackedFloat32Array([r0 * 0.5, r0 * 0.38, r0 * 0.27, r0 * 0.17, r0 * 0.1, r0 * 0.04])
	var moss := PackedFloat32Array([1.0, 1.0, 1.0, 1.0, 1.0, 1.0])
	_tube(ctx["acc"], pts, rads, 6, moss)


static func _limb(ctx: Dictionary, start: Vector3, d0: Vector3, d1: Vector3, length: float, radius: float) -> void:
	var rng: RandomNumberGenerator = ctx["rng"]
	var hero: bool = ctx["hero"]
	var far: bool = ctx["far"]
	var steps := 8 if hero else (4 if far else 7)
	var a := d0.normalized()
	var b := d1.normalized()
	var pts := PackedVector3Array([start])
	var rads := PackedFloat32Array([radius])
	var moss := PackedFloat32Array([1.0])
	var p := start
	var dir := a
	var wig := Vector3.ZERO
	for k in steps:
		var t := float(k + 1) / steps
		wig = (wig + Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.6, 0.6), rng.randf_range(-1.0, 1.0)) * 0.22) * 0.65
		dir = (a.slerp(b, t) + wig).normalized()
		p += dir * length / steps
		pts.append(p)
		rads.append(radius * lerpf(1.0, 0.16, pow(t, 0.9)))
		moss.append(1.0 if t < 0.3 else 0.0)
	pts.append(p + dir * 0.7)
	rads.append(0.012)
	moss.append(0.0)
	_tube(ctx["acc"], pts, rads, int(ctx["limb_sides"]), moss)
	if hero:
		_tube(ctx["shadow"], pts, rads, 4, moss)
	var leaves: Array = ctx["leaves"]
	var leaf: Vector2 = ctx["leaf"]
	var hangs: PackedVector3Array = ctx["hangs"]
	for k in range(1, steps + 1):
		var t := float(k) / steps
		if hero and t > 0.3 and t < 0.9 and pts[k].y > 4.0:
			hangs.append(pts[k] - Vector3(0.0, rads[k], 0.0))
		if t > 0.5 and k % 2 == 0 and pts[k].y > float(ctx["leaf_min"]):
			leaves.append([pts[k] + Vector3(0.0, 0.5, 0.0), rng.randf_range(leaf.x, leaf.y)])
	ctx["hangs"] = hangs
	if p.y > float(ctx["leaf_min"]):
		leaves.append([p, rng.randf_range(leaf.x, leaf.y)])
	var subs := 2 if hero else 1 if far else 2
	for k in subs:
		var kb := clampi(int(steps * (0.35 + 0.5 * float(k) / maxf(subs - 1, 1))), 1, steps - 1)
		var ldir := (pts[kb + 1] - pts[kb]).normalized()
		var perp := ldir.cross(Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.3, 1.0), rng.randf_range(-1.0, 1.0))).normalized()
		var sd0 := (ldir + perp * rng.randf_range(0.7, 1.2) + Vector3.UP * 0.35).normalized()
		var sd1 := (sd0 + Vector3(0.0, -0.9, 0.0)).normalized()
		_branch(ctx, pts[kb], sd0, sd1, rng.randf_range(2.6, 4.4) * (1.3 if far else 1.0), rads[kb] * 0.55)


static func _branch(ctx: Dictionary, start: Vector3, d0: Vector3, d1: Vector3, length: float, radius: float) -> void:
	var rng: RandomNumberGenerator = ctx["rng"]
	var hero: bool = ctx["hero"]
	var steps := 5 if not ctx["far"] else 2
	var pts := PackedVector3Array([start])
	var rads := PackedFloat32Array([radius])
	var moss := PackedFloat32Array([0.0])
	var p := start
	for k in steps:
		var t := float(k + 1) / steps
		p += (d0.slerp(d1, t) + Vector3(rng.randf_range(-0.2, 0.2), rng.randf_range(-0.1, 0.1), rng.randf_range(-0.2, 0.2))).normalized() * length / steps
		pts.append(p)
		rads.append(lerpf(radius, 0.01, t))
		moss.append(0.0)
	_tube(ctx["acc"], pts, rads, int(ctx["sub_sides"]), moss)
	var leaves: Array = ctx["leaves"]
	var leaf: Vector2 = ctx["leaf"]
	if p.y > float(ctx["leaf_min"]) - 0.5:
		leaves.append([p, rng.randf_range(leaf.x, leaf.y)])
	if not hero:
		return
	# One twig near the tip (kept cheap: three rings of four sides).
	var q := pts[steps - 1]
	var td := (d0 + Vector3(rng.randf_range(-0.9, 0.9), rng.randf_range(-0.6, 0.4), rng.randf_range(-0.9, 0.9))).normalized()
	var tip := q + td * rng.randf_range(1.0, 1.9)
	var mid := (q + tip) * 0.5 + Vector3(0.0, -0.15, 0.0)
	_tube(ctx["acc"], PackedVector3Array([q, mid, tip]), PackedFloat32Array([rads[steps - 1] * 0.6, rads[steps - 1] * 0.3, 0.008]), 4, PackedFloat32Array([0.0, 0.0, 0.0]))
	if tip.y > float(ctx["leaf_min"]) - 0.5:
		leaves.append([tip, rng.randf_range(leaf.x, leaf.y) * 0.85])


## Leaf cards: three crossed quads per clump (one lying flat, two upright) with
## spherical normals so a clump shades like a volume (dark underneath).
static func _leaf_mesh(leaves: Array, rng: RandomNumberGenerator) -> ArrayMesh:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()
	var corners := [Vector2(-0.5, 0.5), Vector2(0.5, 0.5), Vector2(0.5, -0.5), Vector2(-0.5, -0.5)]
	var uvs := [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0)]
	for lf: Array in leaves:
		var c: Vector3 = lf[0]
		var s: float = lf[1]
		for q in 3:
			var tilt := PI * 0.5 + rng.randf_range(-0.35, 0.35) if q == 0 else rng.randf_range(-0.5, 0.5)
			var b := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, tilt)
			var centre := c + Vector3(rng.randf_range(-0.3, 0.3), rng.randf_range(-0.2, 0.2), rng.randf_range(-0.3, 0.3)) * s
			var base := v.size()
			var flip := rng.randf() < 0.5
			for k in 4:
				var cv: Vector2 = corners[k]
				var p := centre + b * Vector3(cv.x * s, cv.y * s, 0.0)
				v.append(p)
				# Biased down: seen from the path the canopy is its unlit underside.
				n.append((p - c - Vector3(0.0, s * 0.25, 0.0)).normalized())
				var t: Vector2 = uvs[k]
				uv.append(Vector2(1.0 - t.x, t.y) if flip else t)
			idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	return _mesh(v, n, idx, uv)


## Loose canopy roof: leaf clumps [centre: Vector3, size: float] as one mesh
## node (leaf material) under `parent`, to close the sky over the path.
static func canopy(parent: Node3D, clumps: Array, rng: RandomNumberGenerator, far := false) -> MeshInstance3D:
	var mi := _mesh_node(parent, _leaf_mesh(clumps, rng), "far_leaves" if far else "leaves", "Canopy")
	if far:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


# --- Mesh helpers --------------------------------------------------------------

static func _acc() -> Dictionary:
	return {"v": PackedVector3Array(), "w": PackedFloat32Array(), "i": PackedInt32Array()}


## Appends a tube along `pts` (radius per point, optional shape(angle, y) radius
## multiplier) with parallel-transported rings. Angle 0 points along `first`
## (projected), so for an upright trunk angle a points to (cos a, 0, -sin a).
static func _tube(acc: Dictionary, pts: PackedVector3Array, rads: PackedFloat32Array, sides: int, moss: PackedFloat32Array, first := Vector3.ZERO, shape := Callable()) -> void:
	# Take the packed arrays out first (copy-on-write would copy them per append).
	var v: PackedVector3Array = acc["v"]
	var w: PackedFloat32Array = acc["w"]
	var idx: PackedInt32Array = acc["i"]
	acc["v"] = null
	acc["w"] = null
	acc["i"] = null
	var n := pts.size()
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
			v.append(pts[k] + (nrm * cos(a) + bin * sin(a)) * r)
			w.append(moss[k])
	for k in n - 1:
		for j in sides:
			var p00 := base + k * sides + j
			var p01 := base + k * sides + (j + 1) % sides
			idx.append_array([p00, p00 + sides, p01, p01, p00 + sides, p01 + sides])
	acc["v"] = v
	acc["w"] = w
	acc["i"] = idx


static func _normals(v: PackedVector3Array, idx: PackedInt32Array) -> PackedVector3Array:
	var n := PackedVector3Array()
	n.resize(v.size())
	for f in range(0, idx.size(), 3):
		var a := v[idx[f]]
		var fn := (v[idx[f + 2]] - a).cross(v[idx[f + 1]] - a)
		n[idx[f]] += fn
		n[idx[f + 1]] += fn
		n[idx[f + 2]] += fn
	for i in n.size():
		n[i] = n[i].normalized() if n[i].length_squared() > 0.0 else Vector3.UP
	return n


## Bark mesh + moss mesh: upward-facing triangles of mossy parts (roots,
## buttresses, limb tops near the trunk) go to moss, in blotchy patches.
static func _finish(acc: Dictionary, level: float) -> Array:
	var v: PackedVector3Array = acc["v"]
	var w: PackedFloat32Array = acc["w"]
	var idx: PackedInt32Array = acc["i"]
	var n := _normals(v, idx)
	var bark := PackedInt32Array()
	var moss := PackedInt32Array()
	for f in range(0, idx.size(), 3):
		var i0 := idx[f]
		var i1 := idx[f + 1]
		var i2 := idx[f + 2]
		var c := (v[i0] + v[i1] + v[i2]) / 3.0
		var ny := (n[i0] + n[i1] + n[i2]).normalized().y
		var patch := sin(c.x * 2.3 + c.y * 1.1) * sin(c.z * 1.9 - c.y * 0.7)
		if (w[i0] + w[i1] + w[i2]) > 1.5 and ny > level - patch * 0.35:
			moss.append_array([i0, i1, i2])
		else:
			bark.append_array([i0, i1, i2])
	return [_mesh(v, n, bark), _mesh(v, n, moss) if moss.size() > 0 else null]


## Compact ArrayMesh holding only the vertices `idx` uses.
static func _mesh(v: PackedVector3Array, n: PackedVector3Array, idx: PackedInt32Array, uv := PackedVector2Array()) -> ArrayMesh:
	var remap := PackedInt32Array()
	remap.resize(v.size())
	remap.fill(-1)
	var ov := PackedVector3Array()
	var on := PackedVector3Array()
	var ouv := PackedVector2Array()
	var oi := PackedInt32Array()
	for i in idx:
		if remap[i] < 0:
			remap[i] = ov.size()
			ov.append(v[i])
			on.append(n[i])
			if not uv.is_empty():
				ouv.append(uv[i])
		oi.append(remap[i])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = ov
	arrays[Mesh.ARRAY_NORMAL] = on
	if not ouv.is_empty():
		arrays[Mesh.ARRAY_TEX_UV] = ouv
	arrays[Mesh.ARRAY_INDEX] = oi
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _mesh_node(parent: Node3D, mesh: ArrayMesh, mat_id: String, node_name: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = material(mat_id)
	parent.add_child(mi)
	return mi


## Closed ellipsoid-ish blob along `axis` (radii rx across, half-length ry).
static func _blob(acc: Dictionary, centre: Vector3, axis: Vector3, half: float, radius: float, sides := 8) -> void:
	var pts := PackedVector3Array()
	var rads := PackedFloat32Array()
	var moss := PackedFloat32Array()
	var rings := 6
	for k in rings + 1:
		var t := -1.0 + 2.0 * k / rings
		pts.append(centre + axis * half * t)
		rads.append(radius * sqrt(maxf(1.0 - t * t, 0.0)) + 0.002)
		moss.append(0.0)
	_tube(acc, pts, rads, sides, moss)


# --- Uncanny details -----------------------------------------------------------

## A face pushed out of the bark of a placed tree (child of the tree node, tree
## frame): brow, nose, hollow eyes and a sagging open mouth on the +X side.
static func bark_face(tree_node: Node3D, data: Dictionary, rng: RandomNumberGenerator) -> void:
	var f: Dictionary = data["face"]
	var o: Vector3 = f["o"]
	var out: Vector3 = f["out"]
	var up: Vector3 = f["up"]
	var radius: float = f["r"]
	var side := up.cross(out)
	var width := rng.randf_range(1.0, 1.2)
	var height := width * 1.35
	var sag := rng.randf_range(0.0, 0.25)
	var nx := 13
	var ny := 15
	var v := PackedVector3Array()
	var idx := PackedInt32Array()
	var surf := func(u: float, w: float, lift: float) -> Vector3:
		var rho := radius + lift - 0.05
		var phi := u * width * 0.5 / radius
		return o + out * cos(phi) * rho + side * sin(phi) * rho + up * (w * height * 0.5)
	for iy in ny:
		for ix in nx:
			var u := lerpf(-1.0, 1.0, float(ix) / (nx - 1))
			var w := lerpf(-1.0, 1.0, float(iy) / (ny - 1))
			v.append(surf.call(u, w, _face_relief(u, w, sag)))
	for iy in ny - 1:
		for ix in nx - 1:
			var p00 := iy * nx + ix
			idx.append_array([p00, p00 + nx, p00 + 1, p00 + 1, p00 + nx, p00 + nx + 1])
	var face := Node3D.new()
	face.name = "BarkFace"
	tree_node.add_child(face)
	_mesh_node(face, _mesh(v, _normals(v, idx), idx), "bark_pale", "Relief")
	var holes := [[Vector2(-0.4, 0.15), Vector2(0.21, 0.12)], [Vector2(0.4, 0.15), Vector2(0.21, 0.12)], [Vector2(0.0, -0.47 - sag * 0.3), Vector2(0.27, 0.13 + sag * 0.12)]]
	var hv := PackedVector3Array()
	var hi := PackedInt32Array()
	for hole: Array in holes:
		var c: Vector2 = hole[0]
		var r: Vector2 = hole[1]
		var base := hv.size()
		hv.append(surf.call(c.x, c.y, _face_relief(c.x, c.y, sag) + 0.012))
		for k in 8:
			var a := TAU * k / 8.0
			var q := c + Vector2(cos(a) * r.x, sin(a) * r.y)
			hv.append(surf.call(q.x, q.y, _face_relief(q.x, q.y, sag) + 0.012))
		for k in 8:
			hi.append_array([base, base + 1 + k, base + 1 + (k + 1) % 8])
	_mesh_node(face, _mesh(hv, _normals(hv, hi), hi), "void", "Hollows")


## Height of the face above the bark at (u, w) in -1..1: a swelling that
## grows out of the trunk, so brow, nose and cheeks stand proud while the eye
## hollows and the sagging mouth sit at the bark surface (their dark discs show).
static func _face_relief(u: float, w: float, sag: float) -> float:
	var e := u * u * 0.9 + w * w
	var d := 0.22 * smoothstep(1.05, 0.45, e) - 0.06 * smoothstep(0.95, 1.2, e)
	d += 0.07 * exp(-pow((w - 0.33) / 0.1, 2.0)) * maxf(0.0, 1.0 - u * u * 1.6)
	d += 0.1 * exp(-pow(u / 0.13, 2.0) - pow((w - 0.03) / 0.2, 2.0))
	d -= 0.19 * exp(-pow((absf(u) - 0.4) / 0.2, 2.0) - pow((w - 0.15) / 0.14, 2.0))
	d -= 0.19 * exp(-pow(u / 0.3, 2.0) - pow((w + 0.47 + sag * 0.3) / (0.17 + sag * 0.12), 2.0))
	return d


## A skeleton swallowed by a placed tree (+X side of the trunk): skull, ribs and
## spine half sunk in the bark, one arm pulled up over the head, the other and a
## leg hanging out, all bound by thin strangling roots grown over the bones.
static func skeleton(tree_node: Node3D, data: Dictionary, rng: RandomNumberGenerator) -> void:
	var f: Dictionary = data["face"]
	var o: Vector3 = f["o"]
	var out: Vector3 = f["out"]
	var up: Vector3 = f["up"]
	var radius: float = f["r"]
	var side := up.cross(out)
	# Point on the trunk surface: u metres around, h metres up from the anchor, lift out.
	var surf := func(u: float, h: float, lift: float) -> Vector3:
		var rho := radius + lift
		var phi := u / radius
		return o + out * cos(phi) * rho + side * sin(phi) * rho + up * h
	var bones := _acc()
	var skull_c: Vector3 = surf.call(0.02, 0.5, 0.05)
	_blob(bones, skull_c, up, 0.15, 0.13)
	_blob(bones, skull_c + out * 0.07 - up * 0.15, side, 0.08, 0.045, 6)
	_bone(bones, [surf.call(0.0, -1.0, -0.02), surf.call(0.0, -0.4, 0.03), surf.call(0.0, 0.3, 0.02)], 0.03)
	for k in 6:
		var h := -0.08 - 0.1 * k
		for s: float in [-1.0, 1.0]:
			_bone(bones, [surf.call(0.0, h, 0.03), surf.call(s * 0.14, h - 0.02, 0.1), surf.call(s * 0.26, h - 0.06, 0.06), surf.call(s * 0.33, h - 0.1, -0.03)], 0.022)
	_blob(bones, surf.call(0.0, -1.05, 0.04), side, 0.15, 0.08)
	# Arm pulled up over the head.
	var wrist: Vector3 = surf.call(0.18, 0.98, 0.07)
	_bone(bones, [surf.call(0.2, 0.12, 0.04), surf.call(0.36, 0.5, 0.1), wrist], 0.03)
	for k in 4:
		var fu := 0.1 + 0.06 * k
		_bone(bones, [wrist, surf.call(fu, 1.12, 0.06), surf.call(fu + 0.02, 1.22 + rng.randf_range(0.0, 0.05), 0.03)], 0.012)
	# Arm hanging out of the bark.
	var hand: Vector3 = surf.call(-0.36, -0.68, 0.38)
	_bone(bones, [surf.call(-0.2, 0.12, 0.04), surf.call(-0.36, -0.25, 0.28), hand], 0.03)
	for k in 4:
		_bone(bones, [hand, hand + (-up * 0.12 + side * (0.03 * k - 0.045) + out * 0.03)], 0.011)
	# A leg dangling over the roots.
	_bone(bones, [surf.call(0.12, -1.12, 0.05), surf.call(0.22, -1.42, 0.4), surf.call(0.28, -1.86, 0.5)], 0.035)
	var node := Node3D.new()
	node.name = "Swallowed"
	tree_node.add_child(node)
	var parts := _finish(bones, 2.0)
	_mesh_node(node, parts[0], "bone", "Bones")
	# Eye sockets and nose of the skull.
	var holes := _acc()
	var face_c := skull_c + out * 0.12
	for s: float in [-1.0, 1.0]:
		_blob(holes, face_c + side * s * 0.05 + up * 0.02, out, 0.03, 0.035, 6)
	_blob(holes, face_c - up * 0.05 + out * 0.005, out, 0.02, 0.018, 4)
	_mesh_node(node, _finish(holes, 2.0)[0], "void", "Sockets")
	# Strangling roots over the bones.
	var vines := _acc()
	for k in 5:
		var h0 := -1.0 + 0.36 * k + rng.randf_range(-0.1, 0.1)
		var slope := rng.randf_range(-0.5, 0.5)
		var pts: Array = []
		for j in 7:
			var u := -0.65 + 1.3 * j / 6.0
			var lift := 0.13 * sin(PI * j / 6.0) - 0.04
			pts.append(surf.call(u, h0 + slope * u, lift))
		_bone(vines, pts, 0.05)
	_mesh_node(node, _finish(vines, 2.0)[0], "bark", "Strangler")


static func _bone(acc: Dictionary, pts: Array, radius: float) -> void:
	var p := PackedVector3Array()
	var r := PackedFloat32Array()
	var m := PackedFloat32Array()
	for k in pts.size():
		p.append(pts[k] as Vector3)
		r.append(radius * (1.0 if k < pts.size() - 1 else 0.7))
		m.append(0.0)
	_tube(acc, p, r, 5, m)


## A strip of cloth tied to a branch, hanging from `top` (world/parent space).
static func ribbon(parent: Node3D, top: Vector3, length: float, width: float, red: bool, rng: RandomNumberGenerator) -> void:
	var segs := 4
	var yaw := rng.randf() * TAU
	var sway := Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)) * 0.12
	var twist := rng.randf_range(-1.2, 1.2)
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var idx := PackedInt32Array()
	for k in segs + 1:
		var t := float(k) / segs
		var c := top + Vector3(0.0, -length * t, 0.0) + sway * t * t * length
		var sd := Vector3(cos(yaw + twist * t), 0.0, sin(yaw + twist * t)) * width * (0.5 - 0.15 * t)
		v.append(c - sd)
		v.append(c + sd)
		var nn := sd.cross(Vector3.DOWN).normalized()
		n.append(nn)
		n.append(nn)
		if k < segs:
			var b := k * 2
			idx.append_array([b, b + 2, b + 1, b + 1, b + 2, b + 3])
	var mi := _mesh_node(parent, _mesh(v, n, idx), "rag_red" if red else "rag_pale", "Ribbon")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## A lantern hung from `anchor` on a chain, far above anyone's reach. Returns the
## lantern node; the caller adds the light (light budget lives in the builder).
static func hanged_lantern(parent: Node3D, anchor: Vector3, drop: float) -> Node3D:
	var root := Node3D.new()
	root.name = "HangedLantern"
	root.position = anchor
	parent.add_child(root)
	var chain := _acc()
	_tube(chain, PackedVector3Array([Vector3.ZERO, Vector3(0.0, -drop, 0.0)]), PackedFloat32Array([0.018, 0.018]), 4, PackedFloat32Array([0.0, 0.0]))
	_mesh_node(root, _finish(chain, 2.0)[0], "iron", "Chain")
	var body := AssetKit.place(root, "Lantern_01", Vector3(0.0, -drop - 0.62, 0.0), 0.3, 2.2)
	body.name = "Lantern"
	var glow := _acc()
	_blob(glow, Vector3(0.0, -drop - 0.33, 0.0), Vector3.UP, 0.1, 0.07, 6)
	_mesh_node(root, _finish(glow, 2.0)[0], "lantern_glow", "Flame")
	return root


## A cluster of small pale mushrooms with faintly glowing caps.
static func mushrooms(parent: Node3D, pos: Vector3, rng: RandomNumberGenerator) -> void:
	var stems := _acc()
	var caps := _acc()
	for k in rng.randi_range(3, 6):
		var o := pos + Vector3(rng.randf_range(-0.3, 0.3), -0.02, rng.randf_range(-0.3, 0.3))
		var h := rng.randf_range(0.08, 0.22)
		var r := h * rng.randf_range(0.45, 0.7)
		var lean := Vector3(rng.randf_range(-0.04, 0.04), h, rng.randf_range(-0.04, 0.04))
		_tube(stems, PackedVector3Array([o, o + lean]), PackedFloat32Array([r * 0.22, r * 0.18]), 4, PackedFloat32Array([0.0, 0.0]))
		_blob(caps, o + lean, Vector3.UP, r * 0.4, r, 6)
	var node := Node3D.new()
	node.name = "Mushrooms"
	parent.add_child(node)
	_mesh_node(node, _finish(stems, 2.0)[0], "bone", "Stems")
	_mesh_node(node, _finish(caps, 2.0)[0], "glow_cap", "Caps")


# --- Atmosphere ----------------------------------------------------------------

## Drifting moon motes and blinking fireflies as one MultiMesh (no lights).
static func motes(parent: Node3D, points: PackedVector3Array, fly_ratio: float, rng: RandomNumberGenerator) -> MultiMeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = points.size()
	for i in points.size():
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, points[i]))
		var fly := 1.0 if rng.randf() < fly_ratio else 0.0
		mm.set_instance_custom_data(i, Color(rng.randf(), fly, rng.randf(), rng.randf()))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Motes"
	mmi.multimesh = mm
	if not _mats.has("_motes"):
		var mat := ShaderMaterial.new()
		mat.shader = MOTE_SHADER
		_mats["_motes"] = mat
	mmi.material_override = _mats["_motes"]
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.extra_cull_margin = 2.0
	mmi.visibility_range_end = 42.0
	parent.add_child(mmi)
	return mmi


## Dappled moonlight lying along the ground through `pts` (left/right edge
## pairs, a few centimetres up): one additive wood_mist strip mesh, so the
## path reads as a pale leading line at the cost of one draw call.
static func ground_light(parent: Node3D, lefts: PackedVector3Array, rights: PackedVector3Array, params: Dictionary) -> MeshInstance3D:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()
	var along := 0.0
	for k in lefts.size():
		if k > 0:
			along += lefts[k].distance_to(lefts[k - 1])
		v.append(lefts[k] + Vector3(0.0, 0.07, 0.0))
		v.append(rights[k] + Vector3(0.0, 0.07, 0.0))
		n.append(Vector3.UP)
		n.append(Vector3.UP)
		uv.append(Vector2(0.0, along / 4.0))
		uv.append(Vector2(1.0, along / 4.0))
		if k > 0:
			var b := (k - 1) * 2
			idx.append_array([b, b + 2, b + 1, b + 1, b + 2, b + 3])
	var mi := mist(parent, Vector3.ZERO, Vector2.ONE, params)
	mi.name = "MoonOnPath"
	mi.mesh = _mesh(v, n, idx, uv)
	return mi


## One mist card (wood_mist.gdshader); `params` are shader uniforms.
static func mist(parent: Node3D, pos: Vector3, size: Vector2, params: Dictionary) -> MeshInstance3D:
	var mat := ShaderMaterial.new()
	mat.shader = MIST_SHADER
	for k: String in params:
		mat.set_shader_parameter(k, params[k])
	var quad := QuadMesh.new()
	quad.size = size
	var mi := MeshInstance3D.new()
	mi.name = "Mist"
	mi.mesh = quad
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta(MeshMerger.SKIP_META, true)
	mi.visibility_range_end = float(params.get("far_end", 110.0)) + 5.0
	mi.position = pos
	parent.add_child(mi)
	return mi
