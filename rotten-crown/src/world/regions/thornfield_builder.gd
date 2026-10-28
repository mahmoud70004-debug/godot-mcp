@tool
class_name ThornfieldBuilder
extends RefCounted
## Thornfield: the lonely farmstead at the end of the farm track (reference 1).
## A pale clapboard farmhouse, a huge dead tree, broken split-rail fences,
## tall wind-bent dry grass on both sides of the worn track, scarecrows.
##
## Assumptions (contract C9 / OverworldSpec):
##   - plateau Vector4(-122, 152, 16, 14) flattens the farmyard around the house
##   - dry field Vector3(-95, 128, 58) is painted (G) on the terrain
##   - farm track OverworldSpec.FARM_TRACK ends at (-116, 148), is painted (R)
##   - the dead tree stands 4.5 m off the track centreline (spec point (-104,146)
##     lies on the track, so it is nudged to z = 150.5)
## Output: Node3D "Thornfield" with props plus Marker3D children Spawn_Enemy_1..3,
## Lore_1, Pickup_1, Light_1 and Trigger (meta "radius" = 40). One OmniLight3D
## (range 5.5, no shadow) glows inside the house.

const OOZE_SHADER := preload("res://assets/shaders/ooze.gdshader")
const HOUSE := Vector2(-122.0, 152.0)
const FIELD := Vector3(-95.0, 128.0, 58.0)
const ROAD_CLEAR := 2.2
const SICK_LIGHT := Color(0.75, 0.9, 0.4)


static func build(root: Node3D, terrain: TerrainBuilder, rng: RandomNumberGenerator) -> Node3D:
	var region := Node3D.new()
	region.name = "Thornfield"
	root.add_child(region)
	var ooze := ShaderMaterial.new()
	ooze.shader = OOZE_SHADER
	var blood := ShaderMaterial.new()
	blood.shader = OOZE_SHADER
	blood.set_shader_parameter("surface_color", Color(0.3, 0.02, 0.02))
	blood.set_shader_parameter("deep_color", Color(0.1, 0.0, 0.01))
	blood.set_shader_parameter("emission_strength", 0.0)
	blood.set_shader_parameter("bubble_amount", 0.0)
	blood.set_shader_parameter("roughness_value", 0.4)

	var props := _group(region, "Props")
	_build_house(props, terrain, rng, blood, ooze)
	_build_barn(props, terrain, rng)
	_build_tree(props, terrain, rng)
	_build_well(props, terrain, rng, ooze)
	_build_fences(props, terrain, rng)
	_build_scarecrows(props, terrain, rng)
	var cart := PropKit.cart_wreck(rng)
	cart.position = terrain.ground(-88.0, 137.0)
	cart.rotation.y = 0.7
	props.add_child(cart)
	_build_grass(region, terrain, rng)
	_build_markers(region, terrain)
	return region


# --- Buildings -----------------------------------------------------------------

static func _build_house(parent: Node3D, terrain: TerrainBuilder, rng: RandomNumberGenerator,
		blood: ShaderMaterial, ooze: ShaderMaterial) -> void:
	var size := Vector3(7.0, 3.2, 5.5)
	var house := PropKit.cottage(size, rng, false)
	house.name = "Farmhouse"
	house.position = terrain.ground(HOUSE.x, HOUSE.y)
	var facing := Vector2(32.0, -12.0)  # towards the track
	house.rotation.y = atan2(facing.x, facing.y)
	parent.add_child(house)
	var wood := RetroMaterials.wood()
	var dark := RetroMaterials.flat(Color(0.03, 0.025, 0.02))
	var fz := size.z * 0.5 + 0.25
	# One boarded window (front, left).
	var wx := -size.x * 0.3
	PartBuilder.box(house, Vector3(1.3, 1.2, 0.04), Vector3(wx, size.y * 0.55, fz + 0.02), dark)
	for i in 3:
		PartBuilder.box(house, Vector3(1.5, 0.16, 0.06), Vector3(wx, size.y * 0.55 - 0.4 + i * 0.4, fz + 0.1),
			wood, Vector3(0.0, 0.0, rng.randf_range(-0.2, 0.2)))
	# Door ajar, hanging off its hinge.
	var hinge := PartBuilder.pivot(house, "Door", Vector3(0.5, 0.0, size.z * 0.5))
	hinge.rotation.y = -1.1
	PartBuilder.box(hinge, Vector3(0.95, 1.85, 0.07), Vector3(-0.48, 0.93, 0.0), wood, Vector3(0.0, 0.0, 0.04))
	# Warm-sick glow inside.
	var glow := OmniLight3D.new()
	glow.name = "FarmhouseGlow"
	glow.light_color = SICK_LIGHT
	glow.light_energy = 0.8
	glow.omni_range = 5.5
	glow.shadow_enabled = false
	glow.position = Vector3(0.0, 1.5, 0.0)
	house.add_child(glow)
	# Splats on the ground in front of the door (house-local -> world via transform).
	for i in 7:
		var local := Vector3(rng.randf_range(-1.8, 1.8), 0.0, size.z * 0.5 + rng.randf_range(0.6, 3.5))
		var wp := house.transform * local
		var p := terrain.ground(wp.x, wp.z) + Vector3(0.0, 0.05, 0.0)
		_splat(parent, blood if i % 3 != 0 else ooze, p, rng.randf_range(0.5, 1.6), rng)


