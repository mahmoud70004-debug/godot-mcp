class_name RelicData
extends ItemData
## Cursed / holy trinkets. Their bonuses apply passively while carried.

@export var max_health_bonus := 0.0
@export var max_stamina_bonus := 0.0
@export var damage_multiplier := 1.0


func _init() -> void:
	category = Category.RELIC


func get_stat_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	if max_health_bonus != 0.0:
		lines.append("Max health %+d" % roundi(max_health_bonus))
	if max_stamina_bonus != 0.0:
		lines.append("Max stamina %+d" % roundi(max_stamina_bonus))
	if not is_equal_approx(damage_multiplier, 1.0):
		lines.append("Damage x%.2f" % damage_multiplier)
	return lines
