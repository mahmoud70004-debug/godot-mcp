class_name Level
extends Node3D
## Procedurally generated abandoned hospital wing: a maze of narrow corridors
## with loops, flickering lights, bloody writing, creepy dolls and an exit.

const W := 8
const H := 8
const CELL := 4.0
const WALL_H := 3.2
const WALL_T := 0.3

# h_walls[x][y] : wall on the north edge (z = y*CELL) of cell (x,y); y in 0..H
# v_walls[x][y] : wall on the west edge (x = x*CELL) of cell (x,y); x in 0..W
var h_walls := []
var v_walls := []
var astar := AStar2D.new()
var key_cells: Array[Vector2i] = []
var battery_cells: Array[Vector2i] = []
var lights: Array = []          # [{light, base, broken, lamp_mat}]
var dolls: Array[Node3D] = []
var exit_pos := Vector3.ZERO
var exit_label: Label3D
var exit_light: OmniLight3D
var font: Font

var wall_mat: StandardMaterial3D
var floor_mat: StandardMaterial3D
var ceil_mat: StandardMaterial3D

func build(p_font: Font) -> void:
	font = p_font
	_make_materials()
	_gen_maze()
	_build_geometry()
	_build_graph()
	_place_stuff()

static func cell_center(c: Vector2i) -> Vector3:
	return Vector3((c.x + 0.5) * CELL, 0.0, (c.y + 0.5) * CELL)

static func world_to_cell(p: Vector3) -> Vector2i:
	return Vector2i(clampi(int(floor(p.x / CELL)), 0, W - 1), clampi(int(floor(p.z / CELL)), 0, H - 1))

static func cell_id(c: Vector2i) -> int:
	return c.y * W + c.x

# ---------------------------------------------------------------- materials
func _tile_tex(sz: int, tiles: int, base: Color, grout: Color, grime: Color, stain_count: int) -> ImageTexture:
	# Dirty ceramic tiles: grout lines, per-tile tint, grime noise, rust/blood stains.
	var n := FastNoiseLite.new()
	n.seed = randi()
	n.frequency = 0.035
	n.fractal_octaves = 4
	var img := Image.create(sz, sz, false, Image.FORMAT_RGB8)
	var tsz := sz / tiles
	var tint := []
	for i in tiles * tiles:
		tint.append(randf_range(-0.05, 0.05))
	var stains := []
	for i in stain_count:
		stains.append([Vector2(randf() * sz, randf() * sz), randf_range(8.0, 40.0)])
	for y in sz:
		for x in sz:
			var gx := x % tsz
			var gy := y % tsz
			var g := gx < 2 or gy < 2
			var nv := n.get_noise_2d(x, y) * 0.5 + 0.5
			var c: Color
			if g:
				c = grout.lerp(grime, nv * 0.6)
			else:
				var ti: int = (y / tsz) * tiles + (x / tsz)
				c = base.lightened(tint[ti]) if tint[ti] > 0.0 else base.darkened(-tint[ti])
				c = c.lerp(grime, clampf(nv * nv * 1.3, 0.0, 0.85))
				if (gx + gy * 3) % 37 == 0 and nv > 0.6:
					c = c.darkened(0.5) # cracks
			for st in stains:
				var d: float = Vector2(x, y).distance_to(st[0])
				# streaks running down
				var dy: float = y - st[0].y
				var dx: float = absf(x - st[0].x)
				if d < st[1] or (dy > 0.0 and dy < st[1] * 3.0 and dx < st[1] * 0.25 * (1.0 - dy / (st[1] * 3.0))):
					c = c.lerp(Color(0.18, 0.05, 0.02), 0.45)
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

static var _tex_cache: Dictionary = {}

