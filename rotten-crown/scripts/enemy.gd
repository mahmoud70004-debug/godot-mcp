extends Node3D

var health := 3
var origin_y := 0.0
var clock := 0.0

func _process(delta: float) -> void:
	clock += delta
	position.y = origin_y + sin(clock * 1.6) * 0.035
	rotation.z = sin(clock * 1.1) * 0.035

func take_hit() -> void:
	health -= 1
	if health <= 0:
		queue_free()
