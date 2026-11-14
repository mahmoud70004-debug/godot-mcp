"""Sculpt four hero tree trunks procedurally and export them as low-poly game data.

Run (headless, deterministic - every random number comes from a fixed per-tree seed):
    BL=$(tools/setup_blender.sh)
    $BL -b -P tools/blender/trees/sculpt_trunks.py              # all four trees
    $BL -b -P tools/blender/trees/sculpt_trunks.py -- elder     # only the named tree(s)

Pipeline per tree
  1. Skeleton: trunk polyline (lean, S-bends, flare), rising/spreading limbs with antler sub-forks,
     claw roots (plank-shaped near the trunk, knuckled, diving into the ground).
  2. HIGH sculpt as a signed distance field on a dense voxel grid (numpy): every branch is a chain of
     tapered (root: elliptic) cones; in its own cylinder frame (arc length s along the grain, angle
     around it) the branch is displaced by twisted lobes/flutes, burls, knot holes like eye sockets
     (deep pits with a swollen rim) and fine bark: two octaves of grain-stretched ridged gradient
     noise -> deep narrow vertical furrows between raised plates.  Branches are merged with smooth
     unions (crotch and buttress fillets); hollows are carved with smooth subtraction; everything is
     cut flat at y=-0.4 (under the ground) so the result is closed.  Meshed with OpenVDB
     (pyopenvdb volume -> quads).  Two fields are kept: BASE (no fine bark) and FULL (with bark).
  3. LOW game mesh: two-stage quadric (collapse) decimation of the BASE mesh to the triangle budget
     (hollows and the elder's eye sockets weighted so they survive), cleanup (largest closed shell
     only, triangles only, consistent outward winding), fold repair by edge flips checked against
     the SDF gradient.
  4. Bake: per high vertex AO (SDF ray-march + ground plane) x cavity (furrow depth = FULL vs BASE);
     averaged onto the low vertices -> vertex colour = bark x AO/cavity multiplier (0.25..1),
     moss creeping up one side of the lower 1-2 m, near-black inside hollows.  Low normals =
     smoothed high-poly normals transferred to the low vertices (data-transfer style).
  5. Export data/trees/trunk_<name>.json (Godot Y-up, clockwise front faces) + review renders in
     build/trunks/ (Cycles CPU).
"""

import json
import math
import os
import sys
import time

import bmesh
import bpy
import numpy as np
import pyopenvdb as vdb
from mathutils import Vector
from mathutils.kdtree import KDTree

HERE = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
OUT_DATA = os.path.join(PROJ, "data", "trees")
OUT_REN = os.path.join(PROJ, "build", "trunks")
F32 = np.float32
Z_CUT = -0.4  # everything below is cut flat (hidden under the terrain)
UP = np.array([0.0, 0.0, 1.0])

# ----------------------------------------------------------------------------------------------
# tree specifications (Blender frame: Z up, "front" of a tree = -Y blender = +Z godot)
# ----------------------------------------------------------------------------------------------
TREES = [
    dict(name="tall", seed=1101, R1=0.42, fork=8.0, budget=460, bark=(0.30, 0.29, 0.31), voxel=0.026,
         lean=0.10, lean_az=0.6, bend=0.85, twist=0.10,
         limbs=4, limb_len=(3.0, 4.5), limb_el=(58, 80), limb_r=0.72, gnarl=0.13, rise=0.10, droop=0.0,
         sub=(1.0, 0.36, 0.48), leader=True,
         roots=5, root_len=(1.5, 2.1), root_h0=0.55, root_r=0.50, plank=0.45,
         lobe=0.15, fur=0.070, fur_fa=6.0, fur_fs=0.55,
         knots=[(3.2, -95, 0.15, 0.20, 0.17), (5.6, 60, 0.12, 0.16, 0.13)],
         burls=[(2.1, 150, 0.22, 0.30, 0.12), (4.3, 20, 0.2, 0.3, 0.10), (6.6, -30, 0.18, 0.25, 0.10)],
         clump=(2.3, 3.0), moss_az=-140, hollow=None),
    dict(name="broad", seed=2202, R1=0.64, fork=4.4, budget=420, bark=(0.33, 0.31, 0.30), voxel=0.030,
         lean=0.20, lean_az=35, bend=0.45, twist=0.30,
         limbs=5, limb_len=(5.5, 7.5), limb_el=(16, 34), limb_r=0.66, gnarl=0.15, rise=0.15, droop=0.06,
         sub=(0.8, 0.34, 0.45), leader=False,
         roots=6, root_len=(1.6, 2.4), root_h0=0.65, root_r=0.48, plank=0.5,
         lobe=0.17, fur=0.085, fur_fa=4.8, fur_fs=0.45,
         knots=[(2.0, -80, 0.18, 0.22, 0.20), (3.3, 100, 0.15, 0.18, 0.16)],
         burls=[(1.4, 20, 0.30, 0.35, 0.14), (2.8, -150, 0.25, 0.30, 0.12), (3.8, -60, 0.22, 0.25, 0.10)],
         clump=(2.6, 3.4), moss_az=-120, hollow=None),
    dict(name="elder", seed=3303, R1=1.15, taper=0.12, fork=5.2, budget=760, bark=(0.36, 0.35, 0.34), voxel=0.040,
         lean=0.04, lean_az=200, bend=0.30, twist=0.12,
         limbs=5, limb_len=(8.5, 11.0), limb_el=(18, 36), limb_r=0.60, gnarl=0.12, rise=0.11, droop=0.06,
         sub=(1.0, 0.32, 0.42), leader=False,
         roots=8, root_len=(2.2, 3.0), root_h0=0.55, root_r=0.46, plank=0.6,
         lobe=0.15, fur=0.13, fur_fa=3.3, fur_fs=0.32,
         # face: two eye sockets above the mouth-hollow, a nose burl, brow burls
         knots=[(3.25, -90 - 31, 0.27, 0.27, 0.45), (3.25, -90 + 31, 0.27, 0.27, 0.45), (4.4, 40, 0.24, 0.24, 0.3)],
         burls=[(2.62, -90, 0.20, 0.36, 0.20), (3.66, -90 - 33, 0.36, 0.13, 0.15),
                (3.66, -90 + 33, 0.36, 0.13, 0.15), (1.9, 120, 0.4, 0.45, 0.18), (3.9, -10, 0.3, 0.35, 0.14)],
         calm=[(2.7, -90, 1.0, 1.3, 0.8)],
         clump=(3.2, 4.4), moss_az=-150, hollow="mouth"),
    dict(name="hollow", seed=4404, R1=0.62, fork=6.0, budget=440, bark=(0.27, 0.26, 0.28), voxel=0.028,
         lean=0.07, lean_az=130, bend=0.30, twist=0.10,
         limbs=4, limb_len=(5.8, 7.2), limb_el=(62, 80), limb_r=0.68, gnarl=0.12, rise=0.22, droop=0.0,
         sub=(1.0, 0.34, 0.46), leader=False,
         roots=5, root_len=(1.6, 2.3), root_h0=0.6, root_r=0.48, plank=0.45,
         lobe=0.15, fur=0.075, fur_fa=5.0, fur_fs=0.5,
         knots=[(4.4, 70, 0.14, 0.18, 0.17)],
         burls=[(3.6, -60, 0.22, 0.28, 0.10), (5.0, 170, 0.22, 0.30, 0.10)],
         clump=(2.4, 3.2), moss_az=-170, hollow="split"),
]


# ----------------------------------------------------------------------------------------------
# noise
# ----------------------------------------------------------------------------------------------
_GRAD = np.array([[1, 1, 0], [-1, 1, 0], [1, -1, 0], [-1, -1, 0], [1, 0, 1], [-1, 0, 1], [1, 0, -1],
                  [-1, 0, -1], [0, 1, 1], [0, -1, 1], [0, 1, -1], [0, -1, -1], [1, 1, 0], [-1, 1, 0],
                  [0, -1, 1], [0, -1, -1]], F32)


