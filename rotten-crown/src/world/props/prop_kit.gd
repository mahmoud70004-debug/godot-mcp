@tool
class_name PropKit
extends RefCounted
## Procedural dark-fantasy props built from primitive meshes (PartBuilder) with
## RetroMaterials (StandardMaterial3D only, so MeshMerger.merge_static works).
## Every builder returns a Node3D whose origin sits on the ground (y = 0) and
## takes an explicit RandomNumberGenerator so results are deterministic.
## Physics shapes are never placed under scaled nodes.

const ROW_HEIGHT := 0.24


# --------------------------------------------------------------------------
# Fences
# --------------------------------------------------------------------------
static func fence_run(points: PackedVector3Array, broken: float, rng: RandomNumberGenerator, collide := false) -> Node3D:
	var root := Node3D.new()
	root.name = "FenceRun"
	var wood := RetroMaterials.wood()
	var posts: Array[Vector3] = []
	for i in range(points.size() - 1):
		var n := maxi(1, roundi(points[i].distance_to(points[i + 1]) / 2.0))
		for k in n:
			posts.append(points[i].lerp(points[i + 1], float(k) / n))
	if points.size() > 0:
		posts.append(points[points.size() - 1])
	var body: StaticBody3D = _new_body(root) if collide else null
	var leans: Array[Basis] = []
	for p in posts:
		var pivot := PartBuilder.pivot(root, "Post", p)
		pivot.rotation = Vector3(rng.randf_range(-0.1, 0.1), rng.randf_range(0.0, TAU), rng.randf_range(-0.1, 0.1))
		PartBuilder.box(pivot, Vector3(0.14, 1.25, 0.14), Vector3(0, 0.6, 0), wood)
		leans.append(pivot.basis)
	for i in range(posts.size() - 1):
		for h in [0.55, 1.0]:
			var a: Vector3 = posts[i] + leans[i] * Vector3(0, h, 0)
			var b: Vector3 = posts[i + 1] + leans[i + 1] * Vector3(0, h, 0)
			if rng.randf() < broken:
				if rng.randf() < 0.5:
					continue
				b.y = maxf(0.1, b.y - rng.randf_range(0.4, 0.7))
			_beam(root, a, b, 0.07, 0.1, wood)
		if body != null:
			var d := posts[i + 1] - posts[i]
			var yaw := atan2(-d.z, d.x)
			var mid := (posts[i] + posts[i + 1]) * 0.5 + Vector3(0, 0.55, 0)
			_shape_box(body, Vector3(Vector2(d.x, d.z).length(), 1.1, 0.2), Transform3D(Basis(Vector3.UP, yaw), mid))
	return root


