extends Node2D
## Builds Hrafnvik from the generated data files:
##   data/map.txt      terrain grid -> static collisions
##   data/world.json   sprites, doors, interactables, named spots and zones
##   data/sprites.json sprite sizes / footprints
## The ground is painted in chunks (assets/world/ground_*.png) at `ground_res` x world
## resolution; sprites are stored at `res` x and drawn scaled down, so the world keeps
## its proportions at any camera zoom. Buildings and tree canopies fade out while the
## player walks behind them.
## Objects with a `show_if` condition are shown or hidden whenever story flags change.

const TS := 16
const NPC_SCENE := preload("res://scripts/actors/npc.gd")

const L_WORLD := 1
const L_PLAYER := 2
const L_NPC := 4
const L_INTERACT := 8
const L_DOOR := 16
const L_FEET := 32

var data := {}
var sprites := {}
var grid: PackedStringArray
var spots := {}
var zones: Array = []
var npcs := {}                 # id -> NPC node
var npc_override := {}         # id -> spot name forced by a cutscene ("" hides)

var entities: Node2D
var decals: Node2D
var reflections: Node2D
var _conditional: Array = []   # [{cond, nodes:[...], shapes:[...]}]
var _animated: Array = []      # [Sprite2D, fps, frames]
var _glows: Array = []
var _sun_shadows: Array = []   # [Sprite2D, height above the base line] cast shadows following the sun
var _sun_t := 0.0
var _flickers: Array = []      # [Sprite2D, base alpha, phase] warm interior lights
var _time := 0.0
var _tex_cache := {}
var _blocked := ""
var _occluders: Array = []     # [root, Rect2 (world, the part drawn above the base line)]
var _shadow_tex: Texture2D
var player_ref: Node2D
var _astar: AStarGrid2D


func _ready() -> void:
	data = _json("res://data/world.json")
	sprites = _json("res://data/sprites.json")
	grid = FileAccess.get_file_as_string("res://data/map.txt").split("\n")
	spots = data["spots"]
	zones = data["zones"]
	_blocked = data["blocked"]

	var water := ShaderMaterial.new()
	water.shader = load("res://assets/shaders/water.gdshader")
	var gres := float(data.get("ground_res", 1))
	for c in data["ground"]:
		var ground := Sprite2D.new()
		ground.texture = load("res://assets/world/" + str(c[2]))
		ground.centered = false
		ground.position = Vector2(c[0], c[1])
		ground.scale = Vector2.ONE / gres
		ground.z_index = -10
		ground.material = water
		add_child(ground)
	reflections = Node2D.new()
	reflections.z_index = -7
	add_child(reflections)

	decals = Node2D.new()
	decals.z_index = -5
	add_child(decals)
	entities = Node2D.new()
	entities.name = "Entities"
	entities.y_sort_enabled = true
	add_child(entities)

	_build_collisions()
	for o in data["objects"]:
		_build_object(o)
	_build_nav()
	_spawn_npcs()
	_spawn_gulls()
	Game.flags_changed.connect(refresh)
	Game.time_changed.connect(_update_glows)
	Game.time_changed.connect(_place_npcs)
	refresh()
	_update_glows()


