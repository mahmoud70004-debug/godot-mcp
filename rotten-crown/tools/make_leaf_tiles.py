#!/usr/bin/env python3
"""V23 leaf tiles: individual, shaded, interlocking leaves (not a pixel mass).

A tile is a ragged disc of ~150 real leaf shapes (pointed lens, midrib, a lit and a shaded half)
painted back to front on a 64x64 grid shown 2x2 per texel in the 128 px tile. What makes it read as
foliage and not as a coloured blob:
- DEPTH: every leaf has a depth; the deeper, the darker (ambient occlusion of the clump), so the
  surface leaves are lit and the inside is a dark cavity seen through the gaps;
- CONTACT SHADOWS: each leaf drops a soft shadow (offset away from the light) on the leaves under
  it, which separates every layer and gives the clusters their interlocking;
- PER-LEAF LIGHT: a gradient across each leaf from its lit edge (upper left, where the moon hits)
  to its shaded edge, a lighter midrib, a rim highlight on the lit side;
- COLOUR: every leaf its own tone (cool dark green to yellow-green), so neighbours never merge;
- NORMALS: each leaf is a tilted plane folded along its midrib, so in the game the moon catches
  every leaf at its own angle (the normal map follows the same leaves).

  python3 tools/make_leaf_tiles.py

Writes assets/textures/forest_src/leaf_mass_{a,b,c,d}.png and _n.png (RGBA 128x128, hard alpha).
"""
import pathlib

import numpy as np
from PIL import Image

OUT = pathlib.Path(__file__).resolve().parent.parent / "assets" / "textures" / "forest_src"
N = 64
SCALE = 2
LIGHT = np.array([-0.62, -0.78])  # towards the light on the tile (upper left)

