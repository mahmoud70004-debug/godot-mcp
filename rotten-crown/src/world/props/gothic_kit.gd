@tool
class_name GothicKit
extends RefCounted
## V28 - the gothic modules of the kingdom's architecture, built from code as flat-shaded meshes (the
## world materials are triplanar, so no UVs): fluted spires with ribs and crockets, pinnacles, stepped
## buttresses, pointed windows with tracery, a pointed arch frame, and a great octagonal tower.
## Everything is placed through a Builder: add shapes with a transform, then `commit(parent)` makes one
## MeshInstance3D per material (stone, mossy stone, dark glass, glowing glass), ready for MeshMerger.
## Scale: the kit is authored in metres; the "megalophobia" comes from using it much larger than a
## door (towers of 30 m, spires of 25 m on top) and losing the tops in the fog.

const GLASS := Color(0.012, 0.016, 0.022)
const GLOW := Color(0.45, 0.9, 0.35)


class Builder:
	extends RefCounted
	var xf := Transform3D.IDENTITY
	var stone := {"v": PackedVector3Array(), "n": PackedVector3Array(), "i": PackedInt32Array()}
	var mossy := {"v": PackedVector3Array(), "n": PackedVector3Array(), "i": PackedInt32Array()}
	var glass := {"v": PackedVector3Array(), "n": PackedVector3Array(), "i": PackedInt32Array()}
	var glow := {"v": PackedVector3Array(), "n": PackedVector3Array(), "i": PackedInt32Array()}
	var tris := 0

	## One triangle, oriented so it is front-facing (clockwise) towards `hint` (the outward direction).
	func tri(acc: Dictionary, a: Vector3, b: Vector3, c: Vector3, hint: Vector3) -> void:
		var n := (b - a).cross(c - a)
		if n.length_squared() < 1e-10:
			return
		if n.dot(hint) > 0.0:
			var t := b
			b = c
			c = t
			n = -n
		var out := (xf.basis * -n).normalized()
		var v: PackedVector3Array = acc["v"]
		var nn: PackedVector3Array = acc["n"]
		var idx: PackedInt32Array = acc["i"]
		var base := v.size()
		v.append(xf * a)
		v.append(xf * b)
		v.append(xf * c)
		nn.append(out)
		nn.append(out)
		nn.append(out)
		idx.append_array([base, base + 1, base + 2])
		tris += 1

	func quad(acc: Dictionary, a: Vector3, b: Vector3, c: Vector3, d: Vector3, hint: Vector3) -> void:
		tri(acc, a, b, c, hint)
		tri(acc, a, c, d, hint)

	## Oriented box between two points (a rib / a strut): `side` is the lateral direction hint.
	func rod(acc: Dictionary, p0: Vector3, p1: Vector3, w: float, d: float, side: Vector3) -> void:
		var axis := (p1 - p0).normalized()
		var s := (side - axis * side.dot(axis)).normalized() * (w * 0.5)
		var u := axis.cross(s).normalized() * (d * 0.5)
		var c := [p0 - s - u, p0 + s - u, p0 + s + u, p0 - s + u, p1 - s - u, p1 + s - u, p1 + s + u, p1 - s + u]
		var mid := (p0 + p1) * 0.5
		for f: Array in [[0, 1, 2, 3], [4, 5, 6, 7], [0, 1, 5, 4], [3, 2, 6, 7], [0, 3, 7, 4], [1, 2, 6, 5]]:
			var fc: Vector3 = (c[f[0]] + c[f[1]] + c[f[2]] + c[f[3]]) * 0.25
			quad(acc, c[f[0]], c[f[1]], c[f[2]], c[f[3]], fc - mid)

	func box(acc: Dictionary, centre: Vector3, size: Vector3) -> void:
		var h := size * 0.5
		var c := []
		for i in 8:
			c.append(centre + Vector3(h.x if i & 1 else -h.x, h.y if i & 2 else -h.y, h.z if i & 4 else -h.z))
		for f: Array in [[0, 1, 3, 2], [4, 5, 7, 6], [0, 1, 5, 4], [2, 3, 7, 6], [0, 2, 6, 4], [1, 3, 7, 5]]:
			var fc: Vector3 = (c[f[0]] + c[f[1]] + c[f[2]] + c[f[3]]) * 0.25
			quad(acc, c[f[0]], c[f[1]], c[f[2]], c[f[3]], fc - centre)

	## Loft between horizontal n-gon rings [[radius, height], ...] (a tip has radius 0); phase turns the polygon.
	func loft(acc: Dictionary, rings: Array, sides: int, phase := 0.0, cap_bottom := true) -> void:
		for k in rings.size() - 1:
			var r0: float = rings[k][0]
			var y0: float = rings[k][1]
			var r1: float = rings[k + 1][0]
			var y1: float = rings[k + 1][1]
			for j in sides:
				var a0 := phase + TAU * j / sides
				var a1 := phase + TAU * (j + 1) / sides
				var p00 := Vector3(cos(a0) * r0, y0, sin(a0) * r0)
				var p01 := Vector3(cos(a1) * r0, y0, sin(a1) * r0)
				var p10 := Vector3(cos(a0) * r1, y1, sin(a0) * r1)
				var p11 := Vector3(cos(a1) * r1, y1, sin(a1) * r1)
				var am := (a0 + a1) * 0.5
				var hint := Vector3(cos(am), 0.0, sin(am))
				if r1 <= 0.0001:
					tri(acc, p00, p01, p10, hint + Vector3.UP * 0.3)
				else:
					quad(acc, p00, p01, p11, p10, hint)
		if cap_bottom and rings[0][0] > 0.0:
			var r: float = rings[0][0]
			var y: float = rings[0][1]
			for j in sides:
				var a0 := phase + TAU * j / sides
				var a1 := phase + TAU * (j + 1) / sides
				tri(acc, Vector3(0, y, 0), Vector3(cos(a0) * r, y, sin(a0) * r), Vector3(cos(a1) * r, y, sin(a1) * r), Vector3.DOWN)

	## A small four-sided pyramid (a crocket / a finial) at `at`, base `w`, pointing along `dir`.
	func pyramid(acc: Dictionary, at: Vector3, dir: Vector3, w: float, h: float) -> void:
		var d := dir.normalized()
		var s := d.cross(Vector3.UP)
		s = s.normalized() if s.length_squared() > 0.01 else Vector3.RIGHT
		var u := d.cross(s).normalized()
		var tip := at + d * h
		var c := [at - s * w * 0.5 - u * w * 0.5, at + s * w * 0.5 - u * w * 0.5, at + s * w * 0.5 + u * w * 0.5, at - s * w * 0.5 + u * w * 0.5]
		for k in 4:
			var m: Vector3 = (c[k] + c[(k + 1) % 4]) * 0.5
			tri(acc, c[k], c[(k + 1) % 4], tip, m - at)

	func commit(parent: Node3D, stone_mat: Material, mossy_mat: Material) -> Array[MeshInstance3D]:
		var out: Array[MeshInstance3D] = []
		for entry: Array in [[stone, stone_mat, "Stone"], [mossy, mossy_mat, "Mossy"], [glass, RetroMaterials.flat(GLASS), "Glass"],
				[glow, RetroMaterials.flat(CastleProps.CURSED_LIGHT, 6.0), "Glow"]]:
			var acc: Dictionary = entry[0]
			var v: PackedVector3Array = acc["v"]
			if v.is_empty():
				continue
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = v
			arrays[Mesh.ARRAY_NORMAL] = acc["n"]
			arrays[Mesh.ARRAY_INDEX] = acc["i"]
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var mi := MeshInstance3D.new()
			mi.name = "Gothic" + String(entry[2])
			mi.mesh = mesh
			mi.material_override = entry[1]
			parent.add_child(mi)
			out.append(mi)
		return out


