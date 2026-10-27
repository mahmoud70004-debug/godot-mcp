extends Node
## Run-wide state of the knight: inventory, equipment, upgrades, story flags.
## Everything here is serialisable through to_dict()/from_dict().

signal equipped_weapon_changed(weapon: WeaponData)
signal stats_changed

const DEFAULT_WEAPON_PATH := "res://data/items/weapons/ceremonial_sword.tres"
const BASE_MAX_HEALTH := 100.0
const BASE_MAX_STAMINA := 100.0

var inventory: Inventory
var equipped_weapon: WeaponData
## weapon id -> upgrade level (upgrades live here, never in the shared .tres).
var weapon_upgrades: Dictionary = {}
## Story / world flags, e.g. "gate_opened": true.
var flags: Dictionary = {}
var discovered_lore: Array[String] = []
var enemies_killed := 0
## Current health carried across scene changes; < 0 means "full".
var player_health := -1.0
var current_scene_path := ""
var current_region_id := ""
## Where the player should appear after loading a save (null = level default).
var pending_player_position: Variant = null


func _ready() -> void:
	new_game()
	Events.enemy_killed.connect(func(_data: EnemyData) -> void: enemies_killed += 1)


func new_game() -> void:
	inventory = Inventory.new()
	inventory.changed.connect(_on_inventory_changed)
	weapon_upgrades.clear()
	flags.clear()
	discovered_lore.clear()
	enemies_killed = 0
	player_health = -1.0
	current_region_id = ""
	pending_player_position = null
	var weapon := load(DEFAULT_WEAPON_PATH) as WeaponData
	if weapon:
		inventory.add_item(weapon)
		equip_weapon(weapon)


# --- Equipment -------------------------------------------------------------

func equip_weapon(weapon: WeaponData) -> void:
	if weapon != null and not inventory.has_item(weapon):
		return
	equipped_weapon = weapon
	equipped_weapon_changed.emit(weapon)
	stats_changed.emit()


func get_weapon_level(weapon: WeaponData) -> int:
	if weapon == null:
		return 0
	return int(weapon_upgrades.get(weapon.id, 0))


func upgrade_weapon(weapon: WeaponData) -> bool:
	var level := get_weapon_level(weapon)
	if weapon == null or level >= weapon.max_upgrade_level:
		return false
	weapon_upgrades[weapon.id] = level + 1
	stats_changed.emit()
	return true


# --- Derived stats ---------------------------------------------------------

func get_attack_damage() -> float:
	if equipped_weapon == null:
		return 4.0
	var multiplier := 1.0
	for relic in _carried_relics():
		multiplier *= relic.damage_multiplier
	return equipped_weapon.get_damage(get_weapon_level(equipped_weapon)) * multiplier


func get_max_health() -> float:
	var bonus := 0.0
	for relic in _carried_relics():
		bonus += relic.max_health_bonus
	return BASE_MAX_HEALTH + bonus


func get_max_stamina() -> float:
	var bonus := 0.0
	for relic in _carried_relics():
		bonus += relic.max_stamina_bonus
	return BASE_MAX_STAMINA + bonus


func _carried_relics() -> Array[RelicData]:
	var relics: Array[RelicData] = []
	for slot in inventory.get_slots():
		if slot.item is RelicData:
			relics.append(slot.item as RelicData)
	return relics


# --- Items -----------------------------------------------------------------

func use_item(item: ItemData) -> bool:
	if item is ConsumableData and inventory.remove_item(item, 1):
		Events.consumable_used.emit(item as ConsumableData)
		return true
	if item is LoreData:
		Events.lore_read_requested.emit(item as LoreData)
		return true
	return false


func discover_lore(lore: LoreData) -> void:
	if lore == null:
		return
	if not discovered_lore.has(lore.id):
		discovered_lore.append(lore.id)
	Events.lore_discovered.emit(lore)


# --- Flags -----------------------------------------------------------------

func set_flag(flag: String, value: Variant = true) -> void:
	flags[flag] = value


func get_flag(flag: String, default: Variant = false) -> Variant:
	return flags.get(flag, default)


# --- Serialisation -----------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"inventory": inventory.to_save_data(),
		"equipped_weapon": equipped_weapon.resource_path if equipped_weapon else "",
		"weapon_upgrades": weapon_upgrades.duplicate(),
		"flags": flags.duplicate(true),
		"discovered_lore": Array(discovered_lore),
		"enemies_killed": enemies_killed,
		"player_health": player_health,
		"current_region_id": current_region_id,
	}


func from_dict(data: Dictionary) -> void:
	new_game()
	inventory.load_save_data(data.get("inventory", []))
	weapon_upgrades = data.get("weapon_upgrades", {})
	flags = data.get("flags", {})
	discovered_lore.clear()
	for id in data.get("discovered_lore", []):
		discovered_lore.append(str(id))
	enemies_killed = int(data.get("enemies_killed", 0))
	player_health = float(data.get("player_health", -1.0))
	current_region_id = str(data.get("current_region_id", ""))
	var weapon_path := str(data.get("equipped_weapon", ""))
	if weapon_path != "" and ResourceLoader.exists(weapon_path):
		equip_weapon(load(weapon_path) as WeaponData)


func _on_inventory_changed() -> void:
	if equipped_weapon != null and not inventory.has_item(equipped_weapon):
		equip_weapon(null)
	stats_changed.emit()
