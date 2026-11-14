@tool
class_name KingdomRoads
extends RefCounted
## Dressing of the built roads (Phase 4a inc 4). Output: Node3D "Roads" (merged by the
## caller with the rest of the Plains) and its lantern lights.
##  - The King's Road (OverworldSpec.KINGS_ROAD, kingdom gate -> citadel gate): a paved
##    royal road, flagstone plates laid on the carved terrain road, low kerb stones along
##    both edges, a crowned waymarker every MARKER_STEP m on the right-hand side going in,
##    and LANTERNS posts (warm at the fork inside the gate and before the citadel, one
##    cursed green half-way). Wider and more built than the painted forest trails, so the
##    way to the citadel reads from the gate. paint() widens it on the terrain paint.
##  - The pumpkin road (MAIN_ROAD, also the dirt road from the wake-up spot to the gate):
##    worn wheel ruts, puddles and edge stones (formerly MeadowBuilder).
## Own random stream (SEED), so other builders' layouts do not move when this changes.

const SEED := 4242
## Paved half width, kerb offset from the centreline and kerb spacing (metres).
const PAVE_HALF := 1.8
const PAVE_STEP := 2.0
const KERB_OFFSET := 2.3
const KERB_STEP := 1.6
## Painted (terrain R) half width of the King's Road, wider than the 1.5 m of MAIN_ROAD.
const PAINT_HALF := 2.9
const MARKER_STEP := 27.0
const MARKER_FIRST := 14.0
## [distance along the road, side (-1 left, +1 right going in), colour key].
## (The first two stand clear of the gatehouse: the wall is on the left just inside the gate.)
const LANTERNS := [[10.0, 1.0, "warm"], [16.0, -1.0, "warm"], [82.0, -1.0, "cursed"], [178.0, -1.0, "warm"],
	[178.0, 1.0, "warm"]]
const WARM := Color(1.0, 0.6, 0.3)
const CURSED := Color(0.55, 1.0, 0.3)
const DETAIL_RANGE := 70.0


## Widens the King's Road on the terrain paint (R) and clears the forest floor (B) under
## it, so it reads as one broad worn road. Call before terrain.build().
static func paint(terrain: TerrainBuilder) -> void:
	var spec := terrain.spec
	var reach := PAINT_HALF + 1.0
	for iz in terrain.rows:
		var z := spec.min_corner.y + iz * spec.cell
		if z < 50.0 or z > 210.0:
			continue
		for ix in terrain.cols:
			var x := spec.min_corner.x + ix * spec.cell
			if x < -10.0 or x > 150.0:
				continue
			var d := _poly_dist(Vector2(x, z), OverworldSpec.KINGS_ROAD)
			if d > reach:
				continue
			var i := iz * terrain.cols + ix
			var c := terrain.paint[i]
			var w := 1.0 - smoothstep(PAINT_HALF - 0.8, PAINT_HALF, d)
			c.r = maxf(c.r, w)
			c.b = minf(c.b, 1.0 - w)
			c.g = minf(c.g, 1.0 - w)
			terrain.paint[i] = c


static func build(parent: Node3D, terrain: TerrainBuilder) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var roads := Node3D.new()
	roads.name = "Roads"
	parent.add_child(roads)
	var details := Node3D.new()
	details.name = "Details"
	roads.add_child(details)
	_pave(roads, terrain)
	_kerbs(roads, terrain, rng)
	_markers(roads, terrain, rng)
	_lanterns(roads, terrain)
	_ruts(details, terrain, rng)
	MeshMerger.merge_static(details, MeshMerger.cell_for(DETAIL_RANGE), DETAIL_RANGE)
	for node in details.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.visible:
			mi.set_meta(MeshMerger.SKIP_META, true)
	return roads


# --- King's Road -------------------------------------------------------------------