static func _build_barn(parent: Node3D, terrain: TerrainBuilder, rng: RandomNumberGenerator) -> void:
	var barn := PropKit.cottage(Vector3(4.6, 2.6, 3.8), rng, true)
	barn.name = "Barn"
	barn.position = terrain.ground(-136.0, 141.0)
	barn.rotation.y = 0.9
	parent.add_child(barn)
	var shed := PropKit.cottage(Vector3(3.6, 2.2, 3.0), rng, true)
	shed.name = "Shed"
	shed.position = terrain.ground(-134.0, 166.0)
	shed.rotation.y = 2.3
	parent.add_child(shed)


static func _build_tree(parent: Node3D, terrain: TerrainBuilder, rng: RandomNumberGenerator) -> void:
	var tree := PropKit.dead_tree(rng.randf_range(12.0, 14.0), rng)
	tree.name = "DeadTree"
	tree.position = terrain.ground(-104.0, 150.5)
	parent.add_child(tree)


static func _build_well(parent: Node3D, terrain: TerrainBuilder, rng: RandomNumberGenerator, ooze: ShaderMaterial) -> void:
	var well := _group(parent, "Well")
	var c := terrain.ground(-114.0, 160.0)
	well.position = c
	var stone := RetroMaterials.stone()
	var wood := RetroMaterials.wood()
	PartBuilder.cylinder(well, 0.9, 1.0, 0.8, Vector3(0.0, 0.4, 0.0), stone, 10)
	PartBuilder.cylinder(well, 0.7, 0.7, 0.02, Vector3(0.0, 0.81, 0.0), RetroMaterials.flat(Color(0.0, 0.0, 0.0)), 10)
	for side in [-1.0, 1.0]:
		PartBuilder.box(well, Vector3(0.12, 2.0, 0.12), Vector3(side * 0.9, 1.0, 0.0), wood)
	PartBuilder.box(well, Vector3(1.9, 0.1, 0.1), Vector3(0.0, 1.95, 0.0), wood, Vector3(0.0, 0.0, 0.08))
	# A water trough beside it.
	PartBuilder.box(well, Vector3(2.0, 0.45, 0.6), Vector3(2.6, 0.22, 0.4), wood, Vector3(0.0, 0.3, 0.0))
	_splat(parent, ooze, c + Vector3(0.0, 0.83, 0.0), 1.0, rng)


# --- Fences, scarecrows ------------------------------------------------------------

static func _build_fences(parent: Node3D, terrain: TerrainBuilder, rng: RandomNumberGenerator) -> void:
	var fences := _group(parent, "Fences")
	var track := OverworldSpec.sample_path(OverworldSpec.FARM_TRACK, 4.0)
	for side in [-1.0, 1.0]:
		var pts := PackedVector3Array()
		var k := 0
		while k < track.size():
			var p := track[k]
			var nxt := track[mini(k + 1, track.size() - 1)]
			var prv := track[maxi(k - 1, 0)]
			var dir := (nxt - prv).normalized()
			var off: Vector2 = p + Vector2(-dir.y, dir.x) * 3.0 * side
			# Stop short of the farmyard; leave a gap every few runs.
			if off.distance_to(HOUSE) < 13.0:
				break
			pts.append(terrain.ground(off.x, off.y))
			k += 1
			if pts.size() >= 4 + rng.randi() % 3:
				if pts.size() >= 2:
					fences.add_child(PropKit.fence_run(pts, rng.randf_range(0.4, 0.6), rng))
				pts = PackedVector3Array()
				k += 1 + rng.randi() % 2  # the gap
		if pts.size() >= 2:
			fences.add_child(PropKit.fence_run(pts, 0.5, rng))
	# Paddock beside the barn: three sides, the fourth fallen away.
	var corners: Array[Vector2] = [Vector2(-146.0, 150.0), Vector2(-146.0, 162.0), Vector2(-134.0, 160.0), Vector2(-140.0, 148.0)]
	var ring := PackedVector3Array()
	for c in corners:
		ring.append(terrain.ground(c.x, c.y))
	fences.add_child(PropKit.fence_run(ring, 0.45, rng))


