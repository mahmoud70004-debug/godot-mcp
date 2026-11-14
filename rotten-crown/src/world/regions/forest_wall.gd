@tool
class_name ForestWall
extends RefCounted
## V11: where the player can walk in the wood and the closed line around it (see
## ForestBuilder.VERGE): the walkable grid, the distance of every cell from it, and the
## collider chain on the wall line. ForestBuilder plants the giant wall trees on that line.

const WALL_HEIGHT := 4.0

static var _walk := PackedByteArray()
static var _depth := PackedByteArray()


static func _v2(a: Variant) -> Vector2:
	if a is Vector2:
		return a
	return Vector2(float(a[0]), float(a[1]))


## 1 per 1 m cell of the wall rect the player can stand on (see VERGE), cached.
static func walk_grid() -> PackedByteArray:
	if _walk.is_empty():
		var wr := ForestBuilder.wall_rect()
		var w := int(wr.size.x)
		var h := int(wr.size.y)
		var tiers := ForestBuilder.tier_grid()
		_walk.resize(w * h)
		for i in w * h:
			_walk[i] = 1 if tiers[i] == 0 else 0
		for line: Array in ForestBuilder.road_lines():
			var pts: Array = line[0]
			var r := float(line[1]) + ForestBuilder.VERGE
			for k in pts.size() - 1:
				var a := _v2(pts[k]) - wr.position
				var b := _v2(pts[k + 1]) - wr.position
				var n := maxi(int(ceil(a.distance_to(b) / 0.5)), 1)
				for j in n + 1:
					var c := a.lerp(b, float(j) / n)
					for iz in range(maxi(int(floor(c.y - r)), 0), mini(int(floor(c.y + r)), h - 1) + 1):
						for ix in range(maxi(int(floor(c.x - r)), 0), mini(int(floor(c.x + r)), w - 1) + 1):
							if Vector2(ix + 0.5, iz + 0.5).distance_squared_to(c) <= r * r:
								_walk[iz * w + ix] = 1
	return _walk


## Cells (4-connected steps, capped at 255) from each cell to walkable ground: 0 on it, 1 for
## the wall line itself. Cached.
static func depth_grid() -> PackedByteArray:
	if _depth.is_empty():
		var wr := ForestBuilder.wall_rect()
		var w := int(wr.size.x)
		var h := int(wr.size.y)
		var walk := walk_grid()
		_depth.resize(w * h)
		_depth.fill(255)
		var frontier := PackedInt32Array()
		for i in w * h:
			if walk[i] == 1:
				_depth[i] = 0
				frontier.append(i)
		var d := 0
		while not frontier.is_empty() and d < 254:
			d += 1
			var next := PackedInt32Array()
			for i in frontier:
				var ix := i % w
				for j: int in [i - 1 if ix > 0 else -1, i + 1 if ix < w - 1 else -1, i - w, i + w]:
					if j >= 0 and j < w * h and _depth[j] == 255:
						_depth[j] = d
						next.append(j)
			frontier = next
	return _depth


static func depth_at(p: Vector2) -> int:
	var wr := ForestBuilder.wall_rect()
	var ix := int(floor(p.x - wr.position.x))
	var iz := int(floor(p.y - wr.position.y))
	if ix < 0 or iz < 0 or ix >= int(wr.size.x) or iz >= int(wr.size.y):
		return 255
	return depth_grid()[iz * int(wr.size.x) + ix]


## The unbroken collider on the wall line: every depth-1 cell, merged into boxes along x,
## grouped per ForestBuilder.NEAR_CELL so no body carries more than a few dozen shapes.
static func colliders(forest: Node3D, terrain: TerrainBuilder) -> int:
	var wr := ForestBuilder.wall_rect()
	var w := int(wr.size.x)
	var h := int(wr.size.y)
	var depth := depth_grid()
	var holder := Node3D.new()
	holder.name = "PathWalls"
	forest.add_child(holder)
	var bodies := {}
	var shapes := {}
	var count := 0
	for iz in h:
		var ix := 0
		while ix < w:
			if depth[iz * w + ix] != 1:
				ix += 1
				continue
			var x0 := ix
			while ix < w and depth[iz * w + ix] == 1 and ix - x0 < 12:
				ix += 1
			var n := ix - x0
			var c := Vector2(x0 + n * 0.5, iz + 0.5) + wr.position
			var cell := Vector2i(floori(c.x / ForestBuilder.NEAR_CELL), floori(c.y / ForestBuilder.NEAR_CELL))
			if not bodies.has(cell):
				var body := StaticBody3D.new()
				body.name = "W_%d_%d" % [cell.x, cell.y]
				holder.add_child(body)
				bodies[cell] = body
			if not shapes.has(n):
				var box := BoxShape3D.new()
				box.size = Vector3(n, WALL_HEIGHT, 1.0)
				shapes[n] = box
			var cs := CollisionShape3D.new()
			cs.shape = shapes[n]
			cs.position = Vector3(c.x, terrain.height_at(c.x, c.y) + WALL_HEIGHT * 0.5 - 0.5, c.y)
			(bodies[cell] as StaticBody3D).add_child(cs)
			count += 1
	return count
