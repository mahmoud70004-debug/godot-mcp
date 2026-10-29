extends CanvasLayer
## Modal panels: document reader, Henrik's shop and the timing mini-game.

signal closed
signal _mg_press

var _dim: ColorRect


func _ready() -> void:
	layer = 30
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.55)
	UI.full_rect(_dim)
	add_child(_dim)
	visible = false


func _clear() -> void:
	for c in _dim.get_children():
		c.queue_free()


func _center_panel(w: float, h: float) -> PanelContainer:
	var p := UI.panel()
	p.set_anchors_preset(Control.PRESET_CENTER)
	p.offset_left = -w / 2
	p.offset_right = w / 2
	p.offset_top = -h / 2
	p.offset_bottom = h / 2
	_dim.add_child(p)
	return p


# ---------------------------------------------------------------- reader
func read(title: String, body: String) -> void:
	if Game.fast:
		print("  <read> ", title)
		await get_tree().process_frame
		return
	_clear()
	visible = true
	var p := _center_panel(420, 270)
	p.add_theme_stylebox_override("panel", UI.panel_style(Color(0.96, 0.91, 0.78), UI.WOOD, 4, 3))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	var t := UI.label(title, 18, UI.WOOD, HORIZONTAL_ALIGNMENT_CENTER)
	body = Loc.t(body)
	v.add_child(t)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var b := UI.label(body, 14)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(b)
	var close := UI.button("إغلاق")
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.focus_mode = Control.FOCUS_ALL
	close.pressed.connect(func(): closed.emit())
	v.add_child(close)
	close.call_deferred("grab_focus")
	Audio.sfx("pickup", 0.7)
	await closed
	visible = false


# ---------------------------------------------------------------- shop
func shop(items: Array, title: String) -> void:
	if Game.fast:
		await get_tree().process_frame
		return
	_clear()
	visible = true
	var p := _center_panel(440, 290)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	v.add_child(UI.label(title, 17, UI.WOOD, HORIZONTAL_ALIGNMENT_CENTER))
	var money := UI.label("", 13, UI.INK_SOFT, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(money)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	var rows := []
	var refresh := func():
		money.text = Loc.t("معك %d كرونة") % Game.money
		for r in rows:
			var it: Dictionary = r["item"]
			var owned: bool = it.get("unique", false) and (Game.count(it["id"]) > 0 or Game.has("bought_" + it["id"]))
			var price: int = Director.price(it)
			r["btn"].text = Loc.t("مُشترى") if owned else Loc.t("%d ك") % price
			r["btn"].disabled = owned or Game.money < price or not Game.check(it.get("if", null))
	for it in items:
		var row := HBoxContainer.new()
		row.layout_direction = Loc.layout()
		row.add_theme_constant_override("separation", 8)
		var ic := TextureRect.new()
		ic.texture = UI.icon(it["id"])
		ic.custom_minimum_size = Vector2(24, 24)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		row.add_child(ic)
		var def: Dictionary = Story.ITEMS.get(it["id"], {})
		var info := UI.label("%s — %s" % [Loc.t(def.get("name", it["id"])), Loc.t(it.get("blurb", def.get("desc", "")))], 12)
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		var btn := UI.button("")
		btn.custom_minimum_size = Vector2(72, 0)
		btn.pressed.connect(func():
			await Director.buy(it)
			refresh.call())
		row.add_child(btn)
		list.add_child(row)
		rows.append({"item": it, "btn": btn})
	refresh.call()
	var close := UI.button("إغلاق")
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(func(): closed.emit())
	v.add_child(close)
	await closed
	visible = false


# ---------------------------------------------------------------- timing mini-game
## Press when the moving marker is inside the gold zone. Returns true on success.
func minigame(kind: String) -> bool:
	if Game.fast:
		await get_tree().process_frame
		return true
	_clear()
	visible = true
	var cfg: Dictionary = {
		"fishing": {"title": "الصيد", "hint": "اضغط عندما يكون المؤشر في المنطقة الذهبية لتسحب السمكة", "rounds": 2, "zone": 0.16, "speed": 1.25},
		"repair": {"title": "إصلاح", "hint": "اطرق المسمار في اللحظة المناسبة", "rounds": 3, "zone": 0.24, "speed": 1.0},
		"chop": {"title": "تقطيع الحطب", "hint": "اضرب بالفأس عندما يمر المؤشر بالمنطقة الذهبية", "rounds": 3, "zone": 0.22, "speed": 1.1},
		"rope": {"title": "تجهيز القارب", "hint": "شُدّ الحبال في التوقيت الصحيح", "rounds": 3, "zone": 0.26, "speed": 0.9},
	}.get(kind, {"title": "", "hint": "", "rounds": 2, "zone": 0.2, "speed": 1.0})
	var p := _center_panel(380, 150)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	v.add_child(UI.label(cfg["title"], 17, UI.WOOD, HORIZONTAL_ALIGNMENT_CENTER))
	var hint := UI.label(cfg["hint"], 12, UI.INK_SOFT, HORIZONTAL_ALIGNMENT_CENTER)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(hint)
	var bar := Control.new()
	bar.custom_minimum_size = Vector2(340, 26)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(bar)
	var status := UI.label("", 13, UI.INK, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(status)
	var tap := UI.button("الآن!", 16)
	tap.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	tap.custom_minimum_size = Vector2(120, 0)
	tap.pressed.connect(func(): _mg_press.emit())
	v.add_child(tap)

	var state := {"pos": 0.0, "dir": 1.0, "zone_at": 0.5, "hits": 0, "misses": 0, "flash": 0.0}
	var zone_w: float = cfg["zone"]
	bar.draw.connect(func():
		var w := bar.size.x
		bar.draw_rect(Rect2(0, 4, w, 18), Color(0.3, 0.22, 0.15))
		bar.draw_rect(Rect2((state["zone_at"] - zone_w / 2) * w, 4, zone_w * w, 18), UI.GOLD)
		var x: float = state["pos"] * w
		bar.draw_rect(Rect2(x - 2, 0, 4, 26), Color.WHITE if state["flash"] <= 0 else Color(1, 0.4, 0.3)))
	var rounds: int = cfg["rounds"]
	var running := true
	var pressed := [false]
	var on_press := func(): pressed[0] = true
	_mg_press.connect(on_press)
	while running:
		state["zone_at"] = randf_range(0.2, 0.8)
		pressed[0] = false
		status.text = Loc.t("المحاولة %d من %d") % [state["hits"] + 1, rounds]
		while not pressed[0]:
			var dt := get_process_delta_time()
			state["pos"] += state["dir"] * dt * cfg["speed"]
			if state["pos"] > 1.0:
				state["pos"] = 1.0
				state["dir"] = -1.0
			elif state["pos"] < 0.0:
				state["pos"] = 0.0
				state["dir"] = 1.0
			state["flash"] -= dt
			bar.queue_redraw()
			await get_tree().process_frame
		if abs(state["pos"] - state["zone_at"]) <= zone_w / 2 + 0.01:
			state["hits"] += 1
			Audio.sfx({"fishing": "splash", "repair": "hammer", "chop": "chop", "rope": "select"}.get(kind, "select"))
		else:
			state["misses"] += 1
			state["flash"] = 0.3
			Audio.sfx("fail")
		if state["hits"] >= rounds or state["misses"] >= 3:
			running = false
	_mg_press.disconnect(on_press)
	var ok: bool = state["hits"] >= rounds
	status.text = Loc.t("أحسنت!") if ok else Loc.t("لم تنجح هذه المرة...")
	await get_tree().create_timer(0.8).timeout
	visible = false
	return ok


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		_mg_press.emit()
