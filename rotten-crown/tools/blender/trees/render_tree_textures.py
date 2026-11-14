"""Tree texture source assets (leaf clumps + gnarled bark), deterministic.

Run:  $BL -b -P tools/blender/trees/render_tree_textures.py   (BL=$(tools/setup_blender.sh))
Writes to assets/textures/forest_src/ :
  leaf_mass_{a,b,c,d}.png / _n.png   128x128 RGBA (hard alpha, colour bled into transparent texels)
  bark_gnarled.png / _n.png          256x256 RGB, tileable (procedural displacement, numpy)
  sheet.png                          contact sheet on mid-grey / dark blue
Leaves are real 3D geometry (folded, curled leaf meshes on forking twigs) rendered with an
orthographic camera in Cycles. Shading (depth layering + ambient-occlusion-like falloff + soft top
light) is baked analytically into vertex colours and shown with an emission shader, so the output
has no directional light or colour cast. Normal maps come from the same geometry (view frame).
"""
import math
import os
import random
import struct
import sys
import time
import zlib

import bpy
import numpy as np
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "..", "..", "assets", "textures", "forest_src"))
RENDER_PX = 512
TILE = 128
CAM_SCALE = 2.7  # world units across the tile


# ---------------------------------------------------------------- png io
def write_png(path, arr):
    arr = np.ascontiguousarray(arr.astype(np.uint8))
    h, w, c = arr.shape
    ct = {3: 2, 4: 6}[c]
    raw = b"".join(b"\x00" + arr[y].tobytes() for y in range(h))

    def chunk(t, d):
        b = t + d
        return struct.pack(">I", len(d)) + b + struct.pack(">I", zlib.crc32(b) & 0xFFFFFFFF)

    data = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, ct, 0, 0, 0))
    data += chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(data)


def read_render(path):
    """Raw encoded float RGBA, top-down, straight alpha."""
    img = bpy.data.images.load(path)
    img.colorspace_settings.name = "Non-Color"
    img.alpha_mode = "CHANNEL_PACKED"
    w, h = img.size
    a = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(a)
    bpy.data.images.remove(img)
    return a.reshape(h, w, 4)[::-1].copy()


# ---------------------------------------------------------------- vec helpers
def norm(v):
    l = math.sqrt(v[0] ** 2 + v[1] ** 2 + v[2] ** 2) or 1.0
    return (v[0] / l, v[1] / l, v[2] / l)


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def add(a, b, s=1.0):
    return (a[0] + b[0] * s, a[1] + b[1] * s, a[2] + b[2] * s)


