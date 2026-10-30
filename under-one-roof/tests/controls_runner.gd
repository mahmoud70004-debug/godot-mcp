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
	# the porch steps may be climbed a little, the inn's main wall may not
	_expect(p.global_position.y > house_door.y - 64, "the inn wall blocks Gideon (y=%.1f door=%.1f)" % [p.global_position.y, house_door.y])

	# 3. water blocks movement
	# start on the western beach, just above the waterline
	var shore := 60
	while shore < 95 and not w.is_blocked(24, shore + 1):
		shore += 1
	_expect(w.is_blocked(24, shore + 1), "found the western shore (tile row %d)" % shore)
	p.global_position = Vector2(24 * 16 + 8, (shore - 2) * 16 + 8)
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
	await _world_features()

	print("==== CONTROLS: %d failures ====" % failures)
	get_tree().quit(1 if failures > 0 else 0)


## Camera zoom, villagers' daily routines and roofs/canopies fading over Gideon.
func _world_features() -> void:
	var p = Director.player()
	var w = Director.world()
	for i in 150:
		if not (Director.busy or Game.input_locked):
			break
		if Director.main.dialogue.visible:
			Director.main.dialogue._advance()
		Director.main.fader._tap()
		await _wait(0.2)
	_expect(not Game.input_locked, "control is back after the chapter 5 morning")
	await Director.teleport("spawn_inn_out", false)
	await _wait(0.5)
	# zoom: keyboard, mouse wheel, HUD buttons, two-finger pinch; saved; smooth
	p.set_zoom_level(1.0)
	await _wait(0.8)
	var z0: float = p.camera.zoom.x
	_press("zoom_in")
	await _wait(0.05)
	_expect(p.camera.zoom.x > z0 and p.camera.zoom.x < p.zoom_level(), "zoom eases in smoothly (%.3f -> %.3f)" % [z0, p.camera.zoom.x])
	await _wait(0.8)
	_expect(absf(p.camera.zoom.x - 1.15) < 0.01, "zoom-in key: %.2f" % p.camera.zoom.x)
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	Input.parse_input_event(wheel)
	await _wait(0.8)
	_expect(p.camera.zoom.x < 1.1, "mouse wheel zooms out (%.2f)" % p.camera.zoom.x)
	var hud_in: Control = Director.main.hud.find_child("ZoomIn", true, false)
	_expect(hud_in != null, "HUD has a zoom-in button")
	if hud_in:
		var before: float = p.zoom_level()
		var t := InputEventScreenTouch.new()
		t.pressed = true
		t.position = get_viewport().get_final_transform() * hud_in.get_global_rect().get_center()
		Input.parse_input_event(t)
		await _wait(0.05)
		t = t.duplicate()
		t.pressed = false
		Input.parse_input_event(t)
		await _wait(0.6)
		_expect(p.zoom_level() > before, "HUD + button zooms in (%.2f -> %.2f)" % [before, p.zoom_level()])
	var before_pinch: float = p.zoom_level()
	for i in 2:
		var t := InputEventScreenTouch.new()
		t.index = i
		t.pressed = true
		t.position = get_viewport().get_final_transform() * Vector2(380 + i * 40, 200)
		Input.parse_input_event(t)
	await _wait(0.05)
	for k in 6:
		var d := InputEventScreenDrag.new()
		d.index = 1
		d.position = get_viewport().get_final_transform() * Vector2(420 + (k + 1) * 15, 200)
		Input.parse_input_event(d)
		await _wait(0.03)
	for i in 2:
		var t := InputEventScreenTouch.new()
		t.index = i
		t.pressed = false
		t.position = get_viewport().get_final_transform() * Vector2(380, 200)
		Input.parse_input_event(t)
	await _wait(0.6)
	_expect(p.zoom_level() > before_pinch * 1.5, "two-finger pinch zooms in (%.2f -> %.2f)" % [before_pinch, p.zoom_level()])
	_expect(p.zoom_level() <= p.ZOOM_MAX, "zoom is clamped")
	await _wait(0.6)
	var saved = JSON.parse_string(FileAccess.get_file_as_string("user://settings.json"))
	_expect(absf(float(saved.get("zoom", 0)) - p.zoom_level()) < 0.001, "zoom is saved in the settings")
	p.set_zoom_level(p.ZOOM_MIN)
	await Director.teleport("spawn_inn_in", false)
	await _wait(1.0)
	var view: Vector2 = p.get_viewport_rect().size / p.camera.zoom
	_expect(view.x <= p.room_rect.size.x + 1 and view.y <= p.room_rect.size.y + 1, "indoors the camera never shows past the room (view %s room %s zone %s)" % [view, p.room_rect.size, Director._zone_id])
	await Director.teleport("spawn_inn_out", false)
	p.set_zoom_level(1.0)
	await _wait(0.3)

	# a building fades while Gideon stands behind it
	var inn_root: Node2D = null
	for oc in w._occluders:
		var spr = oc[0].get_child(0)
		if spr is Sprite2D and spr.texture.resource_path.ends_with("ref_inn.png"):
			inn_root = oc[0]
	_expect(inn_root != null, "the inn is registered as an occluder")
	if inn_root:
		p.global_position = Vector2(1194, 270)
		await _wait(0.8)
		_expect(inn_root.modulate.a < 0.6, "the inn fades while Gideon is behind it (a=%.2f)" % inn_root.modulate.a)
		p.global_position = w.spot_pos("spawn_inn_out")
		await _wait(0.8)
		_expect(inn_root.modulate.a > 0.95, "the inn is opaque again in front (a=%.2f)" % inn_root.modulate.a)

	# daily routine: at 18:00 the fisherman leaves the pier and walks to the inn
	Game.set_time(17, 50)
	await _wait(0.3)
	var f = w.npcs["fisher_a"]
	_expect(f.visible and f.current_spot == "amb_fish_1", "fisherman at work on the beach in the afternoon")
	var from: Vector2 = f.position
	Game.set_time(18, 5)
	await _wait(2.0)
	_expect(f.current_spot == "amb_inn_1" and f.position.distance_to(from) > 20.0 and f._walking, "at 18:00 he walks (not teleports) towards the inn")
	var target: Vector2 = w.spot_pos("amb_inn_1")
	var path: PackedVector2Array = w.find_path(from, target)
	_expect(path.size() > 3, "his route follows the paths (%d waypoints)" % path.size())
	var ok_path := true
	for pt in path:
		if w._astar.is_point_solid(Vector2i(pt / 16.0)) and pt != target:
			ok_path = false
	_expect(ok_path, "the route never crosses walls or water")
	for i in 90:
		if not f._walking:
			break
		await _wait(0.5)
	_expect(f.position.distance_to(target) < 2.0, "he arrived at the inn (%.0f px away)" % f.position.distance_to(target))
	# family members from the reference sheet walk with their own animation
	for id in ["clara", "margaret", "jonas", "leif", "edmund"]:
		var n = w.npcs[id]
		var was_visible: bool = n.visible
		n.scripted = true
		n.set_present(true)
		var start_pos: Vector2 = n.position
		var frames := {}
		n.walk_to(start_pos + Vector2(40, 0), 30.0)
		for k in 20:
			await _wait(0.05)
			frames[n._sprite.frame] = true
		await _wait(1.2)
		_expect(frames.size() >= 3 and n.facing == "right", "%s walks with an animated cycle (%d frames seen)" % [id, frames.size()])
		n.teleport(start_pos)
		n.scripted = false
		n.set_present(was_visible)
	var porter = w.npcs["porter"]
	Game.set_time(9, 0)
	await _wait(0.5)
	_expect(porter.visible and porter.patrol.size() >= 3, "the porter runs his errands (%d stops)" % porter.patrol.size())


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
