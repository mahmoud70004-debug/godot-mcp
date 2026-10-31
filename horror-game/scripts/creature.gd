class_name Creature
extends Node3D
## The entity: a tall, emaciated figure with a pale stretched face, black
## eye sockets with pin-point glowing pupils and a mouth that is far too wide.
## Built entirely from primitive meshes. Twitches its head and limbs.

var head: Node3D
var jaw: Node3D
var arm_l: Node3D
var arm_r: Node3D
var eyes: Array[MeshInstance3D] = []
var twitch_strength := 1.0
var walk_phase := 0.0
var moving := 0.0
var _twitch_timer := 0.0
var _head_target := Vector3.ZERO

static var _mats: Dictionary = {}

static func _mat(key: String) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	match key:
		"skin":
			m.albedo_color = Color(0.78, 0.76, 0.7)
			var nt := NoiseTexture2D.new()
			nt.width = 128
			nt.height = 128
			var fn := FastNoiseLite.new()
			fn.frequency = 0.08
			fn.fractal_octaves = 3
			nt.noise = fn
			var g := Gradient.new()
			g.set_color(0, Color(0.45, 0.42, 0.4))
			g.set_color(1, Color(1, 1, 0.96))
			nt.color_ramp = g
			m.albedo_texture = nt
			m.roughness = 0.45
			m.emission_enabled = true
			m.emission = Color(0.55, 0.55, 0.5)
			m.emission_energy_multiplier = 0.12
		"body":
			m.albedo_color = Color(0.13, 0.1, 0.09)
			m.roughness = 0.95
		"limb":
			m.albedo_color = Color(0.32, 0.29, 0.27)
			m.roughness = 0.8
		"hole":
			m.albedo_color = Color(0, 0, 0)
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		"eye":
			m.albedo_color = Color(1, 0.9, 0.85)
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.emission_enabled = true
			m.emission = Color(1.0, 0.2, 0.15)
			m.emission_energy_multiplier = 4.0
		"teeth":
			m.albedo_color = Color(0.78, 0.72, 0.52)
			m.roughness = 0.3
			m.emission_enabled = true
			m.emission = Color(0.6, 0.6, 0.5)
			m.emission_energy_multiplier = 0.2
		"blood":
			m.albedo_color = Color(0.14, 0.0, 0.0)
			m.roughness = 0.2
	_mats[key] = m
	return m

