extends Node
## Screenshots of the main menu, its pages and the three languages.

var out_dir := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var lang0: String = Game.settings["lang"]
	for lang in ["ar", "en", "ja"]:
		Game.settings["lang"] = lang
		Loc.set_lang(lang)
		get_tree().change_scene_to_file("res://scenes/title.tscn")
		await _wait(1.5)
		await _shot("menu_%s" % lang)
		var title = get_tree().current_scene
		title._open_page("settings")
		await _wait(0.6)
		await _shot("settings_%s" % lang)
		title._open_page("music")
		await _wait(0.6)
		await _shot("music_%s" % lang)
	Game.settings["lang"] = lang0
	Loc.set_lang(lang0)
	get_tree().quit()


func _wait(t: float) -> void:
	await get_tree().create_timer(t, true).timeout


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir.path_join(name + ".png"))
	print("shot ", name)