func _make_materials() -> void:
	if _tex_cache.is_empty():
		_tex_cache["wall"] = _tile_tex(256, 8, Color(0.52, 0.58, 0.5), Color(0.2, 0.2, 0.18), Color(0.08, 0.07, 0.05), 3)
		_tex_cache["floor"] = _tile_tex(256, 4, Color(0.36, 0.33, 0.3), Color(0.1, 0.09, 0.08), Color(0.05, 0.04, 0.03), 2)
		_tex_cache["ceil"] = _tile_tex(128, 2, Color(0.3, 0.3, 0.28), Color(0.1, 0.1, 0.1), Color(0.06, 0.05, 0.04), 1)
	wall_mat = StandardMaterial3D.new()
	wall_mat.albedo_texture = _tex_cache["wall"]
	wall_mat.roughness = 0.6
	wall_mat.uv1_triplanar = true
	wall_mat.uv1_scale = Vector3(0.5, 0.5, 0.5)
	floor_mat = StandardMaterial3D.new()
	floor_mat.albedo_texture = _tex_cache["floor"]
	floor_mat.roughness = 0.4
	floor_mat.uv1_scale = Vector3(W * 2, H * 2, 1)
	ceil_mat = StandardMaterial3D.new()
	ceil_mat.albedo_texture = _tex_cache["ceil"]
	ceil_mat.roughness = 1.0
	ceil_mat.uv1_scale = Vector3(W * 2, H * 2, 1)

# --------------------------------------------------------------------- maze
func _gen_maze() -> void:
	h_walls.clear()
	v_walls.clear()
	for x in W + 1:
		h_walls.append([])
		v_walls.append([])
		for y in H + 1:
			h_walls[x].append(true)
			v_walls[x].append(true)
	var visited := {}
	var stack: Array[Vector2i] = [Vector2i(0, 0)]
	visited[Vector2i(0, 0)] = true
	while not stack.is_empty():
		var c: Vector2i = stack.back()
		var opts: Array[Vector2i] = []
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if n.x >= 0 and n.y >= 0 and n.x < W and n.y < H and not visited.has(n):
				opts.append(n)
		if opts.is_empty():
			stack.pop_back()
			continue
		var n: Vector2i = opts[randi() % opts.size()]
		_open(c, n)
		visited[n] = true
		stack.append(n)
	# Knock out extra walls to create loops (so chases are possible).
	var extra := 14
	while extra > 0:
		var c := Vector2i(randi() % W, randi() % H)
		var d: Vector2i = [Vector2i(1, 0), Vector2i(0, 1)][randi() % 2]
		var n: Vector2i = c + d
		if n.x < W and n.y < H and not is_open(c, n):
			_open(c, n)
			extra -= 1

func _open(a: Vector2i, b: Vector2i) -> void:
	if a.x != b.x:
		v_walls[maxi(a.x, b.x)][a.y] = false
	else:
		h_walls[a.x][maxi(a.y, b.y)] = false

func is_open(a: Vector2i, b: Vector2i) -> bool:
	if a.x != b.x:
		return not v_walls[maxi(a.x, b.x)][a.y]
	return not h_walls[a.x][maxi(a.y, b.y)]

func neighbors(c: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n: Vector2i = c + d
		if n.x >= 0 and n.y >= 0 and n.x < W and n.y < H and is_open(c, n):
			out.append(n)
	return out

# ----------------------------------------------------------------- geometry
func _build_geometry() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	add_child(body)
	var transforms: Array[Transform3D] = []
	for x in W + 1:
		for y in H + 1:
			if x < W and h_walls[x][y]:
				transforms.append(Transform3D(Basis(), Vector3((x + 0.5) * CELL, WALL_H * 0.5, y * CELL)))
			if y < H and v_walls[x][y]:
				transforms.append(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(x * CELL, WALL_H * 0.5, (y + 0.5) * CELL)))
	var box := BoxMesh.new()
	box.size = Vector3(CELL + WALL_T, WALL_H, WALL_T)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = box
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = box.size
		cs.shape = sh
		cs.transform = transforms[i]
		body.add_child(cs)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = wall_mat
	add_child(mmi)
	# Floor
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(W * CELL, H * CELL)
	fl.mesh = pm
	fl.material_override = floor_mat
	fl.position = Vector3(W * CELL * 0.5, 0, H * CELL * 0.5)
	add_child(fl)
	var fcs := CollisionShape3D.new()
	var fsh := BoxShape3D.new()
	fsh.size = Vector3(W * CELL + 2, 1, H * CELL + 2)
	fcs.shape = fsh
	fcs.position = Vector3(W * CELL * 0.5, -0.5, H * CELL * 0.5)
	body.add_child(fcs)
	# Ceiling
	var ce := MeshInstance3D.new()
	var cm := PlaneMesh.new()
	cm.size = Vector2(W * CELL, H * CELL)
	cm.flip_faces = true
	ce.mesh = cm
	ce.material_override = ceil_mat
	ce.position = Vector3(W * CELL * 0.5, WALL_H, H * CELL * 0.5)
	ce.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ce)

