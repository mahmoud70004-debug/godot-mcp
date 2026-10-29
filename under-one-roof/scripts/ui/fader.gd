extends CanvasLayer
## Screen fades, chapter title cards, story narration and the credits roll.
##
## Narration screens always accept touch, mouse and keyboard and show a visible
## "Continue" button; skippable sequences also show "Skip". (Before this, the opening
## narration ignored touch input, so phones without a keyboard were stuck on it.)

signal _tapped

var skipped := false

var _black: ColorRect
var _title: Label
var _sub: Label
var _body: Label
var _continue: Button
var _skip: Button
var _waiting_tap := false


func _ready() -> void:
	layer = 50
	_black = ColorRect.new()
	_black.color = Color(0.05, 0.04, 0.06)
	UI.full_rect(_black)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_black.modulate.a = 0.0
	_black.gui_input.connect(func(e):
		if (e is InputEventScreenTouch and e.pressed) or (e is InputEventMouseButton and e.pressed):
			_tap())
	add_child(_black)
	var box := VBoxContainer.new()
	UI.full_rect(box)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 8)
	_black.add_child(box)
	_title = UI.label("", 30, UI.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(_title)
	_sub = UI.label("", 16, UI.PAPER, HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(_sub)
	_body = UI.label("", 16, UI.PAPER, HORIZONTAL_ALIGNMENT_CENTER)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size = Vector2(500, 0)
	_body.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(_body)

	_continue = UI.button("متابعة ◂", 16)
	_continue.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_continue.offset_left = -80
	_continue.offset_right = 80
	_continue.offset_top = -64
	_continue.offset_bottom = -24
	_continue.focus_mode = Control.FOCUS_ALL
	_continue.pressed.connect(_tap)
	_continue.visible = false
	_black.add_child(_continue)
	_skip = UI.button("تخطي المقدمة", 13)
	_skip.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_skip.offset_left = -150
	_skip.offset_right = -16
	_skip.offset_top = 14
	_skip.offset_bottom = 46
	_skip.pressed.connect(func():
		skipped = true
		_tap())
	_skip.visible = false
	_black.add_child(_skip)


func _unhandled_input(event: InputEvent) -> void:
	if _waiting_tap and (event.is_action_pressed("interact") or event.is_action_pressed("ui_accept")):
		get_viewport().set_input_as_handled()
		_tap()


func _tap() -> void:
	if _waiting_tap:
		_waiting_tap = false
		_tapped.emit()


func _clear() -> void:
	_title.text = ""
	_sub.text = ""
	_body.text = ""


func _refresh_fonts() -> void:
	_title.add_theme_font_override("font", Loc.title_font())
	_continue.text = Loc.t("متابعة ◂") if Loc.rtl() else Loc.t("متابعة ◂").replace("◂", "▸")
	_skip.text = Loc.t("تخطي المقدمة")
	for l in [_title, _sub, _body]:
		l.text_direction = Loc.dir()


func fade_out(t := 0.6) -> void:
	if Game.fast:
		t = 0.01
	_clear()
	_black.mouse_filter = Control.MOUSE_FILTER_STOP
	var tw := create_tween()
	tw.tween_property(_black, "modulate:a", 1.0, t)
	await tw.finished


func fade_in(t := 0.6) -> void:
	if Game.fast:
		t = 0.01
	_clear()
	_continue.visible = false
	_skip.visible = false
	var tw := create_tween()
	tw.tween_property(_black, "modulate:a", 0.0, t)
	await tw.finished
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE


func is_black() -> bool:
	return _black.modulate.a > 0.99


## Shows text over the dimmed screen. wait_tap: wait for Continue / tap / key.
## skippable: also offer "Skip intro" (sets `skipped`). dim < 1 lets the world show through.
func narrate(text: String, wait_tap := true, title := "", sub := "", skippable := false, dim := 1.0) -> void:
	if Game.fast or (skippable and skipped):
		if Game.fast:
			print("  <narrate> ", title, " ", sub, " ", text.substr(0, 40))
		await get_tree().process_frame
		return
	_refresh_fonts()
	_black.mouse_filter = Control.MOUSE_FILTER_STOP
	if _black.modulate.a < dim:
		var tw0 := create_tween()
		tw0.tween_property(_black, "modulate:a", dim, 0.4)
		await tw0.finished
	_title.text = Loc.t(title)
	_sub.text = Loc.t(sub)
	_body.text = Loc.t(text)
	for l in [_title, _sub, _body]:
		l.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	for l in [_title, _sub, _body]:
		tw.tween_property(l, "modulate:a", 1.0, 0.7)
	await tw.finished
	if wait_tap:
		_continue.visible = true
		_skip.visible = skippable
		(func(): if _continue.is_inside_tree(): _continue.grab_focus()).call_deferred()
		_waiting_tap = true
		await _tapped
		_continue.visible = false
		_skip.visible = false
	else:
		await get_tree().create_timer(2.0).timeout
	var tw2 := create_tween().set_parallel(true)
	for l in [_title, _sub, _body]:
		tw2.tween_property(l, "modulate:a", 0.0, 0.4)
	await tw2.finished


func chapter_card(number_text: String, title: String) -> void:
	await narrate("", false, title, number_text)


func credits(lines: Array) -> void:
	if Game.fast:
		await get_tree().process_frame
		return
	_refresh_fonts()
	_clear()
	_black.mouse_filter = Control.MOUSE_FILTER_STOP
	var tl := []
	for l in lines:
		tl.append(Loc.t(l))
	_body.text = "\n".join(tl)
	_body.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_body, "modulate:a", 1.0, 1.5)
	await tw.finished
	_continue.visible = true
	_waiting_tap = true
	await _tapped
	_continue.visible = false
