"""The cursed: the Hollow (emaciated, too-long arms, ribs, dislocated jaw) and the Mourner (tall,
wrapped in a black funeral veil, only a gaping jaw and long pale hands showing).
Horror rule: no jump scares - wrong bodies. The head always turns to face the viewer, even
when the body faces away (owl-like neck turn), in every direction.

  $BLENDER -b --factory-startup --python tools/blender/characters/creature.py -- --type hollow|mourner [--preview]
Writes build/sprites_raw/<type>/; then `python3 tools/pixelize_sprites.py <type>`.
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

# Same animation names, frame counts and timings the runtime expects (SpriteCreatureVisual).
ANIMS = {
    "idle": {"frames": 8, "fps": 4, "loop": True},
    "walk": {"frames": 12, "fps": 10, "loop": True},
    "windup": {"frames": 8, "fps": 10, "loop": False},
    "strike": {"frames": 4, "fps": 16, "loop": False},
    "stagger": {"frames": 6, "fps": 10, "loop": False},
    "death": {"frames": 10, "fps": 8, "loop": False},
}

TYPES = {
    "hollow": dict(
        body=humanoid.Body(shoulder=(0.19, 0.03, 1.42), elbow=(0.235, 0.06, 1.04), wrist=(0.245, 0.03, 0.66),
                           hip=(0.085, 0.0, 0.9), knee=(0.095, -0.02, 0.5), ankle=(0.095, 0.02, 0.08),
                           hips_z=0.9, spine_z=1.02, chest_z=1.2, neck_z=1.44, head_z=1.56, head_top=1.78, hand_len=0.2),
        camera=3.8, center=1.0, height=140),
    "mourner": dict(
        body=humanoid.Body(shoulder=(0.17, 0.02, 1.62), elbow=(0.215, 0.05, 1.2), wrist=(0.225, 0.02, 0.76),
                           hip=(0.085, 0.0, 1.0), knee=(0.09, -0.01, 0.55), ankle=(0.09, 0.02, 0.08),
                           hips_z=1.0, spine_z=1.15, chest_z=1.38, neck_z=1.64, head_z=1.76, head_top=2.0, hand_len=0.22),
        camera=4.0, center=1.1, height=150),
}


class Mats:
    def __init__(self, kind):
        pale = (0.6, 0.6, 0.52) if kind == "hollow" else (0.68, 0.66, 0.62)
        self.skin = mat.cloth("skin", pale, rough=0.5, sheen=0.15, weave=2.0, fray=0.22)
        self.rot = mat.cloth("rot", (0.2, 0.24, 0.1), rough=0.6, sheen=0.1, weave=3.0, fray=0.3)
        self.blood = mat.flat("blood", (0.22, 0.015, 0.02), rough=0.25)
        self.bone = mat.cloth("bone", (0.78, 0.74, 0.6), rough=0.45, sheen=0.0, weave=5.0)
        self.rags = mat.cloth("rags", (0.17, 0.14, 0.1), fray=0.25)
        self.veil = mat.cloth("veil", (0.018, 0.017, 0.022), rough=0.85, sheen=0.35, weave=120.0)
        self.void = mat.flat("void", (0.0, 0.0, 0.0), rough=1.0)

    def table(self):
        return [(self.skin, 6), (self.rot, 3), (self.blood, 3), (self.bone, 3), (self.rags, 3), (self.veil, 4),
                (self.void, 1)]


def bpy_data_remove(obj):
    import bpy
    bpy.data.objects.remove(obj, do_unlink=True)


def _arc_bits(name, rx, ry, a0, a1, n, z, size, material, y_off=0.0):
    """Small boxes along an arc, tangent to it (ribs, spine knobs, teeth)."""
    pts = humanoid.partial_ring(rx, ry, a0, a1, n, z, y_off=y_off)
    return [geo.box(name, size, p, material, bevel=min(size) * 0.3,
                    rotation=(0, 0, math.atan2(p[1], p[0]) + math.pi / 2)) for p in pts]


def build_limbs(m, body, attach, kind, rng):
    for side, sx in (("L", 1.0), ("R", -1.0)):
        sh, el, wr = body.shoulder, body.elbow, body.wrist
        hp, kn, an = body.hip, body.knee, body.ankle
        thin = 0.032 if kind == "hollow" else 0.03
        attach(geo.loft("upper_arm", [dict(z=sh[2] + 0.02, rx=thin * 1.4, ry=thin * 1.4, x=sx * sh[0], y=sh[1]),
                                      dict(z=(sh[2] + el[2]) / 2, rx=thin, ry=thin, x=sx * (sh[0] + el[0]) / 2, y=el[1]),
                                      dict(z=el[2], rx=thin * 0.9, ry=thin * 0.9, x=sx * el[0], y=el[1])], m.skin, 10),
               "upper_arm." + side)
        attach(geo.sphere("elbow", thin * 1.25, (sx * el[0], el[1] + 0.01, el[2]), m.bone, segments=8, rings=6),
               "upper_arm." + side)
        attach(geo.loft("forearm", [dict(z=el[2], rx=thin * 0.95, ry=thin * 0.95, x=sx * el[0], y=el[1]),
                                    dict(z=wr[2] + 0.04, rx=thin * 0.75, ry=thin * 0.85, x=sx * wr[0], y=wr[1])], m.skin, 10),
               "forearm." + side)
        # Hand: narrow palm and four over-long jointed fingers, slightly curled, one bent wrong.
        palm = geo.box("palm", (0.045, 0.03, 0.07), (sx * wr[0], wr[1] - 0.005, wr[2] - 0.04), m.skin, bevel=0.01)
        fingers = []
        for j in range(4):
            fx = sx * (wr[0] + (j - 1.5) * 0.012)
            ln = 0.13 + 0.02 * (j % 3)
            bend = -0.35 if not (j == 3 and side == "R") else 0.5
            for k in range(3):
                seg_z = wr[2] - 0.075 - ln * k / 3
                fingers.append(geo.cylinder("finger", 0.0065, 0.005, ln / 3 + 0.01, (fx, wr[1] - 0.012 * k * (1 if bend < 0 else -1),
                                                                                    seg_z - ln / 6), m.skin, 6, rotation=(bend * k * 0.5, 0, 0)))
            fingers.append(geo.sphere("nail", 0.006, (fx, wr[1] - 0.04 * (1 if bend < 0 else -1), wr[2] - 0.075 - ln), m.bone,
                                      segments=6, rings=4))
        attach(geo.join([palm] + fingers, "hand"), "hand." + side)
        leg_mat = m.skin
        attach(geo.loft("thigh", [dict(z=hp[2], rx=0.05, ry=0.055, x=sx * hp[0]),
                                  dict(z=kn[2] + 0.04, rx=0.036, ry=0.04, x=sx * kn[0])], leg_mat, 10), "thigh." + side)
        attach(geo.sphere("knee", 0.042, (sx * kn[0], kn[1] - 0.01, kn[2]), m.bone, scale=(1, 1, 1.15), segments=8, rings=6),
               "shin." + side)
        attach(geo.loft("shin", [dict(z=kn[2], rx=0.034, ry=0.038, x=sx * kn[0]),
                                 dict(z=an[2] - 0.01, rx=0.026, ry=0.03, x=sx * an[0])], leg_mat, 10), "shin." + side)
        heel = geo.sphere("heel", 0.03, (sx * an[0], 0.0, 0.05), m.bone, segments=8, rings=6)
        foot = geo.box("foot", (0.05, 0.16, 0.045), (sx * an[0], -0.05, 0.03), m.skin, bevel=0.015)
        toes = [geo.sphere("toe", 0.012, (sx * an[0] + (t - 1.5) * 0.012, -0.135, 0.015), m.bone, segments=6, rings=4)
                for t in range(4)]
        attach(geo.join([heel, foot] + toes, "foot"), "foot." + side)


def build_head(m, body, attach, kind):
    hz = body.head_z
    skull = geo.sphere("skull", 0.09, (0, 0.0, hz + 0.11), m.skin, scale=(0.82, 1.0, 1.25), segments=20, rings=12)
    cheeks = [geo.sphere("cheek", 0.03, (x * 0.05, -0.07, hz + 0.09), m.bone, segments=8, rings=6) for x in (1, -1)]
    sockets = [geo.sphere("socket", 0.026, (x * 0.033, -0.075, hz + 0.13), m.void, scale=(1, 0.6, 1.2), segments=8, rings=6)
               for x in (1, -1)]
    # Jaw hangs open too far, slightly askew: the horror is in the wrong proportion.
    mouth = geo.box("mouth", (0.06, 0.02, 0.09), (0.004, -0.075, hz + 0.01), m.void, bevel=0.008, rotation=(0.15, 0.08, 0))
    jaw = geo.loft("jaw", [dict(z=hz + 0.04, rx=0.06, ry=0.07, y=0.0), dict(z=hz - 0.04, rx=0.045, ry=0.06, y=-0.025),
                           dict(z=hz - 0.07, rx=0.0, ry=0.0, y=-0.04)], m.skin, 14, cap_top=False)
    teeth = _arc_bits("tooth", 0.038, 0.06, 215, 325, 7, hz + 0.055, (0.009, 0.006, 0.014), m.bone, y_off=-0.02)
    teeth += _arc_bits("tooth", 0.034, 0.055, 220, 320, 6, hz - 0.035, (0.008, 0.006, 0.012), m.bone, y_off=-0.03)
    parts = [skull, mouth, jaw] + cheeks + sockets + teeth
    if kind == "mourner":
        # Funeral veil over the head down past the chin; the jaw gapes out from under it.
        veil = geo.loft("veil_head", [dict(z=hz + 0.25, rx=0.0, ry=0.0), dict(z=hz + 0.23, rx=0.07, ry=0.08),
                                      dict(z=hz + 0.17, rx=0.1, ry=0.115, front=0.01), dict(z=hz + 0.07, rx=0.105, ry=0.12, front=0.015),
                                      dict(z=hz + 0.03, rx=0.11, ry=0.125)], m.veil, 22, cap_bottom=False)
        for o in cheeks + sockets:
            bpy_data_remove(o)
        parts = [skull, veil, mouth, jaw] + teeth
    attach(geo.join(parts, "head"), "head")


def build(m, kind, seed):
    rng = random.Random(seed)
    body = TYPES[kind]["body"]
    extra = [("robe_f", (0, -0.12, body.hips_z), (0, -0.16, 0.1), "hips"),
             ("robe_b", (0, 0.12, body.hips_z), (0, 0.18, 0.1), "hips")]
    arm = rig.build_armature(kind + "_rig", body.bones(extra))

    def attach(obj, bone):
        rig.parent_to_bone(obj, arm, bone)
        return obj

    build_head(m, body, attach, kind)
    attach(geo.loft("neck", [dict(z=body.neck_z - 0.04, rx=0.04, ry=0.04), dict(z=body.head_z + 0.04, rx=0.032, ry=0.034)],
                    m.skin, 10), "neck")
    build_limbs(m, body, attach, kind, rng)
    cz, sz, hz = body.chest_z, body.spine_z, body.hips_z
    if kind == "hollow":
        # Ribcage pushing through starved skin, hunched; a wound on the side; a rag at the hips.
        attach(geo.loft("ribcage", [dict(z=cz - 0.04, rx=0.115, ry=0.085), dict(z=cz + 0.08, rx=0.15, ry=0.11, back=0.02),
                                    dict(z=cz + 0.18, rx=0.165, ry=0.115, back=0.03), dict(z=cz + 0.24, rx=0.14, ry=0.1),
                                    dict(z=cz + 0.27, rx=0.06, ry=0.05)], m.skin, 24), "chest")
        ribs = []
        for i in range(5):
            z = cz + 0.02 + i * 0.045
            r = 0.118 + 0.01 * min(i, 3)
            ribs += _arc_bits("rib", r, r * 0.74, 200, 340, 8, z, (0.03, 0.012, 0.011), m.bone, y_off=-0.002)
        knobs = [geo.sphere("vertebra", 0.014, (0, 0.085 + 0.01 * i / 8, sz + i * 0.05), m.bone, segments=6, rings=4)
                 for i in range(9)]
        wound = geo.sphere("wound", 0.04, (0.11, -0.05, cz + 0.06), m.blood, scale=(0.5, 1, 1.4), segments=8, rings=6)
        rot = geo.sphere("rot", 0.05, (-0.09, 0.06, cz + 0.12), m.rot, scale=(0.6, 1, 1.2), segments=8, rings=6)
        attach(geo.join(ribs + knobs + [wound, rot], "ribs"), "chest")
        attach(geo.loft("belly", [dict(z=hz + 0.04, rx=0.1, ry=0.075), dict(z=sz + 0.06, rx=0.095, ry=0.068),
                                  dict(z=cz, rx=0.115, ry=0.085)], m.skin, 18, cap_bottom=False, cap_top=False), "spine")
        attach(geo.loft("pelvis", [dict(z=hz - 0.06, rx=0.11, ry=0.08), dict(z=hz + 0.06, rx=0.105, ry=0.075)], m.skin, 18),
               "hips")
        rows = []
        for li, z in enumerate((hz + 0.03, hz - 0.12, hz - 0.3)):
            hem = humanoid.tattered([z] * 21, rng, 0.12) if li == 2 else None
            rows.append(humanoid.partial_ring(0.12 + 0.02 * li, 0.09 + 0.02 * li, 0, 360, 21, z, hem, folds=7, fold_amp=0.05))
        rag = humanoid.sheet("rag", rows, m.rags)
        rig.skin_by_height(rag, arm, [("hips", hz), ("robe_f", hz - 0.3)])
        stains = [geo.sphere("stain", 0.035 + 0.02 * rng.random(), (rng.uniform(-0.1, 0.1), -0.09, rng.uniform(cz - 0.1, cz + 0.2)),
                             m.blood, scale=(1, 0.25, 1.5), segments=8, rings=6) for _ in range(3)]
        attach(geo.join(stains, "stains"), "chest")
    else:
        # Mourner: a funeral robe from the shoulders to the ground, tattered, with bell sleeves.
        attach(geo.loft("torso", [dict(z=hz, rx=0.1, ry=0.08), dict(z=cz + 0.1, rx=0.14, ry=0.1), dict(z=body.neck_z, rx=0.07, ry=0.06)],
                        m.veil, 18), "chest")
        rows = []
        levels = [(body.neck_z + 0.02, 0.1, 0.09), (cz + 0.1, 0.2, 0.15), (hz, 0.2, 0.16), (0.55, 0.26, 0.22), (0.05, 0.33, 0.29)]
        for li, (z, rx, ry) in enumerate(levels):
            hem = humanoid.tattered([z] * 37, rng, 0.18) if li == len(levels) - 1 else None
            rows.append(humanoid.partial_ring(rx, ry, 0, 360, 37, z, hem, folds=11, fold_amp=0.02 + 0.025 * li))
        robe = humanoid.sheet("robe", rows, m.veil)
        rig.skin_by_height(robe, arm, [("chest", cz + 0.05), ("hips", hz - 0.05), ("robe_f", 0.1)])
        for side, sx in (("L", 1.0), ("R", -1.0)):
            sh, el, wr = body.shoulder, body.elbow, body.wrist
            attach(geo.loft("sleeve_up", [dict(z=sh[2] + 0.03, rx=0.07, ry=0.07, x=sx * sh[0]),
                                          dict(z=el[2], rx=0.075, ry=0.075, x=sx * el[0])], m.veil, 14), "upper_arm." + side)
            srows = []
            for li, (z, r) in enumerate(((el[2] + 0.02, 0.07), ((el[2] + wr[2]) / 2, 0.1), (wr[2] + 0.05, 0.14))):
                hem = humanoid.tattered([z] * 15, rng, 0.08) if li == 2 else None
                srows.append([(x + sx * (el[0] + (wr[0] - el[0]) * li / 2), y + el[1], zz)
                              for x, y, zz in humanoid.partial_ring(r, r, 0, 360, 15, z, hem, folds=5, fold_amp=0.06)])
            attach(humanoid.sheet("sleeve", srows, m.veil), "forearm." + side)
    return arm


def creature_pose(kind, anim, t):
    hunch = 18 if kind == "hollow" else 6
    base = {"spine_x": hunch * 0.5, "chest_x": hunch * 0.6, "neck_x": -hunch * 0.6, "head_x": -hunch * 0.2,
            "armL_out": 4, "armR_out": 4, "elbowL": 12, "elbowR": 18, "armL_fwd": 8, "armR_fwd": 4}
    if anim == "idle":
        a = math.tau * t
        p = dict(base)
        # Too-still breathing, and a slow wrong tilt of the head.
        p.update({"root_z": 0.004 * math.sin(a), "head_tilt": 14 + 10 * math.sin(a), "chest_roll": 3 * math.sin(a + 1),
                  "wristL": 15 * math.sin(a * 2), "elbowR": 18 + 6 * math.sin(a + 2), "kneeL": 6, "legL_out": 4, "legR_out": 6})
        return p
    if anim == "walk":
        p = humanoid.walk_pose(t, stride=20 if kind == "hollow" else 12, bounce=0.04 if kind == "hollow" else 0.008,
                               arm_swing=6, lean=hunch * 0.5, knee_lift=34 if kind == "hollow" else 18)
        a = math.tau * t
        # A limp: the right leg drags, the body lurches to one side, arms hang dead.
        p.update({"kneeR": p["kneeR"] * 0.4, "hips_roll": 7 * math.sin(a), "chest_roll": -9 * math.sin(a),
                  "head_tilt": 10 + 6 * math.sin(a), "chest_x": hunch * 0.6, "neck_x": -hunch * 0.6,
                  "armL_out": 6, "armR_out": 4, "elbowL": 10, "elbowR": 20, "robef": -6 * math.sin(a)})
        return p
    if anim == "windup":
        keys = [(0.0, base),
                (0.6, dict(base, armL_fwd=150, armL_out=40, elbowL=40, armR_fwd=150, armR_out=40, elbowR=40, chest_x=-15,
                           spine_x=-8, neck_x=10, head_x=-10, root_z=0.03, kneeL=10, kneeR=10)),
                (1.0, dict(base, armL_fwd=165, armL_out=35, elbowL=50, armR_fwd=165, armR_out=35, elbowR=50, chest_x=-20,
                           spine_x=-10, neck_x=12, head_x=-14, root_z=0.04, kneeL=14, kneeR=14))]
        return rig.sample_keys(keys, t, False)
    if anim == "strike":
        keys = [(0.0, dict(base, armL_fwd=165, armL_out=35, elbowL=50, armR_fwd=165, armR_out=35, elbowR=50, chest_x=-20)),
                (0.5, dict(base, armL_fwd=80, armL_out=20, elbowL=10, armR_fwd=80, armR_out=20, elbowR=10, chest_x=25, spine_x=15,
                           root_fwd=0.15, root_z=-0.04, legL_fwd=25, kneeL=25, legR_fwd=-15)),
                (1.0, dict(base, armL_fwd=30, armL_out=15, elbowL=5, armR_fwd=30, armR_out=15, elbowR=5, chest_x=35, spine_x=20,
                           root_fwd=0.22, root_z=-0.07, legL_fwd=30, kneeL=35, legR_fwd=-20, head_x=-20))]
        return rig.sample_keys(keys, t, False)
    if anim == "stagger":
        keys = [(0.0, base),
                (0.3, dict(base, chest_x=-25, spine_x=-12, head_x=-30, head_tilt=30, armL_out=40, armR_out=50, elbowL=30,
                           root_fwd=-0.12, legR_fwd=20, kneeR=20)),
                (1.0, dict(base, chest_x=5, head_tilt=-10, root_fwd=-0.08))]
        return rig.sample_keys(keys, t, False)
    if anim == "death":
        keys = [(0.0, base),
                (0.25, dict(base, head_tilt=40, head_x=-20, chest_x=-15, armL_out=30, armR_out=20, root_fwd=-0.05)),
                (0.55, dict(base, kneeL=80, kneeR=70, legL_fwd=40, legR_fwd=30, root_z=-0.35, chest_x=30, head_x=40, ankleL=-30,
                            ankleR=-30, armL_fwd=20, armR_fwd=30)),
                (1.0, dict(root_pitch=82, root_z=0.0, root_fwd=0.0, head_turn=40, armL_out=70, armR_out=20, elbowL=60, armR_fwd=20,
                           legL_fwd=10, kneeL=30, legR_out=10, head_tilt=20))]
        return rig.sample_keys(keys, t, False)
    return dict(base)


EXTRA = {"robef": ("robe_f", "x"), "robeb": ("robe_b", "x")}


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--type", default="hollow", choices=sorted(TYPES))
    ap.add_argument("--preview", action="store_true")
    ap.add_argument("--only", default="")
    ap.add_argument("--dirs", default="")
    ap.add_argument("--out", default=OUT)
    args = ap.parse_args(argv)
    kind = args.type
    spec = TYPES[kind]
    sprite_render.clear_scene()
    sprite_render.setup_render(512, 6 if args.preview else 16)
    sprite_render.world_hdri("kloofendal_overcast_puresky", CACHE, strength=0.35, tint=(0.6, 0.7, 0.66))
    # Cold, low key from below-front (unwholesome), cold rim.
    sprite_render.sun("key", (60, 0, -30), (0.8, 0.88, 0.85), 2.4, 10)
    sprite_render.sun("under", (150, 0, 20), (0.55, 0.7, 0.55), 0.6, 30)
    sprite_render.sun("rim", (60, 0, 160), (0.85, 0.95, 1.0), 2.8, 6)
    sprite_render.camera(spec["camera"], spec["center"])
    m = Mats(kind)
    arm = build(m, kind, 21 if kind == "hollow" else 33)

    def pose(anim, t):
        p = creature_pose(kind, anim, t)
        # Face the viewer whatever the body does: undo the body's yaw at the neck and head.
        yaw = math.degrees(arm.rotation_euler.z)
        yaw = (yaw + 180.0) % 360.0 - 180.0
        if anim != "death" or t < 0.6:
            p["neck_turn"] = p.get("neck_turn", 0.0) - yaw * 0.35
            p["head_turn"] = p.get("head_turn", 0.0) - yaw * 0.65
        humanoid.apply_pose(arm, p, EXTRA)

    only = [a for a in args.only.split(",") if a]
    dirs = [int(d) for d in args.dirs.split(",") if d] or None
    sprite_render.render_character(kind, arm, pose, ANIMS, args.out, 8, spec["camera"], spec["height"], 40,
                                   only or None, dirs, sprite_render.material_table(m.table()))


if __name__ == "__main__":
    main()
