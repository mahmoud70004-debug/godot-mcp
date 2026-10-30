class_name OverworldPopulator
extends Node
## Turns the baked world's markers (contract C9) into live content: enemies at
## Spawn_Enemy_*, items at Pickup_* / Lore_*, region triggers at Trigger.
## Content tables live here so the bake stays pure scenery.

const HOLLOW_SCENE := preload("res://src/enemies/hollow.tscn")
const PICKUP_SCENE := preload("res://src/interaction/item_pickup.tscn")
const REGIONS := {
	"Thornfield": "res://data/regions/thornfield.tres",
	"Hollowmere": "res://data/regions/hollowmere.tres",
	"WhisperingWood": "res://data/regions/whispering_wood.tres",
}
const ENEMIES := {
	"Thornfield": ["res://data/enemies/steeple.tres", "res://data/enemies/grinner.tres"],
	"Hollowmere": ["res://data/enemies/grinner.tres", "res://data/enemies/steeple.tres", "res://data/enemies/bent.tres"],
	"WhisperingWood": ["res://data/enemies/grinner.tres", "res://data/enemies/steeple.tres", "res://data/enemies/bent.tres"],
}
const PICKUPS := ["res://data/items/consumables/grave_moss.tres", "res://data/items/consumables/feast_wine.tres"]
## region -> lore items, in marker order (Lore_1, Lore_2...). Missing files are skipped.
const LORE := {
	"Thornfield": ["res://data/items/lore/farmers_ledger.tres"],
	"Hollowmere": ["res://data/items/lore/harvest_hymn.tres", "res://data/items/lore/chapel_confession.tres"],
	"WhisperingWood": ["res://data/items/lore/hunters_warning.tres"],
}

## Enemies and witnesses further than this from the player (and idle) stop processing.
const CULL_DISTANCE := 45.0
const CULL_HYSTERESIS := 5.0
const CULL_INTERVAL := 0.5

@export var world: Node3D
@export var seed := 99

var _cull_timer: Timer


func _ready() -> void:
	if world == null:
		return
	_cull_timer = Timer.new()
	_cull_timer.wait_time = CULL_INTERVAL
	_cull_timer.timeout.connect(_cull_far_actors)
	add_child(_cull_timer)
	_cull_timer.start()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for region_name in REGIONS.keys():
		var region := world.get_node_or_null(NodePath(region_name)) as Node3D
		if region == null:
			continue
		var enemy_i := 0
		for node in region.find_children("*", "Marker3D", true, false):
			var marker := node as Marker3D
			var id := String(marker.name)
			if id.begins_with("Spawn_Enemy"):
				var pool: Array = ENEMIES.get(region_name, [])
				if not pool.is_empty():
					_spawn_enemy(marker, load(pool[enemy_i % pool.size()]) as EnemyData, rng)
					enemy_i += 1
			elif id.begins_with("Pickup"):
				_spawn_pickup(marker, load(PICKUPS[rng.randi() % PICKUPS.size()]) as ItemData)
			elif id.begins_with("Lore"):
				var list: Array = LORE.get(region_name, [])
				var idx := id.get_slice("_", 1).to_int() - 1
				if idx >= 0 and idx < list.size() and ResourceLoader.exists(list[idx]):
					_spawn_pickup(marker, load(list[idx]) as ItemData)
			elif id == "Trigger":
				_spawn_trigger(marker, load(REGIONS[region_name]) as RegionData)


## One cheap distance sweep for every actor; the actors park themselves (Enemy.set_far / Witness.set_far).
func _cull_far_actors() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var origin := player.global_position
	var far_sq := CULL_DISTANCE * CULL_DISTANCE
	var near_sq := (CULL_DISTANCE - CULL_HYSTERESIS) * (CULL_DISTANCE - CULL_HYSTERESIS)
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Enemy
		var d_sq := origin.distance_squared_to(enemy.global_position)
		if d_sq > far_sq:
			enemy.set_far(true)
		elif d_sq < near_sq:
			enemy.set_far(false)
	for node in get_tree().get_nodes_in_group("witnesses"):
		var witness := node as Witness
		var d_sq := origin.distance_squared_to(witness.global_position)
		if d_sq > far_sq:
			witness.set_far(true)
		elif d_sq < near_sq:
			witness.set_far(false)


func _spawn_enemy(marker: Marker3D, data: EnemyData, rng: RandomNumberGenerator) -> void:
	var enemy := HOLLOW_SCENE.instantiate() as Enemy
	enemy.data = data
	enemy.start_dormant = rng.randf() < 0.5
	add_child(enemy)
	enemy.global_position = marker.global_position + Vector3.UP * 0.1
	enemy.rotation.y = rng.randf() * TAU
	enemy.reset_physics_interpolation()


func _spawn_pickup(marker: Marker3D, item: ItemData) -> void:
	if item == null:
		return
	var pickup := PICKUP_SCENE.instantiate() as ItemPickup
	pickup.item = item
	add_child(pickup)
	pickup.global_position = marker.global_position + Vector3.UP * 0.35


func _spawn_trigger(marker: Marker3D, region: RegionData) -> void:
	var trigger := RegionTrigger.new()
	trigger.region = region
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = float(marker.get_meta("radius", 40.0))
	shape.shape = sphere
	trigger.add_child(shape)
	add_child(trigger)
	trigger.global_position = marker.global_position
