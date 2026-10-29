extends Node
## Runs the story: interactions, data-driven events (data/story.gd), doors, quests,
## chapter transitions and scripted cutscenes.

var main: Node = null          # set by main.gd
var busy := false
var skip_lines := false        # set by the dialogue "skip" button for the current conversation
var _zone_id := ""
var _zone_t := 0.0
var _following := false


func _process(delta: float) -> void:
	if main == null or not is_instance_valid(main):
		return
	_zone_t -= delta
	if _zone_t <= 0.0:
		_zone_t = 0.25
		_update_zone()
	if not busy and Game.time_running and Game.minutes >= 25 * 60:
		_pass_out()


# ---------------------------------------------------------------- helpers
func world():
	return main.world


func player():
	return main.player


func dialogue():
	return main.dialogue


func _lock(on: bool) -> void:
	Game.input_locked = on
	if main:
		main.touch.set_active(not on)
		main.hud.set_gameplay_visible(not on)
		if on:
			Game.touch_vector = Vector2.ZERO


# ---------------------------------------------------------------- interaction
func interact(area: Area2D) -> void:
	if busy or Game.input_locked:
		return
	var iid: String = area.get_meta("iid")
	if area.has_meta("door_to"):
		door_touched(area)
		return
	var npc = area.get_meta("npc") if area.has_meta("npc") else null
	if npc:
		npc.face_towards(player().global_position)
	await run_event(iid, npc)


func prompt_for(area: Area2D) -> String:
	if area == null:
		return ""
	var iid: String = area.get_meta("iid")
	if area.has_meta("npc"):
		return Loc.t("تحدّث: ") + Loc.t(Story.speaker_name(iid))
	if area.has_meta("label"):
		return area.get_meta("label")
	return Story.label_for(iid)


## True when interacting with `id` right now would do something.
func can_interact(id: String) -> bool:
	if Story.NPCS.has(id):
		return true
	var r := _resolve_event_id(id)
	for e in Story.EVENTS.get(r[0], []):
		if Game.check(_ctx_cond(e.get("if", null), r[1])):
			return not (e.get("lines", []).is_empty() and e.get("do", []).is_empty() and not e.has("mg") and not e.has("choice"))
	return false


func _resolve_event_id(id: String) -> Array:
	# generic handlers: herb_3 -> herb, coin_2 -> coin ...
	if Story.EVENTS.has(id):
		return [id, id]
	for prefix in ["herb_", "coin_", "shell_"]:
		if id.begins_with(prefix):
			return [prefix.trim_suffix("_"), id]
	if id.begins_with("collect_"):
		return ["collect", id]
	return [id, id]


func run_event(id: String, npc = null) -> void:
	if busy:
		return
	var r := _resolve_event_id(id)
	var key: String = r[0]
	var ctx: String = r[1]
	var entries = Story.EVENTS.get(key, null)
	if entries == null:
		if Story.NPCS.has(id):
			entries = [{"lines": [[id, Story.idle_line(id)]]}]
		else:
			return
	for e in entries:
		if Game.check(_ctx_cond(e.get("if", null), ctx)):
			busy = true
			_lock(true)
			await _play_entry(e, ctx, npc)
			skip_lines = false
			if main == null:
				busy = false
				return
			_lock(false)
			busy = false
			main.hud.refresh_quest()
			return


func _ctx_cond(cond, ctx: String):
	if cond == null:
		return null
	var out := []
	for t in cond:
		out.append(str(t).replace("$id", ctx))
	return out


func _play_entry(e: Dictionary, ctx: String, npc) -> void:
	for line in e.get("lines", []):
		await _say_line(line, ctx)
	if e.has("mg"):
		dialogue().close()
		player().play_action([16, 17])
		var ok: bool = await main.panels.minigame(e["mg"])
		player().stop_action()
		await do_actions(e.get("win" if ok else "lose", []), ctx)
	await do_actions(e.get("do", []), ctx)
	if e.has("choice"):
		var opts := []
		for c in e["choice"]:
			opts.append(c[0])
		var i: int = await dialogue().choose(opts)
		await do_actions(e["choice"][i][1], ctx)
	dialogue().close()
	if e.has("then"):
		var nxt: String = e["then"]
		busy = false
		await run_event(nxt, npc)
		busy = true


