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
	_box.offset_top = -80
	_box.offset_bottom = -6
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
	_text.custom_minimum_size = Vector2(280, 50)
	row.add_child(_text)

	_name_plate = UI.panel(UI.WOOD)
	_name_plate.add_theme_stylebox_override("panel", UI.panel_style(UI.WOOD, UI.WOOD_DARK, 2, 4))
	_name_plate.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_name_plate.anchor_left = 0.5
	_name_plate.anchor_right = 0.5
	_name_plate.offset_right = 196
	_name_plate.offset_left = 70
	_name_plate.offset_top = -98
	_name_plate.offset_bottom = -76
	_name_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_name_plate)
	_name = UI.label("", 14, UI.PAPER)
	_name_plate.add_child(_name)

	_more = UI.label("▼", 12, UI.WOOD, HORIZONTAL_ALIGNMENT_LEFT)
	_more.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_more.anchor_left = 0.5
	_more.anchor_right = 0.5
	_more.offset_left = -282
	_more.offset_right = -262
	_more.offset_top = -26
	_more.offset_bottom = -10
	_root.add_child(_more)

	_choices = VBoxContainer.new()
	_choices.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_choices.anchor_left = 0.5
	_choices.anchor_right = 0.5
	_choices.offset_left = -200
	_choices.offset_right = 200
	_choices.offset_top = -206
	_choices.offset_bottom = -88
	_choices.alignment = BoxContainer.ALIGNMENT_END
	_choices.add_theme_constant_override("separation", 6)
	_root.add_child(_choices)
	_skip_btn = UI.button("تخطي الحوار", 11)
	_skip_btn.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_skip_btn.anchor_left = 0.5
	_skip_btn.anchor_right = 0.5
	_skip_btn.offset_top = -104
	_skip_btn.offset_bottom = -82
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
	_more.offset_left = -242 if rtl else 222
	_more.offset_right = -222 if rtl else 242
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


func close() -> void:
	if visible:
		Audio.duck(false)
	visible = false


func say(speaker: String, text: String) -> void:
	if Game.fast:
		print("  [%s] %s" % [speaker, text])
		await get_tree().process_frame
		return
	if not visible:
		Audio.duck(true)
		Audio.sfx("page", randf_range(0.95, 1.05))
	visible = true
	_apply_layout()
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
	Audio.sfx("select")


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
