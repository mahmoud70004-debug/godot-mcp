@tool
class_name OuterWardBlockout
extends Node3D
## Procedural greybox of the Moonlit Meadows and the Outer Ward of Valdron,
## built from primitives with pixel materials. It is the Phase 1 visual test
## bed: walls, the broken gate, abandoned houses, the interrupted feast, the
## well, the smithy stall, lanterns, festival banners, and the green rot.
## Phase 2 replaces it with hand-built modular kit pieces.
##
## Layout (metres, -Z is "into the castle"):
##   z  > 10   Moonlit Meadows - where the knight wakes (spawn ~ z = 30)
##   z  = 10   outer wall and main gate (gap |x| < 3.5)
##   z  < 10   Outer Ward courtyard, enclosed by walls at x = +-40, z = -40
##   z  = -52  silhouette of the Royal Keep beyond the back wall

const OOZE_SHADER := preload("res://assets/shaders/ooze.gdshader")
const WALL_HEIGHT := 7.0
const WALL_THICKNESS := 2.0
const GATE_HALF_WIDTH := 3.5
const WARM_LIGHT := Color(1.0, 0.6, 0.3)
const CURSED_LIGHT := Color(0.55, 1.0, 0.3)

@export var seed := 1337
## Tick in the inspector to rebuild after changing the seed.
@export var rebuild := false:
	set(value):
		if value and is_inside_tree():
			_build()

var _rng := RandomNumberGenerator.new()
var _ooze_mat: ShaderMaterial
var _blood_mat: ShaderMaterial


func _ready() -> void:
	_build()


func _build() -> void:
	for child in get_children():
		remove_child(child)
		child.free()
	_rng.seed = seed
	_make_materials()
	_build_ground()
	_build_walls()
	_build_gate()
	_build_houses()
	_build_feast()
	_build_well()
	_build_smithy()
	_build_lanterns()
	_build_banners()
	_build_meadow()
	_build_keep_silhouette()
	_scatter_rot()


func _make_materials() -> void:
	_ooze_mat = ShaderMaterial.new()
	_ooze_mat.shader = OOZE_SHADER
	_blood_mat = ShaderMaterial.new()
	_blood_mat.shader = OOZE_SHADER
	_blood_mat.set_shader_parameter("surface_color", Color(0.3, 0.02, 0.02))
	_blood_mat.set_shader_parameter("deep_color", Color(0.1, 0.0, 0.01))
	_blood_mat.set_shader_parameter("emission_strength", 0.0)
	_blood_mat.set_shader_parameter("bubble_amount", 0.0)
	_blood_mat.set_shader_parameter("roughness_value", 0.4)


# --- Terrain -----------------------------------------------------------------

func _build_ground() -> void:
	var ground := _group("Ground")
	# Visual tiles: small meshes keep every mesh under the Mobile renderer's
	# per-mesh light limit (8 omni lights).
	for ix in range(-3, 3):
		for iz in range(-3, 3):
			var center := Vector3(ix * 20.0 + 10.0, -0.1, iz * 20.0 + 10.0)
			var inside := center.z < 10.0 and absf(center.x) < 40.0
			var mat := RetroMaterials.mud() if inside else RetroMaterials.dead_grass()
			_box(ground, Vector3(20.0, 0.2, 20.0), center, mat, Vector3.ZERO, false)
	# One collider for the whole floor.
	var body := StaticBody3D.new()
	body.name = "FloorCollider"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(120.0, 1.0, 120.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.0)
	body.add_child(shape)
	ground.add_child(body)
	# Cobbled plaza for the feast and the road through the gate.
	_box(ground, Vector3(16.0, 0.04, 30.0), Vector3(0.0, 0.0, -6.0), RetroMaterials.cobble(), Vector3.ZERO, false)
	_box(ground, Vector3(4.5, 0.04, 50.0), Vector3(0.0, 0.0, 35.0), RetroMaterials.mud(), Vector3.ZERO, false)


func _build_walls() -> void:
	var walls := _group("Walls")
	var stone := RetroMaterials.stone()
	var x_in := GATE_HALF_WIDTH + 3.0
	_wall(walls, Vector3(-40.0, 0.0, 10.0), Vector3(-x_in, 0.0, 10.0), stone, true)
	_wall(walls, Vector3(x_in, 0.0, 10.0), Vector3(40.0, 0.0, 10.0), stone, true)
	_wall(walls, Vector3(-40.0, 0.0, 10.0), Vector3(-40.0, 0.0, -40.0), RetroMaterials.mossy_stone(), false)
	_wall(walls, Vector3(40.0, 0.0, 10.0), Vector3(40.0, 0.0, -40.0), RetroMaterials.mossy_stone(), false)
	_wall(walls, Vector3(-40.0, 0.0, -40.0), Vector3(40.0, 0.0, -40.0), stone, false)
	for corner in [Vector3(-40, 0, 10), Vector3(40, 0, 10), Vector3(-40, 0, -40), Vector3(40, 0, -40)]:
		_round_tower(walls, corner, 2.6, 11.0)


