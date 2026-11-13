@tool
class_name ForestAtlas
extends RefCounted
## The one 2048 x 640 px texture of the kingdom forest (ForestTrees, ForestFloor): leaf clumps,
## understory cards, ground patches, the green rot and the far tree impostors, painted
## in code (pixel art, cut-out alpha) so the bake stores one small image.
## Drawn with the forest shaders (assets/shaders/forest*.gdshader*).
##
## Layout (pixels): the top band (y 0-511) holds the impostors (128 x 256, ForestTrees style
## order; V7: twice the V6 64 x 128), four views per style, one per side of each crossed
## card quad: row y 0-255 seen from the tree's +Z (x 0-895) and +X (x 896-1791) sides, row
## y 256-511 from -Z and -X; the hanging moss strip at x 1792; rows 8-9 hold 64 px tiles. Mipmapped (V7, the shaders sample nearest within a level) with the cut-out
## coverage of every tile kept at each level, so far cards neither show giant pixels nor
## thin out. The impostors' light response (normal + leaf/bark) is a second, half-resolution
## texture over the impostor band (normal_texture()), so the far shader lights an impostor
## with the same moonlight model as its tree.

const WIDTH := 2048
const HEIGHT := 640
## Atlas size as a vector: UV = pixel / SIZE (component-wise).
const SIZE := Vector2(WIDTH, HEIGHT)
const TILE := 64
## Tile name -> top-left corner in tiles (64 px units).
const TILES := {
	"leaf_dark": Vector2i(0, 8), "leaf_birch": Vector2i(1, 8), "leaf_dying": Vector2i(2, 8), "fern": Vector2i(3, 8),
	"bush": Vector2i(4, 8), "bramble": Vector2i(5, 8), "weeds": Vector2i(6, 8), "moss": Vector2i(7, 8),
	"litter": Vector2i(0, 9), "litter_amber": Vector2i(1, 9), "rot": Vector2i(2, 9), "tuft": Vector2i(3, 9),
}
## The hanging moss strip (32 x 64) and the impostor column width.
const HANG := Rect2i(1792, 0, 32, 64)
const IMPOSTOR := Vector2i(128, 256)
## ForestTrees styles (impostor cells per view).
const STYLE_COUNT := 7
## The normal texture is this many times smaller than the impostor band.
const NORMAL_DIV := 2
const ROT_GREEN := Color(0.36, 0.6, 0.1)

static var _image: Image
static var _texture: ImageTexture
static var _normal_texture: ImageTexture


## The finished atlas (impostors included, mipmapped), built once.
static func texture() -> Texture2D:
	if _texture == null:
		# The textures exist before the impostors are painted: the trees they are painted
		# from already need their materials (which hold them).
		var img := image().duplicate() as Image
		var nimg := Image.create(WIDTH / NORMAL_DIV, IMPOSTOR.y * 2 / NORMAL_DIV, false, Image.FORMAT_RGBA8)
		_texture = ImageTexture.create_from_image(with_mipmaps(img))
		var nmip := nimg.duplicate() as Image
		nmip.generate_mipmaps()
		_normal_texture = ImageTexture.create_from_image(nmip)
		ForestTrees.paint_impostors(img, nimg)
		_texture.update(with_mipmaps(img))
		nimg.generate_mipmaps()
		_normal_texture.update(nimg)
	return _texture


## The impostors' light response over the impostor band (see the class comment): rgb =
## normal in the bake view (x right, y up, z towards the viewer) * 0.5 + 0.5, a = 1 leaf,
## 0 bark. Linear filtered, mipmapped.
static func normal_texture() -> Texture2D:
	texture()
	return _normal_texture


## The share of the atlas (UV) the impostor band and so the normal texture covers.
static func impostor_band() -> Vector2:
	return Vector2(1.0, float(IMPOSTOR.y * 2) / HEIGHT)


