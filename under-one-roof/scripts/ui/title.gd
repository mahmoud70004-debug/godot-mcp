extends Control
## Main menu: the living village itself (the same painted world the game uses, with its
## shimmering water, gulls, chimney smoke and lit lamps) seen at dusk while the view
## drifts slowly over the harbour, and the menu on the left: Play, Settings, Music.
## Sub-pages open in a parchment panel on the right.

const WORLD_SCRIPT := preload("res://scripts/world/world.gd")
# slow drift over the village: [world centre, zoom]
const VIEWS := [[Vector2(1330, 930), 1.05], [Vector2(1180, 560), 1.0], [Vector2(1560, 1020), 1.1], [Vector2(700, 480), 1.0]]

var _layer: CanvasLayer
var _world: Node2D
var _menu_box: VBoxContainer
var _page: PanelContainer
var _page_body: VBoxContainer
var _page_title: Label
var _t := 0.0
var _current_page := ""


func _ready() -> void:
	UI.full_rect(self)
	Game.input_locked = true
	Game.time_running = false
	Director.main = null
	Audio.music(Game.settings.get("menu_track", "village"))
	Audio.ambience("sea")
	_build_backdrop()
	_build_ui()
	Loc.language_changed.connect(_rebuild)


# ---------------------------------------------------------------- backdrop
func _build_backdrop() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = -1
	add_child(_layer)
	_world = Node2D.new()
	_world.set_script(WORLD_SCRIPT)
	_layer.add_child(_world)
	var dusk := CanvasModulate.new()
	dusk.color = Color(0.93, 0.8, 0.74)
	_layer.add_child(dusk)
	for g in _world._glows:
		g.visible = true
	# darker band behind the menu on the left so the text stays readable
	var shade := TextureRect.new()
	var g := GradientTexture2D.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0.09, 0.06, 0.05, 0.86))
	grad.set_color(1, Color(0.09, 0.06, 0.05, 0.0))
	g.gradient = grad
	g.fill_from = Vector2(0, 0)
	g.fill_to = Vector2(1, 0)
	g.width = 64
	g.height = 8
	shade.texture = g
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	shade.offset_right = 330
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	_update_view()


func _update_view() -> void:
	# ease between the views, 24 s each
	var n := VIEWS.size()
	var f := fmod(_t / 24.0, float(n))
	var i := int(f)
	var k := smoothstep(0.0, 1.0, f - i)
	var a: Array = VIEWS[i]
	var b: Array = VIEWS[(i + 1) % n]
	var centre: Vector2 = (a[0] as Vector2).lerp(b[0], k)
	var z: float = lerpf(a[1], b[1], k)
	var vp := get_viewport_rect().size
	z *= maxf(1.0, vp.y / 360.0)
	_layer.scale = Vector2(z, z)
	# keep the village right of the menu
	_layer.offset = (vp * Vector2(0.62, 0.5) - centre * z).round()


func _process(delta: float) -> void:
	_t += delta
	_update_view()


# ---------------------------------------------------------------- menu
func _rebuild() -> void:
	for c in get_children():
		if c != _layer and not c is TextureRect:
			c.queue_free()
	_build_ui()
	if _current_page != "":
		_open_page(_current_page)


func _build_ui() -> void:
	var left := VBoxContainer.new()
	left.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	left.offset_left = 28
	left.offset_right = 290
	left.offset_top = 16
	left.offset_bottom = -30
	left.add_theme_constant_override("separation", 2)
	add_child(left)

	var titles := {"ar": ["تحت سقف واحد", "UNDER ONE ROOF"], "en": ["Under One Roof", "تحت سقف واحد"], "ja": ["ひとつ屋根の下", "UNDER ONE ROOF"]}
	var t: Array = titles[Loc.lang]
	var title := Label.new()
	title.text = t[0]
	title.add_theme_font_override("font", Loc.title_font())
	title.add_theme_font_size_override("font_size", 36 if Loc.lang == "ar" else 30)
	title.add_theme_color_override("font_color", UI.GOLD)
	title.add_theme_color_override("font_outline_color", Color(0.18, 0.1, 0.05))
	title.add_theme_constant_override("outline_size", 8)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	title.add_theme_constant_override("shadow_offset_y", 3)
	left.add_child(title)
	var sub := Label.new()
	sub.text = t[1]
	sub.add_theme_font_override("font", load("res://assets/fonts/IMFellEnglishSC.ttf") if t[1].begins_with("U") else load("res://assets/fonts/Lalezar.ttf"))
	sub.add_theme_font_size_override("font_size", 15)
	sub.add_theme_color_override("font_color", UI.PAPER)
	left.add_child(sub)
	var orn := Label.new()
	orn.text = "———  ✦  ———"
	orn.add_theme_color_override("font_color", Color(UI.GOLD, 0.8))
	orn.add_theme_font_size_override("font_size", 12)
	left.add_child(orn)
	var place := UI.label("هرافنفيك · آيسلندا · 1887", 12, UI.PAPER)
	place.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if not Loc.rtl() else HORIZONTAL_ALIGNMENT_LEFT
	left.add_child(place)
	for l in [title, sub, orn, place]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	left.add_child(spacer)

	_menu_box = VBoxContainer.new()
	_menu_box.add_theme_constant_override("separation", 2)
	left.add_child(_menu_box)
	_menu_item("ابدأ اللعب", "play")
	_menu_item("الإعدادات", "settings")
	_menu_item("الموسيقى", "music")
	if not OS.has_feature("mobile") and not OS.has_feature("web"):
		_menu_item("خروج", "quit")
	var first: Button = _menu_box.get_child(0)
	(func(): if is_instance_valid(first) and first.is_inside_tree(): first.grab_focus()).call_deferred()

	var foot := Label.new()
	foot.text = Loc.t("قصة عن عائلة، وثروة، وحقيقة مدفونة.") + "   v" + str(ProjectSettings.get_setting("application/config/version", "2.0"))
	foot.add_theme_font_size_override("font_size", 11)
	foot.add_theme_color_override("font_color", Color(UI.PAPER, 0.75))
	foot.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	foot.offset_left = 28
	foot.offset_top = -26
	foot.offset_right = 420
	foot.offset_bottom = -8
	add_child(foot)

	_page = UI.panel()
	_page.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	_page.offset_left = -392
	_page.offset_right = -18
	_page.offset_top = 18
	_page.offset_bottom = -18
	_page.visible = false
	add_child(_page)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 8)
	_page.add_child(pv)
	var head := HBoxContainer.new()
	head.layout_direction = Loc.layout()
	pv.add_child(head)
	_page_title = UI.label("", 18, UI.WOOD)
	_page_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_page_title)
	var back := UI.button("رجوع", 13)
	back.pressed.connect(_close_page)
	head.add_child(back)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pv.add_child(scroll)
	_page_body = VBoxContainer.new()
	_page_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_body.add_theme_constant_override("separation", 8)
	scroll.add_child(_page_body)


