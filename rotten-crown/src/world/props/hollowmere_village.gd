@tool
class_name HollowmereVillage
extends RefCounted
## Hollowmere (U8) village builders: half-timbered gothic houses, the blood well, market
## stalls and gravestones. Textured architecture goes into a final = false
## HollowmereBatch (merged later by MeshMerger.merge_static), vertex-coloured detail into
## a final batch; colours and materials come from HollowmereProps.

# --------------------------------------------------------------------------
# Gothic house
# --------------------------------------------------------------------------
## Half-timbered gothic house: plinth, plaster walls, a jettied upper storey, a steep
## sagging roof, chimney, shutters, framed windows and a door. ruin: 0 abandoned,
## 1 burnt (roof hole, charred rafters, soot), 2 collapsed (one roof side slumped).
## opts: lit (int windows), sigil (bool), door ("open", "closed", "torn"), rust (bool).
## Returns {"door": world point in front of the door, "anchors": [[pos, normal], ...],
## "roof": [[pos, normal], ...], "xf": Transform3D}.
static func gothic_house(parent: Node3D, tb: HollowmereBatch, b: HollowmereBatch, pos: Vector3, yaw: float, w: float, d: float, storeys: int, ruin: int,
		rng: RandomNumberGenerator, opts: Dictionary = {}) -> Dictionary:
	var xf := Transform3D(Basis(Vector3.UP, yaw), pos)
	var plaster := RetroMaterials.clapboard()
	var wood := HollowmereProps.timber()
	var stone := RetroMaterials.stone()
	var white := Color(1, 1, 1)
	var h1 := rng.randf_range(2.5, 2.8)
	var h2 := rng.randf_range(2.2, 2.45) if storeys > 1 else 0.0
	var j := 0.45 if storeys > 1 else 0.0
	var t := 0.24
	var anchors: Array = []
	var roof_pts: Array = []
	var bd := HollowmereProps.body(parent, "HouseCollider")
	# Stone plinth sunk into the slope.
	tb.box(stone, xf * HollowmereProps.xfm(Basis.IDENTITY, Vector3(0, -0.4, 0)), Vector3(w + 0.25, 1.0, d + 0.25), white)
	b.box(HollowmereProps.organic(), xf * HollowmereProps.xfm(Basis.IDENTITY, Vector3(0, 0.12, 0)), Vector3(w - 0.3, 0.05, d - 0.3), Color(0.1, 0.08, 0.06))
	# Ground storey walls (+ colliders), front split round the door.
	var door_w := 1.05
	var door_h := 2.05
	var door_x := rng.randf_range(-w * 0.15, w * 0.15)
	var walls: Array = []
	var left_len := door_x - door_w * 0.5 + w * 0.5
	var right_len := w * 0.5 - (door_x + door_w * 0.5)
	walls.append([Vector3(-w * 0.5 + left_len * 0.5, h1 * 0.5, d * 0.5), Vector3(left_len, h1, t)])
	walls.append([Vector3(w * 0.5 - right_len * 0.5, h1 * 0.5, d * 0.5), Vector3(right_len, h1, t)])
	walls.append([Vector3(door_x, (h1 + door_h) * 0.5, d * 0.5), Vector3(door_w, h1 - door_h, t)])
	walls.append([Vector3(0, h1 * 0.5, -d * 0.5), Vector3(w, h1, t)])
	walls.append([Vector3(-w * 0.5, h1 * 0.5, 0), Vector3(t, h1, d)])
	walls.append([Vector3(w * 0.5, h1 * 0.5, 0), Vector3(t, h1, d)])
	for wl in walls:
		var c: Vector3 = wl[0]
		var s: Vector3 = wl[1]
		tb.box(plaster, xf * HollowmereProps.xfm(Basis.IDENTITY, c), s, white)
		HollowmereProps.shape_box(bd, s, xf * HollowmereProps.xfm(Basis.IDENTITY, c))
	# Facades: [local transform of the wall plane (x along, z out), length, height, openings].
	var g_front := HollowmereProps.xfm(Basis.IDENTITY, Vector3(0, 0, d * 0.5 + t * 0.5))
	var g_back := HollowmereProps.xfm(Basis(Vector3.UP, PI), Vector3(0, 0, -d * 0.5 - t * 0.5))
	var g_left := HollowmereProps.xfm(Basis(Vector3.UP, -PI * 0.5), Vector3(-w * 0.5 - t * 0.5, 0, 0))
	var g_right := HollowmereProps.xfm(Basis(Vector3.UP, PI * 0.5), Vector3(w * 0.5 + t * 0.5, 0, 0))
	var lit: int = opts.get("lit", 0)
	var front_open: Array = [Rect2(door_x - door_w * 0.5, 0.0, door_w, door_h)]
	var win_x := -door_x * 0.3 + (w * 0.28 if door_x < 0.0 else -w * 0.28)
	if w > 4.2:
		front_open.append(Rect2(win_x - 0.35, 1.0, 0.7, 0.95))
	_facade(tb, b, xf * g_front, w, h1, front_open, false, ruin, rng, lit > 0)
	_facade(tb, b, xf * g_back, w, h1, [Rect2(-0.35, 1.0, 0.7, 0.95)], false, ruin, rng, false)
	_facade(tb, b, xf * g_left, d, h1, [Rect2(-0.35, 1.0, 0.7, 0.95)], false, ruin, rng, false)
	_facade(tb, b, xf * g_right, d, h1, [Rect2(-0.35, 1.0, 0.7, 0.95)] if storeys == 1 else [], false, ruin, rng, lit > 2)
	anchors.append([xf * Vector3(-w * 0.5 - t, rng.randf_range(0.3, 1.0), d * 0.3), xf.basis * Vector3.LEFT])
	anchors.append([xf * Vector3(w * 0.5 + t, rng.randf_range(0.3, 1.4), -d * 0.2), xf.basis * Vector3.RIGHT])
	anchors.append([xf * Vector3(w * 0.35, rng.randf_range(0.2, 0.8), d * 0.5 + t), xf.basis * Vector3.BACK])
	# Door: frame, plank leaf (closed, ajar or torn off), iron straps, step.
	var door_state: String = opts.get("door", "open")
	var dxf := xf * g_front
	var hinge := Vector3(door_x - door_w * 0.5, 0.0, -0.05)
	var leaf_col := HollowmereProps.jit(Color(0.2, 0.13, 0.08), rng)
	var leaf_xf := Transform3D.IDENTITY
	if door_state == "closed":
		leaf_xf = dxf * HollowmereProps.xfm(Basis.IDENTITY, hinge)
	elif door_state == "open":
		leaf_xf = dxf * HollowmereProps.xfm(Basis(Vector3.UP, rng.randf_range(-1.9, -1.2)), hinge)
	else:
		leaf_xf = dxf * HollowmereProps.xfm(Basis(Vector3.RIGHT, -PI * 0.5 + 0.08) * Basis(Vector3.UP, 0.3), Vector3(door_x - door_w * 0.5, 0.1, 1.4))
	for k in 4:
		b.box(HollowmereProps.organic(), leaf_xf * HollowmereProps.xfm(Basis.IDENTITY, Vector3(door_w * (k + 0.5) / 4.0,
				door_h * 0.5, -0.02)), Vector3(door_w / 4.0 - 0.02, door_h - 0.05, 0.06), HollowmereProps.jit(leaf_col, rng, 0.15))
	for y: float in [0.4, door_h - 0.4]:
		b.box(HollowmereProps.organic(), leaf_xf * HollowmereProps.xfm(Basis.IDENTITY, Vector3(door_w * 0.45, y, 0.02)), Vector3(door_w * 0.85, 0.07, 0.02), Color(0.13, 0.12, 0.12))
	tb.box(stone, dxf * HollowmereProps.xfm(Basis.IDENTITY, Vector3(door_x, 0.05, 0.35)), Vector3(door_w + 0.4, 0.2, 0.55), white)
	if opts.get("sigil", false):
		var sxf := leaf_xf * HollowmereProps.xfm(Basis.IDENTITY, Vector3(door_w * 0.5, door_h * 0.6, 0.015)) if door_state == "closed" \
			else dxf * HollowmereProps.xfm(Basis.IDENTITY, Vector3(door_x + (door_w * 0.5 + 0.55) * (1.0 if door_x < 0.0 else -1.0), 1.5, 0.05))
		HollowmereProps.curse_sigil(b, sxf, 0.75, rng)
	if rng.randf() < 0.6:
		HollowmereProps.hand_print(b, dxf * HollowmereProps.xfm(Basis(Vector3(0, 0, 1), rng.randf_range(-0.4, 0.4)), Vector3(door_x + door_w * 0.5 + 0.25, rng.randf_range(0.8, 1.4), 0.06)), 0.2, rng)
	# Upper storey (jettied, leaning a little) or straight to the roof.
	var lean := Basis.from_euler(Vector3(rng.randf_range(-0.03, 0.03), 0.0, rng.randf_range(-0.035, 0.035)))
	var uxf := xf * Transform3D(lean, Vector3(0, h1, 0))
	var uw := w + j
	var ud := d + 2.0 * j
	var wall_top := 0.0
	if storeys > 1:
		var upper_walls := [[Vector3(0, h2 * 0.5, ud * 0.5), Vector3(uw, h2, t)], [Vector3(0, h2 * 0.5, -ud * 0.5), Vector3(uw, h2, t)],
			[Vector3(-uw * 0.5, h2 * 0.5, 0), Vector3(t, h2, ud)], [Vector3(uw * 0.5, h2 * 0.5, 0), Vector3(t, h2, ud)]]
		for wl in upper_walls:
			tb.box(plaster, uxf * HollowmereProps.xfm(Basis.IDENTITY, wl[0]), wl[1], white)
		# Floor deck and the joist ends carrying the jetty.
		tb.box(wood, uxf * HollowmereProps.xfm(Basis.IDENTITY, Vector3(0, -0.08, 0)), Vector3(uw + 0.1, 0.16, ud + 0.1), white)
		var joists := int(uw / 0.5)
		for k in joists:
			var x := -uw * 0.5 + (k + 0.5) * uw / joists
			for zs: float in [1.0, -1.0]:
				tb.box(wood, uxf * HollowmereProps.xfm(Basis.IDENTITY, Vector3(x, -0.24, zs * (d * 0.5 + j * 0.5 + 0.05))), Vector3(0.14, 0.14, j + 0.25), white)
		var u_front := HollowmereProps.xfm(Basis.IDENTITY, Vector3(0, 0, ud * 0.5 + t * 0.5))
		var u_back := HollowmereProps.xfm(Basis(Vector3.UP, PI), Vector3(0, 0, -ud * 0.5 - t * 0.5))
		var u_left := HollowmereProps.xfm(Basis(Vector3.UP, -PI * 0.5), Vector3(-uw * 0.5 - t * 0.5, 0, 0))
		var u_right := HollowmereProps.xfm(Basis(Vector3.UP, PI * 0.5), Vector3(uw * 0.5 + t * 0.5, 0, 0))
		var two := [Rect2(-uw * 0.25 - 0.32, 0.8, 0.64, 0.9), Rect2(uw * 0.25 - 0.32, 0.8, 0.64, 0.9)]
		_facade(tb, b, uxf * u_front, uw, h2, two, true, ruin, rng, lit > 1)
		_facade(tb, b, uxf * u_back, uw, h2, [Rect2(-0.32, 0.8, 0.64, 0.9)], true, ruin, rng, false)
		_facade(tb, b, uxf * u_left, ud, h2, [Rect2(-0.32, 0.8, 0.64, 0.9)], true, ruin, rng, false)
		_facade(tb, b, uxf * u_right, ud, h2, [Rect2(-0.32, 0.8, 0.64, 0.9)], true, ruin, rng, lit > 2)
		wall_top = h2
		anchors.append([uxf * Vector3(-uw * 0.5 - t, h2 * 0.4, ud * 0.1), xf.basis * Vector3.LEFT])
		anchors.append([uxf * Vector3(uw * 0.3, -0.1, ud * 0.5), (xf.basis * Vector3(0, -0.6, 1)).normalized()])
	else:
		uw = w
		ud = d
	# Gables (front and back) with a king post and braces.
	var pitch := rng.randf_range(0.98, 1.08)
	var rh := uw * 0.5 * tan(pitch)
	var gxf := uxf * HollowmereProps.xfm(Basis.IDENTITY, Vector3(0, wall_top, 0))
	for zs: float in [1.0, -1.0]:
		var gz := zs * ud * 0.5
		tb.prism(plaster, gxf * HollowmereProps.xfm(Basis.IDENTITY, Vector3(0, 0, gz)), PackedVector2Array([Vector2(-uw * 0.5, 0), Vector2(uw * 0.5, 0), Vector2(0, rh)]), t, white)
		var o := zs * (t * 0.5 + 0.04)
		tb.beam(wood, gxf * Vector3(-uw * 0.5, 0.05, gz + o), gxf * Vector3(uw * 0.5, 0.05, gz + o), 0.16, 0.08, white)
		tb.beam(wood, gxf * Vector3(0, 0.0, gz + o), gxf * Vector3(0, rh * 0.9, gz + o), 0.16, 0.08, white)
		tb.beam(wood, gxf * Vector3(-uw * 0.3, rh * 0.4, gz + o), gxf * Vector3(uw * 0.3, rh * 0.4, gz + o), 0.14, 0.08, white)
		for sx: float in [-1.0, 1.0]:
			tb.beam(wood, gxf * Vector3(sx * uw * 0.42, 0.05, gz + o), gxf * Vector3(sx * 0.05, rh * 0.4, gz + o), 0.13, 0.07, white)
		if zs > 0.0:
			var gw_lit := lit > 3 or (lit > 0 and storeys == 1)
			_window(tb, b, gxf * HollowmereProps.xfm(Basis.IDENTITY, Vector3(0, rh * 0.58, gz + t * 0.5)), 0.42, 0.6, gw_lit, false, ruin, rng)
	# Roof: two steep slabs that sag between the gables.
	var e := 0.5
	var ridge_y := wall_top + rh + 0.12
	var eave_y := wall_top - e * tan(pitch) + 0.05
	var half := uw * 0.5 + e
	var length := ud + 0.7
	var ridge_sag := rng.randf_range(0.08, 0.3)
	var slope_sag := rng.randf_range(0.05, 0.16)
	var roof_mat: Material = RetroMaterials.rust_roof() if opts.get("rust", false) else RetroMaterials.roof()
	var hole_side := 1.0 if rng.randf() < 0.5 else -1.0
	var hole := Rect2(rng.randf_range(0.2, 0.45), 0.2, rng.randf_range(0.25, 0.4), 0.5)
	var nu := 7
	var nv := 4
	for side: float in [1.0, -1.0]:
		var top_pts := PackedVector3Array()
		var bot_pts := PackedVector3Array()
		var cols := PackedColorArray()
		var up_h := PackedVector3Array()
		var dn_h := PackedVector3Array()
		var slump := 0.0
		if ruin == 2 and side == hole_side:
			slump = 1.0
		for vi in nv + 1:
			var s := float(vi) / nv
			for ui in nu + 1:
				var u := float(ui) / nu
				var z := lerpf(-length * 0.5, length * 0.5, u)
				var y := lerpf(ridge_y, eave_y, s) - ridge_sag * sin(PI * u) * (1.0 - s * 0.6) - slope_sag * sin(PI * u) * sin(PI * s)
				var x := side * half * s
				if slump > 0.0:
					y -= s * s * 1.6 * sin(PI * clampf(u * 1.3, 0.0, 1.0))
					x += side * s * 0.3
				var lp := Vector3(x, y, z)
				top_pts.append(gxf * lp)
				bot_pts.append(gxf * (lp - Vector3(0, 0.16, 0)))
				var nrm := (gxf.basis * Vector3(side * sin(pitch), cos(pitch), 0)).normalized()
				up_h.append(nrm)
				dn_h.append(-nrm)
				cols.append(white)
		var skip := Callable()
		if ruin == 1 and side == hole_side:
			skip = func(r: int, cc: int) -> bool:
				return hole.has_point(Vector2(float(cc) / nu, float(r) / nv))
		tb.grid(roof_mat, top_pts, nu + 1, nv + 1, false, cols, up_h, skip)
		tb.grid(wood, bot_pts, nu + 1, nv + 1, false, cols, dn_h, skip)
		# Barge boards on the gable edges, fascia along the eave.
		for ui: int in [0, nu]:
			tb.beam(wood, top_pts[ui] + Vector3(0, 0.02, 0), top_pts[nv * (nu + 1) + ui] + Vector3(0, 0.02, 0), 0.22, 0.12, white)
		for ui in nu:
			tb.beam(wood, top_pts[nv * (nu + 1) + ui], top_pts[nv * (nu + 1) + ui + 1], 0.2, 0.1, white)
			if side > 0.0:
				tb.beam(wood, top_pts[ui] + Vector3(0, 0.05, 0), top_pts[ui + 1] + Vector3(0, 0.05, 0), 0.16, 0.22, white)
		for k in 2:
			var ui := rng.randi_range(1, nu - 1)
			var vi := rng.randi_range(1, nv - 1)
			roof_pts.append([top_pts[vi * (nu + 1) + ui], up_h[vi * (nu + 1) + ui]])
		if ruin == 1 and side == hole_side:
			_burnt_hole(b, gxf, hole, side, half, length, ridge_y, eave_y, rng)
	# Chimney through the back of the roof.
	var cx := rng.randf_range(-uw * 0.25, uw * 0.25)
	var cz := -ud * 0.25
	var ch_top := h1 + ridge_y + (0.4 if ruin != 2 else -0.6)
	var cpos := xf * Vector3(cx, ch_top * 0.5, cz)
	tb.box(RetroMaterials.brick(), HollowmereProps.xfm(xf.basis, cpos), Vector3(0.75, ch_top, 0.75), white)
	tb.box(RetroMaterials.brick(), HollowmereProps.xfm(xf.basis, xf * Vector3(cx, ch_top, cz)), Vector3(0.95, 0.14, 0.95), white)
	if ruin != 2:
		for k in rng.randi_range(1, 2):
			var pp := xf * Vector3(cx + (k - 0.5) * 0.3, ch_top + 0.07, cz)
			b.tube(HollowmereProps.organic(), PackedVector3Array([pp, pp + Vector3(0, 0.35, 0)]), PackedFloat32Array([0.12, 0.09]), 6, Color(0.36, 0.2, 0.13))
	HollowmereProps.shape_box(bd, Vector3(0.75, h1, 0.75), HollowmereProps.xfm(xf.basis, xf * Vector3(cx, h1 * 0.5, cz)))
	return {"door": dxf * Vector3(door_x, 0, 1.2), "anchors": anchors, "roof": roof_pts, "xf": xf, "eave_y": h1 + eave_y}


