extends CanvasLayer
## Dialogue autoload (contract C13). Plays Events.dialogue_requested lines in order:
##  - THOUGHT: the knight's inner voice, a quiet subtitle typed out at the bottom.
##  - ENTITY: a Witness speaking - a dark window that flickers, the text arrives
##    corrupted and resolves, radio static plays underneath, a garbled voice first.
## Built in code so it needs no scene; sits above the HUD, pauses with the game.

const CHARS_PER_SECOND := 30.0
const FADE := 0.35
## Both sit low, between the joystick and the buttons: the subtitle under the HUD's
## prompt line, the Witness window over it, leaving the speaker in view (UI units).
const THOUGHT_GAP := 8.0
const THOUGHT_HEIGHT := 40.0
const PANEL_GAP := 10.0
const PANEL_HEIGHT := 62.0
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
var _voice: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()
## Bumped when the scene changes: a line still playing from the old scene stops.
var _generation := 0
var _insets := Vector4.ZERO


func _ready() -> void:
	layer = 12
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_rng.randomize()
	_build()
	_place()
	get_viewport().size_changed.connect(_place)
	# Safe-area insets can change without a resize (a 180 degree flip, late browser bars).
	var poll := Timer.new()
	poll.wait_time = 1.0
	poll.autostart = true
	poll.timeout.connect(_on_inset_poll)
	add_child(poll)
	Events.dialogue_requested.connect(_on_requested)
	Events.menu_state_changed.connect(_on_menu_state_changed)
	SceneLoader.scene_changed.connect(_on_scene_changed)


## Keep clear of notches and the browser bar (UiSafeArea) whenever the screen changes.
func _place() -> void:
	var bottom := UiSafeArea.bottom_margin()
	_thought.offset_bottom = -bottom - THOUGHT_GAP
	_thought.offset_top = _thought.offset_bottom - THOUGHT_HEIGHT
	_panel.offset_bottom = -bottom - PANEL_GAP
	_panel.offset_top = _panel.offset_bottom - PANEL_HEIGHT
	_insets = UiSafeArea.insets()


func _on_inset_poll() -> void:
	if UiSafeArea.insets() != _insets:
		_place()


## Pause menu, lore reader, death screen: they draw below this layer, so step aside.
func _on_menu_state_changed(is_open: bool) -> void:
	visible = not is_open


func _on_scene_changed(_path: String) -> void:
	_generation += 1
	_queue.clear()
	_playing = false
	_thought.visible = false
	_panel.visible = false
	offset = Vector2.ZERO
	_static.stop()
	_voice.stop()


func _on_requested(lines: Array) -> void:
	_queue.append_array(lines)
	if not _playing:
		_play_queue()


func _play_queue() -> void:
	_playing = true
	var gen := _generation
	while not _queue.is_empty():
		var line := _queue.pop_front() as DialogueLine
		if line == null:
			continue
		if line.style == DialogueLine.Style.ENTITY:
			await _show_entity(line, gen)
		else:
			await _show_thought(line, gen)
		if gen != _generation:
			return
	_playing = false
	Events.dialogue_finished.emit()


func _show_thought(line: DialogueLine, gen: int) -> void:
	_thought.text = line.text
	_thought.visible_ratio = 0.0
	_thought.modulate.a = 1.0
	_thought.visible = true
	var reveal := create_tween()
	reveal.tween_property(_thought, "visible_ratio", 1.0, line.text.length() / CHARS_PER_SECOND)
	await reveal.finished
	await get_tree().create_timer(line.hold, false).timeout
	if gen != _generation:
		return
	var out := create_tween()
	out.tween_property(_thought, "modulate:a", 0.0, FADE)
	await out.finished
	if gen == _generation:
		_thought.visible = false


func _show_entity(line: DialogueLine, gen: int) -> void:
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
	if gen != _generation:
		return
	_play(_voice, voice)
	# The words arrive wrong and settle into the real line, letter by letter.
	var steps := maxi(line.text.length(), 1)
	var dt := 1.0 / CHARS_PER_SECOND
	for i in steps + 6:
		var known := clampi(i - 3, 0, line.text.length())
		_entity_text.text = line.text.substr(0, known) + _corrupt(line.text.substr(known, 4), 1.0)
		_jitter()
		await get_tree().create_timer(dt, false).timeout
		if gen != _generation:
			return
	_entity_text.text = line.text
	var left := line.hold
	while left > 0.0:
		_jitter()
		var step := _rng.randf_range(0.08, 0.3)
		await get_tree().create_timer(step, false).timeout
		left -= step
		if gen != _generation:
			return
	_play(_sfx, STATIC_BURST)
	var out := create_tween()
	out.tween_property(_panel, "modulate:a", 0.0, 0.18)
	await out.finished
	if gen != _generation:
		return
	_panel.visible = false
	offset = Vector2.ZERO
	_panel.self_modulate = Color.WHITE
	_static.stop()


## A short glitch: the window slips a few pixels and the light stutters. The whole
## layer moves (the subtitle is hidden meanwhile), so the anchored layout is untouched.
func _jitter() -> void:
	if _rng.randf() < 0.35:
		offset = Vector2(_rng.randi_range(-3, 3), _rng.randi_range(-1, 1))
		_panel.self_modulate = Color(1.0, _rng.randf_range(0.7, 1.0), _rng.randf_range(0.7, 1.0))
	else:
		offset = Vector2.ZERO
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
	_thought.anchor_left = 0.22
	_thought.anchor_right = 0.74
	_thought.offset_left = 0.0
	_thought.offset_right = 0.0
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
	_panel.anchor_left = 0.22
	_panel.anchor_right = 0.74
	_panel.offset_left = 0.0
	_panel.offset_right = 0.0
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
	_voice = AudioStreamPlayer.new()
	_voice.bus = &"SFX"
	_voice.volume_db = -6.0
	add_child(_voice)