func _wall(parent: Node3D, a: Vector3, b: Vector3, mat: Material, crenellate: bool) -> void:
	var d := b - a
	var length := d.length()
	var center := (a + b) * 0.5 + Vector3(0.0, WALL_HEIGHT * 0.5, 0.0)
	var yaw := atan2(-d.z, d.x)
	var wall := _box(parent, Vector3(length, WALL_HEIGHT, WALL_THICKNESS), center, mat, Vector3(0.0, yaw, 0.0))
	if not crenellate:
		return
	var count := int(length / 2.0)
	for i in count:
		var x := -length * 0.5 + 1.0 + i * 2.0
		_box(wall, Vector3(0.9, 0.9, WALL_THICKNESS), Vector3(x, WALL_HEIGHT * 0.5 + 0.45, 0.0), mat, Vector3.ZERO, false)


func _round_tower(parent: Node3D, base: Vector3, radius: float, height: float) -> void:
	_cylinder(parent, radius, radius * 1.08, height, base + Vector3(0.0, height * 0.5, 0.0), RetroMaterials.stone(), Vector3.ZERO, true, 10)
	_cylinder(parent, 0.0, radius * 1.25, 4.5, base + Vector3(0.0, height + 2.25, 0.0), RetroMaterials.roof(), Vector3.ZERO, false, 10)


# --- Gate --------------------------------------------------------------------

func _build_gate() -> void:
	var gate := _group("Gate")
	var stone := RetroMaterials.stone()
	var iron := RetroMaterials.iron()
	var wood := RetroMaterials.wood()
	for side in [-1.0, 1.0]:
		_box(gate, Vector3(3.0, 10.0, 3.2), Vector3(side * (GATE_HALF_WIDTH + 1.5), 5.0, 10.0), stone)
		_cylinder(gate, 0.0, 2.3, 3.0, Vector3(side * (GATE_HALF_WIDTH + 1.5), 11.5, 10.0), RetroMaterials.roof(), Vector3.ZERO, false, 4)
	_box(gate, Vector3(GATE_HALF_WIDTH * 2.0, 2.6, 2.4), Vector3(0.0, 6.3, 10.0), stone)
	# Portcullis, jammed half-way and missing teeth.
	var x := -GATE_HALF_WIDTH + 0.35
	while x < GATE_HALF_WIDTH:
		if _rng.randf() > 0.2:
			var bar_len := _rng.randf_range(1.0, 1.7)
			_box(gate, Vector3(0.08, bar_len, 0.08), Vector3(x, 5.0 - bar_len * 0.5, 10.0), iron, Vector3(0.0, 0.0, _rng.randf_range(-0.06, 0.06)), false)
		x += 0.5
	_box(gate, Vector3(GATE_HALF_WIDTH * 2.0, 0.1, 0.1), Vector3(0.0, 4.3, 10.0), iron, Vector3.ZERO, false)
	_box(gate, Vector3(0.09, 1.8, 0.09), Vector3(-1.2, 0.08, 7.5), iron, Vector3(PI * 0.5, 0.4, 0.0), false)
	_box(gate, Vector3(0.09, 1.4, 0.09), Vector3(1.6, 0.08, 8.2), iron, Vector3(PI * 0.5, -0.9, 0.0), false)
	# Left door swung inward; right door torn off and lying in the road.
	var hinge := Vector3(-GATE_HALF_WIDTH, 0.0, 8.9)
	var swing := deg_to_rad(80.0)
	var dir := Vector3(cos(swing), 0.0, -sin(swing))
	_box(gate, Vector3(3.3, 4.8, 0.22), hinge + dir * 1.65 + Vector3(0.0, 2.4, 0.0), wood, Vector3(0.0, swing, 0.0))
	_box(gate, Vector3(3.3, 4.6, 0.22), Vector3(2.3, 0.18, 5.8), wood, Vector3(deg_to_rad(-86.0), deg_to_rad(18.0), 0.0), false)


# --- Houses ------------------------------------------------------------------

