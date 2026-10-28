#!/usr/bin/env python3
"""Pixelizer v2: raw pre-rendered character frames -> pixel-art sprite sheet + SpriteSheetData .tres.

Usage: python3 tools/pixelize_sprites.py [--raw DIR] [--out DIR] [--height PX] [--no-hueshift]
                                         [--contrast F] [--no-cleanup] [chars...]
Raw layout: <raw>/<char>/<anim>_<dir>_<frame>.png + meta.json (see tools/sprite_baker).
Output:     <out>/<char>/<char>.png and <char>.tres   (contract C1, RGBA grid sheet).
v2 (contract C10): when the raw dir also has <anim>_<dir>_<frame>_id.png material-id renders and
meta.json "materials", it writes an L8 trimmed index atlas + <char>_palette.png (material ramps, one row
per variant: row 0 as rendered, row v = meta "variants"[v-1]) + .png.import files + .tres.

Pipeline per character:
  1. palette: k-means in OKLab over the opaque pixels of all frames (meta["palette"] colours, max 64),
     sorted by hue/luminance, optional hue shift of the ramp ends (shadows cooler, highlights warmer);
  2. crisp downscale: every output pixel takes a REPRESENTATIVE palette index of its source block
     (block mode, but a clearly brighter/darker colour covering >= 20% of the block wins, so specular
     glints and dark seams survive); alpha = majority of the block;
  3. cleanup: orphan pixels, 1-px stair-step/dangling silhouette pixels, 1-px holes;
  4. selective outline: inner edge pixels step one ramp darker, a 1-px outer outline uses the adjacent
     colour darkened ~60% and shifted toward blue (extra colours, at most one per palette entry).
"""
import argparse
import json
import os
import sys

import numpy as np
from PIL import Image

PAD = 1
MAX_PALETTE = 64
KEEP_FRACTION = 0.2        # a contrasting colour must cover this much of the block's opaque pixels
KEEP_DELTA_L = 0.12        # ... and differ at least this much in OKLab lightness from the block mode
GLINT_DELTA_L = 0.25       # orphan pixels brighter than their surroundings by this much are kept
OUTLINE_L = 0.40           # outer outline keeps 40% of the neighbour's lightness (-60%)
INNER_L = 0.85             # inner edge steps to the palette colour nearest 85% lightness
COOL_HUE, WARM_HUE = np.deg2rad(275.0), np.deg2rad(75.0)

_M1 = np.array([[0.4122214708, 0.5363325363, 0.0514459929],
                [0.2119034982, 0.6806995451, 0.1073969566],
                [0.0883024619, 0.2817188376, 0.6299787005]])
_M2 = np.array([[0.2104542553, 0.7936177850, -0.0040720468],
                [1.9779984951, -2.4285922050, 0.4505937099],
                [0.0259040371, 0.7827717662, -0.8086757660]])
_M1I, _M2I = np.linalg.inv(_M1), np.linalg.inv(_M2)


def srgb_to_oklab(rgb):
    c = np.asarray(rgb, np.float64)
    lin = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
    return np.cbrt(lin @ _M1.T) @ _M2.T


def oklab_to_srgb(lab):
    lin = np.clip((np.asarray(lab, np.float64) @ _M2I.T) ** 3 @ _M1I.T, 0.0, 1.0)
    return np.where(lin <= 0.0031308, lin * 12.92, 1.055 * lin ** (1 / 2.4) - 0.055)


def to_u8(lab):
    return (np.clip(oklab_to_srgb(lab), 0, 1) * 255.0 + 0.5).astype(np.uint8)


# ---------------------------------------------------------------- loading

def load_frames(raw_dir, meta):
    frames = {}
    for anim, info in meta["anims"].items():
        for d in range(int(meta["dirs"])):
            for f in range(int(info["frames"])):
                path = os.path.join(raw_dir, "%s_%d_%d.png" % (anim, d, f))
                frames[(anim, d, f)] = np.asarray(Image.open(path).convert("RGBA"))
    return frames


def opaque_bbox(arr):
    ys, xs = np.nonzero(arr[..., 3] > 127)
    if len(ys) == 0:
        return None
    return xs.min(), ys.min(), xs.max() + 1, ys.max() + 1


def union_bbox(frames):
    x0 = y0 = 10**9
    x1 = y1 = -1
    for arr in frames.values():
        bb = opaque_bbox(arr)
        if bb is None:
            continue
        x0, y0, x1, y1 = min(x0, bb[0]), min(y0, bb[1]), max(x1, bb[2]), max(y1, bb[3])
    return int(x0), int(y0), int(x1), int(y1)


# ---------------------------------------------------------------- palette

