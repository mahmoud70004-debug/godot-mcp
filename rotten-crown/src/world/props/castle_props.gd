@tool
class_name CastleProps
extends RefCounted
## Gothic dressing of the walls of Valdron as seen from the Moonlit Meadows
## (task U10), used by OuterWardBlockout for both the cursed castle and the
## night of the feast (`festive`): the battered, buttressed front wall with
## machicolations and cross slits, square flanking towers, the twin-towered
## gatehouse with its pointed arch, the portcullis and the tall oak doors -
## raised and thrown open for the feast, jammed, bent and smashed after.
## Primitives with shared RetroMaterials (merged by OuterWardBlockout).
## Layout: the front wall runs along z = 10 (outer face +Z), gate |x| < 3.5.

const WALL_HEIGHT := 7.0
const WALL_THICKNESS := 2.0
const GATE_HALF_WIDTH := 3.5
## Gatehouse towers either side of the gate (x centre, half width, height).
const GATE_TOWER_HALF := 1.9
const GATE_TOWER_X := GATE_HALF_WIDTH + GATE_TOWER_HALF
const GATE_TOWER_H := 11.0
## Pointed (two-centred) gate arch: springing height and arc radius.
const ARCH_SPRING := 4.2
const ARCH_RADIUS := 5.5
## Square flanking towers on the front wall.
const WALL_TOWER_X := 17.0
const CURSED_LIGHT := Color(0.55, 1.0, 0.3)

var festive := false
var _rng: RandomNumberGenerator
var _ooze_mat: ShaderMaterial


static var _mats: Dictionary = {}


## Castle stone of the front (the walls the knight wakes up to): the same
## scanned castle brick as RetroMaterials.stone(), a smaller course and a paler
## tint so the backlit face still reads under the moon.
static func front_stone() -> StandardMaterial3D:
	return _bounce("front_stone", RetroMaterials.stone(), Color(0.6, 0.6, 0.62), 2.4)


## The wet, mossy plinth and string courses of the front.
static func front_mossy() -> StandardMaterial3D:
	return _bounce("front_mossy", RetroMaterials.mossy_stone(), Color(0.44, 0.5, 0.4), 2.4)


## Oak of the gate leaves.
static func door_wood() -> StandardMaterial3D:
	return _bounce("door_wood", RetroMaterials.wood(), Color(0.6, 0.52, 0.45), 2.0)


## Valdron red of the gate banners.
static func banner_cloth() -> StandardMaterial3D:
	return _bounce("banner_cloth", RetroMaterials.valdron_cloth(), Color(1.25, 1.1, 1.1), 0.0)


## A copy of `base` with its own tint and a faint cold emission through its own
## texture: the bounce of the moonlit meadow on the backlit front of the castle,
## so courses, planks and cloth keep their detail (`tile` 0 keeps the mapping).
static func _bounce(key: String, base: StandardMaterial3D, tint: Color, tile: float) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var mat := base.duplicate() as StandardMaterial3D
	mat.albedo_color = tint
	if tile > 0.0:
		mat.uv1_scale = Vector3.ONE / tile
	mat.emission_enabled = true
	mat.emission = Color(0.18, 0.2, 0.22)
	mat.emission_energy_multiplier = 0.5
	mat.emission_texture = mat.albedo_texture
	mat.set_meta("swatch", tint)
	_mats[key] = mat
	return mat


func _init(p_festive: bool, rng: RandomNumberGenerator, ooze: ShaderMaterial) -> void:
	festive = p_festive
	_rng = rng
	_ooze_mat = ooze


## Outer face of a front wall stretch from x0 to x1 (z = 10): battered mossy
## plinth, string course, buttresses, cross-shaped arrow slits, a projecting
## parapet on corbels (machicolations) with tall merlons; green ooze weeping
## from the slits once the curse has taken the castle.
func dress_front(parent: Node3D, x0: float, x1: float) -> void:
	var stone := front_stone()
	var mossy := front_mossy()
	var slit := RetroMaterials.flat(Color(0.012, 0.012, 0.012))
	var length := x1 - x0
	var cx := (x0 + x1) * 0.5
	var face := 10.0 + WALL_THICKNESS * 0.5
	_box(parent, Vector3(length, 1.2, 0.9), Vector3(cx, 0.6, face + 0.35), mossy)
	_box(parent, Vector3(length, 0.3, 0.7), Vector3(cx, 1.25, face + 0.22), mossy, Vector3(-0.55, 0.0, 0.0), false)
	_box(parent, Vector3(length, 0.2, 0.25), Vector3(cx, 4.4, face + 0.1), stone, Vector3.ZERO, false)
	# Machicolations: corbels carrying the outer parapet and its merlons.
	var x := x0 + 0.55
	while x < x1 - 0.3:
		_box(parent, Vector3(0.3, 0.55, 0.5), Vector3(x, 6.72, face + 0.25), stone, Vector3.ZERO, false)
		x += 1.1
	_box(parent, Vector3(length, 1.0, 0.5), Vector3(cx, 7.45, face + 0.3), stone, Vector3.ZERO, false)
	var i := 0
	x = x0 + 1.0
	while x < x1 - 0.5:
		_box(parent, Vector3(1.0, 1.05, 0.5), Vector3(x, 8.47, face + 0.3), stone, Vector3.ZERO, false)
		if i % 2 == 0:
			_box(parent, Vector3(0.09, 0.55, 0.04), Vector3(x, 8.45, face + 0.56), slit, Vector3.ZERO, false)
		x += 2.0
		i += 1
	# Buttresses (skipped where a wall tower stands) and arrow slits between them.
	x = x0 + 3.5
	while x < x1 - 2.0:
		if absf(absf(x) - WALL_TOWER_X) > 3.6:
			_box(parent, Vector3(1.1, 5.0, 1.3), Vector3(x, 2.5, face + 0.65), stone)
			_box(parent, Vector3(1.1, 0.35, 1.5), Vector3(x, 5.15, face + 0.48), mossy, Vector3(0.62, 0.0, 0.0), false)
		var sx := x + 3.5
		if sx < x1 - 1.5 and absf(absf(sx) - WALL_TOWER_X) > 3.2:
			_box(parent, Vector3(0.14, 1.2, 0.05), Vector3(sx, 5.4, face + 0.02), slit, Vector3.ZERO, false)
			_box(parent, Vector3(0.5, 0.12, 0.05), Vector3(sx, 5.55, face + 0.02), slit, Vector3.ZERO, false)
			if not festive and _rng.randf() < 0.22:
				var drip := _splat(parent, _ooze_mat, Vector3(sx, 3.9, face + 0.04), _rng.randf_range(0.9, 1.3), true)
				drip.scale = Vector3(0.35, 2.4, 1.0)
		x += 7.0