func _build_houses() -> void:
	var houses := _group("Houses")
	var specs := [
		[Vector3(-18, 0, 0), 90.0, Vector3(7.0, 4.0, 6.0), false, true],
		[Vector3(-19, 0, -13), 90.0, Vector3(6.0, 3.6, 6.5), true, false],
		[Vector3(-18, 0, -27), 90.0, Vector3(8.0, 4.4, 6.0), false, false],
		[Vector3(18, 0, 0), -90.0, Vector3(7.5, 4.2, 6.0), true, true],
		[Vector3(19, 0, -27), -90.0, Vector3(6.5, 3.8, 6.5), false, false],
		[Vector3(-30, 0, -6), 90.0, Vector3(6.0, 3.4, 5.5), true, false],
		[Vector3(30, 0, -12), -90.0, Vector3(6.0, 3.6, 5.5), false, true],
	]
	for i in specs.size():
		var s: Array = specs[i]
		_house(houses, "House%d" % i, s[0], deg_to_rad(s[1]), s[2], s[3], s[4])


## A house whose door is on its local +Z face.
func _house(parent: Node3D, house_name: String, pos: Vector3, yaw: float, size: Vector3, ruined: bool, lit_window: bool) -> void:
	var root := Node3D.new()
	root.name = house_name
	root.position = pos
	root.rotation.y = yaw
	parent.add_child(root)
	var w := size.x
	var h := size.y
	var d := size.z
	var t := 0.4
	var stone := RetroMaterials.mossy_stone() if ruined else RetroMaterials.stone()
	var door_w := 1.6
	var door_h := 2.4
	_box(root, Vector3(w, h, t), Vector3(0.0, h * 0.5, -d * 0.5), stone)
	_box(root, Vector3(t, h, d), Vector3(-w * 0.5, h * 0.5, 0.0), stone)
	_box(root, Vector3(t, h, d), Vector3(w * 0.5, h * 0.5, 0.0), stone)
	var side_w := (w - door_w) * 0.5
	_box(root, Vector3(side_w, h, t), Vector3(-(door_w + side_w) * 0.5, h * 0.5, d * 0.5), stone)
	_box(root, Vector3(side_w, h, t), Vector3((door_w + side_w) * 0.5, h * 0.5, d * 0.5), stone)
	_box(root, Vector3(door_w, h - door_h, t), Vector3(0.0, door_h + (h - door_h) * 0.5, d * 0.5), stone)
	# Windows: black holes, one of them faintly lit from inside.
	var window_mat := RetroMaterials.flat(Color(0.75, 0.9, 0.35), 2.5) if lit_window else RetroMaterials.flat(Color(0.0, 0.0, 0.0))
	_box(root, Vector3(t + 0.04, 0.7, 0.5), Vector3(-w * 0.5, 2.1, -0.8), window_mat, Vector3.ZERO, false)
	_box(root, Vector3(t + 0.04, 0.7, 0.5), Vector3(w * 0.5, 2.1, 0.9), RetroMaterials.flat(Color(0.0, 0.0, 0.0)), Vector3.ZERO, false)
	_box(root, Vector3(0.6, 0.7, t + 0.04), Vector3(side_w * 0.5 + door_w * 0.5, 2.2, d * 0.5), RetroMaterials.flat(Color(0.0, 0.0, 0.0)), Vector3.ZERO, false)
	# Gable roof (ridge along local X), one slab missing on ruined houses.
	var pitch := deg_to_rad(35.0)
	var slab_len := (d * 0.5) / cos(pitch) + 0.4
	var rise := (d * 0.5) * tan(pitch)
	var roof := RetroMaterials.roof()
	_box(root, Vector3(w + 0.6, 0.18, slab_len), Vector3(0.0, h + rise * 0.5, d * 0.25), roof, Vector3(pitch, 0.0, 0.0), false)
	if ruined:
		_box(root, Vector3(w * 0.7, 0.18, slab_len), Vector3(0.6, 0.9, -d * 0.2), roof, Vector3(-0.5, 0.2, 0.35), false)
		for i in 6:
			var rubble := Vector3(_rng.randf_range(-w * 0.4, w * 0.4), 0.15, _rng.randf_range(-d * 0.4, 0.0))
			_box(root, Vector3.ONE * _rng.randf_range(0.2, 0.5), rubble, stone, Vector3(_rng.randf(), _rng.randf(), _rng.randf()), false)
	else:
		_box(root, Vector3(w + 0.6, 0.18, slab_len), Vector3(0.0, h + rise * 0.5, -d * 0.25), roof, Vector3(-pitch, 0.0, 0.0), false)
	# Interior: an overturned chair, a table, and a heap of empty clothes.
	var wood := RetroMaterials.wood()
	_box(root, Vector3(1.4, 0.08, 0.8), Vector3(-w * 0.2, 0.75, -d * 0.2), wood)
	_box(root, Vector3(0.45, 0.9, 0.45), Vector3(w * 0.25, 0.25, -d * 0.1), wood, Vector3(PI * 0.5, 0.3, 0.0), false)
	_clothes_heap(root, Vector3(0.3, 0.0, d * 0.25))


