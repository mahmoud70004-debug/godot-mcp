@tool
extends Node3D
## Review scene: one of each PropKit prop (and variants) in a row, 6 m apart.
## RC_GALLERY_RANGE="a,b" frames only items a..b (for close-up review shots).

const SPACING := 6.0


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var items: Array[Node3D] = []
	var fence_pts := PackedVector3Array([Vector3(-2.5, 0, 0), Vector3(0, 0, 1.0), Vector3(2.5, 0, 0)])
	items.append(PropKit.fence_run(fence_pts, 0.0, rng, true))
	items.append(PropKit.fence_run(fence_pts, 0.6, rng, true))
	items.append(PropKit.dead_tree(9.0, rng))
	items.append(PropKit.gnarled_tree(10.0, Vector3.RIGHT, rng))
	items.append(PropKit.gnarled_tree(10.0, Vector3.LEFT, rng))
	items.append(PropKit.pumpkin(0.8, rng))
	items.append(PropKit.pumpkin(0.8, rng, true))
	items.append(PropKit.pumpkin(0.8, rng, false, true))
	items.append(PropKit.scarecrow(rng))
	items.append(PropKit.scarecrow(rng, true))
	var labels: Array[String] = ["Hollowmere", "Thornfield"]
	items.append(PropKit.signpost(labels, rng))
	items.append(PropKit.cottage(Vector3(5, 2.6, 4), rng))
	items.append(PropKit.cottage(Vector3(5, 2.6, 4), rng, true))
	items.append(PropKit.chapel(rng))
	items.append(PropKit.chapel(rng, true))
	items.append(PropKit.cart_wreck(rng))
	var scenery := Node3D.new()
	scenery.name = "Props"
	add_child(scenery)
	for i in items.size():
		items[i].position = Vector3(i * SPACING, 0, 0)
		scenery.add_child(items[i])
	MeshMerger.merge_static(scenery)
	var range_a := 0
	var range_b := items.size() - 1
	var env_range := OS.get_environment("RC_GALLERY_RANGE").split(",")
	if env_range.size() == 2:
		range_a = int(env_range[0])
		range_b = int(env_range[1])
	var x0 := range_a * SPACING
	var x1 := range_b * SPACING
	var cx := (x0 + x1) * 0.5
	var half_w := (x1 - x0) * 0.5 + 5.0
	var ground := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(items.size() * SPACING + 20.0, 0.2, 40.0)
	ground.mesh = gm
	ground.material_override = RetroMaterials.dead_grass()
	ground.position = Vector3(items.size() * SPACING * 0.5 - SPACING * 0.5, -0.1, 0)
	add_child(ground)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.04, 0.06, 0.16)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.6, 0.85)
	env.ambient_light_energy = 0.8
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.light_color = Color(0.7, 0.75, 1.0)
	sun.light_energy = 0.9
	add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 40.0
	var dist := half_w / (tan(deg_to_rad(cam.fov * 0.5)) * 1.78)
	cam.position = Vector3(cx, 4.0 + dist * 0.18, dist)
	add_child(cam)
	cam.look_at(Vector3(cx, 3.0, 0))
	cam.current = true