## Timber framing + windows on one facade. xfw: wall plane (x along, y up, z out, origin at
## the wall's base centre on the outer face).
static func _facade(tb: HollowmereBatch, b: HollowmereBatch, xfw: Transform3D, length: float, height: float, openings: Array, upper: bool, ruin: int,
		rng: RandomNumberGenerator, lit: bool) -> void:
	var wood := HollowmereProps.timber()
	var white := Color(1, 1, 1)
	var z := 0.04
	var hl := length * 0.5
	tb.beam(wood, xfw * Vector3(-hl - 0.05, 0.08, z), xfw * Vector3(hl + 0.05, 0.08, z), 0.17, 0.1, white)
	tb.beam(wood, xfw * Vector3(-hl - 0.05, height - 0.08, z), xfw * Vector3(hl + 0.05, height - 0.08, z), 0.17, 0.1, white)
	for sx: float in [-1.0, 1.0]:
		tb.beam(wood, xfw * Vector3(sx * (hl - 0.02), 0.0, z + 0.01), xfw * Vector3(sx * (hl - 0.02), height, z + 0.01), 0.2, 0.12, white)
	# Studs, skipping openings.
	var bays := maxi(2, int(length / 1.15))
	var step := length / bays
	for k in range(1, bays):
		var x := -hl + k * step
		var blocked := false
		for o in openings:
			var r: Rect2 = o
			if x > r.position.x - 0.12 and x < r.end.x + 0.12:
				blocked = true
		if not blocked:
			tb.beam(wood, xfw * Vector3(x, 0.08, z), xfw * Vector3(x, height - 0.08, z), 0.14, 0.08, white)
	# Braces: St Andrew's crosses upstairs, raking braces in the end bays downstairs.
	var mid := height * 0.5
	if upper:
		tb.beam(wood, xfw * Vector3(-hl + 0.1, mid, z), xfw * Vector3(hl - 0.1, mid, z), 0.12, 0.08, white)
		for k in bays:
			var x0 := -hl + k * step
			var x1 := x0 + step
			var free := true
			for o in openings:
				var r: Rect2 = o
				if r.end.x > x0 and r.position.x < x1:
					free = false
			if free and rng.randf() < 0.75:
				tb.beam(wood, xfw * Vector3(x0 + 0.08, 0.1, z), xfw * Vector3(x1 - 0.08, height - 0.1, z), 0.11, 0.07, white)
				tb.beam(wood, xfw * Vector3(x1 - 0.08, 0.1, z), xfw * Vector3(x0 + 0.08, height - 0.1, z), 0.11, 0.07, white)
	else:
		for sx: float in [-1.0, 1.0]:
			var x0 := sx * (hl - 0.05)
			var x1 := sx * (hl - step + 0.1)
			var clear := true
			for o in openings:
				var r: Rect2 = o
				if minf(x0, x1) < r.end.x and maxf(x0, x1) > r.position.x:
					clear = false
			if clear:
				tb.beam(wood, xfw * Vector3(x0, 0.15, z), xfw * Vector3(x1, height * 0.75, z), 0.12, 0.08, white)
		tb.beam(wood, xfw * Vector3(-hl + 0.1, height * 0.62, z), xfw * Vector3(hl - 0.1, height * 0.62, z), 0.1, 0.07, white)
	for o in openings:
		var r: Rect2 = o
		if r.position.y > 0.05:
			_window(tb, b, xfw * HollowmereProps.xfm(Basis.IDENTITY, Vector3(r.get_center().x, r.get_center().y, 0.0)), r.size.x, r.size.y, lit, true, ruin, rng)
			lit = false
		else:
			tb.beam(wood, xfw * Vector3(r.position.x - 0.08, 0.0, z + 0.02), xfw * Vector3(r.position.x - 0.08, r.end.y + 0.1, z + 0.02), 0.18, 0.12, white)
			tb.beam(wood, xfw * Vector3(r.end.x + 0.08, 0.0, z + 0.02), xfw * Vector3(r.end.x + 0.08, r.end.y + 0.1, z + 0.02), 0.18, 0.12, white)
			tb.beam(wood, xfw * Vector3(r.position.x - 0.2, r.end.y + 0.08, z + 0.03), xfw * Vector3(r.end.x + 0.2, r.end.y + 0.08, z + 0.03), 0.2, 0.12, white)
	# Soot and damp streaks on burnt houses.
	if ruin == 1 and rng.randf() < 0.7:
		var sx := rng.randf_range(-hl * 0.6, hl * 0.6)
		var rim := PackedVector3Array()
		for k in 8:
			var a := TAU * k / 8.0
			rim.append(xfw * Vector3(sx + cos(a) * rng.randf_range(0.4, 0.9), height * 0.75 + sin(a) * rng.randf_range(0.3, 0.8), 0.015))
		b.fan(HollowmereProps.organic(), xfw * Vector3(sx, height * 0.75, 0.02), rim, HollowmereProps.CHAR, Color(0.12, 0.1, 0.09), (xfw.basis * Vector3(0, 0, 1)).normalized())