## A fluted spire standing on y = 0: octagonal base, a tall shaft, then the needle, with ribs on
## every edge, crockets climbing them and a finial. `r` base radius, `h` total height.
static func spire(b: Builder, r: float, h: float, sides := 8) -> void:
	var shaft := h * 0.28
	b.loft(b.stone, [[r * 1.12, 0.0], [r * 1.12, h * 0.03], [r, h * 0.035], [r * 0.9, shaft], [r * 0.95, shaft + h * 0.02], [r * 0.7, shaft + h * 0.04]], sides)
	var needle_base := shaft + h * 0.04
	b.loft(b.stone, [[r * 0.7, needle_base], [r * 0.45, needle_base + (h - needle_base) * 0.45], [r * 0.2, needle_base + (h - needle_base) * 0.85], [0.0, h]], sides, 0.0, false)
	# Ribs on the needle edges and crockets up them.
	for j in sides:
		var a := TAU * j / sides
		var dir := Vector3(cos(a), 0.0, sin(a))
		var p0 := dir * (r * 0.7 + 0.04) + Vector3.UP * needle_base
		var p1 := dir * 0.03 + Vector3.UP * (h - 0.2)
		b.rod(b.stone, p0, p1, r * 0.1, r * 0.1, dir.cross(Vector3.UP))
		for k in 6:
			var t := 0.08 + 0.15 * k
			var at := p0.lerp(p1, t)
			b.pyramid(b.stone, at, dir + Vector3.UP * 0.5, r * 0.12, r * 0.28)
	# Belfry openings in the shaft: a tall pointed slit on four faces.
	for j in 4:
		var a := TAU * j / 4 + TAU / (sides * 2.0)
		var dir := Vector3(cos(a), 0.0, sin(a))
		window(b, dir * (r * 0.9 + 0.05) + Vector3.UP * (shaft * 0.35), dir, r * 0.5, shaft * 0.5, false)
	# Finial: a small cross.
	var tip := Vector3.UP * h
	b.box(b.stone, tip + Vector3.UP * 0.55, Vector3(0.07, 1.1, 0.07))
	b.box(b.stone, tip + Vector3.UP * 0.75, Vector3(0.5, 0.07, 0.07))