## The painted tiles without impostors (ForestTrees samples the leaf tiles from it).
static func image() -> Image:
	if _image == null:
		_image = Image.create(WIDTH, HEIGHT, false, Image.FORMAT_RGBA8)
		_image.fill(Color(0.0, 0.0, 0.0, 0.0))
		var rng := RandomNumberGenerator.new()
		rng.seed = 2718
		_leaves(_image, _rect("leaf_dark"), rng, [Color(0.14, 0.22, 0.23), Color(0.2, 0.32, 0.3), Color(0.28, 0.43, 0.38), Color(0.4, 0.55, 0.48)], 1500, 1.0)
		_leaves(_image, _rect("leaf_birch"), rng, [Color(0.22, 0.3, 0.24), Color(0.32, 0.42, 0.3), Color(0.44, 0.52, 0.36), Color(0.56, 0.62, 0.44)], 650, 0.7)
		_leaves(_image, _rect("leaf_dying"), rng, [Color(0.16, 0.12, 0.09), Color(0.26, 0.19, 0.12), Color(0.36, 0.27, 0.15), Color(0.3, 0.3, 0.18)], 520, 0.85)
		_fern(_image, _rect("fern"), rng)
		_bush(_image, _rect("bush"), rng)
		_bramble(_image, _rect("bramble"), rng)
		_weeds(_image, _rect("weeds"), rng)
		_patch(_image, _rect("moss"), rng, [Color(0.07, 0.13, 0.1), Color(0.1, 0.19, 0.13), Color(0.14, 0.26, 0.16), Color(0.19, 0.33, 0.2)], 0)
		_patch(_image, _rect("litter"), rng, [Color(0.1, 0.09, 0.09), Color(0.15, 0.13, 0.12), Color(0.2, 0.17, 0.14), Color(0.25, 0.22, 0.18)], 1)
		_patch(_image, _rect("litter_amber"), rng, [Color(0.36, 0.2, 0.08), Color(0.5, 0.3, 0.1), Color(0.26, 0.14, 0.07), Color(0.6, 0.38, 0.14)], 1)
		_rot(_image, _rect("rot"), rng)
		_tuft(_image, _rect("tuft"), rng)
		_hanging(_image, HANG, rng)
	return _image


## Atlas UV rect of a tile (u0, v0, size).
static func uv_rect(tile: String) -> Rect2:
	var r := _rect(tile)
	return Rect2(Vector2(r.position) / SIZE, Vector2(r.size) / SIZE)


## Atlas UV rect of the hanging moss strip.
static func hang_uv_rect() -> Rect2:
	return Rect2(Vector2(HANG.position) / SIZE, Vector2(HANG.size) / SIZE)


## Pixel rect of a style's impostor (style index 0..6) in one of its two views.
## Views: 0 from +Z, 1 from +X, 2 from -Z, 3 from -X (tree frame).
static func impostor_rect(style: int, view := 0) -> Rect2i:
	return Rect2i(((view % 2) * STYLE_COUNT + style) * IMPOSTOR.x, (view / 2) * IMPOSTOR.y, IMPOSTOR.x, IMPOSTOR.y)


## UV offsets from a style's +Z view to its +X view (u) and to the views of the far sides (v).
static func impostor_view_offset() -> Vector2:
	return Vector2(float(STYLE_COUNT * IMPOSTOR.x) / WIDTH, float(IMPOSTOR.y) / HEIGHT)


static func _rect(tile: String) -> Rect2i:
	var t: Vector2i = TILES[tile]
	return Rect2i(t * TILE, Vector2i(TILE, TILE))


# --- Mipmaps ----------------------------------------------------------------------

