"""Phase 3d monsters (PLAN C11): the Steeple, the Grinner and the Bent One. Non-human bodies on
rc_blender.kin MatrixRigs (parentless bones driven by character-space rigid motions + analytic IK).
Horror rule: no jump scares - wrong bodies. The head turns to face the viewer in every direction.

  $BLENDER -b --factory-startup --python tools/blender/characters/monsters.py -- --type steeple|grinner|bent
           [--preview] [--only idle,walk] [--dirs 0,2,4]
Writes build/sprites_raw/<type>/; then `python3 tools/pixelize_sprites.py <type>`.
"""
import argparse
import math
import os
import random
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from rc_blender import geo, humanoid, kin, mat, sprite_render  # noqa: E402
from rc_blender.kin import V, keys, pivot  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
OUT = os.path.join(ROOT, "build", "sprites_raw")
CACHE = os.path.join(ROOT, "build", "blender_cache")


def jitter(t, frames, amp, seed=0.0):
    """Frame-locked tremble: a different offset on every rendered frame."""
    k = round(t * (frames - 1))
    return amp * math.sin(k * 2.7 + seed * 1.3) * (0.6 + 0.4 * math.sin(k * 5.1 + seed))


class Mats:
    """Shared monster materials; each type picks its own table (max 15 ids)."""

    def __init__(self):
        self.black = mat.cloth("black_flesh", (0.022, 0.02, 0.026), rough=0.55, sheen=0.08, weave=3.0, fray=0.3)
        self.hood = mat.cloth("hood", (0.016, 0.015, 0.019), rough=0.85, sheen=0.3, weave=90.0, fray=0.2)
        self.skull = mat.cloth("skull", (0.74, 0.7, 0.6), rough=0.5, sheen=0.0, weave=4.0, fray=0.18)
        self.knob = mat.cloth("knob", (0.09, 0.08, 0.078), rough=0.45, sheen=0.1, weave=6.0, fray=0.2)
        self.ivory = mat.cloth("ivory", (0.62, 0.58, 0.48), rough=0.4, sheen=0.0, weave=5.0, fray=0.15)
        self.void = mat.flat("void", (0.0, 0.0, 0.0), rough=1.0)
        self.blood = mat.flat("blood", (0.2, 0.012, 0.018), rough=0.25)
        self.pale = mat.cloth("pale_skin", (0.66, 0.65, 0.58), rough=0.5, sheen=0.15, weave=2.0, fray=0.22)
        self.bruise = mat.cloth("bruise", (0.32, 0.27, 0.3), rough=0.55, sheen=0.1, weave=3.0, fray=0.3)
        self.teeth = mat.cloth("teeth", (0.8, 0.77, 0.66), rough=0.35, sheen=0.0, weave=8.0, fray=0.12)
        self.gum = mat.flat("gum", (0.32, 0.07, 0.08), rough=0.4)
        self.eye = mat.flat("eye_shine", (0.9, 0.9, 0.85), rough=0.1)


# =============================================================================== THE STEEPLE

STEEPLE_ANIMS = {
    "idle": {"frames": 8, "fps": 4, "loop": True},
    "walk": {"frames": 12, "fps": 8, "loop": True},
    "windup": {"frames": 12, "fps": 10, "loop": False},
    "strike": {"frames": 5, "fps": 14, "loop": False},
    "stagger": {"frames": 6, "fps": 10, "loop": False},
    "death": {"frames": 10, "fps": 8, "loop": False},
}

# legs: index 0 front (the stabbing pair), 1 middle, 2 back. (hip, knee, foot) for the left side.
STEEPLE_LEGS = [
    ((0.12, -0.12, 1.5), (0.5, -0.74, 2.1), (0.58, -1.12, 0.0)),
    ((0.14, 0.08, 1.42), (0.78, 0.02, 2.2), (0.95, 0.04, 0.0)),
    ((0.12, 0.3, 1.3), (0.58, 0.82, 2.04), (0.62, 1.1, 0.0)),
]
S_BODY_PIVOT = V(0, 0.1, 1.4)
S_CHEST_PIVOT = V(0, 0.08, 1.52)
S_NECK = V(0, -0.24, 1.56)
S_HEAD = V(0, -0.4, 1.7)
S_CONE = V(0, -0.42, 2.02)
S_SKULL = V(0, -0.46, 1.86)


