@tool
class_name SwordMesh
extends RefCounted
## A medieval arming sword built as real geometry (grip at the origin, blade along +Y):
## a blade with a hexagonal-to-diamond section, a fuller in its forte, distal taper and a
## true point; a cross-guard whose quillons flare and dip towards the blade; a wrapped grip
## between two ferrules; and a wheel pommel. Steel shading lives in vertex colours (bright
## bevelled edges, duller flats, a darker fuller, rust creeping from the point) so it reads
## under the game's dim night light without reflection probes. One mesh, three surfaces:
## 0 blade, 1 hilt metal (tinted per weapon: gilt for the ceremonial blade), 2 leather grip.

const BLADE_BASE := 0.115
const BLADE_LEN := 0.86
const BLADE_W := 0.054
const BLADE_T := 0.0125
const FULLER_END := 0.62
const STEEL_EDGE := Color(0.86, 0.89, 0.94)
const STEEL_FLAT := Color(0.56, 0.6, 0.66)
const STEEL_FULLER := Color(0.34, 0.37, 0.43)
const RUST := Color(0.36, 0.17, 0.07)
const LEATHER := Color(0.2, 0.12, 0.08)
const LEATHER_DARK := Color(0.1, 0.06, 0.04)

static var _cache := {}


## The finished mesh for a hilt colour; cached because swords are rebuilt on every equip.
static func mesh(hilt: Color, rust: float = 0.35) -> ArrayMesh:
	var key := "%s|%.2f" % [hilt.to_html(), rust]
	if not _cache.has(key):
		var out := ArrayMesh.new()
		_add(out, _blade(rust), _steel_material())
		_add(out, _hilt(hilt), _hilt_material())
		_add(out, _grip(hilt), _leather_material())
		_cache[key] = out
	return _cache[key]


static func _add(out: ArrayMesh, st: SurfaceTool, mat: Material) -> void:
	st.generate_normals()
	st.commit(out)
	out.surface_set_material(out.get_surface_count() - 1, mat)


# --- Blade ------------------------------------------------------------------

static func _blade(rust: float) -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)  # flat facets: crisp bevels catch the light
	var rings: Array[PackedVector3Array] = []
	var cols: Array[PackedColorArray] = []
	var n := 18
	for i in n + 1:
		var u := float(i) / n
		var y := BLADE_BASE + u * BLADE_LEN
		# Profile: straight taper, then the point (last 14%) closes to nothing.
		var w := BLADE_W * lerpf(1.0, 0.62, u)
		var t := BLADE_T * lerpf(1.0, 0.5, u)
		if u > 0.86:
			var k := (u - 0.86) / 0.14
			w *= sqrt(maxf(1.0 - k * k, 0.0)) * (1.0 - k * 0.15)
			t *= 1.0 - k * 0.7
		var fuller := clampf((FULLER_END - u) / 0.08, 0.0, 1.0) * clampf(u / 0.03, 0.0, 1.0)
		var hw := w * 0.5
		# Eight points around the section, starting at the left edge.
		var mid := t * lerpf(1.0, 0.35, fuller)  # centre line sinks where the fuller runs
		var ring := PackedVector3Array([
			Vector3(-hw, y, 0.0), Vector3(-hw * 0.42, y, t * 0.82), Vector3(0.0, y, mid), Vector3(hw * 0.42, y, t * 0.82),
			Vector3(hw, y, 0.0), Vector3(hw * 0.42, y, -t * 0.82), Vector3(0.0, y, -mid), Vector3(-hw * 0.42, y, -t * 0.82),
		])
		var r := clampf((u - (1.0 - rust)) / maxf(rust, 0.001), 0.0, 1.0)
		var c := PackedColorArray()
		for j in 8:
			var base := STEEL_EDGE if j % 4 == 0 else (STEEL_FULLER.lerp(STEEL_FLAT, 1.0 - fuller) if j % 4 == 2 else STEEL_FLAT)
			# Rust blooms unevenly from the point and along the edges.
			var speck := 0.5 + 0.5 * sin(float(i) * 2.3 + float(j) * 1.7)
			c.append(base.lerp(RUST, clampf(r * (0.55 + 0.45 * speck), 0.0, 0.85)))
		rings.append(ring)
		cols.append(c)
	_loft(st, rings, cols, true)
	# Shoulders: close the base of the blade against the guard.
	_cap(st, rings[0], cols[0], true)
	return st