## Framed window: dark (or candle-lit) panes, mullion cross, sill, shutters.
static func _window(tb: HollowmereBatch, b: HollowmereBatch, xfw: Transform3D, ww: float, wh: float, lit: bool, shutters: bool, ruin: int, rng: RandomNumberGenerator) -> void:
	var wood := HollowmereProps.timber()
	var white := Color(1, 1, 1)
	if lit:
		b.box(HollowmereProps.glow(), xfw * HollowmereProps.xfm(Basis.IDENTITY, Vector3(0, 0, 0.01)), Vector3(ww, wh, 0.04), white)
	else:
		b.box(HollowmereProps.organic(), xfw * HollowmereProps.xfm(Basis.IDENTITY, Vector3(0, 0, 0.01)), Vector3(ww, wh, 0.04), HollowmereProps.GLASS)
	tb.beam(wood, xfw * Vector3(-ww * 0.5 - 0.06, wh * 0.5 + 0.05, 0.06), xfw * Vector3(ww * 0.5 + 0.06, wh * 0.5 + 0.05, 0.06), 0.1, 0.1, white)
	tb.beam(wood, xfw * Vector3(-ww * 0.5 - 0.1, -wh * 0.5 - 0.05, 0.08), xfw * Vector3(ww * 0.5 + 0.1, -wh * 0.5 - 0.05, 0.08), 0.09, 0.16, white)
	for sx: float in [-1.0, 1.0]:
		tb.beam(wood, xfw * Vector3(sx * (ww * 0.5 + 0.04), -wh * 0.5, 0.06), xfw * Vector3(sx * (ww * 0.5 + 0.04), wh * 0.5, 0.06), 0.09, 0.1, white)
	tb.beam(wood, xfw * Vector3(0, -wh * 0.5, 0.05), xfw * Vector3(0, wh * 0.5, 0.05), 0.05, 0.05, white)
	tb.beam(wood, xfw * Vector3(-ww * 0.5, wh * 0.1, 0.05), xfw * Vector3(ww * 0.5, wh * 0.1, 0.05), 0.05, 0.05, white)
	if not shutters:
		return
	var col := HollowmereProps.pick(HollowmereProps.SHUTTERS, rng)
	for sx: float in [-1.0, 1.0]:
		var mode := rng.randf()
		if ruin > 0 and mode < 0.3:
			continue  # shutter gone
		var sxf := xfw * HollowmereProps.xfm(Basis.IDENTITY, Vector3(sx * (ww * 0.5 + 0.08 + ww * 0.25), 0, 0.07))
		if mode > 0.8:
			sxf = xfw * HollowmereProps.xfm(Basis(Vector3(0, 0, 1), sx * 0.45), Vector3(sx * (ww * 0.5 + 0.2), -wh * 0.2, 0.09))
		b.box(HollowmereProps.organic(), sxf, Vector3(ww * 0.5, wh + 0.05, 0.04), HollowmereProps.jit(col, rng, 0.12))
		b.box(HollowmereProps.organic(), sxf * HollowmereProps.xfm(Basis.IDENTITY, Vector3(0, 0, 0.025)), Vector3(ww * 0.5, 0.06, 0.02), col.darkened(0.4))


