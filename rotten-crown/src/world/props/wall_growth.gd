class_name WallGrowth
extends RefCounted
## V16 - the wood takes the kingdom wall. Where the forest stands against the curtain wall the
## stone is no longer a bare sheet: woody creepers climb its inner face, leaf masses cling along
## them, the canopy spills over the wall walk and boughs droop back down with beard moss. On the
## south front the same growth pours over the parapet towards the plains, so the wall reads as
## something the forest is swallowing, from outside too.
##
## A few variants, built once in the wall's frame (x along the wall, y up from its foot, +z out
## of the face) and instanced along the runs like the trees: one MultiMeshInstance3D per
## (chunk, variant). Same atlas, bark and moonlight model as the trees (forest_growth.gdshader =
## forest_card without the tree LOD bands: ViewDistance culls the chunks at the fog line).
## Scenery only: no colliders (the wall has its own; the spill hangs above head height).

const SHADER := preload("res://assets/shaders/forest_growth.gdshader")
const VARIANTS := 4
const SEED := 48211
## What the growth covers: [height (m), width (m), creeper stand-off (m) from the stone]. The wall
## face is KingdomWalls.WALL_HEIGHT above the highest ground of its segment; the towers' shafts are
## 19-21 m. Variants are built to the kind's size, not squashed from the wall's. (The Outer Ward is
## left alone: its west, east and north walls stand 20 m clear of the wood and its front is a
## dressed face of buttresses and machicolations.)
const KINDS := {
	&"wall": [KingdomWalls.WALL_HEIGHT, 9.0, 0.42],
	&"tower": [19.0, 5.2, 0.42],
}
const SPACING := Vector2(7.0, 11.0)
const OUTER_SPACING := Vector2(13.0, 19.0)
## Sites are grouped in chunks this long (one draw per variant per chunk in view).
const CHUNK := 60.0
## No growth this close to a tower / corner / the gate (m along the wall).
const TOWER_PAD := 7.0
const GATE_PAD := 30.0
const STEM := Color(0.2, 0.2, 0.23)
const TINT := Color(0.82, 0.88, 1.0)

static var _meshes: Dictionary = {}
static var _material: ShaderMaterial


static func material() -> ShaderMaterial:
	if _material == null:
		_material = (ForestTrees.material("tree") as ShaderMaterial).duplicate() as ShaderMaterial
		_material.shader = SHADER
		_material.set_shader_parameter("lod_end", 10000.0)
	return _material


## One variant's mesh of a kind. `spill_only`: just the crown over the top and the drooping boughs
## (the outer face of the south front).
static func mesh(kind: StringName, variant: int, spill_only := false) -> ArrayMesh:
	var key := "%s/%d/%s" % [kind, variant, spill_only]
	if not _meshes.has(key):
		_meshes[key] = _build(kind, variant, spill_only)
	return _meshes[key]