func _json(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _tex(path: String) -> Texture2D:
	if not _tex_cache.has(path):
		_tex_cache[path] = load(path)
	return _tex_cache[path]


# ---------------------------------------------------------------- collisions
func is_blocked(tx: int, ty: int) -> bool:
	if ty < 0 or ty >= grid.size() or tx < 0 or tx >= grid[ty].length():
		return true
	return _blocked.contains(grid[ty][tx])


func _build_collisions() -> void:
	var body := StaticBody2D.new()
	body.collision_layer = L_WORLD
	body.collision_mask = 0
	add_child(body)
	# horizontal runs, then merge equal runs on consecutive rows
	var open := {}   # "x0,x1" -> Rect2i being grown
	var rects: Array[Rect2i] = []
	for y in grid.size():
		var runs := {}
		var x := 0
		var row := grid[y]
		while x < row.length():
			if _blocked.contains(row[x]):
				var x0 := x
				while x < row.length() and _blocked.contains(row[x]):
					x += 1
				runs["%d,%d" % [x0, x - 1]] = true
			else:
				x += 1
		for key in open.keys():
			if runs.has(key):
				var r: Rect2i = open[key]
				r.size.y += 1
				open[key] = r
				runs.erase(key)
			else:
				rects.append(open[key])
				open.erase(key)
		for key in runs:
			var p = key.split(",")
			open[key] = Rect2i(int(p[0]), y, int(p[1]) - int(p[0]) + 1, 1)
	for key in open:
		rects.append(open[key])
	for r in rects:
		_add_rect(body, Rect2(r.position * TS, r.size * TS))
	# map borders
	var w := int(data["width"]) * TS
	var h := int(data["height"]) * TS
	for r in [Rect2(-32, -32, w + 64, 32), Rect2(-32, h, w + 64, 32), Rect2(-32, 0, 32, h), Rect2(w, 0, 32, h)]:
		_add_rect(body, r)


func _add_rect(body: CollisionObject2D, r: Rect2) -> CollisionShape2D:
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = r.size
	cs.shape = shape
	cs.position = r.position + r.size / 2.0
	body.add_child(cs)
	return cs


# ---------------------------------------------------------------- navigation
## Tile grid for villagers' daily walks: blocked terrain plus every permanent footprint.
func _build_nav() -> void:
	_astar = AStarGrid2D.new()
	_astar.region = Rect2i(0, 0, int(data["width"]), int(data["height"]))
	_astar.cell_size = Vector2(TS, TS)
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.update()
	for y in grid.size():
		for x in grid[y].length():
			if _blocked.contains(grid[y][x]):
				_astar.set_point_solid(Vector2i(x, y))
	for o in data["objects"]:
		if not o.has("sprite") or o.has("show_if"):
			continue
		var m: Dictionary = sprites["sprites"][o["sprite"]]
		var bases: Array = m.get("bases", [m["base"]] if m.has("base") else [])
		for b in bases:
			var r := Rect2(float(o["x"]) + b[0], float(o["y"]) + b[1], b[2], b[3])
			for ty in range(int(r.position.y) / TS, int(r.end.y - 1) / TS + 1):
				for tx in range(int(r.position.x) / TS, int(r.end.x - 1) / TS + 1):
					if _astar.is_in_boundsv(Vector2i(tx, ty)):
						_astar.set_point_solid(Vector2i(tx, ty))


## World-space path between two points (falls back to a straight line).
func find_path(from: Vector2, to: Vector2) -> PackedVector2Array:
	var a := Vector2i(from / TS)
	var b := Vector2i(to / TS)
	var out := PackedVector2Array()
	if _astar != null and _astar.is_in_boundsv(a) and _astar.is_in_boundsv(b):
		var was_a := _astar.is_point_solid(a)
		var was_b := _astar.is_point_solid(b)
		_astar.set_point_solid(a, false)
		_astar.set_point_solid(b, false)
		var ids := _astar.get_id_path(a, b)
		_astar.set_point_solid(a, was_a)
		_astar.set_point_solid(b, was_b)
		for i in range(1, ids.size() - 1):
			out.append(Vector2(ids[i]) * TS + Vector2(TS, TS) * 0.5)
	out.append(to)
	return out


# ---------------------------------------------------------------- objects
func _build_object(o: Dictionary) -> void:
	var entry := {"cond": o.get("show_if", null), "nodes": [], "shapes": [], "areas": []}
	var t := str(o.get("type", "sprite"))
	if t == "door" or t == "interact":
		var area := _area(Rect2(o["x"], o["y"], o["w"], o["h"]), t == "door")
		area.set_meta("iid", o["id"])
		if t == "door":
			area.set_meta("door_to", o["to"])
		if o.has("label"):
			area.set_meta("label", o["label"])
		add_child(area)
		entry["nodes"].append(area)
		entry["areas"].append(area)
	elif o.has("sprite"):
		var m: Dictionary = sprites["sprites"][o["sprite"]]
		var oy := int(m["oy"])
		var root := Node2D.new()
		root.position = Vector2(o["x"], o["y"] + oy)
		var spr := Sprite2D.new()
		spr.texture = _tex("res://assets/sprites/%s.png" % o["sprite"])
		spr.centered = false
		spr.position = Vector2(0, -oy)
		spr.scale = Vector2.ONE / float(m.get("res", 1))
		if m.has("frames"):
			spr.hframes = int(m["frames"])
			_animated.append([spr, float(m["fps"]), int(m["frames"]), randf() * 3.0])
		root.add_child(spr)
		if o.get("reflect", false):
			_add_reflection(o, m, spr)
		if m.get("flat", false):
			decals.add_child(root)
		else:
			entities.add_child(root)
		entry["nodes"].append(root)
		if m.has("shadow"):
			entry["nodes"].append(_add_shadow(root, m["shadow"], oy))
		if (m.get("tree", false) or m.has("bases")) and int(m["h"]) > 40 and not m.get("flat", false):
			entry["nodes"].append(_add_cast_shadow(root, spr, m, oy))
		if m.has("door") and int(m["h"]) > 60:
			_add_glow(root, Vector2(float(m["door"][0]), -6.0))
		var bases: Array = []
		if o.has("block"):
			var b: Array = o["block"]
			bases.append([b[0], b[1] + 6, b[2], b[3]])
		elif m.has("bases"):
			bases = m["bases"]
		elif m.has("base"):
			bases.append(m["base"])
		if not bases.is_empty():
			var body := StaticBody2D.new()
			body.collision_layer = L_WORLD
			body.collision_mask = 0
			root.add_child(body)
			for base in bases:
				entry["shapes"].append(_add_rect(body, Rect2(base[0], base[1] - oy, base[2], base[3])))
		if m.get("tree", false) or (m.has("bases") and int(m["h"]) > 60):
			# canopy / roof area that may hide the player
			var bottom := float(oy) - 4.0
			if not m.get("tree", false):
				bottom = float(m["bases"][0][1]) + 18.0
			_occluders.append([root, Rect2(float(o["x"]) + 6.0, float(o["y"]), float(m["w"]) - 12.0, bottom)])
		if o.has("interact"):
			var ar := Rect2(o["x"] - 4, o["y"] - 2, int(m["w"]) + 8, int(m["h"]) + 6)
			if int(m["h"]) > 40:
				ar = Rect2(o["x"], o["y"] + oy - 28, int(m["w"]), 34)
			var area := _area(ar, false)
			area.set_meta("iid", o["interact"])
			add_child(area)
			entry["nodes"].append(area)
			entry["areas"].append(area)
		if o["sprite"] == "lamp":
			_add_glow(root, Vector2(5, -oy + 6))
		if m.has("light"):
			_add_light(root, m["light"], oy)
		if m.has("embers"):
			_add_embers(root, m["embers"], oy)
		if o.has("wander"):
			_wander(root, spr, float(o["wander"]))
	if entry["cond"] != null:
		_conditional.append(entry)


## Upside-down, tinted copy of boats and rocks standing in the water.
func _add_reflection(o: Dictionary, m: Dictionary, spr: Sprite2D) -> void:
	var r := Sprite2D.new()
	r.texture = spr.texture
	r.hframes = spr.hframes
	r.centered = false
	r.flip_v = true
	var res := float(m.get("res", 1))
	r.scale = Vector2(1, 0.8) / res
	var h := int(m["h"])
	var waterline := float(o["y"]) + float(m["oy"]) - 2.0
	r.position = Vector2(o["x"], waterline - (h - 1 - int(m["oy"])) * 0.8)
	r.modulate = Color(0.55, 0.75, 0.95, 0.32)
	reflections.add_child(r)
	var tw := create_tween().set_loops()
	tw.tween_property(r, "skew", 0.05, 1.6).set_trans(Tween.TRANS_SINE)
	tw.tween_property(r, "skew", -0.05, 1.6).set_trans(Tween.TRANS_SINE)


## Long shadow cast by the low northern sun: the sprite's own silhouette, flipped
## under its base line and sheared to the side, dark and translucent.
func _add_cast_shadow(root: Node2D, spr: Sprite2D, m: Dictionary, oy: int) -> Sprite2D:
	var res := float(m.get("res", 1))
	var squash := 0.46
	var s := Sprite2D.new()
	s.texture = spr.texture
	s.hframes = spr.hframes
	s.centered = false
	s.flip_v = true
	s.scale = Vector2(1.0, squash) / res
	s.skew = 0.75
	s.position = root.position + Vector2(0, -(float(m["h"]) - oy) * squash)
	s.modulate = Color(0.02, 0.04, 0.08, 0.36)
	decals.add_child(s)
	_sun_shadows.append([s, root.position.y, float(m["h"]) - oy])
	return s


## The low northern sun crosses the sky: shadows lean west in the morning, shrink at
## noon, stretch east in the evening and fade away at night.
func _update_sun() -> void:
	var h := fmod(Game.minutes / 60.0, 24.0)
	var day := clampf((h - 5.0) / 16.0, 0.0, 1.0)            # 05:00 -> 21:00
	var skew_v := lerpf(-1.05, 1.05, day)
	var length := 0.3 + 0.32 * absf(day - 0.5) * 2.0
	var alpha := 0.36 * clampf(1.0 - absf(day - 0.5) * 0.3, 0.0, 1.0)
	if h < 5.0 or h > 21.0:
		alpha = 0.08
	for e in _sun_shadows:
		var s: Sprite2D = e[0]
		var res: float = s.scale.x
		s.skew = skew_v
		s.scale.y = length * res
		s.position.y = float(e[1]) - float(e[2]) * length
		s.modulate.a = alpha


## Soft elliptical contact shadow under buildings, trees and large props.
func _add_shadow(root: Node2D, sh: Array, oy: int) -> Sprite2D:
	if _shadow_tex == null:
		var tex := GradientTexture2D.new()
		tex.width = 64
		tex.height = 64
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		var grad := Gradient.new()
		grad.set_color(0, Color(0.05, 0.06, 0.03, 0.42))
		grad.add_point(0.55, Color(0.05, 0.06, 0.03, 0.22))
		grad.set_color(grad.get_point_count() - 1, Color(0.05, 0.06, 0.03, 0.0))
		tex.gradient = grad
		_shadow_tex = tex
	var s := Sprite2D.new()
	s.texture = _shadow_tex
	s.position = root.position + Vector2(float(sh[0]), float(sh[1]) - oy)
	s.scale = Vector2(float(sh[2]) / 64.0, float(sh[3]) / 64.0)
	decals.add_child(s)
	return s


func _spawn_gulls() -> void:
	var o: Array = data.get("outdoor", [0, 0, 2400, 1472])
	for i in 5:
		var gull := Sprite2D.new()
		gull.texture = _tex("res://assets/sprites/gull.png")
		gull.hframes = 2
		gull.centered = true
		gull.z_index = 20
		add_child(gull)
		_animated.append([gull, 4.0 + i * 0.3, 2, randf()])
		var y := randf_range(62.0, 84.0) * TS
		gull.position = Vector2(randf_range(0, o[2]), y)
		var tw := create_tween().set_loops()
		var span := randf_range(30.0, 60.0)
		tw.tween_callback(func(): gull.flip_h = false)
		tw.tween_property(gull, "position", Vector2(o[2] + 40, y - randf_range(-80, 80)), span)
		tw.tween_callback(func():
			gull.position = Vector2(-40, randf_range(60.0, 86.0) * TS))
		tw.tween_interval(randf_range(2.0, 8.0))


func _area(r: Rect2, door: bool) -> Area2D:
	var area := Area2D.new()
	area.collision_layer = L_DOOR if door else L_INTERACT
	area.collision_mask = L_FEET if door else 0
	area.monitoring = door
	area.monitorable = not door
	_add_rect(area, r)
	if door:
		area.area_entered.connect(func(_a): Director.door_touched(area))
	return area


func _add_glow(root: Node2D, at: Vector2) -> void:
	var g := Sprite2D.new()
	var tex := GradientTexture2D.new()
	tex.width = 96
	tex.height = 96
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.85, 0.5, 0.55))
	grad.set_color(1, Color(1.0, 0.7, 0.3, 0.0))
	tex.gradient = grad
	g.texture = tex
	g.position = at
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	g.material = mat
	g.z_index = 5
	root.add_child(g)
	_glows.append(g)


