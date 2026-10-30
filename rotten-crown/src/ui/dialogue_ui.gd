extends CanvasLayer
## Dialogue autoload (contract C13). Plays Events.dialogue_requested lines in order:
##  - THOUGHT: the knight's inner voice, a quiet subtitle typed out at the bottom.
##  - ENTITY: a Witness speaking - a dark window that flickers, the text arrives
##    corrupted and resolves, radio static plays underneath, a garbled voice first.
## Built in code so it needs no scene; sits above the HUD, pauses with the game.

const CHARS_PER_SECOND := 30.0
const FADE := 0.35
## Space kept free under the subtitle for the HUD's prompt line (640x360 units).
const BOTTOM_GAP := 46.0
const GLITCH_CHARS := "#%&@$*?!/\\|<>~^"
const THOUGHT_COLOR := Color(0.84, 0.8, 0.68)
const ENTITY_COLOR := Color(0.88, 0.9, 0.86)
const SPEAKER_COLOR := Color(0.62, 0.86, 0.55)
const STATIC_LOOP := "res://assets/audio/sfx/static_loop.wav"
const STATIC_BURST := "res://assets/audio/sfx/static_burst.wav"
const VOICES := ["res://assets/audio/voices/garble_1.wav", "res://assets/audio/voices/garble_2.wav",
	"res://assets/audio/voices/garble_3.wav", "res://assets/audio/voices/garble_4.wav"]

var _queue: Array = []
var _playing := false
var _root: Control
var _thought: Label
var _panel: PanelContainer
var _speaker: Label
var _entity_text: Label
var _static: AudioStreamPlayer
var _sfx: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	layer = 12
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_rng.randomize()
	_build()
	Events.dialogue_requested.connect(_on_requested)


func _on_requested(lines: Array) -> void:
	_queue.append_array(lines)
	if not _playing:
		_play_queue()


func _play_queue() -> void:
	_playing = true
	while not _queue.is_empty():
		var line := _queue.pop_front() as DialogueLine
		if line == null:
			continue
		if line.style == DialogueLine.Style.ENTITY:
			await _show_entity(line)
		else:
			await _show_thought(line)
	_playing = false
	Events.dialogue_finished.emit()


func _show_thought(line: DialogueLine) -> void:
	_thought.text = line.text
	_thought.visible_ratio = 0.0
	_thought.modulate.a = 1.0
	_thought.visible = true
	var reveal := create_tween()
	reveal.tween_property(_thought, "visible_ratio", 1.0, line.text.length() / CHARS_PER_SECOND)
	await reveal.finished
	await get_tree().create_timer(line.hold, false).timeout
	var out := create_tween()
	out.tween_property(_thought, "modulate:a", 0.0, FADE)
	await out.finished
	_thought.visible = false


func _show_entity(line: DialogueLine) -> void:
	_speaker.text = _corrupt(line.speaker.to_upper(), 0.25) if line.speaker != "" else "???"
	_entity_text.text = ""
	_panel.modulate.a = 0.0
	_panel.visible = true
	_play(_sfx, STATIC_BURST)
	_play(_static, STATIC_LOOP)
	var voice := VOICES[_rng.randi() % VOICES.size()] as String
	var appear := create_tween()
	appear.tween_property(_panel, "modulate:a", 1.0, 0.12)
	await appear.finished
	_play(_sfx, voice)
	# The words arrive wrong and settle into the real line, letter by letter.
	var steps := maxi(line.text.length(), 1)
	var dt := 1.0 / CHARS_PER_SECOND
	for i in steps + 6:
		var known := clampi(i - 3, 0, line.text.length())
		_entity_text.text = line.text.substr(0, known) + _corrupt(line.text.substr(known, 4), 1.0)
		_jitter()
		await get_tree().create_timer(dt, false).timeout
	_entity_text.text = line.text
	var left := line.hold
	while left > 0.0:
		_jitter()
		var step := _rng.randf_range(0.08, 0.3)
		await get_tree().create_timer(step, false).timeout
		left -= step
	_play(_sfx, STATIC_BURST)
	var out := create_tween()
	out.tween_property(_panel, "modulate:a", 0.0, 0.18)
	await out.finished
	_panel.visible = false
	_panel.position = _panel.get_meta(&"home", _panel.position)
	_static.stop()


## A short glitch: the window slips a few pixels and the light stutters.
func _jitter() -> void:
	var home: Vector2 = _panel.get_meta(&"home", _panel.position)
	if not _panel.has_meta(&"home"):
		_panel.set_meta(&"home", home)
	if _rng.randf() < 0.35:
		_panel.position = home + Vector2(_rng.randi_range(-3, 3), _rng.randi_range(-1, 1))
		_panel.self_modulate = Color(1.0, _rng.randf_range(0.7, 1.0), _rng.randf_range(0.7, 1.0))
	else:
		_panel.position = home
		_panel.self_modulate = Color.WHITE


func _corrupt(text: String, amount: float) -> String:
	var out := ""
	for c in text:
		out += GLITCH_CHARS[_rng.randi() % GLITCH_CHARS.length()] if c != " " and _rng.randf() < amount else c
	return out


func _play(player: AudioStreamPlayer, path: String) -> void:
	if not ResourceLoader.exists(path):
		return
	player.stream = load(path) as AudioStream
	player.play()


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_thought = Label.new()
	_thought.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_thought.anchor_left = 0.12
	_thought.anchor_right = 0.88
	_thought.offset_left = 0.0
	_thought.offset_right = 0.0
	_thought.offset_top = -BOTTOM_GAP - 40.0
	_thought.offset_bottom = -BOTTOM_GAP
	_thought.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_thought.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_thought.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_thought.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_thought.add_theme_color_override("font_color", THOUGHT_COLOR)
	_thought.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_thought.add_theme_constant_override("shadow_offset_x", 1)
	_thought.add_theme_constant_override("shadow_offset_y", 1)
	_thought.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_thought.visible = false
	_root.add_child(_thought)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_panel.anchor_left = 0.2
	_panel.anchor_right = 0.8
	_panel.offset_left = 0.0
	_panel.offset_right = 0.0
	_panel.offset_top = -BOTTOM_GAP - 70.0
	_panel.offset_bottom = -BOTTOM_GAP
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.02, 0.025, 0.02, 0.88)
	box.border_color = Color(0.35, 0.5, 0.3, 0.9)
	box.set_border_width_all(1)
	box.content_margin_left = 10.0
	box.content_margin_right = 10.0
	box.content_margin_top = 6.0
	box.content_margin_bottom = 8.0
	_panel.add_theme_stylebox_override("panel", box)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.visible = false
	_root.add_child(_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	_panel.add_child(column)
	_speaker = Label.new()
	_speaker.add_theme_color_override("font_color", SPEAKER_COLOR)
	column.add_child(_speaker)
	_entity_text = Label.new()
	_entity_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_entity_text.add_theme_color_override("font_color", ENTITY_COLOR)
	column.add_child(_entity_text)

	_static = AudioStreamPlayer.new()
	_static.bus = &"SFX"
	_static.volume_db = -14.0
	add_child(_static)
	_sfx = AudioStreamPlayer.new()
	_sfx.bus = &"SFX"
	_sfx.volume_db = -6.0
	add_child(_sfx)