# --- The interrupted feast -----------------------------------------------------

func _build_feast() -> void:
	var feast := _group("Feast")
	var wood := RetroMaterials.wood()
	for side in [-1.0, 1.0]:
		var tx: float = side * 3.2
		_table(feast, Vector3(tx, 0.0, -5.0), 9.0)
		for bench_side in [-1.0, 1.0]:
			var bx: float = tx + bench_side * 1.05
			if _rng.randf() < 0.35:
				_box(feast, Vector3(0.4, 0.45, 4.0), Vector3(bx + bench_side * 0.4, 0.2, -5.0 + _rng.randf_range(-2.0, 2.0)), wood, Vector3(0.0, 0.0, bench_side * 1.4), false)
			else:
				_box(feast, Vector3(0.4, 0.45, 9.0), Vector3(bx, 0.225, -5.0), wood)
	# High table across the end, with the Herald's tall chair knocked back.
	_table(feast, Vector3(0.0, 0.0, -11.5), 8.0, true)
	_box(feast, Vector3(0.8, 2.2, 0.8), Vector3(0.0, 0.5, -13.2), RetroMaterials.valdron_cloth(), Vector3(-1.1, 0.0, 0.0), false)
	# A roast boar, long gone green.
	var roast := _box(feast, Vector3(0.9, 0.45, 0.5), Vector3(-3.2, 1.15, -6.5), RetroMaterials.flat(Color(0.25, 0.14, 0.08)), Vector3(0.0, 0.3, 0.0), false)
	_splat(roast, _ooze_mat, Vector3(0.0, 0.24, 0.0), 0.7)


func _table(parent: Node3D, center: Vector3, length: float, across: bool = false) -> void:
	var size := Vector3(length, 0.1, 1.3) if across else Vector3(1.3, 0.1, length)
	var wood := RetroMaterials.wood()
	_box(parent, size, center + Vector3(0.0, 0.85, 0.0), wood)
	_box(parent, size + Vector3(0.12, -0.08, 0.12), center + Vector3(0.0, 0.91, 0.0), RetroMaterials.linen(), Vector3.ZERO, false)
	var half := size * 0.5 - Vector3(0.15, 0.0, 0.15)
	for corner in [Vector3(-half.x, 0, -half.z), Vector3(half.x, 0, -half.z), Vector3(-half.x, 0, half.z), Vector3(half.x, 0, half.z)]:
		_box(parent, Vector3(0.12, 0.8, 0.12), center + corner + Vector3(0.0, 0.4, 0.0), wood, Vector3.ZERO, false)
	var gold := RetroMaterials.flat(Color(0.5, 0.42, 0.18))
	var pewter := RetroMaterials.flat(Color(0.35, 0.35, 0.34))
	for i in int(length * 1.6):
		var along := _rng.randf_range(-length * 0.45, length * 0.45)
		var off := _rng.randf_range(-0.45, 0.45)
		var p := center + (Vector3(along, 0.0, off) if across else Vector3(off, 0.0, along))
		if _rng.randf() < 0.5:
			var tipped := _rng.randf() < 0.45
			var rot := Vector3(PI * 0.5, _rng.randf() * TAU, 0.0) if tipped else Vector3.ZERO
			_cylinder(parent, 0.045, 0.035, 0.14, p + Vector3(0.0, 1.0 if not tipped else 0.97, 0.0), gold, rot, false, 6)
			if tipped and _rng.randf() < 0.6:
				_splat(parent, _blood_mat, p + Vector3(0.0, 0.952, 0.0), 0.35)
		else:
			_cylinder(parent, 0.15, 0.13, 0.02, p + Vector3(0.0, 0.95, 0.0), pewter, Vector3.ZERO, false, 8)


# --- Well & smithy -------------------------------------------------------------

