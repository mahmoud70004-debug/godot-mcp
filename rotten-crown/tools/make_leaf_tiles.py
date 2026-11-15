#!/usr/bin/env python3
"""V18 leaf tiles: pixel-clustered, hole-ridden foliage in the spirit of Minecraft's leaves
(the texture work, not the blocks).

A 32x32 grid of coarse texels, shown 4x4 per texel in a 128 px tile. Each tile is a ragged-edged
disc of overlapping small leaf lobes (2-4 texels), painted back to front so the lobes read as
separate leaves stacked into clusters; every lobe has a lit top-left rim and a darker lower-right
edge (one tone step each), four tones overall. Holes (a fifth of the disc, in clumps of 1-3
texels) let the dark body behind show through, so a clump of cards reads as interlocking foliage
with depth, not a printed sheet. Normal maps come from a height field of domed lobes.

  python3 tools/make_leaf_tiles.py

Writes assets/textures/forest_src/leaf_mass_{a,b,c,d}.png and _n.png (RGBA 128x128, hard alpha;
same names and format as the Blender masses they replace, which tools/blender/trees/
render_tree_textures.py still writes if run again).
"""
import pathlib

import numpy as np
from PIL import Image

OUT = pathlib.Path(__file__).resolve().parent.parent / "assets" / "textures" / "forest_src"
N = 32
SCALE = 4

# name: (seed, lobes, lobe radius range, hole share, edge ragged, tones dark->light)
VARIANTS = {
    "a": (11, 150, (1.7, 3.0), 0.16, 0.22, [(0.17, 0.25, 0.20), (0.27, 0.38, 0.29), (0.38, 0.52, 0.38), (0.52, 0.66, 0.48)]),
    "b": (23, 125, (1.6, 2.7), 0.24, 0.30, [(0.19, 0.22, 0.17), (0.30, 0.34, 0.24), (0.43, 0.46, 0.31), (0.56, 0.58, 0.40)]),
    "c": (37, 140, (1.9, 3.2), 0.14, 0.20, [(0.19, 0.26, 0.19), (0.28, 0.38, 0.26), (0.39, 0.51, 0.34), (0.52, 0.64, 0.44)]),
    "d": (41, 150, (1.5, 2.7), 0.20, 0.26, [(0.15, 0.24, 0.21), (0.25, 0.37, 0.31), (0.36, 0.50, 0.41), (0.49, 0.63, 0.52)]),
}


def lobes(rng, count, radius):
    """Index map (-1 empty), tone map and height map of overlapping leaf lobes, back to front."""
    idx = -np.ones((N, N), int)
    tone = np.zeros((N, N), int)
    height = np.zeros((N, N))
    yy, xx = np.mgrid[0:N, 0:N] + 0.5
    for k in range(count):
        # Centres inside a disc, denser towards the middle so the rim stays lacy.
        r = 14.2 * np.sqrt(rng.random()) ** 1.15
        a = rng.random() * np.tau if hasattr(np, "tau") else rng.random() * 2 * np.pi
        cx, cy = N / 2 + r * np.cos(a), N / 2 + r * np.sin(a)
        rx = rng.uniform(*radius)
        ry = rx * rng.uniform(0.55, 0.85)
        th = rng.random() * np.pi
        dx, dy = xx - cx, yy - cy
        u = dx * np.cos(th) + dy * np.sin(th)
        v = -dx * np.sin(th) + dy * np.cos(th)
        d = (u / rx) ** 2 + (v / ry) ** 2
        m = d <= 1.0
        base = rng.choice([0, 1, 1, 2, 2, 3], p=[0.16, 0.2, 0.2, 0.2, 0.14, 0.1])
        # Lit from the upper left: a lobe's own top-left is a tone lighter, its bottom-right darker.
        light = -(dx + dy) / (rx + ry)
        t = np.clip(base + np.where(light > 0.35, 1, np.where(light < -0.35, -1, 0)), 0, 3)
        # Layer depth: later lobes are in front; the rim of the front lobe is a dark line on what it covers.
        idx[m] = k
        tone[m] = t[m]
        height[m] = (1.0 - d[m]) * 0.8 + k * 0.02
    return idx, tone, height