def steeple_build(m, rng):
    bones = [("body", (0, 0.32, 1.28), (0, 0.08, 1.52)),
             ("chest", (0, 0.08, 1.52), (0, -0.22, 1.56)),
             ("neck", tuple(S_NECK), tuple(S_HEAD)),
             ("head", tuple(S_HEAD), tuple(S_CONE)),
             ("cone", tuple(S_CONE), (0, -0.3, 2.66))]
    for s, sx in (("L", 1.0), ("R", -1.0)):
        for i, (hip, knee, foot) in enumerate(STEEPLE_LEGS):
            h, k, f = (V(sx * p[0], p[1], p[2]) for p in (hip, knee, foot))
            bones += [("femur%d.%s" % (i, s), tuple(h), tuple(k)), ("tibia%d.%s" % (i, s), tuple(k), tuple(f))]
        bones += [("arm_up.%s" % s, (sx * 0.13, -0.2, 1.52), (sx * 0.2, -0.42, 1.24)),
                  ("arm_lo.%s" % s, (sx * 0.2, -0.42, 1.24), (sx * 0.1, -0.56, 1.42)),
                  ("hook.%s" % s, (sx * 0.1, -0.56, 1.42), (sx * 0.08, -0.66, 1.3))]
    r = kin.MatrixRig("steeple_rig", bones)
    A = r.attach
    # --- body: a starved black torso folded over the legs, hunched back with spine knobs
    spine = kin.bezier((0, 0.36, 1.24), (0, 0.12, 1.74), (0, -0.26, 1.56), 9)
    radii = [0.09, 0.13, 0.15, 0.16, 0.16, 0.15, 0.13, 0.11, 0.09]
    lower = kin.tube("torso_low", spine[:6], radii[:6], m.black, 16, squash=0.85)
    A(lower, "body")
    upper = kin.tube("torso_up", spine[4:], radii[4:], m.black, 16, squash=0.85)
    ribs = []
    for i in range(5):
        p = spine[3] + (spine[7] - spine[3]) * (i / 4.0)
        for sx in (1, -1):
            ribs.append(kin.tube("rib", kin.bezier(p + V(sx * 0.03, 0.0, 0.14), p + V(sx * 0.19, -0.02, 0.05),
                                                    p + V(sx * 0.1, -0.1, -0.1), 5), 0.016, m.black, 6))
    knobs = [kin.blob("vertebra", p + V(0, 0.0, radii[i + 1] * 0.92), 0.034 - 0.003 * abs(i - 3), m.knob, segments=8,
                      rings=6) for i, p in enumerate(spine[1:8])]
    A(geo.join([upper] + ribs, "torso_up"), "chest")
    A(geo.join(knobs, "spine_knobs"), "chest")
    A(kin.blob("pelvis", (0, 0.34, 1.26), 0.12, m.black, scale=(1.3, 1.0, 0.8)), "body")
    # --- neck and head: a pale skull face sunk inside a tall black cowl that ends in a point
    A(kin.tube("neck", kin.bezier((0, -0.2, 1.52), (0, -0.36, 1.6), S_HEAD + V(0, -0.02, 0.06), 6),
               [0.06, 0.055, 0.05, 0.05, 0.055, 0.06], m.black, 10), "neck")
    hx, hy, hz = S_SKULL
    skull = kin.blob("skull", (0, hy, hz), 0.15, m.skull, scale=(0.8, 0.84, 1.12), segments=22, rings=14)
    brow = kin.blob("brow", (0, hy - 0.08, hz + 0.06), 0.085, m.skull, scale=(1.3, 0.5, 0.42), segments=12, rings=8)
    cheek = [kin.blob("cheek", (sx * 0.07, hy - 0.085, hz - 0.05), 0.042, m.skull, segments=8, rings=6) for sx in (1, -1)]
    sockets = [kin.blob("socket", (sx * 0.05, hy - 0.118, hz + 0.015), 0.043, m.void, scale=(0.9, 0.45, 1.3), segments=10,
                        rings=8) for sx in (1, -1)]
    nose = kin.blob("nose", (0, hy - 0.13, hz - 0.05), 0.02, m.void, scale=(0.8, 0.5, 1.4), segments=8, rings=6)
    mouth = kin.blob("mouth", (0, hy - 0.105, hz - 0.12), 0.06, m.void, scale=(1.05, 0.4, 0.32), segments=10, rings=6)
    teeth = [geo.box("tooth", (0.012, 0.01, 0.02), (x * 0.016, hy - 0.124, hz - 0.115), m.skull, bevel=0.003)
             for x in (-2, -1, 0, 1, 2)]
    A(geo.join([skull, brow, nose, mouth] + cheek + sockets + teeth, "skull"), "head")
    # cowl: open at the front around the face, closing above it into the cone
    rows = []
    levels = [(1.66, 0.25, 0.24, 64, 0.07), (1.76, 0.22, 0.22, 56, 0.06), (1.88, 0.2, 0.205, 46, 0.045),
              (1.97, 0.18, 0.19, 30, 0.035), (2.04, 0.16, 0.17, 0, 0.03)]
    for z, rx, ry, gap, back in levels:
        a0, a1 = -90 + gap, 270 - gap
        rows.append([(x, y + hy + back, z) for x, y, _ in
                     humanoid.partial_ring(rx, ry, a0, a1, 25, z, folds=6, fold_amp=0.04)])
    hood = humanoid.sheet("cowl", rows, m.hood, 0.016)
    A(hood, "head")
    cone_pts = [V(0, hy + 0.03, 2.03), V(0, hy + 0.04, 2.17), V(0.005, hy + 0.06, 2.32), V(0.014, hy + 0.09, 2.46),
                V(0.035, hy + 0.13, 2.58), V(0.07, hy + 0.19, 2.66)]
    cone = kin.tube("cone", cone_pts, [0.165, 0.13, 0.095, 0.06, 0.03, 0.0], m.hood, 18)
    A(cone, "cone")
    # --- legs: six stilts with knobbed knees and a second knob down the shin, pointed ivory tips
    for s, sx in (("L", 1.0), ("R", -1.0)):
        for i, (hip, knee, foot) in enumerate(STEEPLE_LEGS):
            h, k, f = (V(sx * p[0], p[1], p[2]) for p in (hip, knee, foot))
            out = V(sx, 0, 0) * 0.05
            A(geo.join([kin.tube("femur", kin.bezier(h, (h + k) * 0.5 + V(0, 0, 0.04), k, 5), [0.06, 0.05, 0.045, 0.04, 0.04],
                                 m.black, 10),
                        kin.blob("hipknob", h, 0.06, m.knob, segments=8, rings=6)], "femur"), "femur%d.%s" % (i, s))
            mid = k + (f - k) * 0.4 + out
            pts = kin.bezier(k, mid, k + (f - k) * 0.86, 7)
            A(geo.join([kin.tube("tibia", pts, [0.042, 0.036, 0.03, 0.026, 0.022, 0.019, 0.017], m.black, 10),
                        kin.blob("knee", k, 0.07, m.knob, scale=(1, 1, 1.2), segments=10, rings=8),
                        kin.blob("shinknob", pts[3], 0.042, m.knob, segments=8, rings=6),
                        kin.tube("tip", [pts[-1], k + (f - k) * 0.94, f], [0.019, 0.013, 0.0], m.ivory, 8)],
                       "tibia"), "tibia%d.%s" % (i, s))
        # thin hooked arms folded against the chest like a mantis
        a0, a1, a2, a3 = (r.head("arm_up." + s), r.head("arm_lo." + s), r.head("hook." + s), r.tail("hook." + s))
        A(geo.join([kin.tube("arm_up", [a0, a1], [0.034, 0.026], m.black, 8),
                    kin.blob("shoulder", a0, 0.042, m.knob, segments=8, rings=6)], "arm_up"), "arm_up.%s" % s)
        A(geo.join([kin.tube("arm_lo", [a1, a2], [0.026, 0.02], m.black, 8),
                    kin.blob("elbow", a1, 0.036, m.knob, segments=8, rings=6)], "arm_lo"), "arm_lo.%s" % s)
        hooks = []
        for j in range(3):
            off = V(sx * 0.02 * (j - 1), 0, 0)
            hooks.append(kin.tube("hook", kin.bezier(a2 + off, a3 + off + V(0, -0.04, 0.0),
                                                     a3 + off + V(0, 0.04, -0.14 - 0.03 * j), 6),
                                  [0.013, 0.012, 0.01, 0.008, 0.005, 0.0], m.ivory, 6))
        A(geo.join(hooks, "hooks"), "hook.%s" % s)
    return r


def _steeple_feet(t_anim, anim, t):
    """Foot targets (character space) for the six legs: {(i, side): Vector}."""
    feet = {}
    for i, (_, _, f) in enumerate(STEEPLE_LEGS):
        for s, sx in (("L", 1.0), ("R", -1.0)):
            feet[(i, s)] = V(sx * f[0], f[1], f[2])
    return feet


STEEPLE_PHASE = {(2, "L"): 0.0, (1, "L"): 1 / 6, (0, "L"): 2 / 6, (2, "R"): 3 / 6, (1, "R"): 4 / 6, (0, "R"): 5 / 6}