## Square flanking tower standing out of the front wall: battered plinth,
## slits and a lancet window, a corbelled crown with merlons and a steep roof.
func wall_tower(parent: Node3D, base: Vector3) -> void:
	var stone := front_stone()
	var mossy := front_mossy()
	var slit := RetroMaterials.flat(Color(0.012, 0.012, 0.012))
	var w := 5.0
	var h := 10.5
	var c := base + Vector3(0.0, 0.0, 1.5)
	_box(parent, Vector3(w, h, w), c + Vector3(0.0, h * 0.5, 0.0), stone)
	_box(parent, Vector3(w + 0.8, 1.4, w + 0.8), c + Vector3(0.0, 0.7, 0.0), mossy, Vector3.ZERO, false)
	_box(parent, Vector3(w + 0.25, 0.2, w + 0.25), c + Vector3(0.0, 6.5, 0.0), stone, Vector3.ZERO, false)
	_crown(parent, c, w, h, 3)
	_spire(parent, c + Vector3(0.0, h + 1.0, 0.0), w * 0.68, 6.0)
	var front := c.z + w * 0.5 + 0.02
	for ly in [3.6, 6.4]:
		_box(parent, Vector3(0.14, 1.2, 0.05), Vector3(c.x, ly, front), slit, Vector3.ZERO, false)
	_lancet(parent, Vector3(c.x, 8.4, front), 0.55, 1.3, festive)
	for sx in [-1.0, 1.0]:
		_box(parent, Vector3(0.05, 1.2, 0.14), Vector3(c.x + sx * (w * 0.5 + 0.02), 6.2, c.z + 0.6), slit, Vector3.ZERO, false)


## Corbels round the top of a square block (centre c, width w, height h), a
## projecting crown and merlons on it; `per_side` merlons on each face.
func _crown(parent: Node3D, c: Vector3, w: float, h: float, per_side: int) -> void:
	var stone := front_stone()
	var half := w * 0.5
	for k in per_side + 1:
		var t := -half + 0.5 + (w - 1.0) * float(k) / per_side
		_box(parent, Vector3(0.3, 0.55, 0.45), c + Vector3(t, h - 0.55, half + 0.2), stone, Vector3.ZERO, false)
		for sx in [-1.0, 1.0]:
			_box(parent, Vector3(0.45, 0.55, 0.3), c + Vector3(sx * (half + 0.2), h - 0.55, t), stone, Vector3.ZERO, false)
	_box(parent, Vector3(w + 0.8, 1.0, w + 0.8), c + Vector3(0.0, h + 0.2, 0.0), stone, Vector3.ZERO, false)
	for k in per_side:
		var t := -half + w * (float(k) + 0.5) / per_side
		for face in [Vector3(t, 0, half + 0.15), Vector3(t, 0, -half - 0.15)]:
			_box(parent, Vector3(0.8, 0.9, 0.5), c + face + Vector3(0.0, h + 1.15, 0.0), stone, Vector3.ZERO, false)
		for sx in [-1.0, 1.0]:
			_box(parent, Vector3(0.5, 0.9, 0.8), c + Vector3(sx * (half + 0.15), h + 1.15, t), stone, Vector3.ZERO, false)


## Steep four-sided roof with an iron finial and small corner pinnacles
## at the roof's own corners (`pinnacles` off: the caller places its own).
func _spire(parent: Node3D, base: Vector3, radius: float, height: float, pinnacles := true) -> void:
	var roof := RetroMaterials.roof()
	_cylinder(parent, 0.0, radius * 1.414, height, base + Vector3(0.0, height * 0.5, 0.0), roof, Vector3(0.0, PI * 0.25, 0.0), false, 4)
	_cylinder(parent, 0.03, 0.06, 1.6, base + Vector3(0.0, height + 0.7, 0.0), RetroMaterials.iron(), Vector3.ZERO, false, 4)
	_box(parent, Vector3(0.5, 0.05, 0.05), base + Vector3(0.0, height + 1.1, 0.0), RetroMaterials.iron(), Vector3.ZERO, false)
	if pinnacles:
		for k in 4:
			var a := PI * 0.25 + PI * 0.5 * k
			_pinnacle(parent, base + Vector3(cos(a), 0.0, sin(a)) * radius * 1.414 * 0.92)


func _pinnacle(parent: Node3D, p: Vector3) -> void:
	_cylinder(parent, 0.0, 0.28, 1.5, p + Vector3(0.0, 0.55, 0.0), front_stone(), Vector3(0.0, PI * 0.25, 0.0), false, 4)


