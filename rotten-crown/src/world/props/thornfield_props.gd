@tool
class_name ThornfieldProps
extends RefCounted
## Region props of Thornfield (reference 1, task U7): the two-storey farmhouse,
## the collapsed barn, the great dead tree, the well, the dead garden and other
## yard pieces (field pieces: ThornfieldFieldProps). Built like PropKit: primitive meshes (PartBuilder)
## with shared RetroMaterials, origin on the ground, explicit RNG, colliders
## never under scaled nodes. Local front of a prop is +Z.

const OOZE_SHADER := preload("res://assets/shaders/ooze.gdshader")
## Clapboard row height.
const ROW := 0.2

static var _mats: Dictionary = {}


# --------------------------------------------------------------------------
# Materials (own, cached; everything else reuses RetroMaterials)
# --------------------------------------------------------------------------
static func void_mat() -> StandardMaterial3D:
	return RetroMaterials.flat(Color(0.018, 0.016, 0.014))


static func bone_mat() -> StandardMaterial3D:
	return RetroMaterials.flat(Color(0.6, 0.56, 0.47))


static func crow_mat() -> StandardMaterial3D:
	return RetroMaterials.flat(Color(0.03, 0.03, 0.036))


static func glass_mat() -> StandardMaterial3D:
	return RetroMaterials.flat(Color(0.32, 0.36, 0.38))


static func rope_mat() -> StandardMaterial3D:
	return RetroMaterials.flat(Color(0.2, 0.15, 0.09))


static func lit_pane_mat() -> StandardMaterial3D:
	return RetroMaterials.flat(Color(0.8, 0.72, 0.34), 1.8)


## Clapboard whose paint has weathered to grey (mixed in with the pale boards).
static func weathered_board() -> StandardMaterial3D:
	if not _mats.has("weathered"):
		var mat := RetroMaterials.clapboard().duplicate() as StandardMaterial3D
		mat.albedo_color = Color(0.5, 0.5, 0.47)
		mat.set_meta("swatch", mat.albedo_color)
		_mats["weathered"] = mat
	return _mats["weathered"]


static func blood_mat() -> ShaderMaterial:
	if not _mats.has("blood"):
		var mat := ShaderMaterial.new()
		mat.shader = OOZE_SHADER
		mat.set_shader_parameter("surface_color", Color(0.24, 0.02, 0.02))
		mat.set_shader_parameter("deep_color", Color(0.08, 0.0, 0.01))
		mat.set_shader_parameter("emission_strength", 0.0)
		mat.set_shader_parameter("bubble_amount", 0.0)
		mat.set_shader_parameter("roughness_value", 0.35)
		_mats["blood"] = mat
	return _mats["blood"]


## Rain-filled mud puddles: the ooze splat shader, glossy and dark.
static func puddle_mat() -> ShaderMaterial:
	if not _mats.has("puddle"):
		var mat := ShaderMaterial.new()
		mat.shader = OOZE_SHADER
		mat.set_shader_parameter("surface_color", Color(0.09, 0.09, 0.08))
		mat.set_shader_parameter("deep_color", Color(0.03, 0.032, 0.03))
		mat.set_shader_parameter("emission_strength", 0.0)
		mat.set_shader_parameter("bubble_amount", 0.0)
		mat.set_shader_parameter("roughness_value", 0.04)
		mat.set_shader_parameter("pixel_size", 20.0)
		_mats["puddle"] = mat
	return _mats["puddle"]