## Charred rafters and scorch round a roof hole.
static func _burnt_hole(b: HollowmereBatch, gxf: Transform3D, hole: Rect2, side: float, half: float, length: float, ridge_y: float, eave_y: float, rng: RandomNumberGenerator) -> void:
	var mat := HollowmereProps.organic()
	for k in 4:
		var u := hole.position.x + hole.size.x * (k + 0.5) / 4.0
		var z := lerpf(-length * 0.5, length * 0.5, u)
		var s1 := 1.0 if rng.randf() < 0.6 else rng.randf_range(0.4, 0.8)
		var a := gxf * Vector3(0, ridge_y - 0.15, z)
		var e := gxf * Vector3(side * half * s1, lerpf(ridge_y, eave_y, s1) - 0.15 - (0.0 if s1 >= 1.0 else 0.5), z + rng.randf_range(-0.2, 0.2))
		b.beam(mat, a, e, 0.14, 0.12, HollowmereProps.CHAR, rng.randf_range(-0.2, 0.2))
	var u0 := lerpf(-length * 0.5, length * 0.5, hole.get_center().x)
	var s0 := hole.get_center().y
	var c := gxf * Vector3(side * half * s0, lerpf(ridge_y, eave_y, s0) + 0.03, u0)
	var rim := PackedVector3Array()
	for k in 10:
		var a := TAU * k / 10.0
		var du := cos(a) * length * hole.size.x * 0.75
		var ds := sin(a) * hole.size.y * 0.75
		rim.append(gxf * Vector3(side * half * (s0 + ds), lerpf(ridge_y, eave_y, s0 + ds) + 0.04, u0 + du))
	b.fan(mat, c, rim, HollowmereProps.CHAR, Color(0.1, 0.08, 0.07), (gxf.basis * Vector3(side * 0.85, 0.5, 0)).normalized())


