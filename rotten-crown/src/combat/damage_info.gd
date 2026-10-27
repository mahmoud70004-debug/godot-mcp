class_name DamageInfo
extends RefCounted
## A single hit travelling from a HitboxComponent to a HurtboxComponent.

var amount: float
var source: Node3D
var knockback: float
## Set by the receiver when the hit was (partially) blocked.
var blocked := false


func _init(p_amount: float = 0.0, p_source: Node3D = null, p_knockback: float = 0.0) -> void:
	amount = p_amount
	source = p_source
	knockback = p_knockback


## Horizontal direction from the source towards [param target], or ZERO.
func direction_to(target: Node3D) -> Vector3:
	if source == null or target == null:
		return Vector3.ZERO
	var dir := target.global_position - source.global_position
	dir.y = 0.0
	return dir.normalized() if dir.length_squared() > 0.0001 else Vector3.ZERO