## Polyline the paving follows: the map road plus a last step through the citadel gate.
static func pave_line() -> Array:
	var pts := OverworldSpec.KINGS_ROAD.duplicate()
	pts.append(OverworldSpec.WARD_GATE + Vector2(0.0, 3.0))
	return pts


## Flagstone plates every PAVE_STEP m; each sits on the highest ground under it (its sides
## reach below the lowest), so the terrain never pokes through and no edge floats.
static func _pave(parent: Node3D, terrain: TerrainBuilder) -> void:
	var group := Node3D.new()
	group.name = "Paving"
	parent.add_child(group)
	var cobble := RetroMaterials.cobble()
	var line := pave_line()
	var total := _length(line)
	var s := 0.0
	while s < total - 0.1:
		var s1 := minf(s + PAVE_STEP, total)
		var a := _at(line, s)
		var b := _at(line, s1)
		var dir := (b - a).normalized()
		var nrm := Vector2(-dir.y, dir.x)
		var hi := -INF
		var lo := INF
		for t: float in [0.0, 0.5, 1.0]:
			for k: float in [-1.0, 0.0, 1.0]:
				var q := a.lerp(b, t) + nrm * k * PAVE_HALF
				var h := terrain.height_at(q.x, q.y)
				hi = maxf(hi, h)
				lo = minf(lo, h)
		var top := hi + 0.04
		var depth := top - lo + 0.12
		var mid := (a + b) * 0.5
		var plate := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(PAVE_HALF * 2.0, depth, a.distance_to(b) + 0.06)
		plate.mesh = mesh
		plate.material_override = cobble
		plate.position = Vector3(mid.x, top - depth * 0.5, mid.y)
		plate.rotation.y = atan2(dir.x, dir.y)
		plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		group.add_child(plate)
		s = s1


## Low kerb stones on both edges (gaps here and there), left out where the road meets the
## pumpkin road at the fork, in the gate passage and at the citadel gate.
static func _kerbs(parent: Node3D, terrain: TerrainBuilder, rng: RandomNumberGenerator) -> void:
	var group := Node3D.new()
	group.name = "Kerbs"
	parent.add_child(group)
	var stone := MeadowProps.lichen_stone()
	var line := pave_line()
	var total := _length(line)
	var s := 1.0
	while s < total:
		var p := _at(line, s)
		var dir := (_at(line, minf(s + 0.5, total)) - _at(line, maxf(s - 0.5, 0.0))).normalized()
		var nrm := Vector2(-dir.y, dir.x)
		for side: float in [-1.0, 1.0]:
			if rng.randf() < 0.08:
				continue
			var q := p + nrm * side * (KERB_OFFSET + rng.randf_range(-0.06, 0.06))
			if _kerb_skip(q):
				continue
			var size := Vector3(0.42, rng.randf_range(0.2, 0.3), rng.randf_range(0.7, 1.0))
			var kerb := MeshInstance3D.new()
			var mesh := BoxMesh.new()
			mesh.size = size + Vector3(0.0, 0.25, 0.0)
			kerb.mesh = mesh
			kerb.material_override = stone
			kerb.position = terrain.ground(q.x, q.y) + Vector3(0.0, size.y * 0.5 - 0.12, 0.0)
			kerb.rotation = Vector3(rng.randf_range(-0.05, 0.05), atan2(dir.x, dir.y) + rng.randf_range(-0.06, 0.06),
				rng.randf_range(-0.05, 0.05))
			kerb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			group.add_child(kerb)
		s += KERB_STEP


static func _kerb_skip(q: Vector2) -> bool:
	if _poly_dist(q, OverworldSpec.MAIN_ROAD) < 2.8:
		return true
	if q.y < 62.5 and absf(q.x) < 10.0:
		return true
	return q.distance_to(OverworldSpec.WARD_GATE) < 5.0 or OverworldSpec.WARD_RECT.has_point(q)


