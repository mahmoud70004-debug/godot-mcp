@tool
class_name TitleBackdrop
extends Control
## Title screen picture, drawn in pixels: the Moonlit Meadows on the night of the feast.
## The knight sleeps in the grass among the swords of the war dead; on the ridge, Valdron's
## walls and the Royal Keep with its one green window (the goal of the whole game).
## Fog drifts, the grass sways, stars blink and the window breathes. Everything is flat colour on whole
## pixels (no gradients, no glow), redrawn at a capped rate.

const SKY := [Color("0b0f0d"), Color("0f1512"), Color("141b17"), Color("1a221d")]
const SKY_BANDS := [0.0, 0.3, 0.47, 0.58] ## band tops as a share of the horizon height
const HALO := Color("1d2520")
const MOON := Color("d6d2b6")
const MOON_SHADE := Color("b4b29a")
const STAR := Color("8d9483")
const HILLS := Color("131915")
const CASTLE := Color("0c100e")
const WINDOW := Color("a9c04e")
const FOG := Color(0.29, 0.322, 0.29, 0.1)
const MEADOW := Color("111711")
const MEADOW_NEAR := Color("0b100c")
const BLADE := Color("1b251b")
const BLADE_LIT := Color("344232")
const SWORD := Color("2a302b")
const SWORD_LIT := Color("5d6458")
const KNIGHT_DIR := 6
const REDRAW_FPS := 15.0

## Height of the horizon line (castle base) in pixels from the top.
@export var horizon := 238.0
## Seconds of drift; exported so a still frame can be chosen in the editor.
@export var time := 0.0

var _knight: Sprite2D
var _front: Control
var _redraw_wait := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_knight()
	resized.connect(_place_knight)
	_place_knight()


func _process(delta: float) -> void:
	time += delta
	_redraw_wait -= delta
	if _redraw_wait <= 0.0:
		_redraw_wait = 1.0 / REDRAW_FPS
		queue_redraw()
		if _front:
			_front.queue_redraw()


func _build_knight() -> void:
	# Plain property reads (no method calls): in the editor this @tool script sees the
	# non-tool SpriteSheetData as a placeholder resource.
	var data := load("res://assets/sprites/knight/knight.tres")
	if data == null or (data.get("frames") as PackedInt32Array).is_empty():
		return
	var anims: Dictionary = data.get("anims")
	if not anims.has("lie"):
		return
	var lie: Dictionary = anims["lie"]
	var b := (int(lie["start"]) + KNIGHT_DIR * int(lie["frames"])) * 6
	var frames: PackedInt32Array = data.get("frames")
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/pixel_sprite_2d.gdshader")
	mat.set_shader_parameter("palette_tex", data.get("palette"))
	mat.set_shader_parameter("tint", Color(0.78, 0.84, 0.8))
	_knight = Sprite2D.new()
	_knight.texture = data.get("texture")
	_knight.region_enabled = true
	_knight.region_rect = Rect2(frames[b], frames[b + 1], frames[b + 2], frames[b + 3])
	_knight.material = mat
	_knight.centered = false
	_knight.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# Grass blades in front of him are drawn by the child below.
	_knight.show_behind_parent = false
	add_child(_knight, false, Node.INTERNAL_MODE_FRONT)
	var front := GrassFront.new()
	front.backdrop = self
	add_child(front, false, Node.INTERNAL_MODE_FRONT)
	_front = front


func _place_knight() -> void:
	if _knight == null:
		return
	var r := _knight.region_rect.size
	_knight.position = Vector2(floorf(size.x * 0.66 - r.x * 0.5), floorf(size.y - 40.0 - r.y))


func _hash(i: int, salt: int) -> float:
	var h := (i * 374761393 + salt * 668265263) & 0x7fffffff
	h = (h ^ (h >> 13)) * 1274126177 & 0x7fffffff
	return float(h % 10000) / 10000.0


func _draw() -> void:
	var w := size.x
	var h := size.y
	_draw_sky(w)
	_draw_moon(w)
	_draw_hills(w)
	_draw_castle(w)
	_draw_fog(w, horizon - 18.0, 22.0, 0.6, FOG)
	_draw_meadow(w, h)
	_draw_swords(w)
	_draw_grass(w, h, horizon + 6.0, h - 58.0, 150, 0)
	_draw_fog(w, horizon + 30.0, 18.0, -0.4, Color(FOG, 0.07))