## Tall pointed (lancet) window on a +Z face: a dark slot with a pointed head.
## Lit warm for the feast; once cursed one in three glows a faint sick green.
func _lancet(parent: Node3D, centre: Vector3, w: float, h: float, lit: bool) -> void:
	var mat := RetroMaterials.flat(Color(0.012, 0.012, 0.012))
	if lit:
		mat = RetroMaterials.flat(Color(1.0, 0.68, 0.32), 3.0)
	elif _rng.randf() < 0.34:
		mat = RetroMaterials.flat(CURSED_LIGHT * 0.6, 1.6)
	_box(parent, Vector3(w, h, 0.05), centre, mat, Vector3.ZERO, false)
	_box(parent, Vector3(w * 0.707, w * 0.707, 0.05), centre + Vector3(0.0, h * 0.5, 0.0), mat, Vector3(0.0, 0.0, PI * 0.25), false)


# --- Gate --------------------------------------------------------------------

## Height of the pointed (two-centred) gate arch above the ground at x.
static func arch_height(x: float) -> float:
	var c := ARCH_RADIUS - GATE_HALF_WIDTH
	var dx := absf(x) + c
	return ARCH_SPRING + sqrt(maxf(ARCH_RADIUS * ARCH_RADIUS - dx * dx, 0.0))


## The gatehouse: twin towers, the pointed arch, portcullis and doors.
func gatehouse(gate: Node3D) -> void:
	var stone := front_stone()
	var mossy := front_mossy()
	var slit := RetroMaterials.flat(Color(0.012, 0.012, 0.012))
	var tw := GATE_TOWER_HALF * 2.0
	var tz := 10.6
	var td := 4.8
	var front := tz + td * 0.5
	# Twin gate towers standing out of the wall, taller than everything but the Keep.
	for side in [-1.0, 1.0]:
		var c := Vector3(side * GATE_TOWER_X, 0.0, tz)
		_box(gate, Vector3(tw, GATE_TOWER_H, td), c + Vector3(0.0, GATE_TOWER_H * 0.5, 0.0), stone)
		_box(gate, Vector3(tw + 0.4, 1.5, td + 0.8), c + Vector3(side * 0.2, 0.75, 0.2), mossy, Vector3.ZERO, false)
		_box(gate, Vector3(tw + 0.6, 0.35, td + 1.0), c + Vector3(side * 0.2, 1.55, 0.2), mossy, Vector3(-0.35, 0.0, 0.0), false)
		for ly in [4.6, 8.4]:
			_box(gate, Vector3(tw + 0.2, 0.2, td + 0.2), c + Vector3(0.0, ly, 0.0), stone, Vector3.ZERO, false)
		_crown(gate, Vector3(c.x, 0.0, c.z), tw, GATE_TOWER_H, 3)
		# Slender spires: the prologue's opening flight passes close over the right one.
		_spire(gate, Vector3(c.x + side * 0.6, GATE_TOWER_H + 1.0, c.z + 0.3), 0.9, 6.5, false)
		for k in 4:
			var a := PI * 0.25 + PI * 0.5 * k
			_pinnacle(gate, Vector3(c.x, GATE_TOWER_H + 1.0, c.z) + Vector3(cos(a), 0.0, sin(a)) * (tw * 0.5 + 0.2) * 1.414)
		for ly in [3.2, 7.4]:
			_box(gate, Vector3(0.14, 1.2, 0.05), Vector3(c.x, ly, front + 0.02), slit, Vector3.ZERO, false)
			_box(gate, Vector3(0.5, 0.12, 0.05), Vector3(c.x, ly + 0.15, front + 0.02), slit, Vector3.ZERO, false)
		_lancet(gate, Vector3(c.x, 9.4, front + 0.02), 0.6, 1.4, festive)
	# The gate arch: stepped spandrels between the towers, a ring of voussoirs
	# and a keystone on both faces, the wall walk and machicolation above.
	var depth := 3.8
	var az := 10.5
	var apex := arch_height(0.0)
	var top := 10.2
	var y := ARCH_SPRING
	while y < apex - 0.05:
		var y1 := minf(y + 0.4, apex)
		var w := arch_height_inverse((y + y1) * 0.5)
		for side in [-1.0, 1.0]:
			var span := GATE_HALF_WIDTH - w
			_box(gate, Vector3(span, y1 - y, depth), Vector3(side * (w + span * 0.5), (y + y1) * 0.5, az), stone, Vector3.ZERO, false)
		y = y1
	_box(gate, Vector3(GATE_HALF_WIDTH * 2.0, top - apex, depth), Vector3(0.0, (apex + top) * 0.5, az), stone, Vector3.ZERO, false)
	for face_z in [az + depth * 0.5 + 0.08, az - depth * 0.5 - 0.08]:
		_voussoirs(gate, face_z)
	var x := -GATE_HALF_WIDTH + 0.5
	while x < GATE_HALF_WIDTH:
		_box(gate, Vector3(0.3, 0.5, 0.45), Vector3(x, top - 0.45, az + depth * 0.5 + 0.2), stone, Vector3.ZERO, false)
		x += 1.0
	_box(gate, Vector3(GATE_HALF_WIDTH * 2.0, 1.0, 0.5), Vector3(0.0, top + 0.3, az + depth * 0.5 + 0.3), stone, Vector3.ZERO, false)
	for k in 3:
		_box(gate, Vector3(1.0, 0.95, 0.5), Vector3(-2.3 + k * 2.3, top + 1.25, az + depth * 0.5 + 0.3), stone, Vector3.ZERO, false)
	_portcullis(gate, az + depth * 0.5 - 0.35)
	_gate_doors(gate)
	if not festive:
		# The rotten feast glows with the curse: a low sick light over the spill
		# (its source is the ooze pooled among the food, see feast_spill).
		var glow := OmniLight3D.new()
		glow.name = "SpillGlow"
		glow.light_color = Color(0.6, 0.9, 0.4)
		glow.light_energy = 1.3
		glow.omni_range = 6.5
		glow.omni_attenuation = 1.2
		glow.shadow_enabled = false
		glow.position = Vector3(0.0, 1.2, 17.4)
		gate.add_child(glow)


