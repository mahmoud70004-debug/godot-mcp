"""Aether trees (prototype): a giant fluted redwood trunk with buttress roots and moss, a conifer (trunk,
whorled drooping branches, real needle fronds) and a frond close-up, rendered for review.

Run:  $BL -b -P tools/blender/trees/aether_trees.py -- [trunk] [fir] [frond]
Writes build/aether/*.png (one image per view). Everything is procedural numpy geometry (Z up).
Moonlight look: dark cobalt world, a strong blue rim 'moon' from behind-left, a dim cool fill.
"""
import math
import os
import sys
import time

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "..", "..", "build", "aether"))
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(11)


# ----------------------------------------------------------------------------- noise
class Noise:
    def __init__(self, seed, n=64):
        self.n = n
        self.g = np.random.default_rng(seed).random((n, n, n))

    def __call__(self, x, y, z):
        n = self.n
        x, y, z = np.asarray(x, float), np.asarray(y, float), np.asarray(z, float)
        i, j, k = np.floor(x).astype(int), np.floor(y).astype(int), np.floor(z).astype(int)
        fx, fy, fz = x - i, y - j, z - k
        fx, fy, fz = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy), fz * fz * (3 - 2 * fz)
        out = 0.0
        for dx in (0, 1):
            for dy in (0, 1):
                for dz in (0, 1):
                    w = (fx if dx else 1 - fx) * (fy if dy else 1 - fy) * (fz if dz else 1 - fz)
                    out = out + w * self.g[(i + dx) % n, (j + dy) % n, (k + dz) % n]
        return out


N1, N2, N3 = Noise(1), Noise(2), Noise(3)


def ridged(v):
    return 1.0 - np.abs(2.0 * v - 1.0)


def smooth(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3 - 2 * t)


# ----------------------------------------------------------------------------- mesh helpers
def make_object(name, V, F, cols=None, smooth_shade=True):
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in V], [], [tuple(f) for f in F])
    me.update()
    if cols is not None:
        ca = me.color_attributes.new(name="Col", type="FLOAT_COLOR", domain="POINT")
        flat = np.concatenate([cols, np.ones((len(cols), 1))], axis=1).ravel()
        ca.data.foreach_set("color", flat)
    if smooth_shade:
        for p in me.polygons:
            p.use_smooth = True
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def grid_faces(ny, nt):
    F = []
    for j in range(ny - 1):
        for i in range(nt):
            a = j * nt + i
            b = j * nt + (i + 1) % nt
            F.append((a, b, b + nt, a + nt))
    return F