## Warm, gently flickering pool of light (hearths, candles, lanterns).
func _add_light(root: Node2D, l: Array, oy: int) -> void:
	var g := Sprite2D.new()
	var tex := GradientTexture2D.new()
	tex.width = 128
	tex.height = 128
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.add_point(0.45, Color(1, 1, 1, 0.45))
	grad.set_color(grad.get_point_count() - 1, Color(1, 1, 1, 0))
	tex.gradient = grad
	g.texture = tex
	var r := float(l[2])
	g.scale = Vector2.ONE * (r * 2.0 / 128.0)
	g.position = Vector2(float(l[0]), float(l[1]) - oy)
	var col: Array = l[3]
	g.modulate = Color8(int(col[0]), int(col[1]), int(col[2]), int(col[3]))
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	g.material = mat
	g.z_index = 6
	root.add_child(g)
	_flickers.append([g, g.modulate.a, randf() * 10.0])


## Sparks rising from an open fire.
func _add_embers(root: Node2D, e: Array, oy: int) -> void:
	var p := CPUParticles2D.new()
	p.position = Vector2(float(e[0]), float(e[1]) - oy)
	p.amount = 10
	p.lifetime = 1.6
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(float(e[2]) * 0.5, 1.0)
	p.direction = Vector2(0, -1)
	p.spread = 22.0
	p.gravity = Vector2(0, -10)
	p.initial_velocity_min = 8.0
	p.initial_velocity_max = 18.0
	p.scale_amount_min = 1.0
	p.scale_amount_max = 1.6
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.85, 0.4, 1.0))
	ramp.add_point(0.5, Color(1.0, 0.5, 0.15, 0.8))
	ramp.set_color(ramp.get_point_count() - 1, Color(0.8, 0.2, 0.1, 0.0))
	p.color_ramp = ramp
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.material = mat
	p.z_index = 7
	root.add_child(p)


