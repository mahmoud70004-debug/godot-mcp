class_name KnightModel
extends HumanoidRig
## The player's knight: dark weathered Gothic plate under a crimson Valdron
## tabard with a gold cross, great helm, layered pauldrons, long tattered
## cloak. Only used offline to bake sprites, so it is built with lots of small
## overlapping plates (everything is merged per pivot by bake_character).

var goblet: Node3D
var _rim: OmniLight3D


## Cool moonlit rim light for night shots far from the fires.
func set_rim_light(on: bool) -> void:
	if _rim == null:
		_rim = OmniLight3D.new()
		_rim.light_color = Color(0.55, 0.68, 1.0)
		_rim.light_energy = 0.9
		_rim.omni_range = 4.5
		_rim.position = Vector3(0.8, 2.4, 1.8)
		add_child(_rim)
	_rim.visible = on


## Only the toast shows the goblet when sampled offline; runtime code owns it otherwise.
func pose_at(anim: StringName, t: float) -> void:
	super.pose_at(anim, t)
	if not _from_process:
		goblet.visible = anim == &"toast"


var _plate: StandardMaterial3D
var _edge: StandardMaterial3D
var _dark: StandardMaterial3D
var _gold: StandardMaterial3D
var _cloth: StandardMaterial3D
var _cloak: StandardMaterial3D
var _cloak_b: StandardMaterial3D
var _leather: StandardMaterial3D
var _void: StandardMaterial3D


func _build() -> void:
	_plate = PartBuilder.steel(Color(0.32, 0.33, 0.36), 0.8, 0.4)
	_edge = PartBuilder.steel(Color(0.56, 0.58, 0.64), 0.85, 0.3)
	_dark = PartBuilder.steel(Color(0.2, 0.2, 0.23), 0.8, 0.45)
	_gold = PartBuilder.steel(Color(0.72, 0.56, 0.22))
	_cloth = RetroMaterials.valdron_cloth()
	_cloak = RetroMaterials.flat(Color(0.075, 0.07, 0.09))
	_cloak_b = RetroMaterials.flat(Color(0.12, 0.105, 0.13))
	_leather = RetroMaterials.flat(Color(0.16, 0.1, 0.07))
	_void = RetroMaterials.flat(Color(0.0, 0.0, 0.0))

	hips = PartBuilder.pivot(self, "Hips", Vector3(0.0, 1.0, 0.0))
	for side in [-1.0, 1.0]:
		var leg := PartBuilder.pivot(hips, "LegL" if side < 0 else "LegR", Vector3(side * 0.12, 0.0, 0.0))
		_build_leg(leg, side)
		if side < 0:
			leg_l = leg
		else:
			leg_r = leg
	_build_hips()

	spine = PartBuilder.pivot(hips, "Spine", Vector3(0.0, 0.14, 0.0))
	_build_torso()
	_build_cloak()

	for side in [-1.0, 1.0]:
		var shoulder := PartBuilder.pivot(spine, "ShoulderL" if side < 0 else "ShoulderR", Vector3(side * 0.27, 0.5, 0.0))
		var elbow := PartBuilder.pivot(shoulder, "Elbow", Vector3(0.0, -0.32, 0.0))
		var hand := PartBuilder.pivot(elbow, "Hand", Vector3(0.0, -0.3, 0.0))
		_build_arm(shoulder, elbow, hand, side)
		if side < 0:
			shoulder_l = shoulder
			elbow_l = elbow
		else:
			shoulder_r = shoulder
			elbow_r = elbow
			hand_r = hand

	head = PartBuilder.pivot(spine, "Head", Vector3(0.0, 0.64, 0.0))
	_build_helm()

	goblet = PartBuilder.pivot(hand_r, "Goblet", Vector3(0.0, -0.06, -0.06))
	PartBuilder.cylinder(goblet, 0.05, 0.03, 0.1, Vector3(0.0, 0.0, 0.0), _gold, 6, Vector3(PI * 0.5, 0.0, 0.0))
	goblet.visible = false