def steeple_pose(r, anim, t, yaw):
    """Returns nothing; sets every bone motion on r."""
    nf = STEEPLE_ANIMS[anim]["frames"]
    feet = _steeple_feet(None, anim, t)
    body = dict(z=0.0, y=0.0, x=0.0, pitch=0.0, roll=0.0, turn=0.0)
    chest = dict(pitch=0.0, roll=0.0)
    head = dict(pitch=0.0, tilt=0.0)
    cone = dict(pitch=0.0, roll=0.0)
    arms = dict(fwd=0.0, curl=0.0)
    face = 1.0
    knee_out = 1.0
    a = math.tau * t
    if anim == "idle":
        body.update(z=0.035 * math.sin(a), pitch=2.0 * math.sin(a + 0.6), roll=1.5 * math.sin(a * 0.5 * 2))
        chest.update(pitch=3.0 * math.sin(a + 1.0))
        head.update(tilt=12 + 9 * math.sin(a), pitch=-4 * math.sin(a + 2))
        cone.update(pitch=-5 * math.sin(a + 0.7), roll=7 * math.sin(a + 1.9))
        arms.update(curl=10 * math.sin(a * 2))
        # one front foot taps restlessly
        feet[(0, "L")] += V(0, -0.04 * math.sin(a), 0.07 * max(0.0, math.sin(a * 2)))
    elif anim == "walk":
        stride, lift = 0.62, 0.38
        for key, ph in STEEPLE_PHASE.items():
            u = (t + ph) % 1.0
            sw = 1.0 / 3.0
            if u < sw:          # swing: lift high and reach forward
                v = u / sw
                dy = stride * (0.5 - v)
                dz = lift * math.sin(math.pi * v)
            else:               # stance: planted, slides back under the body
                v = (u - sw) / (1 - sw)
                dy = stride * (-0.5 + v)
                dz = 0.0
            feet[key] += V(0, dy - 0.03, dz)
        body.update(z=0.03 * math.sin(a * 3), roll=3 * math.sin(a), pitch=3 + 2 * math.sin(a * 3 + 1), turn=4 * math.sin(a))
        chest.update(pitch=2 * math.sin(a * 3), roll=-4 * math.sin(a))
        head.update(tilt=10 + 6 * math.sin(a), pitch=3 * math.sin(a * 3))
        cone.update(pitch=-6 * math.sin(a * 3 + 1.2), roll=-9 * math.sin(a + 0.8))
        arms.update(curl=8 * math.sin(a * 3))
    elif anim == "windup":
        # rises on the four back legs, the front pair pulls back and up and trembles (long, readable)
        u = kin.smooth(t / 0.7)
        body.update(z=0.32 * u, pitch=-16 * u, y=0.12 * u)
        chest.update(pitch=-14 * u)
        head.update(pitch=-10 * u, tilt=12 * (1 - u))
        cone.update(pitch=-12 * u + jitter(t, nf, 3 * u, 1), roll=jitter(t, nf, 4 * u, 2))
        arms.update(fwd=15 * u, curl=45 * u)
        for s, sx in (("L", 1.0), ("R", -1.0)):
            tr = jitter(t, nf, 0.045 * u, 3 if s == "L" else 5)
            feet[(0, s)] = feet[(0, s)].lerp(V(sx * 0.42, -0.42, 1.55), u) + V(tr, tr * 0.6, -tr)
            feet[(1, s)] += V(sx * 0.1 * u, -0.08 * u, 0)
            feet[(2, s)] += V(sx * 0.06 * u, 0.06 * u, 0)
        body["z"] += jitter(t, nf, 0.012 * u, 7)
    elif anim == "strike":
        # the two front legs stab forward, long reach, the body lunges after them
        u = keys([(0.0, 0.0), (0.45, 1.0), (0.75, 1.0), (1.0, 0.82)], t)
        body.update(z=0.32 - 0.42 * u, pitch=-16 + 34 * u, y=0.12 - 0.5 * u)
        chest.update(pitch=-14 + 26 * u)
        head.update(pitch=-10 + 22 * u)
        cone.update(pitch=-12 + 30 * u)
        arms.update(fwd=15 + 45 * u, curl=45 - 35 * u)
        for s, sx in (("L", 1.0), ("R", -1.0)):
            start = V(sx * 0.42, -0.42, 1.55)
            feet[(0, s)] = start.lerp(V(sx * 0.16, -3.0, 1.0), u)
            feet[(1, s)] += V(sx * 0.1, -0.08 - 0.15 * u, 0)
            feet[(2, s)] += V(sx * 0.06, 0.06 - 0.25 * u, 0)
    elif anim == "stagger":
        u = keys([(0.0, 0.0), (0.3, 1.0), (1.0, 0.0)], t)
        body.update(z=0.08 * u, pitch=-14 * u, y=0.22 * u, roll=8 * u)
        chest.update(pitch=-16 * u, roll=-10 * u)
        head.update(pitch=-25 * u, tilt=-30 * u)
        cone.update(pitch=-25 * u, roll=20 * u)
        arms.update(fwd=-40 * u, curl=-20 * u)
        for s, sx in (("L", 1.0), ("R", -1.0)):
            feet[(0, s)] += V(sx * 0.15 * u, 0.2 * u, 0.55 * u * (1.0 if s == "L" else 0.6))
            feet[(1, s)] += V(sx * 0.05 * u, 0.1 * u, 0)
    elif anim == "death":
        # the legs give way and fold: the body sinks, the stilts buckle outwards, then curl in like a dead spider
        u1 = kin.smooth(t / 0.55)
        u2 = kin.smooth((t - 0.45) / 0.55)
        body.update(z=-1.12 * u1, pitch=8 * u1 - 10 * u2, roll=14 * u2)
        chest.update(pitch=18 * u1 - 8 * u2)
        head.update(pitch=50 * u2, tilt=20 * u1 + 40 * u2)
        cone.update(pitch=35 * u2, roll=25 * u2)
        arms.update(fwd=20 * u1, curl=50 * u2)
        knee_out = 1.0 + 0.8 * u1
        face = 1.0 - u2
        for key in feet:
            i, s = key
            sx = 1.0 if s == "L" else -1.0
            f0 = feet[key]
            out = V(f0.x * 1.5, f0.y * 1.35, 0)
            if i == 0:
                end = V(sx * 0.75, -0.95, 1.15 + (0.25 if s == "L" else 0.0))
            elif i == 1:
                end = V(f0.x * 1.55, f0.y, 0.12)
            else:
                end = V(f0.x * 1.3, f0.y * 1.3, 0.3)
            feet[key] = out.lerp(end, u2)
    _steeple_apply(r, feet, body, chest, head, cone, arms, yaw * face, knee_out)


def _steeple_apply(r, feet, body, chest, head, cone, arms, yaw, knee_out):
    mb = kin.move(pivot(kin.I4, S_BODY_PIVOT, body["pitch"], body["roll"], body["turn"]), (body["x"], body["y"], body["z"]))
    r.set("body", mb)
    mc = pivot(mb, S_CHEST_PIVOT, chest["pitch"], chest["roll"], 0)
    r.set("chest", mc)
    mn = pivot(mc, S_NECK, -chest["pitch"] * 0.5, 0, -yaw * 0.3)
    r.set("neck", mn)
    mh = pivot(mn, S_HEAD, head["pitch"] - body["pitch"] * 0.6, head["tilt"], -yaw * 0.7)
    r.set("head", mh)
    r.set("cone", pivot(mh, S_CONE, cone["pitch"], cone["roll"], 0))
    for s, sx in (("L", 1.0), ("R", -1.0)):
        for i, (hip, knee, foot) in enumerate(STEEPLE_LEGS):
            hb = "femur%d.%s" % (i, s)
            parent = mc if i == 0 else mb
            h_rest, k_rest = r.rest[hb]
            t_rest = r.tail("tibia%d.%s" % (i, s))
            a = (k_rest - h_rest).length
            b = (t_rest - k_rest).length
            h = parent @ h_rest
            f = feet[(i, s)]
            pole = V(sx * 0.7 * knee_out, (-0.5 if i == 0 else 0.5 if i == 2 else 0.0), 1.0)
            k = kin.ik2(h, f, a, b, pole)
            # the shin points from the knee towards the target, at its own length (target may be out of reach)
            f2 = k + (f - k).normalized() * b
            r.set_segment(hb, h, k)
            r.set_segment("tibia%d.%s" % (i, s), k, f2)
        mu = pivot(mc, r.head("arm_up." + s), -arms["fwd"], 0, 0)
        r.set("arm_up." + s, mu)
        ml = pivot(mu, r.head("arm_lo." + s), -arms["curl"] * 0.6, 0, 0)
        r.set("arm_lo." + s, ml)
        r.set("hook." + s, pivot(ml, r.head("hook." + s), -arms["curl"], 0, 0))
    r.apply()


def steeple_table(m):
    return [(m.black, 4), (m.hood, 3), (m.skull, 5), (m.void, 1), (m.knob, 3), (m.ivory, 3)]


# =============================================================================== shared limb helpers

def solve_limb(r, b1, b2, parent_m, target, pole, end_bone=None, end_rot=None):
    """Two-bone IK from parent_m @ rest head of b1 towards target; the end bone (hand/foot) follows the
    wrist with rotation end_rot (4x4, about the wrist) or the parent's rotation. Returns the wrist."""
    h_rest, k_rest = r.rest[b1]
    f_rest = r.tail(b2)
    a = (k_rest - h_rest).length
    b = (f_rest - k_rest).length
    h = parent_m @ h_rest
    k = kin.ik2(h, target, a, b, pole)
    f = k + (V(target) - k).normalized() * b
    r.set_segment(b1, h, k)
    r.set_segment(b2, k, f)
    if end_bone:
        rot = end_rot if end_rot is not None else parent_m.to_3x3().to_4x4()
        r.set(end_bone, kin.Matrix.Translation(f) @ rot @ kin.Matrix.Translation(-f_rest))
    return f


