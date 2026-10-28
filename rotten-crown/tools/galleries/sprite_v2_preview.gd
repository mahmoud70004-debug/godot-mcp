extends Node3D
## Side by side: v2 test sheet (variant 0 and 1) and the legacy v1 hollow sheet, fixed camera.
## Every STEP_FRAMES frames the sprites' yaw advances one direction; the anim flips after a full turn.
## Env: RC_SHOT_DIR (saves a PNG at the end of every direction step), RC_ANIM (idle|walk, stops cycling).
## RC_SHEET (a res:// path to a sheet .tres) shows only that sheet, every palette variant side by side, with RC_ANIM and
## RC_DIR (fixed direction, default 0); RC_ZOOM narrows the camera fov.

const STEP_FRAMES := 4
const TEST_SHEET := "res://tools/galleries/test_sheet_v2/test_sheet.tres"
const V1_SHEET := "res://assets/sprites/hollow/hollow.tres"

var _sprites: Array[PixelSprite3D] = []
var _frame := 0
var _step := 0
var _fixed_anim := ""
var _custom := false


func _ready() -> void:
	_fixed_anim = OS.get_environment("RC_ANIM")
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.06, 0.09)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.55, 0.7)
	env.ambient_light_energy = 0.8
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	light.light_energy = 0.6
	add_child(light)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(14.0, 6.0)
	ground.mesh = plane
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.2, 0.22, 0.2)
	ground.material_override = gmat
	add_child(ground)
	# Ground line the feet must touch (thin strip at z = 0).
	var line := MeshInstance3D.new()
	var lmesh := BoxMesh.new()
	lmesh.size = Vector3(14.0, 0.005, 0.02)
	line.mesh = lmesh
	var lmat := StandardMaterial3D.new()
	lmat.albedo_color = Color(1, 1, 1)
	lmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line.material_override = lmat
	line.position.y = 0.003
	add_child(line)

	var custom_path := OS.get_environment("RC_SHEET")
	_custom = custom_path != ""
	var fov := 35.0
	if _custom:
		var sheet := load(custom_path) as SpriteSheetData
		var n := sheet.variants
		for v in n:
			var s := _add_sprite(sheet, v, Vector3((float(v) - (n - 1) * 0.5) * 1.3, 0.0, 0.0))
			s.fixed_direction = int(OS.get_environment("RC_DIR")) if OS.get_environment("RC_DIR") != "" else 0
		fov = float(OS.get_environment("RC_ZOOM")) if OS.get_environment("RC_ZOOM") != "" else 20.0
	else:
		var test_sheet := load(TEST_SHEET) as SpriteSheetData
		var v1_sheet := load(V1_SHEET) as SpriteSheetData
		_add_sprite(test_sheet, 0, Vector3(-3.5, 0.0, 0.0))
		_add_sprite(test_sheet, 1, Vector3(-1.0, 0.0, 0.0))
		_add_sprite(v1_sheet, 0, Vector3(2.5, 0.0, 0.0))

	var cam := Camera3D.new()
	cam.fov = fov
	cam.position = Vector3(0.0, 1.3, 9.0)
	add_child(cam)
	cam.look_at(Vector3(0.0, 1.0, 0.0))
	cam.current = true
	_apply_step()


func _process(_delta: float) -> void:
	_frame += 1
	if _frame % STEP_FRAMES != 0:
		return
	var shot_dir := OS.get_environment("RC_SHOT_DIR")
	if shot_dir != "":
		DirAccess.make_dir_recursive_absolute(shot_dir)
		get_viewport().get_texture().get_image().save_png("%s/step_%03d.png" % [shot_dir, _step])
	_step += 1
	_apply_step()


func _add_sprite(sheet: SpriteSheetData, variant: int, pos: Vector3) -> PixelSprite3D:
	var s := PixelSprite3D.new()
	s.sheet = sheet
	s.variant = variant
	s.position = pos
	add_child(s)
	_sprites.append(s)
	return s


func _apply_step() -> void:
	var dir := _step % 8
	if _custom:
		dir = 0
	var anim_name := _fixed_anim
	if anim_name == "":
		anim_name = "idle" if (_step / 8) % 2 == 0 else "walk"
	for s in _sprites:
		# Yaw 0 shows direction 4 (back); each +45 deg of node yaw advances the shown direction by one.
		if not _custom:
			s.rotation_degrees.y = float(dir) * 45.0
		s.play(StringName(anim_name))
