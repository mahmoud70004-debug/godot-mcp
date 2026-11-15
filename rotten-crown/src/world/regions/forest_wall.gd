@tool
class_name ForestWall
extends RefCounted
## V11: where the player can walk in the wood and the closed line around it (see
## ForestBuilder.VERGE): the walkable grid, the distance of every cell from it, and the
## collider chain on the wall line. ForestBuilder plants the giant wall trees on that line.

const WALL_HEIGHT := 4.0
## Just inside the kingdom gate, on the King's Road: the walkable ground is flooded from here.
const SPAWN := Vector2(1.0, 64.0)
## The straight run up to the citadel's front gate (the paving bends just short of it).
const GATE_APPROACH := [Vector2(125.0, 186.0), Vector2(125.0, 208.0)]
## Safety cap on the island-linking loop (slivers dropped and trails cut both take a round).
const MAX_ROUNDS := 400
## Walkable islands smaller than this (m2) are slivers, not places: dropped, not joined.
const MIN_ISLAND := 40
const MARKER_GLADE := 5.0

static var _walk := PackedByteArray()
static var _depth := PackedByteArray()
static var _links: Array = []


static func _v2(a: Variant) -> Vector2:
	if a is Vector2:
		return a
	return Vector2(float(a[0]), float(a[1]))


## 1 per 1 m cell of the wall rect the player can stand on (see VERGE), cached. Clearings no
## road reaches are joined to the rest by a straight trail (links()); slivers are dropped.
static func walk_grid() -> PackedByteArray:
	if _walk.is_empty():
		var wr := ForestBuilder.wall_rect()
		var w := int(wr.size.x)
		var h := int(wr.size.y)
		var tiers := ForestBuilder.tier_grid()
		_walk.resize(w * h)
		for i in w * h:
			_walk[i] = 1 if tiers[i] == 0 else 0
		var lines := ForestBuilder.map_road_lines()
		# The King's Road as it is really paved, and the straight run up to the citadel gate.
		lines.append([KingdomRoads.pave_line(), ForestBuilder.ROAD_CLEAR])
		lines.append([GATE_APPROACH, ForestBuilder.ROAD_CLEAR])
		for line: Array in lines:
			_stamp(line[0], float(line[1]) + ForestBuilder.VERGE, w, h, wr.position)
		# Spawn / pickup spots placed straight into the wood get a small glade of their own.
		for m: Array in ForestBuilder.EXTRA_MARKERS:
			if str(m[1]) == "":
				_stamp([m[2], m[2]], MARKER_GLADE, w, h, wr.position)
		_links.clear()
		var start := _cell(SPAWN - wr.position, w)
		var linked := 0
		var rounds := 0
		while rounds < MAX_ROUNDS:
			rounds += 1
			var seen := _flood(start, w, h)
			var link := _nearest_island(seen, w, h)
			if link.is_empty():
				break
			var a: Vector2 = link[0]
			var b: Vector2 = link[1]
			if int(link[2]) < MIN_ISLAND:
				_erase_island(_cell(b, w), w, h)
				continue
			_links.append([a + wr.position, b + wr.position])
			_stamp([a + wr.position, b + wr.position], ForestBuilder.TRAIL_CLEAR + ForestBuilder.VERGE, w, h, wr.position)
			linked += 1
		if rounds >= MAX_ROUNDS:
			push_warning("ForestWall: gave up after %d rounds (%d clearings linked): some clearings may be cut off" % [rounds, linked])
	return _walk


## The trails cut to join cut-off clearings: [[Vector2 from, Vector2 to], ...] (world x, z).
static func links() -> Array:
	walk_grid()
	return _links


static func _cell(p: Vector2, w: int) -> int:
	return int(floor(p.y)) * w + int(floor(p.x))


static func _stamp(pts: Array, r: float, w: int, h: int, origin: Vector2) -> void:
	for k in pts.size() - 1:
		var a := _v2(pts[k]) - origin
		var b := _v2(pts[k + 1]) - origin
		var n := maxi(int(ceil(a.distance_to(b) / 0.5)), 1)
		for j in n + 1:
			var c := a.lerp(b, float(j) / n)
			for iz in range(maxi(int(floor(c.y - r)), 0), mini(int(floor(c.y + r)), h - 1) + 1):
				for ix in range(maxi(int(floor(c.x - r)), 0), mini(int(floor(c.x + r)), w - 1) + 1):
					if Vector2(ix + 0.5, iz + 0.5).distance_squared_to(c) <= r * r:
						_walk[iz * w + ix] = 1


static func _neighbours(i: int, w: int, h: int) -> Array:
	var ix := i % w
	var out := []
	if ix > 0:
		out.append(i - 1)
	if ix < w - 1:
		out.append(i + 1)
	if i >= w:
		out.append(i - w)
	if i < w * (h - 1):
		out.append(i + w)
	return out


## 1 for every walkable cell joined to `start`.
static func _flood(start: int, w: int, h: int) -> PackedByteArray:
	var seen := PackedByteArray()
	seen.resize(w * h)
	seen[start] = 1
	var frontier := PackedInt32Array([start])
	while not frontier.is_empty():
		var next := PackedInt32Array()
		for i in frontier:
			for j: int in _neighbours(i, w, h):
				if _walk[j] == 1 and seen[j] == 0:
					seen[j] = 1
					next.append(j)
		frontier = next
	return seen


## The walkable island nearest to the flooded ground: [cell centre on the main ground,
## cell centre on the island, the island's size in cells], or [] when there is none.
static func _nearest_island(seen: PackedByteArray, w: int, h: int) -> Array:
	var from := PackedInt32Array()
	from.resize(w * h)
	from.fill(-1)
	var frontier := PackedInt32Array()
	for i in w * h:
		if seen[i] == 1:
			from[i] = i
			frontier.append(i)
	while not frontier.is_empty():
		var next := PackedInt32Array()
		for i in frontier:
			for j: int in _neighbours(i, w, h):
				if from[j] != -1:
					continue
				from[j] = from[i]
				if _walk[j] == 1:
					var size := 0
					var island := _flood(j, w, h)
					for k in w * h:
						size += island[k]
					var a := from[i]
					return [Vector2(a % w + 0.5, a / w + 0.5), Vector2(j % w + 0.5, j / w + 0.5), size]
				next.append(j)
		frontier = next
	return []


static func _erase_island(start: int, w: int, h: int) -> void:
	var island := _flood(start, w, h)
	for k in w * h:
		if island[k] == 1:
			_walk[k] = 0


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


## V19: the wood darkens with its depth behind the wall line: the gaps between the front giants
## show an inner darkness (like the black interiors of old retro games), not lighter trees
## behind them. Depth in cells (m) behind the walkable ground; fully dark from INNER_FULL.
const INNER_START := 2.0
const INNER_FULL := 13.0
const INNER_MIN := 0.22


static func inner_dark(c: Color, depth: int) -> Color:
	var k := lerpf(1.0, INNER_MIN, smoothstep(INNER_START, INNER_FULL, float(depth)))
	return Color(c.r * k, c.g * k, c.b * k)
