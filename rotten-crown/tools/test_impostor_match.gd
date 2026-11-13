extends Node
## V7-5: a tree and its impostor must look the same at the near/far swap (one frame, one
## distance, no dither: ViewDistance.SWAP_FADE 0).
##   xvfb-run -a -s "-screen 0 1280x720x24" <godot binary> --path . --rendering-driver opengl3 \
##       --audio-driver Dummy tools/test_impostor_match.tscn
## (A real renderer: the forest shaders only compile for real under OpenGL, not --headless.)
## For every ForestTrees style, at every swap distance (ViewDistance.NEAR_TREES: Low, Medium,
## High) and from eight directions around the tree, renders the near mesh and then its
## impostor card with the shared forest materials under the overworld moon (moon direction,
## colour and sky ambient read from valdron_overworld.tscn, the same global shader
## parameters as in game), once in the open and once under a half canopy shade, and
## compares the mean display colour of the tree's pixels above the ground (exposure + tonemap of the
## overworld environment; no fog, no wind, no clouds, white instance tint, no moss: the
## impostor has none by design).
## PASS when, for every style, the colour difference averaged over all those views is below
## LIMIT / 255 per channel and no single view differs by WORST_LIMIT / 255 or more (a flat
## card cannot be the mesh from every direction: the worst view is reported and bounded).
## Prints one line per style and IMPOSTOR_MATCH_FAILURES <n>; exits with that count.
## IMPOSTOR_MATCH_VERBOSE=1 prints every view, IMPOSTOR_MATCH_DUMP=<dir> saves the frames.

const OVERWORLD := "res://src/levels/valdron/valdron_overworld.tscn"
const LIMIT := 6.0
const WORST_LIMIT := 10.0
const YAWS := 8
## Eye height above the tree's foot; the camera looks at the middle of the tree.
const EYE := 1.6
## Canopy shade values tried (1 = open sky).
const SHADES := [1.0, 0.45]
const BG := Color(1.0, 0.0, 1.0)