static func _mesh(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, scl := Vector3.ONE, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.scale = scl
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

static func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 16
	s.rings = 10
	return s

static func _capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	c.radial_segments = 10
	c.rings = 4
	return c

static func _box(s: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = s
	return b

func _init(face_only := false) -> void:
	if face_only:
		head = Node3D.new()
		add_child(head)
		_build_head(head)
		return
	# Torso: emaciated, slightly hunched.
	var torso := Node3D.new()
	torso.position = Vector3(0, 1.55, 0)
	torso.rotation.x = 0.18
	add_child(torso)
	_mesh(torso, _capsule(0.2, 1.1), _mat("body"), Vector3.ZERO, Vector3(1.0, 1.0, 0.7))
	# ribs
	for i in 4:
		_mesh(torso, _box(Vector3(0.34, 0.025, 0.05)), _mat("limb"), Vector3(0, 0.15 - i * 0.09, -0.13))
	# Legs
	for side in [-1.0, 1.0]:
		_mesh(self, _capsule(0.06, 1.15), _mat("body"), Vector3(0.12 * side, 0.58, 0))
	# Arms: absurdly long, hang to the knees, with claw fingers.
	arm_l = Node3D.new()
	arm_r = Node3D.new()
	for pair in [[arm_l, -1.0], [arm_r, 1.0]]:
		var arm: Node3D = pair[0]
		var side: float = pair[1]
		arm.position = Vector3(0.27 * side, 1.98, 0)
		arm.rotation.z = 0.08 * side
		add_child(arm)
		_mesh(arm, _capsule(0.045, 1.45), _mat("limb"), Vector3(0, -0.7, 0))
		for f in 4:
			_mesh(arm, _capsule(0.012, 0.32), _mat("limb"), Vector3((f - 1.5) * 0.025, -1.52, -0.02), Vector3.ONE, Vector3(0.25, 0, (f - 1.5) * 0.12))
	# Neck + head
	_mesh(self, _capsule(0.05, 0.35), _mat("limb"), Vector3(0, 2.12, -0.05), Vector3.ONE, Vector3(0.4, 0, 0))
	head = Node3D.new()
	head.position = Vector3(0, 2.38, -0.12)
	add_child(head)
	_build_head(head)

static func _cone(r: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = 0.0
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 6
	c.rings = 1
	return c

func _build_head(h: Node3D) -> void:
	# The node faces -Z (Godot forward), so the face is built on the -Z side.
	# Long, gaunt skull shape with sunken cheeks.
	_mesh(h, _sphere(0.2), _mat("skin"), Vector3(0, 0.02, 0), Vector3(0.78, 1.35, 0.85))
	_mesh(h, _sphere(0.12), _mat("skin"), Vector3(0, -0.13, -0.04), Vector3(1.05, 0.8, 1.0))
	# Sunken, uneven eye sockets with a pin-point glowing pupil deep inside.
	for side in [-1.0, 1.0]:
		var sy := 0.07 if side < 0 else 0.055
		_mesh(h, _sphere(0.045), _mat("hole"), Vector3(0.062 * side, sy, -0.148), Vector3(1.0, 1.25, 0.55), Vector3(0, 0, 0.25 * side))
		var e := _mesh(h, _sphere(0.0065), _mat("eye"), Vector3(0.06 * side, sy - 0.004, -0.168))
		eyes.append(e)
		# dark dried blood running from the eyes
		_mesh(h, _box(Vector3(0.007, 0.15, 0.006)), _mat("blood"), Vector3(0.064 * side, sy - 0.1, -0.158), Vector3.ONE, Vector3(0.25, 0, 0.05 * side))
	# Nose: two slits.
	for side in [-1.0, 1.0]:
		_mesh(h, _box(Vector3(0.008, 0.03, 0.01)), _mat("hole"), Vector3(0.012 * side, -0.03, -0.17))
	# The grin: stretched ear to ear, with crooked needle teeth.
	jaw = Node3D.new()
	jaw.position = Vector3(0, -0.12, -0.12)
	h.add_child(jaw)
	for i in 7:
		# the mouth hole is a curved chain of boxes so it smiles upward at the corners
		var x := (i - 3) * 0.042
		var y := pow(absf(i - 3) / 3.0, 2.0) * 0.045
		_mesh(jaw, _box(Vector3(0.05, 0.055 - absf(i - 3) * 0.008, 0.05)), _mat("hole"), Vector3(x, y, -0.02 + absf(i - 3) * 0.012), Vector3.ONE, Vector3(0, -x * 2.5, (i - 3) * -0.12))
	var rng := RandomNumberGenerator.new()
	rng.seed = 666
	for t in 15:
		var x := (t - 7) * 0.019
		var y := pow(absf(t - 7) / 7.0, 2.0) * 0.045
		var z := -0.05 + absf(t - 7) * 0.004
		var l1 := rng.randf_range(0.025, 0.05)
		var l2 := rng.randf_range(0.02, 0.04)
		# upper fang pointing down
		_mesh(jaw, _cone(0.006, l1), _mat("teeth"), Vector3(x, y + 0.026 - l1 * 0.5 + 0.012, z), Vector3.ONE, Vector3(rng.randf_range(-0.2, 0.2), 0, PI + rng.randf_range(-0.25, 0.25)))
		# lower fang pointing up
		_mesh(jaw, _cone(0.005, l2), _mat("teeth"), Vector3(x + 0.009, y - 0.026 + l2 * 0.5 - 0.012, z), Vector3.ONE, Vector3(rng.randf_range(-0.2, 0.2), 0, rng.randf_range(-0.25, 0.25)))

func set_eye_glow(e: float) -> void:
	_mat("eye").emission_energy_multiplier = e

func _process(delta: float) -> void:
	if head == null:
		return
	_twitch_timer -= delta
	if _twitch_timer <= 0.0:
		# Sudden unnatural head snaps.
		_twitch_timer = randf_range(0.08, 0.9) / maxf(twitch_strength, 0.2)
		var k := minf(twitch_strength, 1.0)
		_head_target = Vector3(randf_range(-0.3, 0.3), randf_range(-0.45, 0.45), randf_range(-0.5, 0.5)) * k
		if randf() < 0.25:
			# the horrible sideways head tilt
			_head_target.z = randf_range(1.0, 1.5) * signf(randf() - 0.5) * k
	head.rotation = head.rotation.lerp(_head_target, minf(delta * 22.0, 1.0))
	if jaw:
		jaw.position.y = -0.12 - absf(sin(Time.get_ticks_msec() * 0.004)) * 0.03 * twitch_strength
	if arm_l:
		walk_phase += delta * (2.0 + moving * 6.0)
		var sw := sin(walk_phase) * 0.35 * moving
		arm_l.rotation.x = sw + randf_range(-0.03, 0.03)
		arm_r.rotation.x = -sw + randf_range(-0.03, 0.03)
		position.y = absf(sin(walk_phase)) * 0.06 * moving