func _menu_item(text: String, id: String) -> void:
	var b := Button.new()
	b.text = "  " + Loc.t(text)
	b.name = id
	b.flat = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(220, 34)
	b.add_theme_font_override("font", Loc.menu_font())
	b.add_theme_font_size_override("font_size", 22 if Loc.lang != "ja" else 18)
	b.add_theme_color_override("font_color", UI.PAPER)
	b.add_theme_color_override("font_hover_color", UI.GOLD)
	b.add_theme_color_override("font_focus_color", UI.GOLD)
	b.add_theme_color_override("font_pressed_color", Color(1, 0.9, 0.6))
	b.add_theme_color_override("font_outline_color", Color(0.15, 0.08, 0.04))
	b.add_theme_constant_override("outline_size", 5)
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.35, 0.2, 0.1, 0.55)
	hover.border_color = UI.GOLD
	hover.border_width_left = 3
	hover.set_corner_radius_all(3)
	for st in ["hover", "focus", "pressed"]:
		b.add_theme_stylebox_override(st, hover)
	b.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	b.mouse_entered.connect(func(): b.grab_focus())
	b.focus_entered.connect(func():
		b.text = "◆ " + Loc.t(text)
		Audio.sfx("blip", 1.4))
	b.focus_exited.connect(func(): b.text = "  " + Loc.t(text))
	b.pressed.connect(func(): _on_menu(id))
	_menu_box.add_child(b)


func _on_menu(id: String) -> void:
	Audio.sfx("select")
	Audio.buzz(20)
	match id:
		"play":
			if Game.has_save():
				_open_page("play")
			else:
				_new_game()
		"settings", "music":
			_open_page(id)
		"quit":
			get_tree().quit()


func _open_page(id: String) -> void:
	_current_page = id
	_page.visible = true
	for c in _page_body.get_children():
		c.queue_free()
	match id:
		"play":
			_page_title.text = Loc.t("ابدأ اللعب")
			var cont := UI.button("متابعة الرحلة", 16)
			cont.custom_minimum_size = Vector2(0, 40)
			cont.pressed.connect(_continue)
			_page_body.add_child(cont)
			var new := UI.button("لعبة جديدة", 16)
			new.custom_minimum_size = Vector2(0, 40)
			new.pressed.connect(func(): _open_page("confirm"))
			_page_body.add_child(new)
		"confirm":
			_page_title.text = Loc.t("لعبة جديدة")
			var warn := UI.label("سيُستبدل الحفظ الحالي برحلة جديدة. هل أنت متأكد؟", 13)
			warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_page_body.add_child(warn)
			var yes := UI.button("نعم، ابدأ من جديد", 15)
			yes.pressed.connect(_new_game)
			_page_body.add_child(yes)
			var no := UI.button("لا", 15)
			no.pressed.connect(func(): _open_page("play"))
			_page_body.add_child(no)
		"settings":
			_page_title.text = Loc.t("الإعدادات")
			SettingsUI.build_settings(_page_body, func(): call_deferred("_rebuild"))
		"music":
			_page_title.text = Loc.t("الموسيقى")
			SettingsUI.build_music(_page_body, func(): call_deferred("_open_page", "music"))


func _close_page() -> void:
	Audio.sfx("select")
	_current_page = ""
	_page.visible = false
	if _menu_box.get_child_count() > 0:
		_menu_box.get_child(0).grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if _page.visible and event.is_action_pressed("ui_cancel"):
		_close_page()


func _new_game() -> void:
	Audio.sfx("quest")
	Game.delete_save()
	Game.new_game()
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _continue() -> void:
	Audio.sfx("select")
	if Game.load_game():
		get_tree().change_scene_to_file("res://scenes/main.tscn")