def kmeans_oklab(pts, k, iters=14, seed=7):
    """Weighted-lightness k-means (kmeans++ init). pts: Nx3 OKLab. Returns kx3 centres."""
    rng = np.random.default_rng(seed)
    w = np.array([1.6, 1.0, 1.0])
    x = pts * w
    cent = [x[rng.integers(len(x))]]
    d2 = ((x - cent[0]) ** 2).sum(1)
    for _ in range(1, k):
        cent.append(x[rng.choice(len(x), p=d2 / d2.sum())] if d2.sum() > 0 else x[rng.integers(len(x))])
        d2 = np.minimum(d2, ((x - cent[-1]) ** 2).sum(1))
    cent = np.array(cent)
    for _ in range(iters):
        lab = np.argmin(((x[:, None, :] - cent[None]) ** 2).sum(-1), axis=1)
        for j in range(k):
            m = lab == j
            if m.any():
                cent[j] = x[m].mean(0)
            else:  # reseed an empty cluster at the worst-fit point
                far = np.argmax(((x - cent[lab]) ** 2).sum(1))
                cent[j] = x[far]
    return cent / w


def sort_palette(lab):
    chroma = np.hypot(lab[:, 1], lab[:, 2])
    hue = np.mod(np.arctan2(lab[:, 2], lab[:, 1]), 2 * np.pi)
    bucket = np.where(chroma < 0.03, -1, np.floor(hue / np.deg2rad(40.0)))
    return np.lexsort((lab[:, 0], bucket))


def hue_toward(lab, target, amount):
    """Rotate (a, b) toward the target hue angle by `amount` (0..1) of the shortest arc."""
    chroma = np.hypot(lab[:, 1], lab[:, 2])
    hue = np.arctan2(lab[:, 2], lab[:, 1])
    diff = np.arctan2(np.sin(target - hue), np.cos(target - hue))
    hue = hue + diff * amount
    out = lab.copy()
    out[:, 1], out[:, 2] = chroma * np.cos(hue), chroma * np.sin(hue)
    return out


def hue_shift_ends(lab):
    """Shadows cooler, highlights warmer; midtones untouched. Only chromatic colours move."""
    lo, hi = lab[:, 0].min(), lab[:, 0].max()
    t = (lab[:, 0] - lo) / max(hi - lo, 1e-6)
    out = lab.copy()
    chromatic = np.hypot(lab[:, 1], lab[:, 2]) > 0.02
    cool = np.clip((0.4 - t) / 0.4, 0, 1) * 0.30 * chromatic
    warm = np.clip((t - 0.65) / 0.35, 0, 1) * 0.22 * chromatic
    out = hue_toward(out, COOL_HUE, cool)
    return hue_toward(out, WARM_HUE, warm)


def build_palette(frames_rgba, n_colors, max_samples=160000):
    n_colors = int(min(max(n_colors, 2), MAX_PALETTE))
    pix = np.concatenate([a[a[..., 3] > 127][:, :3][::7] for a in frames_rgba])
    rng = np.random.default_rng(3)
    if len(pix) > max_samples:
        pix = pix[rng.choice(len(pix), max_samples, replace=False)]
    cent = kmeans_oklab(srgb_to_oklab(pix / 255.0), n_colors)
    return cent[sort_palette(cent)]


def quant_lut(pal_lab, bits=6):
    """Nearest palette index for every (r,g,b) cell of a 2^bits cube (OKLab distance)."""
    n = 1 << bits
    g = (np.arange(n) + 0.5) / n
    rgb = np.stack(np.meshgrid(g, g, g, indexing="ij"), -1).reshape(-1, 3)
    lab = srgb_to_oklab(rgb) * np.array([1.6, 1.0, 1.0])
    p = pal_lab * np.array([1.6, 1.0, 1.0])
    out = np.empty(len(lab), np.int16)
    for i in range(0, len(lab), 32768):
        out[i:i + 32768] = np.argmin(((lab[i:i + 32768, None, :] - p[None]) ** 2).sum(-1), axis=1)
    return out.reshape(n, n, n)


# ---------------------------------------------------------------- crisp downscale

def representative_downscale(crop, size, lut, lum, bits=6):
    """crop: HxWx4 uint8 -> (dh, dw) int16 palette indices, -1 where transparent."""
    dw, dh = size
    (blk,), k = block_samples([crop], size)
    opaque = blk[..., 3] > 127
    sh = 8 - bits
    q = lut[blk[..., 0] >> sh, blk[..., 1] >> sh, blk[..., 2] >> sh].astype(np.int64)
    q = np.where(opaque, q, -1)
    pick, n_op = pick_representative(q, lum)
    idx = np.where(n_op * 2 >= k * k, pick, -1)
    return idx.reshape(dh, dw).astype(np.int16)


def pick_representative(q, lum):
    """q: N x K palette indices (-1 = none). Block mode, unless a clearly brighter/darker colour covering
    >= KEEP_FRACTION of the block exists. Returns (index per block, valid sample count per block)."""
    n, kk = q.shape
    p = len(lum)
    flat = (np.arange(n)[:, None] * (p + 1) + (q + 1)).ravel()
    counts = np.bincount(flat, minlength=n * (p + 1)).reshape(n, p + 1)
    col = counts[:, 1:]
    n_op = col.sum(1)
    mode = col.argmax(1)
    dl = lum[None, :] - lum[mode][:, None]
    cand = (col > 0) & (col * 1.0 >= KEEP_FRACTION * n_op[:, None]) & (np.abs(dl) >= KEEP_DELTA_L)
    score = np.where(cand, np.abs(dl) * (1.0 + 0.3 * (dl > 0)), -1.0)
    best = score.argmax(1)
    return np.where(score[np.arange(n), best] > 0, best, mode), n_op


