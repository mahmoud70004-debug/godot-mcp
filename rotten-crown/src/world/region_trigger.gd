class_name RegionTrigger
extends Area3D
## Announces a region (title card) the first time the player walks in, and
## reports every entry/exit so the level can blend that region's atmosphere.

@export var region: RegionData
## Show the title card only on the first visit.
@export var once := true

var _triggered := false


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	monitoring = true
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	if region == null or not body.is_in_group("player"):
		return
	GameState.current_region_id = region.id
	Events.region_zone_entered.emit(region)
	if once and _triggered:
		return
	_triggered = true
	Events.region_entered.emit(region)


func _on_body_exited(body: Node3D) -> void:
	if region != null and body.is_in_group("player"):
		Events.region_zone_exited.emit(region)