class Perlin:
    """Vectorised 3D gradient noise, roughly in [-1, 1]."""

    def __init__(self, seed):
        p = np.random.default_rng(seed).permutation(256).astype(np.int32)
        self.p = np.concatenate([p, p])

    def __call__(self, x, y, z):
        p = self.p
        xf0, yf0, zf0 = np.floor(x), np.floor(y), np.floor(z)
        xf, yf, zf = (x - xf0).astype(F32), (y - yf0).astype(F32), (z - zf0).astype(F32)
        xi, yi, zi = xf0.astype(np.int64) & 255, yf0.astype(np.int64) & 255, zf0.astype(np.int64) & 255
        u = xf * xf * xf * (xf * (xf * 6 - 15) + 10)
        v = yf * yf * yf * (yf * (yf * 6 - 15) + 10)
        w = zf * zf * zf * (zf * (zf * 6 - 15) + 10)
        A = p[xi] + yi
        B = p[xi + 1] + yi
        AA, AB, BA, BB = p[A] + zi, p[A + 1] + zi, p[B] + zi, p[B + 1] + zi

        def g(h, gx, gy, gz):
            gg = _GRAD[p[h] & 15]
            return gg[:, 0] * gx + gg[:, 1] * gy + gg[:, 2] * gz

        x1 = g(AA, xf, yf, zf) + u * (g(BA, xf - 1, yf, zf) - g(AA, xf, yf, zf))
        x2 = g(AB, xf, yf - 1, zf) + u * (g(BB, xf - 1, yf - 1, zf) - g(AB, xf, yf - 1, zf))
        y1 = x1 + v * (x2 - x1)
        x3 = g(AA + 1, xf, yf, zf - 1) + u * (g(BA + 1, xf - 1, yf, zf - 1) - g(AA + 1, xf, yf, zf - 1))
        x4 = g(AB + 1, xf, yf - 1, zf - 1) + u * (g(BB + 1, xf - 1, yf - 1, zf - 1) - g(AB + 1, xf, yf - 1, zf - 1))
        y2 = x3 + v * (x4 - x3)
        return y1 + w * (y2 - y1)


def smin(a, b, k):
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
    return b + (a - b) * h - k * h * (1.0 - h)


def smax(a, b, k):
    return -smin(-a, -b, k)


def nrm(v):
    return v / max(np.linalg.norm(v), 1e-12)


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


# ----------------------------------------------------------------------------------------------
# branches
# ----------------------------------------------------------------------------------------------
class Branch:
    def __init__(self, pts, radii, kind, k, asp=None, lobe=0.05, lobe_fn=None, fur=0.05, fur_rref=0.3,
                 fa=5.0, fs=0.5, twist=0.1, off=(0, 0, 0)):
        self.P = np.asarray(pts, np.float64)
        self.R = np.asarray(radii, np.float64)
        self.A = np.ones(len(self.P)) if asp is None else np.asarray(asp, np.float64)
        self.kind, self.k = kind, k
        self.lobe, self.lobe_fn, self.fur, self.fur_rref = lobe, lobe_fn, fur, fur_rref
        self.fa, self.fs, self.twist, self.off = fa, fs, twist, np.asarray(off, np.float64)
        self.features = []  # dicts: s0, th0, wt (m around), ws (m along), depth (pit) / height (burl)
        D = self.P[1:] - self.P[:-1]
        self.L = np.linalg.norm(D, axis=1)
        self.T = D / self.L[:, None]
        self.S = np.concatenate([[0.0], np.cumsum(self.L)])
        U, V = [], []
        u = None
        for t in self.T:
            if kind == "root" and abs(t[2]) < 0.85:
                u = nrm(np.cross(t, UP))
            elif u is None:
                ref = np.array([1.0, 0, 0]) if abs(t[0]) < 0.9 else np.array([0, 1.0, 0])
                u = nrm(np.cross(t, ref))
            else:
                u = nrm(u - np.dot(u, t) * t)
            U.append(u)
            V.append(np.cross(t, u))
        self.U, self.V = np.array(U), np.array(V)

    def point_at_s(self, s):
        i = int(np.clip(np.searchsorted(self.S, s) - 1, 0, len(self.L) - 1))
        t = np.clip((s - self.S[i]) / self.L[i], 0, 1)
        return i, self.P[i] + t * (self.P[i + 1] - self.P[i]), self.R[i] + t * (self.R[i + 1] - self.R[i])

    def angle_of(self, s, az_deg):
        i, _, _ = self.point_at_s(s)
        d = np.array([math.cos(math.radians(az_deg)), math.sin(math.radians(az_deg)), 0.0])
        return math.atan2(np.dot(d, self.V[i]), np.dot(d, self.U[i]))

    def bounds(self, extra):
        e = (self.R * np.maximum(self.A, 1.0))[:, None] + extra
        return (self.P - e).min(0), (self.P + e).max(0)

    def max_disp(self):
        rmax = self.R.max()
        lf = 1.0 if self.lobe_fn is None else float(self.lobe_fn(0.0))
        lob = self.lobe * lf * rmax * 1.6
        pit = max([f["depth"] for f in self.features if f["type"] == "pit"] or [0.0])
        burl = max([f["height"] for f in self.features if f["type"] == "burl"] or [0.0])
        inn = lob + self.fur * 1.7 + pit + 0.05
        out = lob + self.fur * 0.5 + max(burl * 1.45, pit * 0.35) + 0.05
        return inn, out

    def displacement(self, qu, qv, s, r, noise):
        n_lobe, n_f1, n_f2, n_r = noise
        th = np.arctan2(qv, qu)
        tt = th + self.twist * s
        c, sn = np.cos(tt), np.sin(tt)
        o = self.off
        # big shape: twisted lobes / flutes (angular, independent of radius)
        # rope-like twisted ribs separated by big narrow grooves (zero crossings of a stretched noise)
        nl = n_lobe(c * 1.5 + o[0], sn * 1.5 + o[1], s * 0.2 + o[2])
        lob = 0.36 - 1.15 * np.exp(-(nl / 0.32) ** 2) + 0.35 * nl  # grooves wide enough for the low mesh
        lamp = self.lobe if self.lobe_fn is None else self.lobe * self.lobe_fn(s)
        calm = np.ones_like(s)
        for f in self.features:  # calm zones: the face reads better on a quieter patch of trunk
            if f["type"] == "calm":
                dth = np.angle(np.exp(1j * (th - f["th0"])))
                calm = calm * (1.0 - f["k"] * np.exp(-((dth * r / f["wt"]) ** 2 + ((s - f["s0"]) / f["ws"]) ** 2)))
        base = lamp * r * lob * 1.6 * calm
        for f in self.features:
            if f["type"] == "calm":
                continue
            dth = np.angle(np.exp(1j * (th - f["th0"])))
            q2 = (dth * r / f["wt"]) ** 2 + ((s - f["s0"]) / f["ws"]) ** 2
            if f["type"] == "pit":
                prof = np.clip(1.0 - q2, 0.0, 1.0)
                base = base - f["depth"] * prof ** 0.45
                qq = np.sqrt(q2)
                base = base + f["depth"] * 0.28 * np.exp(-((qq - 1.12) / 0.32) ** 2)  # swollen rim
            else:
                bump = np.exp(-q2 * 1.6)
                base = base + f["height"] * bump * (1.0 + 0.35 * n_r(c * 3 + o[1], sn * 3, s * 2.0))
        # fine bark: grain-stretched ridged noise -> deep narrow furrows, raised plates between
        X, Y = c * r, sn * r
        fa, fs = self.fa, self.fs
        n1 = n_f1(X * fa + o[0], Y * fa + o[1], s * fs + o[2])
        n2 = n_f2(X * fa * 2.3 + o[1], Y * fa * 2.3 + o[2], s * fs * 2.2 + o[0])
        n3 = n_r(X * fa * 5.0, Y * fa * 5.0, s * fs * 9.0)
        g1 = np.exp(-(n1 / 0.15) ** 2)
        g2 = np.exp(-(n2 / 0.13) ** 2)
        plate = np.clip(np.abs(n1), 0, 0.55)
        amp = self.fur * np.clip(r / self.fur_rref, 0.12, 1.0)
        fine = amp * (-1.0 * g1 - 0.45 * g2 + 0.45 * plate + 0.10 * n3)
        return base.astype(F32), fine.astype(F32)


