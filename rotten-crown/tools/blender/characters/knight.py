"""The young knight of the King's guard (prologue): dark worn Gothic plate, a black tattered
cloak and mantle, a faded crimson tabard, sword at the hip (concept art: the knight in the rain).

  $BLENDER -b --factory-startup --python tools/blender/characters/knight.py -- [--preview] [--only a,b] [--dirs 0,2]
Writes build/sprites_raw/knight/ (see rc_blender/sprite_render.py); then run
  python3 tools/pixelize_sprites.py knight
"""
import argparse
import math
import os
import random
import sys

import bpy

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from rc_blender import geo, humanoid, mat, rig, sprite_render  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
OUT = os.path.join(ROOT, "build", "sprites_raw")
CACHE = os.path.join(ROOT, "build", "blender_cache")

ANIMS = {
    "idle": {"frames": 8, "fps": 4, "loop": True},
    "walk": {"frames": 12, "fps": 12, "loop": True},
    "toast": {"frames": 8, "fps": 6, "loop": True},
    "cheer": {"frames": 10, "fps": 10, "loop": True},
    "stretch": {"frames": 12, "fps": 6, "loop": False},
    "lie": {"frames": 1, "fps": 1, "loop": False},
}
CAMERA_SIZE = 2.7
CENTER_Z = 1.05
HEIGHT_PX = 150
PALETTE = 48

SHOULDER = (0.215, 0.0, 1.45)
ELBOW = (0.255, 0.02, 1.17)
WRIST = (0.265, 0.0, 0.93)
HIP = (0.1, 0.0, 0.95)
KNEE = (0.105, -0.01, 0.53)
ANKLE = (0.105, 0.02, 0.1)

BODY = humanoid.Body(SHOULDER, ELBOW, WRIST, HIP, KNEE, ANKLE)
BONES = BODY.bones([
    ("cloak_1", (0, 0.16, 1.42), (0, 0.2, 0.95), "chest"),
    ("cloak_2", (0, 0.2, 0.95), (0, 0.24, 0.4), "cloak_1"),
    ("tabard_f", (0, -0.15, 1.0), (0, -0.16, 0.55), "hips"),
    ("tabard_b", (0, 0.15, 1.0), (0, 0.16, 0.6), "hips"),
])
EXTRA = {"cloak1": ("cloak_1", "x"), "cloak2": ("cloak_2", "x"), "tabf": ("tabard_f", "x"), "tabb": ("tabard_b", "x")}


class Mats:
    def __init__(self):
        self.steel = mat.steel("steel", base=(0.15, 0.158, 0.16), grime=0.65, edge=0.45)
        self.steel_dark = mat.steel("steel_dark", base=(0.12, 0.125, 0.13), grime=0.7, edge=0.25)
        self.black = mat.cloth("cloak", (0.012, 0.012, 0.015), rough=0.97, sheen=0.08)
        self.crimson = mat.cloth("crimson", (0.2, 0.025, 0.03))
        self.leather = mat.cloth("leather", (0.09, 0.055, 0.035), rough=0.6, sheen=0.1, weave=10.0)
        self.mail = mat.mail()
        self.gold = mat.flat("gold", (0.55, 0.4, 0.17), rough=0.35, metallic=1.0)
        self.void = mat.flat("void", (0.0, 0.0, 0.0), rough=1.0)
        self.gold_bright = mat.flat("gold_bright", (0.85, 0.62, 0.25), rough=0.25, metallic=1.0)


