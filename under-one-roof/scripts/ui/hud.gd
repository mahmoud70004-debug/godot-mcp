extends CanvasLayer
## Heads-up display: location & quest (top-left), date/time & money (top-right),
## hotbar (bottom), toasts, interaction prompt and the quest marker.

signal journal_requested

const SLOTS := 8

var player: Node2D
var _loc: Label
var _season: Label
var _quest_title: Label
var _quest_text: Label
var _day: Label
var _time: Label
var _money: Label
var _sun: Control
var _hotbar: HBoxContainer
var _slots: Array = []
var _toasts: VBoxContainer
var _prompt: PanelContainer
var _prompt_label: Label
var _tooltip: PanelContainer
var _tooltip_label: Label
var _marker: Control
var _root: Control
var _last_tap := {"slot": -1, "t": 0}


func _ready() -> void:
	layer = 10
	_root = Control.new()
	UI.full_rect(_root)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# --- top-left: place + quest ------------------------------------------
	var left := VBoxContainer.new()
	left.position = Vector2(8, 6)
	left.add_theme_constant_override("separation", 4)
	_root.add_child(left)
	var loc_panel := UI.panel()
	loc_panel.custom_minimum_size = Vector2(170, 0)
	left.add_child(loc_panel)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", -4)
	loc_panel.add_child(lv)
	_loc = UI.label("هرافنفيك", 15)
	lv.add_child(_loc)
	_season = UI.label("ربيع — 1887", 11, UI.INK_SOFT)
	lv.add_child(_season)

	var quest := UI.panel(Color(0.95, 0.89, 0.74, 0.92))
	quest.custom_minimum_size = Vector2(170, 0)
	quest.mouse_filter = Control.MOUSE_FILTER_STOP
	quest.gui_input.connect(func(e):
		if _is_tap(e):
			journal_requested.emit())
	left.add_child(quest)
	var qv := VBoxContainer.new()
	qv.add_theme_constant_override("separation", -2)
	quest.add_child(qv)
	_quest_title = UI.label("", 12, UI.WOOD)
	qv.add_child(_quest_title)
	_quest_text = UI.label("", 11)
	_quest_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_quest_text.custom_minimum_size = Vector2(154, 0)
	qv.add_child(_quest_text)

	# --- top-right: date, time, money ---------------------------------------
	var right := VBoxContainer.new()
	right.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	right.offset_left = -150
	right.offset_right = -8
	right.offset_top = 6
	right.add_theme_constant_override("separation", 4)
	_root.add_child(right)
	var date_panel := UI.panel()
	right.add_child(date_panel)
	var dh := HBoxContainer.new()
	dh.add_theme_constant_override("separation", 6)
	date_panel.add_child(dh)
	_sun = Control.new()
	_sun.custom_minimum_size = Vector2(26, 26)
	_sun.draw.connect(_draw_sun)
	dh.add_child(_sun)
	var dv := VBoxContainer.new()
	dv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dv.add_theme_constant_override("separation", -4)
	dh.add_child(dv)
	_day = UI.label("", 13)
	dv.add_child(_day)
	_time = UI.label("", 13)
	dv.add_child(_time)
	var money_panel := UI.panel()
	right.add_child(money_panel)
	var mh := HBoxContainer.new()
	money_panel.add_child(mh)
	var coin := TextureRect.new()
	coin.texture = UI.icon("coin")
	coin.custom_minimum_size = Vector2(18, 18)
	coin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mh.add_child(coin)
	_money = UI.label("0", 14, UI.INK, HORIZONTAL_ALIGNMENT_LEFT)
	_money.text_direction = Control.TEXT_DIRECTION_LTR
	_money.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mh.add_child(_money)
	var kr := UI.label("كرونة", 11, UI.INK_SOFT)
	mh.add_child(kr)

	# --- hotbar --------------------------------------------------------------
	var hb_panel := UI.panel(UI.WOOD)
	hb_panel.add_theme_stylebox_override("panel", UI.panel_style(Color(0.55, 0.36, 0.20), UI.WOOD_DARK, 3, 5))
	hb_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hb_panel.anchor_left = 0.5
	hb_panel.anchor_right = 0.5
	hb_panel.offset_left = -150
	hb_panel.offset_right = 150
	hb_panel.offset_top = -44
	hb_panel.offset_bottom = -6
	_root.add_child(hb_panel)
	_hotbar = HBoxContainer.new()
	_hotbar.alignment = BoxContainer.ALIGNMENT_CENTER
	_hotbar.add_theme_constant_override("separation", 3)
	hb_panel.add_child(_hotbar)
	for i in SLOTS:
		var slot := PanelContainer.new()
		slot.custom_minimum_size = Vector2(30, 28)
		slot.mouse_filter = Control.MOUSE_FILTER_STOP
		var idx := i
		slot.gui_input.connect(func(e):
			if _is_tap(e):
				_slot_tapped(idx))
		var tex := TextureRect.new()
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tex.custom_minimum_size = Vector2(22, 22)
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(tex)
		var n := UI.label("", 10, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
		n.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		n.add_theme_color_override("font_outline_color", Color.BLACK)
		n.add_theme_constant_override("outline_size", 3)
		n.text_direction = Control.TEXT_DIRECTION_LTR
		n.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(n)
		_hotbar.add_child(slot)
		_slots.append({"panel": slot, "tex": tex, "n": n})

	_tooltip = UI.panel()
	_tooltip.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_tooltip.anchor_left = 0.5
	_tooltip.anchor_right = 0.5
	_tooltip.offset_left = -160
	_tooltip.offset_right = 160
	_tooltip.offset_top = -100
	_tooltip.offset_bottom = -50
	_tooltip.visible = false
	_root.add_child(_tooltip)
	_tooltip_label = UI.label("", 12)
	_tooltip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tooltip.add_child(_tooltip_label)

	# --- toasts & prompt -------------------------------------------------------
	_toasts = VBoxContainer.new()
	_toasts.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toasts.anchor_left = 0.5
	_toasts.anchor_right = 0.5
	_toasts.offset_left = -130
	_toasts.offset_right = 130
	_toasts.offset_top = 8
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toasts.add_theme_constant_override("separation", 4)
	_root.add_child(_toasts)

	_prompt = UI.panel(Color(0.18, 0.12, 0.08, 0.85))
	_prompt.add_theme_stylebox_override("panel", UI.panel_style(Color(0.18, 0.12, 0.08, 0.85), UI.GOLD, 1, 6))
	_prompt.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_prompt.offset_left = -230
	_prompt.offset_right = -96
	_prompt.offset_top = -96
	_prompt.offset_bottom = -70
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_prompt)
	_prompt_label = UI.label("", 12, UI.PAPER, HORIZONTAL_ALIGNMENT_CENTER)
	_prompt.add_child(_prompt_label)
	_prompt.visible = false

	_marker = Control.new()
	_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marker.draw.connect(_draw_marker)
	UI.full_rect(_marker)
	_root.add_child(_marker)
	move_child(_root, 0)

	Game.money_changed.connect(func(_m, d): _refresh_money(d))
	Game.inventory_changed.connect(_refresh_hotbar)
	Game.time_changed.connect(_refresh_time)
	Game.flags_changed.connect(refresh_quest)
	Game.toast.connect(show_toast)
	Game.clue_added.connect(func(t): show_toast("دليل جديد في الدفتر"))
	_refresh_money(0)
	_refresh_hotbar()
	_refresh_time()
	refresh_quest()


