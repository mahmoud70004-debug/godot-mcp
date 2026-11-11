@tool
class_name OverworldSpec
extends RefCounted
## The kingdom layout (contract C9 in .router/PLAN.md) as a TerrainSpec.
## Coordinates follow res://data/world/kingdom_map.json (tools/test_kingdom_layout.gd
## checks the constants below against it).

const MAIN_ROAD := [Vector2(0, 10), Vector2(0, 60), Vector2(-10, 120), Vector2(5, 200), Vector2(10, 270), Vector2(20, 322)]
const FARM_TRACK := [Vector2(-10, 120), Vector2(-60, 136), Vector2(-116, 148)]
## The King's Road: kingdom gate -> citadel front gate (map road "kings_road").
const KINGS_ROAD := [Vector2(0, 60), Vector2(45, 72), Vector2(100, 112), Vector2(140, 172), Vector2(128, 198)]
## Compatibility alias: the old forest path became the King's Road (Phase 4a inc 4);
## ForestBuilder and older builders still read this name.
const FOREST_PATH := KINGS_ROAD

## Kingdom wall rect (x0, z0, x1, z1) and the gate gap (map "wall", "gate").
const WALL_MIN := Vector2(-235, 58)
const WALL_MAX := Vector2(235, 490)
const GATE := Vector2(0, 58)
const GATE_HALF_WIDTH := 8.0
## Citadel (map "citadel"): the Outer Ward blockout is built around its own origin with
## the gate on +Z (wall line z = +10) and the keep on -Z; here it is turned 180 degrees
## so its gate faces the kingdom gate (south) and its front wall runs along z = 200.
const CITADEL_RECT := Rect2(65, 195, 120, 117)
const WARD_RECT := Rect2(85, 200, 80, 50)
const KEEP_RECT := Rect2(95, 262, 60, 46)
const WARD_GATE := Vector2(125, 198)
const WARD_ORIGIN := Vector2(125, 210)
const WARD_YAW := PI
## Flat ground under the courtyard and the keep front, levelled after the road carving.
const CITADEL_PAD := Vector4(125, 228, 52, 16)
## The plains outside the wall the player may walk on (invisible barriers beyond).
const PLAINS_RECT := Rect2(-110, -60, 220, 118)


static func make() -> TerrainSpec:
	var spec := TerrainSpec.new()
	spec.min_corner = Vector2(-260.0, -70.0)
	spec.max_corner = Vector2(260.0, 450.0)
	spec.plateaus = [Vector4(-122.0, 152.0, 16.0, 14.0), Vector4(22.0, 338.0, 44.0, 24.0)]
	spec.pads = [CITADEL_PAD]
	spec.roads = [PackedVector2Array(MAIN_ROAD), PackedVector2Array(FARM_TRACK), PackedVector2Array(KINGS_ROAD)]
	spec.dry_fields = [Vector3(-95.0, 128.0, 58.0), Vector3(-8.0, 270.0, 40.0)]
	spec.forests = [Vector3(60.0, 85.0, 30.0), Vector3(110.0, 125.0, 34.0), Vector3(140.0, 180.0, 34.0)]
	# The Outer Ward courtyard and the apron before its gate are bare mud.
	spec.mud_rects = [WARD_RECT, Rect2(WARD_GATE.x - 4.0, WARD_GATE.y - 8.0, 8.0, 10.0)]
	return spec


## World position of a point given in the ward blockout's own frame (origin, gate +Z).
static func ward_to_world(local: Vector3, ward_y: float) -> Vector3:
	var turned := local.rotated(Vector3.UP, WARD_YAW)
	return Vector3(WARD_ORIGIN.x + turned.x, ward_y + turned.y, WARD_ORIGIN.y + turned.z)


## Points along a polyline every `step` metres (for placing fences, trees...).
static func sample_path(points: Array, step: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in points.size() - 1:
		var a: Vector2 = points[k]
		var b: Vector2 = points[k + 1]
		var n := maxi(1, int(a.distance_to(b) / step))
		for i in n:
			out.append(a.lerp(b, float(i) / n))
	out.append(points[points.size() - 1])
	return out
