#!/usr/bin/env python3
"""Pixelizer v2: raw pre-rendered character frames -> pixel-art sprite sheet + SpriteSheetData .tres.

Usage: python3 tools/pixelize_sprites.py [--raw DIR] [--out DIR] [--height PX] [--no-hueshift]
                                         [--contrast F] [--no-cleanup] [chars...]
Raw layout: <raw>/<char>/<anim>_<dir>_<frame>.png + meta.json (see tools/sprite_baker).
Output:     <out>/<char>/<char>.png and <char>.tres   (contract C1)

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
    h, w = crop.shape[:2]
    dw, dh = size
    k = int(np.clip(np.ceil(max(w / dw, h / dh)), 1, 8))
    sub = (np.arange(k) + 0.5) / k
    ys = np.clip(np.floor((np.arange(dh)[:, None] + sub[None]) * h / dh).astype(int), 0, h - 1)
    xs = np.clip(np.floor((np.arange(dw)[:, None] + sub[None]) * w / dw).astype(int), 0, w - 1)
    blk = crop[ys[:, :, None, None], xs[None, None, :, :]]          # dh,k,dw,k,4
    blk = blk.transpose(0, 2, 1, 3, 4).reshape(dh * dw, k * k, 4)
    opaque = blk[..., 3] > 127
    sh = 8 - bits
    q = lut[blk[..., 0] >> sh, blk[..., 1] >> sh, blk[..., 2] >> sh].astype(np.int64)
    p = len(lum)
    n = dh * dw
    flat = (np.arange(n)[:, None] * (p + 1) + np.where(opaque, q + 1, 0)).ravel()
    counts = np.bincount(flat, minlength=n * (p + 1)).reshape(n, p + 1)
    n_op = counts[:, 1:].sum(1)
    col = counts[:, 1:]
    mode = col.argmax(1)
    dl = lum[None, :] - lum[mode][:, None]
    cand = (col > 0) & (col * 1.0 >= KEEP_FRACTION * n_op[:, None]) & (np.abs(dl) >= KEEP_DELTA_L)
    score = np.where(cand, np.abs(dl) * (1.0 + 0.3 * (dl > 0)), -1.0)
    best = score.argmax(1)
    pick = np.where(score[np.arange(n), best] > 0, best, mode)
    idx = np.where(n_op * 2 >= k * k, pick, -1)
    return idx.reshape(dh, dw).astype(np.int16)


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


def cleanup(idx, lum):
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

def process(char, raw_root, out_root, height=None, hue_shift=True, contrast=1.1, do_cleanup=True):
    raw_dir = os.path.join(raw_root, char)
    with open(os.path.join(raw_dir, "meta.json")) as fh:
        meta = json.load(fh)
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
    ap.add_argument("chars", nargs="*")
    args = ap.parse_args()
    chars = args.chars or sorted(d for d in os.listdir(args.raw)
                                 if os.path.isfile(os.path.join(args.raw, d, "meta.json")))
    if not chars:
        print("no characters found in %s" % args.raw)
        return 1
    for c in chars:
        process(c, args.raw, args.out, args.height or None, not args.no_hueshift, args.contrast,
                not args.no_cleanup)
    return 0


if __name__ == "__main__":
    sys.exit(main())
