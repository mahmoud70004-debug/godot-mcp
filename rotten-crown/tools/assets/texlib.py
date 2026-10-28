#!/usr/bin/env python3
"""Shared retro texture helpers (PIL + numpy). Used by textures.py and, through the
CLI below, by process_model.py (Blender's python has no PIL).

  python3 texlib.py albedo --diff D.jpg [--ao AO.jpg | --arm ARM.jpg] --px 128 --out O.png [--colors 96] [--alpha] [--wrap]
"""
import argparse

import numpy as np
from PIL import Image, ImageFilter


def _load_gray(path, channel=None):
    im = Image.open(path)
    if channel is not None:
        im = im.convert("RGB").split()[channel]
    else:
        im = im.convert("L")
    return im


def resize(im, px, wrap=False):
    """LANCZOS downscale so the long side is px. wrap=True tiles 3x3 first so a seamless
    texture stays seamless (no edge clamping artefacts)."""
    w, h = im.size
    s = px / float(max(w, h))
    nw, nh = max(8, round(w * s)), max(8, round(h * s))
    if wrap:
        big = Image.new(im.mode, (w * 3, h * 3))
        for ix in range(3):
            for iy in range(3):
                big.paste(im, (ix * w, iy * h))
        big = big.resize((nw * 3, nh * 3), Image.LANCZOS)
        return big.crop((nw, nh, nw * 2, nh * 2))
    return im.resize((nw, nh), Image.LANCZOS)


def albedo(diff, ao=None, arm=None, px=128, colors=0, keep_alpha=False, wrap=False, sharpen=True):
    """diffuse x AO (AO from the arm texture's R channel, else the AO map) -> PIL image."""
    d = Image.open(diff)
    has_a = keep_alpha and ("A" in d.getbands())
    a = d.getchannel("A") if has_a else None
    rgb = d.convert("RGB")
    occ = None
    if arm:
        occ = _load_gray(arm, 0)
    elif ao:
        occ = _load_gray(ao)
    if occ is not None:
        if occ.size != rgb.size:
            occ = occ.resize(rgb.size, Image.LANCZOS)
        f = np.asarray(occ, dtype=np.float32)[..., None] / 255.0
        arr = np.asarray(rgb, dtype=np.float32) * f
        rgb = Image.fromarray(np.clip(arr + 0.5, 0, 255).astype(np.uint8), "RGB")
    rgb = resize(rgb, px, wrap)
    if sharpen:
        rgb = rgb.filter(ImageFilter.UnsharpMask(radius=0.8, percent=60, threshold=2))
    if a is not None:
        a = resize(a, px, wrap)
        rgb.putalpha(a)
    return quantize(rgb, colors)


def quantize(im, colors):
    if colors <= 0:
        return im
    if "A" in im.getbands():
        return im.quantize(colors=colors, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.NONE)
    return im.quantize(colors=colors, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)


def save_png(im, path):
    im.save(path, optimize=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["albedo"])
    ap.add_argument("--diff", required=True)
    ap.add_argument("--ao")
    ap.add_argument("--arm")
    ap.add_argument("--px", type=int, default=128)
    ap.add_argument("--out", required=True)
    ap.add_argument("--colors", type=int, default=0)
    ap.add_argument("--alpha", action="store_true")
    ap.add_argument("--wrap", action="store_true")
    a = ap.parse_args()
    im = albedo(a.diff, a.ao, a.arm, a.px, a.colors, a.alpha, a.wrap)
    save_png(im, a.out)
    print("TEX", a.out, im.size)


if __name__ == "__main__":
    main()