## Inverse of arch_height: half-width of the opening at height y.
static func arch_height_inverse(y: float) -> float:
	var c := ARCH_RADIUS - GATE_HALF_WIDTH
	var dy := y - ARCH_SPRING
	return clampf(sqrt(maxf(ARCH_RADIUS * ARCH_RADIUS - dy * dy, 0.0)) - c, 0.0, GATE_HALF_WIDTH)


## Ring of wedge stones round the pointed arch on the face at z = face_z.
func _voussoirs(parent: Node3D, face_z: float) -> void:
	var stone := front_stone()
	var c := ARCH_RADIUS - GATE_HALF_WIDTH
	var end := acos(c / ARCH_RADIUS)
	var n := 7
	for side in [-1.0, 1.0]:
		for k in n:
			var a0 := end * float(k) / n
			var a1 := end * float(k + 1) / n
			var p0 := Vector2(-c + cos(a0) * ARCH_RADIUS, sin(a0) * ARCH_RADIUS)
			var p1 := Vector2(-c + cos(a1) * ARCH_RADIUS, sin(a1) * ARCH_RADIUS)
			var mid := (p0 + p1) * 0.5
			var out := (mid - Vector2(-c, 0.0)).normalized()
			var centre := mid + out * 0.32
			var ang := atan2(p1.y - p0.y, p1.x - p0.x)
			_box(parent, Vector3(p0.distance_to(p1) + 0.06, 0.62, 0.3), Vector3(side * centre.x, ARCH_SPRING + centre.y, face_z),
				stone, Vector3(0.0, 0.0, ang if side > 0.0 else -ang), false)
	_box(parent, Vector3(0.55, 0.95, 0.36), Vector3(0.0, arch_height(0.0) + 0.3, face_z), stone, Vector3.ZERO, false)


## The portcullis: raised into the arch for the feast (only its teeth show),
## jammed half-way down, bent and missing bars once the gate was forced.
func _portcullis(parent: Node3D, z: float) -> void:
	var iron := RetroMaterials.iron()
	var x := -GATE_HALF_WIDTH + 0.35
	while x < GATE_HALF_WIDTH - 0.2:
		var top := arch_height(x) - 0.1
		if festive:
			_box(parent, Vector3(0.09, 0.7, 0.09), Vector3(x, top - 0.35, z), iron, Vector3.ZERO, false)
		elif _rng.randf() > 0.18:
			var bottom := _rng.randf_range(2.6, 3.4) if _rng.randf() > 0.25 else _rng.randf_range(3.8, 5.0)
			var bar := _box(parent, Vector3(0.09, top - bottom, 0.09), Vector3(x, (top + bottom) * 0.5, z), iron, Vector3.ZERO, false)
			if _rng.randf() < 0.3:
				bar.rotation = Vector3(_rng.randf_range(-0.25, 0.1), 0.0, _rng.randf_range(-0.12, 0.12))
		x += 0.45
	if festive:
		return
	for ly in [3.0, 4.3]:
		_box(parent, Vector3(GATE_HALF_WIDTH * 2.0 - 0.6, 0.1, 0.1), Vector3(0.0, ly, z), iron, Vector3(0.0, 0.0, _rng.randf_range(-0.03, 0.03)), false)
	# Bars torn out and thrown down in the gateway.
	_box(parent, Vector3(0.09, 1.8, 0.09), Vector3(-1.2, 0.08, 7.5), iron, Vector3(PI * 0.5, 0.4, 0.0), false)
	_box(parent, Vector3(0.09, 1.4, 0.09), Vector3(1.6, 0.08, 8.2), iron, Vector3(PI * 0.5, -0.9, 0.0), false)
	_box(parent, Vector3(0.09, 2.2, 0.09), Vector3(-2.4, 0.07, 14.6), iron, Vector3(PI * 0.5, 1.1, 0.0), false)


## Tall pointed oak doors. Feast: both thrown open inward against the passage.
## Cursed: the gate was forced from inside - the left leaf hangs out over the
## meadow from its top hinge, the right one is smashed, its lower half in
## splinters across the road.
func _gate_doors(parent: Node3D) -> void:
	if festive:
		_door(parent, Vector3(-GATE_HALF_WIDTH, 0.0, 8.8), 1.35, -1.0, 0.0, 0.0)
		_door(parent, Vector3(GATE_HALF_WIDTH, 0.0, 8.8), PI - 1.35, 1.0, 0.0, 0.0)
		return
	var left := _door(parent, Vector3(-GATE_HALF_WIDTH, 0.0, 12.95), -2.0, -1.0, 0.0, -0.13)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(3.2, 4.0, 0.3)
	cs.shape = shape
	cs.position = Vector3(1.65, 2.0, 0.0)
	body.add_child(cs)
	left.add_child(body)
	_door(parent, Vector3(GATE_HALF_WIDTH, 0.0, 12.95), PI + 0.22, 1.0, 4.6, 0.05)
	# The lower half of the right leaf: a big chunk and splinters on the road.
	var wood := door_wood()
	var chunk := Node3D.new()
	chunk.name = "DoorChunk"
	chunk.position = Vector3(2.6, 0.12, 15.6)
	chunk.rotation = Vector3(PI * 0.5 - 0.06, 0.5, 0.0)
	parent.add_child(chunk)
	for k in 6:
		_box(chunk, Vector3(0.3, _rng.randf_range(1.6, 2.6), 0.14), Vector3(-0.9 + k * 0.32, 0.0, 0.0), wood, Vector3.ZERO, false)
	_box(chunk, Vector3(1.9, 0.2, 0.08), Vector3(0.0, 0.3, -0.1), wood, Vector3.ZERO, false)
	for i in 9:
		var p := Vector3(_rng.randf_range(-2.0, 3.5), 0.05, _rng.randf_range(12.8, 18.5))
		_box(parent, Vector3(0.12, 0.05, _rng.randf_range(0.5, 1.6)), p, wood, Vector3(0.0, _rng.randf() * TAU, _rng.randf_range(-0.1, 0.1)), false)


