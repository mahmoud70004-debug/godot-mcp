extends Node

var failures := 0
var checks := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Game.fast = true
	Game.delete_save()
	Game.new_game()
	get_tree().change_scene_to_file("res://scenes/main.tscn")
	await _frames(5)
	_validate_data()
	await _play()
	print("\n==== RESULT: %d checks, %d failures ====" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func expect(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		print("FAIL: ", what)


func flags(list: Array, step: String) -> void:
	for f in list:
		expect(Game.check([f]), "%s -> expected %s" % [step, f])


func world():
	return Director.world()


func ev(id: String) -> void:
	print("> event ", id)
	var npc = world().npcs.get(id, null)
	await Director.run_event(id, npc)
	await _frames(2)
	_quest_sanity(id)


func door(id: String) -> void:
	print("> door ", id)
	for c in world().get_children():
		if c is Area2D and c.has_meta("door_to") and c.get_meta("iid") == id:
			await Director.door_touched(c)
			await _frames(3)
			_quest_sanity(id)
			return
	expect(false, "door not found " + id)


func _quest_sanity(step: String) -> void:
	if Director.main == null or Game.has("ending_done"):
		return
	var q: Dictionary = Director.current_quest()
	expect(q.get("title", "") != "", "a main quest is always active (after %s)" % step)
	if q.has("target") and q["target"] != null:
		var t: String = q["target"]
		expect(Story.NPCS.has(t) or world().has_spot(t), "quest target exists: " + t)


# ------------------------------------------------------------------ static checks
func _validate_data() -> void:
	print("== validating data")
	var w = world()
	for id in Story.NPCS:
		for rule in Story.NPCS[id]["spots"]:
			if rule[1] != null and rule[1] != "":
				expect(w.has_spot(rule[1]), "npc spot exists: %s -> %s" % [id, rule[1]])
	for q in Story.MAIN_QUESTS:
		var targets := []
		if q.has("target"):
			targets.append(q["target"])
		for s in q.get("steps", []):
			if s.size() > 2:
				if s[2] is String:
					targets.append(s[2])
				else:
					for alt in s[2]:
						targets.append(alt[1])
		for t in targets:
			expect(Story.NPCS.has(t) or w.has_spot(t), "quest target exists: " + str(t))
	for k in Story.INTERIOR_DOORS:
		expect(w.has_spot(Story.INTERIOR_DOORS[k]), "interior door spot " + k)
		expect(w.has_spot(Story.INTERIOR_EXITS[k]), "interior exit spot " + k)
	# every interactable has a handler
	for o in w.data["objects"]:
		var iid := ""
		if o.get("type", "") == "interact":
			iid = o["id"]
		elif o.has("interact"):
			iid = o["interact"]
		elif o.get("type", "") == "door":
			var to: String = o["to"]
			expect(w.has_spot(to) or Story.DOORS.has(o["id"]), "door target or rule: " + o["id"])
			continue
		if iid == "":
			continue
		var r: Array = Director._resolve_event_id(iid)
		expect(Story.EVENTS.has(r[0]), "event handler for " + iid)
	# every item handed out by events is defined
	for key in Story.EVENTS:
		for e in Story.EVENTS[key]:
			for list in [e.get("do", []), e.get("win", []), e.get("lose", [])]:
				for a in list:
					if a[0] in ["give", "take", "sell"]:
						expect(Story.ITEMS.has(a[1]), "item defined: " + a[1])
			for line in e.get("lines", []):
				expect(Story.NAMES.has(line[0]) or line[0] == "", "speaker known: " + str(line[0]))
	# every displayable string has an English and a Japanese translation
	var strings = JSON.parse_string(FileAccess.get_file_as_string("res://data/i18n/strings.json"))
	for src in strings:
		expect(Loc.has(src, "en") and Loc.has(src, "ja"), "translated: " + str(src).substr(0, 40))
	for it in Story.SHOP:
		expect(Story.ITEMS.has(it["id"]), "shop item defined " + it["id"])
	# every sprite referenced exists
	for o in w.data["objects"]:
		if o.has("sprite"):
			expect(ResourceLoader.exists("res://assets/sprites/%s.png" % o["sprite"]), "sprite " + o["sprite"])
	for id in Story.NPCS:
		var sheet: String = Story.NPCS[id].get("sheet", id)
		expect(ResourceLoader.exists("res://assets/chars/%s.png" % sheet), "character sheet " + sheet)


# ------------------------------------------------------------------ the story
func _play() -> void:
	print("== chapter 1")
	for i in 20:
		if Game.has("intro_done"):
			break
		await _frames(5)
	flags(["intro_done", "ch1"], "intro")
	expect(Director.quest_target() != null, "quest marker points somewhere at start")
	await ev("bjorn")
	flags(["c1_has_fish", "item:fish_basket"], "bjorn gives basket")
	await ev("bjorn_boat")
	flags(["c1_boat", "item:rod"], "boat prepared")
	await ev("sigrid")
	flags(["c1_fish", "!item:fish_basket"], "fish delivered")
	await ev("woodpile")
	flags(["item:firewood_bundle"], "firewood taken")
	await ev("margaret")
	flags(["c1_wood"], "firewood delivered")
	await ev("broken_fence")
	flags(["c1_fence", "fence_fixed"], "fence repaired")
	# jobs
	var m0 := Game.money
	await ev("fishing_spot")
	expect(Game.count("fish") == 1, "caught a fish")
	await ev("chop_wood")
	expect(Game.count("firewood") == 2, "chopped firewood")
	await ev("sigrid")
	await ev("sigrid")
	expect(Game.money == m0 + 4 + 6, "sold fish and firewood (money %d)" % Game.money)
	await ev("harbor_crates")
	await ev("warehouse_drop")
	expect(Game.money == m0 + 15, "crate delivered")
	await ev("bjorn")
	flags(["q_compass_started"], "compass quest offered")
	await ev("lost_compass")
	await ev("bjorn")
	flags(["q_compass_done", "item:special_rod", "item:photograph"], "compass returned")
	await ev("coin_0")
	await ev("shell_0")
	flags(["coin_0_taken", "shell_0_taken", "coins>=1", "shells>=1"], "pickups")
	await ev("herb_0")
	flags(["d_herb_0", "item:herbs"], "herb picked")
	await ev("astrid")
	flags(["!item:herbs"], "herbs sold")
	await ev("gunnar")
	await ev("sheep")
	flags(["gunnar_job", "d_sheep"], "sheep fed")
	await ev("margaret")
	flags(["ch1_end"], "chapter 1 end")
	await ev("gideon_bed")
	flags(["ch2", "!d_herb_0", "!d_sheep"], "morning chapter 2 (daily flags reset)")
	expect(Game.day == 13, "day advanced")

	print("== chapter 2")
	await ev("elias")
	flags(["met_elias"], "met Elias")
	await ev("elias_coat")
	flags(["!got_key"], "coat ignored before rumours")
	await ev("sigrid")
	await ev("bjorn")
	await ev("jonas")
	flags(["rumors>=3"], "three rumours")
	await ev("henrik")
	await ev("einar")
	await ev("runa")
	flags(["q_runa_started"], "runa quest")
	await ev("runa")
	await ev("henrik_cart")
	flags(["item:fabric"], "fabric from Henrik")
	await ev("runa")
	flags(["q_runa_done", "runa_discount", "item:outfit"], "runa quest done")
	await ev("clara")
	flags(["q_paint_started"], "clara quest")
	for v in ["paint_harbor", "paint_church", "paint_waterfall", "paint_hills_view"]:
		await ev(v)
	await ev("clara")
	flags(["q_paint_done", "painting_1"], "paintings")
	await ev("elias_coat")
	flags(["got_key", "item:iron_key"], "found the key")
	await ev("elias")
	flags(["ch2_end", "!item:iron_key"], "Elias took the key")
	await ev("gideon_bed")
	flags(["ch3", "roof_fixed", "debts_paid"], "morning chapter 3")

	print("== chapter 3")
	await door("door_manor")
	expect(world().zone_at(Director.player().global_position)["id"] == "study_in", "entered the study")
	await ev("halldor")
	flags(["met_halldor"], "met Halldor")
	await ev("estate_garden")
	flags(["d_garden"], "garden work")
	await ev("study_desk")
	flags(["cabinet_seen"], "cabinet noticed")
	await ev("study_cabinet")
	flags(["!cabinet_open"], "cabinet still locked")
	await ev("leif")
	flags(["got_lockpick", "item:lockpick"], "lockpick")
	await ev("study_cabinet")
	flags(["cabinet_open", "item:deed_copy", "item:torn_letter"], "cabinet opened")
	await ev("einar")
	flags(["q_priest_started", "item:church_letter"], "priest's letter")
	await ev("olafur")
	flags(["q_priest_done", "item:journal_3", "docs>=1"], "letter delivered")
	await ev("elias")
	flags(["asked_elias_farm"], "asked Elias about the farm")
	await ev("bjorn")
	flags(["bjorn_ship", "ch3_end"], "Bjorn's story")
	await ev("gideon_bed")
	flags(["ch4"], "morning chapter 4")

	print("== chapter 4")
	await ev("astrid")
	flags(["bridge_open"], "bridge open")
	await ev("leif")
	flags(["q_smith_started"], "smith quest")
	await ev("iron_chest")
	await ev("leif")
	flags(["q_smith_done", "got_detector"], "detector")
	await ev("collect_carving")
	await ev("collect_fishing_gear")
	await ev("collect_photo_inn")
	await ev("bjorn")
	flags(["q_wreck_started"], "wreck quest")
	await ev("wreck")
	await ev("bjorn")
	flags(["q_wreck_done", "memorabilia>=4"], "wreck + memorabilia")
	await ev("footprints")
	await ev("collect_journal_1")
	await ev("collect_journal_2")
	await ev("collect_property_farm")
	await ev("collect_letter_church")
	flags(["docs>=5"], "all family documents")
	await door("door_barn")
	flags(["!heard_voice"], "barn locked in daytime")
	await door("door_farmhouse")
	await ev("floorboard")
	flags(["found_edmund_letter", "item:edmund_letter"], "Edmund's letter")
	await ev("clara")
	flags(["clara_symbol"], "Clara recognises the symbol")
	await ev("elias")
	flags(["confronted_elias", "elias_left_barn"], "followed Elias")
	await door("door_barn")
	flags(["heard_voice", "ch5"], "the voice in the barn")

	print("== chapter 5")
	await door("door_barn")
	flags(["!met_edmund"], "look through the window first")
	await ev("barn_window")
	flags(["saw_edmund"], "saw Edmund")
	await door("door_barn")
	flags(["met_edmund", "ch6"], "met Edmund")
	expect(world().npcs["edmund"].visible, "Edmund is in the barn")

	print("== chapter 6")
	Game.auto_choices = [0]
	await ev("elias")
	flags(["refused_elias", "ch7"], "refused to sign")

	print("== chapter 7")
	await ev("edmund")
	flags(["got_box", "item:land_deed", "item:father_letters"], "Edmund's box")
	await ev("gideon_bed")
	flags(["ch8"], "morning chapter 8")

	print("== chapter 8")
	expect(world().npcs["elias"].visible, "Elias at the farm")
	await ev("farm_arrive")
	flags(["elias_fled", "ending"], "confrontation")
	expect(not world().npcs["elias"].visible, "Elias gone")
	await ev("bjorn")
	await ev("margaret")
	print("> door door_home (final scene)")
	for c in world().get_children():
		if c is Area2D and c.has_meta("door_to") and c.get_meta("iid") == "door_home":
			await Director.door_touched(c)
	flags(["final_scene", "ending_done"], "final scene and credits")
	expect(Game.completed_runs == 1, "game completed")
	await _frames(10)
	expect(get_tree().current_scene.scene_file_path == "res://scenes/title.tscn", "back on the title screen")
