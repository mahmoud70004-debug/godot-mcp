extends Node3D
## Review scene for the CC0 asset kit (assets/models/*.glb): every model on a grid on a ground
## plane, with the night environment and retro post-process of the region previews.
##   RC_CAM="x,y,z,look_x,look_y,look_z"   camera placement (default: overview of the grid)
##   RC_ONLY="name,name"                   only these models (file names without .glb)
##   RC_LIGHT=1                            brighter ambient + moon (albedo review)
##   RC_COLS=8                             models per row
## Models are sorted small to large (props in front, trees at the back); multi-piece GLBs are lined up.
## Grid cell = widest model footprint in the row + 2 m; labels float above each model.

const MODEL_DIR := "res://assets/models"
const WORLD_TEX := "res://assets/textures/world/forest_floor.png"

var _stats: Array[String] = []


func _ready() -> void:
	var names := _model_names()
	var only := OS.get_environment("RC_ONLY")
	if only != "":
		var keep := only.split(",")
		names = names.filter(func(n: String) -> bool: return keep.has(n))
	names = _sorted_by_size(names)
	var cols := maxi(1, int(OS.get_environment("RC_COLS")) if OS.get_environment("RC_COLS") != "" else 8)
	var models := Node3D.new()
	models.name = "Models"
	add_child(models)
	var row_z := 0.0
	var row_depth := 0.0
	var x := 0.0
	var max_x := 0.0
	var tri_total := 0
	for i in names.size():
		var res := load("%s/%s.glb" % [MODEL_DIR, names[i]]) as PackedScene
		if res == null:
			push_error("cannot load %s" % names[i])
			continue
		var inst := res.instantiate() as Node3D
		models.add_child(inst)
		_pack_pieces(inst)
		var box := _aabb(inst)
		var w := maxf(box.size.x, box.size.z)
		if i % cols == 0 and i > 0:
			row_z += row_depth + 3.0
			row_depth = 0.0
			x = 0.0
		inst.position = Vector3(x + w * 0.5 - (box.position.x + box.size.x * 0.5), 0.0, row_z - (box.position.z + box.size.z * 0.5))
		var lbl := Label3D.new()
		lbl.text = names[i]
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.pixel_size = 0.006
		lbl.font_size = 40
		lbl.no_depth_test = true
		lbl.modulate = Color(0.9, 0.9, 0.7)
		lbl.position = inst.position + Vector3(0, maxf(box.size.y, 0.5) + 0.6, 0)
		models.add_child(lbl)
		tri_total += _tris(inst)
		_stats.append("%s size=%.2fx%.2fx%.2f m tris=%d" % [names[i], box.size.x, box.size.y, box.size.z, _tris(inst)])
		x += w + 2.0
		max_x = maxf(max_x, x)
		row_depth = maxf(row_depth, box.size.z)
	for s in _stats:
		print("kit ", s)
	print("kit models=%d tris=%d" % [names.size(), tri_total])
	_add_ground(max_x, row_z)
	if OS.get_environment("RC_LIGHT") != "":  # review aid: see the albedo without the night gloom
		($WorldEnvironment as WorldEnvironment).environment.ambient_light_energy = 3.0
		($Moonlight as DirectionalLight3D).light_energy = 2.0
	var cam := $Camera3D as Camera3D
	var raw := OS.get_environment("RC_CAM")
	var v := raw.split_floats(",") if raw != "" else PackedFloat64Array()  # "".split_floats crashes 4.4.1
	if v.size() == 6:
		cam.position = Vector3(v[0], v[1], v[2])
		cam.look_at(Vector3(v[3], v[4], v[5]))
	else:
		var cx := max_x * 0.5
		var cz := row_z * 0.5
		cam.position = Vector3(cx, maxf(max_x, row_z) * 0.35 + 4.0, row_z + maxf(max_x * 0.6, 10.0))
		cam.look_at(Vector3(cx, 2.0, cz))


## Multi-piece GLBs keep their scan layout (pieces can be 20 m apart): line them up for review.
func _pack_pieces(root: Node3D) -> void:
	var cursor := 0.0
	for c in root.get_children():
		if c is MeshInstance3D:
			var mi := c as MeshInstance3D
			var b := mi.get_aabb()
			var w := maxf(b.size.x, b.size.z) * mi.scale.x
			mi.position = Vector3(cursor + w * 0.5, mi.position.y, 0.0)
			cursor += w + 0.5


func _sorted_by_size(names: Array[String]) -> Array[String]:
	var sizes := {}
	for n in names:
		var res := load("%s/%s.glb" % [MODEL_DIR, n]) as PackedScene
		var inst := res.instantiate() as Node3D
		add_child(inst)
		_pack_pieces(inst)
		var b := _aabb(inst)
		sizes[n] = maxf(b.size.y, maxf(b.size.x, b.size.z))
		inst.free()
	var out := names.duplicate()
	out.sort_custom(func(a: String, b: String) -> bool: return sizes[a] < sizes[b])
	return out


func _model_names() -> Array[String]:
	var out: Array[String] = []
	var da := DirAccess.open(MODEL_DIR)
	if da == null:
		return out
	for f in da.get_files():
		var n := f.trim_suffix(".import")
		if n.ends_with(".glb") and not out.has(n.get_basename()):
			out.append(n.get_basename())
	out.sort_custom(func(a: String, b: String) -> bool: return a.to_lower() < b.to_lower())
	return out


func _meshes(n: Node, acc: Array[MeshInstance3D]) -> void:
	if n is MeshInstance3D:
		acc.append(n as MeshInstance3D)
	for c in n.get_children():
		_meshes(c, acc)


func _aabb(root: Node3D) -> AABB:
	var acc: Array[MeshInstance3D] = []
	_meshes(root, acc)
	var box := AABB()
	var first := true
	for m in acc:
		var b := root.global_transform.affine_inverse() * m.global_transform * m.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _tris(root: Node3D) -> int:
	var acc: Array[MeshInstance3D] = []
	_meshes(root, acc)
	var t := 0
	for m in acc:
		for s in m.mesh.get_surface_count():
			var arr := m.mesh.surface_get_arrays(s)
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			t += idx.size() / 3 if idx.size() > 0 else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return t


func _add_ground(width: float, depth: float) -> void:
	var g := MeshInstance3D.new()
	g.name = "Ground"
	var p := PlaneMesh.new()
	p.size = Vector2(width + 60.0, depth + 60.0)
	g.mesh = p
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(WORLD_TEX)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	m.uv1_scale = Vector3(p.size.x / 4.0, p.size.y / 4.0, 1.0)
	g.material_override = m
	g.position = Vector3(width * 0.5, 0.0, depth * 0.5)
	add_child(g)