var _camera: Camera3D
var _holder: Node3D
var _bg: Image


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var root := Node3D.new()
	add_child(root)
	_holder = Node3D.new()
	root.add_child(_holder)
	_camera = Camera3D.new()
	_camera.fov = 72.0
	_camera.near = 0.05
	_camera.far = 300.0
	root.add_child(_camera)
	_camera.make_current()
	# The ground (the buried trunk foot and the roots under it are never seen in game).
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(400.0, 400.0)
	ground.mesh = plane
	var ground_mat := StandardMaterial3D.new()
	ground_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ground_mat.albedo_color = Color(0.0, 0.5, 0.0)
	ground.material_override = ground_mat
	root.add_child(ground)
	var we := WorldEnvironment.new()
	we.environment = _environment()
	root.add_child(we)
	_set_moon()
	var near_mat := (ForestTrees.material("tree").duplicate() as ShaderMaterial)
	near_mat.set_shader_parameter("lod_begin", 0.0)
	near_mat.set_shader_parameter("lod_end", 100000.0)
	near_mat.set_shader_parameter("fade_out", 0.0)
	var far_mat := (ForestTrees.material("far").duplicate() as ShaderMaterial)
	far_mat.set_shader_parameter("lod_begin", 0.0)
	far_mat.set_shader_parameter("fade_in", 0.0)
	far_mat.set_shader_parameter("lod_end", 100000.0)
	far_mat.set_shader_parameter("fade_out", 0.0)
	# The background (sky colour + ground) seen from every pose is captured per pose.
	var failures := 0
	var distances: Array = ViewDistance.NEAR_TREES
	print("IMPOSTOR_MATCH mean < %.1f/255 and worst < %.1f/255 per channel; distances %s; %d directions; canopy shade %s" % [
		LIMIT, WORST_LIMIT, distances, YAWS, SHADES])
	print("     style   | mean |dR| |dG| |dB| | worst |dR| |dG| |dB| (at)           | pixels mesh/impostor")
	for style in ForestTrees.NAMES.size():
		var worst := Vector3.ZERO
		var worst_at := ""
		var sum := Vector3.ZERO
		var n := 0
		var px := Vector2.ZERO
		for shade: float in SHADES:
			_set_shade(shade)
			for dist: float in distances:
				for k in YAWS:
					var yaw := TAU * k / YAWS
					var a: Array = await _capture(_near_instance(style, near_mat), style, dist, yaw)
					var b: Array = await _capture(_far_instance(style, far_mat), style, dist, yaw)
					var signed := (b[0] as Vector3) - (a[0] as Vector3)
					var d := signed.abs()
					if OS.get_environment("IMPOSTOR_MATCH_VERBOSE") != "":
						print("  %-7s %2.0fm %3d deg s%.2f mesh %s impostor-mesh %s" % [ForestTrees.NAMES[style], dist,
							roundi(rad_to_deg(yaw)), shade, (a[0] as Vector3).round(), signed.snapped(Vector3.ONE * 0.1)])
					sum += d
					n += 1
					px += Vector2(float(a[1]), float(b[1]))
					if maxf(d.x, maxf(d.y, d.z)) > maxf(worst.x, maxf(worst.y, worst.z)):
						worst = d
						worst_at = "%.0fm %3d deg s%.2f" % [dist, roundi(rad_to_deg(yaw)), shade]
		var mean := sum / maxf(n, 1)
		var ok := maxf(mean.x, maxf(mean.y, mean.z)) < LIMIT and maxf(worst.x, maxf(worst.y, worst.z)) < WORST_LIMIT
		if not ok:
			failures += 1
		print("%s %-7s | %4.1f %4.1f %4.1f      | %4.1f %4.1f %4.1f (%s) | %d/%d" % ["PASS" if ok else "FAIL", ForestTrees.NAMES[style],
			mean.x, mean.y, mean.z, worst.x, worst.y, worst.z, worst_at, roundi(px.x / n), roundi(px.y / n)])
	print("IMPOSTOR_MATCH_FAILURES %d" % failures)
	get_tree().quit(failures)


## The overworld environment's exposure, tonemap and colour adjustment; a flat background
## (the mask) instead of the sky, no fog, no glow.
func _environment() -> Environment:
	var env := Environment.new()
	var src := _overworld_property("WorldEnvironment", "environment") as Environment
	if src:
		env = src.duplicate() as Environment
	env.background_mode = Environment.BG_COLOR
	env.background_color = BG
	env.fog_enabled = false
	env.glow_enabled = false
	env.volumetric_fog_enabled = false
	return env


## Moon direction / colour (linear, as Moonlight pushes them) and the sky ambient of the
## overworld; no clouds, no wind.
func _set_moon() -> void:
	var rot: Variant = _overworld_property("Moonlight", "rotation")
	var col: Variant = _overworld_property("Moonlight", "light_color")
	var energy: Variant = _overworld_property("Moonlight", "light_energy")
	var basis := Basis.from_euler(rot as Vector3 if rot != null else Vector3(-0.524, -2.634, 0.0))
	var c := (col as Color if col != null else Color(0.58, 0.7, 1.0)).srgb_to_linear()
	var e := float(energy) if energy != null else 1.15
	var model := Moonlight.new()
	var top: Variant = _overworld_property("MoonlightModel", "ambient_top")
	var bottom: Variant = _overworld_property("MoonlightModel", "ambient_bottom")
	var amb_top: Color = top if top != null else model.ambient_top
	var amb_bottom: Color = bottom if bottom != null else model.ambient_bottom
	model.free()
	RenderingServer.global_shader_parameter_set(&"moon_dir", basis.z.normalized())
	RenderingServer.global_shader_parameter_set(&"moon_color", Color(c.r * e, c.g * e, c.b * e, 1.0))
	RenderingServer.global_shader_parameter_set(&"sky_ambient_top", amb_top)
	RenderingServer.global_shader_parameter_set(&"sky_ambient_bottom", amb_bottom)
	RenderingServer.global_shader_parameter_set(&"cloud_strength", 0.0)
	RenderingServer.global_shader_parameter_set(&"wind", Vector4(1.0, 0.0, 0.0, 0.0))


