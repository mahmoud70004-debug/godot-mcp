@tool
class_name HollowmereBuilder
extends RefCounted
## Hollowmere (reference 2: the pumpkin farm and the village with the steeple),
## after the curse: rows of fat pumpkins, some carved and glowing, some grown
## into flesh, a village of ruined clapboard houses and a chapel with a broken spire.
##
## Assumptions (contract C9, owned by the overworld assembler / OverworldSpec):
## - TerrainBuilder over OverworldSpec.make(); -Z is towards the castle.
## - Main road polyline OverworldSpec.MAIN_ROAD, road_width 3.2; it ends at (20, 322).
## - Village plateau Vector4(22, 338, 44, 24) is flat; the chapel stands at (30, 368).
## - Dry/field paint Vector3(-8, 270, 40) under the pumpkin fields (z 236..304).
## - Region node sits at the origin, so child positions are world positions.
## - Markers: Spawn_Enemy_1..5, Lore_1..2, Pickup_1..2, Light_1..2 and Trigger
##   (meta "radius" = 55). The two OmniLight3D nodes (chapel lantern, window candle)
##   are built here too, named LanternLight / CandleLight; Light_N mark the same spots.
## - res://assets/materials/grass_field.tres exists (GrassScatter material).

const OOZE_SHADER := preload("res://assets/shaders/ooze.gdshader")
const GRASS_MAT := "res://assets/materials/grass_field.tres"
const FIELD_Z0 := 236.0
const FIELD_Z1 := 304.0
const SQUARE := Vector2(24.0, 343.0)
const CHAPEL_POS := Vector2(30.0, 368.0)
const LANE := [Vector2(20.0, 322.0), Vector2(27.0, 333.0), Vector2(21.0, 345.0), Vector2(28.0, 357.0), Vector2(30.0, 363.0)]
const COTTAGES := [Vector2(7.0, 338.0), Vector2(9.0, 354.0), Vector2(40.0, 334.0), Vector2(43.0, 350.0),
	Vector2(14.0, 371.0), Vector2(47.0, 366.0), Vector2(-6.0, 350.0), Vector2(34.0, 316.0)]

static var _ooze: ShaderMaterial
static var _blood: ShaderMaterial
static var _pulp: ShaderMaterial


static func build(root: Node3D, terrain: TerrainBuilder, rng: RandomNumberGenerator) -> Node3D:
	_make_materials()
	var region := Node3D.new()
	region.name = "Hollowmere"
	root.add_child(region)
	var fields := _group(region, "PumpkinFields")
	_pumpkin_fields(fields, terrain, rng)
	_fences(region, terrain, rng)
	var village := _group(region, "Village")
	var doors := _village(village, terrain, rng)
	_lane(village, terrain)
	_chapel(village, terrain, rng)
	_square_gore(village, terrain, rng, doors)
	_scarecrow_ring(region, terrain, rng)
	_grass(region, terrain, rng)
	_markers(region, terrain)
	return region


static func _make_materials() -> void:
	_ooze = ShaderMaterial.new()
	_ooze.shader = OOZE_SHADER
	_blood = ShaderMaterial.new()
	_blood.shader = OOZE_SHADER
	_blood.set_shader_parameter("surface_color", Color(0.3, 0.02, 0.02))
	_blood.set_shader_parameter("deep_color", Color(0.1, 0.0, 0.01))
	_blood.set_shader_parameter("emission_strength", 0.0)
	_blood.set_shader_parameter("bubble_amount", 0.0)
	_blood.set_shader_parameter("roughness_value", 0.4)
	_pulp = ShaderMaterial.new()
	_pulp.shader = OOZE_SHADER
	_pulp.set_shader_parameter("surface_color", Color(0.55, 0.26, 0.05))
	_pulp.set_shader_parameter("deep_color", Color(0.14, 0.06, 0.01))
	_pulp.set_shader_parameter("emission_strength", 0.25)
	_pulp.set_shader_parameter("bubble_amount", 0.3)


# --- Geometry helpers ----------------------------------------------------------

static func _group(parent: Node3D, group_name: String) -> Node3D:
	var node := Node3D.new()
	node.name = group_name
	parent.add_child(node)
	return node