func _draw_sky(w: float) -> void:
	for i in SKY.size():
		var top: float = floorf(horizon * float(SKY_BANDS[i]))
		var bottom: float = horizon if i == SKY.size() - 1 else floorf(horizon * float(SKY_BANDS[i + 1]))
		draw_rect(Rect2(0, top, w, bottom - top), SKY[i])
	for i in 46:
		var sx := floorf(_hash(i, 1) * w)
		var sy := floorf(_hash(i, 2) * horizon * 0.62)
		var blink := 0.55 + 0.45 * sin(time * (0.4 + _hash(i, 3)) + float(i))
		draw_rect(Rect2(sx, sy, 1, 1), Color(STAR, 0.35 + 0.5 * blink * _hash(i, 4)))


func _moon_center(w: float) -> Vector2:
	return Vector2(floorf(w - 92.0), 62.0)


func _draw_moon(w: float) -> void:
	var c := _moon_center(w)
	_disc(c, 19.0, HALO)
	_disc(c, 15.0, MOON)
	for spot in [Vector3(-5, -3, 3), Vector3(4, 4, 4), Vector3(3, -6, 2), Vector3(-2, 7, 2)]:
		_disc(c + Vector2(spot.x, spot.y), spot.z, MOON_SHADE)


func _disc(c: Vector2, r: float, col: Color) -> void:
	var ri := int(r)
	for y in range(-ri, ri + 1):
		var half := floorf(sqrt(maxf(r * r - float(y * y), 0.0)))
		draw_rect(Rect2(c.x - half, c.y + y, half * 2.0 + 1.0, 1), col)


func _draw_hills(w: float) -> void:
	var pts := PackedVector2Array()
	pts.append(Vector2(0, horizon + 2))
	var steps := 24
	for i in steps + 1:
		var x := w * float(i) / float(steps)
		var y := horizon - 10.0 - 7.0 * sin(float(i) * 0.7) - 5.0 * sin(float(i) * 1.9 + 1.0)
		pts.append(Vector2(floorf(x), floorf(y)))
	pts.append(Vector2(w, horizon + 2))
	draw_colored_polygon(pts, HILLS)


func _draw_castle(w: float) -> void:
	var base := horizon - 4.0
	var right := w - 36.0
	# Curtain wall with crenels.
	_crenellated(Rect2(right - 270, base - 26, 262, 26), 4)
	# Towers: x offset from the right edge, width, height, roof height (0 = flat with crenels).
	var towers := [
		Vector4(268, 16, 46, 14), Vector4(214, 20, 58, 0), Vector4(168, 14, 40, 12),
		Vector4(60, 18, 52, 0), Vector4(26, 14, 38, 11),
	]
	for t: Vector4 in towers:
		var r := Rect2(right - t.x, base - t.z, t.y, t.z)
		if t.w > 0.0:
			draw_rect(r, CASTLE)
			_roof(r, t.w)
		else:
			_crenellated(r, 3)
	# The Royal Keep: the tallest mass, its spire, and the one lit window near the top.
	var keep := Rect2(right - 132, base - 104, 30, 104)
	_crenellated(Rect2(keep.position.x - 8, base - 70, keep.size.x + 16, 70), 3)
	draw_rect(keep, CASTLE)
	var spire := Rect2(keep.position.x + 8, keep.position.y - 30, 14, 30)
	draw_rect(Rect2(spire.position.x, spire.position.y + 18, spire.size.x, 12), CASTLE)
	_roof(Rect2(spire.position.x, spire.position.y + 18, spire.size.x, 12), 18.0)
	var win := Vector2(keep.position.x + 13, keep.position.y + 10)
	var pulse := 0.85 + 0.15 * sin(time * 0.8)
	draw_rect(Rect2(win, Vector2(4, 6)), Color(WINDOW, pulse))


func _crenellated(r: Rect2, step: int) -> void:
	draw_rect(Rect2(r.position.x, r.position.y + step, r.size.x, r.size.y - step), CASTLE)
	var x := r.position.x
	var on := true
	while x < r.end.x:
		var cw := minf(float(step), r.end.x - x)
		if on:
			draw_rect(Rect2(x, r.position.y, cw, step), CASTLE)
		on = not on
		x += step


