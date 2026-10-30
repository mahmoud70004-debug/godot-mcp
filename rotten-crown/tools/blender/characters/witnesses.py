"""Phase 3d Witnesses (PLAN C12): harmless weirdcore entities that speak to the knight.
  star  - the Star-Eyed Gentleman: an immaculate black suit; the head is a flat five-pointed star with
          one huge realistic eye in its centre.
  root  - the Root Saint: a pale floating figure with a long face and empty eyes whose arms and legs
          branch into pale roots.
  chair - the Chair Man: long-necked, top-hatted, pale-faced, sitting on a too-tall thin wooden chair,
          head tilted 90 degrees, hands folded.
Anims: idle (8 frames, loop) and speak (10 frames, loop). The face always turns to the viewer.

  $BLENDER -b --factory-startup --python tools/blender/characters/witnesses.py -- --type star|root|chair
           [--preview] [--only idle] [--dirs 0,2,4] [--stills idle:0,speak:0.5]
Writes build/sprites_raw/witness_<type>/; then `python3 tools/pixelize_sprites.py witness_<type>`.
"""
import argparse
import math
import os
import random
import sys

import bmesh
from mathutils import Matrix

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from rc_blender import geo, kin, mat, sprite_render  # noqa: E402
from rc_blender.kin import V, pivot  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
OUT = os.path.join(ROOT, "build", "sprites_raw")
CACHE = os.path.join(ROOT, "build", "blender_cache")

ANIMS = {
    "idle": {"frames": 8, "fps": 4, "loop": True},
    "speak": {"frames": 10, "fps": 10, "loop": True},
}


def jitter(t, frames, amp, seed=0.0):
    k = round(t * frames) % frames
    return amp * math.sin(k * 2.7 + seed * 1.3) * (0.6 + 0.4 * math.sin(k * 5.1 + seed))


def scaled(m, c, sx=1.0, sy=1.0, sz=1.0):
    """m @ scale about point c (character axes)."""
    s = Matrix.Diagonal((sx, sy, sz, 1.0))
    return m @ Matrix.Translation(V(c)) @ s @ Matrix.Translation(-V(c))


def cap(name, center, radius, material, keep_above=-0.12, segments=20, rings=12):
    """Spherical cap (eyelid): the part of a sphere above z > keep_above * radius, around +Z."""
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segments, v_segments=rings, radius=radius)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < keep_above * radius], context="VERTS")
    obj = geo.mesh_object(name, bm, material)
    geo.solidify(obj, radius * 0.12, 1.0)
    obj.location = tuple(center)
    return obj