static func _build(kind: StringName, variant: int, spill_only: bool) -> ArrayMesh:
	var size_of: Array = KINDS[kind]
	var height: float = size_of[0]
	var width: float = size_of[1]
	var proud: float = size_of[2]
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + variant * 977 + (31 if spill_only else 0) + int(height) * 13
	var bark := ForestTrees._acc()
	var leaves := ForestTrees._acc()
	var hangs := PackedVector3Array()
	var colour := func(_a: float, h: float, ny: float) -> Color:
		var moss := clampf(1.0 - h / 2.6, 0.0, 1.0) * 0.6 + clampf(ny, 0.0, 1.0) * 0.35
		return STEM.lerp(ForestTrees.MOSS, clampf(moss, 0.0, 0.85))
	var tile := "leaf_dark"
	if not spill_only:
		# Creepers: woody stems wandering up the face, thick and rooted at the foot.
		var stems := rng.randi_range(3, 5) if width > 6.0 else rng.randi_range(2, 3)
		for s in stems:
			var x := lerpf(-width * 0.42, width * 0.42, (s + rng.randf_range(0.15, 0.85)) / stems)
			var top := height * rng.randf_range(0.5, 1.0) if s > 0 else height + 0.5
			var pts := PackedVector3Array()
			var rads := PackedFloat32Array()
			var r0 := rng.randf_range(0.16, 0.26)
			var drift := rng.randf_range(-0.5, 0.5)
			var n := 9 + int(height / 8.0)
			pts.append(Vector3(x + rng.randf_range(-0.3, 0.3), -0.3, 0.75))
			rads.append(r0 * 1.5)
			for k in range(1, n + 1):
				var t := float(k) / n
				x += drift * 0.55 + rng.randf_range(-0.55, 0.55)
				x = clampf(x, -width * 0.5, width * 0.5)
				var y := top * t
				# Over the mossy foot (it stands 0.3 m proud up to 1.4 m), then flat on the stone.
				var z := proud if y < 1.5 else 0.1 + r0 * 0.5
				pts.append(Vector3(x, y, z))
				rads.append(lerpf(r0, 0.045, t))
				if y > 1.6:
					# A continuous mantle, not beads on a string: a full clump at every joint and
					# a lighter one between joints, overlapping, pressed against the stone.
					var size := rng.randf_range(1.7, 2.5) * (0.8 + 0.35 * t)
					ForestTrees._clump(leaves, Vector3(x + rng.randf_range(-0.5, 0.5), y, 0.15 + size * 0.14), size, tile, rng, true)
					var prev := pts[pts.size() - 2]
					var mid := (prev + pts[pts.size() - 1]) * 0.5
					var fill := rng.randf_range(1.5, 2.2)
					ForestTrees._clump(leaves, Vector3(mid.x + rng.randf_range(-0.9, 0.9), mid.y, 0.12 + fill * 0.1), fill, tile, rng, false)
			ForestTrees._tube(bark, pts, rads, 4, colour, Vector3.BACK)
		# A skirt of leaves where the creepers leave the ground.
		for k in 2:
			var size := rng.randf_range(1.3, 1.9)
			ForestTrees._clump(leaves, Vector3(rng.randf_range(-width * 0.4, width * 0.4), size * 0.3, 0.6), size, tile, rng, true)
	# The crown spilling over the wall walk.
	var crowns := rng.randi_range(3, 5)
	for k in crowns:
		var size := rng.randf_range(3.0, 4.4)
		var x := lerpf(-width * 0.45, width * 0.45, (k + rng.randf()) / crowns)
		ForestTrees._clump(leaves, Vector3(x, height + rng.randf_range(0.5, 1.6), rng.randf_range(0.1, 1.5)), size, tile, rng, true)
		hangs.append(Vector3(x + rng.randf_range(-1.0, 1.0), height + 0.2, rng.randf_range(0.45, 0.9)))
	# Boughs reaching in over the wall and drooping back down, heavy with leaves and moss.
	for k in rng.randi_range(1, 2):
		var x := rng.randf_range(-width * 0.35, width * 0.35)
		var reach := rng.randf_range(3.0, 5.2)
		var drop := rng.randf_range(1.8, 4.2)
		var side := rng.randf_range(-1.6, 1.6)
		var pts := PackedVector3Array()
		var rads := PackedFloat32Array()
		var n := 6
		for j in n + 1:
			var t := float(j) / n
			var p := Vector3(x + side * t, height + 0.9 + sin(t * PI * 0.8) * 1.1 - drop * t * t, -0.8 + (reach + 0.8) * t)
			pts.append(p)
			rads.append(lerpf(0.2, 0.05, t))
			if j >= 2:
				ForestTrees._clump(leaves, p + Vector3(rng.randf_range(-0.5, 0.5), 0.3, 0.0), rng.randf_range(2.0, 3.2), tile, rng, true)
				hangs.append(p - Vector3(0.0, 0.25, 0.0))
		ForestTrees._tube(bark, pts, rads, 4, colour, Vector3.UP)
	ForestTrees._append(bark, leaves)
	var uv2 := PackedVector2Array()
	uv2.resize((bark["v"] as PackedVector3Array).size())
	uv2.fill(Vector2.ZERO)
	var moss := ForestTrees._acc()
	for st: Array in ForestTrees._strands(moss, hangs, 40 + variant):
		for k in ForestTrees.STRAND_VERTS:
			uv2.append(Vector2(0.0, float(st[3])))
	ForestTrees._append(bark, moss)
	bark["uv2"] = uv2
	var out := ArrayMesh.new()
	ForestTrees._commit(out, bark, material())
	return out