func _build_graph() -> void:
	astar.clear()
	for y in H:
		for x in W:
			var c := Vector2i(x, y)
			astar.add_point(cell_id(c), Vector2(x, y))
	for y in H:
		for x in W:
			var c := Vector2i(x, y)
			for n in neighbors(c):
				if not astar.are_points_connected(cell_id(c), cell_id(n)):
					astar.connect_points(cell_id(c), cell_id(n))

func path_cells(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for p in astar.get_point_path(cell_id(from), cell_id(to)):
		out.append(Vector2i(int(p.x), int(p.y)))
	return out

func bfs_dist(from: Vector2i) -> Dictionary:
	var dist := {from: 0}
	var q: Array[Vector2i] = [from]
	while not q.is_empty():
		var c: Vector2i = q.pop_front()
		for n in neighbors(c):
			if not dist.has(n):
				dist[n] = dist[c] + 1
				q.append(n)
	return dist

# ------------------------------------------------------------------- props
func _place_stuff() -> void:
	var dist := bfs_dist(Vector2i(0, 0))
	var cells: Array = dist.keys()
	cells.sort_custom(func(a, b): return dist[a] > dist[b])
	# Keys: prefer dead ends far from start, spaced apart.
	var dead_ends: Array = cells.filter(func(c): return neighbors(c).size() == 1 and dist[c] > 3)
	var pool: Array = dead_ends + cells.filter(func(c): return dist[c] > 4 and not dead_ends.has(c))
	for c in pool:
		if key_cells.size() >= 5:
			break
		var ok := true
		for k in key_cells:
			if absi(k.x - c.x) + absi(k.y - c.y) < 3:
				ok = false
		if ok:
			key_cells.append(c)
	for c in pool:
		if key_cells.size() >= 5:
			break
		if not key_cells.has(c):
			key_cells.append(c)
	# Batteries
	var mids: Array = cells.filter(func(c): return dist[c] >= 3 and not key_cells.has(c))
	mids.shuffle()
	for i in mini(4, mids.size()):
		battery_cells.append(mids[i])
	# Ceiling lights (some broken, all flickering)
	var lc: Array = cells.duplicate()
	lc.shuffle()
	for i in 7:
		_add_lamp(lc[i], i >= 5)
	# Exit door on the west wall of the starting cell.
	_build_exit()
	# Writings on the walls
	var words := ["لا تنظر خلفك", "إنه يراك", "اهرب", "لا مفر", "كان يبتسم", "لماذا عدت؟", "لم يخرج أحد", "أنا خلفك", "توقف عن التنفس", "إنه لا ينام"]
	words.shuffle()
	var wc: Array = cells.duplicate()
	wc.shuffle()
	var placed := 0
	for c in wc:
		if placed >= 8 or c == Vector2i(0, 0):
			continue
		if _add_writing(c, words[placed % words.size()]):
			placed += 1
	# Blood pools and debris
	for i in 18:
		var c: Vector2i = cells[randi() % cells.size()]
		var p := cell_center(c) + Vector3(randf_range(-1.2, 1.2), 0.01, randf_range(-1.2, 1.2))
		if i % 2 == 0:
			_add_blood(p)
		else:
			_add_debris(p)
	# Dolls that turn their heads when you are not looking.
	var dc: Array = cells.filter(func(c): return dist[c] >= 2)
	dc.shuffle()
	for i in mini(5, dc.size()):
		_add_doll(dc[i])
	# Hospital beds / wheelchairs as silhouettes
	for i in 5:
		var c: Vector2i = cells[randi() % cells.size()]
		if c != Vector2i(0, 0):
			_add_bed(c)

func _add_lamp(c: Vector2i, broken: bool) -> void:
	var p := cell_center(c) + Vector3(0, WALL_H - 0.05, 0)
	var lamp := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.2, 0.06, 0.25)
	lamp.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.9, 0.85, 0.6)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.85, 0.55)
	m.emission_energy_multiplier = 2.0
	lamp.material_override = m
	lamp.position = p
	lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(lamp)
	var l := OmniLight3D.new()
	l.position = p - Vector3(0, 0.3, 0)
	l.light_color = Color(1.0, 0.8, 0.55)
	l.omni_range = 6.5
	l.omni_attenuation = 1.6
	l.light_energy = 0.0 if broken else 0.9
	l.shadow_enabled = false
	add_child(l)
	lights.append({"light": l, "base": 0.0 if broken else 0.9, "broken": broken, "mat": m, "t": randf() * 10.0, "kill": 0.0})