func _say_line(line, ctx: String) -> void:
	if skip_lines and not Game.fast:
		return
	var speaker: String = str(line[0])
	var text: String = Loc.t(str(line[1])).replace("$money", str(Game.money)).replace("$views", str(Game.counter("views")))
	var npc = world().npcs.get(speaker, null)
	if npc and npc.visible and speaker != "gideon":
		npc.face_towards(player().global_position)
	await dialogue().say(speaker, text)


## Executes an action list. Each action is an Array: [op, args...]
func do_actions(actions: Array, ctx := "") -> void:
	for a in actions:
		var op: String = a[0]
		match op:
			"set": Game.set_flag(str(a[1]).replace("$id", ctx))
			"clear": Game.set_flag(str(a[1]).replace("$id", ctx), false)
			"count": Game.add_counter(a[1], a[2] if a.size() > 2 else 1)
			"give":
				var n: int = a[2] if a.size() > 2 else 1
				Game.give(a[1], n)
				Game.toast.emit(Loc.t("حصلت على: %s%s") % [Loc.t(Story.ITEMS.get(a[1], {}).get("name", a[1])), (" ×%d" % n) if n > 1 else ""])
				Audio.sfx("pickup")
			"take": Game.take(a[1], a[2] if a.size() > 2 else 1)
			"take_all":
				var n := Game.count(a[1])
				Game.take(a[1], n)
			"sell":
				# ["sell", item, price_each]
				var n := Game.count(a[1])
				if n > 0:
					Game.take(a[1], n)
					Game.add_money(n * int(a[2]))
					Audio.sfx("coin")
					Game.toast.emit(Loc.t("بعت %d مقابل %d كرونة") % [n, n * int(a[2])])
			"money":
				Game.add_money(int(a[1]))
				if int(a[1]) > 0:
					Audio.sfx("coin")
					Game.toast.emit(Loc.t("+%d كرونة") % int(a[1]))
			"pay": Game.add_money(-int(a[1]))
			"rep":
				Game.add_counter("rep", int(a[1]))
				Game.toast.emit("ازدادت مكانتك في القرية")
			"clue":
				Game.add_clue(a[1])
				Audio.sfx("clue")
			"toast": Game.toast.emit(a[1])
			"sfx": Audio.sfx(a[1])
			"read":
				dialogue().close()
				await main.panels.read(a[1], a[2])
			"work":
				# ["work", minutes, text]
				dialogue().close()
				await _work(int(a[1]), a[2] if a.size() > 2 else "")
			"time": Game.set_time(int(a[1]), int(a[2]) if a.size() > 2 else 0)
			"advance": Game.advance(int(a[1]))
			"teleport": await teleport(a[1], a.size() > 2 and a[2])
			"fade_out": await main.fader.fade_out()
			"fade_in": await main.fader.fade_in()
			"narrate":
				dialogue().close()
				var was_black: bool = main.fader.is_black()
				if not was_black:
					await main.fader.fade_out()
				await main.fader.narrate(a[1])
				if not was_black and not (a.size() > 2 and a[2] == "stay"):
					await main.fader.fade_in()
			"chapter": await _chapter(int(a[1]))
			"sleep": await _sleep(a.size() > 1 and a[1] == "silent")
			"event":
				var was := busy
				busy = false
				await run_event(a[1])
				busy = was
				_lock(true)
			"cutscene":
				match a[1]:
					"follow_elias": await follow_elias()
					"farm_confrontation": await farm_confrontation()
					"final_scene": await final_scene()
			"morning": await _chapter_morning(int(a[1]))
			"shop":
				dialogue().close()
				await main.panels.shop(Story.SHOP, "عربة هنريك — بضائع من وراء البحار")
			"face":
				var n = world().npcs.get(a[1], null)
				if n:
					n.face(a[2])
			"walk":
				var n = world().npcs.get(a[1], null)
				if n:
					n.scripted = true
					n.set_present(true)
					await n.walk_to(world().spot_pos(a[2]), float(a[3]) if a.size() > 3 else 45.0)
			"release":
				var n = world().npcs.get(a[1], null)
				if n:
					n.scripted = false
					world().refresh()
			"place":
				world().npc_override[a[1]] = a[2]
				var n = world().npcs.get(a[1], null)
				if n:
					n.current_spot = ""
				world().refresh()
			"unplace":
				world().npc_override.erase(a[1])
				world().refresh()
			"wait": await get_tree().create_timer(0.01 if Game.fast else float(a[1])).timeout
			"save": save_now(true)
			"end_game": await _end_game()
			"player_face": player().face(a[1])
			_: push_warning("unknown action " + op)


