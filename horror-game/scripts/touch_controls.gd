class_name TouchControls
extends Control
## Multi-touch mobile controls.
##  * Left half of the screen  : floating joystick (appears where the finger lands).
##  * Right half of the screen : drag to look around.
##  * Buttons on the right     : flashlight toggle and quick 180° turn.
## Desktop fallback: WASD + mouse (hold right button or click to capture).

signal flashlight_pressed
signal turn_pressed

const JOY_RADIUS := 110.0
const DEADZONE := 0.12

var move_vector := Vector2.ZERO
var sprinting := false
var _look_delta := Vector2.ZERO

var _joy_index := -1
var _joy_origin := Vector2.ZERO
var _joy_pos := Vector2.ZERO
var _look_index := -1
var _look_last := Vector2.ZERO
var _btn_flash_down := false
var _btn_turn_down := false
var _alpha := 1.0
var enabled := true

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func consume_look() -> Vector2:
	var d := _look_delta
	_look_delta = Vector2.ZERO
	return d

func _flash_center() -> Vector2:
	var s := size
	return Vector2(s.x - 105.0, s.y - 330.0)

func _turn_center() -> Vector2:
	var s := size
	return Vector2(s.x - 105.0, s.y - 160.0)

func _default_joy() -> Vector2:
	return Vector2(170.0, size.y - 240.0)

func _input(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventScreenTouch:
		var p: Vector2 = event.position
		if event.pressed:
			if p.distance_to(_flash_center()) < 75.0:
				_btn_flash_down = true
				flashlight_pressed.emit()
				queue_redraw()
				return
			if p.distance_to(_turn_center()) < 75.0:
				_btn_turn_down = true
				turn_pressed.emit()
				queue_redraw()
				return
			if p.x < size.x * 0.5 and _joy_index == -1:
				_joy_index = event.index
				_joy_origin = p
				_joy_pos = p
			elif _look_index == -1:
				_look_index = event.index
				_look_last = p
		else:
			_btn_flash_down = false
			_btn_turn_down = false
			if event.index == _joy_index:
				_joy_index = -1
				move_vector = Vector2.ZERO
				sprinting = false
			elif event.index == _look_index:
				_look_index = -1
		queue_redraw()
	elif event is InputEventScreenDrag:
		if event.index == _joy_index:
			_joy_pos = event.position
			var off: Vector2 = _joy_pos - _joy_origin
			var len := off.length()
			# Let the base follow the finger when pulled far away.
			if len > JOY_RADIUS * 1.6:
				_joy_origin = _joy_pos - off.normalized() * JOY_RADIUS * 1.6
				off = _joy_pos - _joy_origin
				len = off.length()
			var v := off / JOY_RADIUS
			if v.length() > 1.0:
				v = v.normalized()
			move_vector = v if v.length() > DEADZONE else Vector2.ZERO
			sprinting = len > JOY_RADIUS * 1.15
			queue_redraw()
		elif event.index == _look_index:
			_look_delta += event.position - _look_last
			_look_last = event.position
	# ---- desktop fallback (ignore mouse events emulated from touch) ----
	elif event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			_look_delta += event.relative
	elif event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT and DisplayServer.get_name() != "headless":
			if not DisplayServer.is_touchscreen_available():
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F:
				flashlight_pressed.emit()
			KEY_Q:
				turn_pressed.emit()
			KEY_ESCAPE:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _process(_delta: float) -> void:
	if not enabled:
		return
	queue_redraw()
	# Keyboard fallback for desktop testing.
	if _joy_index == -1:
		var k := Vector2(
			float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
			float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W)))
		move_vector = k.normalized() if k != Vector2.ZERO else Vector2.ZERO
		sprinting = Input.is_key_pressed(KEY_SHIFT)

func _draw() -> void:
	if not enabled:
		return
	var font := get_theme_default_font()
	# Joystick
	var base := _joy_origin if _joy_index != -1 else _default_joy()
	var knob := _joy_pos if _joy_index != -1 else base
	if knob.distance_to(base) > JOY_RADIUS:
		knob = base + (knob - base).normalized() * JOY_RADIUS
	var a := 0.35 if _joy_index != -1 else 0.14
	draw_circle(base, JOY_RADIUS, Color(1, 1, 1, a * 0.35))
	draw_arc(base, JOY_RADIUS, 0, TAU, 48, Color(1, 1, 1, a), 3.0)
	draw_arc(base, JOY_RADIUS * 1.15, 0, TAU, 48, Color(0.8, 0.1, 0.1, a * 0.7 if sprinting else a * 0.25), 2.0)
	draw_circle(knob, 46.0, Color(1, 1, 1, a + 0.15))
	# Buttons
	_draw_button(_flash_center(), "ضوء", _btn_flash_down, font)
	_draw_button(_turn_center(), "التفت", _btn_turn_down, font)

func _draw_button(c: Vector2, label: String, down: bool, font: Font) -> void:
	draw_circle(c, 62.0, Color(0, 0, 0, 0.45 if not down else 0.7))
	draw_arc(c, 62.0, 0, TAU, 40, Color(0.75, 0.7, 0.65, 0.5), 3.0)
	var fs := 30
	var ts := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
	draw_string(font, c + Vector2(-ts.x * 0.5, ts.y * 0.3), label, HORIZONTAL_ALIGNMENT_CENTER, -1, fs, Color(0.85, 0.8, 0.75, 0.75))