# ----------------------------------------------------------------------------------------------
# skeleton
# ----------------------------------------------------------------------------------------------
def build_skeleton(S, rng, noise=None):
    R1, fork = S["R1"], S["fork"]
    tw = S["twist"]
    # --- trunk
    zt = np.linspace(-0.5, fork + 0.35 * R1, max(12, int((fork + 0.9) / 0.3)))
    la = math.radians(S["lean_az"])
    ldir = np.array([math.cos(la), math.sin(la)])
    pdir = np.array([-ldir[1], ldir[0]])
    ph1, ph2 = rng.uniform(0, 6.28, 2)
    zp = np.maximum(zt, 0.0)
    off = (ldir[None, :] * (S["lean"] * zp * (zp / fork) ** 0.35)[:, None]
           + pdir[None, :] * (S["bend"] * R1 * (np.sin(zp / fork * 3.4 + ph1) - math.sin(ph1)))[:, None]
           + ldir[None, :] * (0.5 * S["bend"] * R1 * (np.sin(zp / fork * 5.1 + ph2) - math.sin(ph2)))[:, None])
    tp = np.column_stack([off, zt])
    taper = S.get("taper", 0.30)
    rt = (R1 * (1 - taper * (zt - 1.0) / (fork - 1.0)) + 0.40 * R1 * (np.exp(-zt / 0.6) - math.exp(-1 / 0.6))
          + 0.10 * R1 * np.exp(-((zt - fork) / (0.6 * fork ** 0.5)) ** 2))
    rt = np.maximum(rt, 0.2 * R1)
    Rf = float(np.interp(fork, zt, rt))

    def trunk_at(z):
        return np.array([np.interp(z, zt, tp[:, 0]), np.interp(z, zt, tp[:, 1]), z])

    noff = lambda: rng.uniform(0, 200, 3)
    common = dict(fa=S["fur_fa"], fs=S["fur_fs"], twist=tw)
    trunk = Branch(tp, rt, "trunk", k=0.0, lobe=S["lobe"] * 1.7, fur=S["fur"], fur_rref=R1 * 0.6,
                   lobe_fn=lambda s: 1.0 + 0.8 * np.exp(-np.maximum(s - 0.5, 0) / 1.4), off=noff(), **common)
    for (z, az, wt, ws, depth) in S["knots"]:
        trunk.features.append(dict(type="pit", s0=z + 0.5, th0=trunk.angle_of(z + 0.5, az), wt=wt, ws=ws, depth=depth))
    for (z, az, wt, ws, k) in S.get("calm", []):
        trunk.features.append(dict(type="calm", s0=z + 0.5, th0=trunk.angle_of(z + 0.5, az), wt=wt, ws=ws, k=k))
    for (z, az, wt, ws, h) in S["burls"]:
        trunk.features.append(dict(type="burl", s0=z + 0.5, th0=trunk.angle_of(z + 0.5, az), wt=wt, ws=ws, height=h))
    # the sculpt (grooves between the ribs, furrows) eats into the trunk on average: rescale the trunk
    # so its sculpted body radius at 1.0 m (median over 72 directions) equals R1
    if noise is not None:
        s1 = 1.0 - tp[0, 2]
        for _ in range(3):
            _, _, r1 = trunk.point_at_s(s1)
            th = np.linspace(-math.pi, math.pi, 72, endpoint=False)
            rr1 = np.full(72, r1)
            bd, fd = trunk.displacement(np.cos(th) * rr1, np.sin(th) * rr1, np.full(72, s1), rr1, noise)
            f = R1 / float(np.median(r1 + bd + fd))
            trunk.R *= f
            rt = rt * f
    branches = [trunk]

    # --- roots (claws)
    nr = S["roots"]
    az0 = rng.uniform(0, 6.28)
    if S["hollow"]:  # keep the opening (front, -Y) between two roots
        az0 = -math.pi / 2 + math.pi / nr
    for i in range(nr):
        az = az0 + 2 * math.pi * i / nr + rng.uniform(-0.28, 0.28) * (0.4 if S["hollow"] else 1.0)
        Lr = rng.uniform(*S["root_len"])
        h0 = S["root_h0"] * rng.uniform(0.8, 1.2)
        r0 = R1 * S["root_r"] * rng.uniform(0.85, 1.15)
        curl = rng.uniform(-0.35, 0.35)
        kn = rng.uniform(0.6, 1.2)
        n = 16
        t = np.linspace(0, 1, n)
        rho = 0.12 * R1 + (0.9 * R1 + Lr) * t ** 0.85
        rr = r0 * (1 - t) ** 0.85 + 0.035
        # claw: rides on the ground with its axis above it (knuckles), then the tip digs in
        z = (h0 * (1 - t) ** 1.8 + 0.75 * rr * smoothstep(0.0, 0.25, t) + kn * 0.18 * R1 * np.sin(math.pi * t) ** 2
             + 0.04 * R1 * np.sin(3.3 * math.pi * t + kn) - 0.8 * np.maximum(0, (t - 0.8) / 0.2) ** 1.6)
        a = az + curl * t ** 2
        base = trunk_at(0.0)
        pts = np.column_stack([base[0] + rho * np.cos(a), base[1] + rho * np.sin(a), z])
        asp = 1.0 + S["plank"] * (1 - t) ** 1.6
        branches.append(Branch(pts, rr, "root", k=0.30 * R1, asp=asp, lobe=0.05, fur=S["fur"] * 0.8,
                               fur_rref=R1 * 0.35, off=noff(), **common))

    # --- limbs with antler sub-forks
    limbs, tips = [], []
    nl = S["limbs"]
    laz0 = rng.uniform(0, 6.28)
    lens = np.linspace(S["limb_len"][0], S["limb_len"][1], nl)
    rng.shuffle(lens)
    for i in range(nl):
        az = laz0 + 2 * math.pi * i / nl + rng.uniform(-0.3, 0.3)
        el = math.radians(rng.uniform(*S["limb_el"]))
        if S["leader"] and i == 0:
            el = math.radians(84)
        L = float(lens[i])
        r0 = Rf * S["limb_r"] * rng.uniform(0.9, 1.1)
        start = trunk_at(fork - 0.25 * Rf)
        d = np.array([math.cos(el) * math.cos(az), math.cos(el) * math.sin(az), math.sin(el)])
        n = max(9, int(L / 0.3) + 1)
        step = L / (n - 1)
        pts, dirs = [start.copy()], [d.copy()]
        p = start.copy()
        for j in range(1, n):
            tj = j / (n - 1)
            kick = rng.normal(0, S["gnarl"], 3)
            if rng.random() < 0.12:
                kick += rng.normal(0, 0.35, 3)  # elbow
            d = nrm(d + kick + UP * (S["rise"] * tj - S["droop"] * (1 - tj)))
            if p[2] + d[2] * step < fork * 0.92 or d[2] < -0.25:  # limbs never sag towards the ground
                d = nrm(d + UP * 0.45)
            p = p + d * step
            pts.append(p.copy())
            dirs.append(d.copy())
        pts = np.array(pts)
        t = np.linspace(0, 1, n)
        rr = r0 * (1 - t) ** 0.8 + 0.034 * t
        sub_p, sub_frac, sub_len = S["sub"]
        if rng.random() < sub_p:
            tf = rng.uniform(0.40, 0.58)
            jf = int(tf * (n - 1))
            rr = rr * np.where(t > tf, 0.86, 1.0) ** np.clip((t - tf) * 8, 0, 1)
            dl = dirs[jf]
            side = nrm(np.cross(dl, rng.normal(0, 1, 3)))
            ds = nrm(dl * 0.7 + side * 0.72 + UP * 0.30)
            Ls = L * rng.uniform(sub_frac, sub_len)
            ns = max(6, int(Ls / 0.3) + 1)
            sp, q, dd = [pts[jf].copy()], pts[jf].copy(), ds
            for j in range(1, ns):
                dd = nrm(dd + rng.normal(0, S["gnarl"] * 1.1, 3) + UP * S["rise"] * 0.8)
                q = q + dd * (Ls / (ns - 1))
                sp.append(q.copy())
            ts = np.linspace(0, 1, ns)
            rs = rr[jf] * 0.62 * (1 - ts) ** 0.8 + 0.032 * ts
            sb = Branch(sp, rs, "limb", k=0.12 * rr[jf], lobe=0.05, fur=S["fur"] * 0.7, fur_rref=Rf * 0.5,
                        off=noff(), **common)
            limbs.append(("sub", sb))
        lb = Branch(pts, rr, "limb", k=0.30 * Rf, lobe=0.06, fur=S["fur"] * 0.8, fur_rref=Rf * 0.6,
                    off=noff(), **common)
        limbs.append(("main", lb))
    # main limbs first, then subs (so subs fillet onto existing limbs)
    mains = [b for kind, b in limbs if kind == "main"]
    subs = [b for kind, b in limbs if kind == "sub"]
    branches += mains + subs
    return dict(branches=branches, trunk=trunk, mains=mains, subs=subs, Rf=Rf, trunk_at=trunk_at,
                zt=zt, rt=rt)