func _is_tap(e: InputEvent) -> bool:
	return (e is InputEventScreenTouch and e.pressed)


func set_location(text: String) -> void:
	if _loc.text != text and text != "":
		_loc.text = text


func set_prompt(text: String) -> void:
	_prompt.visible = text != ""
	_prompt_label.text = text


func set_gameplay_visible(on: bool) -> void:
	_root.visible = on


func _refresh_money(delta: int) -> void:
	_money.text = str(Game.money)
	if delta != 0:
		var tw := create_tween()
		_money.modulate = Color(1, 0.8, 0.2) if delta > 0 else Color(1, 0.4, 0.3)
		tw.tween_property(_money, "modulate", Color.WHITE, 0.6)


func _refresh_time() -> void:
	_day.text = "%s %d" % [Game.weekday(), Game.day]
	_time.text = Game.clock_text()
	_sun.queue_redraw()


func refresh_quest() -> void:
	var q: Dictionary = Director.current_quest()
	_quest_title.text = q.get("title", "")
	_quest_text.text = q.get("short", "")
	_quest_title.get_parent().get_parent().visible = q.get("title", "") != ""


func _refresh_hotbar() -> void:
	for i in SLOTS:
		var s: Dictionary = _slots[i]
		var sel := i == Game.selected_slot and i < Game.inventory.size()
		s["panel"].add_theme_stylebox_override("panel", UI.panel_style(
			Color(1.0, 0.94, 0.78) if sel else UI.PAPER_DARK, UI.GOLD if sel else UI.WOOD_DARK, 2, 3))
		if i < Game.inventory.size():
			var it: Dictionary = Game.inventory[i]
			s["tex"].texture = UI.icon(it["id"])
			s["n"].text = str(it["n"]) if it["n"] > 1 else ""
		else:
			s["tex"].texture = null
			s["n"].text = ""


