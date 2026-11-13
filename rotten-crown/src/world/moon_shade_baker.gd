@tool
class_name MoonShadeBaker
extends RefCounted
## Offline canopy shade map (V7): where the moonlight reaches the ground through the
## trees, walls and buildings of the baked overworld. tools/bake_world.gd calls bake()
## on the freshly built world; the shaders sample the PNG by world XZ through the
## Moonlight node's `shade_map` / `shade_rect` globals, so it costs nothing at runtime
## and every quality level gets the same dappled light.
##
## Grayscale L8: 1.0 = full moonlight on the ground, 0.0 = full shade. Pixel (ix, iz)
## covers world x = RECT.x + ix / PX_PER_M, z = RECT.y + iz / PX_PER_M (row 0 = south).
##
## What casts, each projected along the moon direction onto the ground:
## - every forest tree once (Forest/Trees/N_*/Near_<Style>: one instance per tree): its
##   leaf clumps as soft ellipses (leaf gaps from a seeded noise), its bark (trunk streak,
##   bare limbs) thinner and lighter, and a contact disc at its foot;
## - every static collider of the scenery (walls, towers, gatehouses, houses, the keep):
##   taller than TALL, its oriented box as a hard-ish shadow polygon; lower (boulders,
##   logs, stumps, fences, wells), a soft contact patch round its footprint.
## Inside one caster the opacities take the maximum, between casters they multiply
## (dense groves go dark, glades and roads stay lit). Then a few box-blur passes.

## Keep in step with the Moonlight node in valdron_overworld.tscn (Euler YXZ; the light
## travels along -Z of that basis, +Z points at the moon).
const MOON_ROTATION := Vector3(-0.524, -2.634, 0.0)
## World rect (x0, z0, x1, z1) of the map; the Moonlight node's shade_rect default.
const RECT := Vector4(-260.0, 30.0, 260.0, 520.0)
const PX_PER_M := 2.0
const OUT_PATH := "res://assets/textures/world/moon_shade.png"
const SEED := 7177
## Opacity of one tree's leaf clumps (leaves let some moonlight through), of its bark,
## and of the contact darkening at its foot.
const CROWN_OPACITY := 0.5
const BARK_OPACITY := 0.4
const CONTACT_OPACITY := 0.6
## Contact disc radius at a trunk foot: CONTACT_BASE + CONTACT_TRUNK x trunk radius (m).
const CONTACT_BASE := 1.1
const CONTACT_TRUNK := 1.2
## Scenery colliders: taller than TALL (m) cast a shadow polygon of STRUCTURE_OPACITY;
## lower ones a contact patch of KIT_OPACITY reaching KIT_GROW m past their footprint.
const TALL := 2.5
const STRUCTURE_OPACITY := 0.82
const KIT_OPACITY := 0.55
const KIT_GROW := 0.7
## Leaf gaps: crown opacity x lerp(GAP_MIN, GAP_MAX, noise), clamped to 1.
const GAP_MIN := 0.1
const GAP_MAX := 1.4
const GAP_FREQUENCY := 0.09
## Bark voxels (m) for the trunk streak and the bare limbs.
const BARK_VOXEL := 1.0
## Smallest blob radius in pixels (a blob between pixel centres would vanish).
const MIN_RADIUS_PX := 0.8
const BLUR_RADIUS := 2
const BLUR_PASSES := 2
## Roads and trails stay readable: inside a path's clearance (ForestBuilder.road_lines)
## plus ROAD_EDGE m the canopy shade is raised to the power 1 - ROAD_OPEN (dapples keep
## their pattern, the darkest lift most), fading out over ROAD_FADE m beyond; walls and
## buildings still shade the roads.
const ROAD_OPEN := 0.75
const ROAD_EDGE := 0.5
const ROAD_FADE := 3.0
## Collider bodies that are not scenery: the ground, the invisible world edge, and the
## tree trunks (the trees cast their own shade above).
const SKIP_BODIES := [&"TerrainCollider", &"WorldEdge", &"Trunks"]

static var _blob_cache: Dictionary = {}


## Map size in pixels.
static func size() -> Vector2i:
	return Vector2i(roundi((RECT.z - RECT.x) * PX_PER_M), roundi((RECT.w - RECT.y) * PX_PER_M))


## Unit vector from the ground towards the moon.
static func moon_dir() -> Vector3:
	return Basis.from_euler(MOON_ROTATION).z.normalized()


