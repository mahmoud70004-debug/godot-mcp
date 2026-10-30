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


def _hash(ix, iy, seed):
    h = (ix * 374761393 + iy * 668265263 + seed * 2147483647) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    return (h & 0xFFFF) / 65535.0


def cobblestones(ys, xs, cell, ref, seed=0, warm=False):
    """Laid cobbles: rounded stones (Voronoi on a jittered grid) with dark mortar joints,
    each stone its own tint of the reference's stone colour, lit from the upper left."""
    fx, fy = xs / cell, ys / cell
    ix, iy = np.floor(fx).astype(np.int64), np.floor(fy).astype(np.int64)
    d1 = np.full(xs.shape, 9.0, np.float32)
    d2 = np.full(xs.shape, 9.0, np.float32)
    best = np.zeros(xs.shape, np.int64)
    off = np.zeros(xs.shape + (2,), np.float32)
    for oy in (-1, 0, 1):
        for ox in (-1, 0, 1):
            cx, cy = ix + ox, iy + oy
            jx = 0.18 + 0.64 * _hash(cx, cy, seed)
            jy = 0.18 + 0.64 * _hash(cx, cy, seed + 7)
            dx, dy = (cx + jx) - fx, (cy + jy) - fy
            d = np.sqrt(dx * dx * 0.85 + dy * dy * 1.15).astype(np.float32)
            closer = d < d1
            d2 = np.where(closer, d1, np.minimum(d2, d))
            d1 = np.where(closer, d, d1)
            best = np.where(closer, cx * 92821 + cy, best)
            off[closer] = np.stack([dx, dy], -1)[closer]
    edge = (d2 - d1).astype(np.float32)
    tint = _hash(best, best // 92821, seed + 3)
    base = ref.mean(axis=(0, 1), keepdims=True) if ref.ndim == 3 else ref
    stone = np.empty(xs.shape + (3,), np.float32)
    pal = np.array([[150, 146, 138], [132, 128, 122], [164, 156, 142], [122, 120, 118], [158, 150, 136]], np.float32)
    if warm:
        pal = pal * np.array([1.06, 1.0, 0.9])
    k = (tint * len(pal)).astype(int).clip(0, len(pal) - 1)
    stone[:] = pal[k]
    stone = stone * 0.7 + ref * 0.3
    # dome shading: lit on the upper-left side of each stone
    light = 1.0 + 0.55 * np.clip(off[..., 0] * 0.7 + off[..., 1] * 0.9, -0.6, 0.6)
    stone *= light[..., None]
    mortar = np.clip((edge - 0.05) / 0.12, 0, 1)
    joint = np.array([70, 64, 56], np.float32) if not warm else np.array([84, 70, 52], np.float32)
    out = stone * mortar[..., None] + joint * (1 - mortar[..., None])
    return out


def cozy_planks(ys, xs, base, size, worn=False):
    """Interior floor boards: each board its own tone, staggered joints, nails, wax sheen."""
    row = (ys // size).astype(int)
    out = np.empty(ys.shape + (3,), np.float32)
    out[:] = base
    tone = 0.86 + 0.22 * (((row * 2654435761) % 97) / 97.0)
    out *= tone[..., None]
    seg = ((xs + (row * 37 % 11) * size) // (size * 6)).astype(int)
    out *= (0.95 + 0.1 * (((seg * 31 + row * 17) % 23) / 23.0))[..., None]
    a = ys % size
    out[a < max(1, RES // 2 + 1)] = np.array(base) * 0.48
    out[a == RES] = np.minimum(np.array(base) * 1.18, 255)
    joint = ((xs + (row * 37 % 11) * size) % (size * 6)) < RES
    out[joint] = np.array(base) * 0.55
    nail = (((xs + (row * 37 % 11) * size) % (size * 6)) == 2 * RES) & (a == size // 2)
    out[nail] = (60, 50, 44)
    grain = ((xs * 0.35 + row * 13 + a * 2.5) % 9) < 0.8
    out[grain] *= 0.93
    if worn:
        out *= 0.92
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
    walls = np.isin(T, [idx[c] for c in "WVYU" if c in idx])
    isfloor = np.isin(T, [idx[c] for c in "oOcD" if c in idx])
    dist_wall = cv2.distanceTransform((~walls).astype(np.uint8), cv2.DIST_L2, 5) / RES

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
        ref_cob = sample(mats["cobble"], ys, xs)
        cob = cobblestones(ys, xs, 7.0 * RES, ref_cob, seed=11)
        put("p", cob * (0.96 + 0.08 * dn)[..., None])
        put("k", cobblestones(ys, xs, 5.5 * RES, ref_cob, seed=23, warm=True))
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
        put("o", cozy_planks(ys, xs, (166, 112, 66), 6 * RES))
        put("O", cozy_planks(ys, xs, (118, 96, 74), 6 * RES, worn=True))
        # parquet: herring-bone of warm oak for Elias' study
        hb = ((xs // (4 * RES) + ys // (8 * RES)) % 2 == 0)
        parq = np.empty(ys.shape + (3,), np.float32)
        parq[:] = (150, 88, 56)
        parq[hb] = (172, 106, 66)
        parq[((xs + ys) % (8 * RES)) < RES] = (110, 62, 40)
        parq *= (0.94 + 0.12 * dn)[..., None]
        put("c", parq)
        mat_ = np.empty(ys.shape + (3,), np.float32)
        mat_[:] = (150, 60, 50)
        mat_[(xs % (4 * RES)) < 2 * RES] = (170, 80, 60)
        put("D", mat_)
        # walls seen from the front: horizontal logs over a skirting board
        ty = ys % (TS * RES)
        log_i = (ys // (5 * RES)).astype(int)
        logw = np.empty(ys.shape + (3,), np.float32)
        logw[:] = (176, 128, 80)
        tone = 0.9 + 0.12 * (((log_i * 7919) % 13) / 13.0)
        logw *= tone[..., None]
        in_log = (ys % (5 * RES)).astype(np.float32) / (5 * RES)
        logw *= (1.08 - 0.3 * np.abs(in_log - 0.35))[..., None]
        logw[(ys % (5 * RES)) < RES] = (92, 60, 38)
        logw[((xs + log_i * 53) % (40 * RES)) < RES] = (110, 74, 46)
        put("V", logw)
        # Elias: green panelled wallpaper with a gold rail
        fine = np.empty(ys.shape + (3,), np.float32)
        fine[:] = (74, 98, 78)
        fine[((xs // (2 * RES)) % 4) == 0] = (84, 110, 88)
        fine[(xs % (12 * RES)) < RES] = (58, 78, 62)
        fine[(ty > 5 * RES) & (ty < 6 * RES)] = (196, 160, 80)
        put("Y", fine)
        plk = plank_floor(ys, xs, False, (120, 86, 58), (72, 50, 34), (142, 104, 70), 7 * RES)
        plk *= (0.92 + 0.14 * dn)[..., None]
        put("U", plk)
        put("W", np.zeros(ys.shape + (3,), np.float32) + (58, 40, 30))
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

        # interiors: soft shadow along the walls
        dw = dist_wall[y0:y1]
        near = isfloor[y0:y1] & (dw < 18)
        col[near] = col[near] * (0.62 + 0.38 * np.clip(dw[near] / 18.0, 0, 1) ** 0.7)[..., None]
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