def head_flip(c, p):
    """Point p of a normally modelled head, turned upside down about the head centre c (180 deg about Y)."""
    return V(2 * c[0] - p[0], p[1], 2 * c[2] - p[2])


# =============================================================================== THE GRINNER

GRINNER_ANIMS = {
    "idle": {"frames": 8, "fps": 6, "loop": True},
    "walk": {"frames": 12, "fps": 14, "loop": True},
    "windup": {"frames": 8, "fps": 10, "loop": False},
    "strike": {"frames": 5, "fps": 14, "loop": False},
    "stagger": {"frames": 6, "fps": 10, "loop": False},
    "death": {"frames": 10, "fps": 8, "loop": False},
}
G_SHOULDER, G_ELBOW, G_WRIST = (0.16, -0.3, 0.9), (0.56, -0.56, 1.2), (0.5, -1.08, 0.05)
G_HIP, G_KNEE, G_ANKLE = (0.12, 0.4, 0.74), (0.4, 0.3, 0.92), (0.3, 0.7, 0.07)
G_HEAD_C = V(0, -0.64, 1.0)
G_NECK_TOP = V(0, -0.56, 1.1)
G_NECK_BASE = V(0, -0.3, 0.92)
G_BODY_PIVOT = V(0, 0.1, 0.85)
G_CHEST_PIVOT = V(0, 0.02, 0.95)
G_FINGERS = [(-40, 0.2), (-14, 0.27), (4, 0.3), (22, 0.27), (44, 0.22)]   # (splay deg outwards, length)


def grinner_build(m, rng):
    bones = [("body", (0, 0.44, 0.76), tuple(G_CHEST_PIVOT)), ("chest", tuple(G_CHEST_PIVOT), tuple(G_NECK_BASE)),
             ("neck", tuple(G_NECK_BASE), tuple(G_NECK_TOP)), ("head", tuple(G_NECK_TOP), tuple(G_HEAD_C)),
             ("jaw", tuple(G_HEAD_C), tuple(G_HEAD_C + V(0, -0.1, 0.06)))]
    for s, sx in (("L", 1.0), ("R", -1.0)):
        X = lambda p: V(sx * p[0], p[1], p[2])  # noqa: E731
        w = X(G_WRIST)
        bones += [("arm_up." + s, tuple(X(G_SHOULDER)), tuple(X(G_ELBOW))), ("arm_lo." + s, tuple(X(G_ELBOW)), tuple(w)),
                  ("hand." + s, tuple(w), tuple(w + V(0, -0.1, 0))),
                  ("thigh." + s, tuple(X(G_HIP)), tuple(X(G_KNEE))), ("shin." + s, tuple(X(G_KNEE)), tuple(X(G_ANKLE))),
                  ("foot." + s, tuple(X(G_ANKLE)), tuple(X(G_ANKLE) + V(0, -0.14, -0.04)))]
        for j, (ang, ln) in enumerate(G_FINGERS):
            base = w + V(sx * (j - 2) * 0.022, -0.09, -0.01)
            d = V(math.sin(math.radians(ang)) * sx, -math.cos(math.radians(ang)), 0)
            bones.append(("fing%d.%s" % (j, s), tuple(base), tuple(base + d * ln)))
    r = kin.MatrixRig("grinner_rig", bones)
    A = r.attach
    # --- starved torso: arched spine with knobs, ribs pushing through, sunken belly, shoulder blades
    spine = kin.bezier((0, 0.46, 0.74), (0, 0.06, 1.06), (0, -0.32, 0.9), 11)
    radii = [0.09, 0.105, 0.1, 0.095, 0.1, 0.115, 0.125, 0.13, 0.125, 0.11, 0.08]
    A(kin.tube("belly", spine[:6], radii[:6], m.pale, 14, squash=0.8), "body")
    chest = kin.tube("chest", spine[5:], radii[5:], m.pale, 14, squash=0.8)
    ribs = []
    for i in range(6):
        p = spine[4 + i]
        rr = radii[4 + i] * 1.04
        for sx in (1, -1):
            arc = [p + V(sx * rr * math.cos(math.radians(ang)), 0.0, rr * 0.82 * math.sin(math.radians(ang)))
                   for ang in (70, 35, 0, -35, -70)]
            ribs.append(kin.tube("rib", arc, 0.013, m.teeth, 6))
    knobs = [kin.blob("vert", p + V(0, 0, 0.095), 0.022, m.teeth, segments=8, rings=6) for p in spine[1:10]]
    blades = [kin.blob("blade", (sx * 0.1, -0.18, 1.0), 0.07, m.pale, scale=(0.8, 1.2, 0.35), rotation=(0, sx * 25, 0))
              for sx in (1, -1)]
    bruises = [kin.blob("bruise", (sx * 0.1, -0.05, 0.9), 0.05, m.bruise, scale=(0.6, 1.4, 0.8)) for sx in (1, -1)]
    A(geo.join([chest] + ribs + blades + bruises, "chest"), "chest")
    A(geo.join(knobs[:5], "knobs_low"), "body")
    A(geo.join(knobs[5:], "knobs_up"), "chest")
    A(kin.blob("pelvis", (0, 0.44, 0.74), 0.1, m.pale, scale=(1.3, 1, 0.8)), "body")
    A(kin.tube("neck", kin.bezier(G_NECK_BASE + V(0, 0.04, -0.02), (0, -0.48, 1.12), G_NECK_TOP, 6), 0.042, m.pale, 10), "neck")
    # --- the head, modelled upright then turned upside down: a grin wider than the face, tiny black eyes
    c = G_HEAD_C
    cx, cy, cz = c
    parts = [kin.blob("skull", c, 0.17, m.pale, scale=(0.95, 0.86, 1.05), segments=24, rings=16)]
    fy = cy - 0.17 * 0.86
    grin, upper, lower = [], [], []
    for i in range(17):
        x = -0.15 + 0.3 * i / 16
        u = x / 0.15
        z = cz - 0.055 + 0.07 * u * u
        y = cy - 0.17 * 0.86 * math.sqrt(max(1 - (x / 0.163) ** 2, 0.04)) - 0.006
        grin.append(V(x, y, z))
    rad = [0.008] + [0.03 + 0.012 * math.cos(math.pi * (i / 14 - 0.5)) for i in range(15)] + [0.008]
    gum = kin.tube("lips", [p + V(0, 0.004, 0) for p in grin], [q + 0.008 for q in rad], m.gum, 12, squash=0.3,
                   normal=(0, 0, 1))
    hole = kin.tube("grin", [p + V(0, -0.004, 0) for p in grin], rad, m.void, 12, squash=0.3, normal=(0, 0, 1))
    for i, p in enumerate(grin[1:-1]):
        rotz = math.degrees(math.atan2(p.x / 0.163, 1.0))
        h = rad[i + 1]
        upper.append(geo.box("tooth", (0.017, 0.01, h * 0.8), p + V(0, -0.012, h * 0.55), m.teeth, bevel=0.003,
                             rotation=(0, 0, math.radians(rotz))))
        lower.append(geo.box("tooth", (0.017, 0.01, h * 0.8), p + V(0, -0.012, -h * 0.55), m.teeth, bevel=0.003,
                             rotation=(0, 0, math.radians(rotz))))
    eyes = [kin.blob("eye", (sx * 0.055, fy + 0.008, cz + 0.075), 0.011, m.void, segments=8, rings=6) for sx in (1, -1)]
    sockets = [kin.blob("socket", (sx * 0.055, fy + 0.016, cz + 0.077), 0.03, m.bruise, scale=(1.1, 0.4, 0.75))
               for sx in (1, -1)]
    cheeks = [kin.blob("cheek", (sx * 0.12, fy + 0.04, cz - 0.03), 0.045, m.pale, scale=(0.8, 0.6, 1.0)) for sx in (1, -1)]
    head = geo.join(parts + [gum, hole] + upper + eyes + sockets + cheeks, "head")
    head.rotation_euler = (0, math.pi, 0)      # upside down about the head centre (joined origin = skull)
    A(head, "head")
    jaw = geo.join(lower + [kin.blob("chin", (0, fy + 0.05, cz - 0.13), 0.065, m.pale, scale=(1.4, 0.7, 0.6))], "jaw")
    jaw_obj = geo.join([kin.blob("jaw_anchor", c, 0.001, m.pale), jaw], "jaw")
    jaw_obj.rotation_euler = (0, math.pi, 0)
    A(jaw_obj, "jaw")
    # --- limbs: arms twice too long with raised elbows; spider fingers; crouched frog legs
    for s, sx in (("L", 1.0), ("R", -1.0)):
        X = lambda p: V(sx * p[0], p[1], p[2])  # noqa: E731
        sh, el, wr = X(G_SHOULDER), X(G_ELBOW), X(G_WRIST)
        A(geo.join([kin.tube("arm_up", [sh, (sh + el) * 0.5, el], [0.05, 0.04, 0.034], m.pale, 10),
                    kin.blob("shoulder", sh, 0.055, m.pale, segments=10, rings=8)], "arm_up"), "arm_up." + s)
        A(geo.join([kin.tube("arm_lo", [el, el + (wr - el) * 0.5, wr + V(0, 0, 0.03)], [0.033, 0.026, 0.022], m.pale, 10),
                    kin.blob("elbow", el, 0.04, m.bruise, segments=8, rings=6)], "arm_lo"), "arm_lo." + s)
        A(kin.blob("palm", wr + V(0, -0.045, -0.005), 0.05, m.pale, scale=(1.0, 1.2, 0.4)), "hand." + s)
        for j in range(len(G_FINGERS)):
            b0, b1 = r.rest["fing%d.%s" % (j, s)]
            d = b1 - b0
            pts = [b0, b0 + d * 0.34 + V(0, 0, 0.035), b0 + d * 0.7 + V(0, 0, 0.02), b1 + V(0, 0, -0.02)]
            A(geo.join([kin.tube("finger", pts, [0.011, 0.01, 0.008, 0.0], m.pale, 6),
                        kin.blob("knuckle", pts[1], 0.012, m.bruise, segments=6, rings=4),
                        kin.blob("nail", pts[2] + d * 0.25, 0.007, m.blood, segments=6, rings=4)], "finger"),
              "fing%d.%s" % (j, s))
        hp, kn, an = X(G_HIP), X(G_KNEE), X(G_ANKLE)
        A(kin.tube("thigh", [hp, (hp + kn) * 0.5, kn], [0.06, 0.05, 0.042], m.pale, 10), "thigh." + s)
        A(geo.join([kin.tube("shin", [kn, kn + (an - kn) * 0.5, an], [0.042, 0.032, 0.026], m.pale, 10),
                    kin.blob("knee", kn, 0.048, m.bruise, segments=8, rings=6)], "shin"), "shin." + s)
        toes = [kin.tube("toe", [an + V(sx * 0.02 * (t - 1), -0.08, -0.03), an + V(sx * 0.03 * (t - 1), -0.2, -0.05)],
                         [0.012, 0.006], m.pale, 6) for t in range(3)]
        A(geo.join([kin.blob("foot", an + V(0, -0.04, -0.02), 0.05, m.pale, scale=(0.9, 1.6, 0.6))] + toes, "foot"), "foot." + s)
    return r


