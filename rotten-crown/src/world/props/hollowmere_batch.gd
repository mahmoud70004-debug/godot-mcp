@tool
class_name HollowmereBatch
extends RefCounted
## Vertex-coloured geometry accumulated per (material, cell, visibility range) for the
## Hollowmere props (U8): one mesh per group, so hundreds of pumpkins, leaves, growths
## and blood pools cost a few draw calls. final = true batches keep their vertex colours
## and own ranges (MeshMerger skips them); final = false batches hold textured pieces that
## MeshMerger.merge_static batches with the rest of the region.

class Group:
	var material: Material
	var range_begin := 0.0
	var range_end := 0.0
	var shadow := true
	var origin := Vector3.ZERO
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var i := PackedInt32Array()

	func vert(p: Vector3, nrm: Vector3, col: Color) -> int:
		v.append(p - origin)
		n.append(nrm)
		c.append(col)
		return v.size() - 1

	## Godot front faces are clockwise: the winding follows the vertex normals.
	func tri(a: int, b: int, d: int) -> void:
		var fn := (v[d] - v[a]).cross(v[b] - v[a])
		if fn.length_squared() < 1e-14:
			return
		if fn.dot(n[a] + n[b] + n[d]) < 0.0:
			i.append(a)
			i.append(d)
			i.append(b)
		else:
			i.append(a)
			i.append(b)
			i.append(d)


static var noise: FastNoiseLite
var cell := 16.0
## true: final vertex-coloured meshes (skip MeshMerger, own ranges). false: textured
## pieces handed to MeshMerger.merge_static (which rewrites vertex colours).
var final := true
var groups: Dictionary = {}
var _cell := Vector2i.ZERO
var _range := Vector2(0.0, 60.0)
var _shadow := true

func _init(p_cell: float, p_final := true) -> void:
	cell = p_cell
	final = p_final
	if noise == null:
		noise = FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.frequency = 0.9
		noise.seed = 77

## Following geometry belongs to the cell of `anchor` and is drawn up to `range_end` m.
func at(anchor: Vector3, range_end: float, shadow := false, range_begin := 0.0) -> void:
	_cell = Vector2i(floori(anchor.x / cell), floori(anchor.z / cell))
	_range = Vector2(range_begin, range_end)
	_shadow = shadow

func g(mat: Material) -> Group:
	var key := "%d|%d|%d|%.1f|%.1f|%s" % [mat.get_instance_id(), _cell.x, _cell.y, _range.x, _range.y, _shadow]
	var grp: Group = groups.get(key)
	if grp == null:
		grp = Group.new()
		grp.material = mat
		grp.range_begin = _range.x
		grp.range_end = _range.y
		grp.shadow = _shadow
		grp.origin = Vector3((_cell.x + 0.5) * cell, 0.0, (_cell.y + 0.5) * cell)
		groups[key] = grp
	return grp

func box(mat: Material, xf: Transform3D, size: Vector3, col: Color) -> void:
	var grp := g(mat)
	var h := size * 0.5
	var nb := xf.basis.inverse().transposed()
	for f in 6:
		var axis := f / 2
		var sgn := 1.0 if f % 2 == 0 else -1.0
		var nl := Vector3.ZERO
		nl[axis] = sgn
		var u := Vector3.ZERO
		u[(axis + 1) % 3] = 1.0
		var w := Vector3.ZERO
		w[(axis + 2) % 3] = 1.0
		var nw := (nb * nl).normalized()
		var base := grp.v.size()
		for k in 4:
			var su := -1.0 if k == 0 or k == 3 else 1.0
			var sw := -1.0 if k < 2 else 1.0
			var q := nl + u * su + w * sw
			grp.vert(xf * Vector3(q.x * h.x, q.y * h.y, q.z * h.z), nw, col)
		grp.tri(base, base + 1, base + 2)
		grp.tri(base, base + 2, base + 3)