## One gate leaf hinged at `hinge`, its planks running along local +X when
## yaw = 0 (`dir` = -1 builds the left leaf, +1 the right, mirrored so the
## planks follow the arch). Planks below `broken_below` are smashed away; `sag`
## tilts the free end down (hanging from the top hinge). Returns the pivot.
func _door(parent: Node3D, hinge: Vector3, yaw: float, dir: float, broken_below: float, sag: float) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = "GateLeaf"
	pivot.position = hinge
	pivot.rotation = Vector3(0.0, yaw, sag)
	parent.add_child(pivot)
	var wood := door_wood()
	var iron := RetroMaterials.iron()
	var plank := 0.32
	var n := int(GATE_HALF_WIDTH / plank)
	for k in n:
		var lx := (k + 0.5) * plank
		var world_x := -GATE_HALF_WIDTH + lx if dir < 0.0 else GATE_HALF_WIDTH - lx
		var h := arch_height(world_x) - 0.12
		var y0 := 0.0
		if broken_below > 0.0:
			y0 = broken_below + _rng.randf_range(-0.5, 0.7)
		elif not festive and _rng.randf() < 0.12:
			continue  # a plank stove in
		if h - y0 < 0.3:
			continue
		_box(pivot, Vector3(plank - 0.03, h - y0, 0.16), Vector3(lx, (h + y0) * 0.5, 0.0), wood, Vector3.ZERO, false)
	for by in [1.0, 3.4, 5.8]:
		if by > broken_below:
			_box(pivot, Vector3(GATE_HALF_WIDTH - 0.1, 0.22, 0.1), Vector3(GATE_HALF_WIDTH * 0.5, by, -0.12), wood, Vector3.ZERO, false)
			_box(pivot, Vector3(1.2, 0.12, 0.04), Vector3(0.6, by, 0.1), iron, Vector3.ZERO, false)
	if broken_below <= 0.0:
		_box(pivot, Vector3(3.6, 0.18, 0.08), Vector3(GATE_HALF_WIDTH * 0.5, 2.2, -0.13), wood, Vector3(0.0, 0.0, 0.6), false)
	return pivot


# --- Banners and the spilled feast ---------------------------------------------

## Valdron banners on the gate towers' outer faces. Feast: long, whole, gold
## fringed, and a garland of bunting across the arch. Cursed: the left one torn
## to ribbons, the right one ripped from a nail and hanging askew, the bunting
## dragged down into the grass.
func gate_banners(parent: Node3D) -> void:
	var front := 10.6 + 2.4 + 0.06
	for side in [-1.0, 1.0]:
		var top := Vector3(side * GATE_TOWER_X, GATE_TOWER_H - 1.3, front)
		_box(parent, Vector3(2.9, 0.12, 0.12), top + Vector3(0.0, 0.1, 0.05), RetroMaterials.wood(), Vector3.ZERO, false)
		if festive:
			_banner(parent, top, 0.0, 7.6, 0.0)
		elif side < 0.0:
			_banner(parent, top, 0.0, 3.4, 0.85)
		else:
			_banner(parent, top + Vector3(-1.1, 0.0, 0.0), 0.62, 4.2, 0.5)
	var cloth := [RetroMaterials.valdron_cloth(), RetroMaterials.flat(Color(0.55, 0.45, 0.16)), RetroMaterials.linen()]
	if festive:
		_bunting_line(parent, Vector3(-GATE_TOWER_X - 1.6, 10.4, front + 0.15), Vector3(GATE_TOWER_X + 1.6, 10.4, front + 0.15), 1.2, cloth, 0.0)
		return
	# Torn down: hangs from the left tower crown to the ground in the meadow.
	_bunting_line(parent, Vector3(-GATE_TOWER_X - 1.6, 10.4, front + 0.15), Vector3(-9.5, 0.05, 19.0), 1.2, cloth, 0.3)


