extends Node
## Single-slot JSON save. Later phases add multiple slots and checkpoint altars.

const SAVE_PATH := "user://savegame.json"
const SAVE_VERSION := 1


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func save_game(player_position: Vector3) -> bool:
	var state := GameState.to_dict()
	state["player_position"] = [player_position.x, player_position.y, player_position.z]
	var data := {
		"version": SAVE_VERSION,
		"scene": GameState.current_scene_path,
		"saved_at": Time.get_datetime_string_from_system(),
		"state": state,
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: cannot write %s (%s)" % [SAVE_PATH, error_string(FileAccess.get_open_error())])
		return false
	file.store_string(JSON.stringify(data, "\t"))
	return true


func load_game() -> bool:
	if not has_save():
		return false
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_error("SaveManager: save file is corrupt")
		return false
	var data: Dictionary = parsed
	var state: Dictionary = data.get("state", {})
	GameState.from_dict(state)
	var pos: Array = state.get("player_position", [])
	if pos.size() == 3:
		GameState.pending_player_position = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
	var scene_path := str(data.get("scene", ""))
	if scene_path == "" or not ResourceLoader.exists(scene_path):
		push_error("SaveManager: saved scene '%s' no longer exists" % scene_path)
		return false
	SceneLoader.change_scene(scene_path)
	return true


func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