## Crowned waymarkers: a squat stone post on the right-hand side, its carved (gilt-worn)
## crown facing the traveller coming from the gate. Unlit.
static func _markers(parent: Node3D, terrain: TerrainBuilder, rng: RandomNumberGenerator) -> void:
	var group := Node3D.new()
	group.name = "Waymarkers"
	parent.add_child(group)
	var body := StaticBody3D.new()
	body.name = "WaymarkerBodies"
	group.add_child(body)
	var line := OverworldSpec.KINGS_ROAD
	var total := _length(line)
	var s := MARKER_FIRST
	var n := 0
	while s < total - 6.0:
		var p := _at(line, s)
		var dir := (_at(line, s + 0.5) - _at(line, s - 0.5)).normalized()
		# (-dir.y, dir.x) is the right-hand side when walking along dir (+X is right facing -Z).
		var right := Vector2(-dir.y, dir.x)
		var q := p + right * (KERB_OFFSET + 0.75)
		var marker := waymarker(rng)
		marker.name = "Waymarker%d" % n
		marker.position = terrain.ground(q.x, q.y)
		# Face (local +Z) towards the traveller coming up the road.
		marker.rotation.y = atan2(-dir.x, -dir.y)
		group.add_child(marker)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.6, 1.6, 0.5)
		shape.shape = box
		shape.position = marker.position + Vector3(0.0, 0.8, 0.0)
		shape.rotation.y = marker.rotation.y
		body.add_child(shape)
		s += MARKER_STEP
		n += 1


