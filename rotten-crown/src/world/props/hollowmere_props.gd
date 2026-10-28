@tool
class_name HollowmereProps
extends RefCounted
## Hollowmere (U8) prop builders: the pumpkin harvest, the gothic village and the
## curse's body horror. Organic detail is generated straight into vertex-coloured
## batches (Batch) - one mesh per material per cell with its own visibility range,
## so hundreds of pumpkins, leaves, growths and blood pools cost a few draw calls and
## five shared materials. Architecture uses the shared textured RetroMaterials and is
## emitted as plain MeshInstance3D nodes that MeshMerger.merge_static batches.
## Everything takes an explicit RandomNumberGenerator (deterministic bake).

const FLESH_SHADER := preload("res://assets/shaders/hollowmere_flesh.gdshader")

# Palette (sRGB; vertex colours are flagged sRGB). Accents of ART_DIRECTION: pumpkin
# #c0601e, blood #5a0e0e, flesh #b07a6a.
const PUMPKINS := [Color(0.8, 0.4, 0.1), Color(0.74, 0.33, 0.07), Color(0.86, 0.48, 0.13), Color(0.66, 0.26, 0.06),
	Color(0.78, 0.44, 0.16), Color(0.7, 0.36, 0.12)]
const PALE_PUMPKIN := Color(0.78, 0.74, 0.62)
const GREEN_PUMPKIN := Color(0.4, 0.44, 0.24)
const ROT := Color(0.17, 0.1, 0.045)
const MOULD := Color(0.5, 0.52, 0.42)
const STEM := Color(0.3, 0.27, 0.12)
const LEAF_GREEN := [Color(0.13, 0.22, 0.07), Color(0.18, 0.27, 0.08), Color(0.24, 0.3, 0.09)]
const LEAF_DEAD := [Color(0.38, 0.34, 0.11), Color(0.3, 0.18, 0.07), Color(0.22, 0.13, 0.06)]
const VINE := Color(0.16, 0.2, 0.07)
const SOIL := Color(0.2, 0.14, 0.09)
const SKIN := Color(0.74, 0.6, 0.55)
const SKIN_GREY := Color(0.6, 0.56, 0.52)
const BRUISE := Color(0.42, 0.25, 0.3)
const RAW := Color(0.6, 0.14, 0.12)
const BLOOD := Color(0.35, 0.03, 0.03)
const BLOOD_DARK := Color(0.2, 0.01, 0.015)
const TOOTH := Color(0.86, 0.8, 0.6)
const GUM := Color(0.62, 0.24, 0.26)
const EYE := Color(0.86, 0.83, 0.74)
const IRIS := Color(0.22, 0.27, 0.16)
const PUPIL := Color(0.02, 0.01, 0.01)
const CHAR := Color(0.06, 0.05, 0.045)
const RAG := Color(0.2, 0.15, 0.11)
const ROPE := Color(0.42, 0.33, 0.18)
const STRAW := Color(0.58, 0.47, 0.2)
const GLASS := Color(0.03, 0.035, 0.05)
const SHUTTERS := [Color(0.22, 0.28, 0.22), Color(0.36, 0.13, 0.09), Color(0.27, 0.22, 0.16), Color(0.2, 0.22, 0.28)]
const CLOTH := [Color(0.45, 0.12, 0.09), Color(0.6, 0.54, 0.42), Color(0.32, 0.3, 0.18), Color(0.25, 0.22, 0.32)]

static var _mats: Dictionary = {}


# Materials (five shared materials for all organic detail)
# --------------------------------------------------------------------------
static func _grain() -> Texture2D:
	if _mats.has("grain"):
		return _mats["grain"]
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	noise.frequency = 0.18
	noise.seed = 31
	var gradient := Gradient.new()
	gradient.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	gradient.offsets = PackedFloat32Array([0.0, 0.3, 0.6, 0.85])
	gradient.colors = PackedColorArray([Color(0.84, 0.84, 0.84), Color(0.92, 0.92, 0.92), Color(0.97, 0.97, 0.97), Color(1, 1, 1)])
	var tex := NoiseTexture2D.new()
	tex.width = 32
	tex.height = 32
	tex.seamless = true
	tex.noise = noise
	tex.color_ramp = gradient
	_mats["grain"] = tex
	return tex


static func _vc(key: String, cull: int) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var mat := StandardMaterial3D.new()
	mat.resource_name = "hm_" + key
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.albedo_texture = _grain()
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3.ONE * 1.6
	mat.roughness = 0.92
	mat.cull_mode = cull as BaseMaterial3D.CullMode
	_mats[key] = mat
	return mat


## Pumpkins, soil, cloth, char, teeth: every matte vertex-coloured solid.
static func organic() -> StandardMaterial3D:
	return _vc("organic", BaseMaterial3D.CULL_BACK)


## Leaves, awnings, rags: double-sided vertex-coloured sheets.
static func foliage() -> StandardMaterial3D:
	return _vc("foliage", BaseMaterial3D.CULL_DISABLED)


## Wet breathing flesh and blood (COLOR.a = pulse weight).
static func flesh() -> ShaderMaterial:
	if _mats.has("flesh"):
		return _mats["flesh"]
	var mat := ShaderMaterial.new()
	mat.resource_name = "hm_flesh"
	mat.shader = FLESH_SHADER
	mat.set_shader_parameter("grain", _grain())
	_mats["flesh"] = mat
	return mat


static func _emissive(key: String, col: Color, energy: float) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var mat := StandardMaterial3D.new()
	mat.resource_name = "hm_" + key
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = energy
	mat.roughness = 1.0
	_mats[key] = mat
	return mat


## Candle-lit windows and carved pumpkin faces.
static func glow() -> StandardMaterial3D:
	return _emissive("glow", Color(1.0, 0.56, 0.2), 2.2)


## Curse sigils painted on doors and walls (ember red).
static func sigil() -> StandardMaterial3D:
	return _emissive("sigil", Color(0.85, 0.09, 0.04), 2.0)


## Dark oak for the half-timbering (same scan as RetroMaterials.wood, much darker).
static func timber() -> StandardMaterial3D:
	if _mats.has("timber"):
		return _mats["timber"]
	var mat := StandardMaterial3D.new()
	mat.resource_name = "hm_timber"
	mat.albedo_texture = load("res://assets/textures/world/brown_planks_05.png") as Texture2D
	mat.albedo_color = Color(0.3, 0.24, 0.2)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3.ONE / 1.5
	mat.roughness = 0.95
	_mats["timber"] = mat
	return mat


# --------------------------------------------------------------------------
# Small helpers
# --------------------------------------------------------------------------
static func xfm(basis: Basis, origin: Vector3) -> Transform3D:
	return Transform3D(basis, origin)


static func jit(col: Color, rng: RandomNumberGenerator, amount := 0.06) -> Color:
	var k := 1.0 + rng.randf_range(-amount, amount)
	return Color(clampf(col.r * k, 0, 1), clampf(col.g * k, 0, 1), clampf(col.b * k, 0, 1), col.a)


static func wa(col: Color, a: float) -> Color:
	return Color(col.r, col.g, col.b, a)


static func pick(list: Array, rng: RandomNumberGenerator) -> Color:
	return list[rng.randi() % list.size()]


static func body(parent: Node3D, body_name: String) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.name = body_name
	parent.add_child(b)
	return b


static func shape_box(b: StaticBody3D, size: Vector3, xf: Transform3D) -> void:
	var cs := CollisionShape3D.new()
	var s := BoxShape3D.new()
	s.size = size
	cs.shape = s
	cs.transform = xf
	b.add_child(cs)