func _build_well() -> void:
	var well := _group("Well")
	var c := Vector3(-8.0, 0.0, -18.0)
	_cylinder(well, 1.1, 1.15, 0.9, c + Vector3(0.0, 0.45, 0.0), RetroMaterials.stone(), Vector3.ZERO, true, 10)
	_cylinder(well, 0.88, 0.88, 0.02, c + Vector3(0.0, 0.91, 0.0), RetroMaterials.flat(Color(0.0, 0.0, 0.0)), Vector3.ZERO, false, 10)
	_splat(well, _ooze_mat, c + Vector3(0.0, 0.93, 0.0), 1.5)
	var wood := RetroMaterials.wood()
	for side in [-1.0, 1.0]:
		_box(well, Vector3(0.15, 2.4, 0.15), c + Vector3(side * 1.0, 1.2, 0.0), wood)
	_box(well, Vector3(2.3, 0.12, 0.12), c + Vector3(0.0, 2.3, 0.0), wood, Vector3.ZERO, false)
	_box(well, Vector3(2.6, 0.12, 1.5), c + Vector3(0.0, 2.55, 0.35), RetroMaterials.roof(), Vector3(0.45, 0.0, 0.0), false)
	_box(well, Vector3(2.6, 0.12, 1.5), c + Vector3(0.0, 2.55, -0.35), RetroMaterials.roof(), Vector3(-0.45, 0.0, 0.0), false)
	# The bucket rope goes down into the glow and does not come back up.
	_box(well, Vector3(0.02, 1.6, 0.02), c + Vector3(0.0, 1.5, 0.0), RetroMaterials.flat(Color(0.3, 0.25, 0.15)), Vector3.ZERO, false)
	var glow := OmniLight3D.new()
	glow.light_color = CURSED_LIGHT
	glow.light_energy = 0.9
	glow.omni_range = 4.5
	glow.position = c + Vector3(0.0, 1.0, 0.0)
	well.add_child(glow)


func _build_smithy() -> void:
	var smithy := _group("Smithy")
	var c := Vector3(16.0, 0.0, -13.0)
	var wood := RetroMaterials.wood()
	for corner in [Vector3(-2, 0, -2), Vector3(2, 0, -2), Vector3(-2, 0, 2), Vector3(2, 0, 2)]:
		_box(smithy, Vector3(0.2, 3.2, 0.2), c + corner + Vector3(0.0, 1.6, 0.0), wood)
	_box(smithy, Vector3(4.8, 0.15, 4.8), c + Vector3(0.0, 3.25, 0.0), RetroMaterials.roof(), Vector3(0.0, 0.0, 0.12), false)
	_box(smithy, Vector3(1.6, 1.0, 1.2), c + Vector3(1.2, 0.5, -1.2), RetroMaterials.stone())
	_box(smithy, Vector3(1.2, 0.1, 0.8), c + Vector3(1.2, 1.02, -1.2), RetroMaterials.flat(Color(0.5, 0.12, 0.04), 1.5), Vector3.ZERO, false)
	_box(smithy, Vector3(0.35, 0.6, 0.35), c + Vector3(-0.8, 0.3, 0.3), RetroMaterials.iron())
	_box(smithy, Vector3(0.9, 0.25, 0.4), c + Vector3(-0.8, 0.72, 0.3), RetroMaterials.iron())
	# Work bench where the woodsman's axe is left buried (pickup placed in the level).
	_box(smithy, Vector3(1.8, 0.1, 0.8), c + Vector3(-0.5, 0.85, 1.3), wood)
	_box(smithy, Vector3(1.7, 0.8, 0.7), c + Vector3(-0.5, 0.4, 1.3), wood, Vector3.ZERO, false)
	_clothes_heap(smithy, c + Vector3(0.6, 0.0, 0.2))
	var embers := OmniLight3D.new()
	embers.light_color = Color(1.0, 0.3, 0.1)
	embers.light_energy = 0.7
	embers.omni_range = 4.0
	embers.position = c + Vector3(1.2, 1.4, -1.2)
	smithy.add_child(embers)


# --- Lights, banners -----------------------------------------------------------