# --------------------------------------------------------------------------
# Trees
# --------------------------------------------------------------------------
static func dead_tree(height: float, rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	root.name = "DeadTree"
	var bark := RetroMaterials.bark()
	var r0 := clampf(height * 0.05, 0.3, 1.0)
	var trunk_h := height * 0.65
	var p := Vector3.ZERO
	var pts: Array[Vector3] = [p]
	var segs := 4
	for i in segs:
		var dir := (Vector3.UP + Vector3(rng.randf_range(-0.25, 0.25), 0, rng.randf_range(-0.25, 0.25))).normalized()
		var np := p + dir * (trunk_h / segs)
		var ra := r0 * lerpf(1.0, 0.55, float(i) / segs)
		var rb := r0 * lerpf(1.0, 0.55, float(i + 1) / segs)
		if i == 0:
			ra *= 1.25
		_limb(root, p - dir * 0.1, np, ra, rb, bark, 7)
		p = np
		pts.append(p)
	var big := 5
	for i in big:
		var at: Vector3 = pts[segs] if i < 2 else pts[segs - 1 - (i % 2)]
		var yaw := TAU * i / big + rng.randf_range(-0.4, 0.4)
		var dir := Vector3(cos(yaw), rng.randf_range(0.35, 0.9), sin(yaw)).normalized()
		_branch(root, at, dir, height * rng.randf_range(0.28, 0.4), r0 * 0.5, 3, rng, bark, 0.25)
	var body := _new_body(root)
	_shape_cyl(body, r0 * 0.8, trunk_h, Vector3(0, trunk_h * 0.5, 0))
	return root


static func gnarled_tree(height: float, lean: Vector3, rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	root.name = "GnarledTree"
	var bark := RetroMaterials.bark()
	var moss := RetroMaterials.moss()
	var l := Vector3(lean.x, 0, lean.z)
	l = l.normalized() if l.length() > 0.01 else Vector3.RIGHT
	var side := Vector3.UP.cross(l)
	var r0 := clampf(height * 0.075, 0.35, 1.2)
	var trunk_h := height * 0.62
	var segs := 8
	var p := Vector3.ZERO
	var pts: Array[Vector3] = [p]
	var r := r0 * 1.2
	# Serpentine trunk: a chain of bent, tapering segments that twist.
	var phase := rng.randf() * TAU
	var twist := rng.randf_range(1.0, 1.8)
	for i in segs:
		var t := float(i) / segs
		var sway := sin(phase + t * TAU * twist)
		var dir := (Vector3.UP * 1.1 + side * sway * 0.55 + l * (0.12 + t * 0.35) + side.cross(Vector3.UP) * cos(phase + t * TAU * twist) * 0.2).normalized()
		var np := p + dir * (trunk_h / segs)
		var nr := r0 * lerpf(1.0, 0.55, float(i + 1) / segs)
		_limb(root, p - dir * 0.12, np, r, nr, bark, 7)
		p = np
		r = nr
		pts.append(p)
	# Roots flaring at the base.
	var roots := 7
	for i in roots:
		var a := TAU * i / roots + rng.randf_range(-0.25, 0.25)
		var out := Vector3(cos(a), 0, sin(a))
		var s := Vector3(out.x * r0 * 0.3, r0 * 2.4, out.z * r0 * 0.3)
		var m := Vector3(out.x * r0 * 1.5, r0 * 0.9, out.z * r0 * 1.5)
		var e := Vector3(out.x * r0 * rng.randf_range(2.6, 3.8), -0.1, out.z * r0 * rng.randf_range(2.6, 3.8))
		_limb(root, s, m, r0 * 0.62, r0 * 0.4, bark, 6)
		_limb(root, m, e, r0 * 0.4, r0 * 0.1, bark, 5)
	# Thick limbs curving up, then arching over toward `lean`, ending in twigs.
	var limbs := rng.randi_range(2, 4)
	var seg_len := height * 0.095
	var moss_left := 7
	for i in limbs:
		var q: Vector3 = pts[rng.randi_range(maxi(segs - 4, 3), segs)]
		var dir := (l * 0.45 + Vector3.UP * 1.0 + side * rng.randf_range(-0.7, 0.7)).normalized()
		var lr := r0 * rng.randf_range(0.5, 0.65)
		var steps := 7
		for k in steps:
			var np := q + dir * seg_len
			var nr := lr * 0.82
			_limb(root, q - dir * 0.08, np, lr, nr, bark, 6)
			if moss_left > 0 and k >= 2 and rng.randf() < 0.45:
				moss_left -= 1
				var rad := height * rng.randf_range(0.03, 0.055)
				var blob := PartBuilder.sphere(root, rad, np + Vector3(rng.randf_range(-0.3, 0.3), rad * 0.3, rng.randf_range(-0.3, 0.3)), moss, false, 5)
				blob.scale = Vector3(1.4, 0.38, 1.2)
			if k >= steps - 3:
				for c in 2:
					var td := (dir + Vector3(rng.randf_range(-0.7, 0.7), rng.randf_range(-0.5, 0.3), rng.randf_range(-0.7, 0.7))).normalized()
					_limb(root, np, np + td * seg_len * rng.randf_range(0.8, 1.4), nr * 0.5, nr * 0.12, bark, 4)
			q = np
			lr = nr
			dir.y -= 0.28
			dir += l * 0.3 + side * rng.randf_range(-0.2, 0.2)
			dir = dir.normalized()
	var body := _new_body(root)
	_shape_cyl(body, r0 * 0.85, trunk_h, Vector3(0, trunk_h * 0.5, 0))
	return root


static func _branch(parent: Node3D, origin: Vector3, dir: Vector3, length: float, radius: float, depth: int, rng: RandomNumberGenerator, mat: Material, droop: float) -> void:
	var tip := origin + dir * length
	_limb(parent, origin, tip, radius, radius * 0.62, mat, 5)
	if depth <= 0:
		return
	var count := rng.randi_range(2, 3)
	for i in count:
		var axis := dir.cross(Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)))
		if axis.length() < 0.01:
			axis = Vector3.RIGHT
		var nd := dir.rotated(axis.normalized(), rng.randf_range(0.35, 0.95))
		nd.y = maxf(nd.y - droop * 0.3, -0.3)
		nd = nd.normalized()
		_branch(parent, tip - dir * length * 0.1, nd, length * rng.randf_range(0.62, 0.8), radius * 0.6, depth - 1, rng, mat, droop)