func _slot_tapped(i: int) -> void:
	if i >= Game.inventory.size():
		return
	var now := Time.get_ticks_msec()
	var item: String = Game.inventory[i]["id"]
	if _last_tap["slot"] == i and now - _last_tap["t"] < 450 or (i == Game.selected_slot and _tooltip.visible):
		Director.use_item(item)
	_last_tap = {"slot": i, "t": now}
	Game.selected_slot = i
	_refresh_hotbar()
	var def: Dictionary = Story.ITEMS.get(item, {})
	_tooltip_label.text = "%s\n%s" % [def.get("name", item), def.get("desc", "")]
	if def.has("read"):
		_tooltip_label.text += "\n(اضغط مرة أخرى للقراءة)"
	_tooltip.visible = true
	var my := Time.get_ticks_msec()
	_last_tap["shown"] = my
	await get_tree().create_timer(3.0).timeout
	if _last_tap.get("shown", 0) == my:
		_tooltip.visible = false


func show_toast(text: String) -> void:
	var p := UI.panel(Color(0.18, 0.12, 0.08, 0.88))
	p.add_theme_stylebox_override("panel", UI.panel_style(Color(0.18, 0.12, 0.08, 0.88), UI.GOLD, 1, 6))
	var l := UI.label(text, 13, UI.PAPER, HORIZONTAL_ALIGNMENT_CENTER)
	p.add_child(l)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toasts.add_child(p)
	p.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.25)
	tw.tween_interval(2.6)
	tw.tween_property(p, "modulate:a", 0.0, 0.5)
	tw.tween_callback(p.queue_free)


func _process(_d: float) -> void:
	_marker.queue_redraw()


func _draw_sun() -> void:
	var h := Game.hour()
	var c := Vector2(13, 13)
	if h >= 6 and h < 19:
		_sun.draw_circle(c, 7, Color(1.0, 0.82, 0.25))
		for i in 8:
			var a := i * PI / 4.0
			_sun.draw_line(c + Vector2.from_angle(a) * 9, c + Vector2.from_angle(a) * 12, Color(1.0, 0.75, 0.2), 2)
	else:
		_sun.draw_circle(c, 8, Color(0.92, 0.92, 0.80))
		_sun.draw_circle(c + Vector2(4, -3), 7, UI.PAPER)


func _draw_marker() -> void:
	if player == null or not _root.visible or Game.input_locked:
		return
	var target = Director.quest_target()
	if target == null:
		return
	var xf := player.get_viewport().get_canvas_transform()
	var screen: Vector2 = xf * target
	var vp := _marker.get_viewport_rect().size
	var margin := 28.0
	var t := Time.get_ticks_msec() / 1000.0
	var r := Rect2(Vector2(margin + 20, margin + 60), vp - Vector2(margin * 2 + 40, margin * 2 + 150))
	var inside := r.has_point(screen)
	var gold := Color(1.0, 0.82, 0.28)
	if inside:
		var p := screen + Vector2(0, -34 + sin(t * 4.0) * 3.0)
		_marker.draw_colored_polygon(PackedVector2Array([p + Vector2(-6, -8), p + Vector2(6, -8), p + Vector2(0, 2)]), gold)
		_marker.draw_polyline(PackedVector2Array([p + Vector2(-6, -8), p + Vector2(6, -8), p + Vector2(0, 2), p + Vector2(-6, -8)]), Color(0.3, 0.18, 0.08), 1.5)
	else:
		var center := vp / 2.0
		var dir := (screen - center).normalized()
		var p := center
		for i in 60:
			var q := p + dir * 8.0
			if not r.has_point(q):
				break
			p = q
		var a := dir.angle()
		var pts := PackedVector2Array([p + Vector2.from_angle(a) * 10, p + Vector2.from_angle(a + 2.5) * 8, p + Vector2.from_angle(a - 2.5) * 8])
		_marker.draw_colored_polygon(pts, gold)
		pts.append(pts[0])
		_marker.draw_polyline(pts, Color(0.3, 0.18, 0.08), 1.5)
