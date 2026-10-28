class_name KnightModel
extends HumanoidRig
## The player's knight as seen in cutscenes: full Gothic plate harness under
## a crimson Valdron tabard, armet with a pointed crown and red plume.

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


func _build() -> void:
	var plate := PartBuilder.steel(Color(0.6, 0.62, 0.66))
	var dark := PartBuilder.steel(Color(0.28, 0.28, 0.31))
	var gold := PartBuilder.steel(Color(0.72, 0.56, 0.22))
	var cloth := RetroMaterials.valdron_cloth()
	var leather := RetroMaterials.flat(Color(0.18, 0.11, 0.07))
	var void_mat := RetroMaterials.flat(Color(0.0, 0.0, 0.0))

	hips = PartBuilder.pivot(self, "Hips", Vector3(0.0, 1.0, 0.0))
	for side in [-1.0, 1.0]:
		var leg := PartBuilder.pivot(hips, "LegL" if side < 0 else "LegR", Vector3(side * 0.12, 0.0, 0.0))
		PartBuilder.box(leg, Vector3(0.15, 0.44, 0.17), Vector3(0.0, -0.22, 0.0), plate)
		PartBuilder.sphere(leg, 0.075, Vector3(0.0, -0.46, -0.03), dark)
		PartBuilder.cylinder(leg, 0.07, 0.06, 0.44, Vector3(0.0, -0.7, 0.0), plate, 6)
		PartBuilder.box(leg, Vector3(0.12, 0.08, 0.28), Vector3(0.0, -0.95, -0.06), dark)
		if side < 0:
			leg_l = leg
		else:
			leg_r = leg
	PartBuilder.box(hips, Vector3(0.4, 0.2, 0.28), Vector3(0.0, 0.04, 0.0), plate)
	PartBuilder.box(hips, Vector3(0.34, 0.52, 0.02), Vector3(0.0, -0.2, -0.15), cloth)
	PartBuilder.box(hips, Vector3(0.34, 0.52, 0.02), Vector3(0.0, -0.2, 0.15), cloth)
	PartBuilder.box(hips, Vector3(0.42, 0.05, 0.3), Vector3(0.0, 0.13, 0.0), leather)
	# The ceremonial sword at the left hip.
	var sword := WeaponModelBuilder.build(load("res://data/items/weapons/ceremonial_sword.tres") as WeaponData)
	sword.position = Vector3(-0.24, 0.05, 0.05)
	sword.rotation = Vector3(0.25, 0.0, PI - 0.15)
	sword.scale = Vector3.ONE * 0.9
	hips.add_child(sword)

	spine = PartBuilder.pivot(hips, "Spine", Vector3(0.0, 0.14, 0.0))
	PartBuilder.cylinder(spine, 0.21, 0.17, 0.5, Vector3(0.0, 0.28, 0.0), plate, 6)
	PartBuilder.box(spine, Vector3(0.3, 0.46, 0.02), Vector3(0.0, 0.26, -0.185), cloth)
	PartBuilder.box(spine, Vector3(0.05, 0.3, 0.025), Vector3(0.0, 0.3, -0.2), gold)
	PartBuilder.box(spine, Vector3(0.2, 0.05, 0.025), Vector3(0.0, 0.36, -0.2), gold)
	PartBuilder.cylinder(spine, 0.11, 0.13, 0.09, Vector3(0.0, 0.57, 0.0), dark, 8)
	# Cape from the shoulders.
	PartBuilder.box(spine, Vector3(0.52, 1.15, 0.025), Vector3(0.0, -0.02, 0.2), cloth, Vector3(-0.08, 0.0, 0.0))

	for side in [-1.0, 1.0]:
		var shoulder := PartBuilder.pivot(spine, "ShoulderL" if side < 0 else "ShoulderR", Vector3(side * 0.27, 0.5, 0.0))
		PartBuilder.sphere(shoulder, 0.14, Vector3(side * 0.03, 0.02, 0.0), plate, true)
		PartBuilder.box(shoulder, Vector3(0.2, 0.04, 0.24), Vector3(side * 0.05, -0.04, 0.0), dark, Vector3(0.0, 0.0, side * 0.3))
		PartBuilder.cylinder(shoulder, 0.055, 0.05, 0.28, Vector3(0.0, -0.17, 0.0), plate, 6)
		var elbow := PartBuilder.pivot(shoulder, "Elbow", Vector3(0.0, -0.32, 0.0))
		PartBuilder.sphere(elbow, 0.06, Vector3.ZERO, dark)
		PartBuilder.cylinder(elbow, 0.05, 0.045, 0.26, Vector3(0.0, -0.14, 0.0), plate, 6)
		var hand := PartBuilder.pivot(elbow, "Hand", Vector3(0.0, -0.3, 0.0))
		PartBuilder.box(hand, Vector3(0.09, 0.11, 0.09), Vector3.ZERO, dark)
		if side < 0:
			shoulder_l = shoulder
			elbow_l = elbow
		else:
			shoulder_r = shoulder
			elbow_r = elbow
			hand_r = hand

	head = PartBuilder.pivot(spine, "Head", Vector3(0.0, 0.64, 0.0))
	PartBuilder.cylinder(head, 0.12, 0.125, 0.26, Vector3(0.0, 0.12, 0.0), plate, 8)
	PartBuilder.cylinder(head, 0.015, 0.12, 0.17, Vector3(0.0, 0.335, 0.0), plate, 8)
	PartBuilder.box(head, Vector3(0.17, 0.018, 0.03), Vector3(0.0, 0.15, -0.115), void_mat)
	PartBuilder.box(head, Vector3(0.03, 0.2, 0.04), Vector3(0.0, 0.09, -0.12), plate)
	PartBuilder.box(head, Vector3(0.025, 0.03, 0.03), Vector3(0.0, 0.43, 0.0), gold)
	# Plume streaming back from the crown.
	for i in 4:
		PartBuilder.box(head, Vector3(0.05 - i * 0.008, 0.06, 0.12), Vector3(0.0, 0.42 - i * 0.04, 0.06 + i * 0.07), cloth, Vector3(0.5 + i * 0.25, 0.0, 0.0))

	goblet = PartBuilder.pivot(hand_r, "Goblet", Vector3(0.0, -0.06, -0.06))
	PartBuilder.cylinder(goblet, 0.05, 0.03, 0.1, Vector3(0.0, 0.0, 0.0), gold, 6, Vector3(PI * 0.5, 0.0, 0.0))
	goblet.visible = false