# ----------------------------------------------------------------------------------------------
# SDF evaluation
# ----------------------------------------------------------------------------------------------
class Grid:
    def __init__(self, lo, hi, vs):
        self.vs = vs
        self.o = np.floor(lo / vs) * vs
        self.n = (np.ceil((hi - self.o) / vs).astype(int) + 1)
        self.base = np.full(tuple(self.n), 9.0, F32)
        self.full = np.full(tuple(self.n), 9.0, F32)

    def idx_range(self, lo, hi):
        i0 = np.clip(np.floor((lo - self.o) / self.vs).astype(int), 0, self.n - 1)
        i1 = np.clip(np.ceil((hi - self.o) / self.vs).astype(int) + 1, 1, self.n)
        return i0, i1

    def axes(self, i0, i1):
        return [(self.o[a] + np.arange(i0[a], i1[a]) * self.vs).astype(F32) for a in range(3)]


def add_branch(G, br, noise):
    vs = G.vs
    inn, out = br.max_disp()
    lo, hi = br.bounds((2 * out + br.k + 3 * vs) * max(br.A.max(), 1.0))
    b0, b1 = G.idx_range(lo, hi)
    shp = tuple(b1 - b0)
    dmin = np.full(shp, 9.0, F32)
    QU = np.zeros(shp, F32)
    QV = np.zeros(shp, F32)
    SS = np.zeros(shp, F32)
    RR = np.zeros(shp, F32)
    for kseg in range(len(br.L)):
        a, b = br.P[kseg], br.P[kseg + 1]
        ra, rb = br.R[kseg], br.R[kseg + 1]
        aa, ab = br.A[kseg], br.A[kseg + 1]
        e = (max(ra, rb) + 2 * out + 3 * vs + br.k) * max(aa, ab, 1.0)
        s0, s1 = G.idx_range(np.minimum(a, b) - e, np.maximum(a, b) + e)
        s0 = np.maximum(s0, b0)
        s1 = np.minimum(s1, b1)
        if np.any(s1 <= s0):
            continue
        xs, ys, zs = G.axes(s0, s1)
        px = (xs - a[0])[:, None, None]
        py = (ys - a[1])[None, :, None]
        pz = (zs - a[2])[None, None, :]
        ba = (b - a).astype(F32)
        L2 = float(np.dot(ba, ba))
        # interior joints: let neighbouring cones overlap (no end spheres -> no terraces on tapers)
        t_lo = 0.0 if kseg == 0 else -0.45
        t_hi = 1.0 if kseg == len(br.L) - 1 else 1.45
        t = np.clip((px * ba[0] + py * ba[1] + pz * ba[2]) / L2, t_lo, t_hi)
        qx, qy, qz = px - t * ba[0], py - t * ba[1], pz - t * ba[2]
        u, v = br.U[kseg].astype(F32), br.V[kseg].astype(F32)
        qu = qx * u[0] + qy * u[1] + qz * u[2]
        qv = qx * v[0] + qy * v[1] + qz * v[2]
        asp = np.maximum(aa + (ab - aa) * t, 0.3)
        qv = qv / asp
        r = np.maximum(ra + (rb - ra) * t, 0.6 * min(ra, rb))
        tt = br.T[kseg].astype(F32)
        qa = qx * tt[0] + qy * tt[1] + qz * tt[2]  # axial offset beyond a clamped end -> round caps
        d = np.sqrt(qu * qu + qv * qv + qa * qa) - r
        sl = tuple(slice(s0[i] - b0[i], s1[i] - b0[i]) for i in range(3))
        view = dmin[sl]
        m = d < view
        view[m] = d[m]
        QU[sl][m] = qu[m]
        QV[sl][m] = qv[m]
        SS[sl][m] = (br.S[kseg] + t * br.L[kseg])[m]
        RR[sl][m] = r[m]
    # displace inside a band twice as wide as the largest possible displacement, fading to zero at
    # its edges so the field stays continuous (the surface itself never reaches the fade zone)
    band = (dmin > -(2 * inn + 3 * vs)) & (dmin < 2 * out + 3 * vs)
    db = dmin.copy()
    df = dmin.copy()
    if band.any():
        dm = dmin[band]
        w = np.where(dm > 0, 1.0 - smoothstep(1.15 * out, 2 * out + 3 * vs, dm),
                     1.0 - smoothstep(1.15 * inn, 2 * inn + 3 * vs, -dm)).astype(F32)
        base, fine = br.displacement(QU[band], QV[band], SS[band], RR[band], noise)
        db[band] -= base * w
        df[band] -= (base + fine) * w
    sl = tuple(slice(b0[i], b1[i]) for i in range(3))
    if br.k <= 0:
        G.base[sl] = np.minimum(G.base[sl], db)
        G.full[sl] = np.minimum(G.full[sl], df)
    else:
        G.base[sl] = smin(G.base[sl], db, br.k)
        G.full[sl] = smin(G.full[sl], df, br.k)


def carve_hollow(G, sk, S, noise):
    """Smooth-subtract the hollow cavity. Returns a function cav(P) (SDF of the cavity, <0 inside)."""
    kind = S["hollow"]
    if kind is None:
        return None
    trunk_at = sk["trunk_at"]
    R1 = S["R1"]
    nz = noise[3]

    if kind == "split":
        top = 3.05
        rc0 = 0.45

        def cav(x, y, z):
            c = trunk_at(1.0)
            lx, ly = x - c[0], y - c[1]
            zz = np.maximum(z, 0.0)
            rc = rc0 * np.sqrt(np.clip(1.0 - (zz / top) ** 2, 0.0, 1.0)) * (1 + 0.25 * np.exp(-zz / 0.5))
            d_ch = np.sqrt(lx * lx + ly * ly) - rc
            w = 0.48 * np.clip(1.0 - (zz / (top + 0.05)) ** 1.7, 0.0, 1.0) ** 0.55 + 0.02
            d_sl = np.maximum(np.abs(lx + 0.06 * np.sin(z * 2.1)) - w, ly + 0.05)
            d_sl = np.maximum(d_sl, z - top)
            d_sl = np.maximum(d_sl, -(ly + 1.05))  # only through the trunk wall, not the roots out front
            d = np.minimum(d_ch, d_sl)
            return d + 0.035 * nz(x * 4.5, y * 4.5, z * 1.6)

        lo = trunk_at(1.0) + np.array([-1.6, -2.5, -0.6])
        hi = trunk_at(1.0) + np.array([1.6, 1.0, top + 0.6])
        kk = 0.05
    else:  # elder mouth: an opening on the front plus a chamber inside
        cz = 1.25
        c = trunk_at(cz)

        def cav(x, y, z):
            lx, ly, lz = x - c[0], y - c[1], z - cz
            # opening: ellipsoid poking out of the front surface
            e1 = np.sqrt((lx / 0.72) ** 2 + ((ly + 0.95) / 0.95) ** 2 + (lz / 1.15) ** 2)
            d1 = (e1 - 1.0) * 0.72
            e2 = np.sqrt((lx / 0.78) ** 2 + ((ly + 0.1) / 0.72) ** 2 + ((lz - 0.15) / 1.2) ** 2)
            d2 = (e2 - 1.0) * 0.72
            d = np.minimum(d1, d2)
            return d + 0.05 * nz(x * 3.0, y * 3.0, z * 1.8)

        lo = c + np.array([-2.0, -3.0, -1.8])
        hi = c + np.array([2.0, 1.6, 2.2])
        kk = 0.10
    i0, i1 = G.idx_range(lo, hi)
    xs, ys, zs = G.axes(i0, i1)
    X, Y, Z = np.meshgrid(xs, ys, zs, indexing="ij")
    dc = cav(X.ravel(), Y.ravel(), Z.ravel()).reshape(X.shape).astype(F32)
    sl = tuple(slice(i0[i], i1[i]) for i in range(3))
    G.base[sl] = smax(G.base[sl], -dc, kk)
    G.full[sl] = smax(G.full[sl], -dc, kk)
    return lambda P: cav(P[:, 0], P[:, 1], P[:, 2])