# --- Hilt metal: cross-guard, ferrules, pommel ---------------------------------

static func _hilt(metal: Color) -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hi := metal.lightened(0.25)
	var lo := metal.darkened(0.45)
	# Cross-guard: a square bar along X that thickens at the tips and dips towards the blade.
	st.set_smooth_group(-1)
	var rings: Array[PackedVector3Array] = []
	var cols: Array[PackedColorArray] = []
	var segs := 12
	for i in segs + 1:
		var s := lerpf(-1.0, 1.0, float(i) / segs)
		var x := s * 0.135
		var y := 0.1 + 0.022 * s * s
		var flare := 1.0 + 0.55 * pow(absf(s), 4.0)
		var hy := 0.0105 * flare
		var hz := 0.014 * flare
		if absf(s) < 0.2:  # the block where the blade passes through
			hy *= 1.5
			hz *= 1.25
		var ring := PackedVector3Array([Vector3(x, y - hy, -hz), Vector3(x, y + hy, -hz), Vector3(x, y + hy, hz), Vector3(x, y - hy, hz)])
		rings.append(ring)
		var wear := 0.5 + 0.5 * sin(s * 9.0)
		cols.append(PackedColorArray([lo, hi.lerp(metal, wear), metal, lo.lerp(metal, 0.5)]))
	_loft(st, rings, cols, false)
	_cap(st, rings[0], cols[0], true)
	_cap(st, rings[segs], cols[segs], false)
	# Ferrules at both ends of the grip.
	st.set_smooth_group(0)
	_cylinder(st, Vector3(0, 0.083, 0), 0.019, 0.012, 10, hi, lo)
	_cylinder(st, Vector3(0, -0.142, 0), 0.0185, 0.012, 10, hi, lo)
	# Wheel pommel: a disc seen edge-on from the side, with a raised boss on each face and the
	# peened tang on top.
	_wheel(st, Vector3(0, -0.175, 0), 0.03, 0.022, 16, metal, hi, lo)
	_cylinder(st, Vector3(0, -0.211, 0), 0.0065, 0.008, 8, hi, lo)
	return st


# --- Grip: leather wrapped in a spiral over a slightly swollen core -------------

static func _grip(metal: Color) -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	var rings: Array[PackedVector3Array] = []
	var cols: Array[PackedColorArray] = []
	var sides := 10
	var n := 26
	var y0 := -0.136
	var y1 := 0.077
	for i in n + 1:
		var u := float(i) / n
		var y := lerpf(y0, y1, u)
		var swell := 0.0155 + 0.0022 * sin(u * PI)
		var ring := PackedVector3Array()
		var c := PackedColorArray()
		for j in sides:
			var a := TAU * j / sides
			# The wrap: a ridge every few millimetres, winding around the grip.
			var wrap := 0.5 + 0.5 * sin(a + u * 7.0 * TAU)
			var r := swell + 0.0011 * wrap
			ring.append(Vector3(cos(a) * r, y, sin(a) * r))
			c.append(LEATHER_DARK.lerp(LEATHER, wrap))
		rings.append(ring)
		cols.append(c)
	_loft(st, rings, cols, true)
	# A thin gilt wire binding in the middle of the grip.
	for k in 2:
		_cylinder(st, Vector3(0, -0.04 + k * 0.04, 0), 0.0182, 0.003, 10, metal.lightened(0.2), metal.darkened(0.3))
	return st


# --- Geometry helpers -------------------------------------------------------------

