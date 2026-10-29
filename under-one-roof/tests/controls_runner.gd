extends Node

var failures := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Game.delete_save()
	Game.new_game()
	get_tree().change_scene_to_file("res://scenes/main.tscn")
	await _wait(0.5)
	# click through the intro narration and dialogue like a player would
	for i in 60:
		if Game.has("intro_done") and not Game.input_locked:
			break
		_press("interact")
		Director.main.fader._tap()
		await _wait(0.25)
	_expect(Game.has("intro_done"), "intro finished with the interact key")
	var p = Director.player()
	var w = Director.world()

	# 1. walk out of the house through the door
	var start: Vector2 = p.global_position
	await _hold("move_down", 0.8)
	await _hold("move_right", 0.85)
	await _hold("move_down", 2.0)
	await _wait(1.0)
	var z: Dictionary = w.zone_at(p.global_position)
	_expect(not z["indoor"], "walked out of the house (now in %s, from %s to %s)" % [z["id"], start, p.global_position])

	# 2. houses block movement
	var house_door: Vector2 = w.spot_pos("spawn_inn_out")
	p.global_position = house_door + Vector2(-30, 4)
	await _wait(0.2)
	await _hold("move_up", 1.5)
	_expect(p.global_position.y > house_door.y - 20, "the inn wall blocks Gideon (y=%.1f door=%.1f)" % [p.global_position.y, house_door.y])

	# 3. water blocks movement
	p.global_position = Vector2(24 * 16, 74 * 16)
	await _wait(0.2)
	await _hold("move_down", 2.0)
	var tile := Vector2i(p.global_position / 16.0)
	_expect(not w.is_blocked(tile.x, tile.y), "Gideon never stands on water (tile %s)" % tile)

	# 4. talk to Bjorn with the interact key
	var bjorn = w.npcs["bjorn"]
	p.global_position = bjorn.global_position + Vector2(0, -18)
	p.face("down")
	await _wait(0.3)
	print("dbg player ", p.global_position, " bjorn ", bjorn.global_position, " vis ", bjorn.visible, " overl ", p.reach.get_overlapping_areas().map(func(a): return a.get_meta("iid", "?")), " locked ", Game.input_locked, " busy ", Director.busy)
	_expect(p.target != null and p.target.get_meta("iid") == "bjorn", "Bjorn is targeted when facing him")
	_press("interact")
	await _wait(0.3)
	_expect(Director.busy and Director.main.dialogue.visible, "dialogue opened")
	for i in 40:
		if not Director.busy:
			break
		_press("interact")
		await _wait(0.2)
	_expect(Game.has("c1_has_fish") and Game.count("fish_basket") == 1, "Bjorn gave the fish basket")
	_expect(not Game.input_locked, "control returned to the player")

	# 5. walk into the inn and deliver the basket
	p.global_position = w.spot_pos("spawn_inn_out") + Vector2(0, 6)
	await _wait(0.2)
	await _hold("move_up", 0.8)
	await _wait(1.0)
	_expect(w.zone_at(p.global_position)["id"] == "inn_in", "entered the inn by walking into the door")
	var sigrid = w.npcs["sigrid"]
	p.global_position = sigrid.global_position + Vector2(0, 30)
	p.face("up")
	await _hold("move_up", 0.3)
	await _wait(0.3)
	_press("interact")
	for i in 40:
		await _wait(0.2)
		if not Director.busy:
			break
		_press("interact")
	_expect(Game.has("c1_fish"), "fish delivered by talking to Sigrid (target=%s)" % [p.target.get_meta("iid") if p.target else "none"])

	# 6. the timing mini-game opens and resolves on key presses
	p.global_position = w.spot_pos("fence_spot")
	p.face("up")
	await _wait(0.3)
	_press("interact")
	for i in 60:
		await _wait(0.15)
		if not Director.busy:
			break
		_press("interact")
	_expect(not Director.busy, "fence mini-game finished")

	# 7. journal opens and pauses
	_press("menu")
	await _wait(0.2)
	_expect(Director.main.journal.is_open() and get_tree().paused, "journal opens and pauses the game")
	_press("menu")
	await _wait(0.2)
	_expect(not get_tree().paused, "journal closes")

	# 8. save / load round trip
	Game.save_game(p.global_position)
	var money := Game.money
	Game.money = 0
	_expect(Game.load_game() and Game.money == money and Game.has("c1_fish"), "save and load restore the state")
	Game.pending_load = false

	# 9. chapter 4 night: Elias only walks while Gideon keeps up, then the barn voice
	for f in ["ch2", "ch3", "ch4", "met_elias", "bridge_open", "found_edmund_letter"]:
		Game.set_flag(f)
	await _wait(0.3)
	Director.run_event("elias", w.npcs["elias"])
	for i in 80:
		if Game.has("follow_active") and not Game.input_locked:
			break
		_press("interact")
		Director.main.fader._tap()
		await _wait(0.25)
	_expect(Game.has("follow_active") and Game.hour() >= 22, "night follow started")
	var elias = w.npcs["elias"]
	var e0: Vector2 = elias.global_position
	await _wait(1.5)
	_expect(elias.global_position.distance_to(e0) < 1.0 or p.global_position.distance_to(e0) < 150.0, "Elias waits when Gideon is far")
	for i in 120:
		if Game.has("elias_left_barn"):
			break
		if elias.visible:
			p.global_position = elias.global_position + Vector2(-60, 0)
		await _wait(0.25)
	_expect(Game.has("elias_left_barn"), "Elias visited the barn and left")
	p.global_position = w.spot_pos("spawn_barn_out") + Vector2(0, 8)
	await _wait(0.3)
	await _hold("move_up", 0.6)
	for i in 40:
		if Game.has("ch5"):
			break
		_press("interact")
		Director.main.fader._tap()
		await _wait(0.25)
	_expect(Game.has("heard_voice") and Game.has("ch5"), "heard the voice and woke up in chapter 5")

	print("==== CONTROLS: %d failures ====" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _expect(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		failures += 1


func _wait(t: float) -> void:
	await get_tree().create_timer(t, true).timeout


func _press(action: String) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	Input.parse_input_event(e)
	var r := InputEventAction.new()
	r.action = action
	r.pressed = false
	Input.parse_input_event(r)


func _hold(action: String, t: float) -> void:
	Input.action_press(action)
	await _wait(t)
	Input.action_release(action)