def sample(G, arr, P):
    g = (P - G.o) / G.vs
    i0 = np.clip(np.floor(g).astype(np.int64), 0, G.n - 2)
    f = np.clip(g - i0, 0.0, 1.0)
    x, y, z = i0[:, 0], i0[:, 1], i0[:, 2]
    fx, fy, fz = f[:, 0], f[:, 1], f[:, 2]
    c00 = arr[x, y, z] * (1 - fx) + arr[x + 1, y, z] * fx
    c10 = arr[x, y + 1, z] * (1 - fx) + arr[x + 1, y + 1, z] * fx
    c01 = arr[x, y, z + 1] * (1 - fx) + arr[x + 1, y, z + 1] * fx
    c11 = arr[x, y + 1, z + 1] * (1 - fx) + arr[x + 1, y + 1, z + 1] * fx
    return (c00 * (1 - fy) + c10 * fy) * (1 - fz) + (c01 * (1 - fy) + c11 * fy) * fz


def grad(G, arr, P):
    h = G.vs
    g = np.zeros_like(P)
    for a in range(3):
        e = np.zeros(3)
        e[a] = h
        g[:, a] = sample(G, arr, P + e) - sample(G, arr, P - e)
    return g / np.maximum(np.linalg.norm(g, axis=1, keepdims=True), 1e-9)


def mesh_from_sdf(G, arr):
    grid = vdb.FloatGrid(background=1.0)
    grid.copyFromArray(np.ascontiguousarray(np.clip(arr, -1.0, 1.0)), tolerance=0.0)
    pts, quads = grid.convertToQuads(isovalue=0.0)
    P = G.o + pts.astype(np.float64) * G.vs
    return P, quads.astype(np.int64)


def signed_volume(P, tris):
    a, b, c = P[tris[:, 0]], P[tris[:, 1]], P[tris[:, 2]]
    return float(np.einsum("ij,ij->i", a, np.cross(b, c)).sum() / 6.0)


def make_mesh(name, P, faces):
    me = bpy.data.meshes.new(name)
    me.from_pydata(P.tolist(), [], faces.tolist())
    me.update()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


# ----------------------------------------------------------------------------------------------
# low poly
# ----------------------------------------------------------------------------------------------
def mesh_arrays(me):
    nv = len(me.vertices)
    P = np.empty(nv * 3)
    me.vertices.foreach_get("co", P)
    me.calc_loop_triangles()
    nt = len(me.loop_triangles)
    T = np.empty(nt * 3, np.int64)
    me.loop_triangles.foreach_get("vertices", T)
    return P.reshape(-1, 3), T.reshape(-1, 3)


def cleanup_low(me):
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
    bmesh.ops.dissolve_degenerate(bm, edges=bm.edges, dist=1e-4)
    loose_e = [e for e in bm.edges if not e.link_faces]
    if loose_e:
        bmesh.ops.delete(bm, geom=loose_e, context="EDGES")
    loose_v = [v for v in bm.verts if not v.link_faces]
    if loose_v:
        bmesh.ops.delete(bm, geom=loose_v, context="VERTS")
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 3])
    # keep only the largest connected shell: decimation leaves tiny zero-volume flaps (two back-to-back
    # triangles) as separate islands
    bm.faces.ensure_lookup_table()
    seen, shells = set(), []
    for f0 in bm.faces:
        if f0.index in seen:
            continue
        stack, shell = [f0], []
        seen.add(f0.index)
        while stack:
            f = stack.pop()
            shell.append(f)
            for e in f.edges:
                for g in e.link_faces:
                    if g.index not in seen:
                        seen.add(g.index)
                        stack.append(g)
        shells.append(shell)
    shells.sort(key=len, reverse=True)
    junk = [f for sh in shells[1:] for f in sh]
    if junk:
        bmesh.ops.delete(bm, geom=junk, context="FACES")
    loose_v = [v for v in bm.verts if not v.link_faces]
    if loose_v:
        bmesh.ops.delete(bm, geom=loose_v, context="VERTS")
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    nonman = sum(1 for e in bm.edges if len(e.link_faces) != 2)
    bm.free()
    me.update()
    return nonman


def fold_score(bm, G):
    """Folded area: faces turned against the sculpt's outward direction (SDF gradient at the face
    centre).  (A ray / dihedral test was tried as well; it flagged legitimate faces and made it worse.)"""
    bm.normal_update()
    bm.faces.ensure_lookup_table()
    faces = list(bm.faces)
    cen = np.array([f.calc_center_median()[:] for f in faces])
    fno = np.array([f.normal[:] for f in faces])
    area = np.array([f.calc_area() for f in faces])
    bad = np.einsum("ij,ij->i", fno, grad(G, G.base, cen)) < -0.1
    return float(area[bad].sum()), [faces[k] for k in np.nonzero(bad)[0]], float(area.sum())


def fix_folds(me, G, rounds=6):
    """Repair folds left by decimation by rotating (flipping) edges - topology-safe, keeps the triangle
    count and the closed manifold.  A flip is kept only if it lowers the folded area."""
    fixed = 0
    for _ in range(rounds):
        bm = bmesh.new()
        bm.from_mesh(me)
        score, bad, _ = fold_score(bm, G)
        if not bad:
            bm.free()
            break
        bm.edges.index_update()
        cand = sorted({e.index for f in bad for e in f.edges})  # sorted: deterministic flip order
        bm.edges.ensure_lookup_table()
        cand = [bm.edges[i] for i in cand]
        changed = 0
        for e in cand:
            if not e.is_valid or len(e.link_faces) != 2:
                continue
            res = bmesh.ops.rotate_edges(bm, edges=[e], use_ccw=False)
            if not res["edges"]:
                continue
            sc, _, _ = fold_score(bm, G)
            if sc < score - 1e-6:
                score = sc
                changed += 1
            else:
                bmesh.ops.rotate_edges(bm, edges=res["edges"], use_ccw=True)
        bm.to_mesh(me)
        bm.free()
        fixed += changed
        if not changed:
            break
    me.update()
    return fixed


def count_folds(me, G):
    bm = bmesh.new()
    bm.from_mesh(me)
    sc, bad, tot = fold_score(bm, G)
    bm.free()
    return len(bad), round(sc / tot, 4)


def decimate_to(ob_base, budget, protect=None, pre_factor=12.0):
    tris0 = sum(len(p.vertices) - 2 for p in ob_base.data.polygons)
    mod = ob_base.modifiers.new("dec", "DECIMATE")
    if protect is not None and protect.max() > 0.01:
        # Blender adds edge_length * (2 - w1 - w2) * factor to the collapse cost; with the group
        # inverted, weight 1 = strongly protected, unassigned = plain quadric decimation
        protect = 0.8 * protect  # an inverted weight of exactly 0 would lock the vertex completely
        vg = ob_base.vertex_groups.get("protect") or ob_base.vertex_groups.new(name="protect")
        for w in np.unique(np.round(protect[protect > 0.01], 2)):
            ids = np.nonzero(np.round(protect, 2) == w)[0].tolist()
            vg.add(ids, float(w), "REPLACE")
        mod.vertex_group = "protect"
        mod.invert_vertex_group = True
        mod.vertex_group_factor = 12.0
    mod.decimate_type = "COLLAPSE"
    mod.use_collapse_triangulate = True
    dg = bpy.context.evaluated_depsgraph_get()
    # stage 1: plain quadric decimation to ~12x the budget (keeps the second stage well conditioned)
    pre = ob_base.modifiers.new("pre", "DECIMATE")
    pre.decimate_type = "COLLAPSE"
    pre.use_collapse_triangulate = True
    pre.ratio = min(1.0, budget * pre_factor / tris0)
    bpy.context.view_layer.objects.active = ob_base
    ob_base.modifiers.move(len(ob_base.modifiers) - 1, 0)
    dg.update()
    tris0 = int(budget * pre_factor)
    ratio = budget * 0.97 / tris0
    best = None
    for _ in range(14):
        mod.ratio = ratio
        dg.update()
        me = bpy.data.meshes.new_from_object(ob_base.evaluated_get(dg))
        nonman = cleanup_low(me)
        nt = len(me.polygons)
        if nt <= budget and (best is None or nt > best[1]):
            if best is not None:
                bpy.data.meshes.remove(best[0])
            best = (me, nt, nonman)
        else:
            bpy.data.meshes.remove(me)
        if best is not None and best[1] >= budget * 0.95:
            break
        ratio *= budget / nt * (0.985 if nt > budget else 0.995)
    ob_base.modifiers.remove(mod)
    ob_base.modifiers.remove(pre)
    return best[0], best[2]