# --------------------------------------------------------------------------
# Village furniture
# --------------------------------------------------------------------------
## Stone well brimming with blood, posts, a little roof, rope and bucket.
static func blood_well(parent: Node3D, tb: HollowmereBatch, b: HollowmereBatch, base: Vector3, yaw: float, rng: RandomNumberGenerator) -> Vector3:
	var stone := RetroMaterials.stone()
	var white := Color(1, 1, 1)
	var segs := 12
	var r_out := 1.05
	var r_in := 0.8
	var h := 0.85
	for inward: float in [1.0, -1.0]:
		var rr := r_out if inward > 0.0 else r_in
		var pts := PackedVector3Array()
		var hints := PackedVector3Array()
		var cols := PackedColorArray()
		for y: float in [-0.3, h]:
			for k in segs:
				var a := TAU * k / segs
				var d := Vector3(cos(a), 0, sin(a))
				pts.append(base + d * rr + Vector3(0, y, 0))
				hints.append(d * inward)
				cols.append(white)
		tb.grid(stone, pts, segs, 2, true, cols, hints)
	var rim := PackedVector3Array()
	var rim_h := PackedVector3Array()
	var rim_c := PackedColorArray()
	for rr: float in [r_in - 0.05, r_out + 0.08]:
		for k in segs:
			var a := TAU * k / segs
			rim.append(base + Vector3(cos(a) * rr, h + 0.06, sin(a) * rr))
			rim_h.append(Vector3.UP)
			rim_c.append(white)
	tb.grid(stone, rim, segs, 2, true, rim_c, rim_h)
	var surface := PackedVector3Array()
	for k in segs:
		var a := TAU * k / segs
		surface.append(base + Vector3(cos(a) * r_in, h - 0.25, sin(a) * r_in))
	b.fan(HollowmereProps.flesh(), base + Vector3(0, h - 0.24, 0), surface, HollowmereProps.wa(HollowmereProps.BLOOD_DARK, 0.0), HollowmereProps.wa(HollowmereProps.BLOOD, 0.0), Vector3.UP)
	# Fingers breaking the surface.
	for k in 3:
		var a := rng.randf() * TAU
		var fp := base + Vector3(cos(a) * 0.4, h - 0.3, sin(a) * 0.4)
		b.tube(HollowmereProps.flesh(), PackedVector3Array([fp, fp + Vector3(0.02, 0.14, 0.01), fp + Vector3(0.06,
				0.2, 0.0)]), PackedFloat32Array([0.022, 0.02, 0.015]), 3, HollowmereProps.wa(HollowmereProps.SKIN_GREY, 0.0))
	b.beam(HollowmereProps.flesh(), base + Vector3(r_out * 0.7, h + 0.07, 0.3), base + Vector3(r_out + 0.05, 0.2, 0.4), 0.12, 0.02, HollowmereProps.wa(HollowmereProps.BLOOD, 0.0))
	var basis := Basis(Vector3.UP, yaw)
	var wood := HollowmereProps.timber()
	for sx: float in [-1.0, 1.0]:
		tb.box(wood, HollowmereProps.xfm(basis, base + basis * Vector3(sx * 1.0, 1.4, 0)), Vector3(0.16, 2.8, 0.16), white)
	tb.beam(wood, base + basis * Vector3(-1.15, 2.15, 0), base + basis * Vector3(1.15, 2.15, 0), 0.12, 0.12, white)
	var roof := RetroMaterials.roof()
	for sz: float in [1.0, -1.0]:
		var a := base + basis * Vector3(0, 2.95, 0)
		var e := base + basis * Vector3(0, 2.35, sz * 0.9)
		tb.box(roof, Transform3D(basis * Basis(Vector3.RIGHT, -sz * 0.73), (a + e) * 0.5), Vector3(2.6, 0.08, a.distance_to(e) + 0.1), white)
	tb.beam(wood, base + basis * Vector3(-1.3, 2.96, 0), base + basis * Vector3(1.3, 2.96, 0), 0.1, 0.14, white)
	var hang := base + basis * Vector3(0.2, 2.1, 0)
	b.tube(HollowmereProps.organic(), PackedVector3Array([hang, hang - Vector3(0, 0.9, 0)]), PackedFloat32Array([0.015, 0.015]), 3, HollowmereProps.ROPE)
	var bd := HollowmereProps.body(parent, "WellCollider")
	HollowmereProps.shape_cyl(bd, r_out + 0.05, 1.2, base + Vector3(0, 0.3, 0))
	return hang - Vector3(0, 0.9, 0)