def smooth(a, b, x):
    t = min(1.0, max(0.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


# ---------------------------------------------------------------- shape volumes
class Shape:
    """f(p) <= 1 inside. droop = gravity weight for leaf axes. Coordinates: x right, z up, y depth (-y = viewer)."""

    def __init__(self, kind, rng):
        self.kind = kind
        self.ph = [rng.uniform(0, 6.28) for _ in range(6)]
        self.amp = {"a": 0.10, "b": 0.07, "c": 0.16, "d": 0.08}[kind]

    def edge_noise(self, ang):
        p = self.ph
        return 1 + self.amp * (math.sin(3 * ang + p[0]) * 0.6 + math.sin(5 * ang + p[1]) * 0.5 + math.sin(9 * ang + p[2]) * 0.4)

    def f(self, p):
        x, y, z = p[0] / 0.91, p[1], p[2] / 0.91
        k = self.kind
        if k == "a":
            ang = math.atan2(z, x)
            n = self.edge_noise(ang)
            return ((abs(x) / (1.08 * n)) ** 3.8 + (abs(z) / (1.0 * n)) ** 3.8) + (abs(y) / 0.6) ** 2
        if k == "b":
            zc = 0.12 - 0.5 * (x / 1.15) ** 2
            hw = 0.74 * (1 - min(1.0, abs(x) / 1.28) ** 2.5) ** 0.5 + 0.12
            hw *= 1 + 0.12 * math.sin(4 * x + self.ph[0]) + 0.08 * math.sin(9 * x + self.ph[1])
            return max(abs(z - zc) / hw, (abs(x) / 1.2) ** 4) ** 1.0 + (abs(y) / 0.55) ** 2 * 0.8
        if k == "c":
            ang = math.atan2(z, x)
            n = self.edge_noise(ang)
            return ((abs(x) / (1.05 * n)) ** 3.2 + (abs(z) / (0.98 * n)) ** 3.2) + (abs(y) / 0.6) ** 2
        # d: curtain, wide at top, tapering down
        top = 0.85 + 0.07 * math.sin(5 * x + self.ph[0]) + 0.05 * math.sin(11 * x + self.ph[1])
        t = (top - z) / 2.0
        if t < 0:
            return 2.0 + (-t) * 4
        hw = 1.18 * (1 - 0.45 * t)
        bottom_ragged = 1 + 0.05 * math.sin(7 * x + self.ph[2])
        return max((abs(x) / hw) ** 3.0, t ** 3.0 * bottom_ragged) + (abs(y) / 0.5) ** 2


# ---------------------------------------------------------------- scene geometry builders
class MeshBuilder:
    def __init__(self):
        self.v, self.f, self.col, self.nrm = [], [], [], []

    def add(self, verts, faces, cols, nrms):
        o = len(self.v)
        self.v += verts
        self.col += cols
        self.nrm += nrms
        self.f += [tuple(i + o for i in fc) for fc in faces]


LEAF_T = 7


def make_leaf(mb, p, axis, nvec, L, W, curl, fold, shade, tint, center, rng):
    """Folded + curled leaf. Vertex colour = shade with midrib/tip gradient."""
    a = norm(axis)
    s = norm(cross(a, nvec))
    n = norm(cross(s, a))
    verts, cols, nrms = [], [], []
    for i in range(LEAF_T):
        t = i / (LEAF_T - 1)
        w = W * (math.sin(math.pi * (t ** 0.75)) ** 0.9) + 0.004
        # curl: leaf bends toward -n as it goes along its length
        ang = curl * t
        cp, sp = math.cos(ang), math.sin(ang)
        # centreline position approximated by integrating the bend
        cl_a = L * (math.sin(ang) / (curl + 1e-6)) if abs(curl) > 1e-4 else L * t
        cl_n = L * ((1 - math.cos(ang)) / (curl + 1e-6)) if abs(curl) > 1e-4 else 0.0
        base = add(add(p, a, cl_a), n, -cl_n)
        ta = add(tuple(a_ * cp for a_ in a), n, -sp)  # tangent
        nn = add(tuple(n_ * cp for n_ in n), a, sp)  # bent normal
        for j, sj in enumerate((-1, 0, 1)):
            lift = fold * w * (1 if sj != 0 else 0)
            pos = add(add(base, s, sj * w), nn, lift)
            # normal tilted by fold
            ft = fold * sj * 1.2
            vn = norm(add(tuple(c * math.cos(ft) for c in nn), s, -math.sin(ft) * (1 if sj else 0) * -1 if False else math.sin(ft)))
            if dot(vn, (0, -1, 0)) < 0:
                vn = (-vn[0], -vn[1], -vn[2])
            rad = norm((pos[0] - center[0], pos[1] - center[1], pos[2] - center[2]))
            vn = norm(add(tuple(c * 0.55 for c in vn), rad, 0.45))
            verts.append(pos)
            nrms.append((vn[0], vn[2], -vn[1]))  # world -> view frame (x right, y up, z to viewer)
            g = shade * (0.88 + 0.22 * t) * (1.0 if sj == 0 else 0.93 + 0.0 * rng.random())
            cols.append((g * tint[0], g * tint[1], g * tint[2]))
    faces = []
    for i in range(LEAF_T - 1):
        for j in range(2):
            a0, a1 = i * 3 + j, i * 3 + j + 1
            b0, b1 = (i + 1) * 3 + j, (i + 1) * 3 + j + 1
            faces.append((a0, a1, b1, b0))
    mb.add(verts, faces, cols, nrms)


def make_tube(mb, p0, p1, r0, r1, col, center):
    d = norm((p1[0] - p0[0], p1[1] - p0[1], p1[2] - p0[2]))
    ref = (0, 1, 0) if abs(d[1]) < 0.9 else (1, 0, 0)
    s = norm(cross(d, ref))
    u = norm(cross(s, d))
    verts, nrms, cols = [], [], []
    for p, r in ((p0, r0), (p1, r1)):
        for k in range(4):
            ang = k * math.pi / 2 + math.pi / 4
            off = add(tuple(s_ * math.cos(ang) for s_ in s), u, math.sin(ang))
            verts.append(add(p, off, r))
            vn = off
            if dot(vn, (0, -1, 0)) < 0 and False:
                vn = (-vn[0], -vn[1], -vn[2])
            nrms.append((vn[0], vn[2], -vn[1]))
            cols.append(col)
    faces = [(k, (k + 1) % 4, 4 + (k + 1) % 4, 4 + k) for k in range(4)]
    mb.add(verts, faces, cols, nrms)


def build_variant(kind, seed):
    rng = random.Random(seed)
    shape = Shape(kind, rng)
    mb = MeshBuilder()
    center = (0.0, 0.0, 0.0)
    cfg = {
        "a": dict(n=520, L=0.48, W=0.21, grav=0.10, twig_roots=7, twig_len=0.62, leaf_twig=0.45),
        "b": dict(n=500, L=0.48, W=0.21, grav=0.55, twig_roots=7, twig_len=0.6, leaf_twig=0.45),
        "c": dict(n=440, L=0.44, W=0.18, grav=0.15, twig_roots=11, twig_len=0.5, leaf_twig=0.35),
        "d": dict(n=480, L=0.56, W=0.18, grav=1.25, twig_roots=8, twig_len=0.55, leaf_twig=0.35),
    }[kind]
    twig_col = (0.20, 0.15, 0.11)

    leaves = []  # (pos, axis_hint)
    twig_nodes = []

    def fork(p, d, length, depth, r):
        segs = 3
        cur, cd = p, d
        for s_i in range(segs):
            step = length / segs
            nd = norm((cd[0] + rng.uniform(-0.35, 0.35), cd[1] * 0.5 + rng.uniform(-0.15, 0.15), cd[2] + rng.uniform(-0.35, 0.35) - 0.08 * cfg["grav"]))
            nxt = add(cur, nd, step)
            if shape.f(nxt) > 1.05:
                break
            r1 = r * 0.78
            make_tube(mb, cur, nxt, r, r1, tuple(c * (0.9 + 0.2 * rng.random()) for c in twig_col), center)
            twig_nodes.append((nxt, nd, depth))
            cur, cd, r = nxt, nd, r1
            if depth < 3 and s_i >= 1 and rng.random() < 0.9:
                ang = rng.choice((-1, 1)) * rng.uniform(0.5, 0.95)
                c2 = norm((cd[0] * math.cos(ang) - cd[2] * math.sin(ang), cd[1] + rng.uniform(-0.3, 0.3), cd[0] * math.sin(ang) + cd[2] * math.cos(ang)))
                fork(cur, c2, length * 0.62, depth + 1, r * 0.8)
        if depth < 3 and rng.random() < 0.85:
            ang = rng.choice((-1, 1)) * rng.uniform(0.4, 0.9)
            c2 = norm((cd[0] * math.cos(ang) - cd[2] * math.sin(ang), cd[1] * 0.5, cd[0] * math.sin(ang) + cd[2] * math.cos(ang)))
            fork(cur, c2, length * 0.7, depth + 1, r * 0.8)

    for i in range(cfg["twig_roots"]):
        ang = (i + rng.random() * 0.8) / cfg["twig_roots"] * math.tau
        d = norm((math.cos(ang), rng.uniform(-0.2, 0.2), math.sin(ang) * (0.9 if kind != "d" else 0.4) - (0.0 if kind != "d" else 0.35)))
        if kind == "d":
            d = norm((math.cos(ang) * 1.1, rng.uniform(-0.2, 0.2), 0.45 - abs(math.sin(ang)) * 0.9))
        start = (rng.uniform(-0.15, 0.15), rng.uniform(-0.1, 0.1), rng.uniform(-0.1, 0.25) if kind != "d" else rng.uniform(0.55, 0.9))
        fork(start, d, cfg["twig_len"] * rng.uniform(0.9, 1.3), 0, 0.022)

    tint = (0.80, 1.0, 0.82)
    leaf_list = []
    for (p, d, depth) in twig_nodes:
        if depth >= 1 and rng.random() < cfg["leaf_twig"] * 1.6:
            leaf_list.append((add(p, (rng.uniform(-.05, .05),) * 3, 1), d))
    # fill leaves by rejection sampling inside the volume
    tries = 0
    while len(leaf_list) < cfg["n"] and tries < 200000:
        tries += 1
        p = (rng.uniform(-1.3, 1.3), rng.uniform(-0.65, 0.65), rng.uniform(-1.25, 1.25))
        if shape.f(p) <= 1.0:
            leaf_list.append((p, None))
    leaf_list = leaf_list[: cfg["n"] + 40]

    for p, dhint in leaf_list:
        f = shape.f(p)
        r = min(1.0, max(0.0, f)) ** 0.5
        rad = norm((p[0] - center[0], (p[1] - center[1]) * 0.5, p[2] - center[2] + (0.0 if kind != "d" else 0.0)))
        if dhint is not None:
            base_axis = add(dhint, rad, 0.6)
        else:
            base_axis = add(rad, (rng.uniform(-1, 1), rng.uniform(-0.8, 0.8), rng.uniform(-1, 1)), 0.9)
        axis = (base_axis[0], base_axis[1] * 0.5, base_axis[2] - cfg["grav"] * 0.6)
        axis = norm(add(axis, (rng.uniform(-1, 1), rng.uniform(-0.5, 0.5), rng.uniform(-1, 1)), 0.45))
        nvec = norm((rng.uniform(-0.5, 0.5), -1.0, rng.uniform(-0.2, 0.7)))
        if abs(dot(axis, nvec)) > 0.95:
            nvec = (0, -1, 0.3)
        # shading: inner/back dark, rim + front lighter, soft top light
        depthn = (-p[1] + 0.6) / 1.2  # 1 = nearest viewer
        ao = 0.30 + 0.70 * smooth(0.15, 1.0, r)
        front = 0.75 + 0.25 * depthn
        top = 0.90 + 0.14 * max(-1, min(1, p[2] / 1.1))
        v = 0.10 + 0.34 * ao * front * top
        v *= rng.uniform(0.86, 1.14)
        v = min(0.45, max(0.10, v))
        L = cfg["L"] * rng.uniform(0.8, 1.2)
        W = cfg["W"] * rng.uniform(0.8, 1.2)
        make_leaf(mb, p, axis, nvec, L, W, rng.uniform(-0.6, 1.1), rng.uniform(0.25, 0.6), v, tint, center, rng)
    return mb, len(leaf_list)


# ---------------------------------------------------------------- blender scene
def to_object(mb, name):
    me = bpy.data.meshes.new(name)
    me.from_pydata(mb.v, [], mb.f)
    me.update()
    for nm, data in (("col", mb.col), ("nrm", mb.nrm)):
        att = me.color_attributes.new(name=nm, type="FLOAT_COLOR", domain="POINT")
        flat = []
        for c in data:
            if nm == "nrm":
                c = tuple(max(0.0, min(1.0, x * 0.5 + 0.5)) for x in norm(c))
            # emission is output through the Standard view transform (sRGB OETF): store linear so file value = c
            flat += [c[0] ** 2.2, c[1] ** 2.2, c[2] ** 2.2, 1.0]
        att.data.foreach_set("color", flat)
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def emission_material(attr):
    m = bpy.data.materials.new("m_" + attr)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    a = nt.nodes.new("ShaderNodeAttribute")
    a.attribute_name = attr
    e = nt.nodes.new("ShaderNodeEmission")
    o = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(a.outputs["Color"], e.inputs["Color"])
    nt.links.new(e.outputs["Emission"], o.inputs["Surface"])
    return m


def setup_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 12
    sc.cycles.use_denoising = False
    sc.cycles.seed = 7
    sc.cycles.max_bounces = 0
    sc.render.resolution_x = sc.render.resolution_y = RENDER_PX
    sc.render.film_transparent = True
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.render.image_settings.color_depth = "16"
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"
    sc.display_settings.display_device = "sRGB"
    cam = bpy.data.cameras.new("cam")
    cam.type = "ORTHO"
    cam.ortho_scale = CAM_SCALE
    co = bpy.data.objects.new("cam", cam)
    co.location = (0, -10, 0)
    co.rotation_euler = (math.pi / 2, 0, 0)
    sc.collection.objects.link(co)
    sc.camera = co
    return sc


def render(sc, ob, mat, path):
    ob.data.materials.clear()
    ob.data.materials.append(mat)
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    return read_render(path)


def bleed(rgb, mask, iters=12):
    rgb = rgb.copy()
    m = mask.copy()
    for _ in range(iters):
        if m.all():
            break
        acc = np.zeros_like(rgb)
        cnt = np.zeros(m.shape, dtype=np.float32)
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                if dy == 0 and dx == 0:
                    continue
                mm = np.roll(np.roll(m, dy, 0), dx, 1)
                acc += np.roll(np.roll(rgb, dy, 0), dx, 1) * mm[..., None]
                cnt += mm
        new = (~m) & (cnt > 0)
        rgb[new] = acc[new] / cnt[new][..., None]
        m = m | new
    return rgb


def downscale(img, is_normal=False):
    f = RENDER_PX // TILE
    h = TILE
    a = img[..., 3].reshape(h, f, h, f)
    cov = a.mean(axis=(1, 3))
    mask = cov >= 0.5
    w = img[..., 3:4]
    rgb = (img[..., :3] * w).reshape(h, f, h, f, 3).sum(axis=(1, 3)) / np.maximum(w.reshape(h, f, h, f, 1).sum(axis=(1, 3)), 1e-6)
    if is_normal:
        v = rgb * 2 - 1
        v /= np.maximum(np.linalg.norm(v, axis=-1, keepdims=True), 1e-6)
        rgb = v * 0.5 + 0.5
    rgb = bleed(rgb, mask)
    out = np.zeros((h, h, 4), dtype=np.float32)
    out[..., :3] = np.clip(rgb, 0, 1)
    out[..., 3] = mask
    return out, mask


# ---------------------------------------------------------------- bark
def periodic_noise(rs, n, sx, sy):
    """Tileable noise: white noise filtered in Fourier space with anisotropic gaussian (sx, sy in px)."""
    w = rs.standard_normal((n, n))
    fy = np.fft.fftfreq(n)[:, None]
    fx = np.fft.fftfreq(n)[None, :]
    filt = np.exp(-0.5 * ((fx * sx * 2 * np.pi) ** 2 + (fy * sy * 2 * np.pi) ** 2))
    r = np.real(np.fft.ifft2(np.fft.fft2(w) * filt))
    return (r - r.mean()) / (r.std() + 1e-9)


def wrap_sample(img, xs, ys):
    n = img.shape[0]
    x0 = np.floor(xs).astype(int)
    y0 = np.floor(ys).astype(int)
    fx = xs - x0
    fy = ys - y0
    x0 %= n
    y0 %= n
    x1 = (x0 + 1) % n
    y1 = (y0 + 1) % n
    return (img[y0, x0] * (1 - fx) * (1 - fy) + img[y0, x1] * fx * (1 - fy) + img[y1, x0] * (1 - fx) * fy + img[y1, x1] * fx * fy)


def make_bark(n=256):
    rs = np.random.RandomState(1234)
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float64)
    warp_x = periodic_noise(rs, n, 26, 60) * 9.0
    warp_y = periodic_noise(rs, n, 30, 30) * 5.0
    ridge_base = periodic_noise(rs, n, 3.2, 38)
    ridge_base2 = periodic_noise(rs, n, 6.5, 70)
    base = ridge_base * 0.7 + ridge_base2 * 0.55
    warped = wrap_sample(base, xx + warp_x, yy + warp_y)
    warped = (warped - warped.mean()) / warped.std()
    # ridged: valleys (cracks) on the zero crossings
    h = np.abs(warped)
    h = np.clip(h, 0, 2.2) ** 0.55
    h = h / h.max()
    # slab plateaus: low-freq modulation
    h *= 0.8 + 0.25 * periodic_noise(rs, n, 12, 50)
    # transversal cracks
    cr = periodic_noise(rs, n, 22, 2.2)
    cr = np.clip(cr - 1.35, 0, None)
    h -= cr * 0.28
    # knots
    for (kx, ky, rad) in ((60, 70, 20), (190, 170, 25), (110, 225, 15), (215, 30, 14)):
        for ox in (-n, 0, n):
            for oy in (-n, 0, n):
                dx = (xx - kx - ox) / 0.75
                dy = (yy - ky - oy) * 0.75
                r = np.sqrt(dx * dx + dy * dy)
                ring = np.exp(-((r - rad) / (rad * 0.35)) ** 2) * 0.55
                pit = np.exp(-(r / (rad * 0.5)) ** 2) * 0.65
                swirl = (0.5 + 0.5 * np.cos((r - rad) * 0.9)) * np.exp(-(r / (rad * 1.9)) ** 2) * 0.10
                h += ring - pit + swirl
    h += periodic_noise(rs, n, 1.2, 3.5) * 0.045
    h = (h - h.mean()) / h.std()
    v = np.clip(0.5 + h * 0.2, 0.0, 1.0)
    lo, hi = np.percentile(v, [1, 99])
    v = np.clip(0.5 + (v - 0.5) * 0.37 / max(hi - 0.5, 0.5 - lo), 0.0, 1.0)
    v = np.clip(0.15 + (v - v.min()) / (np.percentile(v, 99.5) - v.min()) * 0.75, 0, 0.9)
    v += 0.5 - v.mean()
    v = np.clip(v, 0.15, 0.9)
    # normal (tangent space, +Y up, image rows go down)
    hh = (v - 0.5) * 2.0
    dx = (np.roll(hh, -1, 1) - np.roll(hh, 1, 1)) * 0.5
    dy = (np.roll(hh, 1, 0) - np.roll(hh, -1, 0)) * 0.5
    s = 2.5
    nv = np.stack([-dx * s, -dy * s, np.ones_like(hh)], -1)
    nv /= np.linalg.norm(nv, axis=-1, keepdims=True)
    return v, nv * 0.5 + 0.5


# ---------------------------------------------------------------- sheet
def over(bg, rgba):
    a = rgba[..., 3:4]
    return rgba[..., :3] * a + bg * (1 - a)


def up(a, k):
    return np.repeat(np.repeat(a, k, 0), k, 1)


def main():
    t0 = time.time()
    os.makedirs(OUT, exist_ok=True)
    sc = setup_scene()
    mat_col = emission_material("col")
    mat_nrm = emission_material("nrm")
    tmp = os.path.join(OUT, "_tmp_render.png")
    tiles, ntiles = {}, {}
    for name, seed in (("a", 101), ("b", 202), ("c", 303), ("d", 404)):
        mb, cnt = build_variant(name, seed)
        ob = to_object(mb, "leaf_" + name)
        col = render(sc, ob, mat_col, tmp)
        nrm = render(sc, ob, mat_nrm, tmp)
        nrm[..., 3] = col[..., 3]
        c_out, mask = downscale(col)
        n_out, _ = downscale(nrm, True)
        n_out[..., 3] = c_out[..., 3]
        write_png(os.path.join(OUT, "leaf_mass_%s.png" % name), np.round(c_out * 255))
        write_png(os.path.join(OUT, "leaf_mass_%s_n.png" % name), np.round(n_out * 255))
        tiles[name], ntiles[name] = c_out, n_out
        lum = c_out[..., :3].mean(-1)[mask]
        edge = max(mask[0].mean(), mask[-1].mean(), mask[:, 0].mean(), mask[:, -1].mean())
        print("edge_alpha=%.2f" % edge)
        print("leaf_mass_%s: leaves=%d tris=%d coverage=%.1f%% lum[%.2f..%.2f] mean %.2f" % (name, cnt, len(mb.f) * 2, mask.mean() * 100, lum.min(), lum.max(), lum.mean()))
        bpy.data.objects.remove(ob)
    os.remove(tmp)

    v, nv = make_bark()
    write_png(os.path.join(OUT, "bark_gnarled.png"), np.round(np.repeat(v[..., None], 3, -1) * 255))
    write_png(os.path.join(OUT, "bark_gnarled_n.png"), np.round(nv * 255))
    print("bark mean %.3f min %.2f max %.2f" % (v.mean(), v.min(), v.max()))

    # contact sheet
    k = 2
    grey = np.array([0.5, 0.5, 0.5])
    blue = np.array([0.04, 0.07, 0.16])
    W = 4 * TILE * k
    rows = []
    for bgc in (grey, blue):
        for src in (tiles, ntiles):
            rows.append(np.concatenate([up(over(bgc, src[n]), k) for n in "abcd"], axis=1))
    bark_rgb = np.repeat(v[..., None], 3, -1)
    bt = np.tile(bark_rgb, (2, 2, 1))
    bn = np.tile(nv, (2, 2, 1))
    brow = np.concatenate([bt, bn], axis=1)
    brow = np.pad(brow, ((0, 0), (0, W - brow.shape[1]), (0, 0)), constant_values=0.2)
    sheet = np.concatenate(rows + [brow], axis=0)
    write_png(os.path.join(OUT, "sheet.png"), np.round(np.clip(sheet, 0, 1) * 255))
    print("total time %.1fs" % (time.time() - t0))


main()
