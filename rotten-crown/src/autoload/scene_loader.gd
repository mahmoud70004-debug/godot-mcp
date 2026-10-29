extends CanvasLayer
## Fade-to-black scene transitions with threaded loading, so large regions
## in later phases do not freeze the main thread.

signal scene_changed(path: String)

const FADE_TIME := 0.6

var _fade_rect: ColorRect
var _busy := false


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0, 0, 0, 0)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_fade_rect)


func change_scene(path: String, fade_time: float = FADE_TIME) -> void:
	if _busy:
		return
	_busy = true
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	await _fade_to(1.0, fade_time)
	get_tree().paused = false
	ResourceLoader.load_threaded_request(path)
	while ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		await get_tree().process_frame
	var packed := ResourceLoader.load_threaded_get(path) as PackedScene
	if packed == null:
		push_error("SceneLoader: failed to load %s" % path)
	else:
		get_tree().change_scene_to_packed(packed)
		await get_tree().process_frame
		var scene := get_tree().current_scene
		if scene and scene.get("prewarming"):
			await scene.prewarmed
		scene_changed.emit(path)
	await _fade_to(0.0, fade_time)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_busy = false


func reload_current(fade_time: float = FADE_TIME) -> void:
	var current := get_tree().current_scene
	if current and current.scene_file_path != "":
		change_scene(current.scene_file_path, fade_time)


func _fade_to(alpha: float, duration: float) -> void:
	var tween := create_tween()
	tween.tween_property(_fade_rect, "color:a", alpha, duration)
	await tween.finished