## One banner hung from `top` (centre of its pole): a 2.2 m wide field of
## Valdron red, gold crown, gold hem. `length` of whole cloth, then `torn` is
## how much of the rest is shredded into hanging strips; `tilt` swings it on
## its remaining nail (radians about Z).
func _banner(parent: Node3D, top: Vector3, tilt: float, length: float, torn: float) -> void:
	var pivot := Node3D.new()
	pivot.name = "Banner"
	pivot.position = top + Vector3(1.1 * signf(tilt), 0.0, 0.0) if tilt != 0.0 else top
	pivot.rotation.z = tilt
	parent.add_child(pivot)
	var off := Vector3(-1.1 * signf(tilt), 0.0, 0.0) if tilt != 0.0 else Vector3.ZERO
	var cloth := banner_cloth()
	var gold := RetroMaterials.flat(Color(0.55, 0.45, 0.16))
	var w := 2.2
	_box(pivot, Vector3(w, length, 0.03), off + Vector3(0.0, -length * 0.5, 0.0), cloth, Vector3.ZERO, false)
	# Crown: band and three points; a gold hem when whole.
	var crown := off + Vector3(0.0, -1.5, 0.03)
	_box(pivot, Vector3(0.9, 0.22, 0.02), crown, gold, Vector3.ZERO, false)
	for k in 3:
		_box(pivot, Vector3(0.18, 0.18, 0.02), crown + Vector3(-0.32 + k * 0.32, 0.22, 0.0), gold, Vector3(0.0, 0.0, PI * 0.25), false)
	_box(pivot, Vector3(0.22, 0.55, 0.02), off + Vector3(0.0, -2.2, 0.03), gold, Vector3.ZERO, false)
	if torn <= 0.0:
		_box(pivot, Vector3(w, 0.12, 0.04), off + Vector3(0.0, -length, 0.0), gold, Vector3.ZERO, false)
		for k in 5:
			_box(pivot, Vector3(0.2, 0.5, 0.03), off + Vector3(-0.88 + k * 0.44, -length - 0.3, 0.0), cloth, Vector3.ZERO, false)
		return
	# Ribbons of torn cloth, one strip gone, a few curling away from the wall.
	var strips := 5
	for k in strips:
		if k == 1:
			continue
		var l := _rng.randf_range(0.4, 3.4) * torn
		var x := -w * 0.5 + w * (float(k) + 0.5) / strips
		_box(pivot, Vector3(w / strips - 0.04, l, 0.03), off + Vector3(x, -length - l * 0.5, 0.02 * k), cloth,
			Vector3(_rng.randf_range(-0.25, 0.05), 0.0, _rng.randf_range(-0.12, 0.12)), false)


## Bunting pennants strung from a to b with `sag`; `lost` is the chance a
## pennant has been torn away.
func _bunting_line(parent: Node3D, a: Vector3, b: Vector3, sag: float, mats: Array, lost: float) -> void:
	var count := int(a.distance_to(b) / 0.75)
	var yaw := atan2(-(b - a).z, (b - a).x)
	var rope := RetroMaterials.flat(Color(0.2, 0.15, 0.09))
	for i in count + 1:
		var t := float(i) / count
		var p := a.lerp(b, t) - Vector3(0.0, sag * 4.0 * t * (1.0 - t), 0.0)
		if i < count:
			var t2 := float(i + 1) / count
			var q := a.lerp(b, t2) - Vector3(0.0, sag * 4.0 * t2 * (1.0 - t2), 0.0)
			ThornfieldProps.beam(parent, p, q, 0.02, 0.02, rope)
		if _rng.randf() < lost or p.y < 0.4:
			continue
		var flag := _box(parent, Vector3(0.3, 0.4, 0.02), p - Vector3(0.0, 0.2, 0.0), mats[i % mats.size()], Vector3(0.0, yaw, _rng.randf_range(-0.2, 0.2)), false)
		flag.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## The victory feast spilling out of the smashed gate: a collapsed trestle