## Market stall: posts, plank counter, sagging torn awning. Returns the counter top centre.
static func market_stall(parent: Node3D, tb: HollowmereBatch, b: HollowmereBatch, base: Vector3, yaw: float, rng: RandomNumberGenerator, butcher := false) -> Vector3:
	var basis := Basis(Vector3.UP, yaw)
	var wood := RetroMaterials.wood()
	var white := Color(1, 1, 1)
	var w := 2.6
	var d := 1.2
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var hgt := 2.3 if sz < 0.0 else 2.0
			tb.box(wood, HollowmereProps.xfm(basis, base + basis * Vector3(sx * w * 0.5, hgt * 0.5, sz * d * 0.5)), Vector3(0.12, hgt, 0.12), white)
	tb.box(wood, HollowmereProps.xfm(basis, base + basis * Vector3(0, 0.9, 0.1)), Vector3(w + 0.1, 0.08, d * 0.75), white)
	tb.box(wood, HollowmereProps.xfm(basis, base + basis * Vector3(0, 0.5, d * 0.45)), Vector3(w, 0.75, 0.05), white)
	# Awning cloth: grid between the post tops, sagging, edge torn.
	var c1: Color = HollowmereProps.CLOTH[rng.randi() % HollowmereProps.CLOTH.size()]
	var c2: Color = HollowmereProps.CLOTH[(rng.randi() + 1) % HollowmereProps.CLOTH.size()]
	var nu := 6
	var nv := 3
	var pts := PackedVector3Array()
	var cols := PackedColorArray()
	var hints := PackedVector3Array()
	for vi in nv + 1:
		var s := float(vi) / nv
		for ui in nu + 1:
			var u := float(ui) / nu
			var lp := Vector3(lerpf(-w * 0.55, w * 0.55, u), lerpf(2.32, 1.95,
					s) - 0.18 * sin(PI * u) * sin(PI * s) - (0.25 * s * s if vi == nv and ui % 2 == 1 else 0.0), lerpf(-d * 0.55, d * 0.75, s))
			pts.append(base + basis * lp)
			cols.append(HollowmereProps.jit(c1 if ui % 2 == 0 else c2, rng, 0.08))
			hints.append(Vector3.UP)
	var torn := rng.randi_range(0, nu - 1)
	b.grid(HollowmereProps.foliage(), pts, nu + 1, nv + 1, false, cols, hints, func(r: int, cc: int) -> bool:
		return r == nv - 1 and cc == torn)
	var bd := HollowmereProps.body(parent, "StallCollider")
	HollowmereProps.shape_box(bd, Vector3(w + 0.1, 1.0, d * 0.8), HollowmereProps.xfm(basis, base + basis * Vector3(0, 0.5, 0.1)))
	if butcher:
		# Hooks with cuts of meat nobody will name.
		tb.beam(RetroMaterials.iron(), base + basis * Vector3(-w * 0.5, 1.9, 0.3), base + basis * Vector3(w * 0.5, 1.9, 0.3), 0.04, 0.04, white)
		for k in 4:
			var hx := -w * 0.35 + k * w * 0.23
			var hp := base + basis * Vector3(hx, 1.86, 0.3)
			tb.beam(RetroMaterials.iron(), hp, hp - Vector3(0, 0.2, 0), 0.02, 0.02, white)
			var lump := rng.randf_range(0.14, 0.22)
			b.blob(HollowmereProps.flesh(), hp - Vector3(0, 0.2 + lump, 0), basis, Vector3(lump * 0.8, lump * 1.4,
					lump * 0.6), 7, 5, HollowmereProps.RAW, 0.25, rng.randf() * 7.0, func(dd: Vector3, _k: float) -> Color:
				return HollowmereProps.wa(HollowmereProps.RAW.lerp(HollowmereProps.SKIN, clampf(dd.x * 1.5, 0.0, 0.8)), 0.0))
			b.beam(HollowmereProps.flesh(), hp - Vector3(0, 0.3 + lump * 2.0, 0), base + basis * Vector3(hx, 0.95, 0.25), 0.02, 0.02, HollowmereProps.wa(HollowmereProps.BLOOD, 0.0))
	return base + basis * Vector3(0, 0.95, 0.1)