## A copy of `img` (RGBA8, no mipmaps) with its mipmap chain: colour averaged over the
## opaque texels only (no dark fringes from the empty background), alpha cut again at
## every level so each impostor cell, tile and the moss strip keeps the share of opaque
## texels it has at full size (a plain average would thin far cards out under the alpha
## scissor). Cells never mix: every region edge is a multiple of 32 px.
static func with_mipmaps(img: Image) -> Image:
	var chain := img.duplicate() as Image
	chain.generate_mipmaps()
	var data := chain.get_data()
	var regions: Array[Rect2i] = []
	for view in 4:
		for style in STYLE_COUNT:
			regions.append(impostor_rect(style, view))
	regions.append(HANG)
	for tile: String in TILES:
		regions.append(_rect(tile))
	var cover := PackedFloat32Array()
	for r in regions:
		cover.append(_coverage(data, WIDTH, r))
	var w := WIDTH
	var h := HEIGHT
	var prev := data.slice(0, w * h * 4)
	var result := prev.duplicate()
	for level in range(1, chain.get_mipmap_count() + 1):
		var nw := maxi(w >> 1, 1)
		var nh := maxi(h >> 1, 1)
		var avg := PackedFloat32Array()
		avg.resize(nw * nh)
		var out := PackedByteArray()
		out.resize(nw * nh * 4)
		for y in nh:
			for x in nw:
				var sum := Vector4.ZERO
				var a_sum := 0.0
				for k in 4:
					var sx := mini(x * 2 + (k & 1), w - 1)
					var sy := mini(y * 2 + (k >> 1), h - 1)
					var o := (sy * w + sx) * 4
					var a := prev[o + 3] / 255.0
					sum += Vector4(prev[o] * a, prev[o + 1] * a, prev[o + 2] * a, 0.0)
					a_sum += a
				var i := y * nw + x
				avg[i] = a_sum * 0.25
				if a_sum > 0.0:
					out[i * 4] = clampi(roundi(sum.x / a_sum), 0, 255)
					out[i * 4 + 1] = clampi(roundi(sum.y / a_sum), 0, 255)
					out[i * 4 + 2] = clampi(roundi(sum.z / a_sum), 0, 255)
		# Alpha: everything at >= 0.5 coverage, then per region the threshold that keeps its share.
		for i in nw * nh:
			out[i * 4 + 3] = 255 if avg[i] >= 0.5 else 0
		var scale := 1 << level
		for ri in regions.size():
			var r := regions[ri]
			var rr := Rect2i(r.position / scale, Vector2i(maxi(r.size.x / scale, 1), maxi(r.size.y / scale, 1)))
			if r.position.x % scale != 0 or r.position.y % scale != 0:
				continue
			var vals := PackedFloat32Array()
			for y in range(rr.position.y, mini(rr.end.y, nh)):
				for x in range(rr.position.x, mini(rr.end.x, nw)):
					vals.append(avg[y * nw + x])
			if vals.is_empty():
				continue
			var sorted := vals.duplicate()
			sorted.sort()
			var keep := roundi(cover[ri] * sorted.size())
			var cut := 2.0 if keep <= 0 else maxf(sorted[sorted.size() - keep], 0.001)
			for y in range(rr.position.y, mini(rr.end.y, nh)):
				for x in range(rr.position.x, mini(rr.end.x, nw)):
					var i := y * nw + x
					out[i * 4 + 3] = 255 if avg[i] >= cut else 0
		# Levels are stored one after the other.
		assert(chain.get_mipmap_offset(level) == result.size())
		result.append_array(out)
		prev = out
		w = nw
		h = nh
	return Image.create_from_data(WIDTH, HEIGHT, true, Image.FORMAT_RGBA8, result)


## Share of opaque (alpha >= 0.5) texels of a rect of an RGBA8 buffer `w` px wide.
static func _coverage(data: PackedByteArray, w: int, r: Rect2i) -> float:
	var n := 0
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if data[(y * w + x) * 4 + 3] >= 128:
				n += 1
	return float(n) / maxf(r.size.x * r.size.y, 1.0)


# --- Painting helpers -------------------------------------------------------------

static func _put(img: Image, r: Rect2i, x: float, y: float, c: Color) -> void:
	var px := int(floor(x))
	var py := int(floor(y))
	if px < r.position.x or py < r.position.y or px >= r.end.x or py >= r.end.y:
		return
	img.set_pixel(px, py, Color(c.r, c.g, c.b, 1.0))