# name: (seed, leaves, length range, hole share, palette dark, palette lit, rim)
VARIANTS = {
    "a": (11, 260, (6.0, 10.0), 0.08, (0.14, 0.22, 0.17), (0.86, 1.0, 0.62)),
    "b": (23, 210, (5.5, 9.0), 0.14, (0.17, 0.16, 0.11), (0.95, 0.82, 0.42)),
    "c": (37, 240, (6.5, 10.5), 0.07, (0.16, 0.22, 0.15), (0.80, 0.90, 0.60)),
    "d": (41, 260, (5.5, 9.5), 0.10, (0.13, 0.21, 0.19), (0.78, 1.0, 0.76)),
}


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def make(seed, count, length, holes, dark, lit):
    rng = np.random.default_rng(seed)
    dark, lit = np.array(dark), np.array(lit)
    yy, xx = np.mgrid[0:N, 0:N] + 0.5
    col = np.zeros((N, N, 3))
    alpha = np.zeros((N, N), bool)
    nrm = np.zeros((N, N, 3))
    nrm[..., 2] = 1.0
    # Leaves back to front: depth 0 (deep) .. 1 (surface).
    leaves = []
    for k in range(count):
        r = 14.8 * np.sqrt(rng.random()) ** 1.1 * (N / 32) / 2 * 2
        r = 30.0 * np.sqrt(rng.random()) ** 1.12
        a = rng.random() * 2 * np.pi
        leaves.append((rng.random(), N / 2 + r * np.cos(a), N / 2 + r * np.sin(a), rng.uniform(*length), rng.random() * np.pi))
    leaves.sort(key=lambda t: t[0])
    for depth, cx, cy, L, th in leaves:
        W = L * rng.uniform(0.46, 0.64)
        c, s = np.cos(th), np.sin(th)
        dx, dy = xx - cx, yy - cy
        u = dx * c + dy * s  # along the leaf
        v = -dx * s + dy * c  # across
        t = u / (L * 0.5)
        shape = (1 - np.clip(t, -1, 1) ** 2) ** 0.85  # pointed ends, fullest in the middle
        wv = W * 0.5 * shape
        m = (np.abs(t) <= 1.0) & (np.abs(v) <= wv) & (wv > 0.25)
        if not m.any():
            continue
        # Contact shadow on whatever is already there (away from the light, softly).
        sh = np.roll(np.roll(m, int(round(-LIGHT[0] * 2.2)), axis=1), int(round(-LIGHT[1] * 2.2)), axis=0)
        sh &= ~m & alpha
        col[sh] *= 0.5
        # Colour: depth (occlusion) x the leaf's own tone x a gradient across it, lit side up-left.
        own = rng.random()
        base = dark + (lit - dark) * (0.15 + 0.85 * own * (0.35 + 0.65 * depth))
        occl = 0.44 + 0.56 * depth ** 0.9
        to_light = (dx * LIGHT[0] + dy * LIGHT[1]) / max(L * 0.5, 1.0)  # -1 away .. 1 towards light
        grad = 0.78 + 0.34 * np.clip(to_light, -1, 1)
        shade = occl * grad
        rib = np.abs(v) < 0.55
        shade = np.where(rib, shade * 1.22, shade)
        # Rim highlight on the lit edge, dark line on the far edge: the leaf has thickness.
        edge = np.clip(1.0 - np.abs(v) / np.maximum(wv, 0.01), 0, 1)
        lit_side = (v * (-s * LIGHT[0] + c * LIGHT[1]) > 0)
        shade = np.where(m & (edge < 0.22) & lit_side, shade * 1.28, shade)
        shade = np.where(m & (edge < 0.22) & ~lit_side, shade * 0.72, shade)
        rgb = base[None, None, :] * shade[..., None] * (1.0 + (rng.random() - 0.5) * 0.18)
        col[m] = np.clip(rgb[m], 0, 1)
        alpha |= m
        # Normal: the leaf is a plane tilted at random, folded along the midrib.
        tilt = rng.normal(0, 0.42, 2)
        fold = 0.38 * np.sign(v)
        px = np.cos(th + np.pi / 2) * fold
        py = np.sin(th + np.pi / 2) * fold
        nx = tilt[0] + px
        ny = tilt[1] + py
        n3 = np.stack([nx, ny, np.ones_like(nx) * 1.0], -1)
        n3 /= np.linalg.norm(n3, axis=-1, keepdims=True)
        nrm[m] = n3[m]
    # Ragged silhouette and the holes: noise-thresholded, the middle stays closed.
    rr = np.hypot(xx - N / 2, yy - N / 2) / (N / 2)
    alpha &= rr < 0.985
    g = rng.random((N // 8, N // 8))
    g = np.kron(g, np.ones((8, 8))) * 0.5 + rng.random((N, N)) * 0.5
    k = np.array([0.25, 0.5, 0.25])
    for axis in (0, 1):
        g = np.apply_along_axis(lambda a: np.convolve(np.pad(a, 1, mode="wrap"), k, mode="valid"), axis, g)
    cut = np.quantile(g[alpha], holes)
    alpha &= (g > cut) | (rr < 0.25)
    # Drop stray single texels.
    p = np.pad(alpha, 1)
    nb = p[:-2, 1:-1].astype(int) + p[2:, 1:-1] + p[1:-1, :-2] + p[1:-1, 2:]
    alpha &= nb >= 1
    return col, alpha, nrm


def finish(col, alpha, nrm):
    rgba = np.zeros((N, N, 4))
    rgba[..., :3] = col
    # Transparent texels take the nearest leaf colour (no dark fringes under filtering).
    filled = alpha.copy()
    out = col.copy()
    for _ in range(8):
        if filled.all():
            break
        pad = np.pad(out, ((1, 1), (1, 1), (0, 0)), mode="edge")
        fpad = np.pad(filled, 1, mode="edge")
        for dy, dx in ((0, 1), (2, 1), (1, 0), (1, 2)):
            take = ~filled & fpad[dy:dy + N, dx:dx + N]
            out[take] = pad[dy:dy + N, dx:dx + N][take]
            filled = filled | take
    rgba[..., :3] = out
    rgba[..., 3] = alpha
    n = nrm * 0.5 + 0.5
    n[~alpha] = (0.5, 0.5, 1.0)
    return rgba, np.concatenate([n, alpha[..., None].astype(float)], -1)


def save(arr, path):
    img = Image.fromarray(np.round(arr * 255).astype(np.uint8), "RGBA")
    img.resize((N * SCALE, N * SCALE), Image.NEAREST).save(path)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    tiles = []
    for name, (seed, count, length, holes, dark, lit) in VARIANTS.items():
        col, alpha, nrm = make(seed, count, length, holes, dark, lit)
        rgba, nrgba = finish(col, alpha, nrm)
        save(rgba, OUT / f"leaf_mass_{name}.png")
        save(nrgba, OUT / f"leaf_mass_{name}_n.png")
        lum = (col[alpha] @ np.array([0.2126, 0.7152, 0.0722])).mean()
        print(f"leaf_mass_{name}: {int(alpha.sum())}/{N * N} opaque, mean luma {lum:.3f}")
        tiles.append(rgba)
    sheet = np.concatenate(tiles, 1)
    bg = np.zeros_like(sheet[..., :3])
    bg[:] = (0.04, 0.06, 0.13)
    prev = sheet[..., :3] * sheet[..., 3:] + bg * (1 - sheet[..., 3:])
    pth = OUT.parent.parent.parent / "build" / "leaf_tiles_preview.png"
    pth.parent.mkdir(exist_ok=True)
    Image.fromarray(np.round(prev * 255).astype(np.uint8)).resize((N * 4 * 4, N * 4), Image.NEAREST).save(pth)


if __name__ == "__main__":
    main()