static func shape_cyl(b: StaticBody3D, radius: float, height: float, pos: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var s := CylinderShape3D.new()
	s.radius = radius
	s.height = height
	cs.shape = s
	cs.position = pos
	b.add_child(cs)


static func shape_sphere(b: StaticBody3D, radius: float, pos: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var s := SphereShape3D.new()
	s.radius = radius
	cs.shape = s
	cs.position = pos
	b.add_child(cs)


## Irregular flat pool hugging the terrain (blood, pulp, mud, ash).
static func ground_pool(b: HollowmereBatch, mat: Material, terrain: TerrainBuilder, centre: Vector2, radius: float, ccol: Color, rcol: Color,
		rng: RandomNumberGenerator, lift := 0.04, stretch := Vector2.ONE, yaw := 0.0) -> void:
	var rim := PackedVector3Array()
	var n := 9 if radius < 0.6 else 13
	var basis := Basis(Vector3.UP, yaw)
	for k in n:
		var a := TAU * k / n
		var r := radius * rng.randf_range(0.6, 1.15)
		var off := basis * Vector3(cos(a) * r * stretch.x, 0, sin(a) * r * stretch.y)
		rim.append(terrain.ground(centre.x + off.x, centre.y + off.z) + Vector3(0, lift, 0))
	b.fan(mat, terrain.ground(centre.x, centre.y) + Vector3(0, lift + 0.01, 0), rim, ccol, rcol, Vector3.UP)


## Blood trail: drag smear plus drops from `from` to `to` (world xz).
static func blood_trail(b: HollowmereBatch, terrain: TerrainBuilder, from: Vector2, to: Vector2, rng: RandomNumberGenerator, width := 0.35) -> void:
	var mat := flesh()
	var steps := maxi(2, int(from.distance_to(to) / 0.5))
	var dir := (to - from).normalized()
	var side := Vector2(-dir.y, dir.x)
	var pts := PackedVector3Array()
	var cols := PackedColorArray()
	var hints := PackedVector3Array()
	for k in steps + 1:
		var f := float(k) / steps
		var p := from.lerp(to, f) + side * sin(f * 9.0 + from.x) * 0.25
		var w := width * (0.6 + 0.4 * sin(f * 23.0)) * (1.0 - f * 0.4)
		for s: float in [-1.0, 1.0]:
			var q := p + side * s * w
			pts.append(terrain.ground(q.x, q.y) + Vector3(0, 0.035, 0))
			hints.append(Vector3.UP)
			cols.append(BLOOD_DARK if s < 0.0 else BLOOD)
	b.grid(mat, pts, 2, steps + 1, false, cols, hints)
	for k in int(steps * 0.6):
		var p := from.lerp(to, rng.randf()) + side * rng.randf_range(-0.8, 0.8)
		ground_pool(b, mat, terrain, p, rng.randf_range(0.08, 0.2), BLOOD, BLOOD_DARK, rng, 0.04)


## Curse sigil: the rotten crown inside a broken ring, with drips. xf: centre on the
## painted surface, local +z out of the surface, +y up.
static func curse_sigil(b: HollowmereBatch, xf: Transform3D, size: float, rng: RandomNumberGenerator) -> void:
	var mat := sigil()
	var col := Color(1, 1, 1)
	var th := size * 0.07
	var r := size * 0.5
	var segs := 10
	var skip := rng.randi() % segs
	for k in segs:
		if k == skip:
			continue
		var a0 := TAU * k / segs
		var a1 := TAU * (k + 1) / segs
		b.beam(mat, xf * Vector3(cos(a0) * r, sin(a0) * r, 0.0), xf * Vector3(cos(a1) * r, sin(a1) * r, 0.0), th, 0.02, col)
	# Crown: base bar and three spikes.
	var base_y := -r * 0.2
	b.beam(mat, xf * Vector3(-r * 0.5, base_y, 0.005), xf * Vector3(r * 0.5, base_y, 0.005), th, 0.02, col)
	for k in 3:
		var x := (k - 1) * r * 0.42
		var tip := Vector3(x, base_y + r * (0.55 if k == 1 else 0.4), 0.005)
		b.beam(mat, xf * Vector3(x - r * 0.12, base_y, 0.005), xf * tip, th, 0.02, col)
		b.beam(mat, xf * Vector3(x + r * 0.12, base_y, 0.005), xf * tip, th, 0.02, col)
	# A single vertical eye slit under the crown, and paint running down.
	b.beam(mat, xf * Vector3(0, -r * 0.35, 0.005), xf * Vector3(0, -r * 0.7, 0.005), th * 1.3, 0.02, col)
	for k in 4:
		var x := rng.randf_range(-r, r)
		var y0 := -sqrt(maxf(r * r - x * x, 0.0))
		b.beam(mat, xf * Vector3(x, y0, 0.004), xf * Vector3(x, y0 - rng.randf_range(0.1, 0.35) * size, 0.004), th * 0.7, 0.02, col)


## Bloody hand print on a surface (xf as for curse_sigil).
static func hand_print(b: HollowmereBatch, xf: Transform3D, size: float, rng: RandomNumberGenerator) -> void:
	var mat := flesh()
	var rim := PackedVector3Array()
	for k in 8:
		var a := TAU * k / 8
		rim.append(xf * Vector3(cos(a) * size * 0.32, sin(a) * size * 0.38, 0.0))
	var nrm := (xf.basis * Vector3(0, 0, 1)).normalized()
	b.fan(mat, xf * Vector3(0, 0, 0.003), rim, BLOOD, BLOOD_DARK, nrm)
	for f in 5:
		var a := lerpf(-0.9, 0.9, f / 4.0) + rng.randf_range(-0.1, 0.1)
		var s := xf * Vector3(sin(a) * size * 0.3, cos(a) * size * 0.3, 0.002)
		var e := xf * Vector3(sin(a) * size * (0.75 if f > 0 else 0.55), cos(a) * size * (0.8 if f > 0 else 0.45) - (0.2 * size if f == 0 else 0.0), 0.002)
		b.beam(mat, s, e, size * 0.1, 0.008, BLOOD)
	# Smear dragging down from the palm.
	b.beam(mat, xf * Vector3(0, -size * 0.3, 0.002), xf * Vector3(rng.randf_range(-0.1, 0.1), -size * rng.randf_range(1.0, 2.0), 0.002), size * 0.35, 0.006, BLOOD_DARK)


# --------------------------------------------------------------------------
# Pumpkins
# --------------------------------------------------------------------------
## Random parameters of one field pumpkin; `kind` 0 plain, 1 pale, 2 green, 3 rotting split,
## 4 flesh (mouth/eyes), 5 wrong growth.
static func roll_pumpkin(rng: RandomNumberGenerator, flesh_chance := 0.08) -> Dictionary:
	var roll := rng.randf()
	var kind := 0
	if roll < 0.08:
		kind = 1
	elif roll < 0.14:
		kind = 2
	elif roll < 0.2:
		kind = 3
	elif roll < 0.2 + flesh_chance:
		kind = 4
	elif roll < 0.23 + flesh_chance:
		kind = 5
	var size := rng.randf_range(0.5, 1.0)
	if rng.randf() < 0.08:
		size = rng.randf_range(1.15, 1.6)
	if kind >= 4:
		size = maxf(size, rng.randf_range(0.8, 1.3))
	var tint: Color = PUMPKINS[rng.randi() % PUMPKINS.size()]
	if kind == 1:
		tint = PALE_PUMPKIN
	elif kind == 2:
		tint = GREEN_PUMPKIN.lerp(tint, rng.randf_range(0.0, 0.4))
	return {"kind": kind, "size": size, "tint": jit(tint, rng), "ribs": rng.randi_range(6, 9),
		"squash": rng.randf_range(0.62, 0.88) if kind != 3 else rng.randf_range(0.42, 0.55),
		"rot": rng.randf_range(0.0, 0.35) if kind != 3 else 1.1, "seed": rng.randi(), "yaw": rng.randf() * TAU,
		"tilt": rng.randf_range(-0.15, 0.15)}


## Ribbed pumpkin standing on `base`. lod 0 = near (2-3 vertices per lobe), 1 = far.
static func pumpkin(b: HollowmereBatch, base: Vector3, p: Dictionary, lod: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(p["seed"])
	var size: float = p["size"]
	var kind: int = p["kind"]
	var ribs: int = p["ribs"]
	var squash: float = p["squash"]
	var tint: Color = p["tint"]
	var rot: float = p["rot"]
	var is_flesh := kind >= 4 and lod == 0
	var mat: Material = flesh() if is_flesh else organic()
	var per := 1 if lod > 0 else (3 if size > 1.3 else 2)
	var segs := ribs * per
	var rings := 3 if lod > 0 else (6 if size > 0.9 else 5)
	var depth := rng.randf_range(0.08, 0.16)
	var basis := Basis(Vector3.UP, float(p["yaw"])) * Basis(Vector3.RIGHT, float(p["tilt"]))
	var r := size * 0.5
	var hy := r * squash
	var centre := base + Vector3(0, hy * 0.86 - size * 0.03, 0)
	var rot_dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.8, 0.3), rng.randf_range(-1, 1)).normalized()
	var skin_dir := Vector3(0, 0.1, 1).normalized()
	var off := 0.5 if lod > 0 else 0.0
	var pts := PackedVector3Array()
	var cols := PackedColorArray()
	var hints := PackedVector3Array()
	var lumpy := kind == 3 or kind == 5
	for ri in rings + 1:
		var v := float(ri) / rings
		var phi := v * PI
		var ring_r := pow(sin(phi), 0.8)
		var y := -cos(phi) - 0.28 * smoothstep(0.72, 1.0, v)
		y = maxf(y, -0.86)
		for ci in segs:
			var th := (float(ci) + off) / segs * TAU
			var s := absf(sin(th * ribs * 0.5))
			var rib := 1.0 - depth * (1.0 - sqrt(s))
			var d := Vector3(cos(th) * ring_r, y, sin(th) * ring_r)
			var k := 1.0
			if lumpy:
				k += 0.16 * HollowmereBatch.noise.get_noise_3d(d.x * 2.0 + p["seed"] % 97, d.y * 2.0, d.z * 2.0)
			var lp := Vector3(d.x * r * rib, d.y * hy, d.z * r * rib) * k
			pts.append(centre + basis * lp)
			hints.append(basis * d)
			var shade := (0.6 + 0.4 * s) * lerpf(0.5, 1.0, clampf(v * 1.7, 0.0, 1.0))
			var cc := Color(tint.r * shade, tint.g * shade, tint.b * shade, 0.0)
			if v > 0.82:
				cc = cc.lerp(Color(0.45, 0.42, 0.16), (v - 0.82) * 2.5)
			var nd := d.normalized()
			if rot > 0.0 and nd.dot(rot_dir) > 1.0 - rot:
				var w := clampf((nd.dot(rot_dir) - (1.0 - rot)) * 4.0, 0.0, 1.0)
				cc = cc.lerp(MOULD if (ci * 7 + ri * 3) % 11 == 0 else ROT, w)
			if kind >= 4:
				var w2 := smoothstep(0.1, 0.75, nd.dot(skin_dir))
				var sk := SKIN.lerp(BRUISE, 0.5 + 0.5 * sin(th * 3.0 + v * 5.0)) if (ci + ri) % 5 == 0 else SKIN
				cc = cc.lerp(sk * shade * 1.1, w2)
				cc.a = w2 * 0.9 if is_flesh else 0.0
			cols.append(cc)
	b.grid(mat, pts, segs, rings + 1, true, cols, hints)
	# Curled stem.
	var top := centre + basis * Vector3(0, hy * 0.7, 0)
	var bend := basis * Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized()
	var path := PackedVector3Array([top - Vector3(0, size * 0.03, 0), top + Vector3(0, size * 0.13, 0) + bend * size * 0.03])
	var radii := PackedFloat32Array([size * 0.065, size * 0.05])
	if lod == 0:
		path.append(top + Vector3(0, size * 0.18, 0) + bend * size * 0.12)
		radii.append(size * 0.03)
	var stem_col := ROT if kind == 3 else STEM
	b.tube(organic(), path, radii, 4 if lod == 0 else 3, stem_col, stem_col.darkened(0.3))
	if lod > 0:
		return
	var fwd := basis * Vector3(0, 0, 1)
	if kind == 3:
		_split_open(b, centre, basis, r, hy, rng)
	elif kind == 4:
		mouth(b, centre + fwd * r * 0.88 + Vector3(0, -hy * 0.1, 0), basis, size * 0.5, rng)
		for e in rng.randi_range(1, 3):
			var a := rng.randf_range(-0.7, 0.7)
			var ed := basis * Vector3(sin(a), rng.randf_range(0.25, 0.55), cos(a)).normalized()
			eye(b, centre + Vector3(ed.x * r * 0.9, ed.y * hy * 0.95, ed.z * r * 0.9), ed, size * rng.randf_range(0.07, 0.11), rng)
	elif kind == 5:
		_wrong_growth(b, centre, basis, r, hy, rng)


static func _split_open(b: HollowmereBatch, centre: Vector3, basis: Basis, r: float, hy: float, rng: RandomNumberGenerator) -> void:
	var mat := organic()
	# Gaping wet split across the top: dark cavity, stringy pulp, seeds spilling out.
	var gash := basis * Vector3(1, 0, 0)
	var top := centre + Vector3(0, hy * 0.75, 0)
	b.blob(mat, top, basis, Vector3(r * 0.55, hy * 0.18, r * 0.22), 8, 3, Color(0.08, 0.03, 0.01))
	for k in 5:
		var p := top + gash * rng.randf_range(-r * 0.4, r * 0.4)
		b.beam(mat, p, p + Vector3(rng.randf_range(-0.1, 0.1), -hy * 0.5, rng.randf_range(-0.1, 0.1)), 0.03, 0.03, Color(0.7, 0.42, 0.1))
	for k in 7:
		var a := rng.randf() * TAU
		var sp := centre + Vector3(cos(a) * r * rng.randf_range(0.9, 1.5), -hy * 0.8, sin(a) * r * rng.randf_range(0.9, 1.5))
		b.box(mat, xfm(Basis(Vector3.UP, a), sp), Vector3(0.05, 0.015, 0.03), Color(0.82, 0.76, 0.55))


## Human mouth: lips ring, crooked teeth, dark gullet. `fwd` along basis z.
static func mouth(b: HollowmereBatch, at: Vector3, basis: Basis, size: float, rng: RandomNumberGenerator) -> void:
	var mat := flesh()
	var w := size * rng.randf_range(0.55, 0.8)
	var h := size * rng.randf_range(0.16, 0.3)
	b.blob(mat, at - basis * Vector3(0, 0, size * 0.15), basis, Vector3(w * 0.9, h * 0.9, size * 0.13), 8, 4, wa(Color(0.3, 0.04, 0.05), 0.0))
	var ring := PackedVector3Array()
	var rad := PackedFloat32Array()
	for k in 13:
		var a := TAU * k / 12
		ring.append(at + basis * Vector3(cos(a) * w, sin(a) * h, size * 0.02))
		rad.append(size * 0.05)
	b.tube(mat, ring, rad, 4, wa(GUM, 0.6))
	var teeth := rng.randi_range(6, 9)
	for row: float in [1.0, -1.0]:
		for k in teeth:
			if rng.randf() < 0.12:
				continue  # missing tooth
			var f := (k + 0.5) / teeth * 2.0 - 1.0
			var x := f * w * 0.85
			var y := row * h * 0.62 * sqrt(maxf(1.0 - f * f, 0.15))
			var tw := w * 1.7 / teeth
			var tt := Basis(Vector3(0, 0, 1), rng.randf_range(-0.25, 0.25))
			b.box(mat, xfm(basis * tt, at + basis * Vector3(x, y - row * size * 0.05, size * 0.06)),
				Vector3(tw * 0.8, size * rng.randf_range(0.1, 0.15), size * 0.06), wa(jit(TOOTH, rng, 0.12), 0.0))


static func eye(b: HollowmereBatch, at: Vector3, dir: Vector3, radius: float, rng: RandomNumberGenerator) -> void:
	var mat := flesh()
	var basis := Basis.looking_at(-dir, Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT)
	b.blob(mat, at, basis, Vector3.ONE * radius, 7, 5, wa(EYE, 0.3), 0.0, 0.0, func(d: Vector3, _k: float) -> Color:
		return wa(EYE.lerp(RAW, clampf(-d.z * 0.5 + 0.1, 0.0, 0.6)), 0.3))
	var look := (dir + Vector3(rng.randf_range(-0.3, 0.3), rng.randf_range(-0.3, 0.1), rng.randf_range(-0.3, 0.3))).normalized()
	b.blob(mat, at + look * radius * 0.82, basis, Vector3(radius * 0.48, radius * 0.48, radius * 0.25), 6, 3, wa(IRIS, 0.0))
	b.blob(mat, at + look * radius * 0.98, basis, Vector3(radius * 0.22, radius * 0.22, radius * 0.1), 5, 2, wa(PUPIL, 0.0))
	# Swollen lid.
	b.blob(mat, at + Vector3(0, radius * 0.55, 0) + dir * radius * 0.2, basis, Vector3(radius * 1.1, radius * 0.45, radius * 0.9), 7, 3, wa(BRUISE, 0.5))


## Tumour lobes, a hand pushing out of the rind, teeth along the seam.
static func _wrong_growth(b: HollowmereBatch, centre: Vector3, basis: Basis, r: float, hy: float, rng: RandomNumberGenerator) -> void:
	var mat := flesh()
	for k in rng.randi_range(2, 4):
		var a := rng.randf() * TAU
		var d := Vector3(cos(a), rng.randf_range(-0.2, 0.6), sin(a)).normalized()
		var rr := r * rng.randf_range(0.3, 0.5)
		b.blob(mat, centre + Vector3(d.x * r * 0.85, d.y * hy * 0.9, d.z * r * 0.85), basis, Vector3(rr, rr * 0.85, rr), 7, 5,
			wa(SKIN, 0.9), 0.25, rng.randf() * 10.0, func(dd: Vector3, kk: float) -> Color:
				return wa(SKIN.lerp(RAW if kk > 1.08 else BRUISE, clampf(absf(kk - 1.0) * 4.0, 0.0, 1.0)), 0.9))
	# A hand pushing out of the rind.
	var a2 := rng.randf() * TAU
	var out := Vector3(cos(a2), 0.5, sin(a2)).normalized()
	var wrist := centre + Vector3(out.x * r * 0.9, out.y * hy, out.z * r * 0.9)
	var palm := wrist + out * r * 0.35
	b.tube(mat, PackedVector3Array([wrist - out * 0.05, palm]), PackedFloat32Array([r * 0.12, r * 0.1]), 5, wa(SKIN_GREY, 0.5))
	for f in 4:
		var side := out.cross(Vector3.UP).normalized()
		var fs := palm + side * (f - 1.5) * r * 0.07
		var fe := fs + out * r * 0.25 + Vector3(0, -r * 0.08, 0) + side * (f - 1.5) * r * 0.05
		b.tube(mat, PackedVector3Array([fs, fe, fe + Vector3(0, -r * 0.12, 0) + out * r * 0.05]), PackedFloat32Array([r * 0.035, r * 0.03, r * 0.02]), 3, wa(SKIN_GREY, 0.3))


## Glowing carved face (jack-o'-lantern) on the +z side.
static func carve_face(b: HollowmereBatch, centre: Vector3, basis: Basis, r: float, hy: float) -> void:
	var mat := glow()
	var col := Color(1, 1, 1)
	var nrm := (basis * Vector3(0, 0, 1)).normalized()
	var z := r * 0.99
	for sx: float in [-1.0, 1.0]:
		var e := PackedVector3Array([centre + basis * Vector3(sx * r * 0.42, hy * 0.08, z * 0.92), centre + basis * Vector3(sx * r * 0.12, hy * 0.1, z),
			centre + basis * Vector3(sx * r * 0.28, hy * 0.42, z * 0.97)])
		b.fan(mat, (e[0] + e[1] + e[2]) / 3.0 + nrm * 0.005, e, col, col, nrm)
	var mouth := PackedVector3Array()
	for k in 9:
		var f := k / 8.0 * 2.0 - 1.0
		mouth.append(centre + basis * Vector3(f * r * 0.55, -hy * (0.18 + 0.12 * (k % 2)), z * (0.96 - f * f * 0.1)))
	for k in 9:
		var f := 1.0 - k / 8.0 * 2.0
		mouth.append(centre + basis * Vector3(f * r * 0.45, -hy * (0.42 + 0.08 * (k % 2)), z * (0.94 - f * f * 0.12)))
	b.fan(mat, centre + basis * Vector3(0, -hy * 0.32, z) + nrm * 0.005, mouth, col, col, nrm)


## Palmate pumpkin leaf, cupped and drooping.
static func leaf(b: HollowmereBatch, pos: Vector3, size: float, yaw: float, tilt: float, col: Color, edge: Color) -> void:
	var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, tilt)
	var rim := PackedVector3Array()
	for k in 10:
		var a := TAU * k / 10.0
		var lobe := 0.6 + 0.4 * absf(cos(a * 2.5))
		var rr := size * lobe
		rim.append(pos + basis * Vector3(cos(a) * rr, -0.35 * rr * rr / maxf(size, 0.01) + 0.05 * size, sin(a) * rr))
	b.fan(foliage(), pos + basis * Vector3(0, 0.08 * size, 0), rim, col, edge, basis * Vector3.UP)


