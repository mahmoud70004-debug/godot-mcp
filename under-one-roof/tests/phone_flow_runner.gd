extends Node
## Touch-only test of the whole start of the game, the way a phone without a keyboard
## plays it: menu -> Play -> intro (Continue / Skip) -> dialogue -> joystick -> action
## button -> doors -> journal -> settings (language) -> music page. No keyboard events.

var failures := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var saved_settings: Dictionary = Game.settings.duplicate()
	Game.settings["text_speed"] = 2
	Game.delete_save()

	# ---- 1. main menu -> Play (no save: starts a new game directly) ----
	get_tree().change_scene_to_file("res://scenes/title.tscn")
	await _wait(1.0)
	var title = get_tree().current_scene
	_expect(title.has_method("_open_page"), "main menu is showing")
	var play: Button = title._menu_box.get_node("play")
	_expect(play != null and play.text.strip_edges().ends_with(Loc.t("ابدأ اللعب")), "Play is the first menu item")
	await _tap_control(play)
	await _wait(1.2)
	_expect(get_tree().current_scene.scene_file_path == "res://scenes/main.tscn", "Play opened the game scene")
	var main = Director.main

	# ---- 2. the intro accepts taps and leads into the house ----
	_expect(main.fader._continue.visible, "intro shows a Continue button")
	var taps := 0
	while not Game.has("intro_done") and taps < 80:
		if main.fader._continue.visible:
			await _tap_control(main.fader._continue)
		elif main.dialogue.visible:
			await _tap_at(Vector2(320, 320))
		await _wait(0.35)
		taps += 1
	_expect(Game.has("intro_done"), "intro + first dialogue finished with taps only (%d taps)" % taps)
	await _wait(1.0)
	var p = Director.player()
	_expect(Director.world().zone_at(p.global_position)["id"] == "home_in", "Gideon is inside the Ashford home")
	_expect(not Game.input_locked and main.touch._root.visible, "touch controls are visible and active")

	# ---- 3. joystick moves Gideon ----
	var start: Vector2 = p.global_position
	await _drag_stick(Vector2(0, 30), 0.8)
	_expect(p.global_position.distance_to(start) > 15.0, "joystick moved Gideon (%.0f px)" % p.global_position.distance_to(start))

	# ---- 4. action button talks to Margaret ----
	var mg = Director.world().npcs["margaret"]
	p.global_position = mg.global_position + Vector2(0, -20)
	p.face("down")
	await _wait(0.4)
	await _tap_control(main.touch._action)
	await _wait(0.4)
	_expect(main.dialogue.visible, "action button opened a conversation")
	for i in 20:
		if not main.dialogue.visible:
			break
		await _tap_at(Vector2(320, 320))
		await _wait(0.3)
	_expect(not main.dialogue.visible and not Game.input_locked, "conversation closed with taps")

	# ---- 5. walk out of the door with the joystick ----
	p.global_position = Director.world().spot_pos("spawn_home_in") + Vector2(0, -6)
	await _wait(0.2)
	await _drag_stick(Vector2(0, 34), 1.4)
	await _wait(1.0)
	_expect(not Director.world().zone_at(p.global_position)["indoor"], "walked out through the door with the joystick")

	# ---- 6. journal button + language switch from the in-game settings ----
	await _tap_control(main.touch._menu)
	await _wait(0.3)
	_expect(main.journal.is_open(), "journal button opened the journal")
	var tabs: HBoxContainer = main.journal._tabs
	await _tap_control(tabs.get_child(tabs.get_child_count() - 1))
	await _wait(0.3)
	var en := _find_button(main.journal._content, "English")
	_expect(en != null, "settings page lists English")
	if en:
		await _tap_control(en)
	await _wait(1.5)
	_expect(Loc.lang == "en", "language switched to English")
	var main2 = Director.main
	_expect(main2 != null and main2 != main and not main2.journal.is_open(), "game reloaded in the new language")
	if main2:
		var q: String = main2.hud._quest_title.text
		_expect(q != "" and not _has_arabic(q), "quest title is now English: '%s'" % q)
	Loc.set_lang("ar")
	Game.settings["lang"] = "ar"

	# ---- 7. title: settings & music pages with taps ----
	Director.to_title()
	await _wait(1.2)
	title = get_tree().current_scene
	await _tap_control(title._menu_box.get_node("music"))
	await _wait(0.4)
	var b := _find_button(title._page_body, "▶")
	_expect(b != null, "music page has play buttons")
	if b:
		await _tap_control(b)
		await _wait(0.4)
		_expect(Game.settings["music_on"] and Audio.current_music() != "", "a track is playing: %s" % Audio.current_music())
	var stop := _find_button(title._page_body, "■")
	if stop:
		await _tap_control(stop)
		await _wait(0.4)
	_expect(not Game.settings["music_on"] and Audio.current_music() == "", "music stopped completely")
	var saved = JSON.parse_string(FileAccess.get_file_as_string("user://settings.json"))
	_expect(typeof(saved) == TYPE_DICTIONARY and saved.get("music_on") == false, "music choice saved to disk")

	# ---- 8. Skip intro path ----
	Game.settings = saved_settings
	Game.settings["music_on"] = true
	Game.save_settings()
	Game.delete_save()
	title._close_page()
	await _tap_control(title._menu_box.get_node("play"))
	await _wait(1.2)
	main = Director.main
	await _tap_control(main.fader._skip)
	await _wait(1.5)
	_expect(main.dialogue.visible, "Skip intro jumps straight to the house dialogue")
	await _tap_control(main.dialogue._skip_btn)
	await _wait(0.6)
	_expect(Game.has("intro_done") and not Game.input_locked, "dialogue Skip finishes the conversation")

	print("==== PHONE FLOW: %d failures ====" % failures)
	Game.delete_save()
	get_tree().quit(1 if failures > 0 else 0)


# ------------------------------------------------------------------ touch helpers
func _expect(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		failures += 1


func _wait(t: float) -> void:
	await get_tree().create_timer(t, true).timeout


func _has_arabic(s: String) -> bool:
	for ch in s:
		if ch.unicode_at(0) >= 0x0600 and ch.unicode_at(0) <= 0x06FF:
			return true
	return false


func _screen(canvas_pos: Vector2) -> Vector2:
	return get_viewport().get_final_transform() * canvas_pos


func _touch(pos: Vector2, pressed: bool, index := 0) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = pos
	e.pressed = pressed
	Input.parse_input_event(e)


func _tap_at(canvas_pos: Vector2) -> void:
	var pos := _screen(canvas_pos)
	_touch(pos, true)
	await get_tree().process_frame
	_touch(pos, false)
	await get_tree().process_frame


func _tap_control(c: Control) -> void:
	if c == null:
		return
	await _tap_at(c.get_global_rect().get_center())


func _drag_stick(offset: Vector2, hold: float) -> void:
	var stick: Control = Director.main.touch._stick
	var c := stick.get_global_rect().get_center()
	_touch(_screen(c), true, 1)
	await get_tree().process_frame
	var d := InputEventScreenDrag.new()
	d.index = 1
	d.position = _screen(c + offset)
	d.relative = offset
	Input.parse_input_event(d)
	await _wait(hold)
	_touch(_screen(c + offset), false, 1)
	await get_tree().process_frame


func _find_button(root: Node, text: String) -> Button:
	for n in root.find_children("*", "Button", true, false):
		if n.is_visible_in_tree() and text in n.text:
			return n
	return null
