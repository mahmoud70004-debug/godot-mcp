@tool
class_name ThornfieldFieldProps
extends RefCounted
## Field props of Thornfield (task U7): the wind-bent wheat sea as merged quad
## chunks, split-rail fences with nailed charms, too-human scarecrows, crows and
## the crow-picked carcass. Same rules as ThornfieldProps (whose materials and
## helpers it shares): primitives, shared materials, explicit RNG.

const WHEAT_SHADER := preload("res://assets/shaders/thornfield_wheat.gdshader")
const GRASS_CHUNK := 12.0

static var _wheat: ShaderMaterial


static func wheat_mat() -> ShaderMaterial:
	if _wheat == null:
		_wheat = ShaderMaterial.new()
		_wheat.shader = WHEAT_SHADER
	return _wheat


# --------------------------------------------------------------------------
# Split-rail fence with charms
# --------------------------------------------------------------------------
## Split-rail fence along the xz polyline `pts` on the terrain. `broken` is the
## chance a rail is fallen, dropped or snapped; `charms` the chance a post
## carries a nailed charm (hung on the `charm_side` of the line, +1 = left).
static func split_rail(terrain: TerrainBuilder, pts: PackedVector2Array, broken: float, charms: float, charm_side: float,
		rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	root.name = "SplitRail"
	var wood := RetroMaterials.wood()
	var grey := ThornfieldProps.weathered_board()
	var posts: Array[Vector3] = []
	var normals: Array[Vector3] = []
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var n := maxi(1, roundi(a.distance_to(b) / 2.6))
		var nrm := Vector2(-(b - a).y, (b - a).x).normalized() * charm_side
		for k in n:
			var q := a.lerp(b, float(k) / n)
			posts.append(terrain.ground(q.x, q.y))
			normals.append(Vector3(nrm.x, 0, nrm.y))
	var last: Vector2 = pts[pts.size() - 1]
	posts.append(terrain.ground(last.x, last.y))
	normals.append(normals[normals.size() - 1] if not normals.is_empty() else Vector3.FORWARD)
	var tops: Array[float] = []
	for i in posts.size():
		var stub := rng.randf() < broken * 0.25
		var h := rng.randf_range(0.6, 0.85) if stub else rng.randf_range(1.4, 1.6)
		tops.append(h)
		var pivot := PartBuilder.pivot(root, "Post", posts[i])
		pivot.rotation = Vector3(rng.randf_range(-0.09, 0.09), rng.randf_range(0, TAU), rng.randf_range(-0.09, 0.09))
		PartBuilder.box(pivot, Vector3(0.17, h + 0.2, 0.15), Vector3(0, h * 0.5 - 0.1, 0), grey if rng.randf() < 0.4 else wood)
		if stub:
			PartBuilder.box(pivot, Vector3(0.07, 0.22, 0.06), Vector3(0.03, h + 0.05, 0.02), wood, Vector3(0, 0, 0.3))
		elif rng.randf() < charms:
			_charm(root, posts[i] + Vector3(0, h - 0.1, 0) + normals[i] * 0.1, normals[i], rng)
	for i in posts.size() - 1:
		var a := posts[i]
		var b := posts[i + 1]
		for rail_h: float in [0.72, 1.28]:
			var ha: float = minf(rail_h, tops[i] - 0.1)
			var hb: float = minf(rail_h, tops[i + 1] - 0.1)
			var pa := a + Vector3(0, ha, 0)
			var pb := b + Vector3(0, hb, 0)
			var roll := rng.randf_range(-0.4, 0.4)
			var mat := grey if rng.randf() < 0.35 else wood
			var r := rng.randf()
			if r < broken * 0.3:
				# Fallen into the grass beside the line.
				var off := Vector3(rng.randf_range(-0.6, 0.6), 0, rng.randf_range(-0.6, 0.6))
				_rail(root, a.lerp(b, 0.1) + off + Vector3(0, 0.06, 0), b.lerp(a, 0.05) + off * 0.5 + Vector3(0, 0.06, 0), roll, mat)
			elif r < broken * 0.6:
				# One end slipped off its post to the ground.
				_rail(root, pa, b + Vector3(rng.randf_range(-0.3, 0.3), 0.05, rng.randf_range(-0.3, 0.3)), roll, mat)
			elif r < broken:
				# Snapped in the middle, both halves sagging.
				var mid := a.lerp(b, rng.randf_range(0.4, 0.6)) + Vector3(0, rail_h * 0.35, 0)
				_rail(root, pa, mid, roll, mat)
				_rail(root, mid + Vector3(0, 0.04, 0), pb, roll, mat)
			else:
				var ext := (pb - pa).normalized() * 0.2
				_rail(root, pa - ext, pb + ext, roll, mat)
	return root


static func _rail(parent: Node3D, a: Vector3, b: Vector3, roll: float, mat: Material) -> void:
	var mi := ThornfieldProps.beam(parent, a, b, 0.13, 0.09, mat)
	mi.rotate_object_local(Vector3.RIGHT, roll)


## A charm nailed to a fence post: crossed twigs, a hanging bone, an upturned
## horseshoe, a straw doll or a rag. `out` points away from the post.
static func _charm(parent: Node3D, at: Vector3, out: Vector3, rng: RandomNumberGenerator) -> void:
	var node := Node3D.new()
	node.name = "Charm"
	node.position = at
	node.basis = Basis.looking_at(-out, Vector3.UP) if out.length() > 0.1 else Basis.IDENTITY
	parent.add_child(node)
	var bark := RetroMaterials.bark()
	var rope := ThornfieldProps.rope_mat()
	var kind := rng.randi() % 5
	match kind:
		0:
			ThornfieldProps.limb(node, Vector3(-0.16, -0.18, 0.04), Vector3(0.16, 0.18, 0.04), 0.014, 0.01, bark, 3)
			ThornfieldProps.limb(node, Vector3(0.16, -0.18, 0.05), Vector3(-0.16, 0.18, 0.05), 0.014, 0.01, bark, 3)
			ThornfieldProps.limb(node, Vector3(0, -0.24, 0.045), Vector3(0, 0.2, 0.045), 0.012, 0.01, bark, 3)
			PartBuilder.box(node, Vector3(0.06, 0.05, 0.04), Vector3(0, 0, 0.05), rope)
		1:
			PartBuilder.box(node, Vector3(0.012, 0.3, 0.012), Vector3(0, -0.15, 0.04), rope)
			ThornfieldProps.limb(node, Vector3(-0.08, -0.32, 0.05), Vector3(0.09, -0.36, 0.05), 0.022, 0.018, ThornfieldProps.bone_mat(), 4)
			PartBuilder.sphere(node, 0.03, Vector3(-0.09, -0.32, 0.05), ThornfieldProps.bone_mat(), false, 4)
		2:
			var iron := RetroMaterials.iron()
			PartBuilder.box(node, Vector3(0.03, 0.14, 0.02), Vector3(-0.06, -0.02, 0.03), iron, Vector3(0, 0, 0.15))
			PartBuilder.box(node, Vector3(0.03, 0.14, 0.02), Vector3(0.06, -0.02, 0.03), iron, Vector3(0, 0, -0.15))
			PartBuilder.box(node, Vector3(0.12, 0.03, 0.02), Vector3(0, -0.09, 0.03), iron)
		3:
			var straw := RetroMaterials.straw()
			PartBuilder.box(node, Vector3(0.012, 0.18, 0.012), Vector3(0, -0.09, 0.05), rope)
			PartBuilder.box(node, Vector3(0.09, 0.2, 0.06), Vector3(0, -0.3, 0.06), straw, Vector3(0, 0, 0.1))
			PartBuilder.sphere(node, 0.045, Vector3(0, -0.17, 0.06), RetroMaterials.sack(), false, 5)
			for sx: float in [-1.0, 1.0]:
				PartBuilder.box(node, Vector3(0.025, 0.14, 0.025), Vector3(sx * 0.06, -0.42, 0.06), straw, Vector3(0, 0, sx * 0.2))
		_:
			PartBuilder.box(node, Vector3(0.08, 0.45, 0.01), Vector3(0.02, -0.22, 0.03), RetroMaterials.rag(), Vector3(0.1, 0, 0.12))


# --------------------------------------------------------------------------
# Scarecrows that are a little too human
# --------------------------------------------------------------------------
## pose 0: tied by the wrists along the bar, head lolled onto a shoulder;
## pose 1: head turned round to watch whoever passes behind it;
## pose 2: slipped down the pole, knees buckled, chin on the chest.
static func scarecrow(pose: int, rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	root.name = "Scarecrow"
	var wood := RetroMaterials.wood()
	var rag := RetroMaterials.rag()
	var sack := RetroMaterials.sack()
	var skin := RetroMaterials.skin()
	var straw := RetroMaterials.straw()
	var rope := ThornfieldProps.rope_mat()
	var dark := ThornfieldProps.void_mat()
	PartBuilder.box(root, Vector3(0.11, 2.75, 0.11), Vector3(0, 1.3, -0.12), wood, Vector3(rng.randf_range(-0.03, 0.03), 0, 0))
	PartBuilder.box(root, Vector3(1.95, 0.09, 0.09), Vector3(0, 1.86, -0.12), wood, Vector3(0, 0, rng.randf_range(-0.05, 0.05)))
	var drop := 0.32 if pose == 2 else 0.0
	var body := PartBuilder.pivot(root, "Body", Vector3(0, -drop, 0))
	# Coat, its tails, a rope belt.
	PartBuilder.frustum(body, 0.48, 0.38, 0.62, 0.24, Vector3(0, 1.5, 0), rag, Vector3(0.08 if pose == 2 else 0.0, 0, 0))
	PartBuilder.frustum(body, 0.4, 0.52, 0.42, 0.2, Vector3(0, 1.0, 0), rag)
	PartBuilder.box(body, Vector3(0.42, 0.04, 0.26), Vector3(0, 1.19, 0), rope)
	# Arms: wrists bound to the bar, hands hanging with fingers too long.
	for sx: float in [-1.0, 1.0]:
		var sh := Vector3(sx * 0.23, 1.78, 0)
		var elbow := Vector3(sx * 0.55, 1.84 + drop * 0.6, -0.04) if pose != 2 else Vector3(sx * 0.42, 1.6, 0.08)
		var wrist := Vector3(sx * 0.86, 1.88 + drop, -0.08) if pose != 2 else Vector3(sx * 0.62, 1.9 + drop, -0.08)
		ThornfieldProps.limb(body, sh, elbow, 0.075, 0.062, rag, 5)
		ThornfieldProps.limb(body, elbow, wrist, 0.062, 0.05, rag, 5)
		PartBuilder.box(body, Vector3(0.07, 0.07, 0.12), wrist + Vector3(sx * 0.02, 0, 0), rope)
		var hand := wrist + Vector3(sx * 0.07, -0.08, 0.02)
		PartBuilder.box(body, Vector3(0.05, 0.12, 0.09), hand, skin, Vector3(0, 0, sx * 0.1))
		for f in 4:
			PartBuilder.box(body, Vector3(0.016, 0.17, 0.016), hand + Vector3(sx * 0.005, -0.13, -0.03 + f * 0.02), skin, Vector3(0, 0, sx * (0.05 + f * 0.04)))
		PartBuilder.box(body, Vector3(0.05, 0.09, 0.05), wrist + Vector3(-sx * 0.06, 0.04, 0), straw, Vector3(0, 0, sx * 0.6))
	# Legs in sacking, bare feet hanging toes-down just above the ground.
	for sx: float in [-1.0, 1.0]:
		var hip := Vector3(sx * 0.1, 1.12, 0)
		var knee := Vector3(sx * 0.12, 0.66, 0.05 + (0.18 if pose == 2 else 0.0))
		var ankle := Vector3(sx * (0.1 + (0.03 if sx > 0.0 else 0.0)), 0.28 + (0.18 if pose == 2 else 0.0), 0.0)
		ThornfieldProps.limb(body, hip, knee, 0.085, 0.07, sack, 5)
		ThornfieldProps.limb(body, knee, ankle, 0.07, 0.055, sack, 5)
		PartBuilder.box(body, Vector3(0.085, 0.07, 0.2), ankle + Vector3(0, -0.06, 0.04), skin, Vector3(0.9, sx * 0.1, 0))
		PartBuilder.box(body, Vector3(0.07, 0.1, 0.07), ankle + Vector3(0, 0.05, 0), straw, Vector3(0, 0, sx * 0.4))
	# Head: a stitched sack, the noose still round its neck.
	var head := PartBuilder.pivot(body, "Head", Vector3(0, 1.84, 0.02))
	match pose:
		0:
			head.rotation = Vector3(0.25, 0.2, 0.95)
		1:
			head.rotation = Vector3(-0.1, 2.6, 0.12)
		_:
			head.rotation = Vector3(0.95, 0.3, 0.2)
	PartBuilder.cylinder(head, 0.085, 0.085, 0.06, Vector3(0, 0.02, 0), rope, 6)
	var skull := PartBuilder.sphere(head, 0.15, Vector3(0, 0.18, 0), sack, false, 8)
	skull.scale = Vector3(0.92, 1.12, 0.95)
	PartBuilder.sphere(head, 0.028, Vector3(-0.055, 0.21, 0.13), dark, false, 4)
	if rng.randf() < 0.5:
		PartBuilder.sphere(head, 0.028, Vector3(0.055, 0.21, 0.13), dark, false, 4)
	else:
		PartBuilder.sphere(head, 0.03, Vector3(0.055, 0.21, 0.135), ThornfieldProps.bone_mat(), false, 4)
	PartBuilder.box(head, Vector3(0.15, 0.012, 0.03), Vector3(0, 0.1, 0.13), dark)
	for i in 5:
		PartBuilder.box(head, Vector3(0.012, 0.05, 0.03), Vector3(-0.06 + i * 0.03, 0.1, 0.135), rope)
	if rng.randf() < 0.6:
		var hat := PartBuilder.pivot(head, "Hat", Vector3(0, 0.3, -0.01))
		hat.rotation = Vector3(-0.15, 0, 0.12)
		PartBuilder.cylinder(hat, 0.27, 0.29, 0.025, Vector3.ZERO, rag, 8)
		PartBuilder.cylinder(hat, 0.12, 0.14, 0.15, Vector3(0, 0.08, 0), rag, 7)
	for i in 4:
		PartBuilder.box(head, Vector3(0.04, 0.14, 0.03), Vector3(-0.12 + i * 0.08, 0.06, -0.08), straw, Vector3(0.3, 0, rng.randf_range(-0.3, 0.3)))
	var col := ThornfieldProps.new_body(root)
	ThornfieldProps.add_box(col, Vector3(0.3, 2.6, 0.3), Vector3(0, 1.3, -0.05))
	return root


# --------------------------------------------------------------------------
# Crows, carcass
# --------------------------------------------------------------------------
static func crow(rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	root.name = "Crow"
	var black := ThornfieldProps.crow_mat()
	var b := PartBuilder.sphere(root, 0.1, Vector3(0, 0.1, 0), black, false, 6)
	b.scale = Vector3(0.75, 0.72, 1.35)
	b.rotation.x = -0.35
	var head := PartBuilder.pivot(root, "Head", Vector3(0, 0.18, 0.1))
	head.rotation = Vector3(rng.randf_range(-0.3, 0.5), rng.randf_range(-1.2, 1.2), 0)
	PartBuilder.sphere(head, 0.05, Vector3.ZERO, black, false, 6)
	PartBuilder.box(head, Vector3(0.022, 0.025, 0.08), Vector3(0, -0.005, 0.07), RetroMaterials.flat(Color(0.12, 0.12, 0.12)), Vector3(0.15, 0, 0))
	PartBuilder.box(root, Vector3(0.09, 0.015, 0.16), Vector3(0, 0.06, -0.17), black, Vector3(0.35, 0, 0))
	for sx: float in [-1.0, 1.0]:
		PartBuilder.box(root, Vector3(0.012, 0.06, 0.012), Vector3(sx * 0.03, 0.03, 0.0), black)
	root.rotation.y = rng.randf() * TAU
	return root


## A crow-picked carcass lying on its side: the upper rib arch stripped bare,
## spine, skull and scattered leg bones, scraps of hide, old blood.
static func carcass(rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	root.name = "Carcass"
	var bone := ThornfieldProps.bone_mat()
	var hide := RetroMaterials.rag()
	var sack := RetroMaterials.sack()
	var spine: Array[Vector3] = []
	for i in 9:
		var t := float(i) / 8.0
		spine.append(Vector3(lerpf(-1.1, 1.0, t), 0.14 + sin(t * PI) * 0.1, -0.35 + sin(t * PI * 1.3) * 0.05))
	for i in spine.size() - 1:
		ThornfieldProps.limb(root, spine[i], spine[i + 1], 0.06, 0.055, bone, 5)
		PartBuilder.box(root, Vector3(0.05, 0.12, 0.05), spine[i] + Vector3(0, 0.08, -0.04), bone, Vector3(0, 0, 0.3))
	# Rib arch (some ribs snapped short).
	for i in 10:
		var x := lerpf(-0.45, 0.7, float(i) / 9.0)
		var reach := rng.randf_range(0.45, 1.0) if i % 3 == 1 else 1.0
		var a := Vector3(x, 0.2, -0.32)
		var b := Vector3(x + 0.04, 0.58, -0.12)
		var c := Vector3(x + 0.09, 0.66, 0.2)
		var e := Vector3(x + 0.12, 0.42, 0.48)
		ThornfieldProps.limb(root, a, b, 0.026, 0.022, bone, 3)
		ThornfieldProps.limb(root, b, b.lerp(c, minf(reach * 1.6, 1.0)), 0.022, 0.02, bone, 3)
		if reach > 0.8:
			ThornfieldProps.limb(root, c, e, 0.02, 0.014, bone, 3)
	# Pelvis and legs.
	PartBuilder.box(root, Vector3(0.36, 0.22, 0.5), Vector3(-1.25, 0.2, -0.3), bone, Vector3(0.2, 0.3, 0.4))
	var legs := [[Vector3(-1.3, 0.1, -0.1), Vector3(-1.9, 0.06, 0.5)], [Vector3(-1.9, 0.06, 0.5), Vector3(-2.3, 0.05, 0.2)],
		[Vector3(0.85, 0.08, 0.05), Vector3(1.0, 0.05, 0.75)], [Vector3(0.3, 0.05, 1.3), Vector3(0.9, 0.05, 1.55)]]
	for leg in legs:
		ThornfieldProps.limb(root, leg[0], leg[1], 0.045, 0.035, bone, 4)
	PartBuilder.box(root, Vector3(0.12, 0.1, 0.1), Vector3(-2.32, 0.05, 0.2), ThornfieldProps.void_mat())
	# Skull with horns and an empty eye, the jaw dragged away.
	var skull := PartBuilder.pivot(root, "Skull", Vector3(1.4, 0.16, -0.25))
	skull.rotation = Vector3(0.2, -0.4, 1.25)
	PartBuilder.frustum(skull, 0.26, 0.14, 0.52, 0.2, Vector3.ZERO, bone)
	PartBuilder.box(skull, Vector3(0.06, 0.06, 0.03), Vector3(0.08, 0.12, 0.1), ThornfieldProps.void_mat())
	for sx: float in [-1.0, 1.0]:
		ThornfieldProps.limb(skull, Vector3(sx * 0.12, 0.22, 0), Vector3(sx * 0.32, 0.34, -0.05), 0.04, 0.012, bone, 4)
	ThornfieldProps.limb(root, Vector3(1.6, 0.05, 0.6), Vector3(2.0, 0.04, 0.85), 0.04, 0.03, bone, 3)
	# Hide scraps still on the bones, and the stain under it all.
	for i in 4:
		var scrap := PartBuilder.box(root, Vector3(rng.randf_range(0.4, 0.7), 0.03, rng.randf_range(0.3, 0.5)),
			Vector3(rng.randf_range(-1.2, 0.2), rng.randf_range(0.12, 0.3), rng.randf_range(-0.5, 0.1)), hide if i % 2 == 0 else sack)
		scrap.rotation = Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(0, TAU), rng.randf_range(-0.4, 0.4))
	ThornfieldProps.splat(root, ThornfieldProps.blood_mat(), Vector3(0, 0.03, 0), 3.2, rng)
	ThornfieldProps.splat(root, ThornfieldProps.blood_mat(), Vector3(-1.4, 0.035, 0.4), 1.4, rng)
	return root


# --------------------------------------------------------------------------
# Wheat sea (merged quad chunks)
# --------------------------------------------------------------------------
## tufts: Array of [Vector3 foot, float yaw, float width, float height, float brightness].
## One ArrayMesh per GRASS_CHUNK cell (identity basis, see thornfield_wheat.gdshader),
## culled beyond range_end. Returns the "Grass" group (RC_PERF=nograss hides it).
static func grass_chunks(parent: Node3D, tufts: Array, range_end: float) -> Node3D:
	var group := Node3D.new()
	group.name = "Grass"
	parent.add_child(group)
	var cells: Dictionary = {}
	for tuft in tufts:
		var p: Vector3 = tuft[0]
		var cell := Vector2i(floori(p.x / GRASS_CHUNK), floori(p.z / GRASS_CHUNK))
		if not cells.has(cell):
			cells[cell] = []
		(cells[cell] as Array).append(tuft)
	var mat := wheat_mat()
	for cell in cells:
		var list: Array = cells[cell]
		var origin := Vector3(cell.x * GRASS_CHUNK, 0.0, cell.y * GRASS_CHUNK)
		var first: Vector3 = list[0][0]
		origin.y = first.y
		var verts := PackedVector3Array()
		var uvs := PackedVector2Array()
		var colors := PackedColorArray()
		var normals := PackedVector3Array()
		var indices := PackedInt32Array()
		for tuft in list:
			var foot: Vector3 = (tuft[0] as Vector3) - origin
			var yaw: float = tuft[1]
			var half: float = tuft[2] * 0.5
			var h: float = tuft[3]
			var right := Vector3(cos(yaw), 0.0, -sin(yaw)) * half
			var c := Color(randf_from(foot), h * 0.5, tuft[4])
			var base := verts.size()
			verts.append_array(PackedVector3Array([foot - right, foot + right, foot + right + Vector3(0, h, 0), foot - right + Vector3(0, h, 0)]))
			uvs.append_array(PackedVector2Array([Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]))
			for k in 4:
				colors.append(c)
				normals.append(Vector3.UP)
			indices.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_INDEX] = indices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		# The wind pushes blades up to ~1 m out of their rest box.
		mesh.custom_aabb = mesh.get_aabb().grow(1.2)
		var mi := MeshInstance3D.new()
		mi.name = "Chunk_%d_%d" % [cell.x, cell.y]
		mi.mesh = mesh
		mi.material_override = mat
		mi.position = origin
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = range_end
		mi.set_meta(MeshMerger.SKIP_META, true)
		group.add_child(mi)
	return group


## Stable 0..1 seed from a position (tuft variety without another RNG stream).
static func randf_from(p: Vector3) -> float:
	return fposmod(sin(p.x * 12.9898 + p.z * 78.233) * 43758.5453, 1.0)