static func _build_scarecrows(parent: Node3D, terrain: TerrainBuilder, rng: RandomNumberGenerator) -> void:
	var spots: Array[Vector2] = [Vector2(-111.0, 143.0), Vector2(-96.0, 160.0), Vector2(-78.0, 118.0), Vector2(-100.0, 124.0)]
	for i in spots.size():
		var s := PropKit.scarecrow(rng, i == 0)
		s.position = terrain.ground(spots[i].x, spots[i].y)
		parent.add_child(s)


# --- Grass ---------------------------------------------------------------------

static func _near_track(p: Vector2, clear: float) -> bool:
	var pts := OverworldSpec.FARM_TRACK
	for k in pts.size() - 1:
		var a: Vector2 = pts[k]
		var b: Vector2 = pts[k + 1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		if p.distance_to(a + ab * t) < clear:
			return true
	return false


static func _build_grass(region: Node3D, terrain: TerrainBuilder, rng: RandomNumberGenerator) -> void:
	var center := Vector2(FIELD.x, FIELD.y)
	var tall := func(p: Vector2) -> bool:
		if p.distance_to(center) > FIELD.z or p.distance_to(HOUSE) < 7.0:
			return false
		return not _near_track(p, ROAD_CLEAR)
	var dry := load("res://assets/materials/grass_dry_tall.tres") as Material
	GrassScatter.scatter(region, terrain, Rect2(FIELD.x - FIELD.z, FIELD.y - FIELD.z, FIELD.z * 2.0, FIELD.z * 2.0),
		2200, dry, Vector2(1.0, 1.1), rng, tall, 60.0)
	var yard := func(p: Vector2) -> bool:
		return p.distance_to(HOUSE) > 5.5 and p.distance_to(HOUSE) < 17.0 and not _near_track(p, ROAD_CLEAR)
	var short := load("res://assets/materials/grass_field.tres") as Material
	GrassScatter.scatter(region, terrain, Rect2(HOUSE.x - 17.0, HOUSE.y - 17.0, 34.0, 34.0), 800, short,
		Vector2(0.8, 0.5), rng, yard, 45.0)


# --- Markers ---------------------------------------------------------------------

static func _build_markers(region: Node3D, terrain: TerrainBuilder) -> void:
	var spawns: Array[Vector2] = [Vector2(-106.0, 138.0), Vector2(-112.0, 164.0), Vector2(-128.0, 131.0)]
	for i in spawns.size():
		_marker(region, "Spawn_Enemy_%d" % (i + 1), terrain.ground(spawns[i].x, spawns[i].y))
	_marker(region, "Lore_1", terrain.ground(HOUSE.x, HOUSE.y) + Vector3(0.0, 0.6, 0.0))
	_marker(region, "Pickup_1", terrain.ground(-111.5, 158.5) + Vector3(0.0, 0.5, 0.0))
	_marker(region, "Light_1", terrain.ground(HOUSE.x, HOUSE.y) + Vector3(0.0, 1.5, 0.0))
	var trig := _marker(region, "Trigger", terrain.ground(HOUSE.x, HOUSE.y))
	trig.set_meta("radius", 40.0)


static func _marker(parent: Node3D, marker_name: String, pos: Vector3) -> Marker3D:
	var m := Marker3D.new()
	m.name = marker_name
	m.position = pos
	parent.add_child(m)
	return m


static func _group(parent: Node3D, group_name: String) -> Node3D:
	var node := Node3D.new()
	node.name = group_name
	parent.add_child(node)
	return node


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