func _work(mins: int, text: String) -> void:
	if text != "":
		Game.toast.emit(text)
	player().play_action([18, 17] if "أعشاب" in text or "الأغنام" in text else [16, 17])
	await get_tree().create_timer(0.01 if Game.fast else 1.2).timeout
	player().stop_action()
	await main.fader.fade_out(0.35)
	Audio.sfx("chop" if "حطب" in text else "select")
	await get_tree().create_timer(0.01 if Game.fast else 0.5).timeout
	Game.advance(mins)
	await main.fader.fade_in(0.35)


# ---------------------------------------------------------------- doors & movement
func door_touched(area: Area2D) -> void:
	if busy or Game.input_locked:
		return
	var id: String = area.get_meta("iid")
	var to: String = area.get_meta("door_to")
	for rule in Story.DOORS.get(id, []):
		if Game.check(rule.get("if", null)):
			if rule.get("allow", false):
				break
			busy = true
			_lock(true)
			# step back so the door does not retrigger immediately
			player().global_position += Vector2(0, 10)
			await _play_entry(rule, id, null)
			_lock(false)
			busy = false
			main.hud.refresh_quest()
			return
	if not world().has_spot(to):
		return
	busy = true
	_lock(true)
	Audio.sfx("door")
	await teleport(to, true)
	_lock(false)
	busy = false
	var after: String = Story.DOOR_EVENTS.get(id, "")
	if after != "":
		await run_event(after)


func teleport(spot: String, fade := true) -> void:
	if fade:
		await main.fader.fade_out(0.3)
	var p = player()
	p.global_position = world().spot_pos(spot)
	p.face(world().spot_dir(spot))
	_update_zone(true)
	p.camera.reset_smoothing()
	if fade:
		await main.fader.fade_in(0.3)


func _update_zone(force := false) -> void:
	var p = player()
	if p == null:
		return
	var z: Dictionary = world().zone_at(p.global_position)
	if z["id"] == _zone_id and not force:
		return
	var changed: bool = z["id"] != _zone_id
	_zone_id = z["id"]
	main.hud.set_location(z["name"])
	var cam: Camera2D = p.camera
	var r: Rect2
	if z["indoor"]:
		var a: Array = z["rect"]
		r = Rect2(a[0], a[1], a[2], a[3]).grow(48)
	else:
		r = world().outdoor_rect()
	cam.limit_left = int(r.position.x)
	cam.limit_top = int(r.position.y)
	cam.limit_right = int(r.end.x)
	cam.limit_bottom = int(r.end.y)
	main.set_indoor(z["indoor"])
	_update_music(z)
	if changed and not busy:
		var ev: String = Story.ZONE_EVENTS.get(z["id"], "")
		if ev != "":
			run_event(ev)


func _update_music(z: Dictionary) -> void:
	if Game.has("ending") and not z["indoor"]:
		Audio.music("ending")
	else:
		var m: String = z.get("music", "village")
		if Game.hour() >= 21 and not z["indoor"]:
			m = "mystery"
		Audio.music(m)
	if z["indoor"]:
		Audio.ambience("fire" if z["id"] in ["home_in", "inn_in", "study_in", "barn_in"] else "")
	elif z["id"] in ["harbor", "beach", "wreck"]:
		Audio.ambience("sea")
	else:
		Audio.ambience("wind")


