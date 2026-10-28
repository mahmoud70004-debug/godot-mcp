"""Valdron villagers for the feast (prologue): three body types, recoloured by palette variants.

  $BLENDER -b --factory-startup --python tools/blender/characters/villager.py -- --type man|woman|musician [--preview]
Writes build/sprites_raw/villager_<type>/; then `python3 tools/pixelize_sprites.py villager_<type>`.
"""
import argparse
import math
import os
import random
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from rc_blender import geo, humanoid, mat, rig, sprite_render  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
OUT = os.path.join(ROOT, "build", "sprites_raw")
CACHE = os.path.join(ROOT, "build", "blender_cache")

ANIMS = {
    "idle": {"frames": 8, "fps": 4, "loop": True},
    "walk": {"frames": 12, "fps": 12, "loop": True},
    "dance": {"frames": 12, "fps": 8, "loop": True},
    "cheer": {"frames": 10, "fps": 10, "loop": True},
}
CAMERA_SIZE = 2.5
CENTER_Z = 0.95
HEIGHT_PX = 120

BODY = humanoid.Body(shoulder=(0.18, 0.0, 1.36), elbow=(0.21, 0.02, 1.1), wrist=(0.22, 0.0, 0.87),
                     hip=(0.09, 0.0, 0.88), knee=(0.095, -0.01, 0.49), ankle=(0.095, 0.02, 0.09),
                     hips_z=0.88, spine_z=1.0, chest_z=1.18, neck_z=1.41, head_z=1.47, head_top=1.7,
                     hand_len=0.09, toe_y=-0.12)

# Variant colours (palette swaps); variant 0 is the rendered colouring.
VARIANTS = {
    "man": [
        {"tunic": (0.42, 0.12, 0.08), "trousers": (0.2, 0.15, 0.1), "hat": (0.25, 0.2, 0.12), "hair": (0.12, 0.08, 0.05)},
        {"tunic": (0.18, 0.24, 0.36), "trousers": (0.16, 0.14, 0.12), "hat": (0.4, 0.34, 0.24), "hair": (0.35, 0.22, 0.1)},
        {"tunic": (0.24, 0.32, 0.17), "trousers": (0.24, 0.18, 0.1), "hat": (0.18, 0.16, 0.14), "hair": (0.55, 0.42, 0.22)},
        {"tunic": (0.47, 0.4, 0.3), "trousers": (0.14, 0.12, 0.14), "hat": (0.32, 0.12, 0.1), "hair": (0.6, 0.6, 0.58)},
    ],
    "woman": [
        {"dress": (0.18, 0.24, 0.38), "apron": (0.62, 0.58, 0.48), "scarf": (0.5, 0.36, 0.18), "hair": (0.3, 0.18, 0.08)},
        {"dress": (0.32, 0.18, 0.28), "apron": (0.55, 0.5, 0.42), "scarf": (0.62, 0.58, 0.5), "hair": (0.12, 0.08, 0.05)},
        {"dress": (0.42, 0.34, 0.15), "apron": (0.6, 0.55, 0.45), "scarf": (0.3, 0.1, 0.08), "hair": (0.55, 0.4, 0.2)},
    ],
    "musician": [
        {"tunic": (0.3, 0.18, 0.28), "trousers": (0.2, 0.15, 0.1), "hat": (0.42, 0.1, 0.08), "hair": (0.2, 0.12, 0.06)},
    ],
}


class Mats:
    def __init__(self, kind):
        v = VARIANTS[kind][0]
        self.skin = mat.cloth("skin", (0.62, 0.45, 0.34), rough=0.55, sheen=0.2, weave=1.0, fray=0.05)
        self.hair = mat.cloth("hair", v["hair"], rough=0.7, sheen=0.5, weave=200.0)
        self.boots = mat.cloth("boots", (0.13, 0.08, 0.05), rough=0.55, sheen=0.1, weave=8.0)
        self.belt = mat.cloth("belt", (0.18, 0.11, 0.06), rough=0.5, sheen=0.1, weave=8.0)
        self.eyes = mat.flat("eyes", (0.02, 0.015, 0.015), rough=0.3)
        self.wood = mat.cloth("wood", (0.36, 0.22, 0.1), rough=0.45, sheen=0.0, weave=30.0)
        if kind == "woman":
            self.dress = mat.cloth("dress", v["dress"])
            self.apron = mat.cloth("apron", v["apron"], fray=0.2)
            self.scarf = mat.cloth("scarf", v["scarf"])
        else:
            self.tunic = mat.cloth("tunic", v["tunic"])
            self.trousers = mat.cloth("trousers", v["trousers"])
            self.hat = mat.cloth("hat", v["hat"], weave=25.0)

    def table(self, kind):
        common = [(self.skin, 5), (self.hair, 3), (self.boots, 3), (self.belt, 2), (self.eyes, 1)]
        if kind == "woman":
            return common + [(self.dress, 5), (self.apron, 4), (self.scarf, 4)]
        extra = [(self.wood, 4)] if kind == "musician" else []
        return common + [(self.tunic, 5), (self.trousers, 4), (self.hat, 4)] + extra