# --------------------------------------------------------------------------
# Field furniture: dead tree, zig-zag fence, scarecrows, cages
# --------------------------------------------------------------------------
## Gnarled dead tree into `tb` (bark, textured). Returns hang points (branch tips) for cages.
static func dead_tree(tb: HollowmereBatch, base: Vector3, height: float, lean: Vector3, rng: RandomNumberGenerator) -> Array[Vector3]:
	var bark := RetroMaterials.bark()
	var hangs: Array[Vector3] = []
	var l := Vector3(lean.x, 0, lean.z).normalized()
	var side := Vector3.UP.cross(l)
	var r0 := height * 0.055
	var trunk := PackedVector3Array()
	var radii := PackedFloat32Array()
	var p := base - Vector3(0, 0.3, 0)
	var steps := 8
	for k in steps + 1:
		var f := float(k) / steps
		trunk.append(p)
		radii.append(r0 * lerpf(1.25, 0.45, f) * (1.4 if k == 0 else 1.0))
		var dir := (Vector3.UP + l * (0.15 + f * 0.5) + side * sin(f * 5.0 + rng.randf()) * 0.35).normalized()
		p += dir * height * 0.68 / steps
	tb.tube(bark, trunk, radii, 7, Color(1, 1, 1))
	for k in 6:
		var a := TAU * k / 6.0 + rng.randf_range(-0.3, 0.3)
		var o := Vector3(cos(a), 0, sin(a))
		tb.tube(bark, PackedVector3Array([base + Vector3(0, r0 * 2.2, 0) + o * r0 * 0.3, base + o * r0 * 1.8 + Vector3(0,
				r0 * 0.4, 0), base + o * r0 * rng.randf_range(3.0, 4.2) - Vector3(0, 0.15, 0)]),
			PackedFloat32Array([r0 * 0.6, r0 * 0.42, r0 * 0.1]), 5, Color(1, 1, 1))
	var limbs := 4
	for i in limbs:
		var q: Vector3 = trunk[rng.randi_range(4, steps)]
		var a := TAU * i / limbs + rng.randf_range(-0.4, 0.4)
		var dir := (Vector3(cos(a), 0, sin(a)) * 0.9 + Vector3.UP * rng.randf_range(0.4, 1.0)).normalized()
		var path := PackedVector3Array([q])
		var rr := PackedFloat32Array([r0 * 0.55])
		var lr := r0 * 0.55
		for k in 6:
			q += dir * height * 0.085
			lr *= 0.78
			path.append(q)
			rr.append(lr)
			dir = (dir + Vector3(rng.randf_range(-0.3, 0.3), -0.12, rng.randf_range(-0.3, 0.3))).normalized()
			if k >= 2 and rng.randf() < 0.6:
				var td := (dir + Vector3(rng.randf_range(-0.8, 0.8), rng.randf_range(-0.2, 0.7), rng.randf_range(-0.8, 0.8))).normalized()
				var tp := q + td * height * rng.randf_range(0.06, 0.12)
				tb.tube(bark, PackedVector3Array([q, tp, tp + (td + Vector3(0, 0.4, 0)).normalized() * height * 0.05]), PackedFloat32Array([lr * 0.6, lr * 0.3, 0.01]), 3, Color(1, 1, 1))
		tb.tube(bark, path, rr, 5, Color(1, 1, 1))
		hangs.append(path[3])
	return hangs