G_TILTS = [0, 0, 38, 38, -24, 46, 46, 8]     # jerky head tilts (frame-locked, idle)


def grinner_pose(r, anim, t, yaw):
    nf = GRINNER_ANIMS[anim]["frames"]
    k = round(t * (nf - (0 if GRINNER_ANIMS[anim]["loop"] else 1))) % nf
    hands = {s: V(sx * G_WRIST[0], G_WRIST[1], G_WRIST[2]) for s, sx in (("L", 1.0), ("R", -1.0))}
    feet = {s: V(sx * G_ANKLE[0], G_ANKLE[1], G_ANKLE[2]) for s, sx in (("L", 1.0), ("R", -1.0))}
    body = dict(z=0.0, y=0.0, pitch=0.0, roll=0.0, turn=0.0)
    chest = dict(pitch=0.0, roll=0.0)
    head = dict(pitch=0.0, tilt=0.0)
    curl = {"L": 0.0, "R": 0.0}
    splay = {"L": 0.0, "R": 0.0}
    jaw = 0.0
    face = 1.0
    a = math.tau * t
    if anim == "idle":
        body.update(z=0.015 * math.sin(a), pitch=1.5 * math.sin(a))
        chest.update(pitch=2.5 * math.sin(a + 0.8))
        head.update(tilt=G_TILTS[k], pitch=6 * (k % 3 == 1))
        curl["L"] = 25 * max(0.0, math.sin(a * 2))          # fingers tap
        splay["R"] = 6 * math.sin(a)
        hands["L"] += V(0, 0, 0.03 * max(0.0, math.sin(a * 2)))
        jaw = 4 * (k in (2, 5))
    elif anim == "walk":
        for limb, pair, ph in (("hand", "L", 0.0), ("foot", "R", 0.05), ("hand", "R", 0.5), ("foot", "L", 0.55)):
            u = (t + ph) % 1.0
            sw = 0.42
            stride, lift = (0.55, 0.3) if limb == "hand" else (0.42, 0.16)
            if u < sw:
                v = u / sw
                d = V(0, stride * (0.5 - v), lift * math.sin(math.pi * v))
                if limb == "hand":
                    curl[pair] = 45 * math.sin(math.pi * v)
                    splay[pair] = -8 * math.sin(math.pi * v)
            else:
                v = (u - sw) / (1 - sw)
                d = V(0, stride * (-0.5 + v), 0)
                if limb == "hand":
                    splay[pair] = 12 * math.sin(math.pi * v)       # fingers splay as the hand bears weight
            (hands if limb == "hand" else feet)[pair] += d
        body.update(z=0.035 * math.sin(2 * a), roll=5 * math.sin(a), turn=5 * math.sin(a), pitch=3 * math.sin(2 * a + 1))
        chest.update(roll=-7 * math.sin(a), pitch=2 * math.sin(2 * a))
        head.update(tilt=G_TILTS[k % 8] * 0.6, pitch=4 * math.sin(2 * a))
    elif anim == "windup":
        u = kin.smooth(t / 0.75)
        snap = 1.0 if t >= 0.5 else 0.0              # the head snaps level, all at once
        body.update(z=-0.26 * u, pitch=6 * u, y=0.12 * u)
        chest.update(pitch=-10 * u)
        head.update(tilt=G_TILTS[min(k, 7)] * (1 - snap), pitch=-14 * snap)
        jaw = 18 * snap
        for s, sx in (("L", 1.0), ("R", -1.0)):
            hands[s] += V(sx * 0.1 * u, 0.12 * u, 0)
            feet[s] += V(sx * 0.04 * u, -0.08 * u, 0)
            splay[s] = 14 * u
    elif anim == "strike":
        # a leaping lunge: launched forward, arms thrown up and raking down
        lu = keys([(0.0, 0.0), (0.35, 1.0), (0.7, 0.85), (1.0, 0.55)], t)
        body.update(z=-0.26 + 0.6 * keys([(0.0, 0.0), (0.35, 1.0), (0.7, 0.45), (1.0, 0.25)], t), y=0.12 - 0.62 * lu,
                    pitch=6 - 22 * keys([(0.0, 0.0), (0.35, 1.0), (1.0, 0.0)], t))
        chest.update(pitch=-10 + 20 * lu)
        head.update(pitch=-14 + 8 * lu)
        jaw = 18 + 14 * lu
        for s, sx in (("L", 1.0), ("R", -1.0)):
            h0 = hands[s] + V(sx * 0.1, 0.12, 0)
            up = V(sx * 0.62, -1.55, 1.45)
            down = V(sx * 0.32, -1.85, 0.2)
            back = V(sx * 0.42, -1.3, 0.04)
            hands[s] = keys([(0.0, tuple(h0)), (0.35, tuple(up)), (0.7, tuple(down)), (1.0, tuple(back))], t)
            hands[s] = V(hands[s])
            curl[s] = keys([(0.0, 0.0), (0.35, -15.0), (0.7, 50.0), (1.0, 30.0)], t)
            splay[s] = keys([(0.0, 14.0), (0.35, 20.0), (0.7, 0.0), (1.0, 5.0)], t)
            feet[s] = V(keys([(0.0, tuple(feet[s] + V(sx * 0.04, -0.08, 0))), (0.35, tuple(feet[s] + V(0, 0.25, 0.25))),
                              (1.0, tuple(feet[s] + V(0, -0.35, 0)))], t))
    elif anim == "stagger":
        u = keys([(0.0, 0.0), (0.3, 1.0), (1.0, 0.0)], t)
        body.update(z=0.06 * u, y=0.2 * u, pitch=-14 * u, roll=-10 * u)
        chest.update(pitch=-12 * u, roll=12 * u)
        head.update(tilt=-50 * u, pitch=-25 * u)
        jaw = 22 * u
        hands["L"] += V(0.2 * u, 0.25 * u, 0.5 * u)
        hands["R"] += V(-0.1 * u, 0.1 * u, 0.15 * u)
        curl["L"] = -20 * u
        splay["L"] = 25 * u
    elif anim == "death":
        u1 = kin.smooth(t / 0.5)
        u2 = kin.smooth((t - 0.4) / 0.6)
        body.update(z=-0.62 * u1, roll=10 * u2, pitch=-6 * u1)
        chest.update(pitch=8 * u1, roll=-6 * u2)
        head.update(tilt=30 * u1 + 50 * u2, pitch=20 * u2)
        jaw = 30 * u2
        face = 1.0 - u2
        for s, sx in (("L", 1.0), ("R", -1.0)):
            hands[s] = hands[s].lerp(V(sx * 1.25, -1.0, 0.03), u1 * 0.6 + u2 * 0.4)
            feet[s] = feet[s].lerp(V(sx * 0.6, 0.85, 0.03), u1)
            curl[s] = 40 * u2 if s == "L" else 10 * u2
            splay[s] = 20 * u1
    _grinner_apply(r, hands, feet, body, chest, head, curl, splay, jaw, yaw * face)


