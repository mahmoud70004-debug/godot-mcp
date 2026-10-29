class_name SpriteCreatureVisual
extends Node3D
## Drop-in replacement for CreatureRig: shows the baked pixel-art sheet of an enemy.
## Maps the rig calls Enemy makes onto sprite animations and adds a small runtime twitch.

signal death_finished

const WALK_THRESHOLD := 0.3
const DEATH_HOLD := 1.2
const TWITCH_MIN_WAIT := 1.5
const TWITCH_MAX_WAIT := 5.0
const TWITCH_MIN_TIME := 0.06
const TWITCH_MAX_TIME := 0.15

var sprite: PixelSprite3D

var _rng := RandomNumberGenerator.new()
var _alive := true
var _moving := false
var _busy := false
var _twitch_intensity := 1.0
var _twitch_wait := 3.0
var _twitch_left := 0.0
var _walk_ref_speed := 2.0
var _hold_anim: StringName = &"idle"
var _move_scale := 1.0
var _missing_sheet := false


func _init() -> void:
	_rng.randomize()
	sprite = PixelSprite3D.new()
	sprite.name = "Sprite"
	add_child(sprite)
	sprite.animation_finished.connect(_on_animation_finished)
	_twitch_wait = _rng.randf_range(TWITCH_MIN_WAIT, TWITCH_MAX_WAIT)


func setup(data: EnemyData) -> void:
	_missing_sheet = data.sprite_sheet == null
	if _missing_sheet:
		push_error("SpriteCreatureVisual: no sprite_sheet in %s" % data.resource_path)
	sprite.sheet = data.sprite_sheet
	sprite.tint = data.sprite_tint
	_twitch_intensity = data.twitch_intensity
	_walk_ref_speed = maxf(data.chase_speed, 0.5)
	sprite.play(&"idle", true)


func set_look_target(_target: Node3D) -> void:
	pass


func set_move_speed(speed: float) -> void:
	_moving = speed > WALK_THRESHOLD
	if _moving:
		_move_scale = clampf(speed / _walk_ref_speed, 0.5, 1.6)
	if _busy or not _alive:
		return
	_play_locomotion()


func play_windup(duration: float) -> void:
	_start_one_shot(&"windup", duration)


func play_strike() -> void:
	_start_one_shot(&"strike", 0.0)


func play_recover() -> void:
	_busy = false
	if _alive:
		_play_locomotion()


func play_stagger() -> void:
	_start_one_shot(&"stagger", 0.0)
	_twitch_left = TWITCH_MAX_TIME
	_apply_twitch(2.5)


func flash() -> void:
	sprite.flash()


## Plays the death animation. Await the returned signal to know when it settled.
func play_death() -> Signal:
	_alive = false
	_busy = true
	_reset_twitch()
	sprite.speed_scale = 1.0
	if _missing_sheet:
		death_finished.emit.call_deferred()
		return death_finished
	sprite.play(&"death", true)
	return death_finished


func _process(delta: float) -> void:
	if not _alive:
		return
	if _twitch_left > 0.0:
		_twitch_left -= delta
		if _twitch_left <= 0.0:
			_reset_twitch()
		return
	_twitch_wait -= delta
	if _twitch_wait <= 0.0:
		_twitch_wait = _rng.randf_range(TWITCH_MIN_WAIT, TWITCH_MAX_WAIT)
		_twitch_left = _rng.randf_range(TWITCH_MIN_TIME, TWITCH_MAX_TIME)
		_apply_twitch(1.0)


func _apply_twitch(strength: float) -> void:
	# Screen-space jitter (sprite pixels): rotation/position are invisible under BILLBOARD_FIXED_Y.
	var k := strength * _twitch_intensity
	sprite.extra_offset = Vector2(_rng.randf_range(-3.0, 3.0), _rng.randf_range(-2.0, 1.0)) * k


func _reset_twitch() -> void:
	sprite.extra_offset = Vector2.ZERO
	_twitch_left = 0.0


func _play_locomotion() -> void:
	if _moving:
		sprite.speed_scale = _move_scale
		sprite.play(&"walk")
	else:
		sprite.play(&"idle")
		sprite.speed_scale = 1.0


func _start_one_shot(anim_name: StringName, duration: float) -> void:
	if not _alive:
		return
	_busy = true
	_hold_anim = anim_name
	var scale_factor := 1.0
	var info: Dictionary = {}
	if sprite.sheet != null:
		info = sprite.sheet.anims.get(anim_name, {})
	if duration > 0.0 and not info.is_empty():
		var natural := float(info["frames"]) / maxf(float(info["fps"]), 0.001)
		scale_factor = natural / duration
	sprite.speed_scale = scale_factor
	sprite.play(anim_name, true)


func _on_animation_finished(anim_name: StringName) -> void:
	if anim_name == &"death":
		await get_tree().create_timer(DEATH_HOLD).timeout
		death_finished.emit()
	elif anim_name == &"stagger" and _alive:
		# Stagger ends the interruption; windup/strike hold until Enemy calls play_recover.
		_busy = false
		_play_locomotion()