## table with its cloth dragged, toppled tables and benches, burst wine barrels
## and their stains, dropped goblets and plates, dead lanterns, a trampled
## laurel wreath, petals and pennants strewn over the road and the verges.
## Keeps the middle of the road (|x| < 1.6) free of anything solid.
func feast_spill(parent: Node3D) -> void:
	var wood := RetroMaterials.wood()
	var linen := RetroMaterials.linen()
	var wine := MeadowProps.wine_mat()
	var body := StaticBody3D.new()
	body.name = "SpillColliders"
	parent.add_child(body)
	# Collapsed trestle table, one end on the ground, its cloth slid off.
	var table := Node3D.new()
	table.name = "CollapsedTable"
	table.position = Vector3(-4.6, 0.0, 16.0)
	table.rotation.y = 0.25
	parent.add_child(table)
	_box(table, Vector3(1.2, 0.09, 4.2), Vector3(0.0, 0.48, 0.0), wood, Vector3(0.22, 0.0, 0.04), false)
	_box(table, Vector3(1.32, 0.03, 3.0), Vector3(0.1, 0.56, 0.7), linen, Vector3(0.22, 0.0, 0.05), false)
	_box(table, Vector3(1.0, 0.02, 1.6), Vector3(0.9, 0.02, 2.6), linen, Vector3(0.0, 0.5, 0.02), false)
	for sz in [-1.0, 1.0]:
		_box(table, Vector3(0.1, 0.85, 1.0), Vector3(0.0, 0.42 + sz * 0.38, sz * -1.6), wood, Vector3(0.0, 0.0, 0.5 if sz > 0.0 else 0.0), false)
	_shape(body, Vector3(1.4, 1.0, 4.2), Transform3D(Basis(Vector3.UP, 0.25), Vector3(-4.6, 0.5, 16.0)))
	# A long feast table thrown over, legs in the air, one snapped.
	var over := Node3D.new()
	over.name = "OverturnedTable"
	over.position = Vector3(4.0, 0.0, 18.2)
	over.rotation.y = -0.3
	parent.add_child(over)
	_box(over, Vector3(1.25, 0.09, 4.4), Vector3(0.0, 0.1, 0.0), wood, Vector3(0.0, 0.0, 0.03), false)
	for corner in [Vector3(-0.48, 0, -1.95), Vector3(0.48, 0, -1.95), Vector3(-0.48, 0, 1.95), Vector3(0.48, 0, 1.95)]:
		var leg := 0.34 if corner.x > 0.0 and corner.z > 0.0 else 0.82
		_box(over, Vector3(0.11, leg, 0.11), corner + Vector3(0.0, 0.15 + leg * 0.5, 0.0), wood, Vector3(_rng.randf_range(-0.06, 0.06), 0.0, _rng.randf_range(-0.06, 0.06)), false)
	_box(over, Vector3(0.08, 0.08, 3.8), Vector3(0.0, 0.62, 0.0), wood, Vector3.ZERO, false)
	_box(over, Vector3(0.7, 0.02, 1.6), Vector3(-0.95, 0.03, -0.6), linen, Vector3(0.0, 0.3, 0.0), false)
	_box(over, Vector3(0.04, 0.5, 1.4), Vector3(-0.65, 0.3, -0.6), linen, Vector3(0.0, 0.0, -0.35), false)
	_shape(body, Vector3(1.3, 1.0, 4.4), Transform3D(Basis(Vector3.UP, -0.3), Vector3(4.0, 0.5, 18.2)))
	# Kit furniture: toppled table, benches and stools, barrels, crates.
	var items := [
		["WoodenTable_01", Vector3(4.8, 0.33, 22.4), Vector3(PI * 0.5, 1.1, 0.0), 1.2, Vector3(1.9, 0.8, 0.7)],
		["painted_wooden_bench", Vector3(5.6, 0.25, 15.2), Vector3(0.0, 0.6, PI * 0.5), 1.0, Vector3(1.2, 0.6, 0.6)],
		["painted_wooden_bench", Vector3(-6.8, 0.0, 20.6), Vector3(0.0, -0.4, 0.0), 1.0, Vector3(1.2, 0.9, 0.5)],
		["wooden_stool_01", Vector3(-2.6, 0.22, 18.6), Vector3(0.0, 0.3, PI * 0.5), 1.0, Vector3.ZERO],
		["wooden_stool_01", Vector3(2.9, 0.0, 13.4), Vector3(0.0, 1.0, 0.0), 1.0, Vector3.ZERO],
		["wine_barrel_01", Vector3(3.5, 0.38, 14.3), Vector3(0.0, 0.4, PI * 0.5), 1.0, Vector3(0.9, 0.8, 0.8)],
		["Barrel_01", Vector3(6.6, 0.0, 13.4), Vector3(0.0, 0.0, 0.0), 1.1, Vector3(0.7, 1.0, 0.7)],
		["Barrel_01", Vector3(-6.4, 0.3, 22.4), Vector3(0.0, 2.0, PI * 0.5), 1.0, Vector3(0.9, 0.7, 0.7)],
		["wooden_crate_02", Vector3(-6.9, 0.0, 14.0), Vector3(0.0, 0.3, 0.0), 1.0, Vector3(0.6, 0.5, 1.2)],
		["wooden_crate_01", Vector3(7.4, 0.45, 14.2), Vector3(0.2, 0.9, 0.3), 1.0, Vector3.ZERO],
	]
	for it in items:
		var node := AssetKit.place(parent, str(it[0]), it[1], 0.0, float(it[3]))
		node.rotation = it[2]
		var size: Vector3 = it[4]
		if size != Vector3.ZERO:
			_shape(body, size, Transform3D(Basis(Vector3.UP, (it[2] as Vector3).y), (it[1] as Vector3) + Vector3(0.0, size.y * 0.5 - 0.1, 0.0)))
	# Staves of a burst barrel; wine soaked into the road and the verges.
	for k in 7:
		var a := _rng.randf() * TAU
		var p := Vector3(-5.6, 0.04, 22.0) + Vector3(cos(a), 0.0, sin(a)) * _rng.randf_range(0.4, 1.5)
		_box(parent, Vector3(0.1, 0.03, 0.82), p, wood, Vector3(0.0, _rng.randf() * TAU, _rng.randf_range(-0.2, 0.2)), false)
	for w in [[Vector3(3.0, 0.03, 15.0), 2.2, 2.0], [Vector3(-5.7, 0.03, 21.6), 1.8, 1.4], [Vector3(1.2, 0.032, 16.6), 1.0, 3.0],
			[Vector3(-3.2, 0.031, 17.4), 1.4, 1.2], [Vector3(6.2, 0.03, 13.9), 1.0, 1.0]]:
		var mi := _splat(parent, wine, w[0], float(w[1]))
		mi.scale = Vector3(1.0, 1.0, float(w[2]))
	# Goblets, pewter plates (some snapped), bread gone green.
	var goblets := [Vector3(1.9, 0.05, 16.2), Vector3(-2.2, 0.05, 19.8), Vector3(0.9, 0.05, 21.0), Vector3(-1.2, 0.05, 13.8)]
	for k in goblets.size():
		var g := AssetKit.place(parent, "brass_goblets", goblets[k], 0.0, 1.0, ["brass_goblet_01", "brass_goblet_02", "brass_goblet_03"][k % 3])
		g.rotation = Vector3(0.0, _rng.randf() * TAU, PI * 0.5)
	var pewter := RetroMaterials.flat(Color(0.35, 0.35, 0.34))
	for k in 8:
		var p := Vector3(_rng.randf_range(-5.0, 5.0), 0.02, _rng.randf_range(12.6, 21.0))
		var plate := _cylinder(parent, 0.15, 0.13, 0.02, p, pewter, Vector3(_rng.randf_range(-0.2, 0.2), 0.0, _rng.randf_range(-0.2, 0.2)), false, 8)
		if k % 3 == 0:
			plate.scale = Vector3(1.0, 1.0, 0.5)
	var rot := RetroMaterials.flat(Color(0.2, 0.22, 0.1))
	for o in [[Vector3(-1.9, 0.034, 17.4), 1.8], [Vector3(0.9, 0.034, 18.6), 1.3], [Vector3(-3.6, 0.036, 15.2), 1.2]]:
		var pool := _splat(parent, _ooze_mat, o[0], float(o[1]))
		pool.scale = Vector3(1.0, 1.0, 0.7)
	for k in 5:
		var p := Vector3(_rng.randf_range(-6.0, 6.0), 0.06, _rng.randf_range(13.0, 20.0))
		PartBuilder.sphere(parent, _rng.randf_range(0.05, 0.12), p, rot, false, 5)
		_splat(parent, _ooze_mat, p + Vector3(0.0, -0.03, 0.0), 0.5)
	# Dead lanterns: one pole still standing dark by the gate, one felled, two dropped.
	_dead_lantern(parent, Vector3(-2.9, 0.0, 13.6), 0.0)
	_dead_lantern(parent, Vector3(4.2, 0.12, 18.2), -1.45)
	AssetKit.place(parent, "Lantern_01", Vector3(-1.8, 0.06, 21.6), 0.0, 1.3).rotation = Vector3(0.0, 0.7, PI * 0.5)
	AssetKit.place(parent, "wooden_lantern_01", Vector3(2.6, 0.12, 24.6), 0.0, 1.0).rotation = Vector3(0.0, -0.4, PI * 0.5)
	# A trampled laurel wreath in the road.
	var wreath := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.24
	torus.outer_radius = 0.36
	torus.rings = 10
	torus.ring_segments = 3
	wreath.mesh = torus
	wreath.material_override = RetroMaterials.moss()
	wreath.position = Vector3(0.7, 0.03, 15.2)
	wreath.scale = Vector3(1.0, 0.35, 1.0)
	parent.add_child(wreath)
	# Petals and pennants strewn from the gate down the road (one litter mesh).
	var litter: Array = []
	for k in 600:
		var z := 12.4 + pow(_rng.randf(), 1.6) * 16.0
		var x := _rng.randf_range(-7.5, 7.5) * (1.0 - (z - 12.4) / 24.0)
		var size := _rng.randf_range(0.06, 0.11)
		litter.append([Vector3(x, 0.035 + _rng.randf() * 0.02, z), Vector2(size, size * 0.8), MeadowProps.petal_color(_rng), _rng.randf() * TAU, _rng.randf_range(-0.3, 0.3)])
	var flag_cols := [Color(0.32, 0.04, 0.04), Color(0.55, 0.45, 0.16), Color(0.4, 0.37, 0.3)]
	for k in 26:
		var t := _rng.randf()
		var p := Vector3(-7.5, 0.0, 13.0).lerp(Vector3(-9.5, 0.0, 19.0), t) + Vector3(_rng.randf_range(-1.4, 1.4), 0.04, _rng.randf_range(-1.0, 1.0))
		if k > 18:
			p = Vector3(_rng.randf_range(-5.0, 6.0), 0.04, _rng.randf_range(13.0, 24.0))
		litter.append([p, Vector2(0.3, 0.38), flag_cols[k % 3].darkened(_rng.randf_range(0.0, 0.3)), _rng.randf() * TAU, _rng.randf_range(-0.15, 0.15)])
	MeadowProps.litter(parent, litter, 60.0)