# ----------------------------------------------------------------------------- redwood trunk
def trunk_mesh(H=30.0, r_mid=1.35, r_top=0.32, roots=8, seed=5, nt=340, ny=1500, flute=1.0, detail=1.0, moss=True):
    r = np.random.default_rng(seed)
    t = np.linspace(0, 1, ny)
    y = -0.7 + (H + 0.7) * t ** 1.15
    th = np.linspace(0, 2 * np.pi, nt, endpoint=False)
    TH, Y = np.meshgrid(th, y)
    base_r = r_top + (r_mid - r_top) * np.clip(1 - Y / H, 0, 1) ** 0.5
    # Broad vertical flutes (ridged noise stretched along the trunk) and finer bark plates.
    cx, sz = np.cos(TH), np.sin(TH)
    f1 = ridged(N1(cx * 4.2 + 8, Y * 0.05, sz * 4.2 + 8))
    f2 = ridged(N2(cx * 11.0 + 3, Y * 0.09, sz * 11.0 + 3))
    f3 = N3(cx * 18 + 5, Y * 0.55, sz * 18 + 5)
    amp = (0.34 - 0.12 * Y / H) * flute
    fl = (f1 * 0.62 + f2 * 0.38 - 0.5) * amp + (f3 - 0.5) * 0.09 * detail
    # Bark: furrows that wander (domain-warped), break into plates and fibres, in metres (not relative to the radius).
    wy = N3(cx * 2.5 + 40, Y * 0.35, sz * 2.5 + 40) * 3.0
    wx = N1(cx * 2.5 + 60, Y * 0.35, sz * 2.5 + 60) * 3.0
    crack = smooth(0.52, 0.88, ridged(N2(cx * 21 + wx, Y * 0.75 + wy * 0.6, sz * 21 + wx)))
    crack2 = smooth(0.55, 0.9, ridged(N3(cx * 44 + wy, Y * 1.9 + wx * 0.5, sz * 44 + wy)))
    plates = ridged(N1(cx * 15 + wx, Y * 1.5 + wy, sz * 15 + wx))
    fibre = N3(cx * 95 + 7, Y * 3.5, sz * 95 + 7) - 0.5
    fl = (f1 * 0.62 + f2 * 0.38 - 0.5) * amp
    fine = (-crack * 0.12 * detail - crack2 * 0.045 * detail + (plates - 0.5) * 0.1 * detail + fibre * 0.03 * detail)
    # Buttress roots: lobes at random angles, strongest at the ground and gone by ~5 m.
    ang = np.sort(r.random(roots)) * 2 * np.pi
    wid = 0.22 + r.random(roots) * 0.16
    amp_r = 0.9 + r.random(roots) * 0.9
    lobes = np.zeros_like(TH)
    for a, w, k in zip(ang, wid, amp_r):
        d = np.angle(np.exp(1j * (TH - a)))
        lobes += k * np.exp(-(d / w) ** 2)
    flare = np.exp(-np.clip(Y, 0, None) / 1.5) * (Y < 6)
    ground = smooth(0.8, -0.6, Y)
    rad = base_r * (1 + fl) + fine + base_r * (0.12 + 0.5 * lobes) * flare * (1 - 0.5 * smooth(2.0, 6.0, Y)) + base_r * 0.45 * lobes * ground
    # Gentle lean/bend and a slight spiral.
    X = rad * np.cos(TH + Y * 0.004) + 0.55 * np.sin(Y * 0.045)
    Yy = rad * np.sin(TH + Y * 0.004) + 0.3 * np.sin(Y * 0.03 + 1.0)
    ridge = np.clip((f1 * 0.6 + f2 * 0.4) * 0.8 + (plates - 0.5) * 0.5 - crack * 0.6 - crack2 * 0.3 + 0.1, 0, 1)
    shade = 0.3 + 1.2 * ridge
    col = np.stack([0.19 * shade, 0.135 * shade, 0.11 * shade], -1)
    if moss:
        # Moss: clumpy cushions that stand off the bark and cover it in patches, lit-green on their crowns.
        w = moss_weights(None, TH, Y).reshape(TH.shape)
        clump = N1(cx * 38 + 9, Y * 2.6 + 9, sz * 38 + 9) * 0.55 + N2(cx * 85, Y * 6.0, sz * 85) * 0.45
        lump = np.clip(clump * 1.4 - 0.25, 0, 1)
        fur = N3(cx * 150 + 3, Y * 14, sz * 150 + 3)
        off = w * (0.07 + 0.22 * lump + 0.04 * fur)
        rad = rad + off
        base_g = np.array([0.006, 0.014, 0.01])
        crown = np.array([0.04, 0.1, 0.055])
        mc = base_g[None, None, :] + (crown - base_g)[None, None, :] * lump[..., None]
        wm = np.clip(w * 1.6, 0, 1)[..., None]
        col = col * (1 - wm) + mc * wm
    X = rad * np.cos(TH + Y * 0.004) + 0.55 * np.sin(Y * 0.045)
    Yy = rad * np.sin(TH + Y * 0.004) + 0.3 * np.sin(Y * 0.03 + 1.0)
    V = np.stack([X, Yy, Y], -1).reshape(-1, 3)
    return V, grid_faces(ny, nt), col.reshape(-1, 3), (TH, Y, rad, ridge), nt, ny


def moss_weights(V, TH, Y, lobes_hint=None):
    """Moss lives low on the trunk, in patches, thickest on the roots' upper side and on the north face."""
    th, y = TH, Y
    patch = N1(np.cos(th) * 2.0 + 20, y * 0.35, np.sin(th) * 2.0 + 20)
    patch2 = N2(np.cos(th) * 6.0, y * 0.9, np.sin(th) * 6.0)
    low = 1 - smooth(1.0, 11.0, y)
    north = 0.85 + 0.15 * np.sin(th)
    w = np.clip((patch * 0.7 + patch2 * 0.45 - 0.3) * 3.0, 0, 1) * (0.2 + 0.8 * low) * north
    w = np.clip(w + 0.3 * N3(np.cos(th) * 3 + 70, y * 1.5, np.sin(th) * 3 + 70) * smooth(2.5, 0.0, y), 0, 1)
    w = np.where(y > 18, w * 0.2, w)
    return w.ravel()


