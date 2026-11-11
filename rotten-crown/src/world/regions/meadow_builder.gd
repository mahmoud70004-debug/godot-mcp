@tool
class_name MeadowBuilder
extends RefCounted
## The plains outside the kingdom wall, where the knight wakes (Phase 4a inc 4: the user
## wants them empty). Only what the wake-up needs: long silver-green grass under the moon,
## the dirt road from the wake-up spot to the kingdom gate (carved by the terrain, its
## ruts laid by KingdomRoads), the knight's sleeping place and his dropped lantern.
## Nothing of it lies inside the wall (the forest fills the kingdom) and nothing in the
## gate passage. The walkable plains are OverworldSpec.PLAINS_RECT (invisible barriers
## beyond, OverworldBuilder); the grass thins out towards them and fog hides the rest.
## Output: Node3D "Meadow" with Details (merged, 60 m), Grass (chunks, 60 m) and the light
## DroppedLantern.

const WAKE := Vector2(1.2, 29.0)
## The grass stops short of the wall's outer face (z = 56.4) and the gate towers (54.2).
const GRASS_NORTH := 53.5
## Dense meadow round the wake-up and the road; sparser plains out to the barriers.
const MEADOW_AREA := Rect2(-72.0, 4.0, 144.0, GRASS_NORTH - 4.0)
const PLAINS_AREA := Rect2(-108.0, -58.0, 216.0, 62.0)
const SMALL_RANGE := 60.0
const GRASS_RANGE := 60.0
const WARM_LIGHT := Color(1.0, 0.6, 0.3)


static func build(root: Node3D, terrain: TerrainBuilder, rng: RandomNumberGenerator) -> Node3D:
	var meadow := Node3D.new()
	meadow.name = "Meadow"
	root.add_child(meadow)
	var details := _group(meadow, "Details")
	var keep_out: Array[Vector3] = []
	_build_wake_area(meadow, details, terrain, rng, keep_out)
	_build_grass(meadow, terrain, rng, keep_out)
	_merge(details, SMALL_RANGE)
	return meadow


## The knight's sleeping place: flattened cloak, an empty jug, a goblet he took, spilt wine,
## and his own lantern dropped in the grass, still burning.
static func _build_wake_area(meadow: Node3D, details: Node3D, terrain: TerrainBuilder, rng: RandomNumberGenerator,
		keep_out: Array[Vector3]) -> void:
	var cloth := RetroMaterials.valdron_cloth()
	# Laid on the ground as it is (the road beside it is carved a little lower).
	var g := func(x: float, y: float, z: float) -> Vector3: return Vector3(x, terrain.height_at(x, z) + y, z)
	PartBuilder.box(details, Vector3(1.0, 0.03, 1.8), g.call(1.2, 0.02, 30.0), cloth, Vector3(0.0, 0.3, 0.0))
	PartBuilder.box(details, Vector3(0.5, 0.06, 0.7), g.call(1.55, 0.04, 29.1), cloth, Vector3(0.1, 0.9, 0.05))
	PartBuilder.cylinder(details, 0.08, 0.12, 0.3, g.call(2.2, 0.1, 30.6), RetroMaterials.flat(Color(0.3, 0.22, 0.14)), 6, Vector3(PI * 0.5, 1.0, 0.0))
	var goblet := AssetKit.place(details, "brass_goblets", g.call(0.35, 0.05, 27.9), 0.0, 1.0, "brass_goblet_01")
	goblet.rotation = Vector3(0.0, 0.7, PI * 0.5)
	ThornfieldProps.splat(details, MeadowProps.wine_mat(), g.call(0.15, 0.025, 27.6), 0.55, rng, 1.6)
	keep_out.append(Vector3(1.2, 30.0, 1.3))
	var at := terrain.ground(0.8, 31.0)
	var lantern := PartBuilder.box(details, Vector3(0.22, 0.3, 0.22), at + Vector3(0.0, 0.12, 0.0), RetroMaterials.iron(), Vector3(0.0, 0.4, PI * 0.5))
	PartBuilder.box(lantern, Vector3(0.12, 0.16, 0.12), Vector3.ZERO, RetroMaterials.flat(WARM_LIGHT, 3.0))
	var light := FlickerLight.new()
	light.name = "DroppedLantern"
	light.light_color = WARM_LIGHT
	light.base_energy = 0.9
	light.omni_range = 6.0
	light.shadow_enabled = false
	light.position = at + Vector3(0.0, 0.4, 0.0)
	meadow.add_child(light)
	keep_out.append(Vector3(0.8, 31.0, 0.5))


# --- Grass -------------------------------------------------------------------------

