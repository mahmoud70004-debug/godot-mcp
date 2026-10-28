extends Node3D
## Review scene: the knight rig under a three-point light, orthographic camera.
## Env: RC_ANIM (default idle), RC_T (seconds, default 0), RC_YAW (degrees).


func _ready() -> void:
	get_tree().root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	var anim := OS.get_environment("RC_ANIM")
	if anim == "":
		anim = "idle"
	var t := OS.get_environment("RC_T").to_float()
	var yaw := OS.get_environment("RC_YAW").to_float()

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.055, 0.07)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.25, 0.28, 0.36)
	env.ambient_light_energy = 0.5
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var knight := KnightModel.new()
	add_child(knight)
	knight.pose_at(StringName(anim), t)
	# The rig faces -Z; the camera looks down -Z, so yaw 0 shows the front.
	knight.rotation_degrees.y = yaw + 180.0
	knight.set_process(false)

	_light(Vector3(-50.0, 40.0, 0.0), Color(0.6, 0.72, 1.0), 1.4)
	_light(Vector3(-20.0, -50.0, 0.0), Color(1.0, 0.7, 0.45), 0.35)
	_light(Vector3(-25.0, 160.0, 0.0), Color(0.75, 0.85, 1.0), 1.3)

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 2.7
	cam.position = Vector3(0.0, 1.12, 5.0)
	add_child(cam)
	cam.look_at(Vector3(0.0, 1.12, 0.0))


func _light(rot_deg: Vector3, color: Color, energy: float) -> void:
	var l := DirectionalLight3D.new()
	l.rotation_degrees = rot_deg
	l.light_color = color
	l.light_energy = energy
	add_child(l)