func _wall_slot(c: Vector2i) -> Dictionary:
	# Returns a wall face inside cell c: {pos, normal}
	var cc := cell_center(c)
	var opts := []
	if h_walls[c.x][c.y]:
		opts.append([cc + Vector3(0, 0, -CELL * 0.5 + WALL_T * 0.5 + 0.02), Vector3(0, 0, 1)])
	if h_walls[c.x][c.y + 1]:
		opts.append([cc + Vector3(0, 0, CELL * 0.5 - WALL_T * 0.5 - 0.02), Vector3(0, 0, -1)])
	if v_walls[c.x][c.y]:
		opts.append([cc + Vector3(-CELL * 0.5 + WALL_T * 0.5 + 0.02, 0, 0), Vector3(1, 0, 0)])
	if v_walls[c.x + 1][c.y]:
		opts.append([cc + Vector3(CELL * 0.5 - WALL_T * 0.5 - 0.02, 0, 0), Vector3(-1, 0, 0)])
	if opts.is_empty():
		return {}
	var o = opts[randi() % opts.size()]
	return {"pos": o[0], "normal": o[1]}

func _add_writing(c: Vector2i, text: String) -> bool:
	var s := _wall_slot(c)
	if s.is_empty():
		return false
	var l := Label3D.new()
	l.text = text
	l.font = font
	l.font_size = 96
	l.pixel_size = 0.006
	l.modulate = Color(0.45, 0.0, 0.0, 0.92)
	l.outline_size = 0
	l.shaded = true
	l.double_sided = false
	l.position = s.pos + Vector3(0, randf_range(1.3, 2.0), 0)
	add_child(l)
	l.look_at(l.position - s.normal, Vector3.UP)
	l.rotate_object_local(Vector3.FORWARD, randf_range(-0.12, 0.12))
	return true

