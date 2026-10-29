extends Node
## Graphics quality (0 Low, 1 Medium, 2 High). Applies content scale, shadows,
## grass density and post-process grain to the current scene, re-applies on
## every scene change and on Events.quality_changed, and downgrades once on weak
## devices. Rain streaks on Low are WeatherController's job. Scenes in the
## persistent group "quality_ignore" (offline bake tools) are left alone. Scenes in the
## group "full_resolution_ui" (the 2D title screen, which costs nothing to draw) always keep
## the full 640x360 content scale, so its composition never has to fit 480x270.
## Web: ?quality=0|1|2 forces a level for this session (tests).
## After the first probe a watchdog keeps checking during play: if the frame rate
## stays under SUSTAINED_FPS for two windows in a row, quality steps down one level
## (never up, and never once the player picked a level themselves).

const LOW := 0
const MEDIUM := 1
const HIGH := 2
const WARMUP_SECONDS := 3.0
const SAMPLE_SECONDS := 8.0
const FPS_THRESHOLD := 40.0
const SUSTAINED_FPS := 26.0
const WATCH_WINDOW := 8.0
## Seconds ignored after a scene change (loading and pre-warm hitches).
const WATCH_GRACE := 6.0

var _pending := false
var _probing := false
var _locked := false
var _watch_time := 0.0
var _watch_frames := 0
var _watch_grace := WATCH_GRACE
var _slow_windows := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().node_added.connect(_on_node_added)
	Events.quality_changed.connect(apply)
	_apply_url_override()
	_schedule_apply()


## Applies the given level to the viewport and the current scene.
func apply(level: int) -> void:
	level = clampi(level, LOW, HIGH)
	var full_res := get_tree().current_scene != null and get_tree().current_scene.is_in_group(&"full_resolution_ui")
	get_tree().root.content_scale_size = Vector2i(480, 270) if level == LOW and not full_res else Vector2i(640, 360)
	if level == MEDIUM:
		RenderingServer.directional_shadow_atlas_set_size(1024, true)
	elif level == HIGH:
		RenderingServer.directional_shadow_atlas_set_size(2048, true)
	var scene := get_tree().current_scene
	if scene == null or scene.is_in_group(&"quality_ignore"):
		return
	_apply_shadows(scene, level)
	_apply_grass(level)
	_apply_post(scene, level)


func _on_node_added(node: Node) -> void:
	if node.get_parent() == get_tree().root and node != self and not node.is_in_group(&"quality_ignore"):
		_schedule_apply()
		_watch_grace = WATCH_GRACE
		_watch_time = 0.0
		_watch_frames = 0
		_slow_windows = 0


func _process(delta: float) -> void:
	if _locked or _probing or Settings.quality_manual or Settings.quality <= LOW or get_tree().paused:
		return
	if get_tree().get_first_node_in_group(&"player") == null:
		return
	if _watch_grace > 0.0:
		_watch_grace -= delta
		return
	_watch_time += delta
	_watch_frames += 1
	if _watch_time < WATCH_WINDOW:
		return
	var fps := _watch_frames / _watch_time
	_watch_time = 0.0
	_watch_frames = 0
	_slow_windows = _slow_windows + 1 if fps < SUSTAINED_FPS else 0
	if _slow_windows >= 2:
		_slow_windows = 0
		Settings.quality -= 1
		Settings.save_settings()
		Events.quality_changed.emit(Settings.quality)
		Events.show_message("Graphics lowered for smoother play (Pause > Quality).")


func _schedule_apply() -> void:
	if _pending:
		return
	_pending = true
	# Level scripts build content (grass, lights) in _ready; wait for it.
	await get_tree().process_frame
	await get_tree().process_frame
	_pending = false
	apply(Settings.quality)
	_maybe_probe()


func _apply_shadows(scene: Node, level: int) -> void:
	for node in scene.find_children("*", "DirectionalLight3D", true, false):
		var light := node as DirectionalLight3D
		light.shadow_enabled = level != LOW
		if level == MEDIUM:
			light.directional_shadow_max_distance = 25.0
		elif level == HIGH:
			light.directional_shadow_max_distance = 40.0


func _apply_grass(level: int) -> void:
	for node in get_tree().get_nodes_in_group(&"grass_chunks"):
		var mmi := node as MultiMeshInstance3D
		if mmi == null or mmi.multimesh == null:
			continue
		if not mmi.has_meta(&"q_range_end"):
			mmi.set_meta(&"q_range_end", mmi.visibility_range_end)
		var original: float = mmi.get_meta(&"q_range_end")
		mmi.multimesh.visible_instance_count = mmi.multimesh.instance_count / 2 if level == LOW else -1
		mmi.visibility_range_end = original * 1.4 if level == HIGH else original


func _apply_post(scene: Node, level: int) -> void:
	for node in scene.find_children("PostProcess", "CanvasLayer", true, false):
		var screen := node.get_node_or_null("Screen") as CanvasItem
		var mat := screen.material as ShaderMaterial if screen else null
		if mat == null:
			continue
		if not mat.has_meta(&"q_orig_grain"):
			mat.set_meta(&"q_orig_grain", mat.get_shader_parameter("grain_strength"))
		var original: Variant = mat.get_meta(&"q_orig_grain")
		if original is float:
			mat.set_shader_parameter("grain_strength", 0.0 if level == LOW else float(original))


func _maybe_probe() -> void:
	if _probing or Settings.quality_auto_checked:
		return
	if get_tree().get_first_node_in_group(&"player") == null:
		return
	_probing = true
	var start_level := Settings.quality
	await get_tree().create_timer(WARMUP_SECONDS).timeout
	var total := 0.0
	var samples := 0
	var elapsed := 0.0
	while elapsed < SAMPLE_SECONDS:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		total += Engine.get_frames_per_second()
		samples += 1
	_probing = false
	Settings.quality_auto_checked = true
	var average := total / maxf(samples, 1)
	# A level the player picked meanwhile wins over the measurement.
	if Settings.quality == start_level and average < FPS_THRESHOLD and Settings.quality > LOW:
		Settings.quality = LOW
		Events.quality_changed.emit(LOW)
		Events.show_message("Graphics set to Low for smoother play (Pause > Quality).")
	Settings.save_settings()


func _apply_url_override() -> void:
	if not OS.has_feature("web"):
		return
	var q: Variant = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('quality') || ''", true)
	if q == null or not str(q).is_valid_int():
		return
	Settings.quality = clampi(str(q).to_int(), LOW, HIGH)
	Settings.quality_auto_checked = true  # session only: not saved
	_locked = true