## A pinnacle: square shaft with a small spire; `w` width, `h` height.
static func pinnacle(b: Builder, w: float, h: float) -> void:
	b.loft(b.stone, [[w * 0.62, 0.0], [w * 0.5, h * 0.55], [w * 0.62, h * 0.57]], 4, PI * 0.25)
	b.loft(b.stone, [[w * 0.5, h * 0.57], [w * 0.2, h * 0.86], [0.0, h]], 4, PI * 0.25, false)
	for j in 4:
		var a := PI * 0.25 + TAU * j / 4 + PI * 0.25
		b.pyramid(b.stone, Vector3(cos(a), 0.0, sin(a)) * w * 0.52 + Vector3.UP * (h * 0.6), Vector3(cos(a), 0.6, sin(a)), w * 0.16, w * 0.3)


## A pointed-arch window on the plane x-y, outward = +z (or `out` after a basis turn by the caller):
## stone frame, dark glass, two mullions, a round tracery light above them. `glow` makes the glass burn.
static func window(b: Builder, at: Vector3, out: Vector3, w: float, h: float, burn: bool) -> void:
	var old := b.xf
	var basis := Basis.looking_at(-out.normalized(), Vector3.UP)
	b.xf = old * Transform3D(basis, at)
	var spring := h * 0.62
	var pane := _arch_outline(w, h, spring)
	var frame := _arch_outline(w + 0.28, h + 0.22, spring)
	_fan(b, b.stone, frame, 0.0)
	_fan(b, b.glow if burn else b.glass, pane, 0.035)
	var t := w * 0.04
	for x in [-w * 0.17, w * 0.17]:
		b.box(b.stone, Vector3(x, spring * 0.5, 0.06), Vector3(t, spring, 0.06))
	b.box(b.stone, Vector3(0.0, spring * 0.62, 0.06), Vector3(w * 0.9, t, 0.06))
	# Tracery light: an octagon above the mullions.
	var c := Vector3(0.0, spring + (h - spring) * 0.42, 0.06)
	var rr := w * 0.17
	for j in 8:
		var a0 := TAU * j / 8
		var a1 := TAU * (j + 1) / 8
		b.tri(b.stone, c, c + Vector3(cos(a0) * rr * 1.3, sin(a0) * rr * 1.3, 0.0), c + Vector3(cos(a1) * rr * 1.3, sin(a1) * rr * 1.3, 0.0), Vector3.BACK)
		b.tri(b.glass, c + Vector3(0, 0, 0.02), c + Vector3(cos(a0) * rr, sin(a0) * rr, 0.02), c + Vector3(cos(a1) * rr, sin(a1) * rr, 0.02), Vector3.BACK)
	b.xf = old


static func _arch_outline(w: float, h: float, spring: float) -> PackedVector2Array:
	# An equilateral two-centred arch: it springs at (+-w/2, spring); the right arc is centred on the left springer
	# (radius w, 0..60 degrees), the left one mirrors it. The rise is stretched to fit `h`.
	var pts := PackedVector2Array()
	pts.append(Vector2(-w * 0.5, 0.0))
	pts.append(Vector2(w * 0.5, 0.0))
	var steps := 6
	var sy := (h - spring) / (w * sin(PI / 3.0))
	for k in range(0, steps + 1):
		var a := deg_to_rad(60.0) * float(k) / steps
		pts.append(Vector2(-w * 0.5 + w * cos(a), spring + w * sin(a) * sy))
	for k in range(steps - 1, -1, -1):
		var a := deg_to_rad(60.0) * float(k) / steps
		pts.append(Vector2(w * 0.5 - w * cos(a), spring + w * sin(a) * sy))
	return pts