def build_head(m, arm, rng, kind, attach):
    hz = BODY.head_z
    head = geo.sphere("head", 0.1, (0, -0.005, hz + 0.1), m.skin, scale=(0.9, 1.0, 1.12), segments=20, rings=12)
    nose = geo.sphere("nose", 0.022, (0, -0.1, hz + 0.09), m.skin, scale=(0.8, 1.0, 1.3), segments=8, rings=6)
    ears = [geo.sphere("ear", 0.025, (x * 0.088, 0.0, hz + 0.1), m.skin, scale=(0.5, 0.8, 1.2), segments=8, rings=6)
            for x in (1, -1)]
    eyes = [geo.sphere("eye", 0.013, (x * 0.035, -0.088, hz + 0.12), m.eyes, segments=8, rings=6) for x in (1, -1)]
    brows = [geo.box("brow", (0.04, 0.012, 0.01), (x * 0.036, -0.093, hz + 0.145), m.hair, rotation=(0, 0, x * 0.15))
             for x in (1, -1)]
    mouth = geo.box("mouth", (0.04, 0.01, 0.008), (0, -0.095, hz + 0.05), m.eyes)
    parts = [head, nose, mouth] + ears + eyes + brows
    if kind == "woman":
        parts.append(geo.loft("scarf", [dict(z=hz + 0.22, rx=0.0, ry=0.0), dict(z=hz + 0.2, rx=0.07, ry=0.08, y=0.01),
                                        dict(z=hz + 0.15, rx=0.106, ry=0.115, y=0.012, back=0.02),
                                        dict(z=hz + 0.06, rx=0.11, ry=0.11, y=0.03, back=0.04),
                                        dict(z=hz - 0.04, rx=0.12, ry=0.1, y=0.05, back=0.05)],
                              m.scarf, 20, cap_bottom=False))
        parts.append(geo.box("fringe", (0.12, 0.03, 0.03), (0, -0.085, hz + 0.18), m.hair, bevel=0.01))
    else:
        parts.append(geo.loft("hair", [dict(z=hz + 0.215, rx=0.0, ry=0.0), dict(z=hz + 0.2, rx=0.07, ry=0.075),
                                       dict(z=hz + 0.15, rx=0.098, ry=0.108, y=0.006),
                                       dict(z=hz + 0.08, rx=0.096, ry=0.1, y=0.02, back=0.01)], m.hair, 20,
                              cap_bottom=False))
        if kind == "musician" or rng.random() < 0.6:
            # Floppy felt cap with a drooping tip.
            parts.append(geo.loft("cap", [dict(z=hz + 0.17, rx=0.115, ry=0.12), dict(z=hz + 0.22, rx=0.1, ry=0.105),
                                          dict(z=hz + 0.26, rx=0.06, ry=0.07, y=0.04),
                                          dict(z=hz + 0.24, rx=0.02, ry=0.025, y=0.12), dict(z=hz + 0.2, rx=0.0, ry=0.0, y=0.15)],
                                  m.hat, 16))
        if rng.random() < 0.5:
            parts.append(geo.loft("beard", [dict(z=hz + 0.06, rx=0.075, ry=0.06, y=-0.045, front=0.01),
                                            dict(z=hz + 0.01, rx=0.06, ry=0.045, y=-0.06),
                                            dict(z=hz - 0.03, rx=0.0, ry=0.0, y=-0.07)], m.hair, 14, cap_top=False))
    attach(geo.join(parts, "head_parts"), "head")


