extends Node
## Music with cross-fades, a looping ambience track and pooled sound effects.

var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _amb: AudioStreamPlayer
var _sfx: Array[AudioStreamPlayer] = []
var _current_music := ""
var _current_amb := ""
var _cache := {}
var _voice: AudioStreamPlayer      # dialogue voices: one syllable at a time, never cut by sfx
var _music_bus := 0
var _duck_tween: Tween
const VOWELS := ["a", "e", "i", "o", "u"]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_music_a = _player()
	_music_b = _player()
	_amb = _player()
	for i in 6:
		_sfx.append(_player())
	_voice = _player()
	# music and ambience go through their own bus so dialogue can duck them smoothly
	AudioServer.add_bus()
	_music_bus = AudioServer.bus_count - 1
	AudioServer.set_bus_name(_music_bus, "Music")
	AudioServer.set_bus_send(_music_bus, "Master")
	for p in [_music_a, _music_b, _amb]:
		p.bus = "Music"
	# preload the small sounds so the first line of dialogue never stutters (web)
	for v in ["man", "deep", "woman", "child", "old", "oldwoman"]:
		for vw in VOWELS:
			_stream("voice_%s_%s" % [v, vw], false)
	for n in ["blip", "select", "page", "discover", "reveal", "clue", "pickup"]:
		_stream(n, false)


func _player() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	add_child(p)
	return p


func _stream(name: String, loop: bool) -> AudioStream:
	var key := name + str(loop)
	if _cache.has(key):
		return _cache[key]
	var path := "res://assets/audio/%s.wav" % name
	if not ResourceLoader.exists(path):
		return null
	var s: AudioStreamWAV = load(path).duplicate()
	if loop:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = int(s.get_length() * s.mix_rate)
	_cache[key] = s
	return s


func sfx(name: String, pitch := 1.0) -> void:
	var s := _stream(name, false)
	if s == null:
		return
	for p in _sfx:
		if not p.playing:
			p.stream = s
			p.pitch_scale = pitch
			p.volume_db = linear_to_db(max(0.001, Game.settings["sfx"]))
			p.play()
			return


## One spoken syllable of a character's voice (see Story.voice_of).
func voice(kind: String, letter: String, pitch := 1.0) -> void:
	var vw: String = VOWELS[absi(letter.unicode_at(0)) % VOWELS.size()] if letter != "" else "a"
	var s := _stream("voice_%s_%s" % [kind, vw], false)
	if s == null:
		return
	_voice.stream = s
	_voice.pitch_scale = pitch * randf_range(0.96, 1.05)
	_voice.volume_db = linear_to_db(max(0.001, Game.settings["sfx"] * 0.75))
	_voice.play()


## Lowers music and ambience while people talk, and brings them back after.
func duck(on: bool) -> void:
	if _duck_tween:
		_duck_tween.kill()
	_duck_tween = create_tween()
	_duck_tween.tween_method(func(v): AudioServer.set_bus_volume_db(_music_bus, v),
		AudioServer.get_bus_volume_db(_music_bus), -7.0 if on else 0.0, 0.45 if on else 0.9)


func current_music() -> String:
	return _current_music


## Short vibration on phones (when enabled in the settings).
func buzz(ms := 30) -> void:
	if Game.settings.get("vibrate", true) and (OS.has_feature("mobile") or OS.has_feature("android")):
		Input.vibrate_handheld(ms)


func music(name: String) -> void:
	if not Game.settings.get("music_on", true):
		name = ""
	if name == _current_music:
		return
	_current_music = name
	var old := _music_a if _music_a.playing else _music_b
	var new := _music_b if old == _music_a else _music_a
	if old.playing:
		var tw := create_tween()
		tw.tween_property(old, "volume_db", -60.0, 1.2)
		tw.tween_callback(old.stop)
	if name == "":
		return
	new.stream = _stream("music_" + name, true)
	if new.stream == null:
		return
	new.volume_db = -60.0
	new.play()
	var tw2 := create_tween()
	tw2.tween_property(new, "volume_db", linear_to_db(max(0.001, Game.settings["music"])), 1.5)


func ambience(name: String) -> void:
	if name == _current_amb:
		return
	_current_amb = name
	if name == "":
		_amb.stop()
		return
	_amb.stream = _stream("amb_" + name, true)
	_amb.volume_db = linear_to_db(max(0.001, Game.settings["sfx"] * 0.45))
	_amb.play()


func refresh_volumes() -> void:
	for p in [_music_a, _music_b]:
		if p.playing:
			p.volume_db = linear_to_db(max(0.001, Game.settings["music"]))
	if _amb.playing:
		_amb.volume_db = linear_to_db(max(0.001, Game.settings["sfx"] * 0.45))