## Fan-fills a convex-ish outline on the local x-y plane at depth z, facing +z.
static func _fan(b: Builder, acc: Dictionary, pts: PackedVector2Array, z: float) -> void:
	var c := Vector2.ZERO
	for p in pts:
		c += p
	c /= float(pts.size())
	for k in pts.size():
		var p0 := pts[k]
		var p1 := pts[(k + 1) % pts.size()]
		b.tri(acc, Vector3(c.x, c.y, z), Vector3(p0.x, p0.y, z), Vector3(p1.x, p1.y, z), Vector3.BACK)


## A stepped buttress on y = 0, projecting along +z from the wall plane (z = 0): `w` wide, `proj` deep, `h` tall,
## weathered in three set-offs, crowned by a pinnacle.
static func buttress(b: Builder, w: float, proj: float, h: float) -> void:
	var steps := [[1.0, 0.0, 0.42], [0.8, 0.42, 0.78], [0.6, 0.78, 1.0]]
	for s: Array in steps:
		var d := proj * float(s[0])
		var y0 := h * float(s[1])
		var y1 := h * float(s[2])
		b.box(b.stone, Vector3(0.0, (y0 + y1) * 0.5, d * 0.5), Vector3(w, y1 - y0, d))
		# A sloped weathering above each set-off.
		var sw := w * 1.04
		b.quad(b.stone, Vector3(-sw * 0.5, y1, 0.0), Vector3(sw * 0.5, y1, 0.0), Vector3(sw * 0.5, y1 - 0.25, d * 1.08), Vector3(-sw * 0.5, y1 - 0.25, d * 1.08), Vector3(0, 1, 1))
	var old := b.xf
	b.xf = old * Transform3D(Basis.IDENTITY, Vector3(0.0, h, proj * 0.6 * 0.5))
	pinnacle(b, w * 0.8, minf(h * 0.3, 4.0))
	b.xf = old


## A great octagonal tower on y = 0: battered plinth, banded shaft with three tiers of pointed windows, a corbelled
## crown and a spire on top. `r` radius, `h` shaft height, `spire_h` height of the spire.
static func great_tower(b: Builder, r: float, h: float, spire_h: float, burn_top := false) -> void:
	var sides := 8
	b.loft(b.mossy, [[r * 1.22, 0.0], [r * 1.12, h * 0.07], [r * 1.0, h * 0.09]], sides, PI / sides)
	b.loft(b.stone, [[r, h * 0.09], [r, h * 0.97]], sides, PI / sides, false)
	for k in 4:
		var y := h * (0.28 + 0.2 * k)
		b.loft(b.stone, [[r * 1.04, y], [r * 1.04, y + 0.35], [r * 1.0, y + 0.5]], sides, PI / sides, false)
	var tiers := [0.19, 0.4, 0.62]
	for tier in tiers.size():
		var ww := r * (0.5 if tier == 0 else 0.42)
		var wh := h * (0.14 if tier == 0 else 0.15)
		for j in sides:
			if tier == 1 and j % 2 == 1:
				continue
			var a := PI / sides + TAU * (j + 0.5) / sides - PI / sides * 0.0
			var dir := Vector3(cos(a), 0.0, sin(a))
			window(b, dir * (r * cos(PI / sides)) + Vector3.UP * (h * float(tiers[tier])), dir, ww, wh, burn_top and tier == 2 and j == 0)
	# Corbelled crown, a parapet of merlons and the spire.
	b.loft(b.stone, [[r * 1.0, h * 0.97], [r * 1.18, h * 0.985], [r * 1.18, h * 1.03], [r * 0.9, h * 1.03]], sides, PI / sides, false)
	for j in sides:
		var a := TAU * j / sides
		var p := Vector3(cos(a), 0.0, sin(a)) * r * 1.1 + Vector3.UP * (h * 1.03 + 0.5)
		b.box(b.stone, p, Vector3(r * 0.26, 1.0, r * 0.26))
		pinnacle_at(b, p + Vector3.UP * 0.5, r * 0.3, r * 1.3)
	var old := b.xf
	b.xf = old * Transform3D(Basis.IDENTITY, Vector3(0.0, h * 1.03, 0.0))
	spire(b, r * 0.8, spire_h)
	b.xf = old


static func pinnacle_at(b: Builder, at: Vector3, w: float, h: float) -> void:
	var old := b.xf
	b.xf = old * Transform3D(Basis.IDENTITY, at)
	pinnacle(b, w, h)
	b.xf = old
