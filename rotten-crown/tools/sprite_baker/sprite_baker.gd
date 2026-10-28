extends Node3D
## Offline sprite baker (Doom-style pre-rendered sprites).
## Renders every character in characters.json from `DIRS` directions and every
## animation frame into build/sprites_raw/<char>/<anim>_<dir>_<frame>.png with a
## transparent background, plus meta.json. tools/pixelize_sprites.py then turns
## the renders into pixel-art sheets. Run through tools/bake_sprites.sh
## (needs a GL context: xvfb-run + --rendering-driver opengl3).
## Env: RC_BAKE_CHARS="knight,villager" (default: all).

const DIRS := 8
const RENDER_PX := 384
const SPEC_PATH := "res://tools/sprite_baker/characters.json"
const OUT_DIR := "res://build/sprites_raw"

var _viewport: SubViewport
var _camera: Camera3D
var _stage: Node3D


func _ready() -> void:
	_setup_stage()
	var specs: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SPEC_PATH))
	var wanted := OS.get_environment("RC_BAKE_CHARS").split(",", false)
	var t0 := Time.get_ticks_msec()
	var total := 0
	for char_id in specs.keys():
		if str(char_id).begins_with("_") or (not wanted.is_empty() and not wanted.has(char_id)):
			continue
		var spec: Dictionary = specs[char_id]
		var variants: Array = spec.get("variants", [spec.get("props", {})])
		for vi in variants.size():
			var name := str(char_id) if variants.size() == 1 else "%s_%d" % [char_id, vi]
			total += await _bake_character(name, spec, variants[vi])
	print("SPRITE_BAKE_DONE frames=%d in %.1fs" % [total, (Time.get_ticks_msec() - t0) / 1000.0])
	get_tree().quit()


func _setup_stage() -> void:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(RENDER_PX, RENDER_PX)
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.32, 0.34, 0.38)
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_viewport.add_child(we)
	# Three-point light: cool moonlit key, warm low fill, bright rim from behind.
	_light(Vector3(-0.75, 0.6, 0.0), Color(0.78, 0.84, 1.0), 1.6)
	_light(Vector3(-0.25, -0.9, 0.0), Color(1.0, 0.72, 0.5), 0.45)
	_light(Vector3(-0.35, PI, 0.0), Color(0.85, 0.92, 1.0), 1.3)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_viewport.add_child(_camera)
	_stage = Node3D.new()
	_viewport.add_child(_stage)


func _light(rot: Vector3, color: Color, energy: float) -> void:
	var l := DirectionalLight3D.new()
	l.rotation = rot
	l.light_color = color
	l.light_energy = energy
	_viewport.add_child(l)


func _bake_character(name: String, spec: Dictionary, props: Dictionary) -> int:
	var model := _make_model(spec, props)
	_stage.add_child(model)
	# Poses are driven explicitly; the rigs' own _process must not interfere.
	model.process_mode = Node.PROCESS_MODE_DISABLED
	var rig: Node3D = model.get_node("Visual") if spec["kind"] == "creature" else model
	if spec["kind"] == "creature":
		(rig as CreatureRig).setup(load(spec["data"]) as EnemyData)
		(rig as CreatureRig).look_at_viewer = bool(spec.get("look_at_viewer", false))
	var size := float(spec["camera_size"])
	var center_y := float(spec["center_y"])
	_camera.size = size
	# Slightly above eye level, looking a little down, like the player sees them.
	_camera.position = Vector3(0.0, center_y + 0.55, 8.0)
	_camera.look_at(Vector3(0.0, center_y, 0.0))
	var dir := ProjectSettings.globalize_path(OUT_DIR + "/" + name)
	DirAccess.make_dir_recursive_absolute(dir)
	var anims: Dictionary = spec["anims"]
	var meta := {"dirs": DIRS, "render_px": RENDER_PX, "camera_size": size, "height_px": spec["height_px"],
		"palette": spec["palette"], "anims": {}}
	var count := 0
	for anim in anims.keys():
		var a: Dictionary = anims[anim]
		var frames := int(a["frames"])
		var duration := float(a["duration"])
		var loop := bool(a["loop"])
		meta["anims"][anim] = {"frames": frames, "fps": a["fps"], "loop": loop}
		for k in DIRS:
			model.rotation.y = PI + k * TAU / DIRS
			for f in frames:
				var t := 0.0
				if frames > 1:
					t = duration * f / (frames if loop else frames - 1)
				if rig is CreatureRig:
					(rig as CreatureRig).viewer_position = _camera.global_position
				rig.call("pose_at", StringName(anim), t)
				await RenderingServer.frame_post_draw
				await RenderingServer.frame_post_draw
				var img := _viewport.get_texture().get_image()
				img.save_png("%s/%s_%d_%d.png" % [dir, anim, k, f])
				count += 1
	var file := FileAccess.open(dir + "/meta.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(meta, "\t"))
	file.close()
	model.queue_free()
	await get_tree().process_frame
	print("baked %s: %d frames" % [name, count])
	return count


func _make_model(spec: Dictionary, props: Dictionary) -> Node3D:
	if spec["kind"] == "creature":
		return (load(spec["scene"]) as PackedScene).instantiate() as Node3D
	var model := (load(spec["script"]) as GDScript).new() as Node3D
	for key in props.keys():
		model.set(key, props[key])
	return model
