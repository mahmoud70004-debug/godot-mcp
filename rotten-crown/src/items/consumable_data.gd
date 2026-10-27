class_name ConsumableData
extends ItemData

@export var heal_amount := 30.0
@export var stamina_restore := 0.0
@export var use_message := ""


func _init() -> void:
	category = Category.CONSUMABLE
	stackable = true
	max_stack = 9


func get_stat_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	if heal_amount > 0.0:
		lines.append("Restores %d health" % roundi(heal_amount))
	if stamina_restore > 0.0:
		lines.append("Restores %d stamina" % roundi(stamina_restore))
	return lines