## Box from a to b with cross-section (ty, tz), rolled around its axis.
func beam(mat: Material, a: Vector3, b: Vector3, ty: float, tz: float, col: Color, roll := 0.0) -> void:
	var d := b - a
	var length := d.length()
	if length < 0.001:
		return
	var x := d / length
	var up := Vector3.UP if absf(x.y) < 0.95 else Vector3.RIGHT
	var z := x.cross(up).normalized()
	var y := z.cross(x)
	var basis := Basis(x, y, z)
	if roll != 0.0:
		basis = Basis(x, roll) * basis
	box(mat, Transform3D(basis, (a + b) * 0.5), Vector3(length, ty, tz), col)

## Smooth surface over a rows x cols point grid (normals from neighbours, signed by `hints`).
func grid(mat: Material, pts: PackedVector3Array, cols: int, rows: int, wrap: bool, colors: PackedColorArray,
		hints: PackedVector3Array, skip := Callable()) -> void:
	var grp := g(mat)
	var base := grp.v.size()
	for r in rows:
		for cc in cols:
			var k := r * cols + cc
			var c0 := (cc - 1 + cols) % cols if wrap else maxi(cc - 1, 0)
			var c1 := (cc + 1) % cols if wrap else mini(cc + 1, cols - 1)
			var du := pts[r * cols + c1] - pts[r * cols + c0]
			var dv := pts[mini(r + 1, rows - 1) * cols + cc] - pts[maxi(r - 1, 0) * cols + cc]
			var nrm := du.cross(dv)
			var hint := hints[k]
			if nrm.length_squared() < 1e-12:
				nrm = hint
			elif nrm.dot(hint) < 0.0:
				nrm = -nrm
			grp.vert(pts[k], nrm.normalized(), colors[k])
	var span := cols if wrap else cols - 1
	for r in rows - 1:
		for cc in span:
			if skip.is_valid() and bool(skip.call(r, cc)):
				continue
			var a := base + r * cols + cc
			var b := base + r * cols + (cc + 1) % cols
			var d := base + (r + 1) * cols + (cc + 1) % cols
			var e := base + (r + 1) * cols + cc
			grp.tri(a, b, d)
			grp.tri(a, d, e)

## Lumpy ellipsoid. colfn(dir: Vector3, bulge: float) -> Color overrides `col`.
func blob(mat: Material, centre: Vector3, basis: Basis, radii: Vector3, segs: int, rings: int, col: Color,
		lump := 0.0, seed := 0.0, colfn := Callable()) -> void:
	var pts := PackedVector3Array()
	var cols := PackedColorArray()
	var hints := PackedVector3Array()
	for r in rings + 1:
		var phi := PI * r / rings
		for cc in segs:
			var th := TAU * cc / segs
			var d := Vector3(sin(phi) * cos(th), -cos(phi), sin(phi) * sin(th))
			var k := 1.0
			if lump > 0.0:
				k += lump * noise.get_noise_3d(d.x * 1.7 + seed, d.y * 1.7 + seed * 0.7, d.z * 1.7 - seed)
			pts.append(centre + basis * Vector3(d.x * radii.x, d.y * radii.y, d.z * radii.z) * k)
			hints.append(basis * d)
			cols.append(colfn.call(d, k) if colfn.is_valid() else col)
	grid(mat, pts, segs, rings + 1, true, cols, hints)