## Main road centre x at world z (linear along the polyline).
static func _road_x(z: float) -> float:
	var pts := OverworldSpec.MAIN_ROAD
	for k in pts.size() - 1:
		var a: Vector2 = pts[k]
		var b: Vector2 = pts[k + 1]
		if z >= a.y and z <= b.y:
			return lerpf(a.x, b.x, (z - a.y) / (b.y - a.y))
	return (pts[pts.size() - 1] as Vector2).x


static func _poly_dist(p: Vector2, pts: Array) -> float:
	var best := INF
	for k in pts.size() - 1:
		var a: Vector2 = pts[k]
		var b: Vector2 = pts[k + 1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t))
	return best


## Thin box between two points (vines, trail strips).
static func _strip(parent: Node3D, a: Vector3, b: Vector3, thick: float, width: float, mat: Material) -> void:
	var v := b - a
	var mi := PartBuilder.box(parent, Vector3(maxf(v.length(), 0.01), thick, width), (a + b) * 0.5, mat)
	mi.rotation.y = atan2(-v.z, v.x)
	mi.rotation.z = asin(clampf(v.y / maxf(v.length(), 0.01), -1.0, 1.0))


static func _splat(parent: Node3D, mat: ShaderMaterial, pos: Vector3, size: float, rng: RandomNumberGenerator) -> void:
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(size, size)
	mi.mesh = plane
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos
	mi.rotation.y = rng.randf() * TAU
	parent.add_child(mi)
	mi.set_meta(MeshMerger.SEED_META, rng.randf())


static func _clothes_heap(parent: Node3D, pos: Vector3, rng: RandomNumberGenerator) -> void:
	var palette := [Color(0.3, 0.05, 0.05), Color(0.2, 0.22, 0.3), Color(0.35, 0.3, 0.2), Color(0.15, 0.25, 0.12), Color(0.4, 0.36, 0.3)]
	var base_color: Color = palette[rng.randi() % palette.size()]
	for i in 3:
		var offset := Vector3(rng.randf_range(-0.35, 0.35), 0.04 + i * 0.04, rng.randf_range(-0.35, 0.35))
		PartBuilder.box(parent, Vector3(rng.randf_range(0.5, 0.9), 0.06, rng.randf_range(0.4, 0.8)), pos + offset,
			RetroMaterials.flat(base_color.darkened(i * 0.15)), Vector3(0.0, rng.randf() * TAU, rng.randf_range(-0.1, 0.1)))
	_splat(parent, _ooze, pos + Vector3(0.0, 0.025, 0.0), 1.2, rng)


static func _trail(parent: Node3D, from: Vector3, to: Vector3, rng: RandomNumberGenerator) -> void:
	var steps := int(from.distance_to(to) / 0.7)
	for i in steps:
		var p := from.lerp(to, float(i) / steps) + Vector3(rng.randf_range(-0.2, 0.2), rng.randf_range(0.04, 0.06), rng.randf_range(-0.2, 0.2))
		_splat(parent, _blood, p, rng.randf_range(0.3, 0.6), rng)


# --- Pumpkin fields --------------------------------------------------------------

