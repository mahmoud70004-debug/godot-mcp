"""Shared humanoid skeleton, pose vocabulary and cloth helpers for the sprite characters.

Pose dicts use semantic keys in degrees (metres for root_z / root_fwd), applied on top of
the rest pose by apply_pose():
  root_z, root_fwd, root_pitch, hips_x/_twist/_roll, spine_x/_twist, chest_x/_twist/_roll,
  neck_x, head_x/_turn/_tilt, arm{L,R}_fwd/_out/_twist, elbow{L,R}, wrist{L,R},
  leg{L,R}_fwd/_out, knee{L,R}, ankle{L,R}; plus character extras {key: (bone, axis)}.
"""
import math

import bmesh

from . import geo, rig


class Body:
    """Joint positions (metres, Z up, facing -Y, left = +X). Mirrored for the right side."""

    def __init__(self, shoulder, elbow, wrist, hip, knee, ankle, hips_z=0.95, spine_z=1.08, chest_z=1.28,
                 neck_z=1.5, head_z=1.58, head_top=1.84, hand_len=0.11, toe_y=-0.14):
        self.shoulder, self.elbow, self.wrist = shoulder, elbow, wrist
        self.hip, self.knee, self.ankle = hip, knee, ankle
        self.hips_z, self.spine_z, self.chest_z = hips_z, spine_z, chest_z
        self.neck_z, self.head_z, self.head_top = neck_z, head_z, head_top
        self.hand_len, self.toe_y = hand_len, toe_y

    def bones(self, extra=()):
        b = [
            ("root", (0, 0, 0), (0, 0, 0.2), None),
            ("hips", (0, 0, self.hips_z), (0, 0, self.spine_z), "root"),
            ("spine", (0, 0, self.spine_z), (0, 0, self.chest_z), "hips"),
            ("chest", (0, 0, self.chest_z), (0, 0, self.neck_z), "spine"),
            ("neck", (0, 0, self.neck_z), (0, 0, self.head_z), "chest"),
            ("head", (0, 0, self.head_z), (0, 0, self.head_top), "neck"),
        ]
        for s, x in (("L", 1.0), ("R", -1.0)):
            sh, el, wr = self.shoulder, self.elbow, self.wrist
            hp, kn, an = self.hip, self.knee, self.ankle
            b += [
                ("upper_arm." + s, (sh[0] * x, sh[1], sh[2]), (el[0] * x, el[1], el[2]), "chest"),
                ("forearm." + s, (el[0] * x, el[1], el[2]), (wr[0] * x, wr[1], wr[2]), "upper_arm." + s),
                ("hand." + s, (wr[0] * x, wr[1], wr[2]), (wr[0] * x, wr[1] - 0.01, wr[2] - self.hand_len), "forearm." + s),
                ("thigh." + s, (hp[0] * x, hp[1], hp[2]), (kn[0] * x, kn[1], kn[2]), "hips"),
                ("shin." + s, (kn[0] * x, kn[1], kn[2]), (an[0] * x, an[1], an[2]), "thigh." + s),
                ("foot." + s, (an[0] * x, an[1], an[2]), (an[0] * x, self.toe_y, 0.03), "shin." + s),
            ]
        return b + list(extra)

    def arm_x(self, z, side):
        """x of the arm line at height z (upper arm and forearm are slightly splayed)."""
        sh, el, wr = self.shoulder, self.elbow, self.wrist
        if z >= el[2]:
            t = (sh[2] - z) / (sh[2] - el[2])
            return side * (sh[0] + (el[0] - sh[0]) * t)
        t = (el[2] - z) / (el[2] - wr[2])
        return side * (el[0] + (wr[0] - el[0]) * t)


REST = {"armL_out": 6, "armR_out": 6, "elbowL": 8, "elbowR": 8}