## Rasterises the shade of everything under `root` (the built overworld, inside the
## scene tree so global transforms hold, with a real RenderingServer so MultiMesh
## instance data can be read) and saves it to `path`. `terrain` (OverworldBuilder.build's
## result) gives the ground under buildings sunk into slopes; without it their lowest
## corner is used. Returns statistics.
static func bake(root: Node3D, terrain: TerrainBuilder = null, path := OUT_PATH) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var dim := size()
	var shade := PackedFloat32Array()
	shade.resize(dim.x * dim.y)
	shade.fill(1.0)
	var noise := FastNoiseLite.new()
	noise.seed = SEED
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = GAP_FREQUENCY
	noise.fractal_octaves = 2
	var gaps := noise.get_image(dim.x, dim.y).get_data()
	var trees := _trees(root)
	for t: Array in trees:
		_stamp_tree(shade, dim, gaps, t[0] as Transform3D, int(t[1]))
	_open_roads(shade, dim)
	var solid := PackedFloat32Array()
	solid.resize(dim.x * dim.y)
	solid.fill(0.0)
	var counts := _structures(root, solid, dim, terrain)
	for i in shade.size():
		shade[i] *= 1.0 - solid[i]
	for k in BLUR_PASSES:
		_blur(shade, dim, BLUR_RADIUS)
	var bytes := PackedByteArray()
	bytes.resize(shade.size())
	var total := 0.0
	var dark := 0
	for i in shade.size():
		var v := clampf(shade[i], 0.0, 1.0)
		total += v
		if v < 0.5:
			dark += 1
		bytes[i] = int(v * 255.0 + 0.5)
	var img := Image.create_from_data(dim.x, dim.y, false, Image.FORMAT_L8, bytes)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var err := img.save_png(path)
	var stats := {"trees": trees.size(), "structures": counts.x, "kits": counts.y, "size": dim,
		"mean": total / shade.size(), "dark_share": float(dark) / shade.size(), "ms": Time.get_ticks_msec() - t0, "error": err}
	print("MoonShadeBaker: %s %s | %d trees, %d structures, %d kits | mean %.3f, %.1f%% below 0.5 | %d ms" % [
		path, error_string(err), trees.size(), counts.x, counts.y, stats["mean"], float(stats["dark_share"]) * 100.0, stats["ms"]])
	return stats


# --- Casters -------------------------------------------------------------------------

## [global Transform3D, style] of every tree, read from the near MultiMeshes (each tree
## is in exactly one N_ cell; the impostor grid repeats them).
static func _trees(root: Node3D) -> Array:
	var out: Array = []
	var group := root.get_node_or_null("Forest/Trees")
	if group == null:
		push_warning("MoonShadeBaker: no Forest/Trees, no canopy shade")
		return out
	for cell in group.get_children():
		if not String(cell.name).begins_with("N_"):
			continue
		for child in cell.get_children():
			var mmi := child as MultiMeshInstance3D
			if mmi == null or mmi.multimesh == null or not String(mmi.name).begins_with("Near_"):
				continue
			var style := ForestTrees.NAMES.find(String(mmi.name).substr(5))
			if style < 0:
				continue
			var mm := mmi.multimesh
			var base := mmi.global_transform
			for i in mm.instance_count:
				out.append([base * mm.get_instance_transform(i), style])
	var degenerate := 0
	for t: Array in out:
		if (t[0] as Transform3D).basis.x.length_squared() < 1e-6:
			degenerate += 1
	if degenerate > 0:
		push_error("MoonShadeBaker: %d tree transforms are empty (headless RenderingServer?)" % degenerate)
	return out