static func _pumpkin_fields(fields: Node3D, terrain: TerrainBuilder, rng: RandomNumberGenerator) -> void:
	var vine := RetroMaterials.flat(Color(0.05, 0.08, 0.035))
	var leaf := RetroMaterials.flat(Color(0.07, 0.12, 0.05))
	var offsets := [4.0, 6.8, 9.6, 12.4]
	var smashed := 0
	for side: float in [-1.0, 1.0]:
		for off: float in offsets:
			var vine_prev := Vector3.INF
			var z := FIELD_Z0 + rng.randf_range(0.0, 1.0)
			var since_vine := 0.0
			while z < FIELD_Z1:
				var x := _road_x(z) + side * (off + sin(z * 0.17 + off) * 0.2 + rng.randf_range(-0.15, 0.15))
				var g := terrain.ground(x, z)
				# Vine line along the row.
				since_vine += 1.0
				if since_vine >= 2.0:
					since_vine = 0.0
					var vp := g + Vector3(rng.randf_range(-0.25, 0.25), 0.04, 0.0)
					if vine_prev != Vector3.INF:
						_strip(fields, vine_prev, vp, 0.05, 0.06, vine)
					vine_prev = vp
					if rng.randf() < 0.45:
						PartBuilder.box(fields, Vector3(0.38, 0.02, 0.3), vp + Vector3(rng.randf_range(-0.3, 0.3), 0.08, rng.randf_range(-0.2, 0.2)), leaf, Vector3(0, rng.randf() * TAU, 0.15))
				z += rng.randf_range(0.9, 1.4)
				if rng.randf() < 0.18:
					continue  # gaps: harvested / eaten
				var roll := rng.randf()
				var sz := rng.randf_range(0.55, 1.05)
				if rng.randf() < 0.06:
					sz = rng.randf_range(1.3, 1.7)
				if roll < 0.04 and smashed < 16:
					smashed += 1
					_smashed_pumpkin(fields, g, sz, rng)
					continue
				var pk := PropKit.pumpkin(sz, rng, roll > 0.88, roll > 0.76 and roll <= 0.88)
				pk.position = g - Vector3(0.0, sz * 0.03, 0.0)
				pk.rotation.y = (PI * 0.5 if side < 0.0 else -PI * 0.5) + rng.randf_range(-0.6, 0.6)
				fields.add_child(pk)
	# Body-horror clusters: a half-buried person with pumpkins fused around.
	var spots := [Vector2(-1.0, 248.0), Vector2(1.0, 261.0), Vector2(-1.0, 276.0), Vector2(1.0, 290.0), Vector2(-1.0, 297.0)]
	var idx := 0
	for spot: Vector2 in spots:
		var z := spot.y
		var x := _road_x(z) + spot.x * (8.2 + rng.randf_range(-0.5, 0.5))
		_torso_cluster(fields, terrain.ground(x, z), rng, idx)
		idx += 1


static func _smashed_pumpkin(parent: Node3D, g: Vector3, sz: float, rng: RandomNumberGenerator) -> void:
	var mat := RetroMaterials.pumpkin()
	for i in 3:
		var a := rng.randf() * TAU
		var chunk := PartBuilder.sphere(parent, sz * rng.randf_range(0.18, 0.3), g + Vector3(cos(a) * sz * 0.35, sz * 0.08, sin(a) * sz * 0.35), mat, true, 6)
		chunk.rotation = Vector3(rng.randf_range(-1.2, 1.2), rng.randf() * TAU, rng.randf_range(-1.2, 1.2))
	PartBuilder.sphere(parent, sz * 0.3, g + Vector3(0, sz * 0.12, 0), RetroMaterials.flat(Color(0.35, 0.14, 0.03)), true, 6)
	_splat(parent, _pulp, g + Vector3(0, 0.03, 0), sz * 2.2, rng)