# ---------------------------------------------------------------- quests
func current_quest() -> Dictionary:
	for q in Story.MAIN_QUESTS:
		var active := Game.check(q.get("if", null))
		if active and q.has("done") and Game.check(q["done"]):
			active = false
		if active:
			var text: String = Loc.t(q.get("text", ""))
			var short := text
			var target = q.get("target", null)
			if q.has("steps"):
				var lines := []
				var done_n := 0
				short = ""
				for s in q["steps"]:
					var done := Game.has(s[0])
					lines.append(("✓ " if done else "○ ") + Loc.t(s[1]))
					if done:
						done_n += 1
					elif short == "":
						short = Loc.t(s[1])
					if not done and target == null and s.size() > 2:
						target = _step_target(s)
				text = "\n".join(lines)
				short = "%s (%d/%d)" % [short, done_n, q["steps"].size()]
			if q.has("counter"):
				text = text % Game.counter(q["counter"])
				short = text
			return {"title": Loc.t(q["title"]), "text": text, "short": short, "target": target}
	return {}


func _step_target(s: Array):
	if s[2] is String:
		return s[2]
	for alt in s[2]:
		if Game.check(alt[0]):
			return alt[1]
	return null


func quest_target():
	var q := current_quest()
	var t = q.get("target", null)
	if t == null or world() == null:
		return null
	var pos: Vector2
	if Story.NPCS.has(t):
		var n = world().npcs[t]
		if not n.visible:
			return null
		pos = n.global_position
	elif world().has_spot(t):
		pos = world().spot_pos(t)
	else:
		return null
	# route through doors when the target is in another interior / outside
	var pz: Dictionary = world().zone_at(player().global_position)
	var tz: Dictionary = world().zone_at(pos)
	if pz["id"] == tz["id"] or (not pz["indoor"] and not tz["indoor"]):
		return pos
	if pz["indoor"]:
		return world().spot_pos(Story.INTERIOR_EXITS[pz["id"]])
	return world().spot_pos(Story.INTERIOR_DOORS[tz["id"]])


func chapter_number() -> int:
	for i in range(8, 0, -1):
		if Game.has("ch%d" % i):
			return i
	return 1


func chapter_number_text() -> String:
	return Story.CHAPTERS[chapter_number() - 1][0]


func chapter_title() -> String:
	if Game.has("ending"):
		return "بداية جديدة"
	return Story.CHAPTERS[chapter_number() - 1][1]


func reputation_text() -> String:
	var r := Game.counter("rep")
	if r >= 6:
		return "محبوب ومحترم"
	if r >= 3:
		return "يثق بك الناس"
	if r >= 1:
		return "يعرفك الناس بالخير"
	return "ابن عائلة فقيرة"


# ---------------------------------------------------------------- shop & items
func price(it: Dictionary) -> int:
	var p: int = it["price"]
	if Game.has("runa_discount"):
		p = int(round(p * 0.8))
	return p


func buy(it: Dictionary) -> void:
	var p := price(it)
	if Game.money < p:
		return
	Game.add_money(-p)
	Audio.sfx("coin")
	if it.get("unique", false):
		Game.set_flag("bought_" + it["id"])
	if not it.get("no_item", false):
		Game.give(it["id"], it.get("n", 1))
	Game.toast.emit(Loc.t("اشتريت: ") + Loc.t(Story.ITEMS.get(it["id"], {}).get("name", it["id"])))
	if it.has("do"):
		await do_actions(it["do"])


func use_item(id: String) -> void:
	var def: Dictionary = Story.ITEMS.get(id, {})
	if def.has("read") and not busy:
		busy = true
		_lock(true)
		await main.panels.read(def["name"], def["read"])
		if def.has("on_read"):
			await do_actions(def["on_read"])
		_lock(false)
		busy = false


