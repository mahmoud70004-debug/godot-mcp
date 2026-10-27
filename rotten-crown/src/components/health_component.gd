class_name HealthComponent
extends Node
## Health pool shared by the player, creatures and destructible props.

signal health_changed(current: float, maximum: float)
signal damaged(info: DamageInfo)
signal healed(amount: float)
signal died

@export var max_health := 100.0

var current_health := 0.0
var is_dead := false
var invulnerable := false


func _ready() -> void:
	current_health = max_health


func take_damage(info: DamageInfo) -> void:
	if is_dead or invulnerable or info == null:
		return
	current_health = maxf(current_health - info.amount, 0.0)
	damaged.emit(info)
	health_changed.emit(current_health, max_health)
	if current_health <= 0.0:
		is_dead = true
		died.emit()


func heal(amount: float) -> void:
	if is_dead or amount <= 0.0:
		return
	current_health = minf(current_health + amount, max_health)
	healed.emit(amount)
	health_changed.emit(current_health, max_health)


func set_max_health(value: float, refill: bool = false) -> void:
	max_health = maxf(value, 1.0)
	current_health = max_health if refill else minf(current_health, max_health)
	health_changed.emit(current_health, max_health)


func set_current_health(value: float) -> void:
	current_health = clampf(value, 0.0, max_health)
	health_changed.emit(current_health, max_health)


func get_ratio() -> float:
	return current_health / max_health if max_health > 0.0 else 0.0