static func _torso_cluster(parent: Node3D, g: Vector3, rng: RandomNumberGenerator, idx: int) -> void:
	var skin := RetroMaterials.skin()
	var rag := RetroMaterials.rag()
	var c := _group(parent, "TorsoCluster_%d" % (idx + 1))
	c.position = g
	c.rotation.y = rng.randf() * TAU
	_splat(c, _blood, Vector3(0, 0.03, 0), 3.0, rng)
	# Torso breaking out of the soil, ribs showing.
	var torso := PartBuilder.box(c, Vector3(0.62, 0.34, 0.34), Vector3(0, 0.12, 0), skin, Vector3(0.0, 0.3, 0.45))
	torso.name = "Torso"
	PartBuilder.box(c, Vector3(0.5, 0.06, 0.3), Vector3(0.05, 0.3, 0.03), RetroMaterials.flat(Color(0.35, 0.05, 0.05)), Vector3(0.0, 0.3, 0.45))
	for i in 4:
		PartBuilder.box(c, Vector3(0.04, 0.04, 0.3), Vector3(-0.15 + i * 0.1, 0.34, 0.03), RetroMaterials.flat(Color(0.8, 0.76, 0.62)), Vector3(0.0, 0.3, 0.45))
	PartBuilder.box(c, Vector3(0.5, 0.05, 0.3), Vector3(-0.3, 0.22, 0.2), rag, Vector3(0.2, 0.5, 0.1))
	# Arm reaching up, fingers curled.
	var s := Vector3(0.28, 0.18, 0.1)
	var e := s + Vector3(0.18, 0.6, 0.05)
	_strip(c, s, e, 0.13, 0.13, skin)
	var h := e + Vector3(0.25, 0.4, -0.05)
	_strip(c, e, h, 0.1, 0.1, skin)
	PartBuilder.box(c, Vector3(0.1, 0.12, 0.05), h + Vector3(0.03, 0.06, 0), skin, Vector3(0, 0, -0.5))
	for i in 4:
		PartBuilder.box(c, Vector3(0.025, 0.12, 0.025), h + Vector3(0.07 + i * 0.002, 0.15, -0.035 + i * 0.025), skin, Vector3(0, 0, -0.3 - i * 0.12))
	# Pumpkins fused around it.
	var n := 6
	for i in n:
		var a := TAU * i / n + rng.randf_range(-0.2, 0.2)
		var sz := rng.randf_range(0.7, 1.1)
		var pk := PropKit.pumpkin(sz, rng, false, i % 2 == 0)
		pk.position = Vector3(cos(a) * 0.85, -sz * 0.05, sin(a) * 0.85)
		pk.rotation.y = -a + PI * 0.5 + rng.randf_range(-0.3, 0.3)
		if i % 2 == 0:
			pk.rotation.x = -0.75  # flesh face tips up towards the sky
		c.add_child(pk)
	# Veins/roots tying them together.
	var vein := RetroMaterials.flat(Color(0.3, 0.05, 0.06))
	for i in n:
		var a := TAU * i / n
		_strip(c, Vector3(0, 0.1, 0), Vector3(cos(a) * 0.8, 0.12, sin(a) * 0.8), 0.04, 0.05, vein)


# --- Fences ------------------------------------------------------------------------

static func _fences(region: Node3D, terrain: TerrainBuilder, rng: RandomNumberGenerator) -> void:
	var fences := _group(region, "Fences")
	for side: float in [-1.0, 1.0]:
		var pts := PackedVector3Array()
		var z := FIELD_Z0 - 4.0
		while z <= FIELD_Z1 + 4.0:
			var p := terrain.ground(_road_x(z) + side * 2.8, z)
			pts.append(p)
			z += 6.0
		fences.add_child(PropKit.fence_run(pts, 0.35, rng))


# --- Village -----------------------------------------------------------------------

## Builds the cottages and returns their door positions (world) for gore trails.
static func _village(village: Node3D, terrain: TerrainBuilder, rng: RandomNumberGenerator) -> Array[Vector3]:
	var doors: Array[Vector3] = []
	var board := RetroMaterials.wood()
	var i := 0
	for spot: Vector2 in COTTAGES:
		var size := Vector3(rng.randf_range(4.2, 5.0), rng.randf_range(2.5, 2.9), rng.randf_range(4.6, 5.6))
		var ruined := i != 0 and i != 5
		var cot := PropKit.cottage(size, rng, ruined)
		cot.name = "Cottage_%d" % (i + 1)
		var to_square := SQUARE - spot
		var yaw := atan2(to_square.x, to_square.y) + rng.randf_range(-0.25, 0.25)
		cot.position = terrain.ground(spot.x + rng.randf_range(-1.0, 1.0), spot.y + rng.randf_range(-1.0, 1.0))
		cot.rotation.y = yaw
		village.add_child(cot)
		var xf := cot.transform
		var front := size.z * 0.5
		# Open door leaf hanging from the hinge.
		var hinge := PartBuilder.pivot(cot, "DoorLeaf", Vector3(-0.5, 0.0, front + 0.1))
		hinge.rotation.y = rng.randf_range(1.1, 1.8)
		PartBuilder.box(hinge, Vector3(0.95, 1.85, 0.06), Vector3(0.48, 0.93, 0), board)
		PartBuilder.box(hinge, Vector3(0.9, 0.08, 0.07), Vector3(0.48, 1.2, 0), RetroMaterials.iron())
		doors.append(xf * Vector3(0.0, 0.0, front + 1.0))
		# Boarded windows.
		if ruined and size.x >= 3.5:
			for sx: float in [-1.0, 1.0]:
				var wp := Vector3(sx * size.x * 0.3, size.y * 0.55, front + 0.2)
				for b in 3:
					PartBuilder.box(cot, Vector3(1.0, 0.14, 0.04), wp + Vector3(0, (b - 1) * 0.28, b * 0.01), board, Vector3(0, 0, rng.randf_range(-0.4, 0.4)))
		# Wrecked interior: clothes and a bloody smear.
		if rng.randf() < 0.7:
			_clothes_heap(cot, Vector3(rng.randf_range(-1.0, 1.0), 0.05, rng.randf_range(-1.0, 1.0)), rng)
		i += 1
	return doors