## Quads between consecutive rings of equal size (closed around when `closed`).
static func _loft(st: SurfaceTool, rings: Array[PackedVector3Array], cols: Array[PackedColorArray], closed: bool) -> void:
	var m := rings[0].size()
	for i in rings.size() - 1:
		var a := rings[i]
		var b := rings[i + 1]
		for j in (m if closed else m - 1):
			var j2 := (j + 1) % m
			_tri(st, a[j], b[j], b[j2], cols[i][j], cols[i + 1][j], cols[i + 1][j2])
			_tri(st, a[j], b[j2], a[j2], cols[i][j], cols[i + 1][j2], cols[i][j2])


static func _cap(st: SurfaceTool, ring: PackedVector3Array, col: PackedColorArray, flip: bool) -> void:
	var centre := Vector3.ZERO
	for p in ring:
		centre += p
	centre /= ring.size()
	for j in ring.size():
		var j2 := (j + 1) % ring.size()
		if flip:
			_tri(st, centre, ring[j2], ring[j], col[j], col[j2], col[j])
		else:
			_tri(st, centre, ring[j], ring[j2], col[j], col[j], col[j2])


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	st.set_color(ca)
	st.add_vertex(a)
	st.set_color(cb)
	st.add_vertex(b)
	st.set_color(cc)
	st.add_vertex(c)


## Upright cylinder centred on `at`.
static func _cylinder(st: SurfaceTool, at: Vector3, r: float, h: float, sides: int, hi: Color, lo: Color) -> void:
	var bot := PackedVector3Array()
	var top := PackedVector3Array()
	var cb := PackedColorArray()
	var ct := PackedColorArray()
	for j in sides:
		var a := TAU * j / sides
		var d := Vector3(cos(a) * r, 0.0, sin(a) * r)
		bot.append(at + d - Vector3(0, h * 0.5, 0))
		top.append(at + d + Vector3(0, h * 0.5, 0))
		var lit := hi.lerp(lo, 0.5 + 0.5 * sin(a * 2.0))
		cb.append(lit.darkened(0.2))
		ct.append(lit)
	var rings: Array[PackedVector3Array] = [bot, top]
	var cols: Array[PackedColorArray] = [cb, ct]
	_loft(st, rings, cols, true)
	_cap(st, bot, cb, true)
	_cap(st, top, ct, false)


## A disc whose axis is Z (faces towards and away from the camera's side), with bosses.
static func _wheel(st: SurfaceTool, at: Vector3, r: float, thick: float, sides: int, metal: Color, hi: Color, lo: Color) -> void:
	var rings: Array[PackedVector3Array] = []
	var cols: Array[PackedColorArray] = []
	# Section profile from one face to the other: boss, face, bevelled rim, face, boss.
	var prof := [[0.0, -thick * 0.85], [0.42, -thick * 0.85], [0.5, -thick * 0.5], [0.92, -thick * 0.5], [1.0, -thick * 0.2],
		[1.0, thick * 0.2], [0.92, thick * 0.5], [0.5, thick * 0.5], [0.42, thick * 0.85], [0.0, thick * 0.85]]
	for p: Array in prof:
		var ring := PackedVector3Array()
		var c := PackedColorArray()
		for j in sides:
			var a := TAU * j / sides
			var rr := r * float(p[0])
			ring.append(at + Vector3(cos(a) * rr, sin(a) * rr, float(p[1])))
			var shade := 0.5 + 0.5 * sin(a + 0.8)
			c.append((hi if float(p[0]) >= 0.92 else metal).lerp(lo, shade * 0.6))
		rings.append(ring)
		cols.append(c)
	_loft(st, rings, cols, true)


# --- Materials ---------------------------------------------------------------------

static func _steel_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	m.metallic = 0.35
	m.roughness = 0.3
	m.metallic_specular = 0.9
	m.rim_enabled = true
	m.rim = 0.55
	m.rim_tint = 0.4
	# No reflection probes at night: a faint self-light keeps steel from going black.
	m.emission_enabled = true
	m.emission = Color(0.05, 0.06, 0.08)
	return m


static func _hilt_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	m.metallic = 0.3
	m.roughness = 0.42
	m.rim_enabled = true
	m.rim = 0.35
	m.emission_enabled = true
	m.emission = Color(0.04, 0.035, 0.02)
	return m


static func _leather_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.9
	return m