# ----------------------------------------------------------------------------------------------
# bake
# ----------------------------------------------------------------------------------------------
def high_shading(G, PH, NH):
    """AO (SDF ray-march incl. ground plane) x furrow cavity, per high-poly vertex, in 0..1."""
    occ = np.zeros(len(PH))
    for h, w in ((0.03, 0.10), (0.07, 0.16), (0.15, 0.20), (0.3, 0.22), (0.6, 0.22), (1.1, 0.2), (1.9, 0.16)):
        Q = PH + NH * h
        d = np.minimum(sample(G, G.full, Q), np.maximum(Q[:, 2], -1.0) + 0.02)
        occ += w * np.clip((h - d) / h, 0.0, 1.0)
    ao = np.clip(1.0 - 0.9 * occ, 0.0, 1.0)
    cav = np.clip(-sample(G, G.base, PH), -0.5, 1.0)  # >0: point lies below the base surface (furrow)
    return ao, cav


def knot_dark(P, knots):
    """1 inside knot holes / eye sockets, 0 away from them."""
    k = np.zeros(len(P))
    for kp, wt, ws, depth in knots:
        d = P - kp
        q = (d[:, 0] ** 2 + d[:, 1] ** 2) / (1.4 * wt) ** 2 + d[:, 2] ** 2 / (1.4 * ws) ** 2
        k = np.maximum(k, np.exp(-q * 1.5) * min(1.0, depth / 0.25))
    return k


def bake_low(G, S, sk, PL, NL_geo, TL, PH, NH, ao, cav, cavfn, knots):
    kd = KDTree(len(PH))
    for i, p in enumerate(PH):
        kd.insert(p, i)
    kd.balance()
    # mean adjacent edge length per low vertex
    elen = np.zeros(len(PL))
    cnt = np.zeros(len(PL))
    for a, b in ((0, 1), (1, 2), (2, 0)):
        l = np.linalg.norm(PL[TL[:, a]] - PL[TL[:, b]], axis=1)
        np.add.at(elen, TL[:, a], l)
        np.add.at(cnt, TL[:, a], 1)
        np.add.at(elen, TL[:, b], l)
        np.add.at(cnt, TL[:, b], 1)
    elen /= np.maximum(cnt, 1)
    fur_ref = max(S["fur"], 1e-3)
    shade_h = ao * (1.0 - 0.6 * np.clip(cav / fur_ref, 0.0, 1.0)) * (1.0 + 0.10 * np.clip(-cav / fur_ref, 0, 1))
    N = np.zeros_like(PL)
    shade = np.zeros(len(PL))
    for i, p in enumerate(PL):
        rn = float(np.clip(0.45 * elen[i], 0.10, 0.7))
        hits = kd.find_range(p, rn)
        if len(hits) < 6:
            hits = kd.find_n(p, 12)
        idx = np.array([h[1] for h in hits])
        dist = np.array([h[2] for h in hits])
        w = np.exp(-(dist / (0.6 * rn)) ** 2) + 1e-6
        n = (NH[idx] * w[:, None]).sum(0)
        n = nrm(n)
        if np.dot(n, NL_geo[i]) < 0.35:
            n = nrm(n + NL_geo[i] * 1.2)
        N[i] = n
        rc = 0.06 + 0.04 * float(np.clip(elen[i] / 2.0, 0, 1))
        wc = np.exp(-(dist / rc) ** 2) + 1e-6
        shade[i] = (shade_h[idx] * wc).sum() / wc.sum()
    # concavity of the low mesh itself (valleys between flutes/roots darker, ridges lighter)
    nb = np.zeros_like(PL)
    nc = np.zeros(len(PL))
    for a, b in ((0, 1), (1, 2), (2, 0), (1, 0), (2, 1), (0, 2)):
        np.add.at(nb, TL[:, a], PL[TL[:, b]])
        np.add.at(nc, TL[:, a], 1)
    lap = nb / np.maximum(nc, 1)[:, None] - PL
    conc = np.einsum("ij,ij->i", lap, NL_geo) / np.maximum(elen, 1e-3)
    shade = shade * np.clip(1.0 - 1.4 * conc, 0.55, 1.12)
    shade = shade * (1.0 - 0.75 * knot_dark(PL, knots))
    mult = np.clip(0.25 + 0.75 * np.clip(shade, 0.0, 1.0) ** 1.1, 0.25, 1.0)
    bark = np.array(S["bark"])
    col = bark[None, :] * mult[:, None]
    # moss: lower 1-2 m on one side (+ tops of the roots), patchy
    pn = Perlin(S["seed"] + 7)
    maz = math.radians(S["moss_az"])
    mdir = np.array([math.cos(maz), math.sin(maz), 0.0])
    patch = pn(PL[:, 0] * 1.3, PL[:, 1] * 1.3, PL[:, 2] * 0.9)
    top = 1.0 + 1.0 * np.clip(0.5 + 0.9 * pn(PL[:, 0] * 0.4 + 9, PL[:, 1] * 0.4, 0.5), 0, 1)
    hfac = 1.0 - smoothstep(top * 0.45, top, PL[:, 2])
    side = np.clip((N[:, :2] @ mdir[:2] + 0.25) / 0.9, 0, 1)
    upf = np.clip((N[:, 2] - 0.2) / 0.6, 0, 1) * (1.0 - smoothstep(0.2, 1.0, PL[:, 2]))
    mw = np.clip((np.maximum(side, upf * 0.7) * hfac) * (0.75 + 0.6 * patch), 0, 0.85)
    mw *= (PL[:, 2] > -0.15)
    moss = np.array([0.20, 0.33, 0.28])
    col = col * (1 - mw[:, None]) + (moss[None, :] * mult[:, None] ** 0.8) * mw[:, None]
    # hollows: near-black inside
    if cavfn is not None:
        dc = cavfn(PL)
        inside = 1.0 - smoothstep(0.0, 0.16, dc)
        col = col * (1.0 - 0.9 * inside[:, None])
    return np.clip(col, 0, 1), N, mult, shade_h


# ----------------------------------------------------------------------------------------------
# game data: clumps / hangs
# ----------------------------------------------------------------------------------------------
def to_godot(P):
    P = np.asarray(P, np.float64).reshape(-1, 3)
    return np.column_stack([P[:, 0], P[:, 2], -P[:, 1]])