func _build_leg(leg: Node3D, side: float) -> void:
	# Cuisse: tapered thigh plate with a bright centre ridge.
	PartBuilder.cylinder(leg, 0.085, 0.07, 0.44, Vector3(0.0, -0.22, 0.0), _plate, 8)
	PartBuilder.box(leg, Vector3(0.025, 0.36, 0.02), Vector3(0.0, -0.21, -0.08), _edge, Vector3(0.05, 0.0, 0.0))
	PartBuilder.cylinder(leg, 0.075, 0.075, 0.03, Vector3(0.0, -0.01, 0.0), _dark, 8)
	# Poleyn: knee cop with a wing and lames above and below it.
	PartBuilder.sphere(leg, 0.085, Vector3(0.0, -0.46, -0.035), _edge)
	PartBuilder.box(leg, Vector3(0.03, 0.1, 0.1), Vector3(side * 0.075, -0.46, -0.03), _plate, Vector3(0.0, 0.0, side * 0.2))
	PartBuilder.cylinder(leg, 0.082, 0.082, 0.025, Vector3(0.0, -0.405, -0.01), _dark, 8)
	PartBuilder.cylinder(leg, 0.075, 0.075, 0.025, Vector3(0.0, -0.52, -0.005), _dark, 8)
	# Greave: flared shin guard with a front ridge and a calf plate.
	PartBuilder.cylinder(leg, 0.075, 0.055, 0.4, Vector3(0.0, -0.72, 0.0), _plate, 8)
	PartBuilder.box(leg, Vector3(0.025, 0.36, 0.025), Vector3(0.0, -0.72, -0.065), _edge, Vector3(-0.04, 0.0, 0.0))
	PartBuilder.box(leg, Vector3(0.1, 0.2, 0.03), Vector3(0.0, -0.68, 0.06), _dark)
	PartBuilder.cylinder(leg, 0.06, 0.065, 0.03, Vector3(0.0, -0.92, 0.0), _dark, 8)
	# Sabaton: heel, instep lames and a pointed toe cap.
	PartBuilder.box(leg, Vector3(0.11, 0.07, 0.12), Vector3(0.0, -0.95, 0.04), _plate)
	for i in 3:
		PartBuilder.box(leg, Vector3(0.115 - i * 0.008, 0.035, 0.06), Vector3(0.0, -0.93, -0.04 - i * 0.045), _plate, Vector3(0.18, 0.0, 0.0))
	PartBuilder.box(leg, Vector3(0.1, 0.05, 0.08), Vector3(0.0, -0.965, -0.17), _dark)
	PartBuilder.cylinder(leg, 0.0, 0.05, 0.1, Vector3(0.0, -0.965, -0.24), _edge, 4, Vector3(-PI * 0.5, PI * 0.25, 0.0))


func _build_hips() -> void:
	PartBuilder.box(hips, Vector3(0.4, 0.14, 0.28), Vector3(0.0, 0.07, 0.0), _plate)
	PartBuilder.box(hips, Vector3(0.42, 0.04, 0.3), Vector3(0.0, 0.14, 0.0), _leather)
	PartBuilder.box(hips, Vector3(0.06, 0.05, 0.02), Vector3(0.0, 0.14, -0.155), _gold)
	# Fauld: overlapping lames flaring over the hips.
	for i in 3:
		var w := 0.44 + i * 0.03
		PartBuilder.box(hips, Vector3(w, 0.05, 0.31 + i * 0.03), Vector3(0.0, 0.02 - i * 0.045, 0.0), _plate if i % 2 == 0 else _dark)
	# Tassets: segmented plates hanging over the thighs.
	for side in [-1.0, 1.0]:
		for i in 4:
			PartBuilder.frustum(hips, 0.17 - i * 0.005, 0.185 - i * 0.005, 0.07, 0.025, Vector3(side * 0.2, -0.1 - i * 0.065, -0.1 + i * 0.012),
				_plate if i % 2 == 0 else _edge, Vector3(-0.1, side * -0.35, side * -0.06))
		PartBuilder.box(hips, Vector3(0.03, 0.06, 0.03), Vector3(side * 0.21, -0.03, -0.1), _gold)
	# Tabard skirt, front and back.
	PartBuilder.frustum(hips, 0.2, 0.28, 0.58, 0.02, Vector3(0.0, -0.22, -0.16), _cloth, Vector3(-0.03, 0.0, 0.0))
	PartBuilder.frustum(hips, 0.28, 0.32, 0.5, 0.02, Vector3(0.0, -0.2, 0.15), _cloth)
	PartBuilder.box(hips, Vector3(0.22, 0.02, 0.025), Vector3(0.0, -0.5, -0.18), _gold)
	# The ceremonial sword at the left hip.
	var sword := WeaponModelBuilder.build(load("res://data/items/weapons/ceremonial_sword.tres") as WeaponData)
	sword.position = Vector3(-0.24, 0.05, 0.05)
	sword.rotation = Vector3(0.25, 0.0, PI - 0.15)
	sword.scale = Vector3.ONE * 0.9
	hips.add_child(sword)


