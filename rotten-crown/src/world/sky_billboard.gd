class_name SkyBillboard
extends MeshInstance3D
## Keeps a sky object (the moon) at a fixed direction and distance from the
## active camera, so it reads as infinitely far away.

@export var direction := Vector3(-0.42, 0.5, -0.755)
@export var distance := 55.0


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam:
		global_position = cam.global_position + direction.normalized() * distance