def block_samples(arrs, size):
    """Sample each output pixel's source block on a k x k rounded grid. arrs: list of HxW(xC) arrays.
    Returns (list of N x K x C... arrays, k)."""
    h, w = arrs[0].shape[:2]
    dw, dh = size
    k = int(np.clip(np.ceil(max(w / dw, h / dh)), 1, 8))
    sub = (np.arange(k) + 0.5) / k
    ys = np.clip(np.floor((np.arange(dh)[:, None] + sub[None]) * h / dh).astype(int), 0, h - 1)
    xs = np.clip(np.floor((np.arange(dw)[:, None] + sub[None]) * w / dw).astype(int), 0, w - 1)
    out = []
    for a in arrs:
        b = a[ys[:, :, None, None], xs[None, None, :, :]]
        b = b.transpose((0, 2, 1, 3) + tuple(range(4, b.ndim)))
        out.append(b.reshape((dh * dw, k * k) + a.shape[2:]))
    return out, k


# ---------------------------------------------------------------- cleanup

_OFFS8 = [(-1, -1), (-1, 0), (-1, 1), (0, -1), (0, 1), (1, -1), (1, 0), (1, 1)]


def shifted(a, dy, dx, fill):
    """Array whose [y, x] is a[y+dy, x+dx] (fill outside)."""
    p = np.pad(a, 1, constant_values=fill)
    h, w = a.shape
    return p[1 + dy:1 + dy + h, 1 + dx:1 + dx + w]


def neighbour_stack(idx):
    return np.stack([shifted(idx, dy, dx, -1) for dy, dx in _OFFS8])


def neighbour_mode(idx, pal_size):
    """Most common opaque 8-neighbour index and its count, per pixel."""
    st = neighbour_stack(idx)
    counts = np.zeros((pal_size,) + idx.shape, np.int16)
    for s in st:
        for v in np.unique(s[s >= 0]):
            counts[v] += (s == v)
    return counts.argmax(0).astype(np.int16), counts.max(0)


def cleanup(idx, lum, owner=None):
    """owner: optional material id per palette entry; orphans of another material than their
    surroundings (eyes, buckles) are real detail and kept."""
    idx = idx.copy()
    m = idx >= 0
    n8 = sum(shifted(m, dy, dx, False).astype(np.int8) for dy, dx in _OFFS8)
    up, dn = shifted(m, -1, 0, False), shifted(m, 1, 0, False)
    lf, rt = shifted(m, 0, -1, False), shifted(m, 0, 1, False)
    n4 = up.astype(np.int8) + dn + lf + rt
    corner = (up & lf) | (up & rt) | (dn & lf) | (dn & rt)
    kill = m & ((n8 == 0) | ((n8 == 2) & (n4 == 2) & corner))   # dangling pixel / 1-px L step
    fill = ~m & (n4 == 4)                                       # 1-px hole
    idx[kill] = -1
    p = len(lum)
    mode, _ = neighbour_mode(np.where(fill, -1, idx), p)
    idx[fill] = mode[fill]
    # orphan colour pixels: differ from every opaque neighbour while those neighbours agree
    mode, cnt = neighbour_mode(idx, p)
    st = neighbour_stack(idx)
    n_nb = (st >= 0).sum(0)
    differs = ~(st == idx[None]).any(0)
    agree = cnt >= n_nb - 1
    glint = (lum[np.maximum(idx, 0)] - lum[mode]) > GLINT_DELTA_L
    orphan = (idx >= 0) & (n_nb >= 5) & differs & agree & ~glint
    if owner is not None:
        orphan &= owner[np.maximum(idx, 0)] == owner[mode]
    idx[orphan] = mode[orphan]
    return idx


# ---------------------------------------------------------------- outline

def outline(idx, pal_n, edge_idx, lum):
    """idx padded by PAD. Returns idx where outer outline pixels hold pal_n + neighbour index."""
    m = idx >= 0
    out = idx.copy()
    nbs = [shifted(idx, dy, dx, -1) for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1))]
    edge = m & (~shifted(m, -1, 0, False) | ~shifted(m, 1, 0, False)
                | ~shifted(m, 0, -1, False) | ~shifted(m, 0, 1, False))
    out[edge] = edge_idx[idx[edge]]
    # outer outline from the darkest adjacent opaque pixel (pre-darken colour)
    best = np.full(idx.shape, -1, np.int16)
    best_l = np.full(idx.shape, 9.0)
    for nb in nbs:
        l = np.where(nb >= 0, lum[np.maximum(nb, 0)], 9.0)
        better = l < best_l
        best = np.where(better, nb, best)
        best_l = np.where(better, l, best_l)
    ring = ~m & (best >= 0)
    out[ring] = pal_n + best[ring]
    return out