func _build_lanterns() -> void:
	var lanterns := _group("Lanterns")
	_lantern(lanterns, Vector3(-2.6, 0.0, 6.5), WARM_LIGHT)
	_lantern(lanterns, Vector3(-6.0, 0.0, -2.0), WARM_LIGHT)
	_lantern(lanterns, Vector3(6.0, 0.0, -9.0), CURSED_LIGHT)
	_lantern(lanterns, Vector3(0.0, 0.0, -15.5), WARM_LIGHT)
	# The knight's own lantern, dropped in the grass where he slept.
	var dropped := _box(lanterns, Vector3(0.22, 0.3, 0.22), Vector3(0.8, 0.12, 31.0), RetroMaterials.iron(), Vector3(0.0, 0.4, PI * 0.5), false)
	_box(dropped, Vector3(0.12, 0.16, 0.12), Vector3.ZERO, RetroMaterials.flat(WARM_LIGHT, 3.0), Vector3.ZERO, false)
	var light := FlickerLight.new()
	light.light_color = WARM_LIGHT
	light.base_energy = 0.9
	light.omni_range = 6.0
	light.position = Vector3(0.8, 0.4, 31.0)
	lanterns.add_child(light)


func _lantern(parent: Node3D, base: Vector3, color: Color) -> void:
	var iron := RetroMaterials.iron()
	_cylinder(parent, 0.05, 0.07, 2.6, base + Vector3(0.0, 1.3, 0.0), RetroMaterials.wood(), Vector3.ZERO, true, 6)
	_box(parent, Vector3(0.6, 0.06, 0.06), base + Vector3(0.28, 2.55, 0.0), iron, Vector3.ZERO, false)
	_box(parent, Vector3(0.24, 0.32, 0.24), base + Vector3(0.52, 2.3, 0.0), iron, Vector3.ZERO, false)
	_box(parent, Vector3(0.14, 0.2, 0.26), base + Vector3(0.52, 2.3, 0.0), RetroMaterials.flat(color, 3.0), Vector3.ZERO, false)
	var light := FlickerLight.new()
	light.light_color = color
	light.base_energy = 1.4
	light.omni_range = 9.0
	light.omni_attenuation = 1.4
	light.position = base + Vector3(0.52, 2.1, 0.0)
	parent.add_child(light)


func _build_banners() -> void:
	var banners := _group("Banners")
	var cloth := RetroMaterials.valdron_cloth()
	var gold := RetroMaterials.flat(Color(0.55, 0.45, 0.16))
	# Victory banners on the inner face of the front wall; some torn.
	for x in [-30.0, -20.0, -11.0, 11.0, 20.0, 30.0]:
		var torn := _rng.randf() < 0.4
		var length := _rng.randf_range(1.4, 2.4) if torn else 3.6
		var banner := _box(banners, Vector3(1.3, length, 0.04), Vector3(x, WALL_HEIGHT - 0.4 - length * 0.5, 8.95), cloth,
			Vector3(0.0, 0.0, _rng.randf_range(-0.12, 0.12) if torn else 0.0), false)
		_box(banner, Vector3(0.45, 0.45, 0.05), Vector3(0.0, length * 0.5 - 0.7, 0.0), gold, Vector3(0.0, 0.0, PI * 0.25), false)
	# Festival bunting strung across the courtyard.
	_bunting(banners, Vector3(-14.8, 3.8, -1.0), Vector3(14.8, 3.8, -1.0), 1.4)
	_bunting(banners, Vector3(-14.8, 3.5, -20.0), Vector3(15.0, 3.2, -20.0), 1.8)


func _bunting(parent: Node3D, a: Vector3, b: Vector3, sag: float) -> void:
	var colors := [RetroMaterials.valdron_cloth(), RetroMaterials.flat(Color(0.55, 0.45, 0.16)), RetroMaterials.linen()]
	var count := int(a.distance_to(b) / 1.2)
	var yaw := atan2(-(b - a).z, (b - a).x)
	for i in count + 1:
		var t := float(i) / count
		if _rng.randf() < 0.15:
			continue  # torn away
		var p := a.lerp(b, t) - Vector3(0.0, sag * 4.0 * t * (1.0 - t), 0.0)
		var flag := _box(parent, Vector3(0.3, 0.38, 0.02), p - Vector3(0.0, 0.19, 0.0), colors[i % colors.size()], Vector3(0.0, yaw, _rng.randf_range(-0.2, 0.2)), false)
		flag.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# --- Outside the walls ---------------------------------------------------------

