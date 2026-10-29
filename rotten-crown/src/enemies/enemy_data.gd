class_name EnemyData
extends Resource
## Stats and behaviour flags for one kind of transformed creature.

@export var id := ""
@export var display_name := ""
@export_multiline var bestiary_entry := ""

@export_group("Vitals")
@export var max_health := 60.0
## A single hit at least this strong interrupts the creature.
@export var stagger_threshold := 15.0
@export var stagger_duration := 0.6
@export_range(0.0, 1.0) var knockback_resistance := 0.3

@export_group("Movement")
@export var chase_speed := 2.2
@export var acceleration := 6.0
## How quickly the body turns towards the player (higher = snappier).
@export var turn_speed := 4.0

@export_group("Senses")
@export var detection_range := 12.0
@export var lose_interest_range := 22.0
## When dormant, the creature ignores the player until this close (or hit).
@export var dormant_wake_range := 5.0
## Moves only while the player is NOT looking at it.
@export var freezes_when_watched := false

@export_group("Attack")
@export var damage := 12.0
@export var knockback := 3.0
@export var attack_range := 1.7
## Long, readable tells instead of cheap surprise.
@export var attack_windup := 0.75
@export var attack_active_time := 0.25
@export var attack_recovery := 0.9
@export var attack_cooldown := 1.0
@export var lunge_speed := 2.8

@export_group("Uncanny")
@export var twitch_intensity := 1.0
@export var head_tilt_degrees := 22.0
@export var body_scale := Vector3.ONE

@export_group("Visual")
@export var sprite_sheet: SpriteSheetData
## Colour multiplier for the sprite (the baked sheets are lit for daylight review).
@export var sprite_tint := Color(0.72, 0.72, 0.7)

@export_group("Loot")
@export var drop_item: ItemData
@export_range(0.0, 1.0) var drop_chance := 0.0