def build(m):
    rng = random.Random(7)
    arm = rig.build_armature("knight_rig", BONES)
    parts = []

    def attach(obj, bone):
        rig.parent_to_bone(obj, arm, bone)
        parts.append(obj)
        return obj

    # --- torso --------------------------------------------------------------------
    attach(geo.loft("breastplate", [
        dict(z=1.2, rx=0.165, ry=0.115, front=0.02),
        dict(z=1.3, rx=0.185, ry=0.13, front=0.035, back=0.01),
        dict(z=1.4, rx=0.2, ry=0.14, front=0.04, back=0.015),
        dict(z=1.48, rx=0.19, ry=0.13, front=0.025),
        dict(z=1.53, rx=0.12, ry=0.09),
    ], m.steel, 28), "chest")
    attach(geo.lames("plackart", 1.23, 1.06, 3, 0.168, 0.118, m.steel, flare=0.01, front=0.015), "spine")
    attach(geo.lames("fauld", 1.07, 0.96, 2, 0.18, 0.135, m.steel, flare=0.02, taper=1.06), "hips")
    attach(geo.lames("gorget", 1.585, 1.5, 3, 0.088, 0.082, m.steel, flare=0.012, taper=1.25), "neck")
    belt = geo.loft("belt", [dict(z=1.075, rx=0.172, ry=0.128), dict(z=1.04, rx=0.176, ry=0.132)], m.leather, 24,
        cap_bottom=False, cap_top=False)
    buckle = geo.box("buckle", (0.045, 0.012, 0.04), (0.0, -0.137, 1.058), m.gold, bevel=0.004)
    attach(geo.join([belt, buckle], "belt"), "hips")
    attach(geo.loft("mail_skirt", [
        dict(z=0.99, rx=0.178, ry=0.13), dict(z=0.84, rx=0.2, ry=0.15), dict(z=0.76, rx=0.21, ry=0.16),
    ], m.mail, 24, cap_bottom=False, cap_top=False), "hips")
    # Rivets along the breastplate's upper rim.
    rivets = [geo.sphere("rivet", 0.008, (0.17 * math.cos(a), -0.12 * math.sin(a) - 0.005, 1.46), m.gold, segments=6,
        rings=4) for a in [math.radians(d) for d in range(20, 170, 25)]]
    attach(geo.join(rivets, "rivets"), "chest")

    # Tabard (faded crimson) front and back, frayed hem.
    for name, ysign, bone, bottom in (("tabard_front", -1.0, "tabard_f", 0.56), ("tabard_back", 1.0, "tabard_b", 0.6)):
        cols = 7
        rows = []
        for zi, z in enumerate((1.04, 0.92, 0.8, 0.68, bottom)):
            w = 0.12 + 0.02 * zi
            row = []
            hem = humanoid.tattered([z] * cols, rng, 0.06) if zi == 4 else [z] * cols
            for i in range(cols):
                x = -w + 2 * w * i / (cols - 1)
                row.append((x, ysign * (0.152 + 0.012 * zi), hem[i]))
            rows.append(row)
        t = humanoid.sheet(name, rows, m.crimson)
        rig.skin_by_height(t, arm, [("hips", 1.0), (bone, 0.7)])
        parts.append(t)

    # --- cloak and mantle ------------------------------------------------------------
    rows = []
    levels = [(1.47, 0.2, 0.15), (1.3, 0.25, 0.2), (1.0, 0.29, 0.23), (0.7, 0.32, 0.26), (0.36, 0.34, 0.28)]
    n = 29
    for li, (z, rx, ry) in enumerate(levels):
        hem = humanoid.tattered([z] * n, rng, 0.16) if li == len(levels) - 1 else None
        amp = 0.02 + 0.03 * li  # folds deepen towards the hem
        rows.append(humanoid.partial_ring(rx, ry, -28, 208, n, z, hem, y_off=0.02, folds=9, fold_amp=amp))
    cloak = humanoid.sheet("cloak", rows, m.black)
    rig.skin_by_height(cloak, arm, [("chest", 1.42), ("cloak_1", 0.95), ("cloak_2", 0.45)])
    parts.append(cloak)
    mrows = []
    for li, (z, rx, ry) in enumerate([(1.57, 0.11, 0.1), (1.52, 0.2, 0.16), (1.44, 0.27, 0.21), (1.36, 0.3, 0.23)]):
        hem = humanoid.tattered([z] * 20, rng, 0.06) if li == 3 else None
        mrows.append(humanoid.partial_ring(rx, ry, -10, 190, 20, z, hem, y_off=0.015))
    attach(humanoid.sheet("mantle", mrows, m.black), "chest")

    # --- helm ------------------------------------------------------------------------
    helm = geo.loft("helm", [
        dict(z=1.565, rx=0.092, ry=0.1, y=-0.005),
        dict(z=1.61, rx=0.115, ry=0.125, front=0.03, y=-0.01),
        dict(z=1.66, rx=0.122, ry=0.132, front=0.035, y=-0.01),
        dict(z=1.72, rx=0.124, ry=0.134, front=0.02, y=-0.005),
        dict(z=1.78, rx=0.116, ry=0.126),
        dict(z=1.83, rx=0.09, ry=0.1),
        dict(z=1.862, rx=0.05, ry=0.055),
        dict(z=1.875, rx=0.0, ry=0.0),
    ], m.steel, 32)
    visor = []
    for z in (1.703, 1.722):
        pts = humanoid.partial_ring(0.127, 0.14, 205, 335, 9, z, y_off=-0.007)
        visor += [geo.box("slit", (0.032, 0.012, 0.009), p, m.void, rotation=(0, 0, math.atan2(p[1], p[0]) + math.pi / 2))
            for p in pts]
    breaths = [geo.sphere("breath", 0.006, (0.04 + 0.02 * (i % 3), -0.14 + 0.012 * (i % 3), 1.63 + 0.02 * (i // 3)), m.void,
        segments=6, rings=4) for i in range(6)]
    crest = geo.box("crest", (0.012, 0.24, 0.02), (0, 0.0, 1.865), m.steel, bevel=0.004, rotation=(0.15, 0, 0))
    attach(geo.join([helm, crest] + visor + breaths, "helm"), "head")

    # --- arms ------------------------------------------------------------------------
    for side, sx in (("L", 1.0), ("R", -1.0)):
        pauldron = []
        for i, (z0, z1, r) in enumerate(((1.55, 1.44, 0.115), (1.47, 1.38, 0.125), (1.41, 1.33, 0.12), (1.36, 1.29, 0.11))):
            pauldron.append(geo.loft("pauldron", [
                dict(z=z0, rx=r * 0.45 if i == 0 else r * 0.92, ry=r * 0.4 if i == 0 else r * 0.85, x=sx * (SHOULDER[0] + 0.02)),
                dict(z=(z0 + z1) / 2, rx=r, ry=r * 0.92, x=sx * (SHOULDER[0] + 0.025)),
                dict(z=z1, rx=r + 0.012, ry=r * 0.92 + 0.012, x=sx * (SHOULDER[0] + 0.03)),
            ], m.steel, 20, cap_bottom=False, cap_top=(i == 0)))
        attach(geo.join(pauldron, "pauldron." + side), "upper_arm." + side)
        attach(geo.lames("rerebrace." + side, 1.33, 1.2, 3, 0.055, 0.055, m.steel, flare=0.008,
            x=BODY.arm_x(1.27, sx), y=0.01), "upper_arm." + side)
        couter = geo.sphere("couter", 0.058, (sx * ELBOW[0], ELBOW[1], ELBOW[2]), m.steel, scale=(1, 1, 0.9))
        wing = geo.cylinder("couter_wing", 0.055, 0.03, 0.02, (sx * (ELBOW[0] + 0.045), ELBOW[1], ELBOW[2]), m.steel, 10,
            rotation=(0, math.pi / 2, 0))
        attach(geo.join([couter, wing], "couter." + side), "upper_arm." + side)
        attach(geo.lames("vambrace." + side, 1.13, 0.95, 3, 0.048, 0.046, m.steel, flare=0.006, taper=0.92,
            x=BODY.arm_x(1.04, sx), y=0.01), "forearm." + side)
        # Gauntlet: flared cuff, back-of-hand plates, curled finger lames, thumb.
        cuff = geo.loft("cuff", [dict(z=0.965, rx=0.05, ry=0.05, x=sx * WRIST[0]),
            dict(z=0.92, rx=0.062, ry=0.058, x=sx * WRIST[0])], m.steel, 16, cap_bottom=False, cap_top=False)
        palm = geo.box("palm", (0.06, 0.075, 0.085), (sx * WRIST[0], -0.005, 0.875), m.steel_dark, bevel=0.012)
        fingers = [geo.box("finger", (0.058, 0.07 - 0.008 * j, 0.022), (sx * WRIST[0], -0.008 - 0.012 * j, 0.825 - 0.02 * j),
            m.steel, bevel=0.006, rotation=(-0.25 * j, 0, 0)) for j in range(3)]
        thumb = geo.box("thumb", (0.02, 0.024, 0.05), (sx * (WRIST[0] - 0.03), -0.04, 0.87), m.steel, bevel=0.006,
            rotation=(0.3, 0, sx * 0.4))
        attach(geo.join([cuff, palm, thumb] + fingers, "gauntlet." + side), "hand." + side)

        # --- legs ----------------------------------------------------------------------
        hx = sx * HIP[0]
        attach(geo.loft("cuisse." + side, [
            dict(z=0.92, rx=0.088, ry=0.092, x=hx), dict(z=0.75, rx=0.083, ry=0.088, front=0.012, x=hx),
            dict(z=0.6, rx=0.068, ry=0.072, front=0.01, x=hx * 1.02),
        ], m.steel, 20, cap_bottom=False), "thigh." + side)
        poleyn = geo.sphere("poleyn", 0.056, (sx * KNEE[0], KNEE[1] - 0.02, KNEE[2]), m.steel, scale=(1, 0.9, 1.1))
        pwing = geo.cylinder("poleyn_wing", 0.05, 0.02, 0.015, (sx * (KNEE[0] + 0.05), KNEE[1] - 0.01, KNEE[2]), m.steel, 10,
            rotation=(0, math.pi / 2, 0))
        attach(geo.join([poleyn, pwing], "poleyn." + side), "shin." + side)
        attach(geo.loft("greave." + side, [
            dict(z=0.49, rx=0.055, ry=0.06, front=0.012, x=sx * KNEE[0]),
            dict(z=0.38, rx=0.068, ry=0.074, front=0.015, back=0.014, x=sx * KNEE[0]),
            dict(z=0.2, rx=0.048, ry=0.052, front=0.01, x=sx * ANKLE[0]),
            dict(z=0.11, rx=0.05, ry=0.054, x=sx * ANKLE[0]),
        ], m.steel, 20, cap_bottom=False), "shin." + side)
        sab = [geo.box("sabaton", (0.085, 0.065, 0.05 - 0.006 * j), (sx * ANKLE[0], 0.02 - 0.045 * j, 0.055 - 0.004 * j),
            m.steel, bevel=0.01, rotation=(0.12 * j, 0, 0)) for j in range(4)]
        sab.append(geo.box("toe", (0.06, 0.05, 0.03), (sx * ANKLE[0], -0.165, 0.03), m.steel, bevel=0.012, rotation=(0.3, 0, 0)))
        attach(geo.join(sab, "sabaton." + side), "foot." + side)

    # --- sword at the left hip, goblet for the toast -------------------------------------
    scab = geo.cylinder("scabbard", 0.022, 0.016, 0.82, (0.2, 0.09, 0.66), m.leather, 8, rotation=(-0.42, -0.12, 0))
    chape = geo.cylinder("chape", 0.02, 0.008, 0.06, (0.215, 0.24, 0.29), m.gold, 8, rotation=(-0.42, -0.12, 0))
    grip = geo.cylinder("grip", 0.016, 0.016, 0.17, (0.175, -0.04, 1.12), m.leather, 8, rotation=(-0.42, -0.12, 0))
    guard = geo.box("guard", (0.03, 0.2, 0.025), (0.18, -0.01, 1.05), m.steel_dark, bevel=0.006, rotation=(-0.42, -0.12, 0))
    pommel = geo.sphere("pommel", 0.026, (0.168, -0.08, 1.2), m.steel_dark)
    attach(geo.join([scab, chape, grip, guard, pommel], "sword"), "hips")
    cup = geo.loft("goblet", [dict(z=0.0, rx=0.04, ry=0.04), dict(z=0.008, rx=0.008, ry=0.008), dict(z=0.07, rx=0.008, ry=0.008),
        dict(z=0.09, rx=0.04, ry=0.04), dict(z=0.17, rx=0.05, ry=0.05)], m.gold_bright, 16, cap_top=False)
    # Modelled upside down: the toast raises the hand over the head, which turns it upright.
    cup.rotation_euler = (math.pi, 0.0, 0.0)
    cup.location = (-WRIST[0], -0.03, 0.82)
    goblet = attach(cup, "hand.R")
    return arm, goblet


# --- poses ----------------------------------------------------------------------------
# Pose dicts: semantic keys, degrees. Applied by apply_pose() on top of the rest pose.
def apply_pose(arm, p):
    humanoid.apply_pose(arm, p, EXTRA)


def walk_pose(t):
    """12-frame walk; the cloak trails and the tabard swings against the legs."""
    a = math.tau * t
    s = math.sin(a)
    p = humanoid.walk_pose(t)
    p.update({"cloak1": 10 + 4 * abs(s), "cloak2": 8 + 8 * math.sin(a * 2 + 0.6), "tabf": -10 * s, "tabb": 8 * s})
    return p


def pose_for(anim, t):
    if anim == "idle":
        b = math.sin(math.tau * t)
        return {"root_z": -0.006 + 0.006 * b, "chest_x": -1.5 * b, "head_x": -2 + 2.5 * b, "head_tilt": 2 * math.sin(math.tau * t + 1.2),
            "armL_out": 7 + 1.5 * b, "armR_out": 7 + 1.5 * b, "elbowL": 10 + 2 * b, "elbowR": 10 + 2 * b,
            "legL_out": 3, "legR_out": 3, "kneeL": 3, "kneeR": 3,
            "cloak1": 3 + 2 * math.sin(math.tau * t + 0.8), "cloak2": 2 + 3 * math.sin(math.tau * t + 1.6)}
    if anim == "walk":
        return walk_pose(t)
    if anim == "toast":
        # Goblet raised high, a proud sway and a nod to the crowd.
        keys = [
            (0.0, {"armR_fwd": 150, "armR_out": 18, "elbowR": 25, "wristR": -20, "armL_fwd": 10, "elbowL": 35, "chest_x": -6,
                "head_x": -14, "spine_x": -3}),
            (0.5, {"armR_fwd": 165, "armR_out": 14, "elbowR": 12, "wristR": -30, "armL_fwd": 14, "elbowL": 40, "chest_x": -9,
                "head_x": -18, "spine_x": -4, "root_z": 0.012, "cloak1": 6}),
        ]
        return rig.sample_keys(keys, t, True)
    if anim == "cheer":
        # Fist pump with both arms: anticipation down, thrust up, overshoot, settle.
        keys = [
            (0.0, {"armL_fwd": 40, "armL_out": 70, "elbowL": 100, "armR_fwd": 40, "armR_out": 70, "elbowR": 100, "root_z": -0.03,
                "kneeL": 14, "kneeR": 14, "legL_fwd": 8, "legR_fwd": 8, "ankleL": -6, "ankleR": -6, "chest_x": 6, "head_x": 6}),
            (0.35, {"armL_fwd": 165, "armL_out": 30, "elbowL": 18, "armR_fwd": 165, "armR_out": 30, "elbowR": 18, "root_z": 0.02,
                "chest_x": -10, "head_x": -16, "cloak1": 12, "cloak2": 10}),
            (0.55, {"armL_fwd": 172, "armL_out": 24, "elbowL": 8, "armR_fwd": 172, "armR_out": 24, "elbowR": 8, "root_z": 0.015,
                "chest_x": -12, "head_x": -20, "cloak1": 6, "cloak2": 14}),
        ]
        return rig.sample_keys(keys, t, True)
    if anim == "stretch":
        # Arms up, back arched, a long yawn; then arms fall and the knees soften to sit down.
        keys = [
            (0.0, {}),
            (0.3, {"armL_fwd": 160, "armL_out": 35, "elbowL": 30, "armR_fwd": 160, "armR_out": 35, "elbowR": 30, "chest_x": -14,
                "spine_x": -6, "head_x": -22, "root_z": 0.01}),
            (0.55, {"armL_fwd": 175, "armL_out": 45, "elbowL": 10, "armR_fwd": 175, "armR_out": 45, "elbowR": 10, "chest_x": -18,
                "spine_x": -8, "head_x": -26, "head_tilt": 6, "root_z": 0.015}),
            (0.8, {"armL_out": 14, "elbowL": 20, "armR_out": 14, "elbowR": 20, "chest_x": 8, "head_x": 14, "root_z": -0.05,
                "kneeL": 22, "kneeR": 22, "legL_fwd": 12, "legR_fwd": 12, "ankleL": -10, "ankleR": -10}),
            (1.0, {"armL_out": 10, "elbowL": 12, "armR_out": 10, "elbowR": 12, "chest_x": 12, "head_x": 18, "root_z": -0.18,
                "kneeL": 70, "kneeR": 70, "legL_fwd": 50, "legR_fwd": 50, "ankleL": -20, "ankleR": -20, "cloak1": -10}),
        ]
        return rig.sample_keys(keys, t, False)
    if anim == "lie":
        # Asleep on the back in the grass, one knee up, arms resting, head turned to the side.
        return {"root_pitch": -88, "root_z": 0.0, "root_fwd": 0.9, "head_turn": 25, "head_x": -6, "armL_out": 22, "elbowL": 35,
            "armR_fwd": 30, "elbowR": 80, "legL_fwd": 35, "kneeL": 70, "ankleL": -10, "legR_fwd": 4, "kneeR": 6,
            "cloak1": 0, "cloak2": 0, "tabf": 30, "tabb": -10}
    return {}


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview", action="store_true", help="low samples")
    ap.add_argument("--only", default="")
    ap.add_argument("--dirs", default="")
    ap.add_argument("--out", default=OUT)
    args = ap.parse_args(argv)
    sprite_render.clear_scene()
    sprite_render.setup_render(512, 6 if args.preview else 16)
    sprite_render.world_hdri("kloofendal_overcast_puresky", CACHE, strength=0.45, tint=(0.6, 0.7, 0.66))
    # Cool key from the front-left above, warm low fill, strong cold rim from behind (the
    # rain picture: mostly dark plate with a few bright glints).
    sprite_render.sun("key", (52, 0, -35), (0.82, 0.88, 1.0), 3.2, 6)
    sprite_render.sun("fill", (100, 0, 140), (1.0, 0.75, 0.55), 0.5, 20)
    sprite_render.sun("rim", (60, 0, 160), (0.85, 0.92, 1.0), 3.5, 6)
    sprite_render.camera(CAMERA_SIZE, CENTER_Z)
    m = Mats()
    arm, goblet = build(m)

    def pose(anim, t):
        apply_pose(arm, pose_for(anim, t))
        goblet.hide_render = anim != "toast"
        if anim == "lie":
            arm.location = (0.0, 0.0, 0.16)
        else:
            arm.location = (0.0, 0.0, 0.0)

    only = [a for a in args.only.split(",") if a]
    dirs = [int(d) for d in args.dirs.split(",") if d] or None
    table = sprite_render.material_table([(m.steel, 9), (m.steel_dark, 5), (m.black, 5), (m.crimson, 5), (m.leather, 4),
        (m.mail, 4), (m.gold, 4), (m.gold_bright, 4), (m.void, 1)])
    sprite_render.render_character("knight", arm, pose, ANIMS, args.out, 8, CAMERA_SIZE, HEIGHT_PX, PALETTE,
        only or None, dirs, table)


if __name__ == "__main__":
    main()