func _build_torso() -> void:
	# Breastplate: tapering cuirass with fluting ridges, waist plates and a tabard panel.
	PartBuilder.cylinder(spine, 0.225, 0.17, 0.5, Vector3(0.0, 0.28, 0.0), _plate, 8)
	PartBuilder.cylinder(spine, 0.19, 0.2, 0.06, Vector3(0.0, 0.04, 0.0), _dark, 8)
	PartBuilder.cylinder(spine, 0.2, 0.22, 0.07, Vector3(0.0, 0.1, 0.0), _plate, 8)
	for x in [-0.17, -0.1, 0.1, 0.17]:
		PartBuilder.box(spine, Vector3(0.018, 0.4, 0.02), Vector3(x, 0.3, -0.18 + absf(x) * 0.25), _edge, Vector3(0.0, x * 1.6, 0.0))
	for x in [-0.14, -0.07, 0.0, 0.07, 0.14]:
		PartBuilder.box(spine, Vector3(0.02, 0.38, 0.02), Vector3(x, 0.3, 0.175), _edge)
	PartBuilder.box(spine, Vector3(0.36, 0.03, 0.04), Vector3(0.0, 0.5, -0.17), _edge)
	PartBuilder.box(spine, Vector3(0.22, 0.46, 0.02), Vector3(0.0, 0.26, -0.2), _cloth)
	PartBuilder.box(spine, Vector3(0.05, 0.3, 0.025), Vector3(0.0, 0.3, -0.215), _gold)
	PartBuilder.box(spine, Vector3(0.2, 0.05, 0.025), Vector3(0.0, 0.36, -0.215), _gold)
	PartBuilder.box(spine, Vector3(0.24, 0.045, 0.04), Vector3(0.0, 0.07, -0.2), _leather)
	PartBuilder.box(spine, Vector3(0.04, 0.045, 0.045), Vector3(0.0, 0.07, -0.21), _gold)
	# Gorget: stacked collar lames and a neck guard.
	PartBuilder.cylinder(spine, 0.13, 0.17, 0.06, Vector3(0.0, 0.54, 0.0), _plate, 10)
	PartBuilder.cylinder(spine, 0.11, 0.135, 0.05, Vector3(0.0, 0.59, 0.0), _dark, 10)
	PartBuilder.cylinder(spine, 0.1, 0.11, 0.04, Vector3(0.0, 0.63, 0.0), _edge, 10)


func _build_cloak() -> void:
	# Long tattered cloak: overlapping tapered panels from the shoulders, ragged hem.
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	PartBuilder.box(spine, Vector3(0.56, 0.07, 0.07), Vector3(0.0, 0.52, 0.17), _cloak, Vector3(-0.15, 0.0, 0.0))
	for i in 6:
		var u := float(i) / 5.0 - 0.5
		var x := u * 0.5
		var length := 1.1 + rng.randf() * 0.4
		var z := 0.2 + absf(u) * 0.04 + (i % 2) * 0.012
		var panel := PartBuilder.frustum(spine, 0.14, 0.2, length, 0.02,
			Vector3(x * 1.1, 0.5 - length * 0.5, z + length * 0.07),
			_cloak if i % 2 == 0 else _cloak_b, Vector3(-0.13 - rng.randf() * 0.05, -u * 0.22, u * 0.1 + rng.randf() * 0.04 - 0.02))
		# Ragged hem: a few torn strips below the panel edge.
		for k in 3:
			var strip := 0.08 + rng.randf() * 0.2
			var local := Vector3((k - 1) * 0.065, -length * 0.5 - strip * 0.4, 0.0)
			PartBuilder.frustum(panel, 0.055, 0.02, strip, 0.016, local, _cloak_b if i % 2 == 0 else _cloak, Vector3(0.0, 0.0, (rng.randf() - 0.5) * 0.35))