func _update_glows() -> void:
	var on := Game.hour() >= 19 or Game.hour() < 6
	for g in _glows:
		g.visible = on


func _wander(root: Node2D, spr: Sprite2D, radius: float) -> void:
	var home := root.position
	var tw := create_tween().set_loops()
	for i in 4:
		var target := home + Vector2(randf_range(-radius, radius), randf_range(-radius * 0.5, radius * 0.5))
		tw.tween_callback(func(): spr.flip_h = target.x < root.position.x)
		tw.tween_property(root, "position", target, randf_range(2.0, 4.0))
		tw.tween_interval(randf_range(1.0, 3.0))


func _process(delta: float) -> void:
	_time += delta
	_sun_t -= delta
	if _sun_t <= 0.0:
		_sun_t = 0.5
		_update_sun()
	if player_ref != null and is_instance_valid(player_ref):
		var p := player_ref.global_position
		for oc in _occluders:
			var root: Node2D = oc[0]
			var hide: bool = root.visible and p.y < root.position.y and (oc[1] as Rect2).has_point(p + Vector2(0, -8))
			var target := 0.45 if hide else 1.0
			if not is_equal_approx(root.modulate.a, target):
				root.modulate.a = move_toward(root.modulate.a, target, delta * 3.0)
	for f in _flickers:
		var g: Sprite2D = f[0]
		if g.is_visible_in_tree():
			var t: float = _time * 6.0 + f[2]
			g.modulate.a = f[1] * (0.84 + 0.1 * sin(t) + 0.06 * sin(t * 2.7 + 1.3))
	for a in _animated:
		var spr: Sprite2D = a[0]
		if spr.is_visible_in_tree():
			spr.frame = int((_time + a[3]) * a[1]) % a[2]