def derive_colours(pal_lab):
    """(shifted-palette OKLab) -> inner-edge indices and outer-outline OKLab colours."""
    lum = pal_lab[:, 0]
    target = pal_lab.copy()
    target[:, 0] *= INNER_L
    d = (((target[:, None, :] - pal_lab[None]) ** 2) * np.array([4.0, 1.0, 1.0])).sum(-1)
    edge_idx = d.argmin(1).astype(np.int16)
    dark = pal_lab.copy()
    dark[:, 0] *= OUTLINE_L
    dark[:, 1:] *= 0.9
    dark = hue_toward(dark, COOL_HUE, 0.25)
    return edge_idx, dark, lum


# ---------------------------------------------------------------- driver

def process(char, raw_root, out_root, height=None, hue_shift=True, contrast=1.1, do_cleanup=True,
            allow_missing=False):
    raw_dir = os.path.join(raw_root, char)
    with open(os.path.join(raw_dir, "meta.json")) as fh:
        meta = json.load(fh)
    if is_v2(raw_dir, meta):
        return process_v2(char, raw_root, out_root, meta, height, hue_shift, contrast, do_cleanup,
                          allow_missing)
    target_h = int(height) if height else int(meta["height_px"])
    dirs = int(meta["dirs"])
    frames = load_frames(raw_dir, meta)
    x0, y0, x1, y1 = union_bbox(frames)
    crop_w, crop_h = x1 - x0, y1 - y0

    # Scale so the idle pose (front, frame 0) is target_h tall; the union crop shares it.
    ref = frames[("idle", 0, 0)] if ("idle", 0, 0) in frames else next(iter(frames.values()))
    rb = opaque_bbox(ref)
    ref_h = rb[3] - rb[1]
    scale = float(target_h) / ref_h
    dw, dh = max(1, round(crop_w * scale)), max(1, round(crop_h * scale))

    crops = {k: a[y0:y1, x0:x1] for k, a in frames.items()}
    pal_q = build_palette(list(crops.values()), int(meta["palette"]))      # used for matching
    lut = quant_lut(pal_q)
    pal_lab = pal_q.copy()
    if hue_shift:
        pal_lab = hue_shift_ends(pal_lab)
    if contrast != 1.0:
        mean_l = pal_lab[:, 0].mean()
        pal_lab[:, 0] = np.clip((pal_lab[:, 0] - mean_l) * contrast + mean_l, 0.0, 1.0)
    lum_q = pal_q[:, 0]
    pn = len(pal_lab)
    edge_idx, dark_lab, _ = derive_colours(pal_lab)
    lum_out = pal_lab[:, 0]
    colours = np.concatenate([to_u8(pal_lab), to_u8(dark_lab)])           # main ramps + outline colours

    fw, fh = dw + 2 * PAD, dh + 2 * PAD
    rows = len(meta["anims"]) * dirs
    cols = max(int(i["frames"]) for i in meta["anims"].values())
    sheet = np.zeros((rows * fh, cols * fw, 4), np.uint8)
    anims_out = {}
    used = set()
    row = 0
    for anim, info in meta["anims"].items():
        anims_out[anim] = {"row": row, "frames": int(info["frames"]), "fps": float(info["fps"]),
                           "loop": bool(info["loop"])}
        for d in range(dirs):
            for f in range(int(info["frames"])):
                idx = representative_downscale(crops[(anim, d, f)], (dw, dh), lut, lum_q)
                if do_cleanup:
                    idx = cleanup(idx, lum_q)
                idx = np.pad(idx, PAD, constant_values=-1)
                idx = outline(idx, pn, edge_idx, lum_out)
                rgba = np.zeros(idx.shape + (4,), np.uint8)
                m = idx >= 0
                rgba[m, :3] = colours[idx[m]]
                rgba[m, 3] = 255
                used.update(np.unique(idx[m]).tolist())
                sheet[(row + d) * fh:(row + d + 1) * fh, f * fw:(f + 1) * fw] = rgba
        row += dirs

    out_dir = os.path.join(out_root, char)
    os.makedirs(out_dir, exist_ok=True)
    Image.fromarray(sheet, "RGBA").save(os.path.join(out_dir, char + ".png"), optimize=True)

    metres_per_raw_px = float(meta["camera_size"]) / float(meta["render_px"])
    pixel_size = metres_per_raw_px / scale
    # feet line = bottom of the idle reference pose; rows below it (death pose, outline pad) are transparent
    foot_offset = int(round((y1 - rb[3]) * scale)) + PAD
    write_tres(out_dir, char, (fw, fh), dirs, anims_out, pixel_size, foot_offset, out_root)
    print("%s: sheet %dx%d, frame %dx%d, rows %d, cols %d, pixel_size %.5f, height %d, colours %d (ramps %d)"
          % (char, sheet.shape[1], sheet.shape[0], fw, fh, rows, cols, pixel_size, target_h,
             len({tuple(colours[i]) for i in used}), pn))


