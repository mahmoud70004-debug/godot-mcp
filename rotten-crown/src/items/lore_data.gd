class_name LoreData
extends ItemData
## Notes, letters and inscriptions that reveal what happened to Valdron.

@export var author := ""
@export_multiline var lore_text := ""
@export var region_id := ""


func _init() -> void:
	category = Category.LORE
