#!/usr/bin/env python3
"""Aether conifer bough tile (replaces leaf_mass_a in the tree atlas): a whole fir bough seen from above,
drawn at 4x and reduced - a twig along the horizontal midline from the trunk end (left) to the tip (right),
side twigs branching forward on both sides (long near the root, short at the tip), every side twig carrying
two rows of fine needles. Dark at the root and underneath, frosty-pale needle tips on the upper side
(the moon catches them), back to front so the sprays overlap with depth. Hard alpha, 128x128, flat normal.
  python3 tools/make_fir_tile.py
"""
import pathlib

import numpy as np
from PIL import Image, ImageDraw

OUT = pathlib.Path(__file__).resolve().parent.parent / "assets" / "textures" / "forest_src"
N = 128
S = 4  # supersampling
W = N * S


def lerp(a, b, t):
    return a + (b - a) * t


def draw(seed):
    rng = np.random.default_rng(seed)
    img = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    mid = W / 2
    dark = np.array([0.045, 0.11, 0.075])
    green = np.array([0.1, 0.26, 0.16])
    pale = np.array([0.55, 0.82, 0.74])

    def rgba(c):
        return tuple(int(np.clip(v, 0, 1) * 255) for v in c) + (255,)

    # Side twigs, drawn back (lower, shaded) side first so the upper side overlaps.
    twigs = []
    for k in range(34):
        t = (k + rng.random() * 0.6) / 34.0
        for side in (-1, 1):
            twigs.append((t, side, rng.random()))
    twigs.sort(key=lambda a: a[1] * 0.0 + rng.random())
    # The main stem.
    d.line([(0, mid), (W * 0.985, mid)], fill=rgba(dark * 1.4), width=max(2, S))
    for t, side, depth in sorted(twigs, key=lambda a: -a[0]):
        x0 = lerp(0.02, 0.93, t) * W
        reach = lerp(0.44, 0.07, t ** 0.85) * W * (0.85 + 0.3 * rng.random())
        ang = np.deg2rad(lerp(62, 30, t) + rng.normal(0, 5))
        # The twig bows slightly forward.
        pts = []
        for i in range(8):
            u = i / 7
            px = x0 + np.cos(ang) * reach * u + 0.06 * reach * u * u
            py = mid + side * np.sin(ang) * reach * u
            pts.append((px, py))
        d.line(pts, fill=rgba(dark * 1.5), width=max(1, S // 2))
        n_needles = int(reach / (1.9 * S))
        for i in range(2, 8 * 6):
            u = i / (8 * 6)
            idx = min(int(u * 7), 6)
            fx = lerp(pts[idx][0], pts[idx + 1][0], u * 7 - idx)
            fy = lerp(pts[idx][1], pts[idx + 1][1], u * 7 - idx)
            nl = lerp(0.1, 0.035, u) * W * (0.8 + 0.4 * rng.random()) * (0.55 + 0.6 * np.sin(np.pi * min(u * 1.1, 1.0)))
            for s2 in (-1, 1):
                a2 = ang * 0.0 + np.deg2rad(lerp(35, 15, u)) * s2
                # Needles point forward and outward from the twig.
                dirx = np.cos(a2) * 0.9 + 0.35
                diry = np.sin(a2) * 0.9 + side * 0.25 * np.sin(ang)
                nrm = np.hypot(dirx, diry)
                ex, ey = fx + dirx / nrm * nl, fy + diry / nrm * nl * (1 if rng.random() < 0.5 else 0.8)
                upper = (diry * side) > 0 or rng.random() < 0.4
                tip = t * 0.0 + u
                c = lerp(green, pale, (0.15 + 0.7 * tip * rng.random()) * (1.0 if upper else 0.35))
                c = lerp(dark, c, 0.35 + 0.65 * depth)
                d.line([(fx, fy), (ex, ey)], fill=rgba(c * (0.85 + 0.3 * rng.random())), width=max(1, S // 3))
    # The stem's tip: a short upright brush.
    for i in range(14):
        a2 = np.deg2rad(rng.normal(0, 30))
        l = W * (0.04 + 0.05 * rng.random())
        d.line([(W * 0.9, mid), (W * 0.9 + np.cos(a2) * l, mid + np.sin(a2) * l)], fill=rgba(lerp(green, pale, 0.6)), width=max(1, S // 3))
    small = np.asarray(img.resize((N, N), Image.BOX)).astype(float) / 255.0
    return small


def main():
    for name, seed, in (("a", 5),):
        s = draw(seed)
        a = s[..., 3]
        alpha = a > 0.4
        rgb = np.clip(np.where(a[..., None] > 1e-3, s[..., :3] / np.maximum(a[..., None], 1e-3), 0.0), 0.0, 1.0)
        # Edge texels take their neighbour's colour so no dark fringe shows under filtering.
        out = np.zeros((N, N, 4))
        out[..., :3] = rgb
        out[..., 3] = alpha
        filled = alpha.copy()
        for _ in range(6):
            pad = np.pad(out[..., :3], ((1, 1), (1, 1), (0, 0)), mode="edge")
            fpad = np.pad(filled, 1, mode="edge")
            for dy, dx in ((0, 1), (2, 1), (1, 0), (1, 2)):
                take = ~filled & fpad[dy:dy + N, dx:dx + N]
                out[..., :3][take] = pad[dy:dy + N, dx:dx + N][take]
                filled = filled | take
        Image.fromarray(np.round(out * 255).astype(np.uint8), "RGBA").save(OUT / f"leaf_mass_{name}.png")
        nrm = np.zeros((N, N, 4))
        nrm[..., :3] = (0.5, 0.5, 1.0)
        nrm[..., 3] = alpha
        Image.fromarray(np.round(nrm * 255).astype(np.uint8), "RGBA").save(OUT / f"leaf_mass_{name}_n.png")
        print("opaque", int(alpha.sum()), "/", N * N)


if __name__ == "__main__":
    main()