## Beaten dirt lane winding from the main road end to the chapel.
static func _lane(village: Node3D, terrain: TerrainBuilder) -> void:
	var lane := _group(village, "Lane")
	var mat := RetroMaterials.red_earth()
	for k in LANE.size() - 1:
		var a: Vector2 = LANE[k]
		var b: Vector2 = LANE[k + 1]
		_strip(lane, terrain.ground(a.x, a.y) + Vector3(0, 0.05, 0), terrain.ground(b.x, b.y) + Vector3(0, 0.05, 0), 0.06, 3.2, mat)
	# Dirt patch of the square.
	var sq := PartBuilder.cylinder(lane, 5.5, 5.5, 0.06, terrain.ground(SQUARE.x, SQUARE.y) + Vector3(0, 0.05, 0), mat, 12)
	sq.name = "Square"


static func _chapel(village: Node3D, terrain: TerrainBuilder, rng: RandomNumberGenerator) -> void:
	var chapel := PropKit.chapel(rng, true)
	chapel.position = terrain.ground(CHAPEL_POS.x, CHAPEL_POS.y)
	chapel.rotation.y = PI  # door faces the village (-Z)
	village.add_child(chapel)
	# Sickly green lantern by the door (light + mesh, pos in region space).
	var lp := chapel.transform * Vector3(1.1, 2.4, 7.2)
	var hook := PartBuilder.box(village, Vector3(0.06, 0.5, 0.06), lp + Vector3(0, 0.45, 0), RetroMaterials.iron())
	hook.name = "LanternHook"
	PartBuilder.box(village, Vector3(0.22, 0.3, 0.22), lp, RetroMaterials.flat(Color(0.4, 0.9, 0.35), 1.6))
	var light := OmniLight3D.new()
	light.name = "LanternLight"
	light.position = lp
	light.light_color = Color(0.45, 0.9, 0.4)
	light.light_energy = 1.3
	light.omni_range = 6.5
	light.shadow_enabled = false
	village.add_child(light)


static func _square_gore(village: Node3D, terrain: TerrainBuilder, rng: RandomNumberGenerator, doors: Array[Vector3]) -> void:
	var gore := _group(village, "Gore")
	# A smashed cart on the lane.
	var cart := PropKit.cart_wreck(rng)
	cart.position = terrain.ground(15.0, 331.0)
	cart.rotation.y = 0.9
	gore.add_child(cart)
	# Empty clothes where the villagers stood.
	for i in 9:
		var a := rng.randf() * TAU
		var r := rng.randf_range(1.5, 14.0)
		var p := SQUARE + Vector2(cos(a), sin(a)) * r
		if _poly_dist(p, LANE) < 1.4:
			continue
		_clothes_heap(gore, terrain.ground(p.x, p.y), rng)
	# Ooze and blood splats around the square.
	for i in 20:
		var a := rng.randf() * TAU
		var r := rng.randf_range(1.0, 22.0)
		var p := SQUARE + Vector2(cos(a), sin(a)) * r
		var g := terrain.ground(p.x, p.y) + Vector3(0, 0.07, 0)
		if i % 3 == 0:
			_splat(gore, _ooze, g, rng.randf_range(0.8, 2.4), rng)
		else:
			_splat(gore, _blood, g, rng.randf_range(0.5, 1.6), rng)
	# A blood trail from the square into the first house.
	var door := doors[0]
	var start := terrain.ground(SQUARE.x + 1.0, SQUARE.y - 1.0)
	_trail(gore, start, Vector3(door.x, terrain.height_at(door.x, door.z), door.z), rng)
	# A candle in one window of a ruined house (cottage 3).
	var cot := village.get_node("Cottage_3") as Node3D
	var cp := cot.transform * Vector3(1.2, 1.4, 1.6)
	PartBuilder.cylinder(village, 0.03, 0.03, 0.14, cp - Vector3(0, 0.07, 0), RetroMaterials.flat(Color(0.8, 0.75, 0.6)), 5)
	PartBuilder.sphere(village, 0.035, cp + Vector3(0, 0.03, 0), RetroMaterials.flat(Color(1.0, 0.7, 0.3), 2.0), false, 5)
	var candle := OmniLight3D.new()
	candle.name = "CandleLight"
	candle.position = cp + Vector3(0, 0.2, 0)
	candle.light_color = Color(1.0, 0.6, 0.25)
	candle.light_energy = 0.8
	candle.omni_range = 4.0
	candle.shadow_enabled = false
	village.add_child(candle)