# --------------------------------------------------------------------------
# Farmhouse
# --------------------------------------------------------------------------
## Weathered two-storey clapboard farmhouse. Gables face +-Z (the front gable,
## +Z, looks down the farm track), the porch with the door runs along +X, a
## collapsed lean-to hangs off -X, the chimney climbs the back gable.
## Meta "door" (local Vector3) marks the doorway on the porch.
static func farmhouse(rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	root.name = "Farmhouse"
	var w := 5.6
	var d := 7.6
	var wh := 5.0
	var roof_h := 2.9
	var t := 0.22
	var floor_y := 0.5
	var core := RetroMaterials.wood()
	var body := new_body(root)
	# Stone footing and the floor the player walks on.
	PartBuilder.box(root, Vector3(w + 0.14, 0.62, d + 0.14), Vector3(0, 0.19, 0), RetroMaterials.stone())
	add_box(body, Vector3(w, 0.2, d), Vector3(0, floor_y - 0.1, 0))
	# Wall cores (+ colliders); the porch side is split around the door.
	var door_z := 0.3
	var door_w := 1.05
	var door_h := 2.15
	for zs: float in [1.0, -1.0]:
		add_solid(root, body, Vector3(w, wh, t), Vector3(0, wh * 0.5, zs * (d * 0.5 - t * 0.5)), core)
	add_solid(root, body, Vector3(t, wh, d), Vector3(-w * 0.5 + t * 0.5, wh * 0.5, 0), core)
	var za := door_z - door_w * 0.5
	var zb := door_z + door_w * 0.5
	add_solid(root, body, Vector3(t, wh, za + d * 0.5), Vector3(w * 0.5 - t * 0.5, wh * 0.5, (za - d * 0.5) * 0.5), core)
	add_solid(root, body, Vector3(t, wh, d * 0.5 - zb), Vector3(w * 0.5 - t * 0.5, wh * 0.5, (zb + d * 0.5) * 0.5), core)
	PartBuilder.box(root, Vector3(t, wh - floor_y - door_h, door_w), Vector3(w * 0.5 - t * 0.5, (wh + floor_y + door_h) * 0.5, door_z), core)
	PartBuilder.box(root, Vector3(w - 0.4, 0.05, d - 0.4), Vector3(0, floor_y, 0), core)
	# Floor between the storeys, seen through the broken windows.
	PartBuilder.box(root, Vector3(w - 0.4, 0.12, d - 0.4), Vector3(0, 2.75, 0), core)
	# Clapboard skin (gable rows continue up into the triangle).
	var fronts := [[Vector3(0, 0, d * 0.5), Vector3.RIGHT], [Vector3(0, 0, -d * 0.5), Vector3.LEFT]]
	for f in fronts:
		_clapboards(root, f[0], f[1], w, 0.42, wh + roof_h, rng, wh, roof_h, Vector2.ZERO)
	_clapboards(root, Vector3(-w * 0.5, 0, 0), Vector3.BACK, d, 0.42, wh, rng, 0.0, 0.0, Vector2.ZERO)
	_clapboards(root, Vector3(w * 0.5, 0, 0), Vector3.FORWARD, d, 0.42, wh, rng, 0.0, 0.0, Vector2(-door_z - door_w * 0.5, -door_z + door_w * 0.5))
	# Gable cores (rows narrowing to the ridge).
	var rows := int(roof_h / ROW)
	for zs: float in [1.0, -1.0]:
		for i in rows:
			var y := wh + ROW * (i + 0.5)
			var gw := w * (1.0 - (y - wh) / roof_h)
			if gw > 0.15:
				PartBuilder.box(root, Vector3(gw, ROW, t), Vector3(0, y, zs * (d * 0.5 - t * 0.5)), core)
	# Corner boards and the plinth trim.
	var trim := RetroMaterials.clapboard()
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			PartBuilder.box(root, Vector3(0.16, wh, 0.16), Vector3(sx * (w * 0.5 + 0.03), wh * 0.5, sz * (d * 0.5 + 0.03)), trim)
	_windows(root, w, d, wh, door_z, rng)
	_door(root, Vector3(w * 0.5 + 0.02, floor_y, door_z), door_w, door_h, rng)
	_roof(root, w, d, wh, roof_h, rng)
	_chimney(root, body, w, d, wh, roof_h)
	_porch(root, body, w, d, floor_y, door_z, rng)
	_lean_to(root, w, rng)
	root.set_meta("door", Vector3(w * 0.5 + 0.3, floor_y, door_z))
	return root


## Horizontal clapboards on the wall plane through `origin` (outward normal =
## axis x up), from y0 to y1. gable_y/gable_h narrow the rows into a gable;
## skip (along-axis interval, centred offsets) leaves the doorway clear.
static func _clapboards(parent: Node3D, origin: Vector3, axis: Vector3, length: float, y0: float, y1: float,
		rng: RandomNumberGenerator, gable_y: float, gable_h: float, skip: Vector2) -> void:
	var normal := axis.cross(Vector3.UP)
	var basis := Basis(axis, Vector3.UP, normal) * Basis(Vector3.RIGHT, -0.12)
	var pale := RetroMaterials.clapboard()
	var grey := weathered_board()
	var y := y0
	while y < y1 - 0.05:
		var row_len := length
		if gable_h > 0.0 and y > gable_y:
			row_len = length * (1.0 - (y + ROW * 0.5 - gable_y) / gable_h) + 0.12
			if row_len < 0.25:
				break
		var a := -row_len * 0.5
		while a < row_len * 0.5 - 0.05:
			var piece := minf(rng.randf_range(1.6, 3.2), row_len * 0.5 - a)
			var mid := a + piece * 0.5
			var clear := skip == Vector2.ZERO or mid + piece * 0.5 < skip.x or mid - piece * 0.5 > skip.y or y > 2.65
			if not clear and y <= 2.65:
				# Split around the doorway.
				_board_piece(parent, origin, axis, normal, basis, a, minf(a + piece, skip.x), y, pale, grey, rng)
				_board_piece(parent, origin, axis, normal, basis, maxf(a, skip.y), a + piece, y, pale, grey, rng)
			elif rng.randf() > 0.035:
				_board_piece(parent, origin, axis, normal, basis, a, a + piece, y, pale, grey, rng)
			a += piece
		y += ROW


static func _board_piece(parent: Node3D, origin: Vector3, axis: Vector3, normal: Vector3, basis: Basis, a: float, b: float, y: float,
		pale: Material, grey: Material, rng: RandomNumberGenerator) -> void:
	if b - a < 0.08:
		return
	var mat := grey if rng.randf() < 0.3 else pale
	var mi := PartBuilder.box(parent, Vector3(b - a, ROW * 1.1, 0.035), Vector3.ZERO, mat)
	var xf := Transform3D(basis, origin + axis * (a + b) * 0.5 + normal * 0.03 + Vector3.UP * (y + ROW * 0.5))
	if rng.randf() < 0.04:
		# A loose board hanging off one nail.
		xf = xf.rotated_local(Vector3.BACK, rng.randf_range(-0.25, 0.25))
		xf.origin.y -= 0.06
	mi.transform = xf


static func _windows(root: Node3D, w: float, d: float, wh: float, door_z: float, rng: RandomNumberGenerator) -> void:
	var front := Basis.IDENTITY
	var back := Basis(Vector3.UP, PI)
	var porch := Basis(Vector3.UP, PI * 0.5)
	var west := Basis(Vector3.UP, -PI * 0.5)
	var fz := d * 0.5 + 0.08
	var px := w * 0.5 + 0.08
	# Front gable: boarded and broken below, the lit one and a shuttered one above, a vent in the apex.
	_window(root, Transform3D(front, Vector3(-1.35, 1.75, fz)), "boarded", rng)
	_window(root, Transform3D(front, Vector3(1.35, 1.75, fz)), "broken", rng)
	_window(root, Transform3D(front, Vector3(-1.3, 3.95, fz)), "shutter", rng)
	_window(root, Transform3D(front, Vector3(1.3, 3.95, fz)), "lit", rng)
	_window(root, Transform3D(front, Vector3(0.0, wh + 1.05, fz)), "vent", rng)
	_window(root, Transform3D(back, Vector3(1.2, 3.95, -fz)), "broken", rng)
	_window(root, Transform3D(back, Vector3(-1.4, 1.75, -fz)), "dark", rng)
	_window(root, Transform3D(porch, Vector3(px, 1.75, door_z - 2.0)), "shutter", rng)
	_window(root, Transform3D(porch, Vector3(px, 1.75, door_z + 2.1)), "broken", rng)
	_window(root, Transform3D(porch, Vector3(px, 3.95, -1.7)), "dark", rng)
	_window(root, Transform3D(porch, Vector3(px, 3.95, 1.9)), "boarded", rng)
	_window(root, Transform3D(west, Vector3(-px, 3.95, 0.4)), "broken", rng)
	_window(root, Transform3D(west, Vector3(-px, 3.95, -2.4)), "dark", rng)


## A window on the wall at xf (local +Z = out of the wall).
static func _window(parent: Node3D, xf: Transform3D, kind: String, rng: RandomNumberGenerator) -> void:
	var win := Node3D.new()
	win.name = "Window"
	win.transform = xf
	parent.add_child(win)
	var trim := RetroMaterials.clapboard()
	var wood := RetroMaterials.wood()
	var hw := 0.36
	var hh := 0.52
	if kind == "vent":
		hw = 0.26
		hh = 0.3
	var pane := lit_pane_mat() if kind == "lit" else void_mat()
	PartBuilder.box(win, Vector3(hw * 2.0, hh * 2.0, 0.02), Vector3(0, 0, -0.02), pane)
	for sy: float in [-1.0, 1.0]:
		PartBuilder.box(win, Vector3(hw * 2.0 + 0.16, 0.08, 0.07), Vector3(0, sy * (hh + 0.04), 0.0), trim)
	for sx: float in [-1.0, 1.0]:
		PartBuilder.box(win, Vector3(0.08, hh * 2.0 + 0.08, 0.07), Vector3(sx * (hw + 0.04), 0, 0.0), trim)
	PartBuilder.box(win, Vector3(hw * 2.0 + 0.26, 0.06, 0.16), Vector3(0, -hh - 0.1, 0.04), trim, Vector3(0.12, 0, rng.randf_range(-0.05, 0.05)))
	match kind:
		"vent":
			for i in 4:
				PartBuilder.box(win, Vector3(hw * 2.0, 0.05, 0.03), Vector3(0, -hh + 0.12 + i * 0.15, 0.01), wood, Vector3(-0.5, 0, 0))
		"lit":
			# Somebody stands in the lit window and does not move.
			var shadow := void_mat()
			var head := PartBuilder.sphere(win, 0.11, Vector3(0.06, 0.1, -0.005), shadow, false, 6)
			head.scale = Vector3(0.85, 1.15, 0.15)
			PartBuilder.box(win, Vector3(0.42, 0.34, 0.01), Vector3(0.04, -0.2, -0.005), shadow, Vector3(0, 0, 0.08))
			PartBuilder.box(win, Vector3(0.05, hh * 2.0, 0.04), Vector3(0, 0, 0.01), trim)
			PartBuilder.box(win, Vector3(hw * 2.0, 0.05, 0.04), Vector3(0, 0.05, 0.01), trim)
		"broken":
			var glass := glass_mat()
			for i in rng.randi_range(3, 4):
				var cx := (1.0 if i % 2 == 0 else -1.0) * hw * 0.72
				var cy := (1.0 if i < 2 else -1.0) * hh * 0.7
				PartBuilder.box(win, Vector3(0.16, 0.3, 0.01), Vector3(cx, cy, -0.008), glass, Vector3(0, 0, rng.randf_range(-0.9, 0.9)))
			PartBuilder.box(win, Vector3(0.05, hh * 2.0, 0.04), Vector3(0, 0, 0.01), trim, Vector3(0, 0, rng.randf_range(-0.12, 0.12)))
		"boarded":
			for i in 3:
				PartBuilder.box(win, Vector3(hw * 2.0 + 0.4, 0.15, 0.04), Vector3(rng.randf_range(-0.05, 0.05), -0.32 + i * 0.32, 0.07), wood,
					Vector3(0, 0, rng.randf_range(-0.35, 0.35)))
		"shutter":
			PartBuilder.box(win, Vector3(0.05, hh * 2.0, 0.04), Vector3(0, 0, 0.01), trim)
			# One shutter still hinged, the other hanging off its lower hinge.
			PartBuilder.box(win, Vector3(hw, hh * 2.0, 0.04), Vector3(-hw * 1.55, 0, 0.03), wood, Vector3(0, 0.15, 0))
			var hang := PartBuilder.pivot(win, "Shutter", Vector3(hw + 0.08, -hh, 0.06))
			hang.rotation = Vector3(0.05, -0.2, rng.randf_range(-0.55, -0.4))
			PartBuilder.box(hang, Vector3(hw, hh * 2.0, 0.04), Vector3(hw * 0.5, hh, 0), wood)


static func _door(root: Node3D, sill: Vector3, door_w: float, door_h: float, rng: RandomNumberGenerator) -> void:
	var trim := RetroMaterials.clapboard()
	var wood := RetroMaterials.wood()
	var voidm := void_mat()
	# Frame boards around the doorway.
	for sz: float in [-1.0, 1.0]:
		PartBuilder.box(root, Vector3(0.12, door_h + 0.1, 0.12), sill + Vector3(0.1, door_h * 0.5, sz * (door_w * 0.5 + 0.06)), trim)
	PartBuilder.box(root, Vector3(0.14, 0.14, door_w + 0.36), sill + Vector3(0.1, door_h + 0.07, 0), trim)
	# Door hanging open on its top hinge, scored by claws.
	var hinge := PartBuilder.pivot(root, "Door", sill + Vector3(0.05, 0, -door_w * 0.5))
	hinge.rotation = Vector3(0.0, 1.05, 0.03)
	var leaf := PartBuilder.box(hinge, Vector3(0.06, door_h - 0.04, door_w - 0.06), Vector3(0, door_h * 0.5, door_w * 0.5), wood)
	leaf.name = "Leaf"
	for i in 4:
		PartBuilder.box(hinge, Vector3(0.02, 0.62, 0.025), Vector3(0.04, 1.2 + i * 0.03, 0.28 + i * 0.11), voidm, Vector3(0.45, 0, 0))
	# Claw marks on the wall beside the doorway, at a height no animal reaches.
	for i in 4:
		PartBuilder.box(root, Vector3(0.02, 0.75 - i * 0.08, 0.025), sill + Vector3(0.07, 1.95 - i * 0.04, door_w * 0.5 + 0.35 + i * 0.1), voidm, Vector3(-0.35 + rng.randf_range(-0.05, 0.05), 0, 0))


static func _roof(root: Node3D, w: float, d: float, wh: float, roof_h: float, rng: RandomNumberGenerator) -> void:
	var roof := RetroMaterials.roof()
	var wood := RetroMaterials.wood()
	var trim := RetroMaterials.clapboard()
	var segs := 6
	var length := d + 0.8
	var seg := length / segs
	var over := 0.45
	var hole := 4
	for side: float in [-1.0, 1.0]:
		for i in segs:
			var zc := -length * 0.5 + seg * (i + 0.5)
			var sag := 0.3 * sin(PI * (i + 0.5) / segs)
			var ridge := Vector3(0, wh + roof_h - sag, zc)
			var eave := Vector3(side * (w * 0.5 + over), wh - 0.28 - sag * 0.6, zc)
			if side > 0.0 and i == hole:
				# Caved-in patch: bare rafters and a few loose boards.
				for k in 3:
					var rz := zc - seg * 0.4 + k * seg * 0.4
					beam(root, Vector3(eave.x, eave.y, rz), Vector3(0, ridge.y, rz), 0.1, 0.08, wood)
				beam(root, eave, eave.lerp(ridge, 0.35), 0.1, seg, roof)
				beam(root, eave.lerp(ridge, 0.55) + Vector3(0, -0.5, 0.2), ridge + Vector3(0, -0.05, -0.1), 0.08, seg * 0.6, roof)
				continue
			var tilt := rng.randf_range(-0.012, 0.012)
			var mi := beam(root, eave, ridge, 0.12, seg + 0.04, roof)
			mi.rotate_object_local(Vector3.RIGHT, tilt)
		# Barge boards along both gables.
		for zs: float in [1.0, -1.0]:
			var z := zs * (length * 0.5 + 0.02)
			beam(root, Vector3(side * (w * 0.5 + over), wh - 0.28, z), Vector3(0, wh + roof_h + 0.04, z), 0.18, 0.06, trim)
	# Ridge cap following the sag.
	for i in segs:
		var z0 := -length * 0.5 + seg * i
		var s0 := 0.3 * sin(PI * float(i) / segs)
		var s1 := 0.3 * sin(PI * float(i + 1) / segs)
		beam(root, Vector3(0, wh + roof_h + 0.06 - s0, z0), Vector3(0, wh + roof_h + 0.06 - s1, z0 + seg), 0.12, 0.2, wood)
	# Eaves fascia.
	for side: float in [-1.0, 1.0]:
		PartBuilder.box(root, Vector3(0.05, 0.2, length), Vector3(side * (w * 0.5 + over + 0.02), wh - 0.36, 0), trim, Vector3(0, 0, 0))


static func _chimney(root: Node3D, body: StaticBody3D, w: float, d: float, wh: float, roof_h: float) -> void:
	var brick := RetroMaterials.brick()
	var h := wh + roof_h + 0.9
	var pos := Vector3(w * 0.2, h * 0.5, -d * 0.5 - 0.4)
	PartBuilder.box(root, Vector3(0.95, h, 0.75), pos, brick, Vector3(0.0, 0.0, 0.015))
	add_box(body, Vector3(0.95, h, 0.75), pos)
	PartBuilder.box(root, Vector3(1.15, 0.16, 0.95), Vector3(pos.x + 0.04, h, pos.z), brick)
	PartBuilder.box(root, Vector3(0.5, 0.06, 0.4), Vector3(pos.x + 0.04, h + 0.09, pos.z), void_mat())
	PartBuilder.box(root, Vector3(1.3, 0.9, 0.95), Vector3(pos.x, 0.45, pos.z), brick)


static func _porch(root: Node3D, body: StaticBody3D, w: float, d: float, floor_y: float, door_z: float, rng: RandomNumberGenerator) -> void:
	var wood := RetroMaterials.wood()
	var roof := RetroMaterials.roof()
	var x0 := w * 0.5 + 0.08
	var depth := 2.2
	var z0 := -d * 0.5 + 0.3
	var z1 := d * 0.5 - 0.3
	# Deck boards running out from the wall, a few missing.
	var z := z0
	while z < z1:
		if rng.randf() > 0.05:
			PartBuilder.box(root, Vector3(depth, 0.05, 0.19), Vector3(x0 + depth * 0.5, floor_y - 0.02, z + 0.1), wood, Vector3(0, rng.randf_range(-0.01, 0.01), rng.randf_range(-0.01, 0.01)))
		z += 0.21
	PartBuilder.box(root, Vector3(depth - 0.1, floor_y - 0.05, z1 - z0 - 0.1), Vector3(x0 + depth * 0.5, (floor_y - 0.05) * 0.5, (z0 + z1) * 0.5), void_mat())
	add_box(body, Vector3(depth, 0.2, z1 - z0), Vector3(x0 + depth * 0.5, floor_y - 0.12, (z0 + z1) * 0.5))
	# Steps down to the yard in front of the door (a ramp collider under them).
	for i in 3:
		var sx := x0 + depth + 0.15 + i * 0.3
		PartBuilder.box(root, Vector3(0.32, 0.06, 1.5), Vector3(sx, floor_y - 0.1 - i * 0.15, door_z), wood, Vector3(0, 0, rng.randf_range(-0.04, 0.04)))
		PartBuilder.box(root, Vector3(0.3, floor_y - 0.1 - i * 0.15, 0.08), Vector3(sx, (floor_y - 0.1 - i * 0.15) * 0.5, door_z + 0.72), wood)
	var ramp := CollisionShape3D.new()
	var ramp_shape := BoxShape3D.new()
	ramp_shape.size = Vector3(1.3, 0.1, 1.5)
	ramp.shape = ramp_shape
	ramp.transform = Transform3D(Basis(Vector3.BACK, -0.42), Vector3(x0 + depth + 0.45, floor_y * 0.5 - 0.06, door_z))
	body.add_child(ramp)
	# Posts; the far one has rotted through and its corner of the roof slumps.
	var post_z: Array[float] = [z0 + 0.1, door_z - 1.0, door_z + 1.0, z1 - 0.1]
	var px := x0 + depth - 0.1
	var top := 2.75
	var drop := [0.0, 0.0, 0.0, 0.5]
	for i in post_z.size():
		var pz: float = post_z[i]
		var dz: float = drop[i]
		if dz > 0.0:
			PartBuilder.box(root, Vector3(0.14, 1.1, 0.14), Vector3(px, floor_y + 0.55, pz), wood, Vector3(0.05, 0, 0.1))
			beam(root, Vector3(px, floor_y + 0.05, pz + 0.3), Vector3(px - 0.6, floor_y + 1.4, pz + 0.7), 0.14, 0.14, wood)
		else:
			PartBuilder.box(root, Vector3(0.14, top - floor_y, 0.14), Vector3(px, (top + floor_y) * 0.5, pz), wood)
	# Porch roof in three slabs, the last one sagging onto the broken post.
	var spans := [[z0 - 0.2, door_z - 1.0, 0.0], [door_z - 1.0, door_z + 1.0, 0.0], [door_z + 1.0, z1 + 0.2, 0.5]]
	for s in spans:
		var za: float = s[0]
		var zb: float = s[1]
		var sag: float = s[2]
		var zc := (za + zb) * 0.5
		var mi := beam(root, Vector3(x0 - 0.05, 3.15, zc), Vector3(x0 + depth + 0.35, top - 0.05 - sag * 0.6, zc), 0.1, zb - za + 0.05, roof)
		if sag > 0.0:
			mi.rotate_object_local(Vector3.RIGHT, -0.12)
	beam(root, Vector3(px, top, z0 - 0.1), Vector3(px, top - 0.35, z1 + 0.1), 0.16, 0.12, wood)
	# Railing on both sides of the steps, half its balusters gone.
	for span in [[z0 + 0.1, door_z - 1.0], [door_z + 1.0, z1 - 0.1]]:
		var ra: float = span[0]
		var rb: float = span[1]
		if rng.randf() < 0.7:
			beam(root, Vector3(px, floor_y + 0.85, ra), Vector3(px, floor_y + 0.85 - rng.randf_range(0.0, 0.25), rb), 0.07, 0.1, wood)
		var bz := ra + 0.2
		while bz < rb - 0.1:
			if rng.randf() < 0.6:
				PartBuilder.box(root, Vector3(0.05, 0.8, 0.05), Vector3(px, floor_y + 0.42, bz), wood, Vector3(rng.randf_range(-0.1, 0.1), 0, 0))
			bz += 0.28


## The collapsed lean-to off the west wall: posts given way, roof slid to the ground.
static func _lean_to(root: Node3D, w: float, rng: RandomNumberGenerator) -> void:
	var wood := RetroMaterials.wood()
	var roof := RetroMaterials.roof()
	var bark := RetroMaterials.bark()
	var x0 := -w * 0.5 - 0.1
	PartBuilder.box(root, Vector3(0.16, 2.6, 0.16), Vector3(x0 - 2.4, 1.3, -2.2), wood, Vector3(0, 0, 0.12))
	beam(root, Vector3(x0 - 2.5, 0.08, 1.6), Vector3(x0 - 1.0, 0.3, 2.7), 0.16, 0.16, wood)
	# Roof: still nailed to the wall at one end, on the ground at the other.
	beam(root, Vector3(x0, 2.9, -1.2), Vector3(x0 - 2.6, 1.6, -1.2), 0.08, 2.4, roof)
	var fallen := beam(root, Vector3(x0, 2.5, 1.3), Vector3(x0 - 2.5, 0.15, 1.5), 0.08, 2.6, roof)
	fallen.rotate_object_local(Vector3.RIGHT, 0.08)
	for i in 4:
		beam(root, Vector3(x0, 2.85, -2.4 + i * 1.6), Vector3(x0 - 2.7, 1.5 - i * 0.35, -2.5 + i * 1.7), 0.08, 0.08, wood)
	# Firewood stacked under what is left of it.
	for row in 3:
		for k in 6:
			var lz := -2.3 + k * 0.32 + (0.16 if row % 2 == 1 else 0.0)
			PartBuilder.cylinder(root, 0.13, 0.14, 1.0, Vector3(x0 - 0.8, 0.14 + row * 0.25, lz), bark, 6, Vector3(0, 0, PI * 0.5 + rng.randf_range(-0.05, 0.05)))


# --------------------------------------------------------------------------
# Collapsed barn
# --------------------------------------------------------------------------
## A plank barn whose ridge broke: one roof side still on its rafters, the other
## slid into the hay, the back wall fallen flat. Door gable faces +Z.
static func collapsed_barn(rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	root.name = "CollapsedBarn"
	var wood := RetroMaterials.wood()
	var grey := weathered_board()
	var roof := RetroMaterials.roof()
	var straw := RetroMaterials.straw()
	var w := 6.0
	var d := 8.0
	var wh := 3.4
	var rh := 2.6
	var body := new_body(root)
	# Corner and mid posts.
	for sx: float in [-1.0, 1.0]:
		for z: float in [-d * 0.5, 0.0, d * 0.5]:
			PartBuilder.box(root, Vector3(0.22, wh, 0.22), Vector3(sx * w * 0.5, wh * 0.5, z), wood, Vector3(rng.randf_range(-0.03, 0.03), 0, rng.randf_range(-0.03, 0.03)))
	# Vertical plank walls: sides and the front gable (with the big doorway).
	for sx: float in [-1.0, 1.0]:
		var z := -d * 0.5
		while z < d * 0.5:
			var h := wh - (rng.randf_range(0.0, 1.4) if sx > 0.0 and z < 0.0 else rng.randf_range(0.0, 0.15))
			if rng.randf() > 0.12:
				PartBuilder.box(root, Vector3(0.05, h, 0.24), Vector3(sx * (w * 0.5 + 0.04), h * 0.5, z + 0.12), grey if rng.randf() < 0.4 else wood)
			z += 0.25
		add_box(body, Vector3(0.2, wh, d), Vector3(sx * w * 0.5, wh * 0.5, 0))
	var x := -w * 0.5
	while x < w * 0.5:
		var in_door := absf(x + 0.12) < 1.4
		var top := wh + rh * (1.0 - absf(x + 0.12) / (w * 0.5))
		var bottom := 2.6 if in_door else 0.0
		if rng.randf() > 0.1 and top - bottom > 0.2:
			PartBuilder.box(root, Vector3(0.24, top - bottom, 0.05), Vector3(x + 0.12, (top + bottom) * 0.5, d * 0.5 + 0.04), grey if rng.randf() < 0.4 else wood)
		x += 0.25
	PartBuilder.box(root, Vector3(w - 0.3, 2.6, 0.04), Vector3(0, 1.3, d * 0.5 - 0.6), void_mat())
	# One barn door hangs open, the other lies in the mud.
	var hinge := PartBuilder.pivot(root, "BarnDoor", Vector3(-1.4, 0, d * 0.5 + 0.08))
	hinge.rotation.y = -1.9
	PartBuilder.box(hinge, Vector3(1.4, 2.5, 0.07), Vector3(0.7, 1.27, 0), wood, Vector3(0, 0, 0.04))
	PartBuilder.box(root, Vector3(1.4, 0.07, 2.5), Vector3(1.6, 0.06, d * 0.5 + 1.6), wood, Vector3(0, 0.3, 0.06))
	# Back wall fallen outwards, planks splayed.
	for i in 22:
		var px := -w * 0.5 + 0.14 + i * 0.27
		var plank := PartBuilder.box(root, Vector3(0.24, 0.05, rng.randf_range(2.0, 3.3)), Vector3(px, 0.06 + rng.randf() * 0.04, -d * 0.5 - 1.6), grey if i % 3 == 0 else wood)
		plank.rotation = Vector3(rng.randf_range(-0.05, 0.15), rng.randf_range(-0.12, 0.12), 0)
	# Roof: west side intact on rafters, the ridge snapped in the middle.
	var ridge_y := wh + rh
	beam(root, Vector3(0, ridge_y, d * 0.5 + 0.2), Vector3(0, ridge_y - 1.1, -0.3), 0.18, 0.18, wood)
	beam(root, Vector3(0, ridge_y - 1.2, -0.2), Vector3(0, ridge_y - 0.2, -d * 0.5 - 0.2), 0.18, 0.18, wood)
	for i in 6:
		var rz := -d * 0.5 + i * (d / 5.0)
		var sag := 1.1 * (1.0 - absf(rz + 0.25) / (d * 0.5))
		beam(root, Vector3(-w * 0.5 - 0.3, wh - 0.2, rz), Vector3(0, ridge_y - sag, rz), 0.12, 0.1, wood)
		if i % 2 == 0:
			beam(root, Vector3(w * 0.5 + 0.3, wh - 0.2, rz), Vector3(0.1, ridge_y - sag - 0.1, rz), 0.12, 0.1, wood)
	beam(root, Vector3(-w * 0.5 - 0.4, wh - 0.25, d * 0.25), Vector3(-0.05, ridge_y - 0.25, d * 0.25), 0.1, d * 0.5 + 0.5, roof)
	var west_back := beam(root, Vector3(-w * 0.5 - 0.4, wh - 0.25, -d * 0.25), Vector3(-0.05, ridge_y - 0.95, -d * 0.25), 0.1, d * 0.5, roof)
	west_back.rotate_object_local(Vector3.RIGHT, 0.08)
	# East side slid down inside, onto the hay.
	beam(root, Vector3(0.3, ridge_y - 0.6, 1.2), Vector3(w * 0.5 - 0.3, 0.5, 1.6), 0.1, 3.6, roof)
	beam(root, Vector3(0.6, 2.2, -2.2), Vector3(w * 0.5 + 0.6, 0.2, -2.6), 0.1, 3.0, roof)
	for i in 5:
		var hay := PartBuilder.sphere(root, rng.randf_range(0.7, 1.1), Vector3(rng.randf_range(-2.0, 1.5), 0.1, rng.randf_range(-3.0, 2.5)), straw, true, 7)
		hay.scale = Vector3(1.3, 0.6, 1.1)
	return root


# --------------------------------------------------------------------------
# Great dead tree
# --------------------------------------------------------------------------
## The huge leafless tree of reference 1: a buttressed trunk forking into three
## gnarled limbs that split down to thin twigs, all shaped by the wind
## (`lean` is the direction the crown leans towards, xz).
static func great_dead_tree(height: float, lean: Vector2, rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	root.name = "GreatDeadTree"
	var bark := RetroMaterials.bark()
	var l := Vector3(lean.x, 0, lean.y).normalized()
	var r0 := height * 0.055
	var trunk_h := height * 0.36
	var p := Vector3.ZERO
	var r := r0 * 1.35
	var segs := 5
	for i in segs:
		var dir := (Vector3.UP + l * 0.12 + Vector3(rng.randf_range(-0.12, 0.12), 0, rng.randf_range(-0.12, 0.12))).normalized()
		var np := p + dir * (trunk_h / segs)
		var nr := r0 * lerpf(1.0, 0.75, float(i + 1) / segs)
		limb(root, p - dir * 0.15, np, r, nr, bark, 8)
		p = np
		r = nr
	# Buttress roots.
	for i in 6:
		var a := TAU * i / 6.0 + rng.randf_range(-0.3, 0.3)
		var out := Vector3(cos(a), 0, sin(a))
		var m := out * r0 * 1.7 + Vector3(0, r0 * 0.5, 0)
		limb(root, out * r0 * 0.3 + Vector3(0, r0 * 2.2, 0), m, r0 * 0.55, r0 * 0.35, bark, 6)
		limb(root, m, out * r0 * rng.randf_range(3.0, 4.2) + Vector3(0, -0.15, 0), r0 * 0.35, r0 * 0.08, bark, 5)
	# Three main limbs from the fork, plus a low dead bough.
	var phase := rng.randf() * TAU
	for i in 3:
		var a := phase + TAU * i / 3.0 + rng.randf_range(-0.35, 0.35)
		var out := Vector3(cos(a), 0, sin(a))
		var dir := (Vector3.UP * 1.2 + out * rng.randf_range(0.55, 0.85) + l * 0.35).normalized()
		_tree_branch(root, p - Vector3(0, 0.3, 0), dir, height * rng.randf_range(0.26, 0.32), r0 * 0.66, 4, rng, bark, l)
	var low_out := Vector3(cos(phase + 1.0), 0, sin(phase + 1.0))
	_tree_branch(root, Vector3(0, trunk_h * 0.55, 0), (low_out + Vector3.UP * 0.35).normalized(), height * 0.24, r0 * 0.4, 3, rng, bark, l)
	var body := new_body(root)
	add_cyl(body, r0, trunk_h, Vector3(0, trunk_h * 0.5, 0))
	root.set_meta("low_bough", Vector3(0, trunk_h * 0.55, 0) + low_out * height * 0.14)
	return root


static func _tree_branch(parent: Node3D, origin: Vector3, dir: Vector3, length: float, radius: float, depth: int,
		rng: RandomNumberGenerator, mat: Material, lean: Vector3) -> void:
	# Each limb kinks once on its way (gnarled), then forks.
	var kink := (dir + Vector3(rng.randf_range(-0.35, 0.35), rng.randf_range(-0.15, 0.2), rng.randf_range(-0.35, 0.35))).normalized()
	var mid := origin + kink * length * 0.5
	var tip := mid + (dir * 1.3 + lean * 0.2).normalized() * length * 0.5
	var sides := 7 if radius > 0.25 else (5 if radius > 0.07 else 3)
	var rm := radius * 0.8
	limb(parent, origin, mid, radius, rm, mat, sides)
	limb(parent, mid - kink * 0.03, tip, rm, radius * 0.62, mat, sides)
	if depth <= 0:
		for i in rng.randi_range(3, 4):
			var td := (dir + Vector3(rng.randf_range(-0.9, 0.9), rng.randf_range(-0.2, 0.6), rng.randf_range(-0.9, 0.9))).normalized()
			limb(parent, tip, tip + td * length * rng.randf_range(0.5, 0.9), radius * 0.5, 0.008, mat, 3)
		return
	var count := 2 if rng.randf() < 0.65 else 3
	for i in count:
		var axis := dir.cross(Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)))
		if axis.length() < 0.01:
			axis = Vector3.RIGHT
		var nd := dir.rotated(axis.normalized(), rng.randf_range(0.35, 0.85))
		nd = (nd + lean * 0.12).normalized()
		var from := tip if i == 0 else mid.lerp(tip, rng.randf_range(0.3, 0.9))
		_tree_branch(parent, from, nd, length * rng.randf_range(0.66, 0.8), radius * 0.6, depth - 1, rng, mat, lean)


# --------------------------------------------------------------------------
# Yard: well, dead garden, clothesline, haystack
# --------------------------------------------------------------------------
static func well(rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	root.name = "Well"
	var stone := RetroMaterials.stone()
	var wood := RetroMaterials.wood()
	var roof := RetroMaterials.roof()
	PartBuilder.cylinder(root, 0.95, 1.02, 0.85, Vector3(0, 0.42, 0), stone, 12)
	PartBuilder.cylinder(root, 1.08, 1.08, 0.12, Vector3(0, 0.88, 0), stone, 12)
	PartBuilder.cylinder(root, 0.78, 0.78, 0.02, Vector3(0, 0.95, 0), void_mat(), 12)
	for sx: float in [-1.0, 1.0]:
		PartBuilder.box(root, Vector3(0.14, 2.3, 0.14), Vector3(sx * 0.98, 1.15, 0), wood, Vector3(0, 0, sx * 0.03))
	PartBuilder.cylinder(root, 0.09, 0.09, 1.9, Vector3(0, 1.65, 0), wood, 6, Vector3(0, 0, PI * 0.5))
	PartBuilder.box(root, Vector3(0.05, 0.3, 0.05), Vector3(1.12, 1.55, 0), RetroMaterials.iron())
	PartBuilder.box(root, Vector3(0.025, 0.75, 0.025), Vector3(0.1, 1.25, 0), rope_mat())
	for sz: float in [-1.0, 1.0]:
		var mi := beam(root, Vector3(0, 2.55, 0), Vector3(0, 1.95, sz * 1.0), 0.06, 2.5, roof)
		mi.rotate_object_local(Vector3.UP, rng.randf_range(-0.03, 0.03))
	# A corn doll hangs from the windlass. Nobody here made toys.
	PartBuilder.box(root, Vector3(0.012, 0.3, 0.012), Vector3(-0.5, 1.45, 0), rope_mat())
	PartBuilder.box(root, Vector3(0.1, 0.24, 0.07), Vector3(-0.5, 1.2, 0), RetroMaterials.straw(), Vector3(0, 0, 0.1))
	PartBuilder.sphere(root, 0.055, Vector3(-0.5, 1.36, 0), RetroMaterials.sack(), false, 5)
	var body := new_body(root)
	add_cyl(body, 1.05, 0.95, Vector3(0, 0.47, 0))
	return root


## Dead kitchen garden: furrows of mud, rotten stalks, drooping dead sunflowers,
## a fallen picket fence round it. Rows run along X over size.
static func dead_garden(size: Vector2, rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	root.name = "DeadGarden"
	var mud := RetroMaterials.mud()
	var straw := RetroMaterials.straw()
	var wood := RetroMaterials.wood()
	var dark := RetroMaterials.flat(Color(0.07, 0.05, 0.03))
	var rows := int(size.y / 0.75)
	for r in rows:
		var z := -size.y * 0.5 + 0.4 + r * 0.75
		PartBuilder.box(root, Vector3(size.x, 0.2, 0.42), Vector3(0, 0.02, z), mud, Vector3(0.0, rng.randf_range(-0.03, 0.03), 0.0))
		var x := -size.x * 0.5 + 0.3
		while x < size.x * 0.5 - 0.2:
			var base := Vector3(x + rng.randf_range(-0.1, 0.1), 0.1, z + rng.randf_range(-0.08, 0.08))
			var roll := rng.randf()
			if roll < 0.22:
				# Dead sunflower: tall stalk bowing its blackened head.
				var h := rng.randf_range(1.3, 2.0)
				var bend := Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(0.1, 0.35))
				var top := base + Vector3(0, h, 0) + bend
				limb(root, base, base + Vector3(0, h * 0.6, 0) + bend * 0.3, 0.025, 0.02, straw, 3)
				limb(root, base + Vector3(0, h * 0.6, 0) + bend * 0.3, top, 0.02, 0.016, straw, 3)
				var head := PartBuilder.cylinder(root, 0.17, 0.14, 0.05, top + bend.normalized() * 0.08 + Vector3(0, -0.12, 0), dark, 8)
				head.rotation = Vector3(1.2 * signf(bend.z), 0, -bend.x * 1.5)
				PartBuilder.box(root, Vector3(0.14, 0.02, 0.05), base + Vector3(0, h * 0.45, 0) + bend * 0.2, straw, Vector3(0.9, rng.randf() * TAU, 0.6))
			elif roll < 0.75:
				var h := rng.randf_range(0.25, 0.6)
				limb(root, base, base + Vector3(rng.randf_range(-0.2, 0.2), h, rng.randf_range(-0.2, 0.2)), 0.02, 0.01, straw, 3)
			elif roll < 0.85:
				var cab := PartBuilder.sphere(root, rng.randf_range(0.12, 0.18), base + Vector3(0, 0.02, 0), dark, false, 6)
				cab.scale = Vector3(1.2, 0.6, 1.1)
			x += rng.randf_range(0.35, 0.55)
	# Picket fence on three sides, sections fallen flat.
	var corners := [Vector2(-size.x * 0.5 - 0.3, -size.y * 0.5 - 0.3), Vector2(size.x * 0.5 + 0.3, -size.y * 0.5 - 0.3),
		Vector2(size.x * 0.5 + 0.3, size.y * 0.5 + 0.3), Vector2(-size.x * 0.5 - 0.3, size.y * 0.5 + 0.3)]
	for side in 3:
		var a: Vector2 = corners[side]
		var b: Vector2 = corners[side + 1]
		var n := int(a.distance_to(b) / 0.22)
		var fallen := rng.randf() < 0.5
		var fall_from := rng.randi_range(0, maxi(n - 8, 0))
		for k in n:
			var q := a.lerp(b, (k + 0.5) / n)
			if fallen and k >= fall_from and k < fall_from + 7:
				PartBuilder.box(root, Vector3(0.08, 0.02, 0.85), Vector3(q.x, 0.05, q.y) + Vector3(0.0, 0.0, 0.0), wood, Vector3(0, atan2(b.x - a.x, b.y - a.y) + PI * 0.5, 0))
			elif rng.randf() > 0.12:
				PartBuilder.box(root, Vector3(0.08, 0.85, 0.025), Vector3(q.x, 0.42, q.y), wood, Vector3(rng.randf_range(-0.12, 0.12), atan2(b.x - a.x, b.y - a.y) + PI * 0.5, rng.randf_range(-0.12, 0.12)))
		if not fallen:
			beam(root, Vector3(a.x, 0.6, a.y), Vector3(b.x, 0.6, b.y), 0.06, 0.03, wood)
	return root


## Clothesline between two T-posts; a sheet and a small dress still hang on it.
static func clothesline(rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	root.name = "Clothesline"
	var wood := RetroMaterials.wood()
	var linen := RetroMaterials.linen()
	for sx: float in [-1.0, 1.0]:
		PartBuilder.box(root, Vector3(0.1, 2.2, 0.1), Vector3(sx * 2.6, 1.1, 0), wood, Vector3(0, 0, sx * 0.04))
		PartBuilder.box(root, Vector3(0.08, 0.08, 0.7), Vector3(sx * 2.6, 2.1, 0), wood)
	PartBuilder.box(root, Vector3(5.2, 0.015, 0.015), Vector3(0, 2.0, 0.25), rope_mat(), Vector3(0, 0, 0.0))
	var sheet := PartBuilder.box(root, Vector3(1.5, 1.55, 0.02), Vector3(-0.9, 1.22, 0.3), linen)
	sheet.rotation = Vector3(-0.32, 0.05, 0.02)
	PartBuilder.box(root, Vector3(0.3, 0.5, 0.02), Vector3(-0.55, 0.3, 0.42), linen, Vector3(-0.2, 0.0, 0.3))
	PartBuilder.frustum(root, 0.3, 0.55, 0.75, 0.02, Vector3(1.0, 1.6, 0.3), linen, Vector3(-0.25, 0, rng.randf_range(-0.08, 0.08)))
	return root


static func haystack(rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	root.name = "Haystack"
	var straw := RetroMaterials.straw()
	var rot := RetroMaterials.sack()
	var mound := PartBuilder.sphere(root, 1.6, Vector3(0, 0.0, 0), straw, true, 9)
	mound.scale = Vector3(1.0, 1.25, 0.9)
	var crown := PartBuilder.sphere(root, 0.9, Vector3(0.2, 1.4, 0.1), rot, false, 7)
	crown.scale = Vector3(1.0, 0.7, 0.9)
	# Pitchfork left standing in it.
	var fork := PartBuilder.pivot(root, "Fork", Vector3(1.0, 1.0, 0.6))
	fork.rotation = Vector3(0.3, rng.randf() * TAU, -0.5)
	PartBuilder.cylinder(fork, 0.025, 0.025, 1.6, Vector3(0, 0.6, 0), RetroMaterials.wood(), 4)
	for i in 3:
		PartBuilder.box(fork, Vector3(0.015, 0.35, 0.015), Vector3(-0.07 + i * 0.07, -0.35, 0), RetroMaterials.iron())
	var body := new_body(root)
	add_cyl(body, 1.4, 1.6, Vector3(0, 0.8, 0))
	return root


# --------------------------------------------------------------------------
# Shared helpers
# --------------------------------------------------------------------------
## Flat procedural splat (blood, puddles) on the ground at pos; keeps its seed through merging.
static func splat(parent: Node3D, mat: ShaderMaterial, pos: Vector3, size: float, rng: RandomNumberGenerator, stretch := 1.0, yaw := -1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(size, size * stretch)
	mi.mesh = plane
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos
	mi.rotation.y = rng.randf() * TAU if yaw < 0.0 else yaw
	parent.add_child(mi)
	mi.set_meta(MeshMerger.SEED_META, rng.randf())
	return mi


## Cylinder from a to b (radius ra at a, rb at b), caps dropped.
static func limb(parent: Node3D, a: Vector3, b: Vector3, ra: float, rb: float, mat: Material, segments: int = 5) -> MeshInstance3D:
	var v := b - a
	var len := maxf(v.length(), 0.01)
	var mi := PartBuilder.cylinder(parent, rb, ra, len, (a + b) * 0.5, mat, segments)
	var cyl := mi.mesh as CylinderMesh
	cyl.cap_top = false
	cyl.cap_bottom = false
	mi.transform = Transform3D(Basis(Quaternion(Vector3.UP, v / len)), (a + b) * 0.5)
	return mi


## Box from a to b with cross-section (ty, tz); local Y stays roughly up.
static func beam(parent: Node3D, a: Vector3, b: Vector3, ty: float, tz: float, mat: Material) -> MeshInstance3D:
	var v := b - a
	var len := maxf(v.length(), 0.01)
	var x := v / len
	var up := Vector3.UP if absf(x.y) < 0.95 else Vector3.RIGHT
	var z := x.cross(up).normalized()
	var y := z.cross(x)
	var mi := PartBuilder.box(parent, Vector3(len, ty, tz), (a + b) * 0.5, mat)
	mi.transform = Transform3D(Basis(x, y, z), (a + b) * 0.5)
	return mi


static func add_solid(parent: Node3D, body: StaticBody3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	PartBuilder.box(parent, size, pos, mat)
	add_box(body, size, pos)


static func new_body(parent: Node3D) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Collider"
	parent.add_child(body)
	return body


static func add_box(body: StaticBody3D, size: Vector3, pos: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.position = pos
	body.add_child(cs)


static func add_cyl(body: StaticBody3D, radius: float, height: float, pos: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	cs.shape = shape
	cs.position = pos
	body.add_child(cs)
