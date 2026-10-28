extends Node
## Graphics quality (0 Low, 1 Medium, 2 High). Applies content scale, shadows,
## grass density and post-process features to the current scene, re-applies on
## every scene change, and downgrades once on weak devices.

const LOW := 0
const MEDIUM := 1
const HIGH := 2
const WARMUP_SECONDS := 3.0
const SAMPLE_SECONDS := 8.0
const FPS_THRESHOLD := 40.0
const RAIN_CAP_LOW := 0.3

var _pending := false
var _probing := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().node_added.connect(_on_node_added)
	_schedule_apply()


## Applies the given level to the viewport and the current scene.
func apply(level: int) -> void:
	level = clampi(level, LOW, HIGH)
	get_tree().root.content_scale_size = Vector2i(480, 270) if level == LOW else Vector2i(640, 360)
	if level == MEDIUM:
		RenderingServer.directional_shadow_atlas_set_size(1024, true)
	elif level == HIGH:
		RenderingServer.directional_shadow_atlas_set_size(2048, true)
	var scene := get_tree().current_scene
	if scene == null:
		return
	_apply_shadows(scene, level)
	_apply_grass(level)
	_apply_post(scene, level)


func _on_node_added(node: Node) -> void:
	if node.get_parent() == get_tree().root and node != self and not node.is_in_group(&"quality_ignore"):
		_schedule_apply()


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
		for param in ["grain_strength", "rain_amount"]:
			if mat.shader.get_shader_uniform_list().filter(func(u: Dictionary) -> bool: return u["name"] == param).is_empty():
				continue
			var key := StringName("q_orig_" + param)
			if not mat.has_meta(key):
				mat.set_meta(key, mat.get_shader_parameter(param))
			var original: float = mat.get_meta(key)
			if level != LOW:
				mat.set_shader_parameter(param, original)
			elif param == "grain_strength":
				mat.set_shader_parameter(param, 0.0)
			else:
				mat.set_shader_parameter(param, minf(original, RAIN_CAP_LOW))


func _maybe_probe() -> void:
	if _probing or Settings.quality_auto_checked:
		return
	if get_tree().get_first_node_in_group(&"player") == null:
		return
	_probing = true
	Settings.quality_auto_checked = true
	Settings.save_settings()
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
	var average := total / maxf(samples, 1)
	if average < FPS_THRESHOLD and Settings.quality > LOW:
		Settings.quality -= 1
		Settings.save_settings()
		apply(Settings.quality)
		Events.quality_changed.emit(Settings.quality)
		Events.show_message("Graphics set to Low for smoother play (Pause > Quality).")