func _build_arm(shoulder: Node3D, elbow: Node3D, hand: Node3D, side: float) -> void:
	# Pauldron: a dome with four overlapping lames, bright rim and a ridge.
	PartBuilder.sphere(shoulder, 0.15, Vector3(side * 0.03, 0.03, 0.0), _plate, true, 10)
	PartBuilder.box(shoulder, Vector3(0.03, 0.025, 0.26), Vector3(side * 0.04, 0.17, 0.0), _edge, Vector3(0.0, 0.0, side * 0.2))
	for i in 4:
		PartBuilder.box(shoulder, Vector3(0.22 - i * 0.01, 0.035, 0.27 - i * 0.012), Vector3(side * (0.055 + i * 0.012), -0.01 - i * 0.045, 0.0),
			_plate if i % 2 == 0 else _dark, Vector3(0.0, 0.0, side * (0.4 - i * 0.04)))
		PartBuilder.box(shoulder, Vector3(0.012, 0.012, 0.25 - i * 0.012), Vector3(side * (0.15 + i * 0.012), -0.03 - i * 0.047, 0.0), _edge, Vector3(0.0, 0.0, side * (0.4 - i * 0.04)))
	# Rerebrace and couter (elbow cop with a wing).
	PartBuilder.cylinder(shoulder, 0.058, 0.05, 0.28, Vector3(0.0, -0.18, 0.0), _plate, 8)
	PartBuilder.box(shoulder, Vector3(0.02, 0.2, 0.02), Vector3(0.0, -0.18, -0.055), _edge)
	PartBuilder.sphere(elbow, 0.065, Vector3(0.0, 0.0, 0.015), _edge)
	PartBuilder.box(elbow, Vector3(0.025, 0.09, 0.09), Vector3(side * 0.06, 0.0, 0.03), _plate, Vector3(0.0, 0.0, side * 0.25))
	PartBuilder.cylinder(elbow, 0.058, 0.058, 0.025, Vector3(0.0, 0.05, 0.0), _dark, 8)
	# Vambrace: flares towards the wrist, ridge on top and a flared cuff.
	PartBuilder.cylinder(elbow, 0.055, 0.045, 0.26, Vector3(0.0, -0.15, 0.0), _plate, 8)
	PartBuilder.box(elbow, Vector3(0.02, 0.2, 0.02), Vector3(0.0, -0.15, -0.055), _edge)
	PartBuilder.cylinder(elbow, 0.05, 0.068, 0.07, Vector3(0.0, -0.27, 0.0), _dark, 8)
	# Gauntlet: cuff, back-of-hand plate, thumb and articulated finger lames.
	PartBuilder.cylinder(hand, 0.062, 0.05, 0.06, Vector3(0.0, 0.01, 0.0), _plate, 8)
	PartBuilder.box(hand, Vector3(0.09, 0.07, 0.07), Vector3(0.0, -0.06, 0.0), _dark)
	PartBuilder.box(hand, Vector3(0.075, 0.015, 0.05), Vector3(0.0, -0.025, -0.01), _edge)
	PartBuilder.box(hand, Vector3(0.025, 0.07, 0.03), Vector3(side * -0.06, -0.07, -0.025), _plate, Vector3(0.0, 0.0, side * 0.3))
	for f in 4:
		var fx := -0.0315 + f * 0.021
		for j in 3:
			PartBuilder.box(hand, Vector3(0.017, 0.025, 0.02), Vector3(fx, -0.11 - j * 0.026, -0.03), _plate if j % 2 == 0 else _edge)
		PartBuilder.box(hand, Vector3(0.016, 0.012, 0.02), Vector3(fx, -0.19, -0.03), _dark)


func _build_helm() -> void:
	# Great helm: rounded skull, flared lower face, visor ridge, dark eye slit and breaths.
	PartBuilder.cylinder(head, 0.125, 0.13, 0.26, Vector3(0.0, 0.12, 0.0), _plate, 12)
	PartBuilder.sphere(head, 0.125, Vector3(0.0, 0.25, 0.0), _plate, true, 12)
	PartBuilder.cylinder(head, 0.13, 0.135, 0.03, Vector3(0.0, -0.005, 0.0), _dark, 12)
	PartBuilder.cylinder(head, 0.128, 0.128, 0.025, Vector3(0.0, 0.24, 0.0), _edge, 12)
	PartBuilder.box(head, Vector3(0.2, 0.04, 0.035), Vector3(0.0, 0.17, -0.115), _edge)
	PartBuilder.box(head, Vector3(0.17, 0.02, 0.03), Vector3(0.0, 0.15, -0.125), _void)
	PartBuilder.box(head, Vector3(0.035, 0.2, 0.04), Vector3(0.0, 0.1, -0.125), _edge)
	for x in [-0.075, -0.045, 0.045, 0.075]:
		for k in 3:
			PartBuilder.box(head, Vector3(0.012, 0.012, 0.02), Vector3(x, 0.115 - k * 0.025, -0.125), _void)
	PartBuilder.box(head, Vector3(0.012, 0.18, 0.012), Vector3(0.0, 0.13, 0.128), _edge)
	PartBuilder.box(head, Vector3(0.03, 0.04, 0.2), Vector3(0.0, 0.385, 0.0), _dark)
	PartBuilder.box(head, Vector3(0.022, 0.03, 0.03), Vector3(0.0, 0.41, -0.07), _gold)
	# Short crimson plume streaming back from the crest.
	for i in 4:
		PartBuilder.frustum(head, 0.05 - i * 0.008, 0.04 - i * 0.008, 0.1 + i * 0.01, 0.03, Vector3(0.0, 0.39 - i * 0.03, 0.09 + i * 0.065), _cloth, Vector3(-0.9 - i * 0.15, 0.0, 0.0))