## Re-evaluate every conditional object and NPC placement.
func refresh() -> void:
	for e in _conditional:
		var on := Game.check(e["cond"])
		for n in e["nodes"]:
			n.visible = on
		for s in e["shapes"]:
			s.set_deferred("disabled", not on)
		for a in e["areas"]:
			for c in a.get_children():
				if c is CollisionShape2D:
					c.set_deferred("disabled", not on)
	_place_npcs()


# ---------------------------------------------------------------- spots & zones
func has_spot(name: String) -> bool:
	return spots.has(name)


func spot_pos(name: String) -> Vector2:
	var s = spots.get(name, null)
	if s == null:
		push_warning("unknown spot " + name)
		return Vector2.ZERO
	return Vector2(s["x"], s["y"])


func spot_dir(name: String) -> String:
	return spots.get(name, {}).get("dir", "down")


func zone_at(pos: Vector2) -> Dictionary:
	for z in zones:
		var r: Array = z["rect"]
		if Rect2(r[0], r[1], r[2], r[3]).has_point(pos):
			return z
	return {"id": "void", "name": "", "indoor": false, "rect": [0, 0, 0, 0], "music": ""}


func outdoor_rect() -> Rect2:
	var o: Array = data.get("outdoor", [0, 0, 116 * TS, 64 * TS])
	return Rect2(o[0], o[1], o[2], o[3])


# ---------------------------------------------------------------- NPCs
func _spawn_npcs() -> void:
	for id in Story.NPCS:
		var def: Dictionary = Story.NPCS[id]
		var n := NPC_SCENE.new()
		n.npc_id = id
		n.sheet = def.get("sheet", id)
		n.wander_radius = def.get("wander", 0.0)
		n.idle_action = def.get("action", [])
		n.world = self
		entities.add_child(n)
		npcs[id] = n


func npc_spot(id: String):
	if npc_override.has(id):
		return npc_override[id]
	for rule in Story.NPCS[id]["spots"]:
		if Game.check(rule[0]):
			return rule[1]
	return null


func _place_npcs() -> void:
	for id in npcs:
		var n = npcs[id]
		if n.scripted:
			continue
		var s = npc_spot(id)
		if s == null or s == "":
			n.set_present(false)
			n.current_spot = ""
		else:
			var was_here: bool = n.visible and n.current_spot != ""
			n.set_present(true)
			if n.current_spot != s:
				n.current_spot = s
				var target := spot_pos(s)
				var out := outdoor_rect()
				if was_here and not Game.fast and out.has_point(n.position) and out.has_point(target):
					n.travel(find_path(n.position, target), spot_dir(s))   # walks over on its own
				else:
					n.teleport(target, spot_dir(s))
				n.patrol.clear()
				for p in Story.NPCS[id].get("patrol", []):
					n.patrol.append(spot_pos(p))
