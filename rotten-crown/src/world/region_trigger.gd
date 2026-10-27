class_name RegionTrigger
extends Area3D
## Announces a region (title card) the first time the player walks in.

@export var region: RegionData
@export var once := true

var _triggered := false


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	monitoring = true
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if region == null or (once and _triggered) or not body.is_in_group("player"):
		return
	_triggered = true
	GameState.current_region_id = region.id
	Events.region_entered.emit(region)
