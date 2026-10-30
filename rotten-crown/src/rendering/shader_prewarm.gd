class_name ShaderPrewarm
extends RefCounted
## Compiles every shader a scene will need while the screen is still black.
##
## The Compatibility renderer (web) compiles a material's shader the first time
## it is drawn, on the main thread; turning the camera towards something new
## then stalls a frame or more on phones. warm() draws one tiny copy of every
## unique (material, vertex format) in front of the camera for a few frames,
## lit by a temporary omni light so the per-light pass variants compile too.

const DISTANCE := 1.2
const CELL := 0.03
const FRAMES := 3
## While warming, the camera and every light see only the copies (this layer): the
## world behind the fade is neither drawn nor shadowed, so the black wait is short
## even on a slow GPU (phones, software GL).
const WARM_LAYER := 1 << 19


## Await this behind a fade. `root` is scanned for GeometryInstance3D nodes.
static func warm(root: Node, camera: Camera3D) -> void:
	if camera == null or not camera.is_inside_tree():
		return
	var lights := root.find_children("*", "Light3D", true, false)
	var light_masks: Array[int] = []
	for l in lights:
		light_masks.append((l as Light3D).light_cull_mask)
		(l as Light3D).light_cull_mask = WARM_LAYER
	var camera_mask := camera.cull_mask
	camera.cull_mask = WARM_LAYER
	var holder := Node3D.new()
	holder.name = "ShaderPrewarm"
	camera.add_child(holder)
	holder.position = Vector3(0.0, 0.0, -DISTANCE)
	var light := OmniLight3D.new()
	light.omni_range = 1.0
	light.light_energy = 0.2
	light.shadow_enabled = false
	holder.add_child(light)
	var seen := {}
	var copies: Array[Node3D] = []
	for node in root.find_children("*", "GeometryInstance3D", true, false):
		var copy := _copy_for(node as GeometryInstance3D, seen)
		if copy != null:
			copies.append(copy)
	var cols := maxi(1, ceili(sqrt(float(copies.size()))))
	for i in copies.size():
		var c := copies[i]
		var slot := Vector3((float(i % cols) / cols - 0.5) * 0.6, (float(i / cols) / cols - 0.5) * 0.34, 0.0)
		# Merged meshes sit at world coordinates: centre each copy on its slot.
		c.position = slot - (c.get_meta(&"centre") as Vector3) * c.scale.x
		holder.add_child(c)
	for _i in FRAMES:
		await RenderingServer.frame_post_draw
	holder.queue_free()
	if is_instance_valid(camera):
		camera.cull_mask = camera_mask
	for i in lights.size():
		if is_instance_valid(lights[i]):
			(lights[i] as Light3D).light_cull_mask = light_masks[i]


## A tiny stand-in that draws `gi`'s materials with the same vertex format, or
## null if every one of its (material, format) pairs was already covered.
static func _copy_for(gi: GeometryInstance3D, seen: Dictionary) -> Node3D:
	if not gi.is_visible_in_tree():
		return null
	var copy: GeometryInstance3D = null
	if gi is MeshInstance3D:
		var mi := gi as MeshInstance3D
		if mi.mesh == null or not _new_pair(mi.mesh, mi, seen):
			return null
		var m := MeshInstance3D.new()
		m.mesh = mi.mesh
		m.material_override = mi.material_override
		for s in mi.get_surface_override_material_count():
			m.set_surface_override_material(s, mi.get_surface_override_material(s))
		copy = m
	elif gi is MultiMeshInstance3D:
		var mm := gi as MultiMeshInstance3D
		if mm.multimesh == null or mm.multimesh.mesh == null or not _new_pair(mm.multimesh.mesh, mm, seen):
			return null
		var m := MultiMeshInstance3D.new()
		m.multimesh = mm.multimesh
		m.material_override = mm.material_override
		copy = m
	elif gi is SpriteBase3D:
		var sp := gi as SpriteBase3D
		var key := "sprite|%d|%d" % [sp.material_override.get_instance_id() if sp.material_override else 0, sp.billboard]
		if seen.has(key):
			return null
		seen[key] = true
		var s := Sprite3D.new()
		s.texture = (sp as Sprite3D).texture if sp is Sprite3D else null
		s.material_override = sp.material_override
		s.billboard = sp.billboard
		s.alpha_cut = sp.alpha_cut
		s.shaded = sp.shaded
		s.double_sided = sp.double_sided
		s.texture_filter = sp.texture_filter
		copy = s
	if copy == null:
		return null
	copy.cast_shadow = gi.cast_shadow
	copy.layers = WARM_LAYER
	copy.visibility_range_end = 0.0
	copy.extra_cull_margin = 16384.0
	var box := copy.get_aabb()
	var size := maxf(maxf(box.size.x, box.size.y), maxf(box.size.z, 0.001))
	copy.scale = Vector3.ONE * (CELL / size)
	copy.set_meta(&"centre", box.get_center())
	return copy


static func _new_pair(mesh: Mesh, gi: GeometryInstance3D, seen: Dictionary) -> bool:
	var fresh := false
	for s in mesh.get_surface_count():
		var mat: Material = gi.material_override
		if mat == null and gi is MeshInstance3D:
			mat = (gi as MeshInstance3D).get_active_material(s)
		if mat == null:
			mat = mesh.surface_get_material(s)
		# Primitive meshes (BoxMesh...) share one standard vertex format.
		var fmt := (mesh as ArrayMesh).surface_get_format(s) if mesh is ArrayMesh else -1
		var key := "%d|%d|%d" % [mat.get_instance_id() if mat else 0, fmt, int(gi is MultiMeshInstance3D)]
		if not seen.has(key):
			seen[key] = true
			fresh = true
	return fresh
