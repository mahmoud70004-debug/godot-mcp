class_name WeaponData
extends ItemData
## A melee weapon. Upgrade levels are stored per-run in GameState.

enum WeaponType { SWORD, AXE, MACE, SPEAR }

@export var weapon_type: WeaponType = WeaponType.SWORD
@export var damage := 18.0
## Seconds for a full swing (wind-up + strike + recovery).
@export var attack_duration := 0.6
@export var stamina_cost := 18.0
## Hitbox depth in metres.
@export var reach := 1.6
@export var knockback := 2.5
## Fraction of damage absorbed while blocking.
@export_range(0.0, 1.0) var block_reduction := 0.6
@export var max_upgrade_level := 3
@export var damage_per_upgrade := 5.0


func _init() -> void:
	category = Category.WEAPON


func get_damage(upgrade_level: int = 0) -> float:
	return damage + damage_per_upgrade * upgrade_level


func get_stat_lines() -> PackedStringArray:
	return PackedStringArray([
		"Damage %d" % roundi(damage),
		"Speed %.1fs" % attack_duration,
		"Stamina %d" % roundi(stamina_cost),
		"Guard %d%%" % roundi(block_reduction * 100.0),
	])