static func _build_grass(meadow: Node3D, terrain: TerrainBuilder, rng: RandomNumberGenerator, keep_out: Array[Vector3]) -> void:
	var patch := FastNoiseLite.new()
	patch.seed = 9091
	patch.frequency = 0.035
	var damp := FastNoiseLite.new()
	damp.seed = 313
	damp.frequency = 0.06
	var tufts: Array = []
	_scatter(tufts, terrain, rng, patch, damp, keep_out, MEADOW_AREA, 0.9, true)
	_scatter(tufts, terrain, rng, patch, damp, keep_out, PLAINS_AREA, 1.25, false)
	# The road: a frayed fringe along both edges and a low crown between the ruts.
	var walk := OverworldSpec.sample_path(OverworldSpec.MAIN_ROAD, 0.7)
	for i in walk.size() - 1:
		var p: Vector2 = walk[i]
		if p.y < 12.5 or p.y > GRASS_NORTH:
			continue
		var dir := (walk[i + 1] - p).normalized()
		var nrm := Vector2(dir.y, -dir.x)
		var yaw := atan2(-dir.y, dir.x)
		for side: float in [-1.0, 1.0]:
			if rng.randf() < 0.85:
				var q := p + nrm * side * rng.randf_range(1.55, 2.1) + dir * rng.randf_range(-0.3, 0.3)
				tufts.append([terrain.ground(q.x, q.y) - Vector3(0, 0.03, 0), yaw + rng.randf_range(-0.6, 0.6), rng.randf_range(0.6, 0.9),
					rng.randf_range(0.3, 0.55), rng.randf_range(0.35, 0.6), MeadowProps.KIND_GRASS])
		if rng.randf() < 0.45:
			var q := p + dir * rng.randf_range(-0.3, 0.3) + nrm * rng.randf_range(-0.15, 0.15)
			tufts.append([terrain.ground(q.x, q.y) - Vector3(0, 0.02, 0), yaw + rng.randf_range(-0.4, 0.4), rng.randf_range(0.45, 0.7),
				rng.randf_range(0.14, 0.28), 0.35, MeadowProps.KIND_GRASS])
	MeadowProps.grass_chunks(meadow, tufts, GRASS_RANGE)
	print("Meadow grass: %d tufts" % tufts.size())


## Jittered-grid scatter over `area` with spacing `step`. Long grass in swathes,
## shorter cropped patches, dark rushes in the damp hollows, sparse weeds. Only outside
## the wall and inside the walkable plains, thinning out towards their edge.
static func _scatter(tufts: Array, terrain: TerrainBuilder, rng: RandomNumberGenerator, patch: FastNoiseLite, damp: FastNoiseLite,
		keep_out: Array[Vector3], area: Rect2, step: float, meadow: bool) -> void:
	var plains := OverworldSpec.PLAINS_RECT
	var nx := int(area.size.x / step)
	var nz := int(area.size.y / step)
	for iz in nz:
		for ix in nx:
			var p := area.position + Vector2((ix + rng.randf()) * step, (iz + rng.randf()) * step)
			var n := patch.get_noise_2d(p.x, p.y)
			var wet := damp.get_noise_2d(p.x, p.y)
			var keep := 0.85 + n * 0.25
			if meadow:
				# Denser around the spawn so the first view is full of grass.
				keep *= 1.0 + 0.5 * exp(-p.distance_to(WAKE) / 14.0)
			else:
				keep *= 0.55 + 0.45 * smoothstep(-0.3, 0.4, n)
			# Fewer tufts towards the barriers: the plain fades into the fog, not into a line.
			var edge := minf(minf(p.x - plains.position.x, plains.end.x - p.x), p.y - plains.position.y)
			keep *= smoothstep(0.0, 22.0, edge)
			if p.y > GRASS_NORTH or rng.randf() > keep:
				continue
			var rd := _road_distance(p)
			if rd < 2.0 + n * 0.4 or _blocked(p, keep_out):
				continue
			var tall := 0.6 + 0.45 * smoothstep(-0.35, 0.45, n)
			var kind := MeadowProps.KIND_GRASS
			var h := rng.randf_range(0.75, 1.05) * tall
			var w := rng.randf_range(0.85, 1.2)
			if wet > 0.38 and rng.randf() < 0.75:
				kind = MeadowProps.KIND_RUSH
				h = rng.randf_range(0.55, 0.85)
				w = rng.randf_range(0.5, 0.75)
			elif rng.randf() < 0.07:
				kind = MeadowProps.KIND_WEED
				h = rng.randf_range(0.65, 0.95)
			var bright := clampf(0.5 + n * 0.45 - maxf(wet, 0.0) * 0.3 + rng.randf_range(-0.12, 0.12), 0.15, 1.0)
			# Most tufts face across the road so the road views see them full on.
			var yaw := rng.randf_range(-0.8, 0.8) if rng.randf() < 0.6 else rng.randf() * TAU
			tufts.append([terrain.ground(p.x, p.y) - Vector3(0, 0.05, 0), yaw, w, h, bright, kind])
			if meadow and rng.randf() < 0.035:
				# A pale flowering weed standing above the grass.
				tufts.append([terrain.ground(p.x + 0.3, p.y + 0.2) - Vector3(0, 0.05, 0), rng.randf() * TAU, 0.5, h * 1.25, 0.7, MeadowProps.KIND_WEED])


# --- Helpers -----------------------------------------------------------------------

static func _road_distance(p: Vector2) -> float:
	var best := INF
	var line := OverworldSpec.MAIN_ROAD
	for k in line.size() - 1:
		var a: Vector2 = line[k]
		var b: Vector2 = line[k + 1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t))
	return best


static func _blocked(p: Vector2, keep_out: Array[Vector3]) -> bool:
	for k in keep_out:
		if p.distance_squared_to(Vector2(k.x, k.y)) < k.z * k.z:
			return true
	return false


## Merges a group here (so it keeps its own cull distance) and shields the
## result from the merge the caller runs over the whole Plains node.
static func _merge(group: Node3D, range_end: float) -> void:
	MeshMerger.merge_static(group, MeshMerger.cell_for(range_end), range_end)
	for node in group.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.visible:
			mi.set_meta(MeshMerger.SKIP_META, true)
			if mi.visibility_range_end <= 0.0:
				mi.visibility_range_end = range_end


static func _group(parent: Node3D, group_name: String) -> Node3D:
	var node := Node3D.new()
	node.name = group_name
	parent.add_child(node)
	return node
