@tool
class_name OverworldSpec
extends RefCounted
## The kingdom layout (contract C9 in .router/PLAN.md) as a TerrainSpec.

const MAIN_ROAD := [Vector2(0, 10), Vector2(0, 60), Vector2(-10, 120), Vector2(5, 200), Vector2(10, 270), Vector2(20, 322)]
const FARM_TRACK := [Vector2(-10, 120), Vector2(-60, 136), Vector2(-116, 148)]
## A short physical connection from Hollowmere to the relocated ward, not a quest route.
const WARD_APPROACH := [Vector2(3, 349), Vector2(-5, 359), Vector2(-8, 380), Vector2(-4, 398), Vector2(0, 401)]
const WARD_CENTER := Vector2(0, 420)
const WARD_PLATEAU := Vector2(0, 435)
const FOREST_PATH := [Vector2(0, 60), Vector2(45, 72), Vector2(100, 112), Vector2(140, 172), Vector2(130, 242), Vector2(82, 300), Vector2(34, 322)]


static func make() -> TerrainSpec:
	var spec := TerrainSpec.new()
	spec.min_corner = Vector2(-260.0, -70.0)
	spec.max_corner = Vector2(260.0, 500.0)
	spec.plateaus = [Vector4(-122.0, 152.0, 16.0, 14.0), Vector4(22.0, 338.0, 44.0, 24.0),
		Vector4(WARD_PLATEAU.x, WARD_PLATEAU.y, 54.0, 6.0)]
	spec.roads = [PackedVector2Array(MAIN_ROAD), PackedVector2Array(FARM_TRACK), PackedVector2Array(FOREST_PATH),
		PackedVector2Array(WARD_APPROACH)]
	spec.dry_fields = [Vector3(-95.0, 128.0, 58.0), Vector3(-8.0, 270.0, 40.0)]
	spec.forests = [Vector3(60.0, 85.0, 30.0), Vector3(110.0, 125.0, 34.0), Vector3(140.0, 180.0, 34.0),
		Vector3(132.0, 240.0, 34.0), Vector3(96.0, 292.0, 30.0)]
	# The Outer Ward courtyard and gate road are bare mud.
	spec.mud_rects = [Rect2(-40.0, 410.0, 80.0, 50.0), Rect2(-3.0, 399.0, 6.0, 12.0)]
	return spec


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