# ---------------------------------------------------------------- v2: material ramps, atlas (C10)

def v2_frame_paths(raw_dir, anim, d, f):
    base = os.path.join(raw_dir, "%s_%d_%d" % (anim, d, f))
    return base + ".png", base + "_id.png"


def load_v2_frame(raw_dir, anim, d, f, known_ids):
    """-> (rgb uint8 HxWx3, ids uint8 HxW, 0 = transparent) or None when missing."""
    p, pid = v2_frame_paths(raw_dir, anim, d, f)
    if not (os.path.isfile(p) and os.path.isfile(pid)):
        return None
    rgba = np.asarray(Image.open(p).convert("RGBA"))
    ids = (np.asarray(Image.open(pid).convert("L")).astype(np.int32) + 8) // 16
    ids = np.where(np.isin(ids, known_ids) & (rgba[..., 3] > 127), ids, 0).astype(np.uint8)
    return rgba[..., :3], ids


def v2_keys(meta):
    for anim, info in meta["anims"].items():
        for d in range(int(meta["dirs"])):
            for f in range(int(info["frames"])):
                yield anim, d, f


def is_v2(raw_dir, meta):
    if not meta.get("materials"):
        return False
    return any(os.path.isfile(v2_frame_paths(raw_dir, *k)[1]) for k in v2_keys(meta))


def ramp_shift(lab):
    """Mild hue shift along one ramp (dark -> light): darks cooler, lights warmer."""
    n = len(lab)
    if n < 2:
        return lab
    t = np.linspace(0.0, 1.0, n)
    chromatic = np.hypot(lab[:, 1], lab[:, 2]) > 0.02
    out = hue_toward(lab, COOL_HUE, np.clip((0.4 - t) / 0.4, 0, 1) * 0.30 * chromatic)
    return hue_toward(out, WARM_HUE, np.clip((t - 0.65) / 0.35, 0, 1) * 0.22 * chromatic)


def recolour_ramp(lab, rgb):
    """Variant ramp: hue/chroma from `rgb`, lightness profile scaled so the mid step equals its lightness."""
    target = srgb_to_oklab(np.array(rgb, np.float64))
    mid = len(lab) // 2
    scale = target[0] / max(lab[mid, 0], 1e-4)
    chroma = np.hypot(lab[:, 1], lab[:, 2])
    rel = chroma / chroma[mid] if chroma[mid] > 0.01 else np.ones(len(lab))
    tc = np.hypot(target[1], target[2])
    th = np.arctan2(target[2], target[1])
    out = np.empty_like(lab)
    out[:, 0] = np.clip(lab[:, 0] * scale, 0.0, 1.0)
    out[:, 1] = tc * np.clip(rel, 0.3, 1.6) * np.cos(th)
    out[:, 2] = tc * np.clip(rel, 0.3, 1.6) * np.sin(th)
    return out


def sample_materials(raw_dir, meta, known_ids, per_frame=500, cap=60000):
    """Pass 1: union bbox of the opaque pixels, reference height and per-material colour samples."""
    rng = np.random.default_rng(5)
    samples = {m: [] for m in known_ids}
    x0 = y0 = 10**9
    x1 = y1 = -1
    ref_h = None
    ref_bottom = None
    found = 0
    for key in v2_keys(meta):
        fr = load_v2_frame(raw_dir, *key, known_ids)
        if fr is None:
            continue
        found += 1
        rgb, ids = fr
        ys, xs = np.nonzero(ids)
        if len(ys) == 0:
            continue
        x0, y0, x1, y1 = min(x0, xs.min()), min(y0, ys.min()), max(x1, xs.max() + 1), max(y1, ys.max() + 1)
        if ref_h is None or key == ("idle", 0, 0):
            ref_h, ref_bottom = ys.max() + 1 - ys.min(), ys.max() + 1
        for m in known_ids:
            sel = rgb[ids == m]
            if len(sel):
                samples[m].append(sel[rng.choice(len(sel), min(len(sel), per_frame), replace=False)])
    if not found:
        raise SystemExit("no frames with id maps found in %s" % raw_dir)
    cols = {}
    for m in known_ids:
        if samples[m]:
            a = np.concatenate(samples[m])
            cols[m] = a[rng.choice(len(a), min(len(a), cap), replace=False)] / 255.0
    return (int(x0), int(y0), int(x1), int(y1)), int(ref_h), int(ref_bottom), cols


def build_ramps(meta, cols, contrast):
    """-> ids (sorted), {id: OKLab ramp dark->light, base look}. Materials without pixels get a grey ramp."""
    ramps = {}
    for mid in sorted(int(k) for k in meta["materials"]):
        n = int(meta["materials"][str(mid)]["shades"])
        if mid in cols and len(cols[mid]):
            lab = srgb_to_oklab(cols[mid])
            cent = kmeans_oklab(lab, n) if n > 1 else lab.mean(0, keepdims=True)
            ramps[mid] = cent[np.argsort(cent[:, 0])]
        else:
            ramps[mid] = np.stack([np.linspace(0.3, 0.8, n), np.zeros(n), np.zeros(n)], 1)
    if contrast != 1.0:
        mean_l = np.mean(np.concatenate([r[:, 0] for r in ramps.values()]))
        for r in ramps.values():
            r[:, 0] = np.clip((r[:, 0] - mean_l) * contrast + mean_l, 0.0, 1.0)
    return ramps