def leaf_data(S, sk, rng):
    clumps, hangs_c = [], []
    lo, hi = S["clump"]
    for b in sk["mains"] + sk["subs"]:
        tip = b.P[-1]
        clumps.append([*(tip + UP * 0.25), rng.uniform(lo, hi)])
    for b in sk["mains"]:
        k = int(rng.integers(2, 4))
        for t in np.sort(rng.uniform(0.55, 0.9, k)):
            _, p, r = b.point_at_s(t * b.S[-1])
            clumps.append([*(p + UP * (r + 0.3)), rng.uniform(lo, hi)])
        for t in np.linspace(0.3, 0.85, 6):
            i, p, r = b.point_at_s(t * b.S[-1])
            hangs_c.append((abs(b.T[i][2]), [*(p - UP * r * 0.95)]))
    clumps = [c for c in clumps if c[2] >= 3.5]
    hangs_c.sort(key=lambda h: h[0])
    n_h = int(np.clip(len(hangs_c) // 2, 6, 14))
    hangs = [h[1] for h in hangs_c[:n_h]]
    hangs = [h for h in hangs if h[2] > 2.0] or hangs
    return clumps, hangs


# ----------------------------------------------------------------------------------------------
# per tree
# ----------------------------------------------------------------------------------------------
def build_tree(S):
    t0 = time.time()
    rng = np.random.default_rng(S["seed"])
    noise = (Perlin(S["seed"] + 1), Perlin(S["seed"] + 2), Perlin(S["seed"] + 3), Perlin(S["seed"] + 4))
    sk = build_skeleton(S, rng, noise)
    lo = np.full(3, 1e9)
    hi = np.full(3, -1e9)
    for b in sk["branches"]:
        inn, out = b.max_disp()
        l, h = b.bounds(out + b.k + 0.2)
        lo, hi = np.minimum(lo, l), np.maximum(hi, h)
    lo[2] = max(lo[2], Z_CUT - 0.15)
    G = Grid(lo, hi, S["voxel"])
    print(f"[{S['name']}] grid {G.n.tolist()} = {np.prod(G.n) / 1e6:.1f} Mvox, branches {len(sk['branches'])}")
    for b in sk["branches"]:
        add_branch(G, b, noise)
    cavfn = carve_hollow(G, sk, S, noise)
    zs = (G.o[2] + np.arange(G.n[2]) * G.vs).astype(F32)
    cut = -(zs - Z_CUT)
    np.maximum(G.base, cut[None, None, :], out=G.base)
    np.maximum(G.full, cut[None, None, :], out=G.full)
    t1 = time.time()
    # meshes
    PH, QH = mesh_from_sdf(G, G.full)
    PB, QB = mesh_from_sdf(G, G.base)
    triH = np.concatenate([QH[:, [0, 1, 2]], QH[:, [0, 2, 3]]])
    if signed_volume(PH, triH) < 0:
        QH, QB = QH[:, ::-1], QB[:, ::-1]
    NH = grad(G, G.full, PH)
    print(f"[{S['name']}] sdf {t1 - t0:.1f}s, high {len(PH)} v / {2 * len(QH)} tris, base {len(PB)} v")
    ob_b = make_mesh(f"base_{S['name']}", PB, QB)
    protect = np.zeros(len(PB))
    if cavfn is not None:
        protect = np.maximum(protect, 1.0 - smoothstep(0.0, 0.35, cavfn(PB)))
    knots = []
    for (z, az, wt, ws, depth) in S["knots"]:
        c = sk["trunk_at"](z)
        a = math.radians(az)
        kp = c + np.array([math.cos(a), math.sin(a), 0.0]) * (float(np.interp(z, sk["zt"], sk["rt"])) - 0.4 * depth)
        knots.append((kp, wt, ws, depth))
        if depth >= 0.3:  # big knot holes (the elder's eyes)
            protect = np.maximum(protect, np.exp(-(np.linalg.norm(PB - kp, axis=1) / (2.2 * wt)) ** 2))
    # a few first-stage targets; keep the result with the least folded area after edge-flip repair
    best = None
    for pf in (12.0, 8.0, 16.0, 24.0, 6.0):
        me_try, nonman = decimate_to(ob_b, S["budget"], protect, pf)
        f0 = count_folds(me_try, G)
        nfix = fix_folds(me_try, G)
        nonman = cleanup_low(me_try)
        folds = count_folds(me_try, G)
        print(f"[{S['name']}] stage-1 x{pf:g}: folded faces before {f0}, edge flips {nfix}, after {folds}")
        if nonman == 0 and (best is None or folds[1] < best[1][1]):
            if best is not None:
                bpy.data.meshes.remove(best[0])
            best = (me_try, folds, nonman)
        else:
            bpy.data.meshes.remove(me_try)
        if best is not None and best[1][0] == 0:
            break
    me_low, folds, nonman = best
    bpy.data.objects.remove(ob_b)
    PL, TL = mesh_arrays(me_low)
    vol = signed_volume(PL, TL)
    # geometric vertex normals of the low mesh
    fn = np.cross(PL[TL[:, 1]] - PL[TL[:, 0]], PL[TL[:, 2]] - PL[TL[:, 0]])
    NLg = np.zeros_like(PL)
    for a in range(3):
        np.add.at(NLg, TL[:, a], fn)
    NLg /= np.maximum(np.linalg.norm(NLg, axis=1, keepdims=True), 1e-9)
    ao, cav = high_shading(G, PH, NH)
    col, NL, mult, shade_h = bake_low(G, S, sk, PL, NLg, TL, PH, NH, ao, cav, cavfn, knots)
    clumps, hangs = leaf_data(S, sk, rng)
    # trunk radius at 1.0 m: the trunk body itself (design radius + its sculpted displacement, median
    # over 72 directions); the buttress/claw roots are separate features and not counted here.
    # radius_buttress = median outer radius of the final sculpt at 1.0 m including the root flare.
    tr = sk["trunk"]
    s1 = 1.0 - tr.P[0, 2]
    _, _, r1 = tr.point_at_s(s1)
    th = np.linspace(-math.pi, math.pi, 72, endpoint=False)
    rr1 = np.full(72, r1)
    bd, fd = tr.displacement(np.cos(th) * rr1, np.sin(th) * rr1, np.full(72, s1), rr1, noise)
    radius = float(np.median(r1 + bd + fd))
    c1 = sk["trunk_at"](1.0)
    sel = np.abs(PH[:, 2] - 1.0) < 0.05
    rel = PH[sel, :2] - c1[:2]
    ang = ((np.arctan2(rel[:, 1], rel[:, 0]) + math.pi) / (2 * math.pi) * 72).astype(int) % 72
    outer = np.zeros(72)
    np.maximum.at(outer, ang, np.linalg.norm(rel, axis=1))
    radius_buttress = float(np.median(outer[outer > 0])) if sel.any() else radius
    base = sk["trunk_at"](1.6)
    # --- export (Godot: x, z, -y ; winding reversed -> clockwise seen from outside)
    Vg = to_godot(PL)
    Ng = to_godot(NL)
    Ng /= np.linalg.norm(Ng, axis=1, keepdims=True)
    Ig = TL[:, [0, 2, 1]]
    data = {
        "name": S["name"],
        "v": [round(float(x), 4) for x in Vg.ravel()],
        "n": [round(float(x), 4) for x in Ng.ravel()],
        "c": [round(float(x), 4) for x in col.ravel()],
        "i": [int(x) for x in Ig.ravel()],
        "clumps": [[round(float(x), 4) for x in (*to_godot(c[:3])[0], c[3])] for c in clumps],
        "hangs": [[round(float(x), 4) for x in to_godot(h)[0]] for h in hangs],
        "base": [round(float(base[0]), 4), round(float(-base[1]), 4)],
        "radius": round(radius, 4),
    }
    os.makedirs(OUT_DATA, exist_ok=True)
    path = os.path.join(OUT_DATA, f"trunk_{S['name']}.json")
    with open(path, "w") as fh:
        json.dump(data, fh, separators=(",", ":"))
    # low object for renders: vertex colours + transferred custom normals
    me_low.name = f"trunk_{S['name']}"
    attr = me_low.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
    rgba = np.column_stack([col, np.ones(len(col))]).astype(F32)
    attr.data.foreach_set("color", rgba.ravel())
    me_low.polygons.foreach_set("use_smooth", [True] * len(me_low.polygons))
    me_low.normals_split_custom_set_from_vertices([tuple(n) for n in NL])
    ob = bpy.data.objects.new(f"trunk_{S['name']}", me_low)
    bpy.context.scene.collection.objects.link(ob)
    meh = bpy.data.meshes.new(f"high_{S['name']}")
    meh.from_pydata(PH.tolist(), [], QH.tolist())
    hc = np.array(S["bark"])[None, :] * (0.25 + 0.75 * np.clip(shade_h * (1 - 0.75 * knot_dark(PH, knots)), 0, 1) ** 1.1)[:, None]
    if cavfn is not None:
        hc *= (1.0 - 0.9 * (1.0 - smoothstep(0.0, 0.16, cavfn(PH))))[:, None]
    ah = meh.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
    ah.data.foreach_set("color", np.column_stack([hc, np.ones(len(hc))]).astype(F32).ravel())
    meh.polygons.foreach_set("use_smooth", [True] * len(meh.polygons))
    obh = bpy.data.objects.new(f"high_{S['name']}", meh)
    bpy.context.scene.collection.objects.link(obh)
    stats = dict(name=S["name"], tris=len(TL), verts=len(PL), high_tris=2 * len(QH), nonmanifold=nonman,
                 volume=vol, bbox_min=Vg.min(0).round(2).tolist(), bbox_max=Vg.max(0).round(2).tolist(),
                 inverted=folds, radius=round(radius, 3), radius_buttress=round(radius_buttress, 3), clumps=len(clumps), hangs=len(hangs), secs=round(time.time() - t0, 1),
                 mult=[round(float(x), 2) for x in np.percentile(mult, [0, 10, 50, 90, 100])], path=path)
    print(f"[{S['name']}] {stats}")
    del G
    return ob, stats


# ----------------------------------------------------------------------------------------------
# renders
# ----------------------------------------------------------------------------------------------
TILE = 480


def setup_scene():
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 28
    sc.cycles.use_denoising = True
    sc.cycles.seed = 3
    sc.cycles.max_bounces = 3
    sc.render.resolution_x = TILE
    sc.render.resolution_y = TILE
    sc.render.resolution_percentage = 100
    sc.render.film_transparent = False
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"
    sc.render.image_settings.file_format = "PNG"
    world = bpy.data.worlds.new("dark")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.012, 0.014, 0.02, 1)
    world.node_tree.nodes["Background"].inputs[1].default_value = 1.0
    sc.world = world

    def sun(name, rot, energy, color, angle):
        ld = bpy.data.lights.new(name, "SUN")
        ld.energy = energy
        ld.color = color
        ld.angle = angle
        o = bpy.data.objects.new(name, ld)
        o.rotation_euler = [math.radians(a) for a in rot]
        sc.collection.objects.link(o)

    sun("key", (52, 0, -38), 3.2, (1.0, 0.96, 0.9), math.radians(18))
    sun("fill", (70, 0, 140), 0.55, (0.6, 0.7, 1.0), math.radians(40))
    sun("rim", (60, 0, 200), 1.2, (0.8, 0.85, 1.0), math.radians(10))
    gm = bpy.data.materials.new("ground")
    gm.use_nodes = True
    gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.03, 0.026, 0.024, 1)
    gm.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 1.0
    bpy.ops.mesh.primitive_plane_add(size=80, location=(0, 0, 0))
    ground = bpy.context.active_object
    ground.data.materials.append(gm)
    mat = bpy.data.materials.new("vcol")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    an = nt.nodes.new("ShaderNodeAttribute")
    an.attribute_name = "Col"
    nt.links.new(an.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.9
    bsdf.inputs["Specular IOR Level"].default_value = 0.15
    cam_d = bpy.data.cameras.new("cam")
    cam = bpy.data.objects.new("cam", cam_d)
    sc.collection.objects.link(cam)
    sc.camera = cam
    return mat, cam


def look(cam, loc, target):
    cam.location = Vector(loc)
    cam.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()


def render_tree(ob, mat, cam, tiles_dir):
    sc = bpy.context.scene
    for o in sc.objects:
        if o.name.startswith("trunk_") or o.name.startswith("high_"):
            o.hide_render = o is not ob
    if not ob.data.materials:
        ob.data.materials.append(mat)
    P = np.array([v.co[:] for v in ob.data.vertices])
    lo, hi = P.min(0), P.max(0)
    ctr = (lo + hi) / 2
    paths = []
    views = [("front", -90, 6), ("side", 0, 6), ("back", 90, 6), ("q34", -135, 18)]
    cd = cam.data
    cd.type = "ORTHO"
    ext = 0
    for _, az, el in views:
        a, e = math.radians(az), math.radians(el)
        fwd = -np.array([math.cos(e) * math.cos(a), math.cos(e) * math.sin(a), math.sin(e)])
        right = nrm(np.cross(fwd, UP))
        upv = np.cross(right, fwd)
        q = P - ctr
        ext = max(ext, np.ptp(q @ right), np.ptp(q @ upv))
    cd.ortho_scale = ext * 1.08
    cd.clip_end = 200
    for name, az, el in views:
        a, e = math.radians(az), math.radians(el)
        d = np.array([math.cos(e) * math.cos(a), math.cos(e) * math.sin(a), math.sin(e)])
        look(cam, ctr + d * 60, ctr)
        path = os.path.join(tiles_dir, f"{ob.name}_{name}.png")
        sc.render.filepath = path
        bpy.ops.render.render(write_still=True)
        paths.append(path)
    # close-up of the root base / hollow (perspective, from the front)
    cd.type = "PERSP"
    cd.lens = 28
    rad = (hi[0] - lo[0]) * 0.0 + max(1.2, np.percentile(np.linalg.norm(P[P[:, 2] < 1.0, :2], axis=1), 80))
    if "elder" in ob.name:
        look(cam, (0.5, -8.8, 2.4), (0, 0, 1.8))
    else:
        look(cam, (rad * 0.55 + 1.0, -(rad * 1.25 + 2.6), 1.9), (0, 0, 0.75))
    path = os.path.join(tiles_dir, f"{ob.name}_closeup.png")
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    paths.append(path)
    # same close-up and the 3/4 view of the HIGH sculpt (review only)
    high = bpy.data.objects.get(ob.name.replace("trunk_", "high_"))
    if high is not None:
        if not high.data.materials:
            high.data.materials.append(mat)
        ob.hide_render, high.hide_render = True, False
        path = os.path.join(tiles_dir, f"{ob.name}_closeup_high.png")
        sc.render.filepath = path
        bpy.ops.render.render(write_still=True)
        paths.append(path)
        cd.type = "ORTHO"
        name, az, el = views[3]
        a, e = math.radians(az), math.radians(el)
        d = np.array([math.cos(e) * math.cos(a), math.cos(e) * math.sin(a), math.sin(e)])
        look(cam, ctr + d * 60, ctr)
        path = os.path.join(tiles_dir, f"{ob.name}_q34_high.png")
        sc.render.filepath = path
        bpy.ops.render.render(write_still=True)
        paths.append(path)
        ob.hide_render, high.hide_render = False, True
    return paths


def load_px(path):
    img = bpy.data.images.load(path)
    w, h = img.size
    a = np.empty(w * h * 4, F32)
    img.pixels.foreach_get(a)
    bpy.data.images.remove(img)
    return a.reshape(h, w, 4)


def save_px(arr, path):
    h, w = arr.shape[:2]
    img = bpy.data.images.new(os.path.basename(path), w, h, alpha=False)
    img.pixels.foreach_set(arr.astype(F32).ravel())
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)