static func _scarecrow_ring(region: Node3D, terrain: TerrainBuilder, rng: RandomNumberGenerator) -> void:
	var ring := _group(region, "ScarecrowRing")
	var center := Vector2(22.0, 330.0)
	var n := 10
	for i in n:
		var a := TAU * i / n + 0.3
		var p := center + Vector2(cos(a), sin(a)) * 10.0
		if _poly_dist(p, LANE) < 2.6 or _poly_dist(p, OverworldSpec.MAIN_ROAD) < 2.6:
			continue
		var sc := PropKit.scarecrow(rng, true)
		sc.position = terrain.ground(p.x, p.y)
		sc.rotation.y = atan2(cos(a), sin(a)) + rng.randf_range(-0.3, 0.3)
		ring.add_child(sc)


static func _grass(region: Node3D, terrain: TerrainBuilder, rng: RandomNumberGenerator) -> void:
	var mat := load(GRASS_MAT) as Material
	if mat == null:
		return
	var cottage_spots: Array = COTTAGES
	var accept := func(p: Vector2) -> bool:
		if _poly_dist(p, OverworldSpec.MAIN_ROAD) <= 2.4 or _poly_dist(p, LANE) <= 2.4:
			return false
		if p.distance_to(SQUARE) < 6.0 or p.distance_to(CHAPEL_POS) < 6.5:
			return false
		for c: Vector2 in cottage_spots:
			if absf(p.x - c.x) < 3.2 and absf(p.y - c.y) < 3.6:
				return false
		# Between the pumpkin rows only at the field edge.
		if p.y > FIELD_Z0 - 2.0 and p.y < FIELD_Z1 + 2.0 and absf(p.x - _road_x(p.y)) < 14.5:
			return false
		return true
	GrassScatter.scatter(region, terrain, Rect2(-34.0, 226.0, 100.0, 170.0), 1500, mat, Vector2(0.8, 0.6), rng, accept)


static func _markers(region: Node3D, terrain: TerrainBuilder) -> void:
	var markers := _group(region, "Markers")
	var enemy := [Vector2(19.0, 346.0), Vector2(29.0, 341.0), Vector2(24.0, 352.0),
		Vector2(_road_x(262.0) + 8.0, 262.0), Vector2(_road_x(282.0) - 8.0, 282.0)]
	for i in enemy.size():
		_marker(markers, "Spawn_Enemy_%d" % (i + 1), terrain, enemy[i])
	_marker(markers, "Lore_1", terrain, Vector2(31.5, 357.0))
	_marker(markers, "Lore_2", terrain, Vector2(_road_x(250.0) - 3.4, 250.0))
	_marker(markers, "Pickup_1", terrain, Vector2(13.0, 333.0))
	_marker(markers, "Pickup_2", terrain, Vector2(40.0, 340.0))
	_marker(markers, "Light_1", terrain, CHAPEL_POS + Vector2(-1.1, -7.2)).position.y += 2.4
	_marker(markers, "Light_2", terrain, Vector2(43.0, 350.0)).position.y += 1.4
	var trig := _marker(markers, "Trigger", terrain, SQUARE)
	trig.set_meta("radius", 55.0)


static func _marker(parent: Node3D, marker_name: String, terrain: TerrainBuilder, xz: Vector2) -> Marker3D:
	var m := Marker3D.new()
	m.name = marker_name
	m.position = terrain.ground(xz.x, xz.y) + Vector3(0, 0.1, 0)
	parent.add_child(m)
	return m
