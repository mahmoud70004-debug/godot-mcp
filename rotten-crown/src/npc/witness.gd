class_name Witness
extends Node3D
## A harmless thing that saw what happened (Phase 3d). It stands still, twitches and
## always faces the knight; faint static hangs around it. When the knight comes close
## and looks at it (or, for the one beside him at the wake-up, once his first thoughts
## are over) it speaks one ENTITY line through DialogueUI, then flickers out of existence.
## It is never seen again once heard (GameState flag "witness_<id>").

enum Phase { WAITING, SPEAKING, GONE }

const STATIC_LOOP := "res://assets/audio/sfx/static_loop.wav"
const LOOK_DOT := 0.75
const TWITCH_MIN_WAIT := 0.8
const TWITCH_MAX_WAIT := 3.5

@export var id := ""
@export var sheet: SpriteSheetData
@export var tint := Color(0.78, 0.78, 0.76)
@export var line: DialogueLine
## Speaks right after the knight's wake-up thoughts instead of waiting to be approached.
@export var speak_after_wake := false
@export var trigger_radius := 4.5
## Sprite size multiplier (the Witnesses are a little too tall).
@export var height_scale := 1.0

var _phase := Phase.WAITING
var _sprite: PixelSprite3D
var _hum: AudioStreamPlayer3D
var _rng := RandomNumberGenerator.new()
var _twitch_wait := 1.0
var _twitch_left := 0.0
var _waiting_for_wake := false


func _ready() -> void:
	if id != "" and GameState.get_flag("witness_" + id):
		queue_free()
		return
	_rng.randomize()
	_snap_to_ground.call_deferred()
	_sprite = PixelSprite3D.new()
	_sprite.name = "Sprite"
	_sprite.sheet = sheet
	_sprite.tint = tint
	# Always the front view: it turns its face to follow you, not its body.
	_sprite.fixed_direction = 0
	_sprite.scale = Vector3.ONE * height_scale
	add_child(_sprite)
	if sheet == null:
		push_warning("Witness %s has no sprite sheet" % id)
	else:
		_sprite.play(&"idle", true)
	_hum = AudioStreamPlayer3D.new()
	_hum.bus = &"SFX"
	_hum.volume_db = -20.0
	_hum.unit_size = 2.0
	_hum.max_distance = 14.0
	_hum.position = Vector3.UP * 1.4
	if ResourceLoader.exists(STATIC_LOOP):
		_hum.stream = load(STATIC_LOOP) as AudioStream
		_hum.autoplay = true
	add_child(_hum)
	# Level clears the flag in its own _ready, which runs after ours.
	_waiting_for_wake = speak_after_wake and GameState.get_flag("waking_up")
	if _waiting_for_wake:
		Events.dialogue_finished.connect(_on_dialogue_finished)


func _process(delta: float) -> void:
	if _phase == Phase.GONE:
		return
	_twitch(delta)
	if _phase == Phase.WAITING and not _waiting_for_wake and _player_close_and_looking():
		_speak()


## The knight's wake-up thoughts are over (then: our own line is over).
func _on_dialogue_finished() -> void:
	if _phase == Phase.WAITING and _waiting_for_wake:
		_waiting_for_wake = false
		_speak.call_deferred()
	elif _phase == Phase.SPEAKING:
		_vanish()


func _speak() -> void:
	if _phase != Phase.WAITING or line == null:
		return
	_phase = Phase.SPEAKING
	if id != "":
		GameState.set_flag("witness_" + id)
	if sheet != null:
		_sprite.play(&"speak", true)
	_hum.volume_db = -12.0
	if not Events.dialogue_finished.is_connected(_on_dialogue_finished):
		Events.dialogue_finished.connect(_on_dialogue_finished)
	Events.dialogue_requested.emit([line])


## It does not walk away: it is simply no longer there, between two flickers.
func _vanish() -> void:
	_phase = Phase.GONE
	var tw := create_tween()
	for i in 5:
		tw.tween_callback(_sprite.set_visible.bind(i % 2 == 1))
		tw.tween_interval(_rng.randf_range(0.04, 0.12))
	tw.tween_callback(queue_free)


## Uncanny stillness broken by sudden small jerks of the whole figure.
func _twitch(delta: float) -> void:
	if _twitch_left > 0.0:
		_twitch_left -= delta
		if _twitch_left <= 0.0:
			_sprite.extra_offset = Vector2.ZERO
		return
	_twitch_wait -= delta
	if _twitch_wait <= 0.0:
		var strength := 2.0 if _phase == Phase.SPEAKING else 1.0
		_sprite.extra_offset = Vector2(_rng.randi_range(-2, 2), _rng.randi_range(-1, 1)) * strength
		_twitch_left = _rng.randf_range(0.05, 0.14)
		_twitch_wait = _rng.randf_range(TWITCH_MIN_WAIT, TWITCH_MAX_WAIT) / strength


func _player_close_and_looking() -> bool:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var cam := get_viewport().get_camera_3d()
	if player == null or cam == null:
		return false
	if player.global_position.distance_to(global_position) > trigger_radius:
		return false
	var to_me := (global_position + Vector3.UP * 1.2 - cam.global_position).normalized()
	return (-cam.global_basis.z).dot(to_me) > LOOK_DOT


func _snap_to_ground() -> void:
	var from := global_position + Vector3.UP * 4.0
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 12.0, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		global_position.y = (hit.position as Vector3).y
