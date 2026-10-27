class_name HurtboxComponent
extends Area3D
## Receives hits. Optionally lets its owner modify the hit first (blocking).

signal hit_received(info: DamageInfo)

@export var health: HealthComponent

## Callable(info: DamageInfo) -> DamageInfo, e.g. the player's block logic.
var damage_modifier: Callable


func _ready() -> void:
	monitoring = false
	monitorable = true


func receive_hit(info: DamageInfo) -> void:
	if damage_modifier.is_valid():
		info = damage_modifier.call(info)
	hit_received.emit(info)
	if health and info.amount > 0.0:
		health.take_damage(info)