## Zig-zag split-rail ("worm") fence along `pts` (world xz). skip(p: Vector2) leaves gaps.
static func zigzag_fence(tb: HollowmereBatch, terrain: TerrainBuilder, pts: PackedVector2Array, broken: float, rng: RandomNumberGenerator, skip := Callable()) -> void:
	var wood := RetroMaterials.wood()
	var white := Color(1, 1, 1)
	var joints: Array[Vector3] = []
	var flip := 1.0
	for k in pts.size():
		var a := pts[maxi(k - 1, 0)]
		var c := pts[mini(k + 1, pts.size() - 1)]
		var dir := (c - a).normalized()
		var q := pts[k] + Vector2(-dir.y, dir.x) * 0.45 * flip
		flip = -flip
		joints.append(terrain.ground(q.x, q.y))
	for k in joints.size() - 1:
		var a := joints[k]
		var c := joints[k + 1]
		var mid := (pts[k] + pts[k + 1]) * 0.5
		if skip.is_valid() and bool(skip.call(mid)):
			continue
		var d := (c - a)
		var ext := d.normalized() * 0.3
		var rails := 4
		for h in rails:
			if rng.randf() < broken * 0.6:
				continue
			var y := 0.22 + h * 0.27
			var s := a - ext + Vector3(0, y + (0.07 if k % 2 == 0 else 0.0), 0)
			var e := c + ext + Vector3(0, y + (0.0 if k % 2 == 0 else 0.07), 0)
			if rng.randf() < broken:
				e.y = c.y + 0.08  # one end fallen to the ground
			tb.beam(wood, s, e, rng.randf_range(0.09, 0.12), rng.randf_range(0.1, 0.14), white, rng.randf_range(-0.3, 0.3))
		# Crossed stakes holding the joint.
		if k % 2 == 0 or rng.randf() < 0.3:
			var nrm := Vector3(-d.z, 0, d.x).normalized()
			for s: float in [-1.0, 1.0]:
				var foot := a + nrm * s * 0.35 - Vector3(0, 0.1, 0)
				var tip := a - nrm * s * 0.25 + Vector3(0, 1.55, 0)
				tb.beam(wood, foot, tip, 0.08, 0.08, white, rng.randf())