func _build_meadow() -> void:
	var meadow := _group("Meadow")
	var placed := 0
	var attempts := 0
	while placed < 20 and attempts < 200:
		attempts += 1
		var p := Vector3(_rng.randf_range(-48.0, 48.0), 0.0, _rng.randf_range(14.0, 56.0))
		if absf(p.x) < 5.0 or p.distance_to(Vector3(1.0, 0.0, 30.0)) < 7.0:
			continue
		_dead_tree(meadow, p)
		placed += 1
	# Swords planted for the soldiers who fell against Loris.
	var iron := RetroMaterials.iron()
	for i in 14:
		var p := Vector3(-15.0, 0.0, 22.0) + Vector3(_rng.randf_range(-4.0, 4.0), 0.0, _rng.randf_range(-3.0, 3.0))
		var sword := _box(meadow, Vector3(0.06, 1.1, 0.02), p + Vector3(0.0, 0.45, 0.0), iron, Vector3(_rng.randf_range(-0.2, 0.2), _rng.randf() * TAU, _rng.randf_range(-0.2, 0.2)), false)
		_box(sword, Vector3(0.3, 0.05, 0.04), Vector3(0.0, 0.35, 0.0), iron, Vector3.ZERO, false)
	# Rocks.
	for i in 12:
		var p := Vector3(_rng.randf_range(-45.0, 45.0), 0.1, _rng.randf_range(13.0, 55.0))
		if absf(p.x) < 4.0:
			continue
		var s := _rng.randf_range(0.4, 1.4)
		_box(meadow, Vector3(s, s * 0.6, s * 0.8), p, RetroMaterials.mossy_stone(), Vector3(_rng.randf(), _rng.randf() * TAU, _rng.randf() * 0.4))
	# Overturned festival cart by the road.
	var wood := RetroMaterials.wood()
	_box(meadow, Vector3(2.4, 0.7, 1.4), Vector3(4.6, 0.7, 19.0), wood, Vector3(0.0, 0.3, 1.2))
	_cylinder(meadow, 0.5, 0.5, 0.1, Vector3(4.1, 0.08, 17.6), wood, Vector3(PI * 0.5, 0.0, 0.0), false, 8)
	_cylinder(meadow, 0.5, 0.5, 0.1, Vector3(5.6, 1.3, 19.6), wood, Vector3(0.0, 0.0, PI * 0.5 - 1.2), false, 8)
	for i in 5:
		var barrel_pos := Vector3(3.0 + _rng.randf_range(-1.5, 1.5), 0.3, 17.0 + _rng.randf_range(-2.0, 2.0))
		_cylinder(meadow, 0.3, 0.3, 0.8, barrel_pos, wood, Vector3(PI * 0.5, _rng.randf() * TAU, 0.0), false, 8)
	# The knight's sleeping place: flattened cloak and an empty wine jug.
	_box(meadow, Vector3(1.0, 0.03, 1.8), Vector3(1.2, 0.02, 30.0), RetroMaterials.valdron_cloth(), Vector3(0.0, 0.3, 0.0), false)
	_cylinder(meadow, 0.08, 0.12, 0.3, Vector3(2.2, 0.1, 30.6), RetroMaterials.flat(Color(0.3, 0.22, 0.14)), Vector3(PI * 0.5, 1.0, 0.0), false, 6)


func _dead_tree(parent: Node3D, base: Vector3) -> void:
	var height := _rng.randf_range(3.0, 6.0)
	var bark := RetroMaterials.bark()
	var trunk := _cylinder(parent, 0.1, 0.24, height, base + Vector3(0.0, height * 0.5, 0.0), bark,
		Vector3(_rng.randf_range(-0.12, 0.12), 0.0, _rng.randf_range(-0.12, 0.12)), true, 6)
	for i in _rng.randi_range(2, 5):
		var pivot := Node3D.new()
		pivot.position = Vector3(0.0, _rng.randf_range(0.0, height * 0.45), 0.0)
		pivot.rotation = Vector3(0.0, _rng.randf() * TAU, _rng.randf_range(0.6, 1.2))
		trunk.add_child(pivot)
		var length := _rng.randf_range(0.8, 2.0)
		_cylinder(pivot, 0.02, 0.07, length, Vector3(0.0, length * 0.5, 0.0), bark, Vector3.ZERO, false, 4)


func _build_keep_silhouette() -> void:
	var keep := _group("RoyalKeep")
	var stone := RetroMaterials.stone()
	var roof := RetroMaterials.roof()
	var c := Vector3(0.0, 0.0, -54.0)
	_box(keep, Vector3(16.0, 22.0, 10.0), c + Vector3(0.0, 11.0, 0.0), stone, Vector3.ZERO, false)
	for side in [-1.0, 1.0]:
		_cylinder(keep, 2.6, 2.8, 30.0, c + Vector3(side * 9.5, 15.0, 0.0), stone, Vector3.ZERO, false, 8)
		_cylinder(keep, 0.0, 3.4, 7.0, c + Vector3(side * 9.5, 33.5, 0.0), roof, Vector3.ZERO, false, 8)
	_cylinder(keep, 0.0, 4.0, 12.0, c + Vector3(0.0, 28.0, 0.0), roof, Vector3.ZERO, false, 4)
	# A single window high in the keep, burning green. Something is awake up there.
	_box(keep, Vector3(1.0, 1.8, 0.2), c + Vector3(-9.5, 24.0, 2.7), RetroMaterials.flat(CURSED_LIGHT, 6.0), Vector3.ZERO, false)