# ----------------------------------------------------------------------------- frond (needle spray)
def frond_mesh(pairs=64, length=1.0, seed=2):
    r = np.random.default_rng(seed)
    V, F, C = [], [], []

    def tri(a, b, c, ca, cb, cc):
        n = len(V)
        V.extend([a, b, c])
        C.extend([ca, cb, cc])
        F.append((n, n + 1, n + 2))

    dark = np.array([0.035, 0.07, 0.055])
    pale = np.array([0.5, 0.78, 0.7])
    for k in range(pairs):
        s = (k + 0.5) / pairs * length
        t = s / length
        lh = (0.05 + 0.17 * np.sin(np.pi * (0.06 + 0.94 * t)) ** 0.7) * (1.0 - 0.25 * t)
        for side in (1, -1):
            for rep in (0, 1):
                ang = np.deg2rad(52 + r.random() * 14)
                sl = lh * (0.85 + 0.3 * r.random())
                dz = -0.03 - 0.06 * r.random()
                base = np.array([s + rep * 0.006, 0, 0])
                tip = base + np.array([np.cos(ang) * sl, side * np.sin(ang) * sl, dz * sl * 4])
                w = np.array([0.0, 0.0, 0.007])
                tc = dark + (pale - dark) * (0.35 + 0.65 * t)
                tri(base - w, base + w, tip, dark * 0.8, dark * 0.8, tc)
    # Stem
    n = len(V)
    V.extend([np.array([0, 0, -0.004]), np.array([0, 0, 0.004]), np.array([length, 0, 0.003]), np.array([length, 0, -0.003])])
    C.extend([dark * 0.6] * 4)
    F.append((n, n + 1, n + 2, n + 3))
    return np.array(V), F, np.array(C)


# ----------------------------------------------------------------------------- scene
def setup_scene(res=(1000, 1400)):
    sc = bpy.context.scene
    for o in list(bpy.data.objects):
        if o.name in ("Cube", "Light", "Camera"):
            bpy.data.objects.remove(o)
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 40
    sc.cycles.use_denoising = True
    sc.cycles.max_bounces = 4
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.resolution_percentage = 100
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"
    sc.view_settings.exposure = 0.4
    sc.render.image_settings.file_format = "PNG"
    world = bpy.data.worlds.new("night")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.01, 0.025, 0.12, 1)
    bg.inputs[1].default_value = 0.8
    sc.world = world

    def sun(name, frm, energy, color, angle):
        ld = bpy.data.lights.new(name, "SUN")
        ld.energy, ld.color, ld.angle = energy, color, math.radians(angle)
        o = bpy.data.objects.new(name, ld)
        d = (-Vector(frm)).normalized()
        o.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
        sc.collection.objects.link(o)
        return o

    # The moon stands behind-left of the camera's subject (camera looks along +y): a strong cold rim.
    sun("moon", (-22, 26, 20), 9.0, (0.4, 0.58, 1.0), 3)
    sun("fill", (12, -30, 14), 1.5, (0.3, 0.45, 1.0), 25)
    gm = bpy.data.materials.new("ground")
    gm.use_nodes = True
    gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.02, 0.025, 0.03, 1)
    gm.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 1.0
    bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, 0))
    g = bpy.context.active_object
    g.data.materials.append(gm)
    cam_d = bpy.data.cameras.new("cam")
    cam = bpy.data.objects.new("cam", cam_d)
    sc.collection.objects.link(cam)
    sc.camera = cam
    return cam


