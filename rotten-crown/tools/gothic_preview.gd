extends Node3D
## Dev preview of the gothic kit (V28): a great tower, a buttress row and a spire on dark ground.
##   xvfb-run -a <godot> --path . --rendering-driver opengl3 --write-movie out/f.png --fixed-fps 10 --quit-after 12 res://tools/gothic_preview.tscn
## RC_GOTH=tower|spire|wall picks the subject.


func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.03, 0.05, 0.1)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.25, 0.32, 0.5)
	e.ambient_light_energy = 0.7
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(0.6, 0.72, 1.0)
	sun.light_energy = 1.3
	sun.rotation_degrees = Vector3(-35, 40, 0)
	add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.06, 0.08, 0.06)
	ground.material_override = gm
	add_child(ground)
	var b := GothicKit.Builder.new()
	var what := OS.get_environment("RC_GOTH")
	var cam := Camera3D.new()
	add_child(cam)
	match what:
		"spire":
			GothicKit.spire(b, 1.6, 22.0)
			cam.position = Vector3(5, 7, 14)
			cam.look_at_from_position(cam.position, Vector3(0, 9, 0))
		"wall":
			for k in 4:
				b.xf = Transform3D(Basis.IDENTITY, Vector3(k * 9.0 - 13.0, 0, 0))
				GothicKit.buttress(b, 1.4, 2.4, 12.0)
				b.xf = Transform3D(Basis.IDENTITY, Vector3(k * 9.0 - 8.5, 5.0, 0.2))
				GothicKit.window(b, Vector3.ZERO, Vector3.BACK, 2.2, 6.0, false)
			cam.position = Vector3(4, 4, 22)
			cam.look_at_from_position(cam.position, Vector3(0, 6, 0))
		_:
			GothicKit.great_tower(b, 5.0, 30.0, 24.0, true)
			cam.position = Vector3(16, 9, 30)
			cam.look_at_from_position(cam.position, Vector3(0, 24, 0))
	b.xf = Transform3D.IDENTITY
	b.commit(self, CastleProps.front_stone(), CastleProps.front_mossy())
	print("GOTHIC tris=", b.tris)
	cam.current = true