def apply_pose(arm, p, extra=None, rest=REST):
    rig.reset_pose(arm)
    g = lambda k: p.get(k, rest.get(k, 0.0))  # noqa: E731
    # Root bone axes: Y = world up, Z = world -Y (forward).
    arm.pose.bones["root"].location = (0.0, g("root_z"), g("root_fwd"))
    rig.rot(arm, "root", x=g("root_pitch"), y=g("root_turn"))
    rig.rot(arm, "hips", x=g("hips_x"), y=g("hips_twist"), z=g("hips_roll"))
    rig.rot(arm, "spine", x=g("spine_x"), y=g("spine_twist"))
    rig.rot(arm, "chest", x=g("chest_x"), y=g("chest_twist"), z=g("chest_roll"))
    rig.rot(arm, "neck", x=g("neck_x"), y=g("neck_turn"))
    rig.rot(arm, "head", x=g("head_x"), y=g("head_turn"), z=g("head_tilt"))
    for s in ("L", "R"):
        rig.arm(arm, s, forward=g("arm%s_fwd" % s), out=g("arm%s_out" % s), twist=g("arm%s_twist" % s),
                elbow=g("elbow" + s), wrist=g("wrist" + s))
        rig.leg(arm, s, forward=g("leg%s_fwd" % s), out=g("leg%s_out" % s), knee=g("knee" + s), ankle=g("ankle" + s))
    for key, (bone, axis) in (extra or {}).items():
        rig.rot(arm, bone, **{axis: g(key)})


def walk_pose(t, stride=26.0, bounce=0.025, arm_swing=22.0, lean=5.0, knee_lift=40.0):
    """Walk cycle over t in [0, 1): contact, down, passing, up per step; opposite arm swing
    and counter-twist of hips and chest."""
    a = math.tau * t
    s = math.sin(a)
    c = math.cos(a)
    lift_l = max(0.0, math.sin(a + math.pi / 2))
    lift_r = max(0.0, math.sin(a - math.pi / 2))
    return {
        "root_z": -bounce * abs(c) + bounce * 0.4,
        "hips_twist": 6 * s, "chest_twist": -9 * s, "spine_x": lean, "chest_x": 2, "head_x": -4, "head_turn": 3 * s,
        "hips_roll": 2.5 * c,
        "legL_fwd": stride * s, "legR_fwd": -stride * s,
        "kneeL": 8 + knee_lift * lift_l, "kneeR": 8 + knee_lift * lift_r,
        "ankleL": -8 * s, "ankleR": 8 * s,
        "armL_fwd": -arm_swing * s, "armR_fwd": arm_swing * s, "armL_out": 7, "armR_out": 7,
        "elbowL": 14 + 10 * max(0.0, -s), "elbowR": 14 + 10 * max(0.0, s),
    }


# --- cloth helpers -------------------------------------------------------------------------

def tattered(pts_z, rng, depth):
    """Ragged hem heights: alternate deep and shallow tears."""
    return [z - rng.random() * depth * (1.0 if i % 2 else 0.45) for i, z in enumerate(pts_z)]


def partial_ring(rx, ry, a0, a1, n, z, jitter=None, y_off=0.0, folds=0, fold_amp=0.0):
    """Arc of an ellipse (degrees, 0 = +X, 90 = +Y = behind); `folds` ripples the radius like hanging cloth."""
    pts = []
    for i in range(n):
        a = math.radians(a0 + (a1 - a0) * i / (n - 1))
        k = 1.0 + fold_amp * math.sin(a * folds)
        pts.append((rx * k * math.cos(a), ry * k * math.sin(a) + y_off, z if jitter is None else jitter[i]))
    return pts


def sheet(name, rows, material, thickness=0.012):
    """Open cloth surface through rows of (x, y, z) points (same count per row)."""
    bm = bmesh.new()
    grid = [[bm.verts.new(p) for p in row] for row in rows]
    for r0, r1 in zip(grid, grid[1:]):
        for i in range(len(r0) - 1):
            bm.faces.new((r0[i], r0[i + 1], r1[i + 1], r1[i]))
    obj = geo.mesh_object(name, bm, material)
    geo.solidify(obj, thickness)
    return obj