# --------------------------------------------------------------------------
# Pumpkin, scarecrow, signpost
# --------------------------------------------------------------------------
static func pumpkin(size: float, rng: RandomNumberGenerator, carved := false, flesh := false) -> Node3D:
	var root := Node3D.new()
	root.name = "Pumpkin"
	var mat := RetroMaterials.pumpkin()
	var dark := RetroMaterials.flat(Color(0.015, 0.01, 0.01))
	var cy := size * 0.38
	var core := PartBuilder.sphere(root, size * 0.42, Vector3(0, cy, 0), mat, false, 10)
	core.scale = Vector3(1, 0.82, 1)
	var lobes := rng.randi_range(6, 8)
	for i in lobes:
		var a := TAU * i / lobes + rng.randf_range(-0.05, 0.05)
		var lobe := PartBuilder.sphere(root, size * 0.3, Vector3(cos(a) * size * 0.26, cy, sin(a) * size * 0.26), mat, false, 8)
		lobe.scale = Vector3(0.9, 1.0, 0.9)
	# Curly stem.
	var stem := RetroMaterials.wood()
	var sp := Vector3(0, size * 0.66, 0)
	var sdir := Vector3.UP
	for i in 3:
		var np := sp + sdir * size * 0.12
		_limb(root, sp, np, size * 0.05, size * 0.04, stem, 5)
		sp = np
		sdir = (sdir + Vector3(0.6, 0.0, 0.2)).normalized()
	if carved:
		for sx in [-1.0, 1.0]:
			var eye := PartBuilder.cylinder(root, size * 0.09, size * 0.09, size * 0.14, Vector3(sx * size * 0.17, cy + size * 0.1, size * 0.53), dark, 3, Vector3(PI / 2, 0, 0))
			eye.rotation.z = PI if sx > 0.0 else 0.0
		for i in 5:
			var mx := (float(i) - 2.0) * size * 0.075
			var zig := size * 0.035 * (1.0 if i % 2 == 0 else -1.0)
			PartBuilder.box(root, Vector3(size * 0.07, size * 0.07, size * 0.14), Vector3(mx, cy - size * 0.14 + zig, size * 0.52), dark, Vector3(0, 0, PI / 4))
	if flesh:
		var skin := RetroMaterials.skin()
		var pc := Vector3(size * 0.14, size * 0.28, size * 0.34)
		var rad := size * 0.27
		var patch := PartBuilder.sphere(root, rad, pc, skin, false, 8)
		patch.scale = Vector3(1, 0.85, 1)
		var lip := RetroMaterials.flat(Color(0.3, 0.08, 0.08))
		var tooth := RetroMaterials.flat(Color(0.8, 0.76, 0.62))
		var tz := pc.z + sqrt(maxf(rad * rad - size * 0.0225, 0.0)) * 0.95
		PartBuilder.box(root, Vector3(size * 0.34, size * 0.045, size * 0.04), Vector3(pc.x, pc.y + size * 0.06, tz), lip)
		PartBuilder.box(root, Vector3(size * 0.34, size * 0.045, size * 0.04), Vector3(pc.x, pc.y - size * 0.06, tz), lip)
		for i in 6:
			var tx := (float(i) - 2.5) * size * 0.055
			var tzz := tz + size * 0.005
			PartBuilder.box(root, Vector3(size * 0.045, size * 0.08, size * 0.03), Vector3(pc.x + tx, pc.y, tzz), tooth)
	root.rotation.y = rng.randf_range(-0.4, 0.4)
	return root


static func scarecrow(rng: RandomNumberGenerator, human := false) -> Node3D:
	var root := Node3D.new()
	root.name = "Scarecrow"
	var wood := RetroMaterials.wood()
	var rag := RetroMaterials.rag()
	var straw := RetroMaterials.straw()
	var sack := RetroMaterials.sack()
	var dark := RetroMaterials.flat(Color(0.02, 0.015, 0.012))
	var rope := RetroMaterials.flat(Color(0.2, 0.15, 0.09))
	PartBuilder.box(root, Vector3(0.12, 2.3, 0.12), Vector3(0, 1.15, 0), wood)
	PartBuilder.box(root, Vector3(1.7, 0.1, 0.1), Vector3(0, 1.65, 0), wood, Vector3(0, 0, rng.randf_range(-0.06, 0.06)))
	root.rotation = Vector3(rng.randf_range(-0.05, 0.05), rng.randf_range(-0.5, 0.5), rng.randf_range(-0.1, 0.1))
	if not human:
		PartBuilder.box(root, Vector3(0.55, 0.85, 0.32), Vector3(0, 1.3, 0), rag)
		PartBuilder.box(root, Vector3(1.4, 0.22, 0.22), Vector3(0, 1.58, 0), rag)
		for sx in [-1.0, 1.0]:
			PartBuilder.box(root, Vector3(0.2, 0.22, 0.2), Vector3(sx * 0.78, 1.52, 0), straw, Vector3(0, 0, rng.randf_range(-0.5, 0.5)))
		for i in 4:
			PartBuilder.box(root, Vector3(0.16, 0.3, 0.16), Vector3((float(i) - 1.5) * 0.14, 0.82, rng.randf_range(-0.08, 0.08)), straw, Vector3(0, 0, rng.randf_range(-0.3, 0.3)))
		if rng.randf() < 0.5:
			var pk := pumpkin(0.5, rng, true)
			pk.position = Vector3(0, 1.67, 0)
			root.add_child(pk)
		else:
			PartBuilder.sphere(root, 0.24, Vector3(0, 1.95, 0), sack, false, 8)
			for sx in [-1.0, 1.0]:
				PartBuilder.box(root, Vector3(0.07, 0.07, 0.04), Vector3(sx * 0.09, 2.0, 0.22), dark, Vector3(0, 0, PI / 4))
			PartBuilder.box(root, Vector3(0.2, 0.03, 0.04), Vector3(0, 1.88, 0.22), dark)
	else:
		var skin := RetroMaterials.skin()
		var body := PartBuilder.pivot(root, "Body", Vector3(0, 0, 0.17))
		body.rotation.x = 0.1
		PartBuilder.box(body, Vector3(0.5, 0.8, 0.26), Vector3(0, 1.28, 0), rag)
		for sx in [-1.0, 1.0]:
			PartBuilder.box(body, Vector3(0.17, 0.75, 0.17), Vector3(sx * 0.12, 0.6, 0.02), rag, Vector3(rng.randf_range(-0.1, 0.1), 0, 0))
			PartBuilder.box(body, Vector3(0.11, 0.7, 0.11), Vector3(sx * 0.36, 1.22, 0.04), rag, Vector3(0, 0, sx * -0.12))
			PartBuilder.box(body, Vector3(0.1, 0.12, 0.1), Vector3(sx * 0.41, 0.82, 0.05), skin)
		PartBuilder.box(body, Vector3(0.58, 0.05, 0.34), Vector3(0, 1.05, 0), rope)
		PartBuilder.box(body, Vector3(0.3, 0.05, 0.34), Vector3(0, 0.3, 0.0), rope)
		var head := PartBuilder.pivot(body, "Head", Vector3(0.02, 1.8, 0.02))
		head.rotation = Vector3(0.3, 0, 0.35)
		PartBuilder.sphere(head, 0.22, Vector3(0, 0.12, 0), sack, false, 8)
		for sx in [-1.0, 1.0]:
			PartBuilder.box(head, Vector3(0.06, 0.06, 0.04), Vector3(sx * 0.08, 0.17, 0.2), dark, Vector3(0, 0, PI / 4))
		PartBuilder.box(head, Vector3(0.22, 0.025, 0.04), Vector3(0, 0.03, 0.2), dark)
		for i in 5:
			PartBuilder.box(head, Vector3(0.02, 0.07, 0.04), Vector3((float(i) - 2.0) * 0.045, 0.03, 0.205), rope)
	return root