def star_prism(name, c, r_out, r_in, depth, puff, material, points=5, rot_deg=0.0):
    """Flat, slightly puffy five-pointed star in the XZ plane, facing -Y."""
    c = V(c)
    bm = bmesh.new()
    ring = []
    for i in range(points * 2):
        a = math.radians(90 + rot_deg + 180.0 * i / points)
        r = r_out if i % 2 == 0 else r_in
        ring.append((math.cos(a) * r, math.sin(a) * r))

    def lay(y, k):
        return [bm.verts.new((c.x + x * k, c.y + y, c.z + z)) for x, z in ring]

    f_out, f_mid = lay(-depth / 2, 1.0), lay(-depth / 2 - puff * 0.7, 0.55)
    b_out, b_mid = lay(depth / 2, 1.0), lay(depth / 2 + puff * 0.4, 0.55)
    fc = bm.verts.new((c.x, c.y - depth / 2 - puff, c.z))
    bc = bm.verts.new((c.x, c.y + depth / 2 + puff * 0.5, c.z))
    n = len(ring)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((f_out[i], f_out[j], b_out[j], b_out[i]))
        bm.faces.new((f_mid[i], f_mid[j], f_out[j], f_out[i]))
        bm.faces.new((fc, f_mid[j], f_mid[i]))
        bm.faces.new((b_out[i], b_out[j], b_mid[j], b_mid[i]))
        bm.faces.new((bc, b_mid[i], b_mid[j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return geo.mesh_object(name, bm, material)


class Mats:
    def __init__(self):
        self.suit = mat.cloth("suit", (0.025, 0.025, 0.03), rough=0.75, sheen=0.4, weave=160.0, fray=0.08)
        self.shirt = mat.cloth("shirt", (0.82, 0.82, 0.78), rough=0.7, sheen=0.2, weave=200.0, fray=0.05)
        self.tie = mat.flat("tie", (0.012, 0.012, 0.016), rough=0.3)
        self.shoe = mat.flat("shoe", (0.02, 0.018, 0.018), rough=0.2)
        self.skin = mat.cloth("skin", (0.72, 0.66, 0.6), rough=0.5, sheen=0.1, weave=2.0, fray=0.15)
        self.star = mat.cloth("star_skin", (0.46, 0.4, 0.17), rough=0.65, sheen=0.1, weave=14.0, fray=0.35)
        self.sclera = mat.cloth("sclera", (0.8, 0.76, 0.68), rough=0.15, sheen=0.0, weave=30.0, fray=0.12)
        self.iris = mat.cloth("iris", (0.24, 0.2, 0.09), rough=0.2, sheen=0.0, weave=40.0, fray=0.4)
        self.void = mat.flat("void", (0.0, 0.0, 0.0), rough=0.2)
        self.pale = mat.cloth("saint_skin", (0.8, 0.78, 0.7), rough=0.55, sheen=0.15, weave=2.0, fray=0.12)
        self.root = mat.cloth("root", (0.66, 0.6, 0.5), rough=0.75, sheen=0.05, weave=20.0, fray=0.35)
        self.dirt = mat.cloth("dirt", (0.2, 0.15, 0.1), rough=0.9, sheen=0.0, weave=10.0, fray=0.3)
        self.wood = mat.cloth("wood", (0.22, 0.13, 0.07), rough=0.6, sheen=0.05, weave=4.0, fray=0.3)
        self.coat = mat.cloth("coat", (0.075, 0.025, 0.035), rough=0.8, sheen=0.35, weave=120.0, fray=0.12)
        self.hat = mat.cloth("hat", (0.02, 0.02, 0.022), rough=0.5, sheen=0.5, weave=200.0, fray=0.05)
        self.face = mat.cloth("face_paint", (0.84, 0.8, 0.76), rough=0.45, sheen=0.1, weave=2.0, fray=0.1)
        self.lips = mat.flat("lips", (0.42, 0.06, 0.07), rough=0.35)


# =============================================================================== THE STAR-EYED GENTLEMAN

STAR_C = V(0, -0.01, 1.98)
EYE_C = V(0, -0.08, 1.98)
EYE_R = 0.1
NECK_TOP = V(0, 0.0, 1.68)


def star_build(m, rng):
    bones = [("body", (0, 0, 0.0), (0, 0, 1.5)), ("neck", (0, 0, 1.5), tuple(NECK_TOP)),
             ("head", tuple(NECK_TOP), tuple(STAR_C)), ("eye", tuple(EYE_C), tuple(EYE_C + V(0, -0.1, 0))),
             ("pupil", tuple(EYE_C), tuple(EYE_C + V(0, -0.1, 0.01))),
             ("lid_u", tuple(EYE_C), tuple(EYE_C + V(0, 0, 0.1))), ("lid_l", tuple(EYE_C), tuple(EYE_C + V(0, 0, -0.1)))]
    r = kin.MatrixRig("star_rig", bones)
    A = r.attach
    parts = []
    for sx in (1, -1):
        parts.append(geo.box("shoe", (0.1, 0.27, 0.075), (sx * 0.1, -0.05, 0.04), m.shoe, bevel=0.03))
        parts.append(geo.loft("trouser", [dict(z=0.07, rx=0.062, ry=0.07, x=sx * 0.1), dict(z=0.5, rx=0.07, ry=0.075, x=sx * 0.1),
                                          dict(z=0.95, rx=0.095, ry=0.095, x=sx * 0.095)], m.suit, 14))
        # sleeves hanging dead straight, white cuffs, pale hands with slightly too long fingers
        parts.append(geo.loft("sleeve", [dict(z=0.84, rx=0.05, ry=0.055, x=sx * 0.265, y=0.01),
                                         dict(z=1.2, rx=0.06, ry=0.065, x=sx * 0.255),
                                         dict(z=1.44, rx=0.07, ry=0.075, x=sx * 0.235)], m.suit, 12))
        parts.append(geo.loft("cuff", [dict(z=0.81, rx=0.046, ry=0.05, x=sx * 0.266, y=0.01),
                                       dict(z=0.85, rx=0.048, ry=0.052, x=sx * 0.266, y=0.01)], m.shirt, 12))
        parts.append(kin.blob("hand", (sx * 0.268, 0.0, 0.75), 0.045, m.skin, scale=(0.55, 0.9, 1.3)))
        for j in range(4):
            parts.append(kin.tube("finger", [V(sx * 0.27, -0.03 + 0.02 * j, 0.71), V(sx * 0.272, -0.035 + 0.02 * j, 0.62),
                                             V(sx * 0.265, -0.04 + 0.02 * j, 0.57)], [0.011, 0.009, 0.0], m.skin, 6))
    parts.append(geo.loft("hips", [dict(z=0.86, rx=0.17, ry=0.115), dict(z=1.0, rx=0.17, ry=0.115)], m.suit, 18))
    jacket = geo.loft("jacket", [dict(z=0.76, rx=0.205, ry=0.145), dict(z=1.0, rx=0.18, ry=0.125), dict(z=1.3, rx=0.2, ry=0.13),
                                 dict(z=1.43, rx=0.245, ry=0.135), dict(z=1.47, rx=0.235, ry=0.13), dict(z=1.53, rx=0.09, ry=0.08)],
                      m.suit, 24, cap_bottom=False)
    parts.append(jacket)
    # the white V of the shirt, the lapels, a black tie and a pocket square
    bm = bmesh.new()
    vs = [bm.verts.new(p) for p in ((-0.085, -0.134, 1.5), (0.085, -0.134, 1.5), (0.0, -0.128, 1.1))]
    bm.faces.new(vs)
    shirt = geo.mesh_object("shirt_v", bm, m.shirt, smooth=False)
    geo.solidify(shirt, 0.006)
    parts.append(shirt)
    for sx in (1, -1):
        parts.append(kin.tube("lapel", [V(sx * 0.085, -0.137, 1.5), V(sx * 0.07, -0.142, 1.36), V(sx * 0.0, -0.133, 1.1)],
                              [0.012, 0.02, 0.006], m.tie, 6, squash=0.3, normal=(1, 0, 0)))
    parts.append(geo.box("knot", (0.04, 0.02, 0.035), (0, -0.142, 1.475), m.tie, bevel=0.008))
    parts.append(kin.tube("tie", [V(0, -0.142, 1.46), V(0, -0.145, 1.3), V(0, -0.14, 1.16), V(0, -0.138, 1.12)],
                          [0.018, 0.024, 0.026, 0.0], m.tie, 8, squash=0.25, normal=(1, 0, 0)))
    parts.append(geo.box("pocket", (0.05, 0.01, 0.022), (0.12, -0.135, 1.33), m.shirt, bevel=0.003, rotation=(0, 0, 0.1)))
    parts.append(geo.loft("collar", [dict(z=1.49, rx=0.07, ry=0.065), dict(z=1.56, rx=0.06, ry=0.058)], m.shirt, 16,
                          cap_bottom=False, cap_top=False))
    A(geo.join(parts, "body"), "body")
    A(kin.tube("neck", [V(0, 0, 1.5), V(0, 0, 1.6), NECK_TOP + V(0, 0, 0.04)], 0.048, m.skin, 12), "neck")
    # the head: a flat five-pointed star, one huge eye in its centre
    A(star_prism("star", STAR_C, 0.37, 0.16, 0.075, 0.04, m.star, rot_deg=4.0), "head")
    A(kin.blob("socket", EYE_C + V(0, 0.02, 0), EYE_R * 1.12, m.star, scale=(1.08, 0.6, 0.95), segments=20, rings=12), "head")
    A(kin.blob("eyeball", EYE_C, EYE_R, m.sclera, segments=24, rings=16), "eye")
    A(kin.blob("iris", EYE_C + V(0, -EYE_R * 0.86, 0), EYE_R * 0.5, m.iris, scale=(1, 0.3, 1), segments=20, rings=10), "eye")
    A(kin.blob("pupil", EYE_C + V(0, -EYE_R * 0.97, 0), EYE_R * 0.22, m.void, scale=(1, 0.25, 1), segments=14, rings=8), "pupil")
    up = cap("lid_up", EYE_C, EYE_R * 1.07, m.star)
    lo = cap("lid_lo", EYE_C, EYE_R * 1.06, m.star)
    lo.rotation_euler = (math.pi, 0, 0)
    A(up, "lid_u")
    A(lo, "lid_l")
    return r


def star_pose(r, anim, t, yaw):
    nf = ANIMS[anim]["frames"]
    k = round(t * nf) % nf
    a = math.tau * t
    tilt = 0.0
    look = (0.0, 0.0)
    lid_u, lid_l = -42.0, 44.0          # open (degrees about X at the eye centre)
    pupil = 1.0
    sway = 0.0
    if anim == "idle":
        # utterly still; only the eye moves: drifts, settles on you, drifts, one slow blink
        look = [(0, 0), (-14, 3), (-20, 4), (-6, 0), (0, 0), (0, 0), (16, -4), (8, -2)][k]
        if k == 5:
            lid_u, lid_l = 86.0, -18.0
        sway = 0.4 * math.sin(a)
    else:
        # the star tilts and trembles, the eye stares wide, pupil shrinking
        tilt = 9 * math.sin(a) + jitter(t, nf, 3.5, 1)
        look = (jitter(t, nf, 3, 2), jitter(t, nf, 2, 3))
        lid_u, lid_l = -62.0, 62.0
        pupil = 0.62 + 0.12 * math.sin(2 * a)
        sway = jitter(t, nf, 0.4, 4)
    mb = pivot(kin.I4, (0, 0, 0), 0, sway * 0.3, 0)
    r.set("body", mb)
    mn = pivot(mb, (0, 0, 1.5), 0, 0, -yaw * 0.4)
    r.set("neck", mn)
    mh = pivot(mn, NECK_TOP, 0, tilt, -yaw * 0.6)
    r.set("head", mh)
    me = pivot(mh, EYE_C, look[1], 0, look[0])
    r.set("eye", me)
    r.set("pupil", scaled(me, EYE_C + V(0, -EYE_R, 0), pupil, 1.0, pupil))
    r.set("lid_u", pivot(mh, EYE_C, lid_u, 0, 0))
    r.set("lid_l", pivot(mh, EYE_C, lid_l, 0, 0))
    r.apply()


def star_table(m):
    return [(m.suit, 3), (m.shirt, 3), (m.tie, 2), (m.shoe, 2), (m.skin, 4), (m.star, 5), (m.sclera, 4), (m.iris, 3),
            (m.void, 1)]


# =============================================================================== THE ROOT SAINT

SAINT_HEAD = V(0, 0.0, 1.96)
SAINT_NECK = V(0, 0.0, 1.62)
SAINT_JAW = V(0, -0.05, 1.86)


def _grow(rng, p, d, length, radius, depth, max_depth, out, droop, spread, plane_y=0.25):
    """Branching root: appends (points, radii) and recurses. droop bends towards -Z, spread = child angle."""
    d = d.normalized()
    n = 6
    pts, rad = [p.copy()], [radius]
    cur = p.copy()
    dd = d.copy()
    for i in range(1, n):
        dd = (dd + V(rng.uniform(-0.25, 0.25), rng.uniform(-plane_y, plane_y), rng.uniform(-0.25, 0.25) - droop)).normalized()
        cur = cur + dd * (length / (n - 1))
        pts.append(cur.copy())
        rad.append(radius * (1.0 - 0.55 * i / (n - 1)))
    if depth >= max_depth:
        rad[-1] = 0.0
    out.append((pts, rad, depth))
    if depth < max_depth:
        kids = 2 if depth > 0 or rng.random() < 0.5 else 3
        for c in range(kids):
            ang = math.radians(spread * (c - (kids - 1) / 2.0) + rng.uniform(-10, 10))
            axis = dd.cross(V(0, 1, 0))
            if axis.length < 1e-3:
                axis = V(1, 0, 0)
            nd = Matrix.Rotation(ang, 3, V(0, 1, 0)) @ dd
            nd = (nd + V(0, rng.uniform(-0.3, 0.3), 0)).normalized()
            _grow(rng, cur, nd, length * rng.uniform(0.6, 0.8), rad[-1] * 0.95, depth + 1, max_depth, out, droop, spread * 0.9,
                  plane_y)


def root_build(m, rng):
    bones = [("body", (0, 0, 1.0), (0, 0, 1.58)), ("neck", tuple(SAINT_NECK), tuple(SAINT_HEAD)),
             ("head", tuple(SAINT_HEAD), tuple(SAINT_HEAD + V(0, 0, 0.25))), ("jaw", tuple(SAINT_JAW), tuple(SAINT_JAW + V(0, 0, -0.1)))]
    arm_roots, leg_roots = {}, {}
    for s, sx in (("L", 1.0), ("R", -1.0)):
        sh, el, wr = V(sx * 0.15, 0, 1.56), V(sx * 0.42, 0, 1.66), V(sx * 0.66, 0, 1.74)
        bones += [("arm_up." + s, tuple(sh), tuple(el)), ("arm_lo." + s, tuple(el), tuple(wr))]
        arm_roots[s] = []
        for j, ang in enumerate((52, 18, -14, -44)):
            d = Matrix.Rotation(math.radians(-ang * sx), 3, V(0, 1, 0)) @ V(sx, 0, 0)
            d = (d + V(0, (j - 1.5) * 0.12, 0)).normalized()
            out = []
            _grow(rng, wr.copy(), d, 0.3, 0.036, 0, 3, out, 0.02 if ang > 0 else 0.06, 44, 0.15)
            arm_roots[s].append(out)
            bones.append(("aroot%d.%s" % (j, s), tuple(wr), tuple(wr + d * 0.3)))
        hp, kn = V(sx * 0.08, 0, 1.0), V(sx * 0.1, -0.02, 0.8)
        bones.append(("thigh." + s, tuple(hp), tuple(kn)))
        leg_roots[s] = []
        for j in range(3):
            d = V(sx * (0.12 + 0.28 * j), (j - 1) * 0.35, -1.0).normalized()
            out = []
            _grow(rng, kn.copy(), d, 0.3, 0.04, 0, 3, out, 0.25, 34, 0.35)
            leg_roots[s].append(out)
            bones.append(("lroot%d.%s" % (j, s), tuple(kn), tuple(kn + d * 0.3)))
    r = kin.MatrixRig("root_rig", bones)
    A = r.attach
    # slender pale body, the ribs and collarbones faintly showing
    torso = geo.loft("torso", [dict(z=0.98, rx=0.12, ry=0.085), dict(z=1.2, rx=0.095, ry=0.07), dict(z=1.42, rx=0.14, ry=0.085),
                               dict(z=1.55, rx=0.15, ry=0.08), dict(z=1.6, rx=0.06, ry=0.05)], m.pale, 20)
    ribs = []
    for i in range(4):
        z = 1.3 + i * 0.05
        ribs.append(kin.tube("rib", [V(x * 0.13, -0.06 - 0.02 * (1 - abs(x)), z - 0.02 * abs(x)) for x in (-1, -0.5, 0.5, 1)],
                             0.008, m.root, 6))
    A(geo.join([torso] + ribs, "torso"), "body")
    A(kin.tube("neck", [SAINT_NECK + V(0, 0, -0.04), SAINT_NECK + V(0, 0, 0.12), SAINT_HEAD + V(0, 0, -0.1)], 0.04, m.pale, 10),
      "neck")
    # a long, long face; empty eyes; the mouth is on the jaw so it can stretch downwards
    hc = SAINT_HEAD + V(0, 0, 0.02)
    skull = kin.blob("skull", hc, 0.12, m.pale, scale=(0.78, 0.82, 1.85), segments=22, rings=16)
    eyes = [kin.blob("eye", hc + V(sx * 0.038, -0.088, 0.06), 0.022, m.void, scale=(0.8, 0.5, 1.6)) for sx in (1, -1)]
    brow = kin.blob("brow", hc + V(0, -0.075, 0.11), 0.05, m.pale, scale=(1.4, 0.5, 0.4))
    nose = kin.tube("nose", [hc + V(0, -0.095, 0.05), hc + V(0, -0.11, -0.02), hc + V(0, -0.1, -0.04)], [0.01, 0.014, 0.0], m.pale, 8)
    A(geo.join([skull, brow, nose] + eyes, "head"), "head")
    A(geo.join([kin.blob("mouth", SAINT_JAW + V(0, -0.045, -0.0), 0.022, m.void, scale=(0.9, 0.5, 1.4)),
                kin.blob("chin", SAINT_JAW + V(0, -0.02, -0.06), 0.045, m.pale, scale=(1.1, 0.8, 0.7))], "jaw"), "jaw")
    for s, sx in (("L", 1.0), ("R", -1.0)):
        sh, el = r.rest["arm_up." + s]
        wr = r.tail("arm_lo." + s)
        A(kin.tube("arm_up", [sh, el], [0.04, 0.032], m.pale, 10), "arm_up." + s)
        A(geo.join([kin.tube("arm_lo", [el, wr], [0.032, 0.024], m.pale, 10),
                    kin.blob("wrist_knot", wr, 0.032, m.root, scale=(1.2, 1, 1))], "arm_lo"), "arm_lo." + s)
        for j, out in enumerate(arm_roots[s]):
            A(geo.join([kin.tube("root", pts, rad, m.root if dep else m.pale, 6 if dep > 1 else 8) for pts, rad, dep in out],
                       "aroot"), "aroot%d.%s" % (j, s))
        hp, kn = r.rest["thigh." + s]
        A(geo.join([kin.tube("thigh", [hp, kn], [0.065, 0.05], m.pale, 10), kin.blob("knee_knot", kn, 0.052, m.root)], "thigh"),
          "thigh." + s)
        for j, out in enumerate(leg_roots[s]):
            tips = [kin.blob("dirt", pts[-2], rad[-2] * 1.6 + 0.004, m.dirt, segments=6, rings=4) for pts, rad, dep in out if dep == 3]
            A(geo.join([kin.tube("root", pts, rad, m.root, 6) for pts, rad, dep in out] + tips, "lroot"), "lroot%d.%s" % (j, s))
    return r


def root_pose(r, anim, t, yaw):
    nf = ANIMS[anim]["frames"]
    a = math.tau * t
    speak = anim == "speak"
    hover = 0.05 * math.sin(a) + 0.03
    mb = kin.move(pivot(kin.I4, (0, 0, 1.2), 1.5 * math.sin(a + 0.5), 1.0 * math.sin(a), 0), (0, 0, hover))
    r.set("body", mb)
    mn = pivot(mb, SAINT_NECK, 0, 0, -yaw * 0.5)
    r.set("neck", mn)
    tilt = 6 * math.sin(a + 1.0) + (jitter(t, nf, 5, 1) if speak else 0.0)
    mh = pivot(mn, SAINT_NECK + V(0, 0, 0.14), (jitter(t, nf, 3, 2) if speak else 0.0), tilt, -yaw * 0.5)
    r.set("head", mh)
    stretch = (1.0 + 0.9 * (0.5 + 0.5 * math.sin(2 * a))) if speak else 1.0 + 0.1 * (0.5 + 0.5 * math.sin(a))
    drop = (stretch - 1.0) * 0.05
    r.set("jaw", scaled(mh @ Matrix.Translation(V(0, 0, -drop)), SAINT_JAW, 1.0 - 0.15 * (stretch - 1.0), 1.0, stretch))
    for s, sx in (("L", 1.0), ("R", -1.0)):
        lift = 4 * math.sin(a + (0 if s == "L" else 1.2))
        mu = pivot(mb, r.head("arm_up." + s), 0, -sx * lift, 0)
        r.set("arm_up." + s, mu)
        ml = pivot(mu, r.head("arm_lo." + s), 0, -sx * lift * 0.6, 0)
        r.set("arm_lo." + s, ml)
        for j in range(4):
            b = "aroot%d.%s" % (j, s)
            curl = 7 * math.sin(a + j * 0.9 + (0 if s == "L" else 2.0))
            if speak:
                curl += jitter(t, nf, 6, j + (5 if s == "L" else 9))
            r.set(b, pivot(ml, r.head(b), curl * 0.4, -sx * curl, 0))
        mt = pivot(mb, r.head("thigh." + s), 3 * math.sin(a + 0.4), 0, 0)
        r.set("thigh." + s, mt)
        for j in range(3):
            b = "lroot%d.%s" % (j, s)
            sw = 6 * math.sin(a + j * 1.3 + (0 if s == "L" else 0.7))
            if speak:
                sw += jitter(t, nf, 5, j + (13 if s == "L" else 17))
            r.set(b, pivot(mt, r.head(b), sw, sx * sw * 0.6, 0))
    r.apply()


def root_table(m):
    return [(m.pale, 6), (m.root, 4), (m.dirt, 2), (m.void, 1)]


# =============================================================================== THE CHAIR MAN

SEAT_Z = 1.15
CHAIR_NECK_LO = V(0, 0.08, 1.92)
CHAIR_NECK_HI = V(0, 0.02, 2.14)
CHAIR_HEAD = V(0, -0.04, 2.36)


def chair_build(m, rng):
    bones = [("body", (0, 0.1, SEAT_Z), (0, 0.08, 1.9)), ("chair", (0, 0, 0), (0, 0, 1.0)),
             ("neck_lo", tuple(CHAIR_NECK_LO), tuple(CHAIR_NECK_HI)), ("neck_hi", tuple(CHAIR_NECK_HI), tuple(CHAIR_HEAD)),
             ("head", tuple(CHAIR_HEAD), tuple(CHAIR_HEAD + V(0, 0, 0.25))),
             ("jaw", tuple(CHAIR_HEAD + V(0, -0.02, -0.06)), tuple(CHAIR_HEAD + V(0, -0.1, -0.12)))]
    r = kin.MatrixRig("chair_rig", bones)
    A = r.attach
    # --- a too-tall thin ladder-back chair, slightly crooked
    parts = [geo.box("seat", (0.48, 0.44, 0.04), (0, 0.08, SEAT_Z - 0.02), m.wood, bevel=0.006)]
    for x in (-0.21, 0.21):
        for y in (-0.12, 0.28):
            top = SEAT_Z - 0.04 if y < 0 else 2.1 + (0.03 if x > 0 else 0.0)
            lean = 0.0 if y < 0 else 0.05
            pts = [V(x * 1.04, y, 0), V(x, y + lean * 0.4, SEAT_Z)]
            if y > 0:
                pts.append(V(x * 0.97, y + lean, top))
            parts.append(kin.tube("leg", pts, 0.02, m.wood, 6, smooth_shade=False))
    for z in (0.32, 0.72):
        for y in (-0.12, 0.28):
            parts.append(kin.tube("rung", [V(-0.215, y, z), V(0.215, y, z)], 0.013, m.wood, 6))
        for x in (-0.215, 0.215):
            parts.append(kin.tube("rung", [V(x, -0.12, z + 0.05), V(x, 0.28, z + 0.05)], 0.013, m.wood, 6))
    for i, z in enumerate((1.5, 1.72, 1.94, 2.08)):
        parts.append(geo.box("slat", (0.42, 0.02, 0.05 if i < 3 else 0.035), (0, 0.28 + 0.05 * (z - SEAT_Z) / 0.95 + 0.012, z), m.wood,
                             bevel=0.005, rotation=(0, 0.03 * (i - 1.5), 0)))
    A(geo.join(parts, "chair"), "chair")
    # --- the long man: coat to the seat, thin thighs forward, shins hanging, feet far above the floor
    body = []
    body.append(geo.loft("coat", [dict(z=SEAT_Z + 0.02, rx=0.19, ry=0.17, y=0.1), dict(z=1.4, rx=0.16, ry=0.13, y=0.1),
                                  dict(z=1.7, rx=0.17, ry=0.12, y=0.09), dict(z=1.86, rx=0.21, ry=0.12, y=0.085),
                                  dict(z=1.94, rx=0.08, ry=0.07, y=0.08)], m.coat, 22))
    for sx in (1, -1):
        hp, kn, an = V(sx * 0.09, 0.05, SEAT_Z + 0.08), V(sx * 0.1, -0.34, SEAT_Z + 0.09), V(sx * 0.1, -0.38, 0.66)
        body.append(kin.tube("thigh", [hp, kn], [0.075, 0.06], m.coat, 12))
        body.append(kin.tube("shin", [kn, an], [0.055, 0.045], m.coat, 12))
        body.append(kin.blob("knee", kn, 0.06, m.coat))
        body.append(kin.tube("shoe", [an + V(0, 0.04, -0.02), an + V(0, -0.1, -0.05), an + V(0, -0.2, -0.04)], [0.04, 0.04, 0.0],
                             m.hat, 10))
        sh, el = V(sx * 0.2, 0.08, 1.86), V(sx * 0.25, 0.0, 1.46)
        hand = V(sx * 0.05, -0.2, 1.3)
        body.append(geo.join([kin.tube("arm", [sh, el, hand + V(sx * 0.06, 0.04, 0.02)], [0.06, 0.052, 0.045], m.coat, 12),
                              kin.blob("shoulder", sh, 0.065, m.coat)], "arm"))
        body.append(kin.blob("hand", hand, 0.05, m.face, scale=(1.3, 0.9, 0.55)))
        for j in range(4):
            base = hand + V(sx * 0.02, -0.03 + j * 0.018, 0.01)
            body.append(kin.tube("finger", [base, base + V(-sx * 0.08, -0.03, -0.015), base + V(-sx * 0.13, -0.02, -0.05)],
                                 [0.011, 0.009, 0.0], m.face, 6))
    body.append(geo.loft("collar", [dict(z=1.9, rx=0.07, ry=0.06, y=0.08), dict(z=1.98, rx=0.055, ry=0.05, y=0.07)], m.face, 14,
                         cap_bottom=False, cap_top=False))
    A(geo.join(body, "man"), "body")
    A(kin.tube("neck_lo", [CHAIR_NECK_LO + V(0, 0, -0.04), CHAIR_NECK_HI + V(0, 0, 0.02)], [0.045, 0.042], m.face, 10), "neck_lo")
    A(kin.tube("neck_hi", [CHAIR_NECK_HI + V(0, 0, -0.06), CHAIR_HEAD + V(0, 0, 0.03)], [0.04, 0.038], m.face, 10), "neck_hi")
    # head (modelled upright; the pose tilts it 90 degrees): white face, dark eyes, red mouth, top hat
    hc = CHAIR_HEAD + V(0, -0.02, 0.1)
    head = [kin.blob("skull", hc, 0.12, m.face, scale=(0.82, 0.9, 1.22), segments=22, rings=14)]
    for sx in (1, -1):
        head.append(kin.blob("socket", hc + V(sx * 0.042, -0.095, 0.03), 0.03, m.void, scale=(1.0, 0.45, 0.9)))
        head.append(kin.blob("glint", hc + V(sx * 0.042, -0.108, 0.035), 0.007, m.face, segments=6, rings=4))
    head.append(kin.tube("nose", [hc + V(0, -0.1, 0.02), hc + V(0, -0.13, -0.04), hc + V(0, -0.115, -0.05)], [0.012, 0.016, 0.0],
                         m.face, 8))
    head.append(kin.blob("lip", hc + V(0, -0.1, -0.085), 0.03, m.lips, scale=(1.1, 0.4, 0.35)))
    head.append(geo.cylinder("brim", 0.17, 0.17, 0.014, hc + V(0, 0.0, 0.135), m.hat, 24))
    head.append(geo.cylinder("crown", 0.098, 0.105, 0.3, hc + V(0, 0.0, 0.29), m.hat, 20))
    head.append(geo.cylinder("band", 0.106, 0.106, 0.035, hc + V(0, 0.0, 0.165), m.lips, 20))
    A(geo.join(head, "head"), "head")
    A(geo.join([kin.blob("mouth", hc + V(0, -0.098, -0.11), 0.026, m.void, scale=(0.9, 0.4, 0.5)),
                kin.blob("chin", hc + V(0, -0.075, -0.14), 0.045, m.face, scale=(1.1, 0.8, 0.6))], "jaw"), "jaw")
    return r


def chair_pose(r, anim, t, yaw):
    nf = ANIMS[anim]["frames"]
    a = math.tau * t
    speak = anim == "speak"
    r.set("chair", kin.I4)
    mb = pivot(kin.I4, (0, 0.1, SEAT_Z), 1.2 * math.sin(a), 0, 0)
    r.set("body", mb)
    mn = pivot(mb, CHAIR_NECK_LO, 4 + 2 * math.sin(a), 0, -yaw * 0.4)
    r.set("neck_lo", mn)
    stretch = 0.14 * (0.5 + 0.5 * math.sin(a * 2 - 1.0)) if speak else 0.015 * math.sin(a)
    up = (CHAIR_HEAD - CHAIR_NECK_HI).normalized() * stretch
    mh2 = Matrix.Translation(mn.to_3x3() @ up) @ pivot(mn, CHAIR_NECK_HI, 3 * math.sin(a), 0, -yaw * 0.3)
    r.set("neck_hi", mh2)
    tilt = 90 + 9 * math.sin(a) + (jitter(t, nf, 4, 1) if speak else 0.0)
    mh = pivot(mh2, CHAIR_HEAD, -6, tilt, -yaw * 0.3)
    r.set("head", mh)
    jaw = (12 + 12 * math.sin(a * 3)) if speak else 2.0
    r.set("jaw", pivot(mh, r.head("jaw"), -jaw, 0, 0) @ Matrix.Translation(V(0, 0, -0.004 * jaw)))
    r.apply()


def chair_table(m):
    return [(m.wood, 4), (m.coat, 4), (m.face, 5), (m.void, 1), (m.hat, 3), (m.lips, 2)]


# =============================================================================== registry

TYPES = {
    "star": dict(build=star_build, pose=star_pose, table=star_table, camera=3.3, center=1.15, height=150, seed=7),
    "root": dict(build=root_build, pose=root_pose, table=root_table, camera=3.6, center=1.2, height=160, seed=11),
    "chair": dict(build=chair_build, pose=chair_pose, table=chair_table, camera=3.6, center=1.4, height=180, seed=13),
}


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--type", default="star", choices=sorted(TYPES))
    ap.add_argument("--preview", action="store_true")
    ap.add_argument("--only", default="")
    ap.add_argument("--dirs", default="")
    ap.add_argument("--out", default=OUT)
    ap.add_argument("--stills", default="")
    args = ap.parse_args(argv)
    spec = TYPES[args.type]
    name = "witness_" + args.type
    sprite_render.clear_scene()
    sprite_render.setup_render(512, 6 if args.preview else 16)
    sprite_render.world_hdri("kloofendal_overcast_puresky", CACHE, strength=0.35, tint=(0.6, 0.7, 0.66))
    sprite_render.sun("key", (55, 0, -25), (0.85, 0.88, 0.82), 2.6, 10)
    sprite_render.sun("under", (150, 0, 20), (0.55, 0.65, 0.6), 0.5, 30)
    sprite_render.sun("rim", (60, 0, 160), (0.85, 0.95, 1.0), 2.6, 6)
    sprite_render.camera(spec["camera"], spec["center"])
    m = Mats()
    r = spec["build"](m, random.Random(spec["seed"]))

    def pose(anim, t):
        spec["pose"](r, anim, t, kin.viewer_yaw(r.obj))

    only = [a for a in args.only.split(",") if a]
    dirs = [int(d) for d in args.dirs.split(",") if d] or None
    if args.stills:
        sprite_render.render_stills(name, r.obj, pose, args.stills, args.out, dirs or [0, 2, 4])
        return
    sprite_render.render_character(name, r.obj, pose, ANIMS, args.out, 8, spec["camera"], spec["height"], 40,
                                   only or None, dirs, sprite_render.material_table(spec["table"](m)))


if __name__ == "__main__":
    main()