## Filled ellipse (centre, half axes, angle).
static func _ellipse(img: Image, r: Rect2i, c: Vector2, ll: float, lw: float, ang: float, col: Color, shade_low := 0.0) -> void:
	var dx := Vector2(cos(ang), sin(ang))
	var dy := Vector2(-dx.y, dx.x)
	var ext := int(ceil(maxf(ll, lw)))
	for py in range(int(c.y) - ext, int(c.y) + ext + 1):
		for px in range(int(c.x) - ext, int(c.x) + ext + 1):
			var q := Vector2(px + 0.5, py + 0.5) - c
			var lx := q.dot(dx) / ll
			var ly := q.dot(dy) / lw
			if lx * lx + ly * ly <= 1.0:
				_put(img, r, px, py, col.darkened(shade_low) if ly > 0.35 else col)


static func _line(img: Image, r: Rect2i, a: Vector2, b: Vector2, col: Color, width := 1.0) -> void:
	var n := maxi(1, int(a.distance_to(b) * 2.0))
	for k in n + 1:
		var p := a.lerp(b, float(k) / n)
		if width <= 1.0:
			_put(img, r, p.x, p.y, col)
		else:
			_ellipse(img, r, p, width * 0.5, width * 0.5, 0.0, col)


# --- Tiles -------------------------------------------------------------------------

## A ragged clump of small leaves, lighter on top where the moon catches it.
static func _leaves(img: Image, r: Rect2i, rng: RandomNumberGenerator, shades: Array, count: int, size: float) -> void:
	var c0 := Vector2(r.position) + Vector2(r.size) * 0.5
	var s := float(r.size.x)
	for k in 7:
		var a := rng.randf() * TAU
		var reach := rng.randf_range(0.18, 0.4) * s
		_line(img, r, c0, c0 + Vector2(cos(a), sin(a)) * reach, Color(0.06, 0.05, 0.05))
	for i in count:
		var a := rng.randf() * TAU
		var rad := pow(rng.randf(), 0.62) * s * 0.46 * (0.8 + 0.2 * sin(a * 5.0 + 1.3))
		var c := c0 + Vector2(cos(a), sin(a)) * rad
		var top := 1.0 - (c.y - r.position.y) / s
		var col: Color = shades[clampi(int(top * 2.4 + rng.randf() * 1.7 - 0.4), 0, 3)]
		_ellipse(img, r, c, rng.randf_range(1.3, 2.2) * size, rng.randf_range(0.6, 1.0) * size, a + rng.randf_range(-0.9, 0.9), col, 0.3)


## Fronds from the bottom centre, each a curved midrib with paired leaflets.
static func _fern(img: Image, r: Rect2i, rng: RandomNumberGenerator) -> void:
	var base := Vector2(r.position.x + r.size.x * 0.5, r.end.y - 1)
	for f in 7:
		var ang := lerpf(-1.25, 1.25, (f + rng.randf_range(-0.3, 0.3)) / 6.0)
		var length := rng.randf_range(0.6, 0.95) * r.size.y
		var bend := rng.randf_range(0.6, 1.1) * signf(ang + 0.01)
		var prev := base
		var n := 16
		for k in range(1, n + 1):
			var t := float(k) / n
			var a := ang + bend * t * t
			var p := base + Vector2(sin(a), -cos(a)) * length * t
			var green := Color(0.14, 0.3, 0.2).lerp(Color(0.26, 0.44, 0.28), t)
			_line(img, r, prev, p, green.darkened(0.3))
			var leaflet := (1.0 - t) * 6.0 + 1.5
			var side := Vector2(cos(a), sin(a))
			_line(img, r, p, p + side * leaflet + Vector2(0.0, -leaflet * 0.4), green)
			_line(img, r, p, p - side * leaflet + Vector2(0.0, -leaflet * 0.4), green.darkened(0.15))
			prev = p


