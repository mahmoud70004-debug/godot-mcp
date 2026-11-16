extends Node3D
## Dev preview of the enemy eye glow (V24): a hollow standing in the dark at 8 m.
##   xvfb-run -a <godot> --path . --rendering-driver opengl3 --write-movie /tmp/e.png --fixed-fps 10 --quit-after 30 res://tools/eyes_preview.tscn

func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.02, 0.03, 0.07)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.12, 0.16, 0.3)
	e.ambient_light_energy = 0.5
	env.environment = e
	add_child(env)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 60)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.05, 0.07, 0.05)
	ground.material_override = gm
	add_child(ground)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80, 1, 80)
	shape.shape = box
	shape.position = Vector3(0, -0.5, 0)
	body.add_child(shape)
	add_child(body)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(0.5, 0.62, 1.0)
	sun.light_energy = 0.35
	sun.rotation_degrees = Vector3(-40, 20, 0)
	add_child(sun)
	var player := Node3D.new()
	player.add_to_group("player")
	player.position = Vector3(0, 1.6, 0)
	add_child(player)
	var cam := Camera3D.new()
	player.add_child(cam)
	cam.current = true
	var x := -9.0
	for n in ["hollow", "grinner", "mourner", "steeple"]:
		var enemy := load("res://src/enemies/hollow.tscn").instantiate() as Enemy
		enemy.data = load("res://data/enemies/%s.tres" % n) as EnemyData
		enemy.position = Vector3(x, 0.0, -9.0 - absf(x) * 0.6)
		enemy.start_dormant = true
		add_child(enemy)
		x += 6.0