func _add_blood(p: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var cy := CylinderMesh.new()
	cy.top_radius = randf_range(0.3, 0.8)
	cy.bottom_radius = cy.top_radius
	cy.height = 0.01
	cy.radial_segments = 12
	mi.mesh = cy
	mi.material_override = Creature._mat("blood")
	mi.position = p
	mi.scale = Vector3(1.0, 1.0, randf_range(0.5, 1.4))
	mi.rotation.y = randf() * TAU
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

func _add_debris(p: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(randf_range(0.2, 0.6), randf_range(0.1, 0.4), randf_range(0.2, 0.6))
	mi.mesh = bm
	mi.material_override = wall_mat
	mi.position = p + Vector3(0, bm.size.y * 0.5, 0)
	mi.rotation.y = randf() * TAU
	add_child(mi)

func _add_bed(c: Vector2i) -> void:
	var s := _wall_slot(c)
	if s.is_empty():
		return
	var root := Node3D.new()
	add_child(root)
	root.position = s.pos + s.normal * 0.55
	root.look_at(root.position + s.normal.cross(Vector3.UP), Vector3.UP)
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.3, 0.3, 0.32)
	metal.metallic = 0.6
	metal.roughness = 0.5
	var sheet := StandardMaterial3D.new()
	sheet.albedo_color = Color(0.55, 0.52, 0.45)
	var frame := MeshInstance3D.new()
	var fb := BoxMesh.new()
	fb.size = Vector3(0.9, 0.08, 2.0)
	frame.mesh = fb
	frame.material_override = metal
	frame.position.y = 0.55
	root.add_child(frame)
	var mat := MeshInstance3D.new()
	var mb := BoxMesh.new()
	mb.size = Vector3(0.85, 0.15, 1.9)
	mat.mesh = mb
	mat.material_override = sheet
	mat.position.y = 0.65
	root.add_child(mat)
	# a covered "body" under the sheet... sometimes
	if randf() < 0.6:
		var lump := MeshInstance3D.new()
		var cap := CapsuleMesh.new()
		cap.radius = 0.22
		cap.height = 1.7
		lump.mesh = cap
		lump.material_override = sheet
		lump.rotation.x = PI * 0.5
		lump.position.y = 0.8
		lump.scale = Vector3(1, 1, 0.55)
		root.add_child(lump)
		_add_blood(root.position + Vector3(randf_range(-0.3, 0.3), 0.01, randf_range(-0.3, 0.3)))
	for lx in [-0.4, 0.4]:
		for lz in [-0.9, 0.9]:
			var leg := MeshInstance3D.new()
			var lb := BoxMesh.new()
			lb.size = Vector3(0.04, 0.55, 0.04)
			leg.mesh = lb
			leg.material_override = metal
			leg.position = Vector3(lx, 0.275, lz)
			root.add_child(leg)

func _add_doll(c: Vector2i) -> void:
	var s := _wall_slot(c)
	if s.is_empty():
		return
	var doll := Node3D.new()
	add_child(doll)
	doll.position = s.pos + s.normal * 0.35 + Vector3(randf_range(-1.0, 1.0) * s.normal.z, 0, randf_range(-1.0, 1.0) * s.normal.x)
	doll.look_at(doll.position + s.normal, Vector3.UP)
	var dress := StandardMaterial3D.new()
	dress.albedo_color = Color(0.35, 0.05, 0.08)
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.85, 0.78, 0.72)
	skin.roughness = 0.3
	var body := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.06
	cone.bottom_radius = 0.17
	cone.height = 0.35
	body.mesh = cone
	body.material_override = dress
	body.position.y = 0.175
	doll.add_child(body)
	var head := Node3D.new()
	head.name = "Head"
	head.position.y = 0.45
	doll.add_child(head)
	var hm := MeshInstance3D.new()
	hm.mesh = Creature._sphere(0.1)
	hm.material_override = skin
	head.add_child(hm)
	for side in [-1.0, 1.0]:
		var e := MeshInstance3D.new()
		e.mesh = Creature._sphere(0.02)
		e.material_override = Creature._mat("hole")
		e.position = Vector3(0.035 * side, 0.02, -0.085)
		head.add_child(e)
	var mouth := MeshInstance3D.new()
	mouth.mesh = Creature._box(Vector3(0.05, 0.008, 0.01))
	mouth.material_override = Creature._mat("blood")
	mouth.position = Vector3(0, -0.04, -0.095)
	head.add_child(mouth)
	dolls.append(doll)

func _build_exit() -> void:
	# Door frame on the west outer wall of cell (0,0)
	var cc := cell_center(Vector2i(0, 0))
	var wall_x := WALL_T * 0.5 + 0.03
	exit_pos = Vector3(wall_x + 0.4, 0, cc.z)
	var door := MeshInstance3D.new()
	var dm := BoxMesh.new()
	dm.size = Vector3(0.1, 2.3, 1.3)
	door.mesh = dm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.22, 0.12, 0.08)
	mat.roughness = 0.7
	door.material_override = mat
	door.position = Vector3(wall_x, 1.15, cc.z)
	add_child(door)
	var handle := MeshInstance3D.new()
	handle.mesh = Creature._sphere(0.05)
	var hm := StandardMaterial3D.new()
	hm.albedo_color = Color(0.6, 0.55, 0.3)
	hm.metallic = 1.0
	handle.material_override = hm
	handle.position = Vector3(wall_x + 0.08, 1.05, cc.z + 0.45)
	add_child(handle)
	exit_label = Label3D.new()
	exit_label.font = font
	exit_label.text = "مخرج - مُقفل"
	exit_label.font_size = 64
	exit_label.pixel_size = 0.006
	exit_label.modulate = Color(1, 0.15, 0.1)
	exit_label.position = Vector3(wall_x + 0.02, 2.55, cc.z)
	exit_label.rotation.y = -PI * 0.5
	exit_label.shaded = false
	exit_label.double_sided = false
	add_child(exit_label)
	exit_label.rotation.y = PI * 0.5
	exit_light = OmniLight3D.new()
	exit_light.light_color = Color(1, 0.1, 0.05)
	exit_light.light_energy = 0.8
	exit_light.omni_range = 3.5
	exit_light.position = Vector3(wall_x + 0.4, 2.5, cc.z)
	add_child(exit_light)