def _grinner_apply(r, hands, feet, body, chest, head, curl, splay, jaw, yaw):
    mb = kin.move(pivot(kin.I4, G_BODY_PIVOT, body["pitch"], body["roll"], body["turn"]), (0, body["y"], body["z"]))
    r.set("body", mb)
    mc = pivot(mb, G_CHEST_PIVOT, chest["pitch"], chest["roll"], 0)
    r.set("chest", mc)
    mn = pivot(mc, G_NECK_BASE, -chest["pitch"] - body["pitch"], 0, -yaw * 0.35)
    r.set("neck", mn)
    mh = pivot(mn, G_NECK_TOP, head["pitch"], head["tilt"], -yaw * 0.65)
    r.set("head", mh)
    # jaw: the lower jaw is on top (head upside down); it opens upwards about the hinge behind the grin
    r.set("jaw", pivot(mh, G_HEAD_C + V(0, 0.02, 0.0), -jaw, 0, 0))
    yaw_body = mb.to_3x3().to_4x4()
    for s, sx in (("L", 1.0), ("R", -1.0)):
        solve_limb(r, "arm_up." + s, "arm_lo." + s, mc, hands[s], V(sx * 0.9, 0.2, 1.0), "hand." + s, yaw_body)
        mhand = r.motion["hand." + s]
        for j in range(len(G_FINGERS)):
            b = "fing%d.%s" % (j, s)
            sp = splay[s] * (j - 2) / 2.0 * sx
            r.set(b, pivot(mhand, r.head(b), curl[s] * (0.6 + 0.2 * (j % 2)), 0, sp))
        solve_limb(r, "thigh." + s, "shin." + s, mb, feet[s], V(sx * 0.8, -0.2, 1.0), "foot." + s, yaw_body)
    r.apply()


def grinner_table(m):
    return [(m.pale, 6), (m.bruise, 3), (m.teeth, 4), (m.gum, 2), (m.void, 1), (m.blood, 2)]


# =============================================================================== THE BENT ONE

BENT_ANIMS = {
    "idle": {"frames": 8, "fps": 4, "loop": True},
    "walk": {"frames": 12, "fps": 6, "loop": True},
    "windup": {"frames": 10, "fps": 8, "loop": False},
    "strike": {"frames": 5, "fps": 12, "loop": False},
    "stagger": {"frames": 6, "fps": 8, "loop": False},
    "death": {"frames": 10, "fps": 7, "loop": False},
}
B_PELVIS, B_APEX_CTRL, B_SHOULDERS = V(0, 0.64, 3.28), V(0, 0.04, 4.42), V(0, -0.6, 3.24)
B_APEX = V(0, 0.02, 3.85)
B_NECK = V(0, -0.66, 3.12)
B_NECK_MID = V(0, -0.6, 2.78)
B_HEAD = V(0, -0.46, 2.52)
B_ARM = ((0.21, -0.6, 3.18), (0.56, -1.26, 0.0))     # shoulder, hand (left)
B_LEG = ((0.21, 0.64, 3.22), (0.56, 1.3, 0.0))       # hip, foot (left)
B_FINGERS = [(-50, 0.3), (-20, 0.46), (0, 0.52), (20, 0.46), (48, 0.36)]


def _bent_mid(a, b, sx, back):
    a, b = V(a), V(b)
    d = (b - a).length
    l = d * 0.53
    return kin.ik2(a, b, l, l, V(sx, back, 0.15))