## A style's shade casters in the tree frame: [centre Vector3, radius m, opacity, leafy].
## Leaf clumps from the near mesh's leaf quads (merged where they overlap), bark from
## its tube vertices in BARK_VOXEL cells; the baked moss strands are left out.
static func _blobs(style: int) -> Array:
	if _blob_cache.has(style):
		return _blob_cache[style]
	var mesh := ForestTrees.tree(style, 0)["mesh"] as ArrayMesh
	var clumps: Array = []
	var cells := {}
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
		var uv2 := PackedVector2Array()
		if arr[Mesh.ARRAY_TEX_UV2] is PackedVector2Array:
			uv2 = arr[Mesh.ARRAY_TEX_UV2]
		var i := 0
		while i < v.size():
			if not uv2.is_empty() and uv2[i].y > 0.0:
				i += 1
				continue  # moss strand
			if uv[i].x < -0.5:
				if v[i].y > 0.4:
					var key := Vector3i((v[i] / BARK_VOXEL).floor())
					if not cells.has(key):
						cells[key] = [Vector3.ZERO, 0]
					var c: Array = cells[key]
					c[0] = (c[0] as Vector3) + v[i]
					c[1] = int(c[1]) + 1
				i += 1
				continue
			# Leaf quad: four consecutive leaf vertices.
			if i + 3 >= v.size():
				break
			var centre := (v[i] + v[i + 1] + v[i + 2] + v[i + 3]) * 0.25
			var half := maxf(v[i].distance_to(v[i + 1]), v[i + 1].distance_to(v[i + 2])) * 0.5
			_merge_clump(clumps, centre, half * 0.85)
			i += 4
	var out: Array = []
	for c: Array in clumps:
		out.append([c[0], c[1], CROWN_OPACITY, true])
	var keys := cells.keys()
	keys.sort()
	for key: Vector3i in keys:
		var c: Array = cells[key]
		out.append([(c[0] as Vector3) / float(c[1]), BARK_VOXEL * 0.45, BARK_OPACITY, false])
	_blob_cache[style] = out
	return out


## Adds a leaf quad (centre, radius) to the clump it overlaps most, else starts one.
static func _merge_clump(clumps: Array, centre: Vector3, radius: float) -> void:
	for c: Array in clumps:
		var at: Vector3 = c[0]
		var r: float = c[1]
		var d := at.distance_to(centre)
		if d < maxf(r, radius) * 0.8:
			var n := int(c[2])
			c[0] = (at * n + centre) / (n + 1)
			c[1] = maxf(r, d + radius * 0.9)
			c[2] = n + 1
			return
	clumps.append([centre, radius, 1])


## One tree: every blob projected along the moon onto the plane of the tree's foot, the
## opacities joined by maximum in a local window, then multiplied into `shade`.
static func _stamp_tree(shade: PackedFloat32Array, dim: Vector2i, gaps: PackedByteArray, xf: Transform3D, style: int) -> void:
	var moon := moon_dir()
	var foot := xf.origin
	var scale := xf.basis.x.length()
	# [x px, z px, radius px, opacity, leafy] after projection.
	var proj: Array = []
	var stretch := 1.0 / maxf(moon.y, 0.1)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for b: Array in _blobs(style):
		var w: Vector3 = xf * (b[0] as Vector3)
		var g := w - moon * ((w.y - foot.y) / moon.y)
		var p := _to_px(g.x, g.z)
		var r := maxf(float(b[1]) * scale * PX_PER_M, MIN_RADIUS_PX)
		proj.append([p.x, p.y, r, b[2], b[3]])
		var reach := r * stretch
		lo = lo.min(p - Vector2(reach, reach))
		hi = hi.max(p + Vector2(reach, reach))
	var fp := _to_px(foot.x, foot.z)
	var cr := (CONTACT_BASE + CONTACT_TRUNK * ForestTrees.radius(style) * scale) * PX_PER_M
	proj.append([fp.x, fp.y, cr, CONTACT_OPACITY, false, true])
	lo = lo.min(fp - Vector2(cr, cr))
	hi = hi.max(fp + Vector2(cr, cr))
	var x0 := maxi(floori(lo.x), 0)
	var z0 := maxi(floori(lo.y), 0)
	var x1 := mini(ceili(hi.x), dim.x - 1)
	var z1 := mini(ceili(hi.y), dim.y - 1)
	if x1 < x0 or z1 < z0:
		return
	var lw := x1 - x0 + 1
	var local := PackedFloat32Array()
	local.resize(lw * (z1 - z0 + 1))
	local.fill(0.0)
	# Shadow direction on the ground (away from the moon) for the ellipses.
	var d2 := Vector2(-moon.x, -moon.z).normalized()
	for b: Array in proj:
		var contact := b.size() > 5
		_ellipse(local, lw, x0, z0, x1, z1, b, d2, 1.0 if contact else stretch, contact, gaps, dim.x)
	var k := 0
	for z in range(z0, z1 + 1):
		var row := z * dim.x
		for x in range(x0, x1 + 1):
			var a := local[k]
			k += 1
			if a > 0.0:
				shade[row + x] *= 1.0 - a