## Lays the growth on the kingdom wall, the Outer Ward walls and the towers (after the forest is
## placed: it only grows where the wood stands against the stone). Returns the "WallGrowth" node.
static func build(root: Node3D, terrain: TerrainBuilder) -> Node3D:
	var node := Node3D.new()
	node.name = "WallGrowth"
	root.add_child(node)
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var w := KingdomWalls.WEST
	var e := KingdomWalls.EAST
	var s := KingdomWalls.SOUTH
	var n := KingdomWalls.NORTH
	var g := KingdomWalls.GAP
	# [from, to, face normal]: the same runs KingdomWalls builds (normal: towards the wood).
	var runs := [
		[Vector2(w, s), Vector2(-g, s), Vector2(0.0, 1.0)], [Vector2(g, s), Vector2(e, s), Vector2(0.0, 1.0)],
		[Vector2(w, s), Vector2(w, n), Vector2(1.0, 0.0)], [Vector2(e, s), Vector2(e, n), Vector2(-1.0, 0.0)],
		[Vector2(w, n), Vector2(e, n), Vector2(0.0, -1.0)],
	]
	var sites := 0
	for run: Array in runs:
		sites += _run(node, terrain, rng, run[0], run[1], run[2], &"wall", KingdomWalls.THICKNESS, 7.0, NAN, false)
		if is_equal_approx((run[0] as Vector2).y, s) and is_equal_approx((run[1] as Vector2).y, s):
			sites += _run(node, terrain, rng, run[0], run[1], -(run[2] as Vector2), &"wall", KingdomWalls.THICKNESS, 7.0, NAN, true)
	var wall_sites := sites
	sites += _towers(node, terrain, rng)
	print("WallGrowth: wall %d, towers %d" % [wall_sites, sites - wall_sites])
	print("WallGrowth: %d sites, %d chunk draws" % [sites, node.get_child_count()])
	return node


## Towers of the kingdom wall: growth up the face(s) turned to the wood. [centre, width, height, normals].
static func _towers(node: Node3D, terrain: TerrainBuilder, rng: RandomNumberGenerator) -> int:
	var list := []
	for z: float in KingdomWalls.TOWER_Z:
		list.append([Vector2(KingdomWalls.WEST, z), 6.2, 19.0, [Vector2(1.0, 0.0)]])
		list.append([Vector2(KingdomWalls.EAST, z), 6.2, 19.0, [Vector2(-1.0, 0.0)]])
	for x: float in [KingdomWalls.WEST, KingdomWalls.EAST]:
		var inward := Vector2(-signf(x), 0.0)
		list.append([Vector2(x, KingdomWalls.SOUTH), 7.0, 21.0, [inward, Vector2(0.0, 1.0)]])
		list.append([Vector2(x, KingdomWalls.NORTH), 7.0, 21.0, [inward, Vector2(0.0, -1.0)]])
	var chunks := {}
	var count := 0
	for t: Array in list:
		var c: Vector2 = t[0]
		for nrm: Vector2 in t[3]:
			var face := c + nrm * (float(t[1]) * 0.5 + 0.05)
			var look := c
			for q: Vector2 in t[3]:
				look += q * 9.0  # corners: diagonally into the kingdom
			if ForestBuilder.tier_at(look.x, look.y) < 1:
				continue
			var ground := terrain.height_at(face.x, face.y)
			var base := terrain.height_at(c.x, c.y)
			var wide := (float(t[1]) - 0.8) / float(KINDS[&"tower"][1])
			_site(chunks, &"tower", rng.randi() % VARIANTS, face, nrm, wide, base + float(t[2]), ground - 0.15, false)
			count += 1
	_flush(node, chunks, "T")
	return count


