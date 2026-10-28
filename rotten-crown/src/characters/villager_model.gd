class_name VillagerModel
extends HumanoidRig
## A citizen of Valdron on the night of the feast: ordinary, warm, alive.
## (Their proportions are deliberately *correct* - after the curse the same
## silhouettes return stretched and wrong.)

const SKIN := [Color(0.78, 0.6, 0.48), Color(0.66, 0.48, 0.36), Color(0.52, 0.36, 0.26), Color(0.85, 0.7, 0.58)]
# Muted, homespun dyes: the sprite bake lights and contrast-boosts them, so brighter values read as neon.
const CLOTH := [Color(0.4, 0.1, 0.08), Color(0.16, 0.22, 0.36), Color(0.2, 0.3, 0.16), Color(0.44, 0.36, 0.16),
	Color(0.3, 0.18, 0.28), Color(0.46, 0.4, 0.31), Color(0.24, 0.16, 0.1)]
const HAIR := [Color(0.12, 0.08, 0.05), Color(0.35, 0.22, 0.1), Color(0.6, 0.45, 0.2), Color(0.7, 0.7, 0.68)]

@export var seed := 0
@export var wears_dress := false
@export var holds_instrument := false

var _height := 1.0


func _build() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	_height = rng.randf_range(0.88, 1.06)
	var skin := RetroMaterials.flat(SKIN[rng.randi() % SKIN.size()])
	var tunic := RetroMaterials.flat(CLOTH[rng.randi() % CLOTH.size()])
	var trousers := RetroMaterials.flat(CLOTH[rng.randi() % CLOTH.size()].darkened(0.4))
	var hair := RetroMaterials.flat(HAIR[rng.randi() % HAIR.size()])

	hips = PartBuilder.pivot(self, "Hips", Vector3(0.0, _hip_height(), 0.0))
	leg_l = PartBuilder.pivot(hips, "LegL", Vector3(-0.09, 0.0, 0.0))
	leg_r = PartBuilder.pivot(hips, "LegR", Vector3(0.09, 0.0, 0.0))
	for leg in [leg_l, leg_r]:
		PartBuilder.box(leg, Vector3(0.11, 0.86 * _height, 0.12), Vector3(0.0, -0.43 * _height, 0.0), trousers)
		PartBuilder.box(leg, Vector3(0.11, 0.07, 0.2), Vector3(0.0, -0.88 * _height, -0.04), RetroMaterials.flat(Color(0.15, 0.1, 0.07)))
	spine = PartBuilder.pivot(hips, "Spine", Vector3(0.0, 0.05, 0.0))
	if wears_dress:
		PartBuilder.cylinder(hips, 0.16, 0.3, 0.7 * _height, Vector3(0.0, -0.32 * _height, 0.0), tunic, 8)
	PartBuilder.box(spine, Vector3(0.34, 0.5, 0.2), Vector3(0.0, 0.25, 0.0), tunic)
	PartBuilder.box(spine, Vector3(0.36, 0.05, 0.22), Vector3(0.0, 0.02, 0.0), RetroMaterials.flat(Color(0.2, 0.13, 0.08)))
	for side in [-1.0, 1.0]:
		var shoulder := PartBuilder.pivot(spine, "Shoulder", Vector3(side * 0.22, 0.46, 0.0))
		PartBuilder.box(shoulder, Vector3(0.09, 0.3, 0.09), Vector3(0.0, -0.15, 0.0), tunic)
		var elbow := PartBuilder.pivot(shoulder, "Elbow", Vector3(0.0, -0.3, 0.0))
		PartBuilder.box(elbow, Vector3(0.08, 0.26, 0.08), Vector3(0.0, -0.13, 0.0), skin)
		if side < 0:
			shoulder_l = shoulder
			elbow_l = elbow
		else:
			shoulder_r = shoulder
			elbow_r = elbow
			hand_r = PartBuilder.pivot(elbow, "Hand", Vector3(0.0, -0.27, 0.0))
	head = PartBuilder.pivot(spine, "Head", Vector3(0.0, 0.56, 0.0))
	PartBuilder.sphere(head, 0.12, Vector3(0.0, 0.1, 0.0), skin)
	PartBuilder.box(head, Vector3(0.25, 0.08, 0.25), Vector3(0.0, 0.2, 0.02), hair)
	match rng.randi() % 3:
		0:
			PartBuilder.cylinder(head, 0.14, 0.17, 0.08, Vector3(0.0, 0.24, 0.0), tunic, 8)
		1:
			PartBuilder.cylinder(head, 0.0, 0.11, 0.25, Vector3(0.0, 0.34, 0.0), RetroMaterials.flat(CLOTH[rng.randi() % CLOTH.size()]), 6)
		_:
			pass
	if holds_instrument:
		var lute := PartBuilder.pivot(spine, "Lute", Vector3(0.05, 0.25, -0.18))
		PartBuilder.sphere(lute, 0.15, Vector3.ZERO, RetroMaterials.wood())
		PartBuilder.box(lute, Vector3(0.05, 0.4, 0.03), Vector3(0.0, 0.25, 0.0), RetroMaterials.wood(), Vector3(0.0, 0.0, -0.5))
	elif rng.randf() < 0.5:
		PartBuilder.cylinder(hand_r, 0.045, 0.03, 0.1, Vector3(0.0, 0.0, -0.05), RetroMaterials.flat(Color(0.55, 0.45, 0.18)), 6)


func _hip_height() -> float:
	return 0.92 * _height