def ramp_colours(ramps, hue_shift, layout):
    """256 x 3 uint8 colour table for one variant. layout: {id: (outline_index, first_shade_index)}."""
    table = np.zeros((256, 3), np.uint8)
    for mid, lab in ramps.items():
        lab = ramp_shift(lab) if hue_shift else lab
        dark = lab[0:1].copy()
        dark[:, 0] *= OUTLINE_L
        dark[:, 1:] *= 0.9
        dark = hue_toward(dark, COOL_HUE, 0.25)
        o, s = layout[mid]
        table[o] = to_u8(dark)[0]
        table[s:s + len(lab)] = to_u8(lab)
    return table


def downscale_v2(rgb, ids, size, shade_lab, owner, lum):
    """Crisp representative downscale with ids: block id = majority id (never averaged); colour = nearest
    shade of that material for samples of the block id, mode / contrast pick among those."""
    dw, dh = size
    (brgb, bid), k = block_samples([rgb, ids], size)
    n = dh * dw
    cnt = np.bincount((np.arange(n)[:, None] * 16 + bid).ravel(), minlength=n * 16).reshape(n, 16)
    cnt[:, 0] = 0
    block_id = cnt.argmax(1)
    total = cnt.sum(1)
    valid = (bid == block_id[:, None]) & (block_id[:, None] > 0)
    lab = srgb_to_oklab(brgb.reshape(-1, 3) / 255.0) * np.array([1.6, 1.0, 1.0])
    pl = shade_lab * np.array([1.6, 1.0, 1.0])
    d = ((lab[:, None, :] - pl[None]) ** 2).sum(-1)
    d = np.where(owner[None, :] == bid.reshape(-1)[:, None], d, np.inf)
    q = np.where(valid.reshape(-1), d.argmin(1), -1).reshape(n, k * k)
    pick, _ = pick_representative(q, lum)
    idx = np.where((total * 2 >= k * k) & (block_id > 0), pick, -1)
    return idx.reshape(dh, dw).astype(np.int16)


def shelf_pack(sizes, max_h=4096):
    """sizes: list of (w, h). Tries widths 256..2048; returns (width, height, positions) for the smallest
    width whose height fits max_h. Tallest frames first; 1 px gap."""
    order = sorted(range(len(sizes)), key=lambda i: (-sizes[i][1], -sizes[i][0]))
    widest = max((w for w, _ in sizes), default=1)
    for width in (256, 384, 512, 768, 1024, 1536, 2048):
        if width < widest + 1:
            continue
        pos = [None] * len(sizes)
        x = y = shelf = 0
        for i in order:
            w, h = sizes[i]
            if w == 0:
                pos[i] = (0, 0)
                continue
            if x + w > width:
                x, y, shelf = 0, y + shelf, 0
            pos[i] = (x, y)
            x += w + 1
            shelf = max(shelf, h + 1)
        if y + shelf <= max_h:
            return width, max(1, y + shelf), pos
    raise SystemExit("atlas does not fit 2048 x %d" % max_h)


IMPORT_TPL = (
    '[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n'
    'path="res://.godot/imported/%(n)s.png-%(h)s.ctex"\nmetadata={\n"vram_texture": false\n}\n\n[deps]\n\n'
    'source_file="%(res)s"\ndest_files=["res://.godot/imported/%(n)s.png-%(h)s.ctex"]\n\n[params]\n\n'
    "compress/mode=0\ncompress/high_quality=false\ncompress/lossy_quality=0.7\ncompress/hdr_compression=1\n"
    "compress/normal_map=0\ncompress/channel_pack=0\nmipmaps/generate=false\nmipmaps/limit=-1\n"
    'roughness/mode=0\nroughness/src_normal=""\nprocess/fix_alpha_border=false\nprocess/premult_alpha=false\n'
    "process/normal_map_invert_y=false\nprocess/hdr_as_srgb=false\nprocess/hdr_clamp_exposure=false\n"
    "process/size_limit=0\ndetect_3d/compress_to=0\n"
)


def write_import(out_dir, name):
    """Lossless, no mipmaps, no VRAM compression. Only for files inside the project; an existing file
    (with the uid Godot wrote) is kept."""
    res = res_path(out_dir, name)
    if not res.startswith("res://"):
        return
    path = os.path.join(out_dir, name + ".import")
    if os.path.exists(path):
        return
    import hashlib
    with open(path, "w") as fh:
        fh.write(IMPORT_TPL % {"n": name[:-4], "h": hashlib.md5(res.encode()).hexdigest(), "res": res})


