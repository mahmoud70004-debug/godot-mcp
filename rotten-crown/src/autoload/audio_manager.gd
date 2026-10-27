extends Node
## Pooled one-shot SFX (2D and 3D) and a cross-fading music player.

const SFX_POOL_SIZE := 8
const SFX_3D_POOL_SIZE := 12

var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_3d_players: Array[AudioStreamPlayer3D] = []
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _active_music: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in SFX_POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = &"SFX"
		add_child(p)
		_sfx_players.append(p)
	for i in SFX_3D_POOL_SIZE:
		var p3 := AudioStreamPlayer3D.new()
		p3.bus = &"SFX"
		p3.max_distance = 30.0
		p3.unit_size = 4.0
		add_child(p3)
		_sfx_3d_players.append(p3)
	_music_a = AudioStreamPlayer.new()
	_music_b = AudioStreamPlayer.new()
	for m in [_music_a, _music_b]:
		m.bus = &"Music"
		add_child(m)
	_active_music = _music_a


func play_sfx(stream: AudioStream, volume_db: float = 0.0, pitch_variation: float = 0.08) -> void:
	if stream == null:
		return
	var player := _free_player(_sfx_players) as AudioStreamPlayer
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = 1.0 + randf_range(-pitch_variation, pitch_variation)
	player.play()


func play_sfx_3d(stream: AudioStream, position: Vector3, volume_db: float = 0.0, pitch_variation: float = 0.08) -> void:
	if stream == null:
		return
	var player := _free_player(_sfx_3d_players) as AudioStreamPlayer3D
	player.stream = stream
	player.global_position = position
	player.volume_db = volume_db
	player.pitch_scale = 1.0 + randf_range(-pitch_variation, pitch_variation)
	player.play()


func play_music(stream: AudioStream, fade_time: float = 2.0) -> void:
	if _active_music.stream == stream and _active_music.playing:
		return
	var old := _active_music
	var incoming := _music_b if old == _music_a else _music_a
	incoming.stream = stream
	incoming.volume_db = -60.0
	if stream:
		incoming.play()
	var tween := create_tween().set_parallel(true)
	tween.tween_property(incoming, "volume_db", 0.0, fade_time)
	tween.tween_property(old, "volume_db", -60.0, fade_time)
	tween.chain().tween_callback(old.stop)
	_active_music = incoming


func stop_music(fade_time: float = 2.0) -> void:
	var tween := create_tween()
	tween.tween_property(_active_music, "volume_db", -60.0, fade_time)
	tween.tween_callback(_active_music.stop)


func _free_player(pool: Array) -> Node:
	for p in pool:
		if not p.playing:
			return p
	return pool[0]
