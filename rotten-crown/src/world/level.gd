class_name Level
extends Node3D
## Root script for every playable level.

@export var region: RegionData
@export var player: Player
@export var environment: WorldEnvironment
@export var kill_height := -25.0
## Announce the region as soon as the level starts (otherwise use RegionTrigger).
@export var announce_on_start := false


func _ready() -> void:
	GameState.current_scene_path = scene_file_path
	if region:
		GameState.current_region_id = region.id
		_apply_region_atmosphere()
		if announce_on_start:
			_announce_region.call_deferred()
	if player and GameState.pending_player_position is Vector3:
		player.global_position = GameState.pending_player_position
		GameState.pending_player_position = null


func _announce_region() -> void:
	Events.region_entered.emit(region)


func _physics_process(_delta: float) -> void:
	if player and player.global_position.y < kill_height:
		player.kill()


func _apply_region_atmosphere() -> void:
	if environment == null or environment.environment == null:
		return
	var env := environment.environment
	env.fog_light_color = region.fog_color
	env.fog_density = region.fog_density
	env.ambient_light_color = region.ambient_color
