extends CanvasLayer
## Gideon's notebook / pause menu: quests, clues, bag, collectibles and settings.

signal closed

var _dim: ColorRect
var _content: VBoxContainer
var _tabs: HBoxContainer
var _tab := 0
var _open := false

const TABS := ["المهام", "الأدلة", "الحقيبة", "المقتنيات", "الإعدادات"]


func _ready() -> void:
	layer = 25
	process_mode = Node.PROCESS_MODE_ALWAYS
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.55)
	UI.full_rect(_dim)
	add_child(_dim)
	var p := UI.panel()
	p.set_anchors_preset(Control.PRESET_CENTER)
	p.offset_left = -270
	p.offset_right = 270
	p.offset_top = -165
	p.offset_bottom = 165
	_dim.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	var title := UI.label("دفتر غيديون", 18, UI.WOOD, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(title)
	_tabs = HBoxContainer.new()
	_tabs.layout_direction = Loc.layout()
	_tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	_tabs.add_theme_constant_override("separation", 4)
	v.add_child(_tabs)
	for i in TABS.size():
		var b := UI.button(TABS[i], 13)
		var idx := i
		b.pressed.connect(func(): _show(idx))
		_tabs.add_child(b)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 5)
	scroll.add_child(_content)
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.layout_direction = Loc.layout()
	bottom.add_theme_constant_override("separation", 8)
	v.add_child(bottom)
	var resume := UI.button("متابعة اللعب")
	resume.pressed.connect(close)
	bottom.add_child(resume)
	var save := UI.button("حفظ")
	save.pressed.connect(func(): Director.save_now())
	bottom.add_child(save)
	var quit := UI.button("القائمة الرئيسية")
	quit.pressed.connect(func():
		close()
		Director.to_title())
	bottom.add_child(quit)
	visible = false


func is_open() -> bool:
	return _open


func open() -> void:
	_open = true
	visible = true
	get_tree().paused = true
	_show(_tab)
	Audio.sfx("select")


func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	get_tree().paused = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if _open and event.is_action_pressed("menu"):
		get_viewport().set_input_as_handled()
		close()


func _line(text: String, size := 13, color := UI.INK) -> Label:
	var l := UI.label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(l)
	return l


func _show(i: int) -> void:
	_tab = i
	for j in _tabs.get_child_count():
		var b: Button = _tabs.get_child(j)
		b.add_theme_stylebox_override("normal", UI.panel_style(Color(1.0, 0.93, 0.72) if j == i else UI.PAPER_DARK, UI.GOLD if j == i else UI.WOOD, 2, 4))
	for c in _content.get_children():
		c.queue_free()
	match i:
		0: _quests()
		1: _clues()
		2: _bag()
		3: _collect()
		4: _settings()


func _quests() -> void:
	var q: Dictionary = Director.current_quest()
	_line("%s — %s" % [Loc.t(Director.chapter_number_text()), Loc.t(Director.chapter_title())], 15, UI.WOOD)
	if q.get("title", "") != "":
		_line("◆ " + q["title"], 14)
		_line(q.get("text", ""), 13, UI.INK_SOFT)
	_line("")
	_line("مهام جانبية", 15, UI.WOOD)
	var any := false
	for s in Story.SIDE_QUESTS:
		if Game.check(s["show"]):
			any = true
			var done := Game.check(s["done"])
			_line(("✓ " if done else "○ ") + Loc.t(s["title"]), 14, UI.INK_SOFT if done else UI.INK)
			if not done:
				_line(s["text"], 12, UI.INK_SOFT)
	if not any:
		_line("لا توجد مهام جانبية بعد. تحدّث إلى أهل القرية.", 12, UI.INK_SOFT)
	_line("")
	_line(Loc.t("مكانتك في القرية: %s") % Loc.t(Director.reputation_text()), 13, UI.WOOD)


func _clues() -> void:
	if Game.clues.is_empty():
		_line("لم تدوّن أي دليل بعد.", 13, UI.INK_SOFT)
	for c in Game.clues:
		_line("• " + Loc.t(str(c)), 13)


func _bag() -> void:
	if Game.inventory.is_empty():
		_line("الحقيبة فارغة.", 13, UI.INK_SOFT)
	for it in Game.inventory:
		var def: Dictionary = Story.ITEMS.get(it["id"], {})
		var row := HBoxContainer.new()
		row.layout_direction = Loc.layout()
		row.add_theme_constant_override("separation", 8)
		var ic := TextureRect.new()
		ic.texture = UI.icon(it["id"])
		ic.custom_minimum_size = Vector2(24, 24)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		row.add_child(ic)
		var l := UI.label("%s ×%d — %s" % [Loc.t(def.get("name", it["id"])), it["n"], Loc.t(def.get("desc", ""))], 12)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		if def.has("read"):
			var b := UI.button("اقرأ", 12)
			var id: String = it["id"]
			b.pressed.connect(func():
				close()
				Director.use_item(id))
			row.add_child(b)
		_content.add_child(row)


func _collect() -> void:
	for group in Story.COLLECTION_GROUPS:
		var have := Game.counter(group["counter"])
		_line("%s: %d / %d" % [Loc.t(group["name"]), have, group["total"]], 14, UI.INK if have < group["total"] else UI.WOOD)
		_line(group["desc"], 12, UI.INK_SOFT)


func _settings() -> void:
	SettingsUI.build_settings(_content, func(): call_deferred("_language_changed"))
	_line("")
	_line("التحكم: الأسهم أو WASD للحركة، Shift للركض، E أو المسافة للتفاعل، J أو Esc لفتح الدفتر.", 12, UI.INK_SOFT)
	_line("على الهاتف: عصا التحكم يسارًا، وزر اليد للتفاعل، وزر الجري، وزر الدفتر.", 12, UI.INK_SOFT)


## Rebuild the whole game screen in the new language (state is kept through a quick save).
func _language_changed() -> void:
	close()
	if Game.has("follow_active"):
		Game.toast.emit("ستظهر اللغة الجديدة كاملة بعد هذا المشهد")
		return
	Game.save_game(Director.player().global_position)
	if Game.load_game():
		get_tree().change_scene_to_file("res://scenes/main.tscn")