def bent_build(m, rng):
    bones = [("hips", tuple(B_PELVIS), tuple(B_APEX)), ("chest", tuple(B_APEX), tuple(B_SHOULDERS)),
             ("neck", tuple(B_NECK), tuple(B_NECK_MID)), ("neck2", tuple(B_NECK_MID), tuple(B_HEAD)),
             ("head", tuple(B_HEAD), tuple(B_HEAD + V(0, 0, -0.3))), ("jaw", tuple(B_HEAD + V(0, -0.02, -0.1)),
                                                                         tuple(B_HEAD + V(0, -0.1, -0.25)))]
    for s, sx in (("L", 1.0), ("R", -1.0)):
        for limb, (j0, j1), back in (("arm", B_ARM, 0.45), ("leg", B_LEG, -0.45)):
            a, b = V(sx * j0[0], j0[1], j0[2]), V(sx * j1[0], j1[1], j1[2])
            k = _bent_mid(a, b, sx, back)
            bones += [("%s_up.%s" % (limb, s), tuple(a), tuple(k)), ("%s_lo.%s" % (limb, s), tuple(k), tuple(b + V(0, 0, 0.06))),
                      ("%s_end.%s" % (limb, s), tuple(b + V(0, 0, 0.06)), tuple(b + V(0, -0.12 if limb == "arm" else 0.12, 0.0)))]
    r = kin.MatrixRig("bent_rig", bones)
    A = r.attach
    # --- the arch: a long starved black back bent over like a bridge, vertebrae along the top
    spine = kin.bezier(B_PELVIS + V(0, 0.08, -0.06), B_APEX_CTRL, B_SHOULDERS + V(0, -0.08, -0.06), 15)
    radii = [0.17, 0.2, 0.21, 0.21, 0.2, 0.19, 0.18, 0.175, 0.18, 0.19, 0.2, 0.21, 0.21, 0.2, 0.17]
    A(geo.join([kin.tube("back_hind", spine[:8], radii[:8], m.black, 16, squash=0.8)] +
               [kin.blob("vert", p + V(0, 0, radii[i] * 0.85), 0.05, m.knob, segments=8, rings=6) for i, p in enumerate(spine[1:8], 1)],
               "back_hind"), "hips")
    A(geo.join([kin.tube("back_fore", spine[7:], radii[7:], m.black, 16, squash=0.8)] +
               [kin.blob("vert", p + V(0, 0, radii[i] * 0.85), 0.05, m.knob, segments=8, rings=6)
                for i, p in enumerate(spine[8:14], 8)] +
               [kin.blob("shoulder", (sx * 0.17, -0.62, 3.2), 0.13, m.black, scale=(1, 1, 0.9)) for sx in (1, -1)],
               "back_fore"), "chest")
    A(kin.blob("pelvis", (0, 0.66, 3.22), 0.19, m.black, scale=(1.3, 1, 0.9)), "hips")
    # --- the neck hangs down under the arch; a small pale head with a gaping mouth at its end
    A(kin.tube("neck", kin.bezier(B_NECK + V(0, 0, 0.08), B_NECK + V(0, 0.02, -0.2), B_NECK_MID, 5), 0.06, m.black, 10), "neck")
    A(kin.tube("neck2", kin.bezier(B_NECK_MID, B_NECK_MID + V(0, 0.04, -0.15), B_HEAD + V(0, 0.04, 0.1), 5),
               [0.06, 0.055, 0.05, 0.048, 0.05], m.black, 10), "neck2")
    hc = B_HEAD + V(0, -0.03, -0.1)
    skull = kin.blob("skull", hc, 0.13, m.pale, scale=(0.78, 0.82, 1.22), segments=20, rings=14)
    fy = hc.y - 0.13 * 0.82
    sockets = [kin.blob("socket", (sx * 0.042, fy + 0.012, hc.z + 0.05), 0.028, m.void, scale=(0.9, 0.45, 0.7)) for sx in (1, -1)]
    mouth = kin.blob("mouth", (0, fy + 0.0, hc.z - 0.07), 0.05, m.void, scale=(0.85, 0.45, 1.45), segments=12, rings=8)
    teeth = [geo.box("tooth", (0.011, 0.01, 0.018), (x * 0.014, fy - 0.004, hc.z - 0.008), m.teeth, bevel=0.002)
             for x in (-2, -1, 0, 1, 2)]
    A(geo.join([skull, mouth] + sockets + teeth, "head"), "head")
    jaw = kin.blob("jaw", (0, fy + 0.03, hc.z - 0.16), 0.06, m.pale, scale=(1.0, 0.75, 0.55), segments=12, rings=8)
    jt = [geo.box("tooth", (0.011, 0.01, 0.016), (x * 0.014, fy - 0.002, hc.z - 0.135), m.teeth, bevel=0.002) for x in (-1, 0, 1)]
    A(geo.join([jaw] + jt, "jaw"), "jaw")
    # --- four impossibly long thin limbs, knobbed joints, long spider fingers on the fore hands
    for s, sx in (("L", 1.0), ("R", -1.0)):
        for limb in ("arm", "leg"):
            a, k = r.rest["%s_up.%s" % (limb, s)]
            w = r.tail("%s_lo.%s" % (limb, s))
            A(geo.join([kin.tube("up", kin.bezier(a, (a + k) * 0.5 + V(sx * 0.03, 0, 0), k, 6),
                                 [0.085, 0.075, 0.065, 0.058, 0.055, 0.055], m.black, 10)], "up"), "%s_up.%s" % (limb, s))
            A(geo.join([kin.tube("lo", kin.bezier(k, (k + w) * 0.5 + V(sx * 0.03, 0, 0), w, 6),
                                 [0.055, 0.05, 0.044, 0.038, 0.034, 0.032], m.black, 10),
                        kin.blob("joint", k, 0.085, m.knob, scale=(1, 1, 1.25), segments=10, rings=8)], "lo"), "%s_lo.%s" % (limb, s))
            fwd = -1.0 if limb == "arm" else 1.0
            fingers = [kin.blob("palm", w + V(0, fwd * 0.05, -0.03), 0.06, m.black, scale=(1.0, 1.4, 0.45))]
            for j, (ang, ln) in enumerate(B_FINGERS if limb == "arm" else B_FINGERS[1:4]):
                ln = ln if limb == "arm" else ln * 0.6
                d = V(math.sin(math.radians(ang)) * sx, fwd * math.cos(math.radians(ang)), 0)
                b0 = w + V(sx * (j - 2) * 0.025, fwd * 0.1, -0.03)
                pts = [b0, b0 + d * ln * 0.35 + V(0, 0, 0.05), b0 + d * ln * 0.72 + V(0, 0, 0.025), b0 + d * ln + V(0, 0, -0.05)]
                fingers.append(kin.tube("finger", pts, [0.017, 0.014, 0.01, 0.0], m.black, 6))
                fingers.append(kin.blob("knuckle", pts[1], 0.02, m.knob, segments=6, rings=4))
            A(geo.join(fingers, "hand"), "%s_end.%s" % (limb, s))
    return r


B_PHASE = {("leg", "L"): 0.0, ("arm", "L"): 0.25, ("leg", "R"): 0.5, ("arm", "R"): 0.75}