## A low dense bush: round, bottom-anchored, darker underneath.
static func _bush(img: Image, r: Rect2i, rng: RandomNumberGenerator) -> void:
	var c0 := Vector2(r.position.x + r.size.x * 0.5, r.end.y - r.size.y * 0.36)
	var shades := [Color(0.08, 0.14, 0.13), Color(0.12, 0.21, 0.18), Color(0.17, 0.29, 0.24), Color(0.23, 0.36, 0.28)]
	for i in 900:
		var a := rng.randf() * TAU
		var rad := pow(rng.randf(), 0.6) * r.size.x * 0.44
		var c := c0 + Vector2(cos(a) * rad, sin(a) * rad * 0.8)
		if c.y > r.end.y - 2:
			continue
		var top := 1.0 - (c.y - r.position.y) / r.size.y
		var col: Color = shades[clampi(int(top * 3.0 + rng.randf() * 1.4 - 0.5), 0, 3)]
		_ellipse(img, r, c, rng.randf_range(1.2, 2.0), rng.randf_range(0.7, 1.1), rng.randf() * TAU, col, 0.25)


## Thorny tangled stems with a few leaves, hugging the ground.
static func _bramble(img: Image, r: Rect2i, rng: RandomNumberGenerator) -> void:
	var stem := Color(0.2, 0.12, 0.16)
	for s in 9:
		var p := Vector2(r.position.x + rng.randf_range(4.0, r.size.x - 4.0), r.end.y - 1)
		var a := rng.randf_range(-1.4, 1.4)
		for k in 26:
			a += rng.randf_range(-0.35, 0.35) + 0.04 * signf(a)
			var q := p + Vector2(sin(a), -cos(a) * 0.75) * 2.0
			_line(img, r, p, q, stem.lightened(rng.randf_range(0.0, 0.2)))
			if k % 3 == 0:
				var side := Vector2(cos(a), sin(a)) * (1.0 if rng.randf() < 0.5 else -1.0)
				_line(img, r, q, q + side * 2.0 + Vector2(0.0, -1.0), Color(0.33, 0.24, 0.24))
			if k % 5 == 2:
				_ellipse(img, r, q + Vector2(rng.randf_range(-2.0, 2.0), -1.0), 2.0, 1.1, rng.randf() * TAU, Color(0.12, 0.2, 0.15), 0.2)
			p = q
			if p.y < r.position.y + r.size.y * 0.3:
				break


## Tall dead stalks, pale and dry, with drooping seed heads.
static func _weeds(img: Image, r: Rect2i, rng: RandomNumberGenerator) -> void:
	for s in 22:
		var p := Vector2(r.position.x + rng.randf_range(3.0, r.size.x - 3.0), r.end.y - 1)
		var h := rng.randf_range(0.45, 0.98) * r.size.y
		var lean := rng.randf_range(-0.35, 0.35)
		var col := Color(0.42, 0.42, 0.38).darkened(rng.randf_range(0.0, 0.45))
		var top := p + Vector2(lean * h, -h)
		var mid := p.lerp(top, 0.6) + Vector2(lean * h * 0.25, 0.0)
		_line(img, r, p, mid, col)
		_line(img, r, mid, top, col)
		if rng.randf() < 0.6:
			for k in 4:
				_put(img, r, top.x + rng.randf_range(-1.5, 1.5), top.y + k, col.lightened(0.15))