func save_now(silent := false) -> void:
	if main == null or Game.has("ending_done"):
		return
	if Game.has("follow_active") or (busy and not silent):
		if not silent:
			Game.toast.emit("لا يمكن الحفظ الآن")
		return
	Game.save_game(player().global_position)


func to_title() -> void:
	get_tree().paused = false
	Game.time_running = false
	Game.input_locked = false
	busy = false
	main = null
	get_tree().change_scene_to_file("res://scenes/title.tscn")


func refresh_touch() -> void:
	if main:
		main.touch.set_active(not Game.input_locked)


# ---------------------------------------------------------------- chapters & sleep
func _chapter(n: int) -> void:
	for i in range(1, n + 1):
		Game.set_flag("ch%d" % i)
	dialogue().close()
	var was_black: bool = main.fader.is_black()
	if not was_black:
		await main.fader.fade_out()
	Audio.sfx("quest")
	await main.fader.chapter_card(Story.CHAPTERS[n - 1][0], Story.CHAPTERS[n - 1][1])
	if not was_black:
		await main.fader.fade_in()


## Ends a chapter overnight: next morning at home with the new chapter's title card.
func _chapter_morning(n: int) -> void:
	dialogue().close()
	if not main.fader.is_black():
		await main.fader.fade_out(1.0)
	Game.next_day()
	for i in range(1, n + 1):
		Game.set_flag("ch%d" % i)
	world().npc_override.clear()
	await teleport("game_start", false)
	player().face("down")
	Audio.sfx("quest")
	await main.fader.chapter_card(Story.CHAPTERS[n - 1][0], Story.CHAPTERS[n - 1][1])
	save_now(true)
	await main.fader.fade_in(1.0)


func _sleep(silent := false) -> void:
	dialogue().close()
	await main.fader.fade_out(1.0)
	Game.next_day()
	await teleport("game_start", false)
	player().face("down")
	if not silent:
		await main.fader.narrate("صباح يوم جديد...", false)
	save_now(true)
	await main.fader.fade_in(1.0)


func _pass_out() -> void:
	busy = true
	_lock(true)
	await main.fader.fade_out(1.2)
	await main.fader.narrate("أنهك التعب غيديون فغلبه النوم... حمله جيرانه إلى البيت.", false)
	Game.next_day()
	Game.add_money(-min(Game.money, 3))
	await teleport("game_start", false)
	await main.fader.fade_in(1.0)
	_lock(false)
	busy = false


# ---------------------------------------------------------------- cutscenes
## Opening scene of a new game: two short story cards over the dimmed Ashford home
## (Continue / Skip), the chapter title, then the family dialogue inside the house.
func intro() -> void:
	busy = true
	_lock(true)
	main.fader.skipped = false
	await main.fader.narrate("هرافنفيك، قرية صيد صغيرة على الساحل الغربي لآيسلندا.\nربيع عام 1887.", true, "تحت سقف واحد", "Under One Roof", true, 0.86)
	await main.fader.narrate(Story.INTRO_FAMILY, true, "", "", true, 0.86)
	if not main.fader.skipped:
		await main.fader.chapter_card(Story.CHAPTERS[0][0], Story.CHAPTERS[0][1])
	await main.fader.fade_in(0.8)
	_lock(false)
	busy = false
	await run_event("intro")


