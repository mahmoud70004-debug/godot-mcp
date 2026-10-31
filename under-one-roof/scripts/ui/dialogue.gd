extends CanvasLayer
## Dialogue box with portrait, speaker name, typewriter text and choices.
##   await say(speaker_id, text)
##   var i = await choose(["...", "..."])

signal advanced
signal chosen(index: int)

var _root: Control
var _box: PanelContainer
var _name_plate: PanelContainer
var _name: Label
var _text: Label
const BOX_TOP := -92             # dialogue box top (from the screen bottom); plates sit above it

var _portrait: TextureRect
var _portrait_frame: PanelContainer
var _more: Label
var _choices: VBoxContainer
var _typing := false
var _waiting := false
var _choosing := false
var _skip := false
var _skip_btn: Button


func _ready() -> void:
	layer = 20
	_root = Control.new()
	UI.full_rect(_root)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.gui_input.connect(_on_input)
	add_child(_root)

	_box = UI.panel()
	_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_box.anchor_left = 0.5
	_box.anchor_right = 0.5
	_box.offset_left = -250
	_box.offset_right = 250
	_box.offset_top = BOX_TOP
	_box.offset_bottom = -6
	var st: StyleBox = _box.get_theme_stylebox("panel").duplicate()
	st.content_margin_top = 9
	st.content_margin_bottom = 12
	st.content_margin_left = 10
	st.content_margin_right = 10
	_box.add_theme_stylebox_override("panel", st)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_box)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.layout_direction = Loc.layout()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(row)

	_portrait_frame = UI.panel(UI.PAPER_DARK)
	_portrait_frame.custom_minimum_size = Vector2(58, 58)
	_portrait_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_portrait_frame)
	_portrait = TextureRect.new()
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.custom_minimum_size = Vector2(48, 52)
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_portrait_frame.add_child(_portrait)

	_text = UI.label("", 14)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_text.custom_minimum_size = Vector2(280, 58)
	row.add_child(_text)

	_name_plate = UI.panel(UI.WOOD)
	_name_plate.add_theme_stylebox_override("panel", UI.panel_style(UI.WOOD, UI.WOOD_DARK, 2, 4))
	_name_plate.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_name_plate.anchor_left = 0.5
	_name_plate.anchor_right = 0.5
	_name_plate.offset_right = 196
	_name_plate.offset_left = 70
	_name_plate.offset_top = BOX_TOP - 24
	_name_plate.offset_bottom = BOX_TOP - 1
	_name_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_name_plate)
	_name = UI.label("", 14, UI.PAPER)
	_name_plate.add_child(_name)

	_more = UI.label("▼", 12, UI.WOOD, HORIZONTAL_ALIGNMENT_CENTER)
	_more.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_more.anchor_left = 0.5
	_more.anchor_right = 0.5
	_more.offset_left = -282
	_more.offset_right = -262
	_more.offset_top = -17
	_more.offset_bottom = -1
	_root.add_child(_more)

	_choices = VBoxContainer.new()
	_choices.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_choices.anchor_left = 0.5
	_choices.anchor_right = 0.5
	_choices.offset_left = -200
	_choices.offset_right = 200
	_choices.offset_top = BOX_TOP - 150
	_choices.offset_bottom = BOX_TOP - 30
	_choices.alignment = BoxContainer.ALIGNMENT_END
	_choices.add_theme_constant_override("separation", 6)
	_root.add_child(_choices)
	_skip_btn = UI.button("تخطي الحوار", 11)
	_skip_btn.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_skip_btn.anchor_left = 0.5
	_skip_btn.anchor_right = 0.5
	_skip_btn.offset_top = BOX_TOP - 25
	_skip_btn.offset_bottom = BOX_TOP - 2
	_skip_btn.pressed.connect(func():
		Director.skip_lines = true
		_skip = true
		_advance())
	_root.add_child(_skip_btn)
	visible = false


func _apply_layout() -> void:
	var rtl := Loc.rtl()
	_name_plate.offset_left = 40 if rtl else -166
	_name_plate.offset_right = 166 if rtl else -40
	_more.offset_left = -8
	_more.offset_right = 8
	_skip_btn.offset_left = -250 if rtl else 166
	_skip_btn.offset_right = -166 if rtl else 250
	_skip_btn.text = Loc.t("تخطي الحوار")
	_text.horizontal_alignment = UI.flow(HORIZONTAL_ALIGNMENT_RIGHT)
	_text.text_direction = Loc.dir()
	_name.horizontal_alignment = UI.flow(HORIZONTAL_ALIGNMENT_RIGHT)
	_box.get_child(0).layout_direction = Loc.layout()


func _process(delta: float) -> void:
	if _more.visible:
		_more.modulate.a = 0.5 + 0.5 * sin(Time.get_ticks_msec() / 150.0)


