extends Node
## Global signal bus. Systems that should not know about each other
## (player, HUD, enemies, world) communicate through these signals.

# Player
signal player_health_changed(current: float, maximum: float)
signal player_stamina_changed(current: float, maximum: float)
signal player_damaged(amount: float)
signal player_died
## The knight wakes in the meadow after the prologue (HUD plays the eyelids).
signal wake_up_started(duration: float)

# Input routed from the touch layer (degrees of yaw/pitch).
signal look_input(delta_degrees: Vector2)

# Interaction & items
signal interaction_prompt_changed(text: String)
signal item_picked_up(item: ItemData, quantity: int)
signal consumable_used(item: ConsumableData)
signal lore_discovered(lore: LoreData)
signal lore_read_requested(lore: LoreData)

# World
signal enemy_killed(enemy_data: EnemyData)
signal region_entered(region: RegionData)
## Every time the player walks into / out of a RegionTrigger (fog, rain follow these).
signal region_zone_entered(region: RegionData)
signal region_zone_exited(region: RegionData)

# Dialogue (C13): Array of DialogueLine; the Dialogue autoload shows them in order.
signal dialogue_requested(lines: Array)
signal dialogue_finished

# UI
signal message_requested(text: String, duration: float)
signal menu_state_changed(is_open: bool)
## Graphics quality changed (0 Low, 1 Medium, 2 High).
signal quality_changed(level: int)


func show_message(text: String, duration: float = 2.5) -> void:
	message_requested.emit(text, duration)
