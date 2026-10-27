class_name Interactable
extends Area3D
## Anything the player can look at and use with the interact button.
## Lives on physics layer 4 ("interactables"); the player's ray detects it.

signal interacted(by: Node)

@export var prompt_text := "Examine"
@export var enabled := true


func _ready() -> void:
	collision_layer = 8
	collision_mask = 0
	monitoring = false
	monitorable = true


func get_prompt() -> String:
	return prompt_text


func can_interact(_by: Node) -> bool:
	return enabled


func interact(by: Node) -> void:
	interacted.emit(by)