def make(name, seed, count, radius, holes, ragged, tones):
    rng = np.random.default_rng(seed)
    idx, tone, height = lobes(rng, count, radius)
    yy, xx = np.mgrid[0:N, 0:N] + 0.5
    rr = np.hypot(xx - N / 2, yy - N / 2) / (N / 2)
    alpha = (idx >= 0) & (rr < 0.97 - ragged * rng.random((N, N)) * np.clip(rr * 1.4 - 0.45, 0, 1))
    # Holes: smooth noise thresholded, so they come in clumps of 1-3 texels.
    g = rng.random((N // 4, N // 4))
    g = np.kron(g, np.ones((4, 4)))
    g = 0.55 * g + 0.45 * rng.random((N, N))
    k = np.array([0.25, 0.5, 0.25])
    for axis in (0, 1):
        g = np.apply_along_axis(lambda a: np.convolve(np.pad(a, 1, mode="wrap"), k, mode="valid"), axis, g)
    cut = np.quantile(g[alpha], holes) if alpha.any() else 0
    # The very middle stays closed (the clump's heart) so a card is never see-through at its centre.
    alpha &= (g > cut) | (rr < 0.22)
    # Drop single stray texels (they read as noise), then keep the texel count honest.
    p = np.pad(alpha, 1)
    nb = p[:-2, 1:-1].astype(int) + p[2:, 1:-1] + p[1:-1, :-2] + p[1:-1, 2:]
    alpha &= nb >= 1
    # Depth shade: texels with an open neighbour above-left are rim-lit, those under a hole sit darker.
    col = np.zeros((N, N, 3))
    for t in range(4):
        col[tone == t] = tones[t]
    p = np.pad(alpha, 1)
    under_hole = (~p[:-2, 1:-1]) & alpha
    col[under_hole] = np.clip(col[under_hole] * 1.12, 0, 1)
    over_hole = (~p[2:, 1:-1]) & alpha
    col[over_hole] = col[over_hole] * 0.78
    # Fine per-texel jitter: reads as separate leaves, not flat plates.
    col *= (1.0 + (rng.random((N, N, 1)) - 0.5) * 0.10)
    rgba = np.zeros((N, N, 4))
    rgba[..., :3] = np.clip(col, 0, 1)
    rgba[..., 3] = alpha
    # Transparent texels keep the colour of the nearest leaf (no dark fringes under filtering).
    for _ in range(6):
        e = rgba[..., 3] == 0
        if not e.any():
            break
        pad = np.pad(rgba, ((1, 1), (1, 1), (0, 0)), mode="edge")
        for dy, dx in ((0, 1), (2, 1), (1, 0), (1, 2)):
            nbr = pad[dy:dy + N, dx:dx + N]
            take = e & (nbr[..., 3] > 0) & (rgba[..., 3] == 0)
            rgba[take, :3] = nbr[take, :3]
            rgba[take, 3] = 1e-3
    a_mask = rgba[..., 3] > 0.5
    rgba[..., 3] = np.where(a_mask, 1.0, 0.0)
    # Normal map from the lobes' height field (domed lobes: each leaf catches the moon at its own angle).
    h = np.where(alpha, height, -0.3)
    gx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5
    gy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5
    nx, ny, nz = -gx * 0.9, gy * 0.9, np.ones_like(h)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    nrm = np.stack([nx / ln, ny / ln, nz / ln], -1) * 0.5 + 0.5
    nrm[~alpha] = (0.5, 0.5, 1.0)
    nrgba = np.concatenate([nrm, a_mask[..., None].astype(float)], -1)
    return rgba, nrgba


def save(arr, path):
    img = Image.fromarray(np.round(arr * 255).astype(np.uint8), "RGBA")
    img.resize((N * SCALE, N * SCALE), Image.NEAREST).save(path)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name, (seed, count, radius, holes, ragged, tones) in VARIANTS.items():
        rgba, nrgba = make(name, seed, count, radius, holes, ragged, tones)
        save(rgba, OUT / f"leaf_mass_{name}.png")
        save(nrgba, OUT / f"leaf_mass_{name}_n.png")
        print(f"leaf_mass_{name}: {int((rgba[..., 3] > 0.5).sum())}/{N * N} texels opaque")
    sheet = np.zeros((N * SCALE, N * SCALE * 4, 4))
    for i, name in enumerate(VARIANTS):
        a = np.asarray(Image.open(OUT / f"leaf_mass_{name}.png")).astype(float) / 255
        sheet[:, i * N * SCALE:(i + 1) * N * SCALE] = a
    bg = np.zeros_like(sheet[..., :3])
    bg[:] = (0.05, 0.08, 0.16)
    out = sheet[..., :3] * sheet[..., 3:] + bg * (1 - sheet[..., 3:])
    Image.fromarray(np.round(out * 255).astype(np.uint8)).resize((N * SCALE * 4 * 2, N * SCALE * 2), Image.NEAREST).save(OUT.parent.parent.parent / "build" / "leaf_tiles_preview.png")


if __name__ == "__main__":
    main()