## A uniform canopy shade over the test area.
func _set_shade(value: float) -> void:
	var img := Image.create(4, 4, false, Image.FORMAT_L8)
	img.fill(Color(value, value, value))
	RenderingServer.global_shader_parameter_set(&"shade_map", ImageTexture.create_from_image(img))
	RenderingServer.global_shader_parameter_set(&"shade_rect", Vector4(-100.0, -100.0, 100.0, 100.0))


## A property of a node (by name) as stored in the overworld scene, or null.
func _overworld_property(node_name: String, prop: String) -> Variant:
	var packed := load(OVERWORLD) as PackedScene
	var state := packed.get_state()
	for i in state.get_node_count():
		if String(state.get_node_name(i)) != node_name:
			continue
		for p in state.get_node_property_count(i):
			if String(state.get_node_property_name(i, p)) == prop:
				return state.get_node_property_value(i, p)
	return null


func _near_instance(style: int, mat: ShaderMaterial) -> MultiMeshInstance3D:
	var mesh := (ForestTrees.tree(style, 0)["mesh"] as ArrayMesh).duplicate() as ArrayMesh
	mesh.surface_set_material(0, mat)
	return _instance(mesh, Transform3D.IDENTITY, Color(0.0, 0.0, 0.0, 0.0))


## The impostor exactly as ForestBuilder places it: the card scaled to the style's size,
## the atlas cell in the custom data.
func _far_instance(style: int, mat: ShaderMaterial) -> MultiMeshInstance3D:
	var size := ForestTrees.impostor_size(style)
	var cell := ForestAtlas.impostor_rect(style)
	var uv := Vector2(cell.position) / ForestAtlas.SIZE
	var mmi := _instance(ForestFloor.mesh("card"), Transform3D(Basis.from_scale(Vector3(size.x, size.y, size.x)), Vector3.ZERO),
		Color(uv.x, uv.y, 0.0, 0.0))
	mmi.material_override = mat
	return mmi


func _instance(mesh: Mesh, xf: Transform3D, custom: Color) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = 1
	mm.set_instance_transform(0, xf)
	mm.set_instance_color(0, Color.WHITE)
	mm.set_instance_custom_data(0, custom)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.custom_aabb = AABB(Vector3(-20.0, -2.0, -20.0), Vector3(40.0, 40.0, 40.0))
	return mmi


## Renders `inst` alone from `dist` m at azimuth `yaw`; returns [mean display colour of the
## tree pixels (0..255), pixel count].
func _capture(inst: MultiMeshInstance3D, style: int, dist: float, yaw: float) -> Array:
	for c in _holder.get_children():
		c.queue_free()
	var mid := ForestTrees.impostor_size(style).y * 0.5
	_camera.position = Vector3(sin(yaw) * dist, EYE, cos(yaw) * dist)
	_camera.look_at(Vector3(0.0, mid, 0.0))
	for _i in 2:
		await RenderingServer.frame_post_draw
	_bg = get_viewport().get_texture().get_image()
	_holder.add_child(inst)
	for _i in 3:
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var dump := OS.get_environment("IMPOSTOR_MATCH_DUMP")
	if dump != "":
		img.save_png("%s/%s_%02d_%03d_%s.png" % [dump, ForestTrees.NAMES[style], roundi(dist), roundi(rad_to_deg(yaw)),
			"mesh" if inst.material_override == null else "imp"])
	var sum := Vector3.ZERO
	var count := 0
	for y in img.get_height():
		for x in img.get_width():
			var p := img.get_pixel(x, y)
			var q := _bg.get_pixel(x, y)
			if absf(p.r - q.r) + absf(p.g - q.g) + absf(p.b - q.b) < 0.02:
				continue
			sum += Vector3(p.r, p.g, p.b)
			count += 1
	return [sum / maxf(count, 1) * 255.0, count]