## Gravestone (stone): 0 round-topped slab, 1 stone cross, 2 obelisk. Leaning.
static func gravestone(tb: HollowmereBatch, base: Vector3, yaw: float, kind: int, rng: RandomNumberGenerator) -> void:
	var stone := RetroMaterials.mossy_stone() if rng.randf() < 0.4 else RetroMaterials.stone()
	var white := Color(1, 1, 1)
	var basis := Basis(Vector3.UP, yaw) * Basis.from_euler(Vector3(rng.randf_range(-0.25, 0.25), 0, rng.randf_range(-0.2, 0.2)))
	var s := rng.randf_range(0.8, 1.2)
	var xf := Transform3D(basis, base - Vector3(0, 0.15, 0))
	if kind == 0:
		var hgt := 0.85 * s
		var wd := 0.55 * s
		var poly := PackedVector2Array([Vector2(-wd * 0.5, 0), Vector2(wd * 0.5, 0), Vector2(wd * 0.5, hgt)])
		for k in 5:
			var a := PI * (k + 1) / 6.0
			poly.append(Vector2(cos(a) * wd * 0.5, hgt + sin(a) * wd * 0.45))
		poly.append(Vector2(-wd * 0.5, hgt))
		tb.prism(stone, xf, poly, 0.14 * s, white)
	elif kind == 1:
		tb.box(stone, xf * HollowmereProps.xfm(Basis.IDENTITY, Vector3(0, 0.6 * s, 0)), Vector3(0.14, 1.2 * s, 0.14) * Vector3(s, 1, s), white)
		tb.box(stone, xf * HollowmereProps.xfm(Basis.IDENTITY, Vector3(0, 0.9 * s, 0)), Vector3(0.6 * s, 0.13, 0.13), white)
		tb.box(stone, xf * HollowmereProps.xfm(Basis.IDENTITY, Vector3(0, 0.06, 0)), Vector3(0.4, 0.2, 0.3), white)
	else:
		tb.box(stone, xf * HollowmereProps.xfm(Basis.IDENTITY, Vector3(0, 0.12, 0)), Vector3(0.5, 0.3, 0.5), white)
		tb.tube(stone, PackedVector3Array([xf * Vector3(0, 0.25, 0), xf * Vector3(0, 1.4 * s, 0), xf * Vector3(0, 1.62 * s, 0)]), PackedFloat32Array([0.26, 0.16, 0.0]), 4, white)