## A villager stitched to a scarecrow post: rags, grey skin, rope, nails, a sewn head.
static func stitched_scarecrow(parent: Node3D, tb: HollowmereBatch, b: HollowmereBatch, terrain: TerrainBuilder, xz: Vector2, yaw: float, rng: RandomNumberGenerator, pumpkin_head := false) -> void:
	var base := terrain.ground(xz.x, xz.y)
	var basis := Basis(Vector3.UP, yaw) * Basis(Vector3(0, 0, 1), rng.randf_range(-0.06, 0.06))
	var xf := Transform3D(basis, base)
	var wood := timber()
	var white := Color(1, 1, 1)
	var fl := flesh()
	var org := organic()
	tb.box(wood, xf * xfm(Basis.IDENTITY, Vector3(0, 1.25, 0)), Vector3(0.16, 2.9, 0.16), white)
	tb.box(wood, xf * xfm(Basis(Vector3(0, 0, 1), rng.randf_range(-0.08, 0.08)), Vector3(0, 2.15, 0.02)), Vector3(2.0, 0.13, 0.13), white)
	var bd := body(parent, "ScarecrowPost")
	shape_box(bd, Vector3(0.3, 2.8, 0.3), xf * xfm(Basis.IDENTITY, Vector3(0, 1.4, 0)))
	var skin := jit(SKIN_GREY, rng)
	var slump := rng.randf_range(0.05, 0.2)
	# Torso hanging slightly forward of the post.
	var chest := xf * Vector3(0, 1.7, 0.2)
	b.blob(fl, chest, basis, Vector3(0.22, 0.36, 0.14), 8, 5, wa(skin, 0.4), 0.08, rng.randf() * 10.0, func(d: Vector3, _k: float) -> Color:
		return wa(skin.lerp(BRUISE, clampf(-d.y, 0.0, 0.6)), 0.4))
	# Torn shirt panels, and the Y-incision sewn shut with black thread.
	b.blob(org, xf * Vector3(0, 1.48, 0.22), basis, Vector3(0.24, 0.22, 0.16), 8, 4, jit(RAG, rng))
	var seam_top := xf * Vector3(0, 1.98, 0.34)
	var seam_bot := xf * Vector3(0, 1.55, 0.36)
	b.beam(fl, seam_top, seam_bot, 0.03, 0.02, wa(RAW, 0.0))
	for k in 6:
		var p := seam_top.lerp(seam_bot, (k + 0.5) / 6.0)
		b.box(org, xfm(basis, p + basis * Vector3(0, 0, 0.01)), Vector3(0.08, 0.012, 0.012), Color(0.03, 0.02, 0.02))
	b.beam(fl, xf * Vector3(0, 1.45, 0.33), xf * Vector3(0.05, 0.9, 0.08), 0.05, 0.02, wa(BLOOD_DARK, 0.0))
	# Arms lashed along the crossbar, palms nailed, fingers hanging.
	for sx: float in [-1.0, 1.0]:
		var sh := xf * Vector3(sx * 0.22, 1.98, 0.14)
		var el := xf * Vector3(sx * 0.55, 2.1, 0.1)
		var wr := xf * Vector3(sx * 0.85, 2.14 - slump * 0.3, 0.09)
		b.tube(fl, PackedVector3Array([sh, el, wr]), PackedFloat32Array([0.07, 0.055, 0.045]), 5, wa(skin, 0.2))
		b.blob(org, xf * Vector3(sx * 0.42, 2.06, 0.13), basis, Vector3(0.14, 0.08, 0.09), 6, 3, jit(RAG, rng))
		for rp: float in [0.5, 0.82]:
			b.blob(org, xf * Vector3(sx * rp, 2.13, 0.08), basis, Vector3(0.03, 0.09, 0.09), 5, 3, ROPE)
		var palm := wr + basis * Vector3(sx * 0.1, -0.05, 0.0)
		b.box(fl, xfm(basis, palm), Vector3(0.1, 0.12, 0.04), wa(skin, 0.0))
		b.box(organic(), xfm(basis, palm + basis * Vector3(0, 0, 0.05)), Vector3(0.03, 0.03, 0.12), Color(0.16, 0.15, 0.14))
		for f in 4:
			var fs := palm + basis * Vector3(sx * 0.02 + (f - 1.5) * 0.025, -0.06, 0.0)
			b.tube(fl, PackedVector3Array([fs, fs + basis * Vector3(0, -0.07, 0.02), fs + basis * Vector3(0, -0.14, 0.01)]), PackedFloat32Array([0.013, 0.012, 0.009]), 3, wa(skin, 0.0))
		b.beam(fl, palm, palm + Vector3(0, -0.5, 0), 0.02, 0.015, wa(BLOOD, 0.0))
	# Legs dangling, ankles bound to the post.
	for sx: float in [-1.0, 1.0]:
		var hip := xf * Vector3(sx * 0.1, 1.38, 0.18)
		var knee := xf * Vector3(sx * 0.08, 0.92, 0.2)
		var ankle := xf * Vector3(sx * 0.04, 0.5, 0.12)
		b.tube(org, PackedVector3Array([hip, knee, ankle]), PackedFloat32Array([0.085, 0.07, 0.055]), 5, jit(Color(0.24, 0.2, 0.15), rng))
		b.tube(fl, PackedVector3Array([ankle, ankle + Vector3(0, -0.06, 0), ankle + basis * Vector3(0, -0.12, 0.12)]), PackedFloat32Array([0.04, 0.045, 0.035]), 4, wa(skin, 0.0))
	b.blob(org, xf * Vector3(0, 0.5, 0.06), basis, Vector3(0.14, 0.04, 0.12), 6, 3, ROPE)
	# Straw stuffed into the wounds.
	for k in 5:
		var sp := xf * Vector3(rng.randf_range(-0.2, 0.2), rng.randf_range(1.35, 1.9), 0.3)
		b.beam(org, sp, sp + basis * Vector3(rng.randf_range(-0.15, 0.15), rng.randf_range(-0.2, 0.1), 0.15), 0.015, 0.015, STRAW)
	# The head: slumped, a sack hood sewn to the scalp, or a pumpkin grafted onto the neck.
	var neck := xf * Vector3(0, 2.08, 0.2)
	var head := neck + basis * Vector3(rng.randf_range(-0.1, 0.1), 0.06, 0.12)
	var hb := basis * Basis(Vector3.RIGHT, 0.6 + slump) * Basis(Vector3(0, 0, 1), rng.randf_range(-0.5, 0.5))
	if pumpkin_head:
		var p := {"kind": 0, "size": 0.55, "tint": pick(PUMPKINS, rng), "ribs": 7, "squash": 0.8, "rot": 0.3, "seed": rng.randi(), "yaw": yaw, "tilt": 0.5}
		pumpkin(b, head - Vector3(0, 0.12, 0), p, 0)
		b.tube(fl, PackedVector3Array([neck - Vector3(0, 0.05, 0), head - Vector3(0, 0.08, 0)]), PackedFloat32Array([0.08, 0.13]), 6, wa(RAW, 0.6))
		carve_face(b, head + Vector3(0, 0.09, 0), Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, 0.5), 0.27, 0.2)
	else:
		b.blob(fl, head, hb, Vector3(0.12, 0.15, 0.13), 7, 5, wa(skin, 0.1))
		b.blob(org, head + hb * Vector3(0, 0.04, -0.03), hb, Vector3(0.14, 0.15, 0.14), 7, 4, Color(0.42, 0.34, 0.22), 0.1, rng.randf())
		var face := head + hb * Vector3(0, -0.02, 0.135)
		for sx: float in [-1.0, 1.0]:
			var e := face + hb * Vector3(sx * 0.05, 0.04, 0.0)
			b.box(org, xfm(hb * Basis(Vector3(0, 0, 1), PI / 4), e), Vector3(0.06, 0.012, 0.012), PUPIL)
			b.box(org, xfm(hb * Basis(Vector3(0, 0, 1), -PI / 4), e), Vector3(0.06, 0.012, 0.012), PUPIL)
		for k in 5:
			b.box(org, xfm(hb, face + hb * Vector3((k - 2) * 0.022, -0.06, 0.0)), Vector3(0.008, 0.045, 0.012), PUPIL)
		b.beam(fl, face + hb * Vector3(0, -0.08, 0), face + hb * Vector3(0.02, -0.4, 0.02), 0.02, 0.01, wa(BLOOD, 0.0))
	b.beam(fl, xf * Vector3(0.0, 1.2, 0.085), xf * Vector3(0.02, 0.1, 0.085), 0.06, 0.01, wa(BLOOD_DARK, 0.0))
	ground_pool(b, fl, terrain, xz + Vector2(sin(yaw), cos(yaw)) * 0.2, 0.55, wa(BLOOD_DARK, 0.0), wa(BLOOD, 0.0), rng)


