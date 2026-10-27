class_name ItemData
extends Resource
## Base definition of anything the knight can carry.

enum Category { WEAPON, CONSUMABLE, RELIC, LORE, KEY, MATERIAL }

@export var id := ""
@export var display_name := ""
@export_multiline var description := ""
@export var icon: Texture2D
@export var category: Category = Category.MATERIAL
@export var stackable := false
@export_range(1, 99) var max_stack := 1
## Placeholder colour for icons / world models until real art exists.
@export var tint := Color(0.7, 0.7, 0.7)


func get_max_stack() -> int:
	return max_stack if stackable else 1


func get_category_name() -> String:
	return Category.keys()[category].capitalize()


## Extra stat lines shown in the inventory detail panel.
func get_stat_lines() -> PackedStringArray:
	return PackedStringArray()
