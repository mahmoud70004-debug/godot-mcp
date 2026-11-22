#!/usr/bin/env python3
"""PROTOTYPE (Aether): a conifer frond tile for the tree atlas (replaces leaf_mass_a): a stem along the
tile's horizontal midline from the trunk end (left) to the tip (right) with rows of angled needles, dark
at the root, frosty-pale at the tips on the upper side, darker below. Hard alpha, 128x128, plus a flat
normal map. Pixel style: drawn with 1 px lines, no antialiasing.
  python3 tools/make_fir_tile.py
"""
import pathlib
import numpy as np
from PIL import Image, ImageDraw

OUT = pathlib.Path(__file__).resolve().parent.parent / "assets" / "textures" / "forest_src"
N = 128


def draw(seed):
    rng = np.random.default_rng(seed)
    img = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    mid = N // 2
    def col(x, up, tipness):
        base = np.array([0.10, 0.19, 0.15]) if up else np.array([0.07, 0.13, 0.11])
        pale = np.array([0.78, 0.92, 0.88]) if up else np.array([0.26, 0.4, 0.36])
        c = base + (pale - base) * tipness
        c = np.clip(c * (1.0 + (rng.random() - 0.5) * 0.18), 0, 1)
        return tuple(int(v * 255) for v in c) + (255,)
    # Side twigs: every ~22 px a longer twig branches off at a shallow angle on each side.
    def needle_row(x0, y0, ang, length, up):
        dx, dy = np.cos(ang), -np.sin(ang) * (1 if up else -1)
        steps = int(length)
        for i in range(steps):
            t = i / max(steps - 1, 1)
            x = x0 + dx * i
            y = y0 + dy * i
            nl = (1.0 - 0.7 * t) * 15 * np.sin(np.pi * min(1.0, (x / N) * 1.05)) ** 0.6 + 3
            if i % 2 == 0:
                for side in (-1, 1):
                    a2 = ang + side * 0.95
                    ex = x + np.cos(a2) * nl
                    ey = y - np.sin(a2) * nl * (1 if up else -1)
                    tip = min(1.0, 0.25 + 0.75 * (i / max(steps - 1, 1)))
                    d.line([(x, y), (ex, ey)], fill=col(x, up, tip * (1.0 if side > 0 else 0.7)), width=2)
        d.line([(x0, y0), (x0 + dx * steps, y0 + dy * steps)], fill=(20, 34, 26, 255), width=2)
    d.line([(1, mid), (N - 2, mid)], fill=(24, 34, 26, 255), width=3)
    for x in range(4, N - 12, 2):
        taper = np.sin(np.pi * min(1.0, x / N * 1.05)) ** 0.6
        l = 20 * taper + 4
        for up in (True, False):
            for k in range(2):
                ang = np.deg2rad(48 + rng.random() * 16)
                ex = x + np.cos(ang) * l
                ey = mid - np.sin(ang) * l * (1 if up else -1)
                tipness = min(1.0, 0.2 + 0.85 * (x / N))
                d.line([(x, mid), (ex, ey)], fill=col(x, up, tipness), width=2)
    for x0 in range(18, N - 30, 24):
        for up in (True, False):
            needle_row(x0, mid, np.deg2rad(32 + rng.random() * 8), 38 + rng.random() * 20 - x0 * 0.12, up)
    a = np.asarray(img).astype(float) / 255
    alpha = (a[..., 3] > 0.5)
    a[..., 3] = alpha
    # Fill transparent texels with the nearest leaf colour (no dark fringes when filtered).
    for _ in range(6):
        pad = np.pad(a, ((1, 1), (1, 1), (0, 0)), mode="edge")
        for dy, dx in ((0, 1), (2, 1), (1, 0), (1, 2)):
            nb = pad[dy:dy + N, dx:dx + N]
            take = (a[..., 3] == 0) & (nb[..., 3] > 0)
            a[take, :3] = nb[take, :3]
            a[take, 3] = 1e-3
    a[..., 3] = np.where(a[..., 3] > 0.5, 1.0, 0.0)
    n = np.zeros_like(a)
    n[..., 0] = 0.5
    n[..., 1] = 0.5
    n[..., 2] = 1.0
    n[..., 3] = a[..., 3]
    return a, n


def main():
    a, n = draw(5)
    Image.fromarray(np.round(a * 255).astype(np.uint8), "RGBA").save(OUT / "leaf_mass_a.png")
    Image.fromarray(np.round(n * 255).astype(np.uint8), "RGBA").save(OUT / "leaf_mass_a_n.png")
    print("opaque", float((a[..., 3] > 0.5).mean()))


if __name__ == "__main__":
    main()
