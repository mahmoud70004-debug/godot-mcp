class_name SettingsUI
extends RefCounted
## Builders for the Settings and Music pages (used by the title menu and the in-game journal).
## Every option here changes something real and is saved in user://settings.json.

const TRACKS := [
	{"id": "village", "name": "القرية", "desc": "لحن دافئ للحياة اليومية والميناء"},
	{"id": "mystery", "name": "الغموض", "desc": "توتر خفيف للتحقيق واكتشاف الأسرار"},
	{"id": "melancholy", "name": "الحنين", "desc": "لحن هادئ لمشاهد العائلة والماضي"},
]


static func _row(parent: Control, title: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.layout_direction = Loc.layout()
	row.add_theme_constant_override("separation", 10)
	var l := UI.label(title, 13)
	l.custom_minimum_size = Vector2(88, 0)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(l)
	parent.add_child(row)
	return row


static func _slider(row: HBoxContainer, key: String) -> HSlider:
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = Game.settings[key]
	s.custom_minimum_size = Vector2(120, 24)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.layout_direction = Control.LAYOUT_DIRECTION_LTR
	s.value_changed.connect(func(v):
		Game.settings[key] = v
		Audio.refresh_volumes()
		Game.save_settings())
	row.add_child(s)
	return s


static func _choice(row: HBoxContainer, options: Array, current: int, on_pick: Callable) -> Array:
	var buttons := []
	for i in options.size():
		var b := UI.button(options[i], 11)
		b.toggle_mode = true
		b.button_pressed = i == current
		b.custom_minimum_size = Vector2(0, 28)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		buttons.append(b)
		row.add_child(b)
	for i in buttons.size():
		var idx: int = i
		buttons[i].pressed.connect(func():
			for j in buttons.size():
				buttons[j].set_pressed_no_signal(j == idx)
			on_pick.call(idx))
	_mark(buttons)
	return buttons


static func _mark(buttons: Array) -> void:
	for b in buttons:
		b.toggled.connect(func(on): b.add_theme_stylebox_override("normal", UI.panel_style(Color(1.0, 0.92, 0.66) if on else UI.PAPER, UI.GOLD if on else UI.WOOD, 2, 4)))
		b.add_theme_stylebox_override("normal", UI.panel_style(Color(1.0, 0.92, 0.66) if b.button_pressed else UI.PAPER, UI.GOLD if b.button_pressed else UI.WOOD, 2, 4))


static func _toggle(parent: Control, title: String, key: String, after := Callable()) -> CheckButton:
	var row := _row(parent, title)
	var t := CheckButton.new()
	t.button_pressed = bool(Game.settings.get(key, true))
	t.toggled.connect(func(on):
		Game.settings[key] = on
		Game.save_settings()
		if after.is_valid():
			after.call())
	row.add_child(t)
	return t


## Builds the settings page. on_language(): called after the language changes so the
## caller can rebuild its screen in the new language.
static func build_settings(parent: Control, on_language: Callable) -> void:
	var langs := ["ar", "en", "ja"]
	var row := _row(parent, "اللغة")
	_choice(row, [Loc.NAMES["ar"], Loc.NAMES["en"], Loc.NAMES["ja"]], langs.find(Loc.lang), func(i):
		Game.settings["lang"] = langs[i]
		Game.save_settings()
		Loc.set_lang(langs[i])
		on_language.call())
	_slider(_row(parent, "صوت الموسيقى"), "music")
	_slider(_row(parent, "المؤثرات الصوتية"), "sfx")
	row = _row(parent, "سرعة النصوص")
	_choice(row, ["بطيئة", "عادية", "سريعة", "فورية"], int(Game.settings.get("text_speed", 1)), func(i):
		Game.settings["text_speed"] = i
		Game.save_settings())
	if OS.has_feature("mobile"):
		_toggle(parent, "الاهتزاز", "vibrate", func(): Audio.buzz(60))
		_toggle(parent, "إبقاء الشاشة مضاءة", "keep_on", func(): Game.apply_display())
	else:
		_toggle(parent, "ملء الشاشة", "fullscreen", func(): Game.apply_display())
		_toggle(parent, "الاهتزاز (للهاتف)", "vibrate")
	_toggle(parent, "إظهار أزرار اللمس", "touch", func():
		if Director.main:
			Director.refresh_touch())
	var reset := UI.button("استعادة الإعدادات الافتراضية", 12)
	reset.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	reset.pressed.connect(func():
		Game.reset_settings()
		Audio.refresh_volumes()
		on_language.call())
	parent.add_child(reset)


## Builds the music page: pick and preview one of the three original pieces,
## switch music off completely, and set the volume.
static func build_music(parent: Control, refresh: Callable) -> void:
	for tr in TRACKS:
		var row := HBoxContainer.new()
		row.layout_direction = Loc.layout()
		row.add_theme_constant_override("separation", 8)
		var playing: bool = Game.settings.get("music_on", true) and Audio.current_music() == tr["id"]
		var play := UI.button("■" if playing else "▶", 14)
		play.custom_minimum_size = Vector2(40, 32)
		var id: String = tr["id"]
		play.pressed.connect(func():
			if Audio.current_music() == id and Game.settings.get("music_on", true):
				Game.settings["music_on"] = false
				Audio.music("")
			else:
				Game.settings["music_on"] = true
				Game.settings["menu_track"] = id
				Audio.music(id)
			Game.save_settings()
			refresh.call())
		row.add_child(play)
		var info := VBoxContainer.new()
		info.add_theme_constant_override("separation", -3)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.custom_minimum_size = Vector2(150, 0)
		var chosen: bool = Game.settings.get("menu_track", "village") == id
		info.add_child(UI.label(Loc.t(tr["name"]) + ("  ◆" if chosen else ""), 15, UI.WOOD if chosen else UI.INK))
		var desc := UI.label(tr["desc"], 11, UI.INK_SOFT)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(desc)
		row.add_child(info)
		parent.add_child(row)
	var on := _row(parent, "الموسيقى")
	var t := CheckButton.new()
	t.button_pressed = Game.settings.get("music_on", true)
	t.toggled.connect(func(v):
		Game.settings["music_on"] = v
		Game.save_settings()
		Audio.music(Game.settings.get("menu_track", "village") if v else "")
		refresh.call())
	on.add_child(t)
	_slider(_row(parent, "مستوى الصوت"), "music")
	var note := UI.label("مقطوعات أصلية مولّدة لهذه اللعبة.", 11, UI.INK_SOFT)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(note)