def build(m, kind, seed):
    rng = random.Random(seed)
    extra = [("skirt_f", (0, -0.12, 0.95), (0, -0.14, 0.2), "hips"), ("skirt_b", (0, 0.12, 0.95), (0, 0.15, 0.2), "hips")]
    arm = rig.build_armature("villager_rig", BODY.bones(extra if kind == "woman" else ()))

    def attach(obj, bone):
        rig.parent_to_bone(obj, arm, bone)
        return obj

    build_head(m, arm, rng, kind, attach)
    attach(geo.loft("neck", [dict(z=1.38, rx=0.05, ry=0.05), dict(z=1.5, rx=0.045, ry=0.045)], m.skin, 12), "neck")
    if kind == "woman":
        # Bodice, then a long skirt skinned between the hips and the skirt bones (moves with the legs).
        attach(geo.loft("bodice", [dict(z=0.98, rx=0.13, ry=0.1), dict(z=1.2, rx=0.15, ry=0.11, front=0.015),
                                   dict(z=1.33, rx=0.15, ry=0.1, front=0.01), dict(z=1.4, rx=0.08, ry=0.07)], m.dress, 22),
               "chest")
        rows = []
        for li, (z, rx, ry) in enumerate([(1.0, 0.14, 0.11), (0.8, 0.19, 0.16), (0.5, 0.24, 0.21), (0.12, 0.28, 0.25)]):
            rows.append(humanoid.partial_ring(rx, ry, 0, 360, 33, z, folds=10, fold_amp=0.015 + 0.02 * li))
        skirt = humanoid.sheet("skirt", rows, m.dress)
        rig.skin_by_height(skirt, arm, [("hips", 0.96), ("skirt_f", 0.2)])
        arows = []
        for z, w in ((1.02, 0.11), (0.75, 0.15), (0.4, 0.17)):
            arows.append([(x, -0.17 - (1.02 - z) * 0.12, z) for x in [-w + 2 * w * i / 6 for i in range(7)]])
        apron = humanoid.sheet("apron", arows, m.apron)
        rig.skin_by_height(apron, arm, [("hips", 0.96), ("skirt_f", 0.4)])
        attach(geo.loft("belt", [dict(z=1.03, rx=0.135, ry=0.105), dict(z=0.99, rx=0.138, ry=0.108)], m.belt, 20,
                        cap_bottom=False, cap_top=False), "hips")
        sleeve_mat = m.dress
    else:
        attach(geo.loft("tunic", [dict(z=1.2, rx=0.15, ry=0.11), dict(z=1.33, rx=0.17, ry=0.115),
                                  dict(z=1.4, rx=0.09, ry=0.08)], m.tunic, 22), "chest")
        attach(geo.loft("tunic_belly", [dict(z=0.98, rx=0.15, ry=0.115), dict(z=1.1, rx=0.155, ry=0.125, front=0.01),
                                        dict(z=1.22, rx=0.15, ry=0.11)], m.tunic, 22, cap_bottom=False, cap_top=False), "spine")
        attach(geo.loft("tunic_skirt", [dict(z=1.0, rx=0.155, ry=0.118), dict(z=0.86, rx=0.18, ry=0.14),
                                        dict(z=0.72, rx=0.2, ry=0.16)], m.tunic, 22, cap_bottom=False, cap_top=False), "hips")
        attach(geo.loft("belt", [dict(z=1.01, rx=0.158, ry=0.12), dict(z=0.97, rx=0.16, ry=0.122)], m.belt, 20,
                        cap_bottom=False, cap_top=False), "hips")
        pouch = geo.box("pouch", (0.06, 0.04, 0.07), (0.12, -0.08, 0.94), m.belt, bevel=0.012)
        attach(pouch, "hips")
        sleeve_mat = m.tunic
    for side, sx in (("L", 1.0), ("R", -1.0)):
        sh, el, wr = BODY.shoulder, BODY.elbow, BODY.wrist
        attach(geo.loft("sleeve", [dict(z=sh[2] + 0.02, rx=0.06, ry=0.065, x=sx * sh[0]),
                                   dict(z=el[2], rx=0.055, ry=0.055, x=sx * el[0]),
                                   dict(z=el[2] - 0.02, rx=0.053, ry=0.053, x=sx * el[0])], sleeve_mat, 14), "upper_arm." + side)
        attach(geo.loft("forearm", [dict(z=el[2] + 0.01, rx=0.05, ry=0.05, x=sx * el[0]),
                                    dict(z=wr[2] + 0.03, rx=0.055, ry=0.05, x=sx * wr[0]),
                                    dict(z=wr[2] + 0.01, rx=0.04, ry=0.035, x=sx * wr[0])], sleeve_mat, 14), "forearm." + side)
        hand = geo.box("hand", (0.05, 0.06, 0.08), (sx * wr[0], -0.005, wr[2] - 0.045), m.skin, bevel=0.018)
        thumb = geo.box("thumb", (0.018, 0.02, 0.04), (sx * (wr[0] - 0.025), -0.03, wr[2] - 0.035), m.skin, bevel=0.007,
                        rotation=(0.3, 0, sx * 0.4))
        attach(geo.join([hand, thumb], "hand"), "hand." + side)
        hp, kn, an = BODY.hip, BODY.knee, BODY.ankle
        leg_mat = m.dress if kind == "woman" else m.trousers
        attach(geo.loft("thigh", [dict(z=hp[2] + 0.02, rx=0.075, ry=0.08, x=sx * hp[0]),
                                  dict(z=kn[2] + 0.03, rx=0.055, ry=0.06, x=sx * kn[0])], leg_mat, 14), "thigh." + side)
        attach(geo.loft("shin", [dict(z=kn[2] + 0.03, rx=0.052, ry=0.058, x=sx * kn[0]),
                                 dict(z=0.3, rx=0.05, ry=0.056, back=0.01, x=sx * an[0]),
                                 dict(z=0.2, rx=0.048, ry=0.05, x=sx * an[0])], leg_mat, 14), "shin." + side)
        boot = geo.loft("boot", [dict(z=0.24, rx=0.05, ry=0.054, x=sx * an[0]), dict(z=0.08, rx=0.05, ry=0.06, x=sx * an[0])],
                        m.boots, 14, cap_bottom=False)
        toe = geo.box("toe", (0.075, 0.15, 0.065), (sx * an[0], -0.05, 0.035), m.boots, bevel=0.025)
        attach(geo.join([boot, toe], "boot"), "foot." + side)
    lute = None
    if kind == "musician":
        body = geo.sphere("lute_body", 0.13, (0, 0, 0), m.wood, scale=(1.0, 0.45, 1.25), segments=16, rings=10)
        neck = geo.box("lute_neck", (0.04, 0.025, 0.36), (0, 0, 0.3), m.wood)
        head = geo.box("lute_head", (0.05, 0.03, 0.08), (0, 0.03, 0.5), m.belt, rotation=(0.5, 0, 0))
        hole = geo.cylinder("lute_hole", 0.03, 0.03, 0.01, (0, -0.06, 0.03), m.eyes, 10, rotation=(math.pi / 2, 0, 0))
        lute = geo.join([body, neck, head, hole], "lute")
        # Held across the chest, neck up to the left.
        lute.location = (0.02, -0.17, 1.12)
        lute.rotation_euler = (0.0, math.radians(-55), 0.0)
        attach(lute, "chest")
    return arm, lute