static func _run(node: Node3D, terrain: TerrainBuilder, rng: RandomNumberGenerator, a: Vector2, b: Vector2, normal: Vector2,
		kind: StringName, thick: float, probe: float, top_y: float, outer: bool) -> int:
	var height: float = KINDS[kind][0]
	var length := a.distance_to(b)
	var dir := (b - a) / length
	var segments := ceili(length / KingdomWalls.SEGMENT_LENGTH)
	var spacing := OUTER_SPACING if outer else SPACING
	var chunks := {}
	var count := 0
	var d := rng.randf_range(2.0, spacing.x)
	var pad := TOWER_PAD if kind == &"wall" else 3.0
	while d < length - pad:
		var at := d
		d += rng.randf_range(spacing.x, spacing.y)
		var variant := rng.randi() % VARIANTS
		var wide := rng.randf_range(0.9, 1.2)
		if at < pad or (kind == &"wall" and _near_tower(a + dir * at)):
			continue
		var p := a + dir * at
		# Only where the wood stands against the wall, not on the open gate court.
		# The wood on the wall's far side (the spill of the south front's outer face is fed from behind).
		var look := normal * probe * (-1.0 if outer else 1.0)
		if ForestBuilder.tier_at(p.x + look.x, p.y + look.y) < 1:
			continue
		if kind == &"wall" and absf(p.x) < GATE_PAD and is_equal_approx(p.y, KingdomWalls.SOUTH):
			continue
		var face := p + normal * (thick * 0.5)
		var foot := terrain.height_at(face.x, face.y) - 0.15
		var top := top_y
		if is_nan(top):
			var seg := clampi(int(at / length * segments), 0, segments - 1)
			top = KingdomWalls._ground_span(terrain, a.lerp(b, float(seg) / segments), a.lerp(b, float(seg + 1) / segments)).y + height
		_site(chunks, kind, variant, face, normal, wide, top, foot, outer)
		count += 1
	_flush(node, chunks, "%s%d" % ["O" if outer else "I", int(a.x + a.y * 3.0)])
	return count


## Queues one growth instance: `face` on the stone, `normal` out of it (towards the wood), scaled
## in width by `wide` and up to `top` from `foot`.
static func _site(chunks: Dictionary, kind: StringName, variant: int, face: Vector2, normal: Vector2, wide: float, top: float,
		foot: float, spill: bool) -> void:
	var tall := (top - foot) / float(KINDS[kind][0])
	# x along the face with x * up = normal (right-handed: the bark winding stays outward).
	var along := Vector3(normal.y, 0.0, -normal.x)
	var basis := Basis(along * wide, Vector3.UP * tall, Vector3(normal.x, 0.0, normal.y))
	var key := "%s/%d/%d" % [kind, int(face.x / CHUNK), int(face.y / CHUNK)]
	if not chunks.has(key):
		chunks[key] = {}
	var by: Dictionary = chunks[key]
	var vkey := "%d/%s" % [variant, spill]
	if not by.has(vkey):
		by[vkey] = [kind, variant, []]
	((by[vkey] as Array)[2] as Array).append(Transform3D(basis, Vector3(face.x, foot, face.y)))


static func _flush(node: Node3D, chunks: Dictionary, tag: String) -> void:
	for key: String in chunks:
		var by: Dictionary = chunks[key]
		for vkey: String in by:
			var entry: Array = by[vkey]
			var xforms: Array = entry[2]
			var sum := Vector3.ZERO
			for xf: Transform3D in xforms:
				sum += xf.origin
			var centre := sum / xforms.size()
			var spill := vkey.ends_with("true")
			node.add_child(_instances(mesh(entry[0], entry[1], spill), xforms, centre, entry[0], "%s_%s_%s" % [tag, key.replace("/", "_"), vkey.replace("/", "_")]))


static func _near_tower(p: Vector2) -> bool:
	if absf(p.x - KingdomWalls.WEST) < 1.0 or absf(p.x - KingdomWalls.EAST) < 1.0:
		for z: float in KingdomWalls.TOWER_Z:
			if absf(p.y - z) < TOWER_PAD:
				return true
		return minf(absf(p.y - KingdomWalls.SOUTH), absf(p.y - KingdomWalls.NORTH)) < TOWER_PAD + 2.0
	return minf(absf(p.x - KingdomWalls.WEST), absf(p.x - KingdomWalls.EAST)) < TOWER_PAD + 2.0


static func _instances(m: Mesh, xforms: Array, centre: Vector3, kind: StringName, id: String) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = m
	mm.instance_count = xforms.size()
	var height: float = KINDS[kind][0]
	var width: float = KINDS[kind][1]
	var half := Vector3(width, height, width)
	for i in xforms.size():
		var xf: Transform3D = xforms[i]
		xf.origin -= centre
		mm.set_instance_transform(i, xf)
		# Every moss strand shows (custom.y = moss amount 1), no rot glow.
		mm.set_instance_custom_data(i, Color(0.0, 1.0, 0.0, 0.0))
		mm.set_instance_color(i, TINT)
		half = half.max(xf.origin.abs() + Vector3(width, height * 1.6, width) * 1.3)
	mm.custom_aabb = AABB(-half, half * 2.0)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Growth_" + id
	mmi.multimesh = mm
	mmi.position = centre
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = KingdomWalls.WALL_RANGE
	return mmi