## Chapter 4 night: Gideon follows Elias across the bridge to the barn.
func follow_elias() -> void:
	var w = world()
	var elias = w.npcs["elias"]
	dialogue().close()
	await main.fader.fade_out(1.0)
	Game.set_time(22, 10)
	Game.set_flag("follow_active")
	await main.fader.narrate("في تلك الليلة، لم يستطع غيديون النوم.\nرأى إلياس يتسلّل خارج الضيعة حاملًا فانوسًا...", true)
	await teleport("follow_start", false)
	elias.scripted = true
	elias.set_present(true)
	elias.teleport(w.spot_pos("elias_walk_0"), "right")
	await main.fader.fade_in(1.0)
	_lock(false)
	busy = false
	Game.toast.emit("اتبع إلياس من مسافة آمنة")
	_following = true
	if Game.fast:
		player().global_position = w.spot_pos("barn_window")
	for i in range(1, 5):
		var target: Vector2 = w.spot_pos("elias_walk_%d" % i)
		while elias.global_position.distance_to(target) > 2.0:
			# Elias only moves while Gideon keeps up
			var d: float = player().global_position.distance_to(elias.global_position)
			if Game.fast:
				await elias.walk_to(target)
			elif d < 150.0:
				var step: Vector2 = (target - elias.position)
				await elias.walk_to(elias.position + step.limit_length(14.0), 34.0)
				if d < 28.0:
					Game.toast.emit("اقتربتَ كثيرًا! ابقَ خلفه")
			else:
				await get_tree().create_timer(0.2).timeout
	# Elias goes into the barn
	elias.set_present(false)
	Audio.sfx("door")
	Game.set_flag("elias_in_barn")
	await get_tree().create_timer(0.01 if Game.fast else 4.0).timeout
	elias.teleport(w.spot_pos("elias_walk_4"), "down")
	elias.set_present(true)
	Audio.sfx("door")
	await elias.walk_to(w.spot_pos("elias_walk_2"), 40.0)
	await elias.walk_to(w.spot_pos("elias_walk_1"), 40.0)
	elias.set_present(false)
	elias.scripted = false
	_following = false
	Game.set_flag("elias_left_barn")
	main.hud.refresh_quest()


## Chapter 8: the confrontation at the farm.
func farm_confrontation() -> void:
	var w = world()
	await teleport("gideon_farm", true)
	player().face("left")
	await do_actions([["place", "edmund", ""]])
	for line in Story.CONFRONTATION_A:
		await _say_line(line, "")
	# Edmund steps out of the barn
	dialogue().close()
	var ed = w.npcs["edmund"]
	ed.scripted = true
	ed.teleport(w.spot_pos("elias_walk_4"), "down")
	ed.set_present(true)
	Audio.sfx("door")
	await ed.walk_to(w.spot_pos("edmund_farm"), 30.0)
	ed.face("left")
	for line in Story.CONFRONTATION_B:
		await _say_line(line, "")
	dialogue().close()
	var el = w.npcs["elias"]
	el.scripted = true
	await el.walk_to(w.spot_pos("elias_walk_1"), 50.0)
	el.set_present(false)
	ed.scripted = false
	el.scripted = false
	w.npc_override.erase("edmund")
	Game.set_flag("elias_fled")
	await _ending()


func _ending() -> void:
	await main.fader.fade_out(1.5)
	Audio.music("ending")
	for t in Story.ENDING_NARRATION:
		await main.fader.narrate(t, true)
	Game.set_flag("ending")
	Game.set_flag("roof_fixed")
	Game.next_day()
	Game.day += 20
	Game.set_time(19, 0)
	await teleport("ending_view", false)
	player().face("up")
	await main.fader.chapter_card("الخاتمة", "بداية جديدة")
	await main.fader.fade_in(1.5)


func final_scene() -> void:
	Game.set_flag("final_scene")
	await teleport("spawn_home_in", true)
	for line in Story.FINAL_SCENE:
		await _say_line(line, "")
	dialogue().close()
	await main.fader.fade_out(2.0)
	await main.fader.narrate("«الثروة قد تبني بيتًا... لكنّ الذين يعيشون فيه وحدهم يجعلونه وطنًا.»", true)
	if Game.counter("docs") >= 5:
		await main.fader.narrate(Story.FATHER_LETTER, true, "رسالة من أبي")
	await _end_game()


func _end_game() -> void:
	Game.set_flag("ending_done")
	Audio.music("ending")
	await main.fader.credits(Story.CREDITS)
	Game.delete_save()
	Game.completed_runs += 1
	call_deferred("to_title")