def process_v2(char, raw_root, out_root, meta, height, hue_shift, contrast, do_cleanup, allow_missing):
    raw_dir = os.path.join(raw_root, char)
    dirs = int(meta["dirs"])
    known = sorted(int(k) for k in meta["materials"])
    (x0, y0, x1, y1), ref_h, ref_bottom, cols = sample_materials(raw_dir, meta, known)
    scale = float(height or int(meta["height_px"])) / ref_h
    dw, dh = max(1, round((x1 - x0) * scale)), max(1, round((y1 - y0) * scale))
    fw, fh = dw + 2 * PAD, dh + 2 * PAD

    ramps = build_ramps(meta, cols, contrast)
    layout, pos = {}, 1                    # index 0 = transparent; per material: outline step, then shades
    for mid in known:
        layout[mid] = (pos, pos + 1)
        pos += 1 + len(ramps[mid])
    if pos > 256:
        raise SystemExit("palette needs %d entries (max 256)" % pos)
    variants = [{}] + list(meta.get("variants", []))
    names = {int(k): v["name"] for k, v in meta["materials"].items()}
    tables = []
    for var in variants:
        vr = {}
        for mid in known:
            vr[mid] = recolour_ramp(ramps[mid], var[names[mid]]) if names[mid] in var else ramps[mid]
        tables.append(ramp_colours(vr, hue_shift, layout))
    # matching space: base ramps (shade space = concatenated shades), shade -> final index, owner material
    shade_lab = np.concatenate([ramps[m] for m in known])
    owner = np.concatenate([[m] * len(ramps[m]) for m in known]).astype(np.int64)
    lum = shade_lab[:, 0]
    fin = np.concatenate([np.arange(layout[m][1], layout[m][1] + len(ramps[m])) for m in known])
    s_n = len(shade_lab)
    out_fin = np.array([layout[m][0] for m in known])       # outline index per known material position
    mat_pos = {m: i for i, m in enumerate(known)}
    owner_pos = np.array([mat_pos[o] for o in owner])
    # inner edge step: nearest shade of the same material near 85% lightness
    tgt = shade_lab.copy()
    tgt[:, 0] *= INNER_L
    dd = (((tgt[:, None, :] - shade_lab[None]) ** 2) * np.array([4.0, 1.0, 1.0])).sum(-1)
    dd = np.where(owner[:, None] == owner[None, :], dd, np.inf)
    edge_idx = dd.argmin(1).astype(np.int16)

    mapping = np.concatenate([fin, out_fin]).astype(np.uint8)   # [shade idx | s_n + material pos] -> final
    trimmed = {}
    missing = 0
    for key in v2_keys(meta):
        fr = load_v2_frame(raw_dir, *key, known)
        if fr is None:
            if not allow_missing:
                raise SystemExit("missing frame %s_%d_%d in %s (use --allow-missing)" % (key + (raw_dir,)))
            missing += 1
            trimmed[key] = None
            continue
        rgb, ids = fr
        idx = downscale_v2(rgb[y0:y1, x0:x1], ids[y0:y1, x0:x1], (dw, dh), shade_lab, owner, lum)
        if do_cleanup:
            idx = cleanup(idx, lum, owner)
        idx = np.pad(idx, PAD, constant_values=-1)
        m = idx >= 0
        out = outline(idx, s_n, edge_idx, lum)
        ring = out >= s_n
        out[ring] = s_n + owner_pos[out[ring] - s_n]
        fin_img = np.where(out >= 0, mapping[np.maximum(out, 0)], 0).astype(np.uint8)
        bb = Image.fromarray(fin_img, "L").getbbox()
        trimmed[key] = None if bb is None else (fin_img[bb[1]:bb[3], bb[0]:bb[2]], bb[0], bb[1])

    keys = list(v2_keys(meta))
    sizes = [(0, 0) if trimmed[k] is None else trimmed[k][0].shape[::-1] for k in keys]
    width, height_px, positions = shelf_pack(sizes)
    atlas = np.zeros((height_px, width), np.uint8)
    ints = []
    for k, (px, py) in zip(keys, positions):
        t = trimmed[k]
        if t is None:
            ints += [0, 0, 0, 0, 0, 0]
            continue
        h, w = t[0].shape
        atlas[py:py + h, px:px + w] = t[0]
        ints += [px, py, w, h, t[1], t[2]]
    anims_out, start = {}, 0
    for anim, info in meta["anims"].items():
        anims_out[anim] = {"start": start, "frames": int(info["frames"]), "fps": float(info["fps"]),
                           "loop": bool(info["loop"])}
        start += dirs * int(info["frames"])

    out_dir = os.path.join(out_root, char)
    os.makedirs(out_dir, exist_ok=True)
    png = os.path.join(out_dir, char + ".png")
    Image.fromarray(atlas, "L").save(png, optimize=True)
    pal = np.zeros((len(tables), 256, 4), np.uint8)
    for v, t in enumerate(tables):
        pal[v, :, :3] = t
        pal[v, 1:pos, 3] = 255
    ppng = os.path.join(out_dir, char + "_palette.png")
    Image.fromarray(pal, "RGBA").save(ppng)
    write_import(out_dir, char + ".png")
    write_import(out_dir, char + "_palette.png")
    metres_per_raw_px = float(meta["camera_size"]) / float(meta["render_px"])
    pixel_size = metres_per_raw_px / scale
    foot_offset = int(round((y1 - ref_bottom) * scale)) + PAD
    write_tres_v2(out_dir, char, (fw, fh), dirs, anims_out, pixel_size, foot_offset, ints, len(tables))
    print("%s [v2]: atlas %dx%d (%d bytes png, %d raw), palette %d entries x %d variants, frame box %dx%d, "
          "%d frames (%d missing), pixel_size %.5f, height %d"
          % (char, width, height_px, os.path.getsize(png), atlas.size, pos, len(tables), fw, fh, len(keys),
             missing, pixel_size, int(round(dh))))