func _roof(r: Rect2, height: float) -> void:
	var rows := int(height)
	for i in rows:
		var t := float(i + 1) / float(rows)
		var half := floorf((r.size.x * 0.5 + 1.0) * t)
		var cx := floorf(r.position.x + r.size.x * 0.5)
		draw_rect(Rect2(cx - half, r.position.y - height + i, half * 2.0, 1), CASTLE)


func _draw_fog(w: float, top: float, depth: float, speed: float, col: Color) -> void:
	# A flat band whose upper edge rolls; drawn as 4-pixel columns.
	var x := 0.0
	while x < w:
		var wave := sin(x * 0.021 + time * speed) * 4.0 + sin(x * 0.057 - time * speed * 1.7) * 2.0
		var y := floorf(top + wave)
		draw_rect(Rect2(x, y, 4, depth - wave), col)
		x += 4.0


func _draw_meadow(w: float, h: float) -> void:
	var near := h - 64.0
	draw_rect(Rect2(0, horizon, w, near - horizon), MEADOW)
	draw_rect(Rect2(0, near, w, h - near), MEADOW_NEAR)
	for x in range(0, int(w), 2):
		draw_rect(Rect2(x, near - 1, 1, 1), MEADOW_NEAR)


func _draw_swords(w: float) -> void:
	# Swords planted for the war dead, at slightly different depths.
	var swords := [Vector3(0.12, 268, 15), Vector3(0.42, 258, 11), Vector3(0.9, 276, 17), Vector3(0.53, 300, 22)]
	for s: Vector3 in swords:
		var x := floorf(w * s.x)
		var y := s.y
		var blade := s.z
		draw_rect(Rect2(x, y - blade, 1, blade), SWORD)
		draw_rect(Rect2(x + 1, y - blade + 2, 1, blade - 4), SWORD_LIT)
		var guard := floorf(blade * 0.36)
		draw_rect(Rect2(x - guard + 1, y - blade + 3, guard * 2.0, 1), SWORD)
		draw_rect(Rect2(x, y - blade - 2, 2, 2), SWORD)


## Grass tufts between rows `top` and `bottom`. `salt` separates the back and front layers.
func _draw_grass(w: float, _h: float, top: float, bottom: float, count: int, salt: int) -> void:
	for i in count:
		var gx := floorf(_hash(i, 11 + salt) * w)
		var depth := _hash(i, 12 + salt)
		var gy := floorf(lerpf(top, bottom, depth))
		var tall := 2.0 + floorf(depth * 7.0)
		var sway := sin(time * 1.1 + gx * 0.05) * (0.5 + depth)
		for b in 3:
			var bx := gx + float(b * 2 - 2)
			var bh := tall - float(absi(b - 1)) * 2.0
			var lean := roundf(sway * (1.0 if b != 1 else 1.4))
			draw_rect(Rect2(bx, gy - bh + 1, 1, floorf(bh * 0.5)), BLADE)
			draw_rect(Rect2(bx + lean, gy - bh, 1, ceilf(bh * 0.5)), BLADE_LIT if depth > 0.8 else BLADE)


## Draws the nearest grass over the sleeping knight.
class GrassFront:
	extends Control
	var backdrop: TitleBackdrop

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)

	func _draw() -> void:
		if backdrop == null:
			return
		var w := size.x
		var h := size.y
		for i in 90:
			var gx := floorf(backdrop._hash(i, 31) * w)
			var gy := floorf(lerpf(h - 52.0, h - 30.0, backdrop._hash(i, 32)))
			var tall := 5.0 + floorf(backdrop._hash(i, 33) * 8.0)
			var sway := roundf(sin(backdrop.time * 1.1 + gx * 0.05) * 1.5)
			for b in 3:
				var bx := gx + float(b * 2 - 2)
				var bh := tall - float(absi(b - 1)) * 3.0
				draw_rect(Rect2(bx, gy - bh + 1, 1, floorf(bh * 0.5)), MEADOW_NEAR)
				draw_rect(Rect2(bx + sway, gy - bh, 1, ceilf(bh * 0.5)), MEADOW_NEAR)
		draw_rect(Rect2(0, h - 32.0, w, 32.0), MEADOW_NEAR)