func _unhandled_input(event: InputEvent) -> void:
	if not visible or _choosing:
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		_advance()


func _on_input(event: InputEvent) -> void:
	if _choosing:
		return
	if (event is InputEventScreenTouch and event.pressed):
		_advance()


func _advance() -> void:
	if _typing:
		_skip = true
	elif _waiting:
		_waiting = false
		advanced.emit()


func open() -> void:
	visible = true


var _last_speaker := ""
var _more_tween: Tween


## Small, quick motions that make a line feel spoken: the box rises in when the
## conversation starts, the portrait pops when someone new talks, the skip button fades
## in, and the "more" arrow bobs while it waits.
func _animate_line(opening: bool, speaker: String) -> void:
	if opening:
		_box.modulate.a = 0.0
		_box.offset_top = BOX_TOP + 10
		_box.offset_bottom = -6 + 10
		var tb := create_tween().set_parallel()
		tb.tween_property(_box, "modulate:a", 1.0, 0.18)
		tb.tween_property(_box, "offset_top", float(BOX_TOP), 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tb.tween_property(_box, "offset_bottom", -6.0, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_skip_btn.modulate.a = 0.0
		create_tween().tween_property(_skip_btn, "modulate:a", 1.0, 0.35).set_delay(0.25)
	if speaker != _last_speaker or opening:
		_portrait_frame.pivot_offset = _portrait_frame.size / 2.0
		_portrait_frame.scale = Vector2(0.85, 0.85)
		create_tween().tween_property(_portrait_frame, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_name_plate.modulate.a = 0.0
		create_tween().tween_property(_name_plate, "modulate:a", 1.0, 0.2)
	_last_speaker = speaker
	if _more_tween == null or not _more_tween.is_valid():
		_more_tween = create_tween().set_loops()
		_more_tween.tween_property(_more, "position:y", _more.position.y + 3, 0.4).set_trans(Tween.TRANS_SINE)
		_more_tween.tween_property(_more, "position:y", _more.position.y, 0.4).set_trans(Tween.TRANS_SINE)


func close() -> void:
	_last_speaker = ""
	if visible:
		Audio.duck(false)
		Audio.sfx("dlg_close")
	visible = false


func say(speaker: String, text: String) -> void:
	if Game.fast:
		print("  [%s] %s" % [speaker, text])
		await get_tree().process_frame
		return
	var opening := not visible
	if opening:
		Audio.duck(true)
		Audio.dialogue_open()
	visible = true
	_apply_layout()
	_animate_line(opening, speaker)
	_box.visible = true
	_choices.visible = false
	var name: String = Loc.t(Story.speaker_name(speaker))
	_name_plate.visible = name != ""
	_name.text = name
	var tex := UI.portrait(Story.portrait_of(speaker))
	_portrait_frame.visible = tex != null
	_portrait.texture = tex
	_text.text = text
	_text.add_theme_color_override("font_color", UI.INK if speaker != "" else UI.INK_SOFT)
	_text.visible_characters = 0
	_more.visible = false
	_typing = true
	_skip = false
	var total := text.length()
	var shown := 0
	var delay := Game.text_delay()
	if delay <= 0.0:
		_skip = true
	var kind := Story.voice_of(speaker)
	var pitch := 1.0 + 0.25 * float(Story.voice_pitch(speaker))
	var letters := 0
	while shown < total and not _skip:
		shown += 1
		_text.visible_characters = shown
		var ch := text[shown - 1]
		var wait := delay
		if ch in ".!?…؟":
			wait += delay * 9.0        # a breath between sentences
		elif ch in ",،;:—":
			wait += delay * 4.0
		elif ch != " ":
			letters += 1
			if kind != "" and letters % 3 == 1:
				Audio.voice(kind, ch, pitch)
		await get_tree().create_timer(wait).timeout
	_text.visible_characters = -1
	_typing = false
	_more.visible = true
	_waiting = true
	if Director.skip_lines:
		_waiting = false
	else:
		await advanced
	Audio.sfx("dlg_next")


func choose(options: Array) -> int:
	if Game.fast:
		await get_tree().process_frame
		var pick: int = Game.auto_choices.pop_front() if not Game.auto_choices.is_empty() else 0
		print("  <choice> ", options[pick])
		return pick
	visible = true
	_choosing = true
	_more.visible = false
	for c in _choices.get_children():
		c.queue_free()
	var first: Button = null
	for i in options.size():
		var b := UI.button(str(options[i]), 15)
		b.focus_mode = Control.FOCUS_ALL
		b.pressed.connect(func(): chosen.emit(i))
		_choices.add_child(b)
		if first == null:
			first = b
	_choices.visible = true
	first.call_deferred("grab_focus")
	var idx: int = await chosen
	Audio.sfx("select")
	_choices.visible = false
	_choosing = false
	return idx