def compose(rows, path):
    """rows: list of lists of image paths (top row first)."""
    imgs = [[load_px(p) for p in r] for r in rows]
    cols = max(len(r) for r in imgs)
    H = TILE * len(imgs)
    W = TILE * cols
    out = np.zeros((H, W, 4), F32)
    out[..., 3] = 1
    for ri, r in enumerate(imgs):
        y0 = H - (ri + 1) * TILE  # blender pixel rows are bottom-up
        for ci, im in enumerate(r):
            out[y0:y0 + TILE, ci * TILE:(ci + 1) * TILE] = im
            out[y0:y0 + TILE, ci * TILE:ci * TILE + 1, :3] = 0.25
        out[y0:y0 + 1, :, :3] = 0.25
    save_px(out, path)


# ----------------------------------------------------------------------------------------------
def main():
    t_start = time.time()
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    names = argv or [t["name"] for t in TREES]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    os.makedirs(OUT_REN, exist_ok=True)
    tiles_dir = os.path.join(OUT_REN, "tiles")
    os.makedirs(tiles_dir, exist_ok=True)
    built, all_stats = [], []
    for S in TREES:
        if S["name"] in names:
            ob, st = build_tree(S)
            built.append(ob)
            all_stats.append(st)
    t_build = time.time() - t_start
    mat, cam = setup_scene()
    rows = []
    for ob in built:
        paths = render_tree(ob, mat, cam, tiles_dir)
        compose([paths[:4]], os.path.join(OUT_REN, f"{ob.name}_turntable.png"))
        compose([[paths[4]]], os.path.join(OUT_REN, f"{ob.name}_closeup.png"))
        if len(paths) > 5:
            compose([[paths[3], paths[6], paths[4], paths[5]]], os.path.join(OUT_REN, f"{ob.name}_low_vs_high.png"))
        rows.append(paths[:5])
    compose(rows, os.path.join(OUT_REN, "sheet.png" if len(built) == len(TREES) else "sheet_partial.png"))
    print("STATS", json.dumps(all_stats))
    print(f"DONE build {t_build:.1f}s total {time.time() - t_start:.1f}s")


main()