# --- Rot -----------------------------------------------------------------------

func _scatter_rot() -> void:
	var rot := _group("Rot")
	for i in 22:
		var p := Vector3(_rng.randf_range(-30.0, 30.0), _rng.randf_range(0.03, 0.05), _rng.randf_range(-36.0, 8.0))
		_splat(rot, _ooze_mat, p, _rng.randf_range(0.8, 2.6))
	for i in 30:
		var p := Vector3(_rng.randf_range(-12.0, 12.0), _rng.randf_range(0.03, 0.05), _rng.randf_range(-20.0, 8.0))
		_splat(rot, _blood_mat, p, _rng.randf_range(0.4, 1.5))
	# Drag marks from the feast towards the houses.
	_trail(rot, Vector3(-2.0, 0.0, -3.0), Vector3(-15.0, 0.0, 0.0))
	_trail(rot, Vector3(2.5, 0.0, -8.0), Vector3(15.0, 0.0, 0.0))
	_trail(rot, Vector3(0.0, 0.0, -12.0), Vector3(-7.0, 0.0, -17.0))
	# Empty festival clothes where people used to be.
	for i in 12:
		var p := Vector3(_rng.randf_range(-7.0, 7.0), 0.0, _rng.randf_range(-14.0, 4.0))
		_clothes_heap(rot, p)
	# Ooze weeping down the inside of the gate towers.
	for x in [-5.0, -4.2, 4.4, 5.3]:
		var drip := _splat(rot, _ooze_mat, Vector3(x, _rng.randf_range(2.0, 4.0), 8.38), _rng.randf_range(1.0, 1.8), true)
		drip.scale = Vector3(0.6, 1.8, 1.0)


func _trail(parent: Node3D, from: Vector3, to: Vector3) -> void:
	var steps := int(from.distance_to(to) / 0.6)
	for i in steps:
		var p := from.lerp(to, float(i) / steps) + Vector3(_rng.randf_range(-0.15, 0.15), _rng.randf_range(0.03, 0.05), _rng.randf_range(-0.15, 0.15))
		_splat(parent, _blood_mat, p, _rng.randf_range(0.3, 0.55))


func _clothes_heap(parent: Node3D, pos: Vector3) -> void:
	var palette := [Color(0.3, 0.05, 0.05), Color(0.2, 0.22, 0.3), Color(0.35, 0.3, 0.2), Color(0.15, 0.25, 0.12), Color(0.4, 0.36, 0.3)]
	var base_color: Color = palette[_rng.randi() % palette.size()]
	for i in 3:
		var offset := Vector3(_rng.randf_range(-0.35, 0.35), 0.04 + i * 0.04, _rng.randf_range(-0.35, 0.35))
		_box(parent, Vector3(_rng.randf_range(0.5, 0.9), 0.06, _rng.randf_range(0.4, 0.8)), pos + offset,
			RetroMaterials.flat(base_color.darkened(i * 0.15)), Vector3(0.0, _rng.randf() * TAU, _rng.randf_range(-0.1, 0.1)), false)
	_splat(parent, _ooze_mat, pos + Vector3(0.0, 0.025, 0.0), 1.2)


# --- Primitive helpers ---------------------------------------------------------

func _group(group_name: String) -> Node3D:
	var node := Node3D.new()
	node.name = group_name
	add_child(node)
	return node


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO, collide: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	if collide:
		var shape := BoxShape3D.new()
		shape.size = size
		_add_collider(mi, shape)
	return mi


func _cylinder(parent: Node3D, top_radius: float, bottom_radius: float, height: float, pos: Vector3, mat: Material,
		rot: Vector3 = Vector3.ZERO, collide: bool = false, segments: int = 8) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.height = height
	mesh.radial_segments = segments
	mesh.rings = 1
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	if collide:
		var shape := CylinderShape3D.new()
		shape.radius = maxf(top_radius, bottom_radius)
		shape.height = height
		_add_collider(mi, shape)
	return mi


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
	mi.set_instance_shader_parameter("seed", _rng.randf() * 100.0)
	return mi


func _add_collider(mi: MeshInstance3D, shape: Shape3D) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	mi.add_child(body)
