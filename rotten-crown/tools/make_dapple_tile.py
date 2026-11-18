#!/usr/bin/env python3
"""V26 leaf-dapple tile: how the moonlight breaks up on the forest floor where the baked canopy shade
(MoonShadeBaker) is only partly lit.

A 256x256 seamless grey tile of overlapping leaf silhouettes (pointed lenses, a few sizes, any
direction). Each texel holds the RANK of its leaf coverage (a uniform 0..1 histogram: few leaves over
it = high = a gap), so the shader can ask for "a fraction s lit" with a plain threshold and get gaps
shaped like the leaves, not round blobs: lit where tile > 1 - s. Two copies at different scales and
drifting directions (moonlight_dapple in moonlight.gdshaderinc) move slowly like a canopy in the wind.

  python3 tools/make_dapple_tile.py   ->  assets/textures/world/leaf_dapple.png
"""
import pathlib

import numpy as np
from PIL import Image

OUT = pathlib.Path(__file__).resolve().parent.parent / "assets" / "textures" / "world" / "leaf_dapple.png"
N = 256


def lens(xx, yy, cx, cy, length, width, theta, n=N):
    """Soft coverage (0..1) of one pointed leaf, wrapped so the tile is seamless."""
    out = np.zeros((n, n))
    c, s = np.cos(theta), np.sin(theta)
    for ox in (-n, 0, n):
        for oy in (-n, 0, n):
            dx, dy = xx - cx + ox, yy - cy + oy
            u = (dx * c + dy * s) / (length * 0.5)
            v = (-dx * s + dy * c) / (width * 0.5)
            shape = np.clip(1.0 - u * u, 0.0, 1.0) ** 0.8
            d = np.abs(v) - shape
            out = np.maximum(out, np.clip(0.5 - d * 6.0, 0.0, 1.0) * (np.abs(u) <= 1.0))
    return out


def main():
    rng = np.random.default_rng(2024)
    yy, xx = np.mgrid[0:N, 0:N].astype(float)
    cover = np.zeros((N, N))
    for size, count in ((46.0, 70), (30.0, 150), (18.0, 260)):
        for _ in range(count):
            cx, cy = rng.random() * N, rng.random() * N
            cover += lens(xx, yy, cx, cy, size * rng.uniform(0.8, 1.25), size * rng.uniform(0.32, 0.5), rng.random() * np.pi)
    # A touch of fine noise breaks ties between equal coverage; then rank-equalise.
    cover = cover + rng.random((N, N)) * 0.05
    order = np.argsort(cover.ravel())
    rank = np.empty(N * N)
    rank[order] = np.linspace(0.0, 1.0, N * N)
    tile = 1.0 - rank.reshape(N, N)  # high = few leaves over it = a gap that lets the light through
    OUT.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(np.round(tile * 255).astype(np.uint8), "L").save(OUT)
    print("wrote", OUT.relative_to(OUT.parents[3]), "mean", round(tile.mean(), 3))
    prev = np.round(np.concatenate([tile > t for t in (0.8, 0.6, 0.4, 0.2)], 1) * 255).astype(np.uint8)
    Image.fromarray(prev).save(OUT.parents[3] / "build" / "dapple_preview.png")


if __name__ == "__main__":
    main()
