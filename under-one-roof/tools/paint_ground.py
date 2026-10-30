"""Paints the ground from the tile grid using materials synthesised from the art reference
(tools/materials/*.png, see gen_materials.py).

Rendered at RES x world resolution and cut into CHUNK x CHUNK textures
(assets/world/ground_<cx>_<cy>.png). The alpha channel of each chunk marks water
(used by the water shimmer shader), everything else is opaque.
"""
import os
import cv2
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
RES = 2
CHUNK = 1024


def value_noise(h, w, cell, seed):
    """Smooth value noise of shape (h, w) (kept for the world generator)."""
    r = np.random.RandomState(seed)
    gh, gw = h // cell + 2, w // cell + 2
    grid = r.rand(gh, gw)
    ys = np.arange(h) / cell
    xs = np.arange(w) / cell
    y0 = ys.astype(int); x0 = xs.astype(int)
    ty = ys - y0; tx = xs - x0
    ty = ty * ty * (3 - 2 * ty); tx = tx * tx * (3 - 2 * tx)
    a = grid[y0][:, x0]; b = grid[y0][:, x0 + 1]
    c_ = grid[y0 + 1][:, x0]; d = grid[y0 + 1][:, x0 + 1]
    top = a * (1 - tx) + b * tx
    bot = c_ * (1 - tx) + d * tx
    return top * (1 - ty[:, None]) + bot * ty[:, None]


