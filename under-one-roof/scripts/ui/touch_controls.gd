extends CanvasLayer
## On-screen controls for phones: a floating joystick (left), an action button,
## a run toggle and a journal button (right). Works with mouse emulation too.

signal action_pressed
signal menu_pressed

const STICK_RADIUS := 34.0
const SCALE := 0.72              # compact controls that leave the scene visible
const IDLE_ALPHA := 0.6          # semi-transparent until touched

var _root: Control
var _stick: Control
var _action: Control
var _run: Control
var _menu: Control
var _stick_touch := -1
var _stick_origin := Vector2.ZERO
var _stick_pos := Vector2.ZERO
var _action_down := false


func _ready() -> void:
	layer = 11
	_root = Control.new()
	UI.full_rect(_root)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_stick = _make(Control.PRESET_BOTTOM_LEFT, Vector2(12, -106), Vector2(96, 96), _draw_stick)
	_stick.gui_input.connect(_stick_input)
	_action = _make(Control.PRESET_BOTTOM_RIGHT, Vector2(-76, -78), Vector2(64, 64), _draw_action)
	_action.gui_input.connect(func(e):
		if _pressed(e):
			_action_down = true
			_action.queue_redraw()
			action_pressed.emit()
		elif _released(e):
			_action_down = false
			_action.queue_redraw())
	_run = _make(Control.PRESET_BOTTOM_RIGHT, Vector2(-112, -52), Vector2(46, 46), _draw_run)
	_run.gui_input.connect(func(e):
		if _pressed(e):
			Game.touch_run = not Game.touch_run
			_run.queue_redraw())
	_menu = _make(Control.PRESET_BOTTOM_RIGHT, Vector2(-50, -112), Vector2(40, 40), _draw_menu)
	_menu.gui_input.connect(func(e):
		if _pressed(e):
			menu_pressed.emit())
	# shrink each control towards its screen corner
	for c in [_stick]:
		c.pivot_offset = Vector2(0, c.size.y)
		c.scale = Vector2.ONE * SCALE
	for c in [_action, _run, _menu]:
		c.pivot_offset = c.size
		c.scale = Vector2.ONE * SCALE
	_root.modulate.a = IDLE_ALPHA
	for c in [_stick, _action, _run, _menu]:
		c.gui_input.connect(func(e):
			if _pressed(e):
				_root.modulate.a = 0.92
			elif _released(e):
				_root.modulate.a = IDLE_ALPHA)


func _make(preset: int, offset: Vector2, size: Vector2, drawer: Callable) -> Control:
	var c := Control.new()
	c.set_anchors_preset(preset)
	c.offset_left = offset.x
	c.offset_top = offset.y
	c.offset_right = offset.x + size.x
	c.offset_bottom = offset.y + size.y
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	c.draw.connect(drawer)
	_root.add_child(c)
	return c


func set_active(on: bool) -> void:
	_root.visible = on and Game.settings.get("touch", true)
	if not on:
		_reset_stick()


func _pressed(e: InputEvent) -> bool:
	return (e is InputEventScreenTouch and e.pressed)


func _released(e: InputEvent) -> bool:
	return (e is InputEventScreenTouch and not e.pressed)


func _stick_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if e.pressed and _stick_touch == -1:
			_stick_touch = e.index
			_stick_origin = _stick.size / 2.0
			_update_stick(e.position)
		elif not e.pressed and e.index == _stick_touch:
			_reset_stick()
	elif e is InputEventScreenDrag and e.index == _stick_touch:
		_update_stick(e.position)


func _update_stick(local: Vector2) -> void:
	var d := local - _stick_origin
	if d.length() > STICK_RADIUS:
		d = d.normalized() * STICK_RADIUS
	_stick_pos = d
	var v := d / STICK_RADIUS
	Game.touch_vector = v if v.length() > 0.2 else Vector2.ZERO
	_stick.queue_redraw()


func _reset_stick() -> void:
	_stick_touch = -1
	_stick_pos = Vector2.ZERO
	Game.touch_vector = Vector2.ZERO
	if _stick:
		_stick.queue_redraw()


func _draw_stick() -> void:
	var c := _stick.size / 2.0
	_stick.draw_circle(c, 44, Color(0.15, 0.12, 0.10, 0.35))
	_stick.draw_arc(c, 44, 0, TAU, 48, Color(0.95, 0.89, 0.74, 0.7), 2.5, true)
	for a in [0.0, PI / 2, PI, PI * 1.5]:
		var p := c + Vector2.from_angle(a) * 34
		var pts := PackedVector2Array([p + Vector2.from_angle(a) * 5, p + Vector2.from_angle(a + 2.3) * 5, p + Vector2.from_angle(a - 2.3) * 5])
		_stick.draw_colored_polygon(pts, Color(0.95, 0.89, 0.74, 0.8))
	_stick.draw_circle(c + _stick_pos, 17, Color(0.95, 0.89, 0.74, 0.92))
	_stick.draw_arc(c + _stick_pos, 17, 0, TAU, 32, UI.WOOD, 2.0, true)


func _round_button(c: Control, active := false) -> Vector2:
	var center := c.size / 2.0
	var r := c.size.x / 2.0 - 2
	c.draw_circle(center, r, Color(0.95, 0.89, 0.74, 0.92) if not active else Color(1.0, 0.82, 0.4, 0.95))
	c.draw_arc(center, r, 0, TAU, 40, UI.WOOD, 2.5, true)
	return center


func _draw_action() -> void:
	var c := _round_button(_action, _action_down)
	var ink := UI.WOOD_DARK
	# a simple open hand
	_action.draw_rect(Rect2(c + Vector2(-8, -2), Vector2(15, 14)), ink)
	for i in 4:
		_action.draw_rect(Rect2(c + Vector2(-8 + i * 4, -14 + abs(i - 1.5) * 2), Vector2(3, 13)), ink)
	_action.draw_rect(Rect2(c + Vector2(7, 0), Vector2(6, 3)).abs(), ink)


func _draw_run() -> void:
	var c := _round_button(_run, Game.touch_run)
	var ink := UI.WOOD_DARK
	_run.draw_circle(c + Vector2(3, -11), 3.5, ink)
	_run.draw_line(c + Vector2(2, -7), c + Vector2(-2, 3), ink, 3)
	_run.draw_line(c + Vector2(-2, 3), c + Vector2(4, 8), ink, 3)
	_run.draw_line(c + Vector2(4, 8), c + Vector2(3, 13), ink, 3)
	_run.draw_line(c + Vector2(-2, 3), c + Vector2(-8, 10), ink, 3)
	_run.draw_line(c + Vector2(1, -5), c + Vector2(8, -1), ink, 3)
	_run.draw_line(c + Vector2(1, -5), c + Vector2(-6, -2), ink, 3)


func _draw_menu() -> void:
	var c := _round_button(_menu)
	var ink := UI.WOOD_DARK
	# a small book
	_menu.draw_rect(Rect2(c + Vector2(-9, -8), Vector2(18, 16)), ink)
	_menu.draw_rect(Rect2(c + Vector2(-7, -6), Vector2(6, 12)), UI.PAPER)
	_menu.draw_rect(Rect2(c + Vector2(1, -6), Vector2(6, 12)), UI.PAPER)