## A flat ground patch seen from above: irregular blob of speckles (0 moss, 1 leaves).
static func _patch(img: Image, r: Rect2i, rng: RandomNumberGenerator, shades: Array, kind: int) -> void:
	var c0 := Vector2(r.position) + Vector2(r.size) * 0.5
	var lobes: Array = []
	for k in 5:
		lobes.append([rng.randf() * TAU, rng.randf_range(0.05, 0.16)])
	for py in r.size.y:
		for px in r.size.x:
			var q := Vector2(px + 0.5, py + 0.5) + Vector2(r.position) - c0
			var a := q.angle()
			var edge := 0.4
			for l: Array in lobes:
				edge += float(l[1]) * cos(a * 2.0 + float(l[0]) * 3.0)
			var d := q.length() / (r.size.x * 0.5)
			if d > edge + rng.randf_range(-0.05, 0.05):
				continue
			if kind == 1 and rng.randf() < 0.35:
				continue
			# Clustered shades (soft clumps, not per-pixel noise).
			var n := sin(q.x * 0.45 + float(lobes[0][0]) * 4.0) * sin(q.y * 0.5 + float(lobes[1][0]) * 4.0) + rng.randf_range(-0.35, 0.35)
			var col: Color = shades[clampi(int((n + 1.0) * 2.0), 0, 3)]
			_put(img, r, r.position.x + px, r.position.y + py, col)
	if kind == 1:
		for i in 140:
			var a := rng.randf() * TAU
			var c := c0 + Vector2(cos(a), sin(a)) * pow(rng.randf(), 0.7) * r.size.x * 0.38
			_ellipse(img, r, c, rng.randf_range(1.6, 2.6), rng.randf_range(0.8, 1.3), rng.randf() * TAU, shades[rng.randi() % 4], 0.2)


## The green rot from above: branching wet veins from a swollen heart, pustules on them.
static func _rot(img: Image, r: Rect2i, rng: RandomNumberGenerator) -> void:
	var c0 := Vector2(r.position) + Vector2(r.size) * 0.5
	var dark := Color(0.12, 0.22, 0.04)
	for v in 7:
		var p := c0
		var a := rng.randf() * TAU
		var w := 2.6
		for k in 22:
			a += rng.randf_range(-0.5, 0.5)
			var q := p + Vector2(cos(a), sin(a)) * 1.6
			_line(img, r, p, q, ROT_GREEN.lerp(dark, float(k) / 22.0), w)
			w = maxf(1.0, w * 0.93)
			if k % 6 == 3:
				var b := a + rng.randf_range(0.6, 1.2) * (1.0 if rng.randf() < 0.5 else -1.0)
				var bp := q
				for j in 6:
					var bq := bp + Vector2(cos(b), sin(b)) * 1.5
					_line(img, r, bp, bq, ROT_GREEN.lerp(dark, 0.6))
					b += rng.randf_range(-0.5, 0.5)
					bp = bq
			if k % 5 == 4 and rng.randf() < 0.7:
				_ellipse(img, r, q, 1.6, 1.6, 0.0, Color(0.55, 0.78, 0.22))
			p = q
	_ellipse(img, r, c0, 5.0, 4.0, rng.randf(), Color(0.3, 0.5, 0.08))
	_ellipse(img, r, c0 + Vector2(-1.0, -1.0), 2.0, 1.6, 0.0, Color(0.62, 0.84, 0.3))


## Short pale grass blades (trampled trail edges).
static func _tuft(img: Image, r: Rect2i, rng: RandomNumberGenerator) -> void:
	for s in 40:
		var p := Vector2(r.position.x + r.size.x * 0.5 + rng.randf_range(-22.0, 22.0), r.end.y - 1)
		var h := rng.randf_range(0.2, 0.6) * r.size.y
		var lean := rng.randf_range(-0.6, 0.6)
		var col := Color(0.36, 0.4, 0.34).darkened(rng.randf_range(0.0, 0.5))
		_line(img, r, p, p + Vector2(lean * h, -h), col)


## Beard moss hanging from a branch: tapering grey-green strands.
static func _hanging(img: Image, r: Rect2i, rng: RandomNumberGenerator) -> void:
	for s in 16:
		var x := r.position.x + rng.randf_range(3.0, r.size.x - 3.0)
		var length := rng.randf_range(0.4, 1.0) * r.size.y
		var col := Color(0.28, 0.36, 0.3).darkened(rng.randf_range(0.0, 0.5))
		var y := float(r.position.y)
		var sway := rng.randf_range(-0.12, 0.12)
		while y < r.position.y + length:
			var t := (y - r.position.y) / length
			_put(img, r, x + sin(y * 0.3 + s) * 1.2 + sway * (y - r.position.y), y, col)
			if t < 0.5 and rng.randf() < 0.4:
				_put(img, r, x + 1.0, y, col.darkened(0.2))
			y += 1.0