## Iron gibbet cage hanging from `hang` (world), with what is left of its prisoner.
static func gibbet_cage(tb: HollowmereBatch, b: HollowmereBatch, hang: Vector3, drop: float, rng: RandomNumberGenerator) -> void:
	var iron := RetroMaterials.iron()
	var white := Color(1, 1, 1)
	var fl := flesh()
	var top := hang - Vector3(0, drop, 0)
	var links := int(drop / 0.12)
	for k in links:
		var p := hang - Vector3(0, (k + 0.5) * 0.12, 0)
		tb.box(iron, xfm(Basis(Vector3.UP, PI * 0.5 * (k % 2)), p), Vector3(0.07, 0.13, 0.02), white)
	var h := 1.45
	var r := 0.36
	var sway := Basis(Vector3(1, 0, 0.3).normalized(), rng.randf_range(-0.1, 0.1))
	var bars := 8
	for k in bars:
		var a := TAU * k / bars
		var s := top + sway * Vector3(cos(a) * r * 0.35, -0.05, sin(a) * r * 0.35)
		var m := top + sway * Vector3(cos(a) * r, -0.35, sin(a) * r)
		var e := top + sway * Vector3(cos(a) * r, -h, sin(a) * r)
		tb.beam(iron, s, m, 0.03, 0.03, white)
		tb.beam(iron, m, e, 0.03, 0.03, white)
	for y: float in [-0.35, -h * 0.65, -h]:
		var ring := PackedVector3Array()
		var rr := PackedFloat32Array()
		for k in bars + 1:
			var a := TAU * k / bars
			ring.append(top + sway * Vector3(cos(a) * r, y, sin(a) * r))
			rr.append(0.022)
		tb.tube(iron, ring, rr, 3, white)
	# The prisoner: a shrunken grey body folded inside, one arm hanging out through the bars.
	var seat := top + sway * Vector3(0, -h + 0.35, 0)
	var skin := Color(0.5, 0.5, 0.44)
	b.blob(fl, seat + Vector3(0, 0.25, 0), sway, Vector3(0.17, 0.32, 0.12), 7, 5, wa(skin, 0.0), 0.12, rng.randf() * 5.0)
	b.blob(fl, seat + Vector3(0.05, 0.62, 0.06), sway * Basis(Vector3.RIGHT, 0.9), Vector3(0.1, 0.13, 0.11), 6, 4, wa(skin.darkened(0.1), 0.0))
	b.blob(organic(), seat + Vector3(0, 0.12, 0), sway, Vector3(0.2, 0.18, 0.16), 6, 3, RAG)
	var shoulder := seat + Vector3(0.12, 0.42, 0.05)
	var out := top + sway * Vector3(r * 1.1, -h * 0.7, 0.05)
	b.tube(fl, PackedVector3Array([shoulder, out, out + Vector3(0.05, -0.4, 0), out + Vector3(0.06, -0.62, 0.02)]), PackedFloat32Array([0.04, 0.035, 0.03, 0.02]), 4, wa(skin, 0.0))
	for k in 3:
		b.beam(fl, seat + Vector3(rng.randf_range(-0.2, 0.2), 0.0, rng.randf_range(-0.2, 0.2)), seat + Vector3(rng.randf_range(-0.2,
				0.2), -rng.randf_range(0.3, 0.9), rng.randf_range(-0.2, 0.2)), 0.015, 0.015, wa(BLOOD_DARK, 0.0))