def bent_pose(r, anim, t, yaw):
    nf = BENT_ANIMS[anim]["frames"]
    ends = {}
    for s, sx in (("L", 1.0), ("R", -1.0)):
        ends[("arm", s)] = V(sx * B_ARM[1][0], B_ARM[1][1], 0.06)
        ends[("leg", s)] = V(sx * B_LEG[1][0], B_LEG[1][1], 0.06)
    body = dict(x=0.0, y=0.0, z=0.0, pitch=0.0, roll=0.0, turn=0.0)
    chest = dict(pitch=0.0, roll=0.0)
    neck = dict(swing=0.0, side=0.0)
    head = dict(pitch=0.0, tilt=0.0)
    jaw = 10.0
    curl = 0.0
    face = 1.0
    a = math.tau * t
    if anim == "idle":
        body.update(x=0.07 * math.sin(a), z=0.04 * math.sin(2 * a), roll=4 * math.sin(a), turn=2 * math.sin(a + 1))
        chest.update(pitch=2 * math.sin(2 * a + 0.5))
        neck.update(swing=9 * math.sin(a + 0.9), side=-10 * math.sin(a + 0.4))
        head.update(tilt=10 * math.sin(a + 1.6), pitch=4 * math.sin(2 * a))
        jaw = 14 + 10 * math.sin(a + 2.0)
        curl = 12 * max(0.0, math.sin(2 * a))
    elif anim == "walk":
        for key, ph in B_PHASE.items():
            u = (t + ph) % 1.0
            sw = 0.3
            if u < sw:
                v = u / sw
                d = V(0, 1.1 * (0.5 - v), 0.65 * math.sin(math.pi * v))
            else:
                v = (u - sw) / (1 - sw)
                d = V(0, 1.1 * (-0.5 + v), 0.0)
            ends[key] += d
        body.update(z=0.08 * math.sin(2 * a + 0.6), roll=5 * math.sin(a), x=0.06 * math.sin(a), turn=3 * math.sin(a))
        chest.update(roll=-4 * math.sin(a), pitch=2 * math.sin(2 * a))
        neck.update(swing=-12 * math.sin(2 * a + 1.4), side=-12 * math.sin(a + 0.8))
        head.update(tilt=8 * math.sin(a + 2.2))
        jaw = 16 + 6 * math.sin(2 * a)
    elif anim == "windup":
        # rises tall on the hind limbs, the forelimbs leave the ground and gather up in front
        u = kin.smooth(t / 0.8)
        body.update(z=0.55 * u, y=0.25 * u, pitch=-14 * u)
        chest.update(pitch=-12 * u)
        neck.update(swing=-25 * u + jitter(t, nf, 3 * u, 1))
        head.update(pitch=-20 * u)
        jaw = 10 + 30 * u
        curl = 35 * u
        for s, sx in (("L", 1.0), ("R", -1.0)):
            ends[("arm", s)] = ends[("arm", s)].lerp(V(sx * 0.3, -1.25, 2.9), u) + V(jitter(t, nf, 0.04 * u, 2 + sx), 0, 0)
            ends[("leg", s)] += V(sx * 0.1 * u, -0.1 * u, 0)
    elif anim == "strike":
        # slams down: both fore hands hit the ground far in front, the arch drops
        u = keys([(0.0, 0.0), (0.4, 1.0), (1.0, 1.0)], t)
        settle = keys([(0.0, 0.0), (0.4, 0.0), (0.65, 1.0), (1.0, 0.7)], t)
        body.update(z=0.55 - 0.85 * u + 0.1 * settle, y=0.25 - 0.55 * u, pitch=-14 + 26 * u - 4 * settle)
        chest.update(pitch=-12 + 24 * u)
        neck.update(swing=-25 + 55 * u - 15 * settle)
        head.update(pitch=-20 + 30 * u)
        jaw = 40
        curl = 35 - 45 * u
        for s, sx in (("L", 1.0), ("R", -1.0)):
            ends[("arm", s)] = V(sx * 0.3, -1.25, 2.9).lerp(V(sx * 0.42, -2.0, 0.06), u)
            ends[("leg", s)] += V(sx * 0.1, -0.1 - 0.25 * u, 0)
    elif anim == "stagger":
        u = keys([(0.0, 0.0), (0.3, 1.0), (1.0, 0.0)], t)
        body.update(z=0.12 * u, y=0.3 * u, pitch=-10 * u, roll=7 * u)
        chest.update(pitch=-10 * u, roll=-6 * u)
        neck.update(swing=-40 * u, side=25 * u)
        head.update(tilt=-35 * u, pitch=-20 * u)
        jaw = 10 + 35 * u
        ends[("arm", "L")] += V(0.15 * u, 0.25 * u, 0.9 * u)
        ends[("arm", "R")] += V(-0.05 * u, 0.1 * u, 0.3 * u)
    elif anim == "death":
        # the limbs buckle outwards, the arch comes down in a heap, knees up like a dead spider
        u1 = kin.smooth(t / 0.6)
        u2 = kin.smooth((t - 0.5) / 0.5)
        body.update(z=-2.78 * u1, roll=12 * u2, pitch=4 * u1)
        chest.update(pitch=10 * u1 + 8 * u2)
        neck.update(swing=30 * u1, side=40 * u2)
        head.update(tilt=40 * u2, pitch=20 * u2)
        jaw = 10 + 40 * u2
        curl = 40 * u2
        face = 1.0 - u2
        for (limb, s), e in list(ends.items()):
            sx = 1.0 if s == "L" else -1.0
            ends[(limb, s)] = e.lerp(V(sx * 2.1, e.y * 1.25, 0.06), u1)
    _bent_apply(r, ends, body, chest, neck, head, jaw, curl, yaw * face)


def _bent_apply(r, ends, body, chest, neck, head, jaw, curl, yaw):
    mb = kin.move(pivot(kin.I4, B_APEX, body["pitch"], body["roll"], body["turn"]), (body["x"], body["y"], body["z"]))
    r.set("hips", mb)
    mc = pivot(mb, B_APEX, chest["pitch"], chest["roll"], 0)
    r.set("chest", mc)
    # the hanging neck swings like a pendulum (keeps hanging roughly down whatever the body does)
    mn = pivot(mc, B_NECK, -chest["pitch"] - body["pitch"] + neck["swing"], neck["side"], -yaw * 0.4)
    r.set("neck", mn)
    mn2 = pivot(mn, B_NECK_MID, neck["swing"] * 0.6, neck["side"] * 0.5, -yaw * 0.6)
    r.set("neck2", mn2)
    mh = pivot(mn2, B_HEAD, head["pitch"], head["tilt"], 0)
    r.set("head", mh)
    r.set("jaw", pivot(mh, r.head("jaw"), -jaw * 0.5, 0, 0))
    flat = mb.to_3x3().to_4x4()
    for (limb, s), e in ends.items():
        sx = 1.0 if s == "L" else -1.0
        parent = mc if limb == "arm" else mb
        pole = V(sx, 0.45 if limb == "arm" else -0.45, 0.15)
        rot = flat
        if limb == "arm" and curl:
            rot = flat @ kin.rot(x=curl)
        solve_limb(r, "%s_up.%s" % (limb, s), "%s_lo.%s" % (limb, s), parent, e, pole, "%s_end.%s" % (limb, s), rot)
    r.apply()


def bent_table(m):
    return [(m.black, 4), (m.pale, 5), (m.void, 1), (m.knob, 3), (m.teeth, 2)]


# =============================================================================== registry

TYPES = {
    "steeple": dict(build=steeple_build, pose=steeple_pose, table=steeple_table, anims=STEEPLE_ANIMS,
                    camera=6.4, center=1.3, height=136, render_px=640, seed=41),
    "grinner": dict(build=grinner_build, pose=grinner_pose, table=grinner_table, anims=GRINNER_ANIMS,
                    camera=4.2, center=0.75, height=100, render_px=640, seed=52),
    "bent": dict(build=bent_build, pose=bent_pose, table=bent_table, anims=BENT_ANIMS,
                 camera=6.6, center=2.2, height=152, render_px=640, seed=63),
}


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--type", default="steeple", choices=sorted(TYPES))
    ap.add_argument("--preview", action="store_true")
    ap.add_argument("--only", default="")
    ap.add_argument("--dirs", default="")
    ap.add_argument("--out", default=OUT)
    ap.add_argument("--stills", default="", help="anim:t,... single poses for iteration (writes <out>/<type>_stills/)")
    args = ap.parse_args(argv)
    kind = args.type
    spec = TYPES[kind]
    sprite_render.clear_scene()
    sprite_render.setup_render(spec["render_px"], 6 if args.preview else 16)
    sprite_render.world_hdri("kloofendal_overcast_puresky", CACHE, strength=0.35, tint=(0.6, 0.7, 0.66))
    # Same cold, unwholesome lighting as the Hollow and the Mourner (creature.py).
    sprite_render.sun("key", (60, 0, -30), (0.8, 0.88, 0.85), 2.4, 10)
    sprite_render.sun("under", (150, 0, 20), (0.55, 0.7, 0.55), 0.6, 30)
    sprite_render.sun("rim", (60, 0, 160), (0.85, 0.95, 1.0), 2.8, 6)
    sprite_render.camera(spec["camera"], spec["center"])
    m = Mats()
    r = spec["build"](m, random.Random(spec["seed"]))

    def pose(anim, t):
        spec["pose"](r, anim, t, kin.viewer_yaw(r.obj))

    only = [a for a in args.only.split(",") if a]
    dirs = [int(d) for d in args.dirs.split(",") if d] or None
    if args.stills:
        sprite_render.render_stills(kind, r.obj, pose, args.stills, args.out, dirs or [0, 2, 4])
        return
    sprite_render.render_character(kind, r.obj, pose, spec["anims"], args.out, 8, spec["camera"], spec["height"], 40,
                                   only or None, dirs, sprite_render.material_table(spec["table"](m)))


if __name__ == "__main__":
    main()
