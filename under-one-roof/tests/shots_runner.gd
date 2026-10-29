extends Node

var out_dir := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await _wait(0.5)
	get_tree().change_scene_to_file("res://scenes/title.tscn")
	await _wait(2.0)
	await _shot("01_title")
	Game.delete_save()
	Game.new_game()
	get_tree().change_scene_to_file("res://scenes/main.tscn")
	await _wait(1.6)
	await _shot("02_intro_card")
	for i in 4:
		Director.main.fader._tap()
		await _wait(2.0)
	await _wait(1.0)
	await _shot("03_intro_dialogue")
	await _skip_dialogue()
	await _shot("04_home_interior")
	await Director.teleport("spawn_home_out", false)
	await _wait(1.0)
	await _shot("05_outside_home")
	var w = Director.world()
	var p = Director.player()
	p.global_position = w.spot_pos("henrik_cart") + Vector2(30, 10)
	await _wait(1.0)
	await _shot("06_square")
	p.global_position = w.spot_pos("bjorn_dock") + Vector2(0, -20)
	p.face("down")
	await _wait(1.0)
	await _shot("07_harbor")
	Director.run_event("bjorn", w.npcs["bjorn"])
	await _wait(1.5)
	await _shot("08_bjorn_dialogue")
	await _skip_dialogue()
	# mini-game
	Director.run_event("bjorn_boat")
	await _wait(1.5)
	await _skip_dialogue(1)
	await _wait(0.6)
	await _shot("09_minigame")
	for i in 8:
		Director.main.panels._mg_press.emit()
		await _wait(0.3)
	await _skip_dialogue()
	# shop
	Game.add_money(40)
	Director.main.panels.shop(Story.SHOP, "عربة هنريك — بضائع من وراء البحار")
	await _wait(0.6)
	await _shot("10_shop")
	Director.main.panels.closed.emit()
	await _wait(0.3)
	# reader
	Director.main.panels.read(Story.ITEMS["father_letters"]["name"], Story.ITEMS["father_letters"]["read"])
	await _wait(0.6)
	await _shot("11_reader")
	Director.main.panels.closed.emit()
	await _wait(0.3)
	# chapter card
	Director.main.fader.fade_out(0.1)
	await _wait(0.2)
	Director.main.fader.chapter_card("الفصل الخامس", "الرجل في الحظيرة")
	await _wait(1.0)
	await _shot("12_chapter_card")
	await _wait(2.5)
	Director.main.fader.fade_in(0.1)
	# barn interior with Edmund
	for f in ["ch2", "ch3", "ch4", "ch5", "met_edmund"]:
		Game.set_flag(f)
	await Director.teleport("spawn_barn_in", false)
	await _wait(1.0)
	await _shot("13_barn_interior")
	# night: following Elias
	Game.set_time(22, 30)
	p.global_position = w.spot_pos("elias_walk_1")
	await _wait(1.2)
	await _shot("14_night_bridge")
	# the ending: evening village
	for f in ["ch6", "ch7", "ch8", "elias_fled", "ending", "roof_fixed"]:
		Game.set_flag(f)
	Game.set_time(19, 10)
	await Director.teleport("ending_view", false)
	await _wait(1.5)
	await _shot("15_ending_evening")
	get_tree().quit()


func _skip_dialogue(max_lines := 30) -> void:
	for i in max_lines:
		if not Director.main.dialogue.visible:
			break
		Director.main.dialogue._advance()
		await _wait(0.12)
		Director.main.dialogue._advance()
		await _wait(0.15)
	await _wait(0.4)


func _wait(t: float) -> void:
	await get_tree().create_timer(t, true).timeout


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	print("shot ", name)
