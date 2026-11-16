extends Node3D
## Dev preview of the pickup models (V24): one of each category on dark ground under a moon-ish light.
##   xvfb-run -a <godot> --path . --rendering-driver opengl3 --write-movie /tmp/p.png --fixed-fps 10 --quit-after 20 res://tools/pickup_preview.tscn

func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.03, 0.05, 0.1)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.2, 0.28, 0.45)
	e.ambient_light_energy = 0.6
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(0.6, 0.72, 1.0)
	sun.light_energy = 0.9
	sun.rotation_degrees = Vector3(-50, 30, 0)
	add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(6, 6)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.08, 0.1, 0.08)
	ground.material_override = gm
	add_child(ground)
	var dirs := ["consumables", "lore", "relics"]
	var x := -0.45
	for d: String in dirs:
		var files := DirAccess.get_files_at("res://data/items/" + d)
		for f in files:
			if not f.ends_with(".tres"):
				continue
			var pick := ItemPickup.new()
			pick.item = load("res://data/items/%s/%s" % [d, f]) as ItemData
			pick.hover = false
			pick.position = Vector3(x, 0.12, 0)
			add_child(pick)
			x += 0.3
			break
	var pouch := ItemPickup.new()
	var it := ItemData.new()
	it.display_name = "Pouch"
	it.tint = Color(0.6, 0.5, 0.3)
	pouch.item = it
	pouch.hover = false
	pouch.position = Vector3(x, 0.1, 0)
	add_child(pouch)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 0.45, 1.1)
	cam.look_at_from_position(cam.position, Vector3(0, 0.08, 0))
	cam.current = true
	add_child(cam)