static func signpost(labels: Array[String], rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	root.name = "Signpost"
	var wood := RetroMaterials.wood()
	var post_h := 1.8 + 0.4 * labels.size()
	PartBuilder.box(root, Vector3(0.14, post_h, 0.14), Vector3(0, post_h * 0.5, 0), wood)
	root.rotation = Vector3(0, 0, rng.randf_range(-0.04, 0.04))
	for i in labels.size():
		var dir := 1.0 if i % 2 == 0 else -1.0
		var pivot := PartBuilder.pivot(root, "Board%d" % i, Vector3(0, post_h - 0.3 - 0.4 * i, 0.09))
		pivot.rotation.y = rng.randf_range(-0.35, 0.35) + (0.0 if dir > 0.0 else PI * 0.0)
		var bx := dir * 0.5
		PartBuilder.box(pivot, Vector3(1.2, 0.3, 0.05), Vector3(bx, 0, 0), wood)
		PartBuilder.box(pivot, Vector3(0.21, 0.21, 0.05), Vector3(bx + dir * 0.6, 0, 0), wood, Vector3(0, 0, PI / 4))
		var label := Label3D.new()
		label.text = labels[i]
		label.font_size = 24
		label.pixel_size = 0.0065
		label.double_sided = true
		label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		label.shaded = false
		label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		label.modulate = Color(0.06, 0.04, 0.03)
		label.outline_size = 0
		label.position = Vector3(bx, 0, 0.03)
		pivot.add_child(label)
	return root


# --------------------------------------------------------------------------
# Cottage
# --------------------------------------------------------------------------
static func cottage(size: Vector3, rng: RandomNumberGenerator, ruined := false) -> Node3D:
	var root := Node3D.new()
	root.name = "Cottage"
	var w := size.x
	var wh := size.y
	var d := size.z
	var t := 0.25
	var board := RetroMaterials.clapboard()
	var core_mat := RetroMaterials.wood()
	var roof_mat := RetroMaterials.rust_roof() if rng.randf() < 0.5 else RetroMaterials.roof()
	var brick := RetroMaterials.brick()
	var door_w := 1.0
	var door_h := minf(1.9, wh - 0.3)
	var roof_h := w * 0.6
	var body := _new_body(root)
	var miss := 0.22 if ruined else 0.0
	# Wall cores (+ colliders). Front is split around the door gap.
	var front_len := (w - door_w) * 0.5
	for sx in [-1.0, 1.0]:
		var fc := Vector3(sx * (door_w * 0.5 + front_len * 0.5), wh * 0.5, d * 0.5)
		PartBuilder.box(root, Vector3(front_len, wh, t), fc, core_mat)
		_shape_box(body, Vector3(front_len, wh, t), Transform3D(Basis.IDENTITY, fc))
	var lintel := Vector3(0, (wh + door_h) * 0.5, d * 0.5)
	PartBuilder.box(root, Vector3(door_w, wh - door_h, t), lintel, core_mat)
	_shape_box(body, Vector3(door_w, wh - door_h, t), Transform3D(Basis.IDENTITY, lintel))
	PartBuilder.box(root, Vector3(w, wh, t), Vector3(0, wh * 0.5, -d * 0.5), core_mat)
	_shape_box(body, Vector3(w, wh, t), Transform3D(Basis.IDENTITY, Vector3(0, wh * 0.5, -d * 0.5)))
	for sx in [-1.0, 1.0]:
		PartBuilder.box(root, Vector3(t, wh, d), Vector3(sx * w * 0.5, wh * 0.5, 0), core_mat)
		_shape_box(body, Vector3(t, wh, d), Transform3D(Basis.IDENTITY, Vector3(sx * w * 0.5, wh * 0.5, 0)))
	# Clapboard outer layer.
	_planks(root, board, Vector3(-w * 0.5 + front_len * 0.5, 0, d * 0.5), Vector3.RIGHT, front_len, 0.0, wh, 0.05, t, rng, miss)
	_planks(root, board, Vector3(w * 0.5 - front_len * 0.5, 0, d * 0.5), Vector3.RIGHT, front_len, 0.0, wh, 0.05, t, rng, miss)
	_planks(root, board, Vector3(0, 0, d * 0.5), Vector3.RIGHT, door_w, door_h, wh, 0.05, t, rng, miss)
	_planks(root, board, Vector3(0, 0, -d * 0.5), Vector3.LEFT, w, 0.0, wh, 0.05, t, rng, miss)
	_planks(root, board, Vector3(-w * 0.5, 0, 0), Vector3.BACK, d, 0.0, wh, 0.05, t, rng, miss)
	_planks(root, board, Vector3(w * 0.5, 0, 0), Vector3.FORWARD, d, 0.0, wh, 0.05, t, rng, miss)
	# Gable triangles (solid rows narrowing to the ridge).
	var rows := int(roof_h / ROW_HEIGHT)
	for zs in [1.0, -1.0]:
		for i in rows:
			var y := wh + ROW_HEIGHT * (i + 0.5)
			var gw := w * (1.0 - (y - wh) / roof_h)
			if gw < 0.1 or (ruined and rng.randf() < 0.1):
				continue
			PartBuilder.box(root, Vector3(gw, ROW_HEIGHT * 0.95, t), Vector3(0, y, zs * d * 0.5), board if i % 2 == 0 else core_mat)
	# Door frame and floor.
	PartBuilder.box(root, Vector3(0.1, door_h, 0.3), Vector3(-door_w * 0.5, door_h * 0.5, d * 0.5), core_mat)
	PartBuilder.box(root, Vector3(0.1, door_h, 0.3), Vector3(door_w * 0.5, door_h * 0.5, d * 0.5), core_mat)
	PartBuilder.box(root, Vector3(w - 0.4, 0.05, d - 0.4), Vector3(0, 0.025, 0), core_mat)
	# Windows.
	_window(root, Vector3(0, wh * 0.55, d * 0.5 + t * 0.5 + 0.05), Vector3.RIGHT, ruined, rng, w * 0.3 if w >= 3.5 else 0.0)
	_window(root, Vector3(0, wh * 0.55, d * 0.5 + t * 0.5 + 0.05), Vector3.RIGHT, ruined, rng, -w * 0.3 if w >= 3.5 else 0.0)
	_window(root, Vector3(w * 0.5 + t * 0.5 + 0.05, wh * 0.55, 0), Vector3.FORWARD, ruined, rng, 0.0)
	_window(root, Vector3(-w * 0.5 - t * 0.5 - 0.05, wh * 0.55, 0), Vector3.BACK, ruined, rng, 0.0)
	# Roof.
	var ridge := Vector3(0, wh + roof_h + 0.05, 0)
	var drop := 0.35 * roof_h / (w * 0.5)
	var eave_r := Vector3(w * 0.5 + 0.35, wh - drop, 0)
	var eave_l := Vector3(-w * 0.5 - 0.35, wh - drop, 0)
	if not ruined:
		_beam(root, eave_r, ridge, 0.14, d + 0.7, roof_mat)
		_beam(root, eave_l, ridge, 0.14, d + 0.7, roof_mat)
	else:
		_beam(root, eave_l, eave_l.lerp(ridge, 0.65), 0.14, d + 0.7, roof_mat)
		_beam(root, Vector3(w * 0.5 + 0.1, wh - 0.1, 0), Vector3(w * 0.05, 0.7, 0), 0.14, d * 0.6, roof_mat)
		for i in 3:
			var a := eave_r.lerp(ridge, rng.randf_range(0.2, 0.8))
			a.z = rng.randf_range(-d * 0.4, d * 0.4)
			_beam(root, a, a + Vector3(rng.randf_range(-0.8, 0.2), rng.randf_range(0.5, 1.0), 0), 0.1, 0.1, core_mat)
	# Chimney.
	var ch_h := (wh + roof_h * (0.5 if ruined else 1.0)) + 0.6
	var ch_pos := Vector3(-w * 0.5 - 0.4, ch_h * 0.5, -d * 0.15)
	PartBuilder.box(root, Vector3(0.9, ch_h, 0.9), ch_pos, brick)
	_shape_box(body, Vector3(0.9, ch_h, 0.9), Transform3D(Basis.IDENTITY, ch_pos))
	PartBuilder.box(root, Vector3(1.1, 0.15, 1.1), Vector3(ch_pos.x, ch_h, ch_pos.z), brick)
	PartBuilder.box(root, Vector3(0.45, 0.05, 0.45), Vector3(ch_pos.x, ch_h + 0.08, ch_pos.z), RetroMaterials.flat(Color(0.01, 0.01, 0.01)))
	return root


## Horizontal clapboard rows along `axis` (horizontal unit) centred on `center`.
static func _planks(parent: Node3D, mat: Material, center: Vector3, axis: Vector3, length: float, y0: float, y1: float, th: float, wall_t: float, rng: RandomNumberGenerator, miss: float) -> void:
	var normal := axis.cross(Vector3.UP)
	var basis := Basis(axis, Vector3.UP, normal)
	var rows := maxi(1, int((y1 - y0) / ROW_HEIGHT))
	var rh := (y1 - y0) / rows
	for i in rows:
		var y := y0 + rh * (i + 0.5)
		var pieces := 2 if miss > 0.0 else 1
		for k in pieces:
			if miss > 0.0 and rng.randf() < miss:
				continue
			var plen := length / pieces
			var off := (k - (pieces - 1) * 0.5) * plen
			var out := wall_t * 0.5 + th * 0.5 + 0.02 * (i % 2)
			var pos := center + axis * off + normal * out
			pos.y = y
			var mi := PartBuilder.box(parent, Vector3(plen, rh * 0.94, th), Vector3.ZERO, mat)
			mi.transform = Transform3D(basis, pos)


static func _window(parent: Node3D, pos: Vector3, axis: Vector3, ruined: bool, rng: RandomNumberGenerator, along: float) -> void:
	if along == 0.0 and axis == Vector3.RIGHT:
		return
	var pivot := PartBuilder.pivot(parent, "Window", pos + axis * along)
	pivot.basis = Basis(axis, Vector3.UP, axis.cross(Vector3.UP))
	var wood := RetroMaterials.wood()
	PartBuilder.box(pivot, Vector3(0.6, 0.8, 0.04), Vector3.ZERO, RetroMaterials.flat(Color(0.015, 0.02, 0.03)))
	PartBuilder.box(pivot, Vector3(0.7, 0.07, 0.08), Vector3(0, 0.43, 0), wood)
	PartBuilder.box(pivot, Vector3(0.7, 0.07, 0.08), Vector3(0, -0.43, 0), wood)
	PartBuilder.box(pivot, Vector3(0.07, 0.9, 0.08), Vector3(-0.33, 0, 0), wood)
	PartBuilder.box(pivot, Vector3(0.07, 0.9, 0.08), Vector3(0.33, 0, 0), wood)
	PartBuilder.box(pivot, Vector3(0.05, 0.8, 0.06), Vector3.ZERO, wood)
	if ruined:
		for i in rng.randi_range(2, 3):
			PartBuilder.box(pivot, Vector3(0.95, 0.12, 0.05), Vector3(0, -0.25 + 0.25 * i, 0.07), wood, Vector3(0, 0, rng.randf_range(-0.5, 0.5)))


# --------------------------------------------------------------------------
# Chapel
# --------------------------------------------------------------------------
static func chapel(rng: RandomNumberGenerator, ruined := false) -> Node3D:
	var root := Node3D.new()
	root.name = "Chapel"
	var stone := RetroMaterials.stone()
	var roof := RetroMaterials.roof()
	var iron := RetroMaterials.iron()
	var wood := RetroMaterials.wood()
	var dark := RetroMaterials.flat(Color(0.012, 0.014, 0.025))
	var body := _new_body(root)
	var w := 5.0
	var wh := 4.2
	var nave_l := 9.0
	var roof_h := 2.8
	var t := 0.4
	for sx in [-1.0, 1.0]:
		var c := Vector3(sx * w * 0.5, wh * 0.5, 0)
		PartBuilder.box(root, Vector3(t, wh, nave_l), c, stone)
		_shape_box(body, Vector3(t, wh, nave_l), Transform3D(Basis.IDENTITY, c))
		for z in [-2.8, 0.0, 2.8]:
			PartBuilder.box(root, Vector3(0.1, 1.5, 0.5), Vector3(sx * (w * 0.5 + 0.2), 2.4, z), dark)
			PartBuilder.box(root, Vector3(0.1, 0.36, 0.36), Vector3(sx * (w * 0.5 + 0.2), 3.2, z), dark, Vector3(PI / 4, 0, 0))
			PartBuilder.box(root, Vector3(0.45, wh, 0.35), Vector3(sx * (w * 0.5 + 0.2), wh * 0.5, z + 1.4), stone)
	var back := Vector3(0, wh * 0.5, -nave_l * 0.5)
	PartBuilder.box(root, Vector3(w, wh, t), back, stone)
	_shape_box(body, Vector3(w, wh, t), Transform3D(Basis.IDENTITY, back))
	var rows := int(roof_h / ROW_HEIGHT)
	for i in rows:
		var y := wh + ROW_HEIGHT * (i + 0.5)
		var gw := w * (1.0 - (y - wh) / roof_h)
		PartBuilder.box(root, Vector3(gw, ROW_HEIGHT * 0.95, t), Vector3(0, y, -nave_l * 0.5), stone)
	var ridge := Vector3(0, wh + roof_h + 0.05, 0)
	var eave_r := Vector3(w * 0.5 + 0.4, wh - 0.4, 0)
	var eave_l := Vector3(-w * 0.5 - 0.4, wh - 0.4, 0)
	_beam(root, eave_l, ridge, 0.16, nave_l + 0.6, roof)
	if ruined:
		_beam(root, eave_r, eave_r.lerp(ridge, 0.5), 0.16, nave_l + 0.6, roof)
	else:
		_beam(root, eave_r, ridge, 0.16, nave_l + 0.6, roof)
	# Tower at the front (+Z), door facing +Z.
	var tz := nave_l * 0.5 + 0.9
	var tw := 3.0
	var th := 7.0
	var tc := Vector3(0, th * 0.5, tz)
	PartBuilder.box(root, Vector3(tw, th, tw), tc, stone)
	_shape_box(body, Vector3(tw, th, tw), Transform3D(Basis.IDENTITY, tc))
	PartBuilder.box(root, Vector3(1.3, 2.3, 0.1), Vector3(0, 1.15, tz + tw * 0.5 + 0.02), dark)
	PartBuilder.box(root, Vector3(0.9, 0.9, 0.1), Vector3(0, 2.4, tz + tw * 0.5 + 0.02), dark, Vector3(0, 0, PI / 4))
	PartBuilder.box(root, Vector3(0.1, 1.6, 0.5), Vector3(tw * 0.5 + 0.02, 4.5, tz), dark)
	PartBuilder.box(root, Vector3(0.1, 1.6, 0.5), Vector3(-tw * 0.5 - 0.02, 4.5, tz), dark)
	# Belfry.
	var by := th + 1.1
	PartBuilder.box(root, Vector3(tw - 0.9, 2.2, tw - 0.9), Vector3(0, by, tz), dark)
	for cx in [-1.0, 1.0]:
		for cz in [-1.0, 1.0]:
			PartBuilder.box(root, Vector3(0.45, 2.2, 0.45), Vector3(cx * (tw * 0.5 - 0.22), by, tz + cz * (tw * 0.5 - 0.22)), stone)
	PartBuilder.box(root, Vector3(tw + 0.2, 0.25, tw + 0.2), Vector3(0, th + 2.3, tz), stone)
	# Spire (4-sided pyramid), snapped when ruined.
	var sb := th + 2.4
	var sh := 6.5
	var sr := 1.9
	if not ruined:
		var cone := PartBuilder.cylinder(root, 0.02, sr, sh, Vector3(0, sb + sh * 0.5, tz), roof, 4)
		cone.rotation.y = PI / 4
		_cross(root, Vector3(0, sb + sh, tz), iron)
		PartBuilder.cylinder(root, 0.15, 0.4, 0.7, Vector3(0, by - 0.2, tz), iron, 8)
		PartBuilder.sphere(root, 0.1, Vector3(0, by - 0.6, tz), iron, false, 6)
	else:
		var cut := 0.35
		var lo_h := sh * cut
		var r_cut := sr * (1.0 - cut)
		var lower := PartBuilder.cylinder(root, r_cut, sr, lo_h, Vector3(0, sb + lo_h * 0.5, tz), roof, 4)
		lower.rotation.y = PI / 4
		var up_h := sh - lo_h
		var snap := PartBuilder.pivot(root, "SnappedSpire", Vector3(0.1, sb + lo_h, tz))
		snap.rotation = Vector3(0.15, 0, -0.55)
		var upper := PartBuilder.cylinder(snap, 0.02, r_cut, up_h, Vector3(0, up_h * 0.5, 0), roof, 4)
		upper.rotation.y = PI / 4
		_cross(snap, Vector3(0, up_h, 0), iron)
		# Fallen bell beside the tower.
		var bell := PartBuilder.pivot(root, "FallenBell", Vector3(tw * 0.5 + 1.4, 0.35, tz + 1.8))
		bell.rotation = Vector3(0.2, rng.randf_range(0, TAU), 1.35)
		PartBuilder.cylinder(bell, 0.15, 0.4, 0.7, Vector3.ZERO, iron, 8)
		PartBuilder.sphere(bell, 0.1, Vector3(0, -0.45, 0), iron, false, 6)
		PartBuilder.box(root, Vector3(0.4, 0.3, 0.3), Vector3(tw * 0.5 + 0.7, 0.15, tz + 0.6), stone, Vector3(0.2, 0.5, 0.1))
		PartBuilder.box(root, Vector3(0.5, 0.2, 0.3), Vector3(-tw * 0.5 - 0.8, 0.1, tz + 0.2), wood, Vector3(0, 0.3, 0.1))
	return root


static func _cross(parent: Node3D, pos: Vector3, mat: Material) -> void:
	PartBuilder.box(parent, Vector3(0.12, 1.0, 0.12), pos + Vector3(0, 0.5, 0), mat)
	PartBuilder.box(parent, Vector3(0.6, 0.12, 0.12), pos + Vector3(0, 0.7, 0), mat)


# --------------------------------------------------------------------------
# Cart wreck
# --------------------------------------------------------------------------
static func cart_wreck(rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	root.name = "CartWreck"
	var wood := RetroMaterials.wood()
	var iron := RetroMaterials.iron()
	var sack := RetroMaterials.sack()
	var straw := RetroMaterials.straw()
	var cart := PartBuilder.pivot(root, "Cart", Vector3(0, 0.62, 0))
	cart.rotation = Vector3(0, rng.randf_range(0, TAU), 2.6)
	PartBuilder.box(cart, Vector3(1.8, 0.1, 1.1), Vector3.ZERO, wood)
	for sz in [-1.0, 1.0]:
		PartBuilder.box(cart, Vector3(1.8, 0.4, 0.06), Vector3(0, 0.22, sz * 0.55), wood)
	PartBuilder.box(cart, Vector3(0.06, 0.4, 1.1), Vector3(-0.9, 0.22, 0), wood)
	for sz in [-1.0, 1.0]:
		PartBuilder.box(cart, Vector3(2.0, 0.07, 0.09), Vector3(1.8, 0.0, sz * 0.35), wood, Vector3(0, 0, 0.05))
	PartBuilder.cylinder(cart, 0.04, 0.04, 1.5, Vector3(-0.2, -0.2, 0), iron, 6, Vector3(PI / 2, 0, 0))
	_wheel(cart, 0.5, Vector3(-0.2, -0.2, 0.75), 8, wood, iron)
	var broken := PartBuilder.pivot(root, "BrokenWheel", Vector3(-1.6, 0.12, 1.4))
	broken.rotation = Vector3(0.1, 0.6, 0.0)
	_wheel(broken, 0.5, Vector3(0, 0.0, 0), 5, wood, iron)
	broken.rotation.x = -PI / 2 + 0.2
	broken.position.y = 0.06
	for i in 3:
		var sp := Vector3(rng.randf_range(1.0, 2.2), 0.2, rng.randf_range(-1.4, 1.2))
		var s := PartBuilder.sphere(root, 0.38, sp, sack, false, 6)
		s.scale = Vector3(1.0, 0.65, 0.8)
		s.rotation.y = rng.randf_range(0, TAU)
	for i in 5:
		var h := PartBuilder.sphere(root, rng.randf_range(0.2, 0.35), Vector3(rng.randf_range(1.2, 2.6), 0.05, rng.randf_range(-1.5, 0.8)), straw, true, 6)
		h.scale = Vector3(1.4, 0.5, 1.0)
	var body := _new_body(root)
	_shape_box(body, Vector3(1.9, 1.0, 1.2), Transform3D(cart.basis, Vector3(0, 0.5, 0)))
	return root


static func _wheel(parent: Node3D, r: float, pos: Vector3, spokes: int, wood: Material, iron: Material) -> void:
	var w := PartBuilder.pivot(parent, "Wheel", pos)
	var rim := TorusMesh.new()
	rim.inner_radius = r - 0.05
	rim.outer_radius = r
	rim.rings = 10
	rim.ring_segments = 4
	var mi := MeshInstance3D.new()
	mi.mesh = rim
	mi.material_override = iron
	mi.rotation.x = PI / 2
	w.add_child(mi)
	PartBuilder.cylinder(w, 0.09, 0.09, 0.14, Vector3.ZERO, wood, 6, Vector3(PI / 2, 0, 0))
	for i in spokes:
		var ang := PI * i / spokes * (2.0 if spokes < 8 else 1.0) * 0.5
		PartBuilder.box(w, Vector3(r * 2.0 - 0.06, 0.05, 0.05), Vector3.ZERO, wood, Vector3(0, 0, ang * 2.0 if spokes < 8 else ang))


# --------------------------------------------------------------------------
# Shared helpers
# --------------------------------------------------------------------------
## Cylinder from a to b (radius ra at a, rb at b).
static func _limb(parent: Node3D, a: Vector3, b: Vector3, ra: float, rb: float, mat: Material, segments: int = 6) -> MeshInstance3D:
	var v := b - a
	var len := maxf(v.length(), 0.01)
	var mi := PartBuilder.cylinder(parent, rb, ra, len, (a + b) * 0.5, mat, segments)
	mi.transform = Transform3D(Basis(Quaternion(Vector3.UP, v / len)), (a + b) * 0.5)
	return mi


## Box from a to b with cross-section (ty, tz); local Y stays roughly up.
static func _beam(parent: Node3D, a: Vector3, b: Vector3, ty: float, tz: float, mat: Material) -> MeshInstance3D:
	var v := b - a
	var len := maxf(v.length(), 0.01)
	var x := v / len
	var up := Vector3.UP if absf(x.y) < 0.95 else Vector3.RIGHT
	var z := x.cross(up).normalized()
	var y := z.cross(x)
	var mi := PartBuilder.box(parent, Vector3(len, ty, tz), (a + b) * 0.5, mat)
	mi.transform = Transform3D(Basis(x, y, z), (a + b) * 0.5)
	return mi


static func _new_body(parent: Node3D) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Collider"
	parent.add_child(body)
	return body


static func _shape_box(body: StaticBody3D, size: Vector3, xf: Transform3D) -> void:
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.transform = xf
	body.add_child(cs)


static func _shape_cyl(body: StaticBody3D, radius: float, height: float, pos: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	cs.shape = shape
	cs.position = pos
	body.add_child(cs)