class Noise:
    """Value noise evaluated at arbitrary pixel coordinates (lattice cached)."""

    def __init__(self, h, w, cell, seed):
        self.cell = cell
        self.grid = np.random.RandomState(seed).rand(h // cell + 3, w // cell + 3).astype(np.float32)

    def at(self, ys, xs):
        fy, fx = ys / self.cell, xs / self.cell
        y0, x0 = fy.astype(int), fx.astype(int)
        ty, tx = fy - y0, fx - x0
        ty = ty * ty * (3 - 2 * ty)
        tx = tx * tx * (3 - 2 * tx)
        g = self.grid
        a = g[y0, x0] * (1 - tx) + g[y0, x0 + 1] * tx
        b = g[y0 + 1, x0] * (1 - tx) + g[y0 + 1, x0 + 1] * tx
        return a * (1 - ty) + b * ty


def load_materials():
    mats = {}
    for f in os.listdir(os.path.join(HERE, "materials")):
        if f.endswith(".png"):
            mats[f[:-4]] = np.array(Image.open(os.path.join(HERE, "materials", f)).convert("RGB")).astype(np.float32)
    return mats


def sample(mat, ys, xs, scale=1.0, ox=0, oy=0):
    h, w, _ = mat.shape
    return mat[((ys * scale + oy).astype(int)) % h, ((xs * scale + ox).astype(int)) % w]


def plank_floor(ys, xs, horizontal, base, dark, light, size):
    """Wooden planks (bridges, piers, interior floors)."""
    out = np.empty(ys.shape + (3,), np.float32)
    out[:] = base
    a = ys if horizontal else xs
    b = xs if horizontal else ys
    seam = (a % size) < RES
    out[seam] = dark
    row = (a // size).astype(int)
    joint = ((b + row * 37) % (size * 7)) < RES
    out[joint] = dark
    grain = ((b * 0.5 + row * 13 + (a % size) * 3) % 11) < 1
    out[grain & ~seam] = out[grain & ~seam] * 0.92
    hl = (a % size) == RES
    out[hl] = light
    return out


def paint(g, TS, CRISP):
    H, W = g.shape
    PH, PW = H * TS * RES, W * TS * RES
    mats = load_materials()
    chars = sorted(set("".join(g.flatten())) | set(".hgf=psbd~rP#^oOcDVUYWXSk"))
    idx = {ch: i for i, ch in enumerate(chars)}
    gi = np.vectorize(idx.get)(g).astype(np.uint8)
    crisp_ids = np.array([idx[ch] for ch in CRISP if ch in idx])
    wx_n = Noise(PH, PW, 20 * RES, 1)
    wy_n = Noise(PH, PW, 20 * RES, 2)
    big_n = Noise(PH, PW, 90 * RES, 3)
    mid_n = Noise(PH, PW, 26 * RES, 4)
    det_n = Noise(PH, PW, 7 * RES, 5)
    STRIP = 128

    # ---- pass 1: terrain id per output pixel ----
    # Soft labels: each terrain's tile mask is blurred at 1 sample / world px and the
    # strongest one wins, so tile staircases become rounded, organic shorelines and
    # paths; a fine coordinate warp then roughens the edges. Crisp tiles (floors,
    # piers, stairs...) keep exact tile borders.
    LH, LW = H * TS * RES, W * TS * RES
    best = np.full((LH, LW), -1.0, np.float32)
    lab = np.zeros((LH, LW), np.uint8)
    soft_n = Noise(LH, LW, 9 * RES, 6)
    jitter = np.empty((LH, LW), np.float32)
    for y0 in range(0, LH, STRIP * 2):
        lys, lxs = np.mgrid[y0:min(LH, y0 + STRIP * 2), 0:LW].astype(np.float32)
        jitter[y0:y0 + STRIP * 2] = (soft_n.at(lys, lxs) - 0.5) * 0.34
    del lys, lxs
    for ch, i in idx.items():
        m = (gi == i)
        if not m.any():
            continue
        up = cv2.resize(m.astype(np.float32), (LW, LH), interpolation=cv2.INTER_NEAREST)
        if i not in crisp_ids:
            up = cv2.GaussianBlur(up, (0, 0), TS * RES * 0.42) + jitter
        better = up > best
        best[better] = up[better]
        lab[better] = i
    del best, jitter
    T = np.zeros((PH, PW), np.uint8)
    for y0 in range(0, PH, STRIP):
        ys, xs = np.mgrid[y0:min(PH, y0 + STRIP), 0:PW].astype(np.float32)
        tc = gi[(ys // (TS * RES)).astype(int), (xs // (TS * RES)).astype(int)]
        wx = (wx_n.at(ys, xs) - 0.5) * 5 * RES
        wy = (wy_n.at(ys, xs) - 0.5) * 5 * RES
        lx = np.clip((xs + wx).astype(int), 0, LW - 1)
        ly = np.clip((ys + wy).astype(int), 0, LH - 1)
        tw = lab[ly, lx]
        crisp = np.isin(tc, crisp_ids) | np.isin(tw, crisp_ids)
        T[y0:y0 + STRIP] = np.where(crisp, tc, tw)

    water_ids = [idx[c] for c in "~rP" if c in idx]
    water = np.isin(T, water_ids)
    dist_land = cv2.distanceTransform(water.astype(np.uint8), cv2.DIST_L2, 5) / RES   # in world px
    river = np.isin(T, [idx[c] for c in "rP" if c in idx])
    dist_river = cv2.distanceTransform((~river).astype(np.uint8), cv2.DIST_L2, 5) / RES
    blk = np.isin(T, [idx[c] for c in "#^" if c in idx])
    dist_blk = cv2.distanceTransform((~blk).astype(np.uint8), cv2.DIST_L2, 5) / RES

    img = np.zeros((PH, PW, 4), np.uint8)
    for y0 in range(0, PH, STRIP):
        y1 = min(PH, y0 + STRIP)
        ys, xs = np.mgrid[y0:y1, 0:PW].astype(np.float32)
        t = T[y0:y1]
        col = np.zeros(ys.shape + (3,), np.float32)
        bn = big_n.at(ys, xs)
        mn = mid_n.at(ys, xs)
        dn = det_n.at(ys, xs)

        def put(ch, rgb):
            if ch in idx:
                m = t == idx[ch]
                col[m] = rgb[m]

        grass = sample(mats["grass"], ys, xs)
        gdark = sample(mats["grass_dark"], ys, xs, ox=171, oy=93)
        mix_g = np.clip((bn - 0.35) * 2.2, 0, 1)[..., None] * 0.55
        g_col = grass * (1 - mix_g) + gdark * mix_g
        g_col *= (0.93 + 0.14 * mn)[..., None]
        put(".", g_col)
        put("h", g_col * np.array([1.03, 1.01, 0.92]))
        mix_d = np.clip(0.35 + (bn - 0.5) * 1.6 + (mn - 0.5) * 0.5, 0.15, 0.85)[..., None]
        put("g", (g_col * (1 - mix_d) + gdark * mix_d) * 0.94)
        put("^", gdark * 0.72)
        dirt = sample(mats["dirt"], ys, xs) * (0.95 + 0.1 * mn)[..., None]
        put("=", dirt)
        farm = dirt * 0.82
        fur = (ys % (8 * RES)) < 3 * RES
        farm[fur] *= 0.72
        sprout = ((ys % (8 * RES)) == 5 * RES) & ((xs % (6 * RES)) < 2 * RES)
        farm[sprout] = farm[sprout] * 0.4 + np.array([70, 120, 50]) * 0.6
        put("f", farm)
        cob = sample(mats["cobble"], ys, xs) * (0.95 + 0.1 * dn)[..., None]
        put("p", cob)
        put("k", cob * np.array([1.05, 1.03, 1.0]))
        put("s", sample(mats["sand"], ys, xs) * (0.96 + 0.08 * mn)[..., None])
        cliff = sample(mats["cobble"], ys, xs, scale=0.6, ox=55) * np.array([0.82, 0.78, 0.72])
        put("#", cliff)
        st = np.empty(ys.shape + (3,), np.float32)
        st[:] = (150, 145, 136)
        st[(ys % (6 * RES)) < 2 * RES] = (92, 88, 82)
        st[(ys % (6 * RES)) == 2 * RES] = (186, 180, 170)
        put("S", st)
        put("b", plank_floor(ys, xs, False, (128, 92, 58), (66, 46, 30), (160, 120, 80), 7 * RES))
        put("d", plank_floor(ys, xs, True, (122, 88, 56), (60, 42, 28), (150, 112, 74), 6 * RES))
        put("o", plank_floor(ys, xs, True, (150, 108, 70), (100, 70, 46), (172, 128, 86), 6 * RES))
        put("O", plank_floor(ys, xs, True, (112, 92, 72), (70, 56, 44), (130, 112, 88), 6 * RES))
        parq = np.empty(ys.shape + (3,), np.float32)
        parq[:] = (128, 70, 50)
        parq[((xs // (4 * RES) + ys // (4 * RES)) % 2) == 0] = (146, 84, 58)
        put("c", parq)
        mat_ = np.empty(ys.shape + (3,), np.float32)
        mat_[:] = (150, 60, 50)
        mat_[(xs % (4 * RES)) < 2 * RES] = (170, 80, 60)
        put("D", mat_)
        wall = np.empty(ys.shape + (3,), np.float32)
        wall[:] = (206, 190, 150)
        wall[(xs % (8 * RES)) < RES] = (180, 162, 124)
        wall[(ys % (TS * RES)) > 10 * RES] = (120, 84, 56)
        put("V", wall)
        fine = np.empty(ys.shape + (3,), np.float32)
        fine[:] = (92, 108, 88)
        fine[(xs % (8 * RES)) < RES] = (116, 132, 106)
        fine[(ys % (TS * RES)) > 10 * RES] = (88, 52, 38)
        put("Y", fine)
        plk = plank_floor(ys, xs, False, (104, 76, 54), (70, 50, 36), (124, 92, 64), 7 * RES)
        put("U", plk)
        put("W", np.zeros(ys.shape + (3,), np.float32) + (54, 38, 30))
        put("X", np.zeros(ys.shape + (3,), np.float32) + (14, 12, 16))

        # water
        dl = dist_land[y0:y1]
        wm = water[y0:y1]
        rv = river[y0:y1]
        sea = sample(mats["sea"], ys, xs)
        deep = sample(mats["sea_deep"], ys, xs, ox=90)
        td = np.clip(dl / 60.0, 0, 1)[..., None]
        sea_col = sea * (1 - td) + deep * td * 0.92
        shallow = np.clip(1 - dl / 9.0, 0, 1)[..., None]
        sea_col = sea_col * (1 - shallow * 0.45) + np.array([120, 170, 170]) * shallow * 0.45
        riv = sample(mats["river"], ys, xs)
        pond = sample(mats["pond"], ys, xs)
        wcol = np.where(rv[..., None], riv, sea_col)
        if "P" in idx:
            wcol = np.where((t == idx["P"])[..., None], pond, wcol)
        # white foam line along every shore, with broken wisps
        foam_w = 2.2 + 1.4 * dn
        foam = dl <= foam_w
        wcol[foam & wm] = wcol[foam & wm] * 0.25 + np.array([236, 244, 240]) * 0.75
        wisp = (dl > foam_w + 1) & (dl < foam_w + 3.5) & (dn > 0.62)
        wcol[wisp & wm] = wcol[wisp & wm] * 0.55 + np.array([220, 236, 236]) * 0.45
        col[wm] = wcol[wm]

        # land near water: wet sand on beaches, dark earthy banks along rivers
        land = ~wm
        dr = dist_river[y0:y1]
        bank = land & (dr < 4.0) & ~np.isin(t, [idx[c] for c in "bdS" if c in idx])
        k = np.clip(1 - dr / 4.0, 0, 1)[..., None]
        col[bank] = (col * (1 - k * 0.75) + np.array([72, 60, 40]) * k * 0.75)[bank]
        # ambient occlusion under cliffs / dense forest edges
        db = dist_blk[y0:y1]
        ao = land & (db > 0) & (db < 10)
        col[ao] = col[ao] * (0.78 + 0.22 * np.clip(db[ao] / 10.0, 0, 1))[..., None]

        img[y0:y1, :, :3] = np.clip(col, 0, 255).astype(np.uint8)
        img[y0:y1, :, 3] = np.where(wm & (dl > 2.5), 150, 255)
    return img


def save_chunks(img, out_dir):
    """Writes ground_<cx>_<cy>.png chunks (skipping empty void ones) + .import presets."""
    os.makedirs(out_dir, exist_ok=True)
    for f in os.listdir(out_dir):
        if f.startswith("ground_") and (f.endswith(".png") or f.endswith(".png.import")):
            os.remove(os.path.join(out_dir, f))
    PH, PW = img.shape[:2]
    chunks = []
    for cy in range(0, PH, CHUNK):
        for cx in range(0, PW, CHUNK):
            c = img[cy:cy + CHUNK, cx:cx + CHUNK]
            if (c[..., :3].max(axis=2) < 20).all():
                continue
            name = f"ground_{cx // CHUNK}_{cy // CHUNK}.png"
            Image.fromarray(c, "RGBA").save(os.path.join(out_dir, name), optimize=False, compress_level=6)
            with open(os.path.join(out_dir, name + ".import"), "w") as f:
                f.write('[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n'
                        f'[deps]\n\nsource_file="res://assets/world/{name}"\n\n'
                        '[params]\n\ncompress/mode=2\nmipmaps/generate=false\n')
            chunks.append([cx // RES, cy // RES, name])
    return chunks