EXTRA = {"skirtf": ("skirt_f", "x"), "skirtb": ("skirt_b", "x")}


def pose_for(kind, anim, t):
    if anim == "idle":
        b = math.sin(math.tau * t)
        p = {"root_z": -0.004 + 0.004 * b, "chest_x": -1.5 * b, "head_x": -2 + 2 * b, "head_tilt": 3 * math.sin(math.tau * t + 1),
             "armL_out": 6 + b, "armR_out": 6 + b, "elbowL": 12, "elbowR": 12, "legL_out": 3, "legR_out": 3}
    elif anim == "walk":
        p = humanoid.walk_pose(t, stride=24, bounce=0.03, arm_swing=26, lean=3)
        p["skirtf"] = -8 * math.sin(math.tau * t)
    elif anim == "dance":
        # A country jig: hop on alternating feet, arms akimbo swinging, hips swaying.
        a = math.tau * t
        s = math.sin(a)
        hop = abs(math.sin(a))
        p = {"root_z": 0.05 * hop - 0.02, "hips_roll": 6 * s, "chest_roll": -8 * s, "head_tilt": 6 * s, "head_x": -6,
             "legL_fwd": 30 * max(0.0, s), "kneeL": 60 * max(0.0, s) + 6, "legR_fwd": 30 * max(0.0, -s), "kneeR": 60 * max(0.0, -s) + 6,
             "legL_out": 6, "legR_out": 6, "ankleL": 20 * max(0.0, s), "ankleR": 20 * max(0.0, -s),
             "armL_out": 45, "elbowL": 100, "armL_fwd": -10 + 25 * s, "armR_out": 45, "elbowR": 100, "armR_fwd": -10 - 25 * s,
             "skirtf": 14 * s, "skirtb": -10 * s, "chest_twist": 12 * s}
    elif anim == "cheer":
        keys = [
            (0.0, {"armL_fwd": 40, "armL_out": 60, "elbowL": 90, "armR_fwd": 30, "armR_out": 40, "elbowR": 60, "root_z": -0.03,
                   "kneeL": 12, "kneeR": 12, "legL_fwd": 6, "legR_fwd": 6, "chest_x": 5, "head_x": 5}),
            (0.35, {"armL_fwd": 170, "armL_out": 25, "elbowL": 15, "armR_fwd": 120, "armR_out": 45, "elbowR": 40, "root_z": 0.04,
                    "chest_x": -10, "head_x": -18}),
            (0.55, {"armL_fwd": 175, "armL_out": 20, "elbowL": 8, "armR_fwd": 130, "armR_out": 40, "elbowR": 30, "root_z": 0.03,
                    "chest_x": -12, "head_x": -20}),
        ]
        p = rig.sample_keys(keys, t, True)
    elif anim == "music":
        a = math.tau * t
        strum = math.sin(a * 2)
        p = {"armL_fwd": 50, "armL_out": 20, "elbowL": 85, "wristL": -10,
             "armR_fwd": 35 + 6 * strum, "armR_out": 10, "elbowR": 75 + 10 * strum, "wristR": 15 * strum,
             "head_tilt": 8 * math.sin(a), "head_x": 6, "root_z": 0.01 * abs(math.sin(a)), "kneeL": 6 + 8 * max(0.0, math.sin(a)),
             "chest_roll": 3 * math.sin(a)}
    else:
        p = {}
    if kind == "musician" and anim in ("idle", "walk"):
        # Keep holding the lute.
        p.update({"armL_fwd": 50, "armL_out": 20, "elbowL": 85, "armR_fwd": 35, "armR_out": 10, "elbowR": 75})
    return p


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--type", default="man", choices=sorted(VARIANTS))
    ap.add_argument("--preview", action="store_true")
    ap.add_argument("--only", default="")
    ap.add_argument("--dirs", default="")
    ap.add_argument("--out", default=OUT)
    args = ap.parse_args(argv)
    kind = args.type
    sprite_render.clear_scene()
    sprite_render.setup_render(512, 6 if args.preview else 16)
    sprite_render.world_hdri("kloofendal_overcast_puresky", CACHE, strength=0.4, tint=(0.75, 0.75, 0.85))
    # Feast lighting: warm lantern key, cool moon rim.
    sprite_render.sun("key", (50, 0, -35), (1.0, 0.86, 0.68), 2.6, 12)
    sprite_render.sun("fill", (100, 0, 140), (0.55, 0.62, 0.9), 0.5, 20)
    sprite_render.sun("rim", (60, 0, 160), (0.8, 0.88, 1.0), 2.2, 8)
    sprite_render.camera(CAMERA_SIZE, CENTER_Z)
    m = Mats(kind)
    arm, _lute = build(m, kind, {"man": 11, "woman": 12, "musician": 18}[kind])
    anims = dict(ANIMS)
    if kind == "musician":
        anims = {"idle": ANIMS["idle"], "walk": ANIMS["walk"], "music": {"frames": 12, "fps": 8, "loop": True}}

    def pose(anim, t):
        humanoid.apply_pose(arm, pose_for(kind, anim, t), EXTRA if kind == "woman" else None)

    only = [a for a in args.only.split(",") if a]
    dirs = [int(d) for d in args.dirs.split(",") if d] or None
    variants = [{k: list(c) for k, c in v.items()} for v in VARIANTS[kind]]
    sprite_render.render_character("villager_" + kind, arm, pose, anims, args.out, 8, CAMERA_SIZE, HEIGHT_PX, 40,
                                   only or None, dirs, sprite_render.material_table(m.table(kind)), variants)


if __name__ == "__main__":
    main()
