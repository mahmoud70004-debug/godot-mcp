extends Node3D

const PickupScript = preload("res://scripts/pickup.gd")
const EnemyScript = preload("res://scripts/enemy.gd")
var pickups: Array = []
var enemies: Array = []
var materials: Dictionary = {}

func _ready() -> void:
	_environment()
	_build_ground()
	_build_village()
	_build_gate()
	_build_forest()
	_build_story_objects()

func _material(color: Color, emission := false) -> StandardMaterial3D:
	var key := str(color) + str(emission)
	if materials.has(key):
		return materials[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	if emission:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 0.8
	materials[key] = mat
	return mat

func _box(parent: Node3D, pos: Vector3, size: Vector3, color: Color, solid := false, rotation := Vector3.ZERO, glow := false) -> Node3D:
	var root: Node3D = StaticBody3D.new() if solid else Node3D.new()
	root.position = pos
	root.rotation_degrees = rotation
	parent.add_child(root)
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = _material(color, glow)
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	root.add_child(visual)
	if solid:
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		collision.shape = shape
		root.add_child(collision)
	return root

func _environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("10171a")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("758880")
	env.ambient_light_energy = 0.52
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color("283834")
	env.fog_light_energy = 0.7
	env.fog_density = 0.022
	var world_environment := WorldEnvironment.new()
	world_environment.environment = env
	add_child(world_environment)
	var moonlight := DirectionalLight3D.new()
	moonlight.rotation_degrees = Vector3(-45, -35, 0)
	moonlight.light_color = Color("a7c0b1")
	moonlight.light_energy = 0.75
	add_child(moonlight)
	# A distant pale disc, deliberately simple and untextured for the blockout.
	var moon := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 2.0
	sphere.height = 4.0
	var moon_mat := _material(Color("a0b6a1"), true)
	moon_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sphere.material = moon_mat
	moon.mesh = sphere
	moon.position = Vector3(-20, 24, -70)
	add_child(moon)

func _build_ground() -> void:
	_box(self, Vector3(0, -0.25, 0), Vector3(90, 0.5, 100), Color("27352d"), true)
	_box(self, Vector3(0, 0.012, -2), Vector3(5.5, 0.025, 43), Color("514b40"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 74012
	for i in range(100):
		var z := rng.randf_range(-23, 19)
		var x := rng.randf_range(-2.5, 2.5)
		_box(self, Vector3(x, 0.035, z), Vector3(rng.randf_range(0.3, 0.8), 0.025, rng.randf_range(0.3, 0.9)), Color("61594b"), false, Vector3(0, rng.randf_range(-15, 15), 0))
	# Traces of the curse and blood, not hazards in this phase.
	for p in [Vector3(-1.9, 0.045, 7), Vector3(1.3, 0.045, 1), Vector3(-3, 0.045, -9), Vector3(5, 0.045, -14)]:
		_box(self, p, Vector3(1.4, 0.025, 0.65), Color("496b35"), false, Vector3(0, 22, 0), true)
	for p in [Vector3(0.8, 0.05, 5), Vector3(-1, 0.05, -4), Vector3(3.5, 0.05, -13)]:
		_box(self, p, Vector3(0.9, 0.025, 0.38), Color("5b2925"), false, Vector3(0, -28, 0))

func _house(x: float, z: float, scale_factor: float) -> void:
	var s := scale_factor
	var wall := Color("655f51")
	var wood := Color("302b29")
	_box(self, Vector3(x, 1.65*s, z), Vector3(4*s, 3.3*s, 4*s), wall, true)
	_box(self, Vector3(x-1.05*s, 3.5*s, z), Vector3(2.6*s, 0.25*s, 4.6*s), wood, false, Vector3(0, 0, -31))
	_box(self, Vector3(x+1.05*s, 3.5*s, z), Vector3(2.6*s, 0.25*s, 4.6*s), wood, false, Vector3(0, 0, 31))
	# Windows and beams face toward the road.
	var face := x - signf(x) * 2.03*s
	_box(self, Vector3(face, 1.65*s, z), Vector3(0.06, 1.15*s, 0.95*s), Color("151a19"))
	_box(self, Vector3(face-signf(x)*0.02, 1.65*s, z), Vector3(0.07, 1.15*s, 0.09*s), wood)
	_box(self, Vector3(face-signf(x)*0.02, 1.65*s, z), Vector3(0.07, 0.09*s, 0.95*s), wood)
	for dz in [-1.8, 1.8]:
		_box(self, Vector3(face, 1.65*s, z+dz*s), Vector3(0.1, 3.3*s, 0.16*s), wood)

func _build_village() -> void:
	_house(-6.5, 4, 1.0)
	_house(7.0, -2, 1.15)
	_house(-7.5, -11, 1.1)
	_house(7.5, -15, 0.9)
	# Low broken fence and grave markers.
	for z in [8.0, 6.0, 4.0, 2.0, 0.0, -2.0]:
		_box(self, Vector3(3.8, 0.55, z), Vector3(0.13, 1.1, 0.13), Color("3a3229"))
	_box(self, Vector3(3.8, 0.7, 3), Vector3(0.1, 0.12, 10), Color("3a3229"))
	for p in [Vector3(-11, 0.65, 11), Vector3(-13, 0.5, 7), Vector3(-10, 0.55, 6), Vector3(12, 0.7, 10)]:
		_box(self, p, Vector3(0.65, p.y*2, 0.22), Color("55584c"), true, Vector3(0, 0, 8))

func _build_gate() -> void:
	var stone := Color("4d514b")
	# The open portal frames the silhouette of the distant keep.
	_box(self, Vector3(-10, 4, -23), Vector3(14, 8, 2), stone, true)
	_box(self, Vector3(10, 4, -23), Vector3(14, 8, 2), stone, true)
	_box(self, Vector3(0, 7.2, -23), Vector3(6, 1.6, 2), stone, true)
	for x in [-4.0, 4.0]:
		_box(self, Vector3(x, 5, -23), Vector3(2, 10, 3.4), Color("575a52"), true)
		for dx in [-0.75, 0.75]:
			_box(self, Vector3(x+dx, 10.3, -23), Vector3(0.5, 0.7, 3.4), stone)
	_box(self, Vector3(0, 7, -44), Vector3(13, 14, 8), Color("303b38"), true)
	for x in [-7.0, 7.0]:
		_box(self, Vector3(x, 9, -44), Vector3(4, 18, 6), Color("343f3b"), true)
		_box(self, Vector3(x, 19, -44), Vector3(5, 2, 7), Color("272f2c"))

func _build_forest() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 506
	for i in range(36):
		var side := -1 if i % 2 == 0 else 1
		var x := side * rng.randf_range(13.0, 30.0)
		var z := rng.randf_range(-30, 20)
		var h := rng.randf_range(4.0, 7.0)
		var trunk := _box(self, Vector3(x, h/2, z), Vector3(0.5, h, 0.5), Color("282b25"), true, Vector3(0, 0, rng.randf_range(-8, 8)))
		_box(trunk, Vector3(0.9, h*0.18, 0), Vector3(2, 0.22, 0.22), Color("282b25"), false, Vector3(0, 0, 35))
		_box(trunk, Vector3(-0.65, h*0.3, 0), Vector3(1.6, 0.18, 0.18), Color("282b25"), false, Vector3(0, 0, -42))

func _build_story_objects() -> void:
	_add_pickup(Vector3(-2.0, 0.2, 9), "Torn decree", "Valdron celebrates; Loris burns.")
	_add_pickup(Vector3(2.0, 0.2, -11), "Alchemist's note", "A green stain spreads beneath the skin.")
	var enemy = EnemyScript.new()
	enemy.position = Vector3(0.5, 0, -3)
	add_child(enemy)
	enemies.append(enemy)
	# A silent, asymmetrical figure: a placeholder for future creature design.
	_box(enemy, Vector3(0, 1.05, 0), Vector3(0.65, 1.1, 0.4), Color("56584a"), false, Vector3(0, 0, 12))
	_box(enemy, Vector3(0.12, 1.85, 0), Vector3(0.48, 0.62, 0.4), Color("8b8873"), false, Vector3(0, 0, -12))
	_box(enemy, Vector3(-0.4, 0.92, 0), Vector3(0.16, 1.25, 0.16), Color("777866"), false, Vector3(0, 0, -13))
	_box(enemy, Vector3(0.48, 0.8, 0), Vector3(0.18, 1.65, 0.18), Color("777866"), false, Vector3(0, 0, 12))
	for x in [-0.2, 0.2]:
		_box(enemy, Vector3(x, 0.35, 0), Vector3(0.2, 0.7, 0.23), Color("484a40"))
	for x in [0.02, 0.22]:
		_box(enemy, Vector3(x, 1.92, 0.205), Vector3(0.06, 0.06, 0.03), Color("b8cc91"), false, Vector3.ZERO, true)

func _add_pickup(pos: Vector3, title: String, detail: String) -> void:
	var item = PickupScript.new()
	item.item_name = title
	item.description = detail
	item.position = pos
	add_child(item)
	pickups.append(item)
	_box(item, Vector3.ZERO, Vector3(0.45, 0.12, 0.35), Color("c6b67c"), false, Vector3(0, 20, 0), true)

func get_nearby_item(pos: Vector3) -> Node3D:
	for item in pickups:
		if is_instance_valid(item) and not item.is_queued_for_deletion() and item.global_position.distance_to(pos) < 2.4:
			return item
	return null

func hit_enemy(pos: Vector3, forward: Vector3) -> bool:
	for enemy in enemies:
		if not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
			continue
		var offset: Vector3 = enemy.global_position - pos
		offset.y = 0
		if offset.length() < 2.6 and forward.dot(offset.normalized()) > 0.45:
			enemy.take_hit()
			return true
	return false