## One blob into the local window (max): an ellipse `stretch` times longer along the
## shadow direction `d2` (a sphere's shadow at the moon's elevation), solid core with a
## soft rim; contact discs fade all the way out; leafy blobs take the leaf-gap noise.
static func _ellipse(local: PackedFloat32Array, lw: int, x0: int, z0: int, x1: int, z1: int, b: Array, d2: Vector2,
		stretch: float, contact: bool, gaps: PackedByteArray, map_w: int) -> void:
	var cx: float = b[0]
	var cz: float = b[1]
	var r: float = b[2]
	var opacity: float = b[3]
	var leafy: bool = b[4]
	var ra := r * stretch
	var inv_a := 1.0 / ra
	var inv_b := 1.0 / r
	var dx := d2.x
	var dz := d2.y
	var bx0 := maxi(floori(cx - ra), x0)
	var bx1 := mini(ceili(cx + ra), x1)
	var bz0 := maxi(floori(cz - ra), z0)
	var bz1 := mini(ceili(cz + ra), z1)
	for z in range(bz0, bz1 + 1):
		var oz := z + 0.5 - cz
		var lrow := (z - z0) * lw - x0
		var grow := z * map_w
		for x in range(bx0, bx1 + 1):
			var ox := x + 0.5 - cx
			var u := (ox * dx + oz * dz) * inv_a
			var v := (oz * dx - ox * dz) * inv_b
			var q := u * u + v * v
			if q >= 1.0:
				continue
			var a: float
			if contact:
				a = opacity * (1.0 - q) * (1.0 - q)
			else:
				a = opacity * minf((1.0 - q) * 3.0, 1.0)
				if leafy:
					a = minf(a * lerpf(GAP_MIN, GAP_MAX, gaps[grow + x] / 255.0), 1.0)
			if a > local[lrow + x]:
				local[lrow + x] = a


## Static scenery colliders into `solid` (max): tall ones as their moon shadow polygon,
## low ones as a soft patch round their footprint. Returns (structures, kits).
static func _structures(root: Node3D, solid: PackedFloat32Array, dim: Vector2i, terrain: TerrainBuilder) -> Vector2i:
	var moon := moon_dir()
	var counts := Vector2i.ZERO
	for node in root.find_children("*", "CollisionShape3D", true, false):
		var cs := node as CollisionShape3D
		if cs.disabled or cs.shape == null or cs.shape is HeightMapShape3D or cs.shape is WorldBoundaryShape3D:
			continue
		var body := cs.get_parent()
		if not (body is StaticBody3D) or body.name in SKIP_BODIES:
			continue
		var box := cs.shape.get_debug_mesh().get_aabb()
		var xf := cs.global_transform
		var corners := PackedVector3Array()
		var bottom := INF
		var top := -INF
		for k in 8:
			var c := xf * box.get_endpoint(k)
			corners.append(c)
			bottom = minf(bottom, c.y)
			top = maxf(top, c.y)
		var ground := bottom
		if terrain:
			var mid := xf * box.get_center()
			ground = clampf(terrain.height_at(mid.x, mid.z), bottom, top)
		if top - ground > TALL:
			var pts := PackedVector2Array()
			for c in corners:
				var g := c - moon * (maxf(c.y - ground, 0.0) / moon.y)
				pts.append(_to_px(g.x, g.z))
			_polygon(solid, dim, Geometry2D.convex_hull(pts), STRUCTURE_OPACITY)
			counts.x += 1
		else:
			_patch(solid, dim, xf, box)
			counts.y += 1
	return counts


## Convex polygon (pixel space) into `solid` at `opacity` (max).
static func _polygon(solid: PackedFloat32Array, dim: Vector2i, hull: PackedVector2Array, opacity: float) -> void:
	if hull.size() < 3:
		return
	var lo := hull[0]
	var hi := hull[0]
	for p in hull:
		lo = lo.min(p)
		hi = hi.max(p)
	var x0 := maxi(floori(lo.x), 0)
	var z0 := maxi(floori(lo.y), 0)
	var x1 := mini(ceili(hi.x), dim.x - 1)
	var z1 := mini(ceili(hi.y), dim.y - 1)
	for z in range(z0, z1 + 1):
		var row := z * dim.x
		for x in range(x0, x1 + 1):
			if solid[row + x] < opacity and Geometry2D.is_point_in_polygon(Vector2(x + 0.5, z + 0.5), hull):
				solid[row + x] = opacity


