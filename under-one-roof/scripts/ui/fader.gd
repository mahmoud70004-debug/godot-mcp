extends CanvasLayer
## Screen fades, chapter title cards, narration on black and the credits roll.

signal _tapped

var _black: ColorRect
var _title: Label
var _sub: Label
var _body: Label
var _waiting_tap := false


func _ready() -> void:
	layer = 50
	_black = ColorRect.new()
	_black.color = Color(0.05, 0.04, 0.06)
	UI.full_rect(_black)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_black.modulate.a = 0.0
	_black.gui_input.connect(func(e):
		if e is InputEventScreenTouch and e.pressed:
			_tap())
	add_child(_black)
	var box := VBoxContainer.new()
	UI.full_rect(box)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 6)
	_black.add_child(box)
	_title = UI.label("", 30, UI.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	_title.add_theme_font_override("font", load("res://assets/fonts/Lalezar.ttf"))
	box.add_child(_title)
	_sub = UI.label("", 16, UI.PAPER, HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(_sub)
	_body = UI.label("", 16, UI.PAPER, HORIZONTAL_ALIGNMENT_CENTER)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size = Vector2(480, 0)
	_body.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(_body)


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
	var tw := create_tween()
	tw.tween_property(_black, "modulate:a", 0.0, t)
	await tw.finished
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE


func is_black() -> bool:
	return _black.modulate.a > 0.99


## Shows text on black. Expects the screen to be black already.
func narrate(text: String, wait_tap := true, title := "", sub := "") -> void:
	if Game.fast:
		print("  <narrate> ", title, " ", sub, " ", text.substr(0, 40))
		await get_tree().process_frame
		return
	_title.text = title
	_sub.text = sub
	_body.text = text
	for l in [_title, _sub, _body]:
		l.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	for l in [_title, _sub, _body]:
		tw.tween_property(l, "modulate:a", 1.0, 0.8)
	await tw.finished
	if wait_tap:
		_waiting_tap = true
		await _tapped
	else:
		await get_tree().create_timer(2.2).timeout
	var tw2 := create_tween().set_parallel(true)
	for l in [_title, _sub, _body]:
		tw2.tween_property(l, "modulate:a", 0.0, 0.5)
	await tw2.finished


func chapter_card(number_text: String, title: String) -> void:
	await narrate("", false, title, number_text)


func credits(lines: Array) -> void:
	if Game.fast:
		await get_tree().process_frame
		return
	_clear()
	_body.text = "\n".join(lines)
	_body.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_body, "modulate:a", 1.0, 1.5)
	await tw.finished
	_waiting_tap = true
	await _tapped