func _dead_lantern(parent: Node3D, base: Vector3, fall: float) -> void:
	var pivot := Node3D.new()
	pivot.name = "DeadLantern"
	pivot.position = base
	pivot.rotation = Vector3(0.0, 0.5, fall)
	parent.add_child(pivot)
	var iron := RetroMaterials.iron()
	PartBuilder.cylinder(pivot, 0.05, 0.07, 2.6, Vector3(0.0, 1.3, 0.0), RetroMaterials.wood(), 6)
	_box(pivot, Vector3(0.6, 0.06, 0.06), Vector3(0.28, 2.55, 0.0), iron, Vector3.ZERO, false)
	_box(pivot, Vector3(0.24, 0.32, 0.24), Vector3(0.52, 2.3, 0.0), iron, Vector3(0.0, 0.0, 0.3 if fall == 0.0 else 0.0), false)
	_box(pivot, Vector3(0.14, 0.2, 0.26), Vector3(0.52, 2.3, 0.0), MeadowProps.dead_glass(), Vector3(0.0, 0.0, 0.3 if fall == 0.0 else 0.0), false)


func _shape(body: StaticBody3D, size: Vector3, xf: Transform3D) -> void:
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.transform = xf
	body.add_child(cs)


# --- Primitive helpers (same contract as OuterWardBlockout's) ------------------

func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO, collide: bool = true) -> MeshInstance3D:
	var mi := PartBuilder.box(parent, size, pos, mat, rot)
	if collide:
		var shape := BoxShape3D.new()
		shape.size = size
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		mi.add_child(body)
	return mi


func _cylinder(parent: Node3D, top_radius: float, bottom_radius: float, height: float, pos: Vector3, mat: Material,
		rot: Vector3 = Vector3.ZERO, _collide: bool = false, segments: int = 8) -> MeshInstance3D:
	return PartBuilder.cylinder(parent, top_radius, bottom_radius, height, pos, mat, segments, rot)


func _splat(parent: Node3D, mat: ShaderMaterial, pos: Vector3, size: float, vertical: bool = false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(size, size)
	if vertical:
		plane.orientation = PlaneMesh.FACE_Z
	mi.mesh = plane
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos
	mi.rotation.y = 0.0 if vertical else _rng.randf() * TAU
	parent.add_child(mi)
	mi.set_meta(MeshMerger.SEED_META, _rng.randf())
	return mi