def write_tres_v2(out_dir, char, frame_size, dirs, anims, pixel_size, foot_offset, ints, variants):
    anims_text = ", ".join(
        '"%s": {"start": %d, "frames": %d, "fps": %.1f, "loop": %s}'
        % (k, v["start"], v["frames"], v["fps"], "true" if v["loop"] else "false") for k, v in anims.items())
    text = (
        '[gd_resource type="Resource" script_class="SpriteSheetData" load_steps=4 format=3]\n\n'
        '[ext_resource type="Script" path="res://src/rendering/sprite_sheet_data.gd" id="1_script"]\n'
        '[ext_resource type="Texture2D" path="%s" id="2_tex"]\n'
        '[ext_resource type="Texture2D" path="%s" id="3_pal"]\n\n'
        '[resource]\nscript = ExtResource("1_script")\ntexture = ExtResource("2_tex")\npalette = ExtResource("3_pal")\n'
        'variants = %d\nframe_size = Vector2i(%d, %d)\nframes = PackedInt32Array(%s)\ndirections = %d\n'
        'anims = {%s}\npixel_size = %.6f\nfoot_offset_px = %d\n'
    ) % (res_path(out_dir, char + ".png"), res_path(out_dir, char + "_palette.png"), variants,
         frame_size[0], frame_size[1], ", ".join(map(str, ints)), dirs, anims_text, pixel_size, foot_offset)
    with open(os.path.join(out_dir, char + ".tres"), "w") as fh:
        fh.write(text)


def res_path(out_dir, name):
    rel = os.path.relpath(os.path.join(out_dir, name), os.getcwd()).replace(os.sep, "/")
    if rel.startswith(".."):
        return name
    return "res://" + rel


def write_tres(out_dir, char, frame_size, dirs, anims, pixel_size, foot_offset, out_root):
    def anim_text(a):
        return '{"row": %d, "frames": %d, "fps": %.1f, "loop": %s}' % (
            a["row"], a["frames"], a["fps"], "true" if a["loop"] else "false")

    anims_text = ", ".join('"%s": %s' % (k, anim_text(v)) for k, v in anims.items())
    text = (
        '[gd_resource type="Resource" script_class="SpriteSheetData" load_steps=3 format=3]\n\n'
        '[ext_resource type="Script" path="res://src/rendering/sprite_sheet_data.gd" id="1_script"]\n'
        '[ext_resource type="Texture2D" path="%s" id="2_tex"]\n\n'
        '[resource]\n'
        'script = ExtResource("1_script")\n'
        'texture = ExtResource("2_tex")\n'
        'frame_size = Vector2i(%d, %d)\n'
        'directions = %d\n'
        'anims = {%s}\n'
        'pixel_size = %.6f\n'
        'foot_offset_px = %d\n'
    ) % (res_path(out_dir, char + ".png"), frame_size[0], frame_size[1], dirs, anims_text,
         pixel_size, foot_offset)
    with open(os.path.join(out_dir, char + ".tres"), "w") as fh:
        fh.write(text)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--raw", default="build/sprites_raw")
    ap.add_argument("--out", default="assets/sprites")
    ap.add_argument("--height", type=int, default=0, help="override meta height_px (up to 200)")
    ap.add_argument("--no-hueshift", action="store_true", help="keep ramp end hues as clustered")
    ap.add_argument("--contrast", type=float, default=1.1, help="palette lightness contrast (1 = off)")
    ap.add_argument("--no-cleanup", action="store_true")
    ap.add_argument("--allow-missing", action="store_true", help="v2: missing frames become empty")
    ap.add_argument("chars", nargs="*")
    args = ap.parse_args()
    chars = args.chars or sorted(d for d in os.listdir(args.raw)
                                 if os.path.isfile(os.path.join(args.raw, d, "meta.json")))
    if not chars:
        print("no characters found in %s" % args.raw)
        return 1
    for c in chars:
        process(c, args.raw, args.out, args.height or None, not args.no_hueshift, args.contrast,
                not args.no_cleanup, args.allow_missing)
    return 0


if __name__ == "__main__":
    sys.exit(main())
