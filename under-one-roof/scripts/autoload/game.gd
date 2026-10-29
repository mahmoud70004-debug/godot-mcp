extends Node
## Global game state: story flags, counters, money, inventory, clock and saving.

signal flags_changed
signal money_changed(amount: int, delta: int)
signal inventory_changed
signal time_changed
signal toast(text: String)
signal clue_added(text: String)

const SAVE_PATH := "user://save.json"
const START_MINUTES := 6 * 60 + 30
const MINUTES_PER_SECOND := 1.0 / 0.7
const WEEKDAYS := ["السبت", "الأحد", "الاثنين", "الثلاثاء", "الأربعاء", "الخميس", "الجمعة"]

var flags := {}
var counters := {}
var money := 0
var inventory: Array = []           # [{id, n}] in hotbar order
var clues: Array = []               # journal entries (strings)
var minutes := float(START_MINUTES)
var day := 12
var selected_slot := 0

var time_running := false           # the clock only advances during free play
var input_locked := false           # dialogue / cutscenes
var touch_vector := Vector2.ZERO    # written by the on-screen joystick
var touch_run := false
var pending_load := false           # main scene restores the saved position when true
var player_spot := "game_start"
var player_pos := Vector2.ZERO
var settings := {"music": 0.7, "sfx": 0.8}
var fast := false                   # automated tests: no waiting, mini-games always succeed
var auto_choices: Array = []        # automated tests: answers for dialogue choices
var completed_runs := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_settings()


func _process(delta: float) -> void:
	if time_running and not input_locked and not get_tree().paused:
		var before := int(minutes) / 10
		minutes += delta * MINUTES_PER_SECOND
		if minutes > 26 * 60:
			minutes = 26 * 60
		if int(minutes) / 10 != before:
			time_changed.emit()


# ---------------------------------------------------------------- new / save / load
func new_game() -> void:
	flags = {"ch1": true}
	counters = {}
	money = 12
	inventory = [{"id": "hammer", "n": 1}, {"id": "axe", "n": 1}]
	clues = []
	minutes = START_MINUTES
	day = 12
	selected_slot = 0
	pending_load = false
	player_spot = "game_start"


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func save_game(pos: Vector2) -> void:
	var data := {
		"flags": flags, "counters": counters, "money": money, "inventory": inventory,
		"clues": clues, "minutes": minutes, "day": day, "pos": [pos.x, pos.y], "version": 1,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))
		toast.emit("تم حفظ التقدّم")


func load_game() -> bool:
	if not has_save():
		return false
	var data = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(data) != TYPE_DICTIONARY:
		return false
	flags = data.get("flags", {})
	counters = {}
	for k in data.get("counters", {}):
		counters[k] = int(data["counters"][k])
	money = int(data.get("money", 0))
	inventory = []
	for it in data.get("inventory", []):
		inventory.append({"id": str(it["id"]), "n": int(it["n"])})
	clues = data.get("clues", [])
	minutes = float(data.get("minutes", START_MINUTES))
	day = int(data.get("day", 12))
	var p = data.get("pos", [0, 0])
	player_pos = Vector2(p[0], p[1])
	pending_load = true
	return true


func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


func save_settings() -> void:
	var f := FileAccess.open("user://settings.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(settings))


func _load_settings() -> void:
	if FileAccess.file_exists("user://settings.json"):
		var d = JSON.parse_string(FileAccess.get_file_as_string("user://settings.json"))
		if typeof(d) == TYPE_DICTIONARY:
			settings.merge(d, true)


# ---------------------------------------------------------------- flags & conditions
func has(flag: String) -> bool:
	return flags.get(flag, false)


func set_flag(flag: String, value := true) -> void:
	if value:
		if flags.get(flag, false):
			return
		flags[flag] = true
	else:
		if not flags.has(flag):
			return
		flags.erase(flag)
	flags_changed.emit()


func counter(name: String) -> int:
	return counters.get(name, 0)


func add_counter(name: String, n := 1) -> void:
	counters[name] = counter(name) + n
	flags_changed.emit()


## A condition is an Array of terms that must all hold:
##   "flag"       flag is set          "!flag"      flag is not set
##   "name>=3"    counter comparison   "item:fish"  inventory has the item
##   "money>=10"  money comparison     "night"      after 20:00
func check(cond) -> bool:
	if cond == null:
		return true
	for term in cond:
		if not _term(str(term)):
			return false
	return true


func _term(t: String) -> bool:
	if t.begins_with("!"):
		return not _term(t.substr(1))
	if t.begins_with("item:"):
		return count(t.substr(5)) > 0
	if t == "night":
		return hour() >= 20 or hour() < 5
	if t == "evening":
		return hour() >= 17
	for op in [">=", "<=", "<", ">", "=="]:
		var i := t.find(op)
		if i > 0:
			var key := t.substr(0, i)
			var val := int(t.substr(i + op.length()))
			var have := money if key == "money" else counter(key)
			match op:
				">=": return have >= val
				"<=": return have <= val
				"<": return have < val
				">": return have > val
				"==": return have == val
	return has(t)


# ---------------------------------------------------------------- items & money
func count(item: String) -> int:
	for it in inventory:
		if it["id"] == item:
			return it["n"]
	return 0


func give(item: String, n := 1) -> void:
	for it in inventory:
		if it["id"] == item:
			it["n"] += n
			inventory_changed.emit()
			flags_changed.emit()
			return
	inventory.append({"id": item, "n": n})
	inventory_changed.emit()
	flags_changed.emit()


func take(item: String, n := 1) -> bool:
	for i in inventory.size():
		var it = inventory[i]
		if it["id"] == item:
			it["n"] -= n
			if it["n"] <= 0:
				inventory.remove_at(i)
				selected_slot = clampi(selected_slot, 0, max(0, inventory.size() - 1))
			inventory_changed.emit()
			flags_changed.emit()
			return true
	return false


func add_money(n: int) -> void:
	money = max(0, money + n)
	money_changed.emit(money, n)
	flags_changed.emit()


func add_clue(text: String) -> void:
	if text in clues:
		return
	clues.append(text)
	clue_added.emit(text)


# ---------------------------------------------------------------- clock
func hour() -> int:
	return int(minutes / 60.0) % 24


func clock_text() -> String:
	var m := int(minutes) % (24 * 60)
	var h := m / 60
	var mm := (m % 60) / 10 * 10
	var suffix := "صباحًا" if h < 12 else "مساءً"
	var h12 := h % 12
	if h12 == 0:
		h12 = 12
	return "%d:%02d %s" % [h12, mm, suffix]


func weekday() -> String:
	return WEEKDAYS[(day - 12) % 7]


func set_time(h: int, m := 0) -> void:
	minutes = h * 60 + m
	time_changed.emit()


func advance(mins: int) -> void:
	minutes += mins
	time_changed.emit()


## Start a new day: daily flags (prefixed "d_") reset.
func next_day() -> void:
	day += 1
	minutes = START_MINUTES
	for k in flags.keys():
		if str(k).begins_with("d_"):
			flags.erase(k)
	time_changed.emit()
	flags_changed.emit()
