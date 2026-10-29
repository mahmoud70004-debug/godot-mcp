"""Paints the ground layer (terrain with organic edges) from the tile grid."""
import numpy as np
from PIL import Image


def value_noise(h, w, cell, seed):
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


def paint(g, TS, CRISP):
    H, W = g.shape
    PH, PW = H * TS, W * TS
    rs = np.random.RandomState(42)
    Y, X = np.mgrid[0:PH, 0:PW]
    chars = sorted(set("".join(g.flatten())) | set(".hgf=psbd~rP#^oOcDVUYWXSk"))
    idx = {ch: i for i, ch in enumerate(chars)}
    gi = np.vectorize(idx.get)(g)

    wx = (value_noise(PH, PW, 10, 1) - 0.5) * 9
    wy = (value_noise(PH, PW, 10, 2) - 0.5) * 9
    tc = gi[Y // TS, X // TS]
    txw = np.clip(((X + wx) // TS).astype(int), 0, W - 1)
    tyw = np.clip(((Y + wy) // TS).astype(int), 0, H - 1)
    tw = gi[tyw, txw]
    crisp_ids = [idx[ch] for ch in CRISP if ch in idx]
    crisp_c = np.isin(tc, crisp_ids)
    crisp_w = np.isin(tw, crisp_ids)
    T = np.where(crisp_c | crisp_w, tc, tw)

    img = np.zeros((PH, PW, 3), dtype=np.float32)
    n1 = value_noise(PH, PW, 24, 3)
    n2 = value_noise(PH, PW, 6, 4)
    rnd = rs.rand(PH, PW)

    def put(ch, rgb):
        if ch in idx:
            m = T == idx[ch]
            img[m] = rgb[m] if rgb.ndim == 3 else rgb

    def blend3(c1, c2, c3, a, b):
        c1, c2, c3 = (np.array(v, dtype=np.float32) for v in (c1, c2, c3))
        out = c1[None, None, :] * (1 - a[..., None]) + c2[None, None, :] * a[..., None]
        return out * (1 - b[..., None]) + c3[None, None, :] * b[..., None]

    # grass
    grass = blend3((104, 166, 76), (122, 182, 86), (86, 146, 66), n1, (n2 > 0.72) * 0.6)
    grass[(rnd < 0.05)] = (82, 140, 60)
    grass[(rnd > 0.985)] = (146, 200, 104)
    tuft = (((X % 7) == 3) & ((Y % 9) < 2) & (n2 > 0.55))
    grass[tuft] = (74, 128, 56)
    put(".", grass)
    hill = blend3((112, 158, 78), (134, 170, 88), (94, 136, 70), n1, (n2 > 0.7) * 0.5)
    hill[(rnd < 0.05)] = (88, 126, 62)
    hill[tuft] = (80, 116, 58)
    put("h", hill)
    tall = blend3((78, 130, 60), (96, 146, 66), (64, 108, 52), n1, n2 * 0.4)
    blades = ((X + (Y // 3)) % 4 == 0) & (rnd < 0.6)
    tall[blades] = (58, 98, 46)
    tall[(rnd > 0.97)] = (170, 180, 96)
    put("g", tall)
    farm = np.zeros((PH, PW, 3), np.float32)
    farm[:] = (122, 86, 56)
    farm[(Y % 8) < 3] = (98, 68, 44)
    farm[((Y % 8) == 5) & (X % 6 < 2)] = (90, 150, 70)
    put("f", farm)
    # paths
    dirt = blend3((200, 166, 116), (186, 150, 102), (214, 182, 132), n1, (n2 > 0.75) * 0.5)
    dirt[rnd < 0.03] = (160, 128, 90)
    dirt[rnd > 0.99] = (230, 210, 170)
    put("=", dirt)
    # cobblestones
    row = Y // 6
    offs = (row % 2) * 4
    cx = (X + offs) // 8
    stone_rand = np.random.RandomState(9).rand(PH // 6 + 1, PW // 8 + 2)
    sv = stone_rand[row, cx]
    cob = blend3((168, 160, 150), (150, 142, 134), (186, 178, 166), sv, (sv > 0.8) * 0.5)
    mortar = ((Y % 6) == 0) | (((X + offs) % 8) == 0)
    cob[mortar] = (118, 112, 106)
    put("p", cob)
    small = ((Y // 4) % 2) * 2
    kv = np.random.RandomState(19).rand(PH // 4 + 1, PW // 5 + 2)[Y // 4, (X + small) // 5]
    kob = blend3((178, 164, 140), (158, 146, 124), (196, 184, 160), kv, (kv > 0.85) * 0.4)
    kob[((Y % 4) == 0) | (((X + small) % 5) == 0)] = (124, 112, 96)
    put("k", kob)
    stairs = np.zeros((PH, PW, 3), np.float32)
    stairs[:] = (176, 170, 162)
    stairs[(Y % 6) < 2] = (128, 122, 116)
    stairs[(Y % 6) == 2] = (204, 198, 190)
    put("S", stairs)
    sand = blend3((236, 218, 168), (226, 204, 150), (244, 230, 190), n1, (n2 > 0.8) * 0.4)
    sand[rnd < 0.02] = (200, 180, 130)
    put("s", sand)
    # mountain rock / cliffs
    rockc = blend3((112, 116, 132), (96, 100, 116), (136, 140, 152), n1, (rnd < 0.15) * 0.6)
    put("^", rockc)
    strata = ((Y + (n2 * 6).astype(int)) % 5 == 0)
    cliff = blend3((134, 118, 104), (112, 98, 88), (88, 76, 70), n2, strata * 0.7)
    cliff[(rnd < 0.04)] = (160, 146, 128)
    cm = T == idx["#"]
    top_edge = cm & ~np.roll(cm, 3, axis=0)
    lip = cm & ~np.roll(cm, 1, axis=0)
    cliff[top_edge] = (156, 142, 124)
    cliff[lip] = (86, 140, 64)
    bot = cm & ~np.roll(cm, -2, axis=0)
    cliff[bot] = cliff[bot] * 0.7
    put("#", cliff)
    # wood: bridge, docks, floors
    plank_v = np.zeros((PH, PW, 3), np.float32)
    plank_v[:] = (150, 104, 64)
    plank_v[(X % 6) == 0] = (104, 70, 44)
    plank_v[((X % 6) == 3) & (rnd < 0.1)] = (176, 128, 82)
    put("b", plank_v)
    plank_h = np.zeros((PH, PW, 3), np.float32)
    plank_h[:] = (156, 110, 68)
    plank_h[(Y % 5) == 0] = (102, 70, 44)
    plank_h[((Y % 5) == 2) & ((X + (Y // 5) * 7) % 23 == 0)] = (102, 70, 44)
    put("d", plank_h)
    floor = np.zeros((PH, PW, 3), np.float32)
    floor[:] = (168, 122, 78)
    floor[(Y % 6) == 0] = (124, 86, 54)
    floor[((Y % 6) == 3) & ((X + (Y // 6) * 11) % 29 == 0)] = (124, 86, 54)
    floor[rnd < 0.02] = (186, 140, 92)
    put("o", floor)
    old = np.zeros((PH, PW, 3), np.float32)
    old[:] = (126, 104, 82)
    old[(Y % 6) == 0] = (78, 62, 48)
    old[rnd < 0.06] = (104, 88, 70)
    old[(n2 > 0.8)] = (150, 136, 100)
    put("O", old)
    parq = np.zeros((PH, PW, 3), np.float32)
    parq[:] = (128, 70, 50)
    parq[((X // 4 + Y // 4) % 2) == 0] = (146, 84, 58)
    parq[(X % 4 == 0) | (Y % 4 == 0)] = (100, 54, 40)
    put("c", parq)
    mat = np.zeros((PH, PW, 3), np.float32)
    mat[:] = (150, 60, 50)
    mat[(X % 4) < 2] = (170, 80, 60)
    put("D", mat)
    # walls
    wallp = np.zeros((PH, PW, 3), np.float32)
    wallp[:] = (220, 206, 168)
    wallp[(X % 8) == 0] = (200, 184, 146)
    wallp[(Y % TS) > 10] = (130, 92, 60)
    wallp[(Y % TS) == 11] = (100, 70, 46)
    put("V", wallp)
    fine = np.zeros((PH, PW, 3), np.float32)
    fine[:] = (96, 112, 92)
    fine[((X % 8) == 0) | (((X + 4) % 8 == 0) & ((Y % 8) == 4))] = (122, 140, 112)
    fine[(Y % TS) > 10] = (92, 54, 40)
    fine[(Y % TS) == 11] = (200, 170, 100)
    put("Y", fine)
    plankw = np.zeros((PH, PW, 3), np.float32)
    plankw[:] = (110, 80, 56)
    plankw[(X % 7) == 0] = (78, 56, 40)
    plankw[rnd < 0.05] = (90, 66, 46)
    put("U", plankw)
    put("W", np.zeros((PH, PW, 3), np.float32) + np.array((58, 40, 32), np.float32))
    put("X", np.zeros((PH, PW, 3), np.float32) + np.array((14, 12, 16), np.float32))

    # water (sea, river, pond) with depth from distance to land
    water_ids = [idx[ch] for ch in "~rP" if ch in idx]
    wm = np.isin(T, water_ids)
    land = ~wm
    dist = np.full((PH, PW), 40, np.float32)
    cur = land.copy()
    for d in range(1, 40):
        nxt = cur.copy()
        nxt[1:, :] |= cur[:-1, :]; nxt[:-1, :] |= cur[1:, :]
        nxt[:, 1:] |= cur[:, :-1]; nxt[:, :-1] |= cur[:, 1:]
        newly = nxt & ~cur
        dist[newly] = d
        cur = nxt
        if d > 30:
            break
    t = np.clip(dist / 30.0, 0, 1)[..., None]
    shallow = np.array((72, 176, 214), np.float32)
    deep = np.array((26, 82, 158), np.float32)
    water = shallow * (1 - t) + deep * t
    river = (T == idx.get("r", -1)) | (T == idx.get("P", -1))
    water[river] = water[river] * 0.6 + np.array((84, 170, 210), np.float32) * 0.4
    waves = (np.sin(X * 0.21 + np.sin(Y * 0.05) * 3) > 0.92) & ((Y % 9) == 0) & (rnd < 0.7)
    water[waves] = water[waves] * 0.5 + 0.5 * np.array((210, 236, 245), np.float32)
    foam = dist <= 2
    water[foam] = (226, 244, 246)
    foam2 = (dist == 3) & (rnd < 0.5)
    water[foam2] = (180, 228, 236)
    # darker water under docks & below cliffs
    dock = T == idx.get("d", -1)
    shadow = np.zeros_like(dock)
    for k in range(1, 5):
        shadow[k:, :] |= dock[:-k, :]
    water[shadow & wm] *= 0.72
    img[wm] = water[wm]

    # ambient shading: darken grass just under cliffs / mountains, light rim on cliff tops
    blk = np.isin(T, [idx[ch] for ch in "#^" if ch in idx])
    for k in range(1, 9):
        under = np.zeros_like(blk)
        under[k:, :] |= blk[:-k, :]
        under &= ~blk & ~wm
        img[under] *= 0.97 if k > 3 else 0.9
    # bridge rails
    bm = T == idx.get("b", -1)
    edge_top = bm & ~np.roll(bm, 2, axis=0)
    edge_bot = bm & ~np.roll(bm, -2, axis=0)
    img[edge_top | edge_bot] = (92, 60, 38)
    # dock edges
    de = dock & (~np.roll(dock, 1, axis=0) | ~np.roll(dock, -1, axis=0) | ~np.roll(dock, 1, axis=1) | ~np.roll(dock, -1, axis=1))
    img[de] = (96, 64, 40)

    out = np.clip(img, 0, 255).astype(np.uint8)
    mask = (wm & (dist > 2)).astype(np.uint8) * 255
    return Image.fromarray(out, "RGB"), Image.fromarray(mask, "L")