static func waymarker(rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	var stone := RetroMaterials.stone()
	var lichen := MeadowProps.lichen_stone()
	var gilt := RetroMaterials.flat(Color(0.42, 0.36, 0.2))
	var lean := Vector3(rng.randf_range(-0.04, 0.04), 0.0, rng.randf_range(-0.05, 0.05))
	var post := PartBuilder.pivot(root, "Post", Vector3.ZERO)
	post.rotation = lean
	PartBuilder.box(post, Vector3(0.7, 0.3, 0.6), Vector3(0, 0.05, 0), lichen)
	PartBuilder.box(post, Vector3(0.48, 1.25, 0.38), Vector3(0, 0.75, 0), stone)
	PartBuilder.box(post, Vector3(0.58, 0.14, 0.48), Vector3(0, 1.43, 0), stone)
	PartBuilder.box(post, Vector3(0.3, 0.2, 0.3), Vector3(0, 1.6, 0), stone, Vector3(0, PI * 0.25, 0))
	# The crown carved on the road face: a band and three points.
	var face := 0.2
	PartBuilder.box(post, Vector3(0.34, 0.08, 0.03), Vector3(0, 1.0, face), gilt)
	for k in 3:
		var x := (k - 1) * 0.12
		var h := 0.14 if k == 1 else 0.1
		PartBuilder.box(post, Vector3(0.06, h, 0.03), Vector3(x, 1.04 + h * 0.5, face), gilt)
	PartBuilder.box(post, Vector3(0.05, 0.05, 0.03), Vector3(0, 1.22, face), gilt, Vector3(0, 0, PI * 0.25))
	return root


static func _lanterns(parent: Node3D, terrain: TerrainBuilder) -> void:
	var group := Node3D.new()
	group.name = "Lanterns"
	parent.add_child(group)
	var line := OverworldSpec.KINGS_ROAD
	for spec: Array in LANTERNS:
		var s: float = spec[0]
		var side: float = spec[1]
		var color := CURSED if str(spec[2]) == "cursed" else WARM
		var p := _at(line, s)
		var dir := (_at(line, s + 0.5) - _at(line, s - 0.5)).normalized()
		var nrm := Vector2(-dir.y, dir.x)
		var q := p + nrm * side * (KERB_OFFSET + 0.6)
		var base := terrain.ground(q.x, q.y)
		# The arm (local +X) hangs the lamp out over the road.
		var over := -nrm * side
		var yaw := atan2(-over.y, over.x)
		var post := Node3D.new()
		post.name = "LanternPost"
		post.position = base
		post.rotation.y = yaw
		group.add_child(post)
		PartBuilder.cylinder(post, 0.06, 0.08, 2.8, Vector3(0, 1.4, 0), RetroMaterials.wood(), 6)
		PartBuilder.box(post, Vector3(0.7, 0.07, 0.07), Vector3(0.3, 2.72, 0), RetroMaterials.iron())
		PartBuilder.box(post, Vector3(0.26, 0.34, 0.26), Vector3(0.6, 2.45, 0), RetroMaterials.iron())
		PartBuilder.box(post, Vector3(0.16, 0.22, 0.28), Vector3(0.6, 2.45, 0), RetroMaterials.flat(color, 3.0))
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.15
		cyl.height = 2.8
		shape.shape = cyl
		shape.position = Vector3(0, 1.4, 0)
		body.add_child(shape)
		post.add_child(body)
		var light := FlickerLight.new()
		light.name = "RoadLantern"
		light.light_color = color
		light.base_energy = 0.75 if color == CURSED else 1.0
		light.omni_range = 5.5
		light.shadow_enabled = false
		light.position = Vector3(0.6, 2.3, 0)
		post.add_child(light)


# --- Pumpkin road (and its stretch outside the gate) --------------------------------

## Loose edge stones along MAIN_ROAD (ruts and puddles removed in V10).
static func _ruts(details: Node3D, terrain: TerrainBuilder, rng: RandomNumberGenerator) -> void:
	var path := OverworldSpec.sample_path(OverworldSpec.MAIN_ROAD, 1.2)
	for i in path.size() - 1:
		var p: Vector2 = path[i]
		if p.y < 12.5:
			continue
		var dir := (path[i + 1] - p).normalized()
		var nrm := Vector2(dir.y, -dir.x)
		var yaw := atan2(dir.x, dir.y)
		for side: float in [-0.75, 0.75]:
			if rng.randf() < 0.45:
				continue
			# V10: the dark rut boxes read as black holes at night; removed. The draws stay so
			# the rest of the road's random layout (edge stones) is unchanged.
			for _k in 5:
				rng.randf()
		if rng.randf() < 0.09:
			# V10: puddles (near-black planes) removed for the same reason; draws kept (position,
			# size, stretch, the splat's seed, and its spin when the road heading is negative).
			for _k in (5 if yaw < 0.0 else 4):
				rng.randf()
		if rng.randf() < 0.16:
			var q := p + nrm * (2.0 if rng.randf() < 0.5 else -2.0) * rng.randf_range(0.9, 1.15)
			var s := rng.randf_range(0.18, 0.32)
			PartBuilder.box(details, Vector3(s * 1.4, s * 0.6, s), terrain.ground(q.x, q.y) + Vector3(0, s * 0.15, 0),
				MeadowProps.lichen_stone(), Vector3(rng.randf_range(-0.3, 0.3), rng.randf() * TAU, rng.randf_range(-0.3, 0.3)))


# --- Polyline helpers ----------------------------------------------------------------

static func _length(pts: Array) -> float:
	var total := 0.0
	for k in pts.size() - 1:
		total += (pts[k] as Vector2).distance_to(pts[k + 1])
	return total


## Point at arc length s along the polyline (clamped to its ends).
static func _at(pts: Array, s: float) -> Vector2:
	var left := maxf(s, 0.0)
	for k in pts.size() - 1:
		var a: Vector2 = pts[k]
		var b: Vector2 = pts[k + 1]
		var seg := a.distance_to(b)
		if left <= seg:
			return a.lerp(b, left / maxf(seg, 0.0001))
		left -= seg
	return pts[pts.size() - 1]


static func _poly_dist(p: Vector2, pts: Array) -> float:
	var best := INF
	for k in pts.size() - 1:
		var a: Vector2 = pts[k]
		var b: Vector2 = pts[k + 1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t))
	return best