## Standing gallows post for a cage. Returns the hang point.
static func gallows(parent: Node3D, tb: HollowmereBatch, base: Vector3, yaw: float) -> Vector3:
	var wood := timber()
	var white := Color(1, 1, 1)
	var basis := Basis(Vector3.UP, yaw)
	tb.box(wood, xfm(basis, base + Vector3(0, 1.9, 0)), Vector3(0.24, 4.4, 0.24), white)
	var arm_end := base + basis * Vector3(1.5, 3.9, 0)
	tb.beam(wood, base + Vector3(0, 3.95, 0), arm_end + basis * Vector3(0.15, 0, 0), 0.18, 0.18, white)
	tb.beam(wood, base + Vector3(0, 3.0, 0), base + basis * Vector3(0.9, 3.9, 0), 0.12, 0.12, white)
	var bd := body(parent, "Gallows")
	shape_box(bd, Vector3(0.4, 4.2, 0.4), xfm(basis, base + Vector3(0, 2.1, 0)))
	return arm_end - Vector3(0, 0.1, 0)


# --------------------------------------------------------------------------
# Houses (single entry point)
# --------------------------------------------------------------------------
## Every Hollowmere house is created here, so the procedural cottage can be swapped for
## kit models (e.g. oga_house_*) without touching the region builder. Contract: build the
## house at `pos` facing local +z rotated by `yaw`, colliders under `parent`, textured
## pieces into `tb`, vertex-coloured detail into `b`, and return
## {"door": Vector3 (world, in front of the door), "anchors": [[pos, normal], ...] (walls),
##  "roof": [[pos, normal], ...], "xf": Transform3D, "eave_y": float}. The builder hangs the
## curse on those points (flesh growths, sigils, blood trails, the swallowing mass).
## ruin: 0 abandoned, 1 burnt, 2 collapsed. opts: see HollowmereVillage.gothic_house.
static func house(parent: Node3D, tb: HollowmereBatch, b: HollowmereBatch, pos: Vector3, yaw: float, w: float, d: float, storeys: int,
		ruin: int, rng: RandomNumberGenerator, opts: Dictionary = {}) -> Dictionary:
	return HollowmereVillage.gothic_house(parent, tb, b, pos, yaw, w, d, storeys, ruin, rng, opts)


# --------------------------------------------------------------------------
# Curse growths
# --------------------------------------------------------------------------
## Swelling flesh bursting out of a surface: lumpy lobes, pustules, veins crawling out,
## sometimes teeth or an eye.
static func flesh_growth(b: HollowmereBatch, at: Vector3, nrm: Vector3, size: float, rng: RandomNumberGenerator) -> void:
	var mat := flesh()
	var n := nrm.normalized()
	var t1 := n.cross(Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT).normalized()
	var t2 := n.cross(t1)
	var basis := Basis(t1, n, t2)
	for k in rng.randi_range(3, 5):
		var off := t1 * rng.randf_range(-0.5, 0.5) * size + t2 * rng.randf_range(-0.5, 0.5) * size
		var rr := size * rng.randf_range(0.28, 0.5)
		b.blob(mat, at + off + n * rr * 0.35, basis, Vector3(rr, rr * 0.7, rr), 8, 5, SKIN, 0.3, rng.randf() * 20.0, func(d: Vector3, kk: float) -> Color:
			var c := SKIN.lerp(RAW, clampf((kk - 1.0) * 5.0, 0.0, 1.0)).lerp(BRUISE, clampf(-d.y * 0.8, 0.0, 0.7))
			return wa(c, 0.85))
	for k in rng.randi_range(3, 6):
		var off := t1 * rng.randf_range(-0.6, 0.6) * size + t2 * rng.randf_range(-0.6, 0.6) * size
		b.blob(mat, at + off + n * size * 0.35, basis, Vector3.ONE * size * rng.randf_range(0.05, 0.09), 5, 3, wa(Color(0.78, 0.7, 0.42), 0.5))
	for k in rng.randi_range(4, 7):
		var a := rng.randf() * TAU
		var dir := t1 * cos(a) + t2 * sin(a)
		var path := PackedVector3Array()
		var radii := PackedFloat32Array()
		var p := at + dir * size * 0.3
		for s in 5:
			path.append(p + n * 0.03)
			radii.append(size * 0.06 * (1.0 - s / 5.0) + 0.008)
			dir = (dir + (t1 * rng.randf_range(-0.6, 0.6) + t2 * rng.randf_range(-0.6, 0.6))).normalized()
			p += dir * size * rng.randf_range(0.25, 0.4)
		b.tube(mat, path, radii, 3, wa(Color(0.4, 0.06, 0.08), 0.4), wa(Color(0.3, 0.1, 0.14), 0.1))
	var roll := rng.randf()
	if roll < 0.35:
		eye(b, at + n * size * 0.55, n, size * 0.16, rng)
	elif roll < 0.6:
		mouth(b, at + n * size * 0.5, basis * Basis(Vector3.RIGHT, -PI * 0.5), size * 0.5, rng)


