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
var _duck := 1.0                  # 1 = full, lower while people talk (no extra buses: web samples)
var _duck_tween: Tween
var _fade := {}                   # player -> 0..1 crossfade level
var _unlocked := false            # browsers only allow sound after the first touch / click


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_music_a = _player()
	_music_b = _player()
	_amb = _player()
	for i in 6:
		_sfx.append(_player())
	_voice = _player()
	# preload the small sounds so the first line of dialogue never stutters (web)
	for i in 8:
		_stream("dlg_tick_%d" % i, false)
	for n in ["dlg_open", "dlg_next", "dlg_close", "blip", "select", "discover", "reveal", "clue", "pickup"]:
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


## Dialogue sound design: a soft pentatonic click per few letters. The notes walk up
## and down the scale a step at a time (driven by the letters), so a line sounds like
## a quiet little melody; each kind of voice sits higher or lower.
const VOICE_PITCH := {"child": 1.26, "woman": 1.12, "oldwoman": 1.06, "man": 1.0, "old": 0.89, "deep": 0.84}
var _tick_i := 3


func voice(kind: String, letter: String, _pitch := 1.0) -> void:
	var code := letter.unicode_at(0) if letter != "" else 0
	_tick_i = clampi(_tick_i + [-1, 0, 1, 1, -1, 2, -2][code % 7], 0, 7)
	var s := _stream("dlg_tick_%d" % _tick_i, false)
	if s == null:
		return
	_voice.stream = s
	_voice.pitch_scale = float(VOICE_PITCH.get(kind, 1.0))
	_voice.volume_db = linear_to_db(max(0.001, Game.settings["sfx"] * 0.8))
	_voice.play()


## Start of a conversation: the melody starts from the middle of the scale.
func dialogue_open() -> void:
	_tick_i = 3
	sfx("dlg_open")


## Lowers music and ambience while people talk, and brings them back after.
func duck(on: bool) -> void:
	if _duck_tween:
		_duck_tween.kill()
	_duck_tween = create_tween()
	_duck_tween.tween_property(self, "_duck", 0.45 if on else 1.0, 0.45 if on else 0.9)


func is_ducked() -> bool:
	return _duck < 0.9


func _process(_delta: float) -> void:
	var m := float(Game.settings["music"])
	for p in [_music_a, _music_b]:
		if p.playing:
			p.volume_db = linear_to_db(max(0.0001, m * float(_fade.get(p, 1.0)) * _duck))
	if _amb.playing:
		_amb.volume_db = linear_to_db(max(0.0001, float(Game.settings["sfx"]) * 0.45 * lerpf(1.0, _duck, 0.6)))


## Web: the first touch or click unlocks audio; restart what should already be playing.
func _input(event: InputEvent) -> void:
	if _unlocked:
		return
	if event is InputEventScreenTouch or event is InputEventMouseButton or event is InputEventKey:
		_unlocked = true
		if OS.has_feature("web"):
			call_deferred("_restart_after_unlock")


func _restart_after_unlock() -> void:
	for p in [_music_a, _music_b, _amb]:
		if p.playing and p.stream:
			var at: float = p.get_playback_position()
			p.stop()
			p.play(at)


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
		tw.tween_method(func(v): _fade[old] = v, float(_fade.get(old, 1.0)), 0.0, 1.2)
		tw.tween_callback(old.stop)
	if name == "":
		return
	new.stream = _stream("music_" + name, true)
	if new.stream == null:
		return
	_fade[new] = 0.0
	new.volume_db = -80.0
	new.play()
	var tw2 := create_tween()
	tw2.tween_method(func(v): _fade[new] = v, 0.0, 1.0, 1.5)


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
	pass   # volumes follow the settings every frame (_process)

