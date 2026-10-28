@tool
class_name TerrainSpec
extends Resource
## Parameters of the kingdom terrain. Built in code by the overworld builder;
## all lengths in metres, x/z world plane.

@export var min_corner := Vector2(-260.0, -70.0)
@export var max_corner := Vector2(260.0, 450.0)
## Grid spacing of the heightfield (also the collider resolution).
@export var cell := 2.0
@export var chunk_size := 64.0
@export var seed := 7
@export var hill_amplitude := 7.0
@export var hill_frequency := 0.008
@export var detail_amplitude := 0.6
## Hills fade to y = 0 inside this circle (the castle + meadow are built flat).
@export var flat_center := Vector2(0.0, 10.0)
@export var flat_radius := 58.0
@export var flat_falloff := 45.0
## Flattened ground for villages: Vector4(x, z, radius, falloff), height = hills at centre.
@export var plateaus: Array[Vector4] = []
## Roads as xz polylines.
@export var roads: Array[PackedVector2Array] = []
@export var road_width := 3.2
## Painted zones, Vector3(x, z, radius): pale dry fields (G) and forest floor (B).
@export var dry_fields: Array[Vector3] = []
@export var forests: Array[Vector3] = []
## Rectangles painted as bare mud/road (R), e.g. the castle courtyard.
@export var mud_rects: Array[Rect2] = []
