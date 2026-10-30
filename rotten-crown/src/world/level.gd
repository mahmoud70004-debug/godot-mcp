class_name Level
extends Node3D
## Root script for every playable level.

signal prewarmed

@export var region: RegionData
@export var player: Player
@export var environment: WorldEnvironment
## Optional: regions change the rain when entered.
@export var weather: WeatherController
## Seconds to blend fog/rain when walking into another region.
@export var region_blend_time := 4.0
@export var kill_height := -25.0
## Announce the region as soon as the level starts (otherwise use RegionTrigger).
@export var announce_on_start := false
## The knight's inner voice after waking up here (DialogueUI subtitles).
@export var wake_dialogue: DialogueSequence

## True while shaders are being compiled behind the loading fade (SceneLoader waits).
var prewarming := false
var _base_region: RegionData
var _zones: Array[RegionData] = []
var _blend_tween: Tween


func _ready() -> void:
	GameState.current_scene_path = scene_file_path
	if region:
		GameState.current_region_id = region.id
		_apply_region_atmosphere()
		if announce_on_start and not GameState.get_flag("waking_up"):
			_announce_region.call_deferred()
	if player and GameState.pending_player_position is Vector3:
		player.global_position = GameState.pending_player_position
		GameState.pending_player_position = null
	_apply_dev_shot()
	_base_region = region
	Events.region_zone_entered.connect(_on_zone_entered)
	Events.region_zone_exited.connect(_on_zone_exited)
	_apply_dev_perf_flags()
	if player:
		prewarming = true
		_prewarm.call_deferred()
	if player and GameState.get_flag("waking_up"):
		GameState.flags.erase("waking_up")
		_wake_up.call_deferred()


## Compile every material's shader now, under the black fade, instead of the
## first time the camera turns towards it (stutter on phones).
func _prewarm() -> void:
	# Quality applies shadows/grass two frames after the scene enters the tree.
	for _i in 3:
		await get_tree().process_frame
	await ShaderPrewarm.warm(self, player.camera)
	prewarming = false
	prewarmed.emit()


func _wake_up() -> void:
	if prewarming:
		await prewarmed
	await player.play_wake_up()
	if region and announce_on_start:
		Events.region_entered.emit(region)
	if wake_dialogue and not wake_dialogue.lines.is_empty():
		Events.dialogue_requested.emit(wake_dialogue.lines)


## Dev aid for profiling: RC_PERF="nosky,nograss,nohorizon,nopost,nofog".
func _apply_dev_perf_flags() -> void:
	var raw := OS.get_environment("RC_PERF")
	if OS.has_feature("web"):
		var q: Variant = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('perf') || ''", true)
		raw = str(q) if q != null else raw
	var flags := raw.split(",", false)
	if flags.is_empty():
		return
	var env := environment.environment if environment else null
	if flags.has("nosky") and env:
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.05, 0.06, 0.05)
	if flags.has("nofog") and env:
		env.fog_enabled = false
	for node in find_children("*", "", true, false):
		if flags.has("nograss") and node.name == "Grass":
			(node as Node3D).visible = false
		if flags.has("nohorizon") and node.name == "Horizon":
			(node as Node3D).visible = false
		if flags.has("nopost") and node.name == "PostProcess":
			(node as CanvasLayer).visible = false
		if node is GeometryInstance3D:
			var gi := node as GeometryInstance3D
			var bm := gi.material_override as BaseMaterial3D
			if flags.has("notriplanar") and bm and bm.uv1_triplanar:
				bm.uv1_triplanar = false
			if flags.has("nocutout") and bm and bm.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
				gi.visible = false
			var cut := bm and bm.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			if flags.has("cutcheap") and cut:
				bm.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
				bm.disable_receive_shadows = true
			if flags.has("cutnocast") and cut:
				gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if flags.has("noshadow"):
				gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# "hide:Name" hides every node called Name (cost of one baked group).
		if node is Node3D and flags.has("hide:" + node.name):
			(node as Node3D).visible = false


## Dev aid for rendering review shots: RC_SHOT="x,y,z,yaw_deg,pitch_deg".
func _apply_dev_shot() -> void:
	var shot := OS.get_environment("RC_SHOT")
	if OS.has_feature("web"):
		# ?tp=x,y,z,yaw (yaw 180 faces +Z); pitch is level.
		var q: Variant = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('tp') || ''", true)
		if q != null and str(q) != "":
			shot = str(q) + ",0"
	if shot == "" or player == null:
		return
	var v := shot.split_floats(",")
	if v.size() >= 5:
		player.global_position = Vector3(v[0], v[1], v[2])
		player.rotation_degrees.y = v[3]
		player.head.rotation_degrees.x = v[4]


## Zones can overlap; the most recently entered one wins, and leaving all of
## them falls back to the level's own region. A region may have several
## overlapping triggers (a long forest path): one entry per trigger, so leaving
## one of them keeps the region while another still holds the player.
func _on_zone_entered(zone: RegionData) -> void:
	_zones.append(zone)
	_blend_to(zone)


func _on_zone_exited(zone: RegionData) -> void:
	_zones.erase(zone)
	var fallback: RegionData = _zones.back() if not _zones.is_empty() else _base_region
	if fallback:
		GameState.current_region_id = fallback.id
		_blend_to(fallback)


func _blend_to(new_region: RegionData) -> void:
	if environment == null or environment.environment == null or new_region == region:
		return
	region = new_region
	var env := environment.environment
	if _blend_tween != null:
		_blend_tween.kill()
	_blend_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE)
	_blend_tween.tween_property(env, "fog_light_color", new_region.fog_color, region_blend_time)
	_blend_tween.tween_property(env, "fog_density", new_region.fog_density, region_blend_time)
	_blend_tween.tween_property(env, "ambient_light_color", new_region.ambient_color, region_blend_time)
	if weather:
		weather.set_rain(new_region.rain, region_blend_time)


func _announce_region() -> void:
	Events.region_entered.emit(region)


func _physics_process(_delta: float) -> void:
	if player and player.global_position.y < kill_height:
		player.kill()


func _apply_region_atmosphere() -> void:
	if environment == null or environment.environment == null:
		return
	var env := environment.environment
	env.fog_light_color = region.fog_color
	env.fog_density = region.fog_density
	env.ambient_light_color = region.ambient_color
	if weather:
		weather.rain = region.rain