## Soft contact patch round a low collider: discs along the long side of its footprint
## (a log is a row of them), KIT_GROW m wider than the footprint.
static func _patch(solid: PackedFloat32Array, dim: Vector2i, xf: Transform3D, box: AABB) -> void:
	var centre := xf * box.get_center()
	var ax := xf.basis.x * box.size.x * 0.5
	var az := xf.basis.z * box.size.z * 0.5
	var half_x := Vector2(ax.x, ax.z).length()
	var half_z := Vector2(az.x, az.z).length()
	var along := Vector2(ax.x, ax.z) if half_x >= half_z else Vector2(az.x, az.z)
	var long := maxf(half_x, half_z)
	var short := minf(half_x, half_z)
	var r := (short + KIT_GROW) * PX_PER_M
	var n := maxi(ceili(long / maxf(short, 0.25)), 1)
	for k in n:
		var t := 0.0 if n == 1 else lerpf(-1.0, 1.0, float(k) / (n - 1)) * (long - short)
		var at := Vector2(centre.x, centre.z) + along.normalized() * t
		var p := _to_px(at.x, at.y)
		var x0 := maxi(floori(p.x - r), 0)
		var z0 := maxi(floori(p.y - r), 0)
		var x1 := mini(ceili(p.x + r), dim.x - 1)
		var z1 := mini(ceili(p.y + r), dim.y - 1)
		for z in range(z0, z1 + 1):
			var row := z * dim.x
			var oz := z + 0.5 - p.y
			for x in range(x0, x1 + 1):
				var ox := x + 0.5 - p.x
				var q := (ox * ox + oz * oz) / (r * r)
				if q >= 1.0:
					continue
				var a := KIT_OPACITY * minf((1.0 - q) * 1.6, 1.0)
				if a > solid[row + x]:
					solid[row + x] = a


## Lifts the canopy shade over every road and trail (see ROAD_OPEN): a capsule per
## segment, the strongest lift kept, then shade = shade ^ (1 - ROAD_OPEN x lift).
static func _open_roads(shade: PackedFloat32Array, dim: Vector2i) -> void:
	var lift := PackedFloat32Array()
	lift.resize(dim.x * dim.y)
	lift.fill(0.0)
	for line: Array in ForestBuilder.road_lines():
		var pts: Array = line[0]
		var inner := (float(line[1]) + ROAD_EDGE) * PX_PER_M
		var outer := inner + ROAD_FADE * PX_PER_M
		for k in pts.size() - 1:
			var a := _to_px(float(pts[k][0]), float(pts[k][1]))
			var b := _to_px(float(pts[k + 1][0]), float(pts[k + 1][1]))
			var ab := b - a
			var len_sq := maxf(ab.length_squared(), 1e-6)
			var x0 := maxi(floori(minf(a.x, b.x) - outer), 0)
			var z0 := maxi(floori(minf(a.y, b.y) - outer), 0)
			var x1 := mini(ceili(maxf(a.x, b.x) + outer), dim.x - 1)
			var z1 := mini(ceili(maxf(a.y, b.y) + outer), dim.y - 1)
			for z in range(z0, z1 + 1):
				var row := z * dim.x
				for x in range(x0, x1 + 1):
					var q := Vector2(x + 0.5, z + 0.5)
					var t := clampf((q - a).dot(ab) / len_sq, 0.0, 1.0)
					var d := q.distance_to(a + ab * t)
					if d >= outer:
						continue
					var f := 1.0 - smoothstep(inner, outer, d)
					if f > lift[row + x]:
						lift[row + x] = f
	for i in shade.size():
		var f := lift[i]
		if f > 0.0:
			shade[i] = pow(maxf(shade[i], 0.0), 1.0 - ROAD_OPEN * f)


# --- Helpers ---------------------------------------------------------------------------

static func _to_px(x: float, z: float) -> Vector2:
	return Vector2((x - RECT.x) * PX_PER_M, (z - RECT.y) * PX_PER_M)


## Separable box blur (running sums, edges clamped) in place.
static func _blur(data: PackedFloat32Array, dim: Vector2i, radius: int) -> void:
	var tmp := PackedFloat32Array()
	tmp.resize(data.size())
	var inv := 1.0 / (radius * 2 + 1)
	var w := dim.x
	var h := dim.y
	for z in h:
		var row := z * w
		var acc := 0.0
		for k in range(-radius, radius + 1):
			acc += data[row + clampi(k, 0, w - 1)]
		for x in w:
			tmp[row + x] = acc * inv
			acc += data[row + mini(x + radius + 1, w - 1)] - data[row + maxi(x - radius, 0)]
	for x in w:
		var acc := 0.0
		for k in range(-radius, radius + 1):
			acc += tmp[clampi(k, 0, h - 1) * w + x]
		for z in h:
			data[z * w + x] = acc * inv
			acc += tmp[mini(z + radius + 1, h - 1) * w + x] - tmp[maxi(z - radius, 0) * w + x]