def vcol_material(name, rough=0.85, spec=0.2, emit=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    a = nt.nodes.new("ShaderNodeAttribute")
    a.attribute_name = "Col"
    nt.links.new(a.outputs["Color"], b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = rough
    b.inputs["Specular IOR Level"].default_value = spec
    return m


def look(cam, loc, target, lens=40):
    cam.location = Vector(loc)
    cam.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    cam.data.lens = lens
    cam.data.clip_end = 500


def render(name):
    sc = bpy.context.scene
    sc.render.filepath = os.path.join(OUT, name + ".png")
    t0 = time.time()
    bpy.ops.render.render(write_still=True)
    print("rendered", name, round(time.time() - t0), "s")


def add_moss(ob, weights, count=70000, length=0.075):
    vg = ob.vertex_groups.new(name="moss")
    idx = np.nonzero(weights > 0.02)[0]
    for w in np.unique(np.round(weights[idx], 1)):
        sel = idx[np.round(weights[idx], 1) == w]
        vg.add([int(i) for i in sel], float(w), "REPLACE")
    mm = bpy.data.materials.new("moss")
    mm.use_nodes = True
    b = mm.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (0.05, 0.13, 0.07, 1)
    b.inputs["Roughness"].default_value = 0.8
    ob.data.materials.append(mm)
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    bpy.ops.object.particle_system_add()
    ps = ob.particle_systems[-1]
    st = ps.settings
    st.type = "HAIR"
    st.count = count
    st.hair_length = length
    st.use_advanced_hair = False
    ps.vertex_group_density = "moss"
    st.child_type = "INTERPOLATED"
    st.child_percent = 1
    st.rendered_child_count = 6
    st.child_length = 0.9
    st.child_length_threshold = 0.3
    st.child_radius = 0.04
    st.material = len(ob.data.materials)
    st.hair_step = 3
    ob.select_set(False)


def do_trunk():
    t0 = time.time()
    V, F, col, _, nt, ny = trunk_mesh()
    ob = make_object("trunk", V, F, col)
    ob.data.materials.append(vcol_material("bark", 0.92, 0.12))
    cam = setup_scene((900, 1500))
    bpy.context.scene.cycles.samples = 40
    print("trunk built", round(time.time() - t0), "s", len(V), "verts")
    look(cam, (-5, -34, 13.5), (0.0, 0.0, 13.0), 38)
    render("trunk_full")
    bpy.context.scene.render.resolution_x, bpy.context.scene.render.resolution_y = 1400, 900
    look(cam, (-5.5, -7.0, 2.6), (0.0, 0.0, 1.7), 30)
    render("trunk_base_moss")
    look(cam, (-2.4, -5.0, 8.0), (0.0, 0.0, 7.6), 36)
    render("trunk_bark_close")


_FROND = {}


def get_frond():
    if not _FROND:
        fv, ff, fc = frond_mesh()
        me = bpy.data.meshes.new("frond")
        me.from_pydata([tuple(v) for v in fv], [], [tuple(f) for f in ff])
        me.update()
        ca = me.color_attributes.new(name="Col", type="FLOAT_COLOR", domain="POINT")
        ca.data.foreach_set("color", np.concatenate([fc, np.ones((len(fc), 1))], axis=1).ravel())
        fm = vcol_material("needles", 0.55, 0.3)
        fm.use_backface_culling = False
        me.materials.append(fm)
        _FROND["me"] = me
    return _FROND["me"]


def build_fir(Tm, seed=1, height=27.0, dense=1.0):
    """Conifer with its foot at Tm: trunk, whorled drooping branches, needle fronds."""
    rng = np.random.default_rng(seed)
    H = height
    created = []
    V, F, col, _, nt, ny = trunk_mesh(H=H, r_mid=0.55, r_top=0.04, roots=5, seed=9 + seed, nt=48, ny=200, flute=0.35, detail=0.4, moss=False)
    trunk = make_object("fir_trunk", V, F, col * 0.8)
    trunk.data.materials.append(vcol_material("bark2", 0.9, 0.1))
    frond_me = get_frond()
    Z = np.array([0.0, 0.0, 1.0])
    count = 0
    bv, bf, bc = [], [], []

    def tube(points, r0, r1, sides=5):
        n = len(points)
        base = len(bv)
        for k, p in enumerate(points):
            tt = k / (n - 1)
            tan = points[min(k + 1, n - 1)] - points[max(k - 1, 0)]
            tan = tan / (np.linalg.norm(tan) + 1e-9)
            a = np.cross(tan, Z)
            if np.linalg.norm(a) < 1e-4:
                a = np.array([1.0, 0, 0])
            a = a / np.linalg.norm(a)
            b = np.cross(tan, a)
            rr = r0 + (r1 - r0) * tt
            for s in range(sides):
                ang = 2 * np.pi * s / sides
                bv.append(p + (a * np.cos(ang) + b * np.sin(ang)) * rr)
                bc.append(np.array([0.1, 0.075, 0.06]) * (1.0 - 0.3 * tt))
        for k in range(n - 1):
            for s in range(sides):
                a0 = base + k * sides + s
                a1 = base + k * sides + (s + 1) % sides
                bf.append((a0, a1, a1 + sides, a0 + sides))

    y = 3.0
    tier = 0
    while y < H - 1.0:
        t = (y - 3.0) / (H - 4.0)
        L = 6.2 * (1 - t) ** 0.8 * (0.9 + 0.2 * rng.random()) + 0.9
        nb = int((11 if t < 0.8 else 6) * dense)
        spin = rng.random() * 6.28
        trunk_r = 0.55 * (1 - y / H) ** 1.25 + 0.04
        for kb in range(nb):
            yaw = spin + 2 * np.pi * kb / nb + rng.normal(0, 0.12)
            out = np.array([np.cos(yaw), np.sin(yaw), 0.0])
            Lb = L * (0.85 + 0.3 * rng.random())
            pts = []
            for s in np.linspace(0, 1, 9):
                p = np.array([0, 0, y]) + out * (trunk_r + Lb * s) + Z * (Lb * (0.14 * s - 0.34 * s * s + 0.18 * s ** 4))
                pts.append(p)
            pts = np.array(pts)
            tube(pts, 0.05 * (1 - 0.5 * t) + 0.01, 0.006)
            # Fronds along the branch, both sides, plus the tip.
            lat = np.cross(Z, out)
            for si in np.linspace(0.12, 0.97, 18):
                k = int(si * 8)
                pp = pts[k] + (pts[min(k + 1, 8)] - pts[k]) * (si * 8 - k)
                for side in (1, -1):
                    ang = np.deg2rad(58 + 8 * rng.normal())
                    dirv = out * np.cos(ang) + lat * side * np.sin(ang)
                    dirv = dirv + Z * (-0.22 - 0.16 * rng.random())
                    dirv = dirv / np.linalg.norm(dirv)
                    flen = (0.8 + 1.25 * (1 - si)) * (0.55 + 0.6 * (1 - t) ** 0.5) * (0.85 + 0.35 * rng.random())
                    y2 = np.cross(Z, dirv)
                    y2 = y2 / (np.linalg.norm(y2) + 1e-9)
                    z2 = np.cross(dirv, y2)
                    M = Matrix(((dirv[0], y2[0], z2[0], pp[0]), (dirv[1], y2[1], z2[1], pp[1]), (dirv[2], y2[2], z2[2], pp[2]), (0, 0, 0, 1)))
                    M = M @ Matrix.Scale(flen, 4)
                    ob = bpy.data.objects.new("f", frond_me)
                    ob.matrix_world = M
                    bpy.context.scene.collection.objects.link(ob)
                    created.append(ob)
                    count += 1
            tip_dir = pts[-1] - pts[-2]
            tip_dir = tip_dir / np.linalg.norm(tip_dir)
            y2 = np.cross(Z, tip_dir)
            y2 = y2 / (np.linalg.norm(y2) + 1e-9)
            z2 = np.cross(tip_dir, y2)
            M = Matrix(((tip_dir[0], y2[0], z2[0], pts[-1][0]), (tip_dir[1], y2[1], z2[1], pts[-1][1]), (tip_dir[2], y2[2], z2[2], pts[-1][2]), (0, 0, 0, 1)))
            M = M @ Matrix.Scale(0.9 * (0.5 + 0.5 * (1 - t)), 4)
            ob = bpy.data.objects.new("f", frond_me)
            ob.matrix_world = M
            bpy.context.scene.collection.objects.link(ob)
            created.append(ob)
            count += 1
        y += 0.6 * (0.9 + 0.2 * (1 - t)) / dense
        tier += 1
    br = make_object("branches", np.array(bv), bf, np.array(bc))
    br.data.materials.append(vcol_material("bark3", 0.9, 0.1))
    br.matrix_world = Tm
    trunk.matrix_world = Tm
    for o in created:
        o.matrix_world = Tm @ o.matrix_world
    return count


def do_fir():
    cam = setup_scene((1000, 1500))
    count = build_fir(Matrix.Identity(4), 3)
    print("fir fronds", count)
    bpy.context.scene.cycles.samples = 32
    look(cam, (-10, -34, 13.5), (0, 0, 13.0), 38)
    render("fir_full")
    bpy.context.scene.render.resolution_x, bpy.context.scene.render.resolution_y = 1400, 900
    look(cam, (-3.2, -7.0, 8.6), (0.8, 1.5, 7.6), 32)
    render("fir_branch_close")


def do_frond():
    fv, ff, fc = frond_mesh()
    ob = make_object("frond", fv, ff, fc, smooth_shade=False)
    m = vcol_material("needles", 0.5, 0.3)
    m.use_backface_culling = False
    ob.data.materials.append(m)
    cam = setup_scene((1400, 900))
    for o in list(bpy.data.objects):
        if o.name.startswith("Plane"):
            bpy.data.objects.remove(o)
    ob.rotation_euler = (math.radians(-60), 0, math.radians(0))
    look(cam, (0.5, -1.7, 0.3), (0.5, 0, 0.0), 40)
    render("frond_close")


def do_scene():
    """The composition: giant mossy redwoods and firs in glowing cobalt fog, seen from the path."""
    cam = setup_scene((1500, 900))
    sc = bpy.context.scene
    mat = vcol_material("bark", 0.92, 0.12)
    for (x, y, seed, h) in [(-8.5, 13, 5, 34), (6.5, 24, 6, 38), (-4, 46, 7, 42), (17, 8, 8, 30), (-22, 30, 9, 36), (24, 40, 10, 40)]:
        V, F, col, _, _, _ = trunk_mesh(H=h, r_mid=1.45, r_top=0.4, seed=seed, nt=220, ny=520)
        ob = make_object("giant%d" % seed, V, F, col)
        ob.data.materials.append(mat)
        ob.location = (x, y, 0)
        ob.rotation_euler = (0, 0, seed)
    for (x, y, seed, h) in [(2.5, 8, 21, 17), (-14, 20, 22, 20), (13, 33, 23, 22), (-1, 36, 24, 24), (-17, 52, 25, 26), (9, 56, 26, 28), (3, 16, 27, 14)]:
        build_fir(Matrix.Translation((x, y, 0)), seed, height=h, dense=0.75)
    # Glowing cobalt fog: a scattering volume in the world.
    if not os.environ.get("NOFOG"):
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 35, 18))
        box = bpy.context.active_object
        box.scale = (130, 120, 36)
        fm = bpy.data.materials.new("fog")
        fm.use_nodes = True
        nt = fm.node_tree
        for n in list(nt.nodes):
            if n.type != "OUTPUT_MATERIAL":
                nt.nodes.remove(n)
        vs = nt.nodes.new("ShaderNodeVolumePrincipled")
        vs.inputs["Color"].default_value = (0.25, 0.45, 1.0, 1)
        vs.inputs["Density"].default_value = float(os.environ.get("FOG_DENSITY", "0.012"))
        vs.inputs["Anisotropy"].default_value = 0.5
        nt.links.new(vs.outputs["Volume"], nt.nodes["Material Output"].inputs["Volume"])
        box.data.materials.append(fm)
        box.visible_shadow = False
    sc.world.node_tree.nodes["Background"].inputs[1].default_value = 2.4
    sc.cycles.samples = int(os.environ.get("SCENE_SAMPLES", "40"))
    sc.cycles.volume_bounces = 1
    sc.cycles.volume_max_steps = 96
    if os.environ.get("QUICK"):
        sc.render.resolution_x, sc.render.resolution_y = 750, 450
    look(cam, (3.5, -9.0, 1.7), (-0.5, 30.0, 8.0), 24)
    render(os.environ.get("OUTNAME", "scene_fog"))


if __name__ == "__main__":
    what = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else ["trunk", "fir", "frond"]
    if "scene" in what:
        do_scene()
    elif "trunk" in what:
        do_trunk()
    elif "fir" in what:
        do_fir()
    elif "frond" in what:
        do_frond()