## Generalised cylinder along `path` (parallel-transport frames), no caps.
func tube(mat: Material, path: PackedVector3Array, radii: PackedFloat32Array, sides: int, col: Color, col_end := Color(-1, 0, 0)) -> void:
	var count := path.size()
	if count < 2:
		return
	var pts := PackedVector3Array()
	var cols := PackedColorArray()
	var hints := PackedVector3Array()
	var t0 := (path[1] - path[0]).normalized()
	var ref := Vector3.UP if absf(t0.y) < 0.9 else Vector3.RIGHT
	var nrm := t0.cross(ref).normalized()
	for k in count:
		var t := (path[mini(k + 1, count - 1)] - path[maxi(k - 1, 0)]).normalized()
		var proj := nrm - t * nrm.dot(t)
		if proj.length_squared() < 1e-6:
			proj = t.cross(Vector3.RIGHT if absf(t.x) < 0.9 else Vector3.FORWARD)
		nrm = proj.normalized()
		var bin := t.cross(nrm)
		var f := float(k) / (count - 1)
		var cc := col if col_end.r < 0.0 else col.lerp(col_end, f)
		for s in sides:
			var a := TAU * s / sides
			var d := nrm * cos(a) + bin * sin(a)
			pts.append(path[k] + d * radii[k])
			hints.append(d)
			cols.append(cc)
	grid(mat, pts, sides, count, true, cols, hints)

func fan(mat: Material, centre: Vector3, rim: PackedVector3Array, ccol: Color, rcol: Color, nrm: Vector3) -> void:
	var grp := g(mat)
	var c0 := grp.vert(centre, nrm, ccol)
	var base := grp.v.size()
	for p in rim:
		grp.vert(p, nrm, rcol)
	for k in rim.size():
		grp.tri(c0, base + k, base + (k + 1) % rim.size())

## Convex polygon (x, y in the xf plane) extruded along local z by `depth`.
func prism(mat: Material, xf: Transform3D, poly: PackedVector2Array, depth: float, col: Color) -> void:
	var grp := g(mat)
	var nb := xf.basis.inverse().transposed()
	for side: float in [1.0, -1.0]:
		var nrm := (nb * Vector3(0, 0, side)).normalized()
		var rim := PackedVector3Array()
		for p in poly:
			rim.append(xf * Vector3(p.x, p.y, side * depth * 0.5))
		var base := grp.v.size()
		for p in rim:
			grp.vert(p, nrm, col)
		for k in range(1, rim.size() - 1):
			grp.tri(base, base + k, base + k + 1)
	for k in poly.size():
		var a := poly[k]
		var b := poly[(k + 1) % poly.size()]
		var e := (b - a).normalized()
		var nrm := (nb * Vector3(e.y, -e.x, 0)).normalized()
		var centroid := Vector2.ZERO
		for p in poly:
			centroid += p
		centroid /= poly.size()
		if Vector2(e.y, -e.x).dot(a - centroid) < 0.0:
			nrm = -nrm
		var base := grp.v.size()
		grp.vert(xf * Vector3(a.x, a.y, depth * 0.5), nrm, col)
		grp.vert(xf * Vector3(b.x, b.y, depth * 0.5), nrm, col)
		grp.vert(xf * Vector3(b.x, b.y, -depth * 0.5), nrm, col)
		grp.vert(xf * Vector3(a.x, a.y, -depth * 0.5), nrm, col)
		grp.tri(base, base + 1, base + 2)
		grp.tri(base, base + 2, base + 3)

## Creates the meshes under `parent`; returns the triangle count.
func commit(parent: Node3D, label: String) -> int:
	var tris := 0
	for key in groups:
		var grp: Group = groups[key]
		if grp.i.is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = grp.v
		arrays[Mesh.ARRAY_NORMAL] = grp.n
		arrays[Mesh.ARRAY_COLOR] = grp.c
		arrays[Mesh.ARRAY_INDEX] = grp.i
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mi := MeshInstance3D.new()
		mi.name = label
		mi.mesh = mesh
		mi.material_override = grp.material
		mi.position = grp.origin
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if grp.shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if final:
			mi.set_meta(MeshMerger.SKIP_META, true)
			mi.visibility_range_begin = grp.range_begin
			mi.visibility_range_end = grp.range_end
			mi.visibility_range_begin_margin = 2.0 if grp.range_begin > 0.0 else 0.0
			mi.visibility_range_end_margin = 2.0
		parent.add_child(mi)
		tris += grp.i.size() / 3
	groups.clear()
	return tris


# --------------------------------------------------------------------------
