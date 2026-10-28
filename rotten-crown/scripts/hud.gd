extends Control

var game
var joystick_finger := -1
var look_finger := -1
var defend_finger := -1
var stick := Vector2.ZERO
var font: Font
var ink := Color("d4d0b5")
var muted := Color("a4a892")
var accent := Color("b9c78c")

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = ThemeDB.fallback_font

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and game != null and game.player != null:
		joystick_finger = -1
		look_finger = -1
		defend_finger = -1
		stick = Vector2.ZERO
		game.player.move_input = Vector2.ZERO
		game.player.defending = false

func _stick_center() -> Vector2:
	return Vector2(size.x * 0.13, size.y * 0.77)

func _radius() -> float:
	return minf(size.x, size.y) * 0.115

func _button_center(kind: String) -> Vector2:
	match kind:
		"attack": return Vector2(size.x * 0.91, size.y * 0.76)
		"defend": return Vector2(size.x * 0.80, size.y * 0.84)
		"interact": return Vector2(size.x * 0.82, size.y * 0.63)
		_: return Vector2(size.x * 0.94, size.y * 0.11)

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_touch_start(touch.index, touch.position)
		else:
			_touch_end(touch.index)
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == joystick_finger:
			_update_stick(drag.position)
		elif drag.index == look_finger and not game.inventory_open:
			game.player.look(drag.relative)
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not game.inventory_open:
		game.player.look(event.relative)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			else:
				game.attack()
	elif event is InputEventKey and not event.echo:
		if event.keycode == KEY_SHIFT:
			game.player.defending = event.pressed and not game.inventory_open
		if not event.pressed:
			return
		match event.keycode:
			KEY_E: game.interact()
			KEY_SPACE: game.attack()
			KEY_TAB, KEY_I: game.toggle_inventory()
			KEY_ESCAPE: Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _touch_start(index: int, pos: Vector2) -> void:
	var r := _radius()
	if pos.distance_to(_button_center("inventory")) < r * 0.62:
		game.toggle_inventory()
		return
	if game.inventory_open:
		return
	if pos.distance_to(_button_center("attack")) < r * 0.65:
		game.attack()
	elif pos.distance_to(_button_center("defend")) < r * 0.58:
		if defend_finger == -1:
			defend_finger = index
			game.player.defending = true
	elif pos.distance_to(_button_center("interact")) < r * 0.58:
		game.interact()
	elif pos.distance_to(_stick_center()) < r * 1.35 and joystick_finger == -1:
		joystick_finger = index
		_update_stick(pos)
	elif pos.x > size.x * 0.45 and look_finger == -1:
		look_finger = index

func _touch_end(index: int) -> void:
	if index == joystick_finger:
		joystick_finger = -1
		stick = Vector2.ZERO
		game.player.move_input = Vector2.ZERO
	if index == look_finger:
		look_finger = -1
	if index == defend_finger:
		defend_finger = -1
		game.player.defending = false

func _update_stick(pos: Vector2) -> void:
	stick = ((pos - _stick_center()) / _radius()).limit_length(1.0)
	game.player.move_input = stick

func _text(pos: Vector2, text: String, font_size: int, color: Color, width := -1.0, alignment := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	draw_string(font, pos, text, alignment, width, font_size, color)

func _ring(center: Vector2, radius: float, label: String, active := false) -> void:
	draw_circle(center, radius, Color(0.05, 0.07, 0.06, 0.62))
	draw_arc(center, radius, 0, TAU, 48, Color(0.72, 0.75, 0.63, 0.7) if active else Color(0.72, 0.75, 0.63, 0.38), 1.5, true)
	var fs := maxi(11, int(size.y * 0.018))
	_text(center + Vector2(-radius, fs * 0.35), label, fs, ink, radius * 2, HORIZONTAL_ALIGNMENT_CENTER)

func _draw() -> void:
	var h := size.y
	var w := size.x
	var r := _radius()
	# Fine frame and restrained labels keep the scene readable on a phone.
	draw_rect(Rect2(0, 0, w, h * 0.105), Color(0.025, 0.035, 0.03, 0.55))
	draw_line(Vector2(w * 0.035, h * 0.105), Vector2(w * 0.965, h * 0.105), Color(0.73, 0.75, 0.61, 0.35), 1.0)
	_text(Vector2(w * 0.035, h * 0.047), "R O T T E N   C R O W N", maxi(15, int(h * 0.025)), ink)
	_text(Vector2(w * 0.035, h * 0.079), "VALDRON  /  THE SILENT OUTSKIRTS", maxi(10, int(h * 0.015)), muted)
	_text(Vector2(w * 0.69, h * 0.052), "PHASE 01  /  VISUAL STUDY", maxi(10, int(h * 0.014)), muted)
	_ring(_button_center("inventory"), r * 0.48, "BAG", game.inventory_open)
	if game.inventory_open:
		var panel := Rect2(w * 0.26, h * 0.19, w * 0.48, h * 0.58)
		draw_rect(panel, Color(0.035, 0.045, 0.038, 0.95))
		draw_rect(panel, Color(0.65, 0.69, 0.55, 0.7), false, 1.0)
		_text(panel.position + Vector2(24, 38), "INVENTORY  /  RELICS & CLUES", maxi(16, int(h*0.024)), ink)
		_text(panel.position + Vector2(24, 68), "Fragments gathered in the silence.", maxi(11, int(h*0.017)), muted)
		if game.inventory.is_empty():
			_text(panel.position + Vector2(24, 115), "Nothing collected yet.", maxi(12, int(h*0.019)), muted)
		else:
			for i in range(game.inventory.size()):
				_text(panel.position + Vector2(24, 115 + i * 30), "+  " + game.inventory[i], maxi(12, int(h*0.019)), accent)
		_text(Vector2(panel.position.x + 24, panel.end.y - 20), "BAG / TAB to close", maxi(11, int(h*0.016)), muted)
		return
	# Crosshair and contextual prompt.
	var center := Vector2(w / 2, h / 2)
	draw_line(center - Vector2(6, 0), center + Vector2(6, 0), Color(0.85, 0.87, 0.76, 0.7), 1)
	draw_line(center - Vector2(0, 6), center + Vector2(0, 6), Color(0.85, 0.87, 0.76, 0.7), 1)
	if game.world.get_nearby_item(game.player.global_position) != null:
		_text(Vector2(w*0.3, h*0.59), "A FRAGMENT NEARBY  /  USE", maxi(11, int(h*0.018)), accent, w*0.4, HORIZONTAL_ALIGNMENT_CENTER)
	if game.notice_time > 0:
		_text(Vector2(w*0.2, h*0.91), game.notice, maxi(12, int(h*0.018)), ink, w*0.6, HORIZONTAL_ALIGNMENT_CENTER)
	_ring(_stick_center(), r, "")
	draw_circle(_stick_center() + stick * r * 0.72, r * 0.32, Color(0.8, 0.83, 0.7, 0.36))
	_ring(_button_center("attack"), r * 0.62, "STRIKE")
	_ring(_button_center("defend"), r * 0.53, "GUARD", game.player.defending)
	_ring(_button_center("interact"), r * 0.53, "USE")
	_text(Vector2(w*0.035, h*0.965), "MOVE", maxi(10, int(h*0.014)), muted)
	_text(Vector2(w*0.73, h*0.965), "DRAG TO LOOK", maxi(10, int(h*0.014)), muted)
