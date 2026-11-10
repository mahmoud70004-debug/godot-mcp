class_name RegionTrigger
extends Area3D
## Announces a region (title card) the first time the player walks in, and
## reports every entry/exit so the level can blend that region's atmosphere.
##
## Zones can nest (a village inside the Kingswood). The level lets the most recently
## entered zone win, so entries that happen in the same physics step (spawning,
## loading a save or teleporting straight into a village) are reported together at the
## end of the frame, largest zone first: the smallest, most specific one always wins.

## Entries waiting for the end of the frame (shared by every trigger).
static var _pending: Array[RegionTrigger] = []

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
	if _pending.is_empty():
		_flush_pending.call_deferred()
	_pending.append(self)


func _on_body_exited(body: Node3D) -> void:
	if region == null or not body.is_in_group("player"):
		return
	if _pending.has(self):
		# Left again before the entry was reported: nothing to undo.
		_pending.erase(self)
		return
	Events.region_zone_exited.emit(region)


## Reports the waiting entries, largest zone first (any trigger may run it).
func _flush_pending() -> void:
	var batch := _pending.duplicate()
	_pending.clear()
	batch.sort_custom(func(a: RegionTrigger, b: RegionTrigger) -> bool: return a.zone_volume() > b.zone_volume())
	for trigger: RegionTrigger in batch:
		if is_instance_valid(trigger) and trigger.is_inside_tree():
			trigger._enter()


func _enter() -> void:
	# Already inside this region through an overlapping trigger: no second title card.
	var already_here := GameState.current_region_id == region.id
	GameState.current_region_id = region.id
	Events.region_zone_entered.emit(region)
	if (once and _triggered) or already_here:
		_triggered = true
		return
	_triggered = true
	Events.region_entered.emit(region)


## Volume of the trigger's shape (m3; unknown shapes count as huge, so they go first).
func zone_volume() -> float:
	for child in get_children():
		var cs := child as CollisionShape3D
		if cs == null or cs.shape == null:
			continue
		if cs.shape is BoxShape3D:
			var s := (cs.shape as BoxShape3D).size
			return s.x * s.y * s.z
		if cs.shape is SphereShape3D:
			var r := (cs.shape as SphereShape3D).radius
			return 4.0 / 3.0 * PI * r * r * r
	return INF