## The giant pumpkin-flesh mass swallowing a house: ribbed rind on top turning to raw
## flesh below, a mouth of human teeth, eyes, tendrils gripping walls and soil.
static func flesh_mass(parent: Node3D, b: HollowmereBatch, terrain: TerrainBuilder, centre: Vector3, radius: float, face_dir: Vector3, grips: Array, rng: RandomNumberGenerator) -> void:
	var mat := flesh()
	var fwd := Vector3(face_dir.x, 0, face_dir.z).normalized()
	var basis := Basis.looking_at(-fwd, Vector3.UP)
	var ribs := 9
	var segs := ribs * 3
	var rings := 14
	var pts := PackedVector3Array()
	var cols := PackedColorArray()
	var hints := PackedVector3Array()
	for ri in rings + 1:
		var v := float(ri) / rings
		var phi := v * PI
		var y := -cos(phi) - 0.2 * smoothstep(0.75, 1.0, v)
		for ci in segs:
			var th := float(ci) / segs * TAU
			var s := absf(sin(th * ribs * 0.5))
			var rib := 1.0 - 0.12 * (1.0 - sqrt(s)) * smoothstep(0.1, 0.6, v)
			var d := Vector3(cos(th) * sin(phi), y, sin(th) * sin(phi))
			var k := 1.0 + 0.16 * HollowmereBatch.noise.get_noise_3d(d.x * 1.6, d.y * 1.6 + 3.0, d.z * 1.6)
			pts.append(centre + basis * Vector3(d.x * radius * rib, d.y * radius * 0.8, d.z * radius * rib) * k)
			hints.append(basis * d)
			var rind := smoothstep(0.35, 0.75, v + 0.15 * HollowmereBatch.noise.get_noise_3d(d.x * 3.0, d.y * 3.0, d.z * 3.0))
			var shade := 0.6 + 0.4 * s
			var flesh_c := SKIN.lerp(RAW, clampf((k - 1.0) * 5.0 + 0.3, 0.0, 1.0)).lerp(BRUISE, clampf(0.4 - v, 0.0, 0.5))
			var c := flesh_c.lerp(Color(0.72, 0.34, 0.08) * shade, rind)
			cols.append(wa(c, lerpf(1.0, 0.35, rind)))
	b.grid(mat, pts, segs, rings + 1, true, cols, hints)
	# Secondary swellings round the base.
	for k in 5:
		var a := TAU * k / 5.0 + rng.randf_range(-0.3, 0.3)
		var dir := basis * Vector3(cos(a), 0, sin(a))
		var rr := radius * rng.randf_range(0.35, 0.55)
		var lp := centre + dir * radius * 0.85 + Vector3(0, -radius * 0.45, 0)
		lp.y = maxf(lp.y, terrain.height_at(lp.x, lp.z) + rr * 0.25)
		b.blob(mat, lp, basis, Vector3(rr, rr * 0.75, rr), 10, 6, SKIN, 0.28, rng.randf() * 30.0, func(dd: Vector3, kk: float) -> Color:
			return wa(SKIN.lerp(RAW, clampf((kk - 1.0) * 4.0 + 0.2, 0.0, 1.0)).lerp(BRUISE, clampf(-dd.y, 0.0, 0.6)), 0.95))
	# Mouth facing the lane, eyes above it.
	mouth(b, centre + fwd * radius * 0.93 + Vector3(0, -radius * 0.2, 0), basis, radius * 1.1, rng)
	var glow_rim := PackedVector3Array()
	for k in 8:
		var a := TAU * k / 8.0
		glow_rim.append(centre + fwd * radius * 0.9 + basis * Vector3(cos(a) * radius * 0.35, sin(a) * radius * 0.1 - radius * 0.2, 0))
	b.fan(glow(), centre + fwd * radius * 0.88 + Vector3(0, -radius * 0.2, 0), glow_rim, Color(1, 1, 1), Color(1, 1, 1), fwd)
	for k in 4:
		var a := rng.randf_range(-0.9, 0.9)
		var ed := (basis * Vector3(sin(a), rng.randf_range(0.05, 0.5), cos(a))).normalized()
		eye(b, centre + ed * radius * 0.92, ed, radius * rng.randf_range(0.07, 0.12), rng)
	for k in 6:
		var a := rng.randf() * TAU
		var dir := basis * Vector3(cos(a), rng.randf_range(0.0, 0.6), sin(a)).normalized()
		flesh_growth(b, centre + dir * radius * 0.95, dir, radius * 0.25, rng)
	# Tendrils: to each grip point (house walls, roof) and down into the soil.
	var targets: Array = grips.duplicate()
	var back := atan2(-fwd.z, -fwd.x)
	for k in 5:
		var a := back + rng.randf_range(-1.6, 1.6)
		var far := Vector2(centre.x, centre.z) + Vector2(cos(a), sin(a)) * radius * rng.randf_range(1.4, 2.0)
		targets.append(terrain.ground(far.x, far.y) - Vector3(0, 0.1, 0))
	for tgt in targets:
		var end: Vector3 = tgt
		var start := centre + (end - centre).normalized() * radius * 0.8
		var path := PackedVector3Array()
		var radii := PackedFloat32Array()
		var steps := 7
		var bulge := Vector3(0, radius * 0.25, 0)
		for s in steps + 1:
			var f := float(s) / steps
			path.append(start.lerp(end, f) + bulge * sin(f * PI) + Vector3(rng.randf_range(-0.1, 0.1), 0, rng.randf_range(-0.1, 0.1)))
			radii.append(lerpf(radius * 0.14, 0.03, f))
		b.tube(mat, path, radii, 5, wa(RAW, 0.8), wa(BRUISE, 0.3))
	ground_pool(b, mat, terrain, Vector2(centre.x, centre.z) + Vector2(fwd.x, fwd.z) * radius * 1.1, radius * 0.7, wa(BLOOD_DARK, 0.0), wa(Color(0.4, 0.12, 0.04), 0.0), rng, 0.05)
	var bd := body(parent, "FleshMassCollider")
	shape_sphere(bd, radius * 0.85, centre)


## Half-buried villager with pumpkins sprouting from its back.
static func torso_bed(b: HollowmereBatch, terrain: TerrainBuilder, xz: Vector2, rng: RandomNumberGenerator) -> void:
	var g := terrain.ground(xz.x, xz.y)
	var yaw := rng.randf() * TAU
	var basis := Basis(Vector3.UP, yaw)
	var fl := flesh()
	ground_pool(b, fl, terrain, xz, 1.4, wa(BLOOD_DARK, 0.0), wa(Color(0.3, 0.06, 0.03), 0.0), rng, 0.035)
	var back := g + Vector3(0, 0.05, 0)
	b.blob(fl, back, basis * Basis(Vector3(0, 0, 1), 0.15), Vector3(0.45, 0.2, 0.26), 9, 5, SKIN_GREY, 0.1, rng.randf() * 9.0, func(d: Vector3, _k: float) -> Color:
		return wa(SKIN_GREY.lerp(BRUISE, clampf(-d.y + 0.2, 0.0, 0.7)), 0.5))
	# Spine ridge and opened ribs.
	for k in 6:
		b.blob(fl, back + basis * Vector3(-0.35 + k * 0.13, 0.17, 0), basis, Vector3(0.05, 0.04, 0.05), 5, 3, wa(TOOTH, 0.0))
	for k in 4:
		for sz: float in [-1.0, 1.0]:
			var r0 := back + basis * Vector3(-0.2 + k * 0.12, 0.16, sz * 0.03)
			b.tube(fl, PackedVector3Array([r0, r0 + basis * Vector3(0, 0.12, sz * 0.15), r0 + basis * Vector3(0.02, 0.05, sz * 0.27)]), PackedFloat32Array([0.018, 0.016, 0.012]), 3, wa(TOOTH, 0.0))
	b.blob(fl, back + basis * Vector3(-0.05, 0.12, 0), basis, Vector3(0.22, 0.07, 0.1), 7, 3, wa(RAW, 0.9))
	# Head turned to the side, half sunk.
	b.blob(fl, g + basis * Vector3(0.6, 0.05, 0.05), basis, Vector3(0.13, 0.12, 0.15), 7, 4, wa(SKIN_GREY, 0.0))
	# Arm clawing out of the soil.
	var sh := back + basis * Vector3(0.3, 0.05, -0.25)
	var el := sh + basis * Vector3(0.15, 0.45, -0.2)
	var hand := el + basis * Vector3(0.2, 0.35, 0.05)
	b.tube(fl, PackedVector3Array([sh, el, hand]), PackedFloat32Array([0.06, 0.05, 0.04]), 5, wa(SKIN_GREY, 0.1))
	for f in 4:
		var fs := hand + basis * Vector3(0.03, 0.02, -0.04 + f * 0.027)
		b.tube(fl, PackedVector3Array([fs, fs + basis * Vector3(0.06, 0.08, 0), fs + basis * Vector3(0.12, 0.06, 0)]), PackedFloat32Array([0.014, 0.012, 0.009]), 3, wa(SKIN_GREY, 0.0))
	# Pumpkins rooted in the body, umbilical vines into the flesh.
	for k in 4:
		var a := TAU * k / 4.0 + rng.randf_range(-0.3, 0.3)
		var off := Vector2(cos(a), sin(a)) * rng.randf_range(0.7, 1.0)
		var p := roll_pumpkin(rng, 0.0)
		p["kind"] = 4 if k % 2 == 0 else 0
		p["size"] = rng.randf_range(0.6, 0.95)
		p["yaw"] = -a + PI * 0.5
		pumpkin(b, terrain.ground(xz.x + off.x, xz.y + off.y), p, 0)
		var top := terrain.ground(xz.x + off.x, xz.y + off.y) + Vector3(0, float(p["size"]) * 0.55, 0)
		b.tube(fl, PackedVector3Array([back + Vector3(0, 0.15, 0), (back + top) * 0.5 + Vector3(0, 0.3, 0),
				top]), PackedFloat32Array([0.05, 0.04, 0.03]), 4, wa(Color(0.4, 0.07, 0.08), 0.6), wa(VINE, 0.0))
