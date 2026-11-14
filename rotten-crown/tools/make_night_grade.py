#!/usr/bin/env python3
"""Fit the night colour grade (V8) and write it as a 3D LUT strip for retro_post.

The grade is measured, not eyeballed: per-channel tone curves are fitted so an ungraded game frame
(the user's reference pose, rendered with retro_post's own grade switched off) gets the colour
distribution of the user's edited screenshot (.router/ref/v8_reference_edited.png). Warm, saturated
colours (windows, lanterns, fires, the feast) keep their hue: they only follow the luminance curve.

  python3 tools/make_night_grade.py RAW_REF_FRAME.png [--sim OUT_DIR RAW_FRAME.png ...]

Writes assets/textures/post/night_grade_lut.png: 32 slices of 32x32 (x = blue slice * 32 + red,
y = green), sampled by retro_post.gdshader with linear filtering and manual slice interpolation.
"""
import argparse
import pathlib
import sys

import numpy as np
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
REF = ROOT.parent / ".router" / "ref" / "v8_reference_edited.png"
OUT = ROOT / "assets" / "textures" / "post" / "night_grade_lut.png"
N = 32

# Parts of the edited screenshot that are game world, not HUD (bars, joystick, buttons, sword).
REF_RECTS = [(0.0, 0.10, 1.0, 0.58), (0.22, 0.58, 0.55, 1.0), (0.72, 0.58, 0.84, 0.95)]
# Parts of a rendered frame below the region title, without the sword's corner.
SRC_RECTS = [(0.0, 0.30, 1.0, 0.62), (0.0, 0.62, 0.55, 1.0)]

# Warm protection: hue window (degrees) and saturation ramp.
WARM_HUE = (0.0, 58.0)
WARM_SAT = (0.28, 0.5)
WARM_SAT_GAIN = 1.1


def load(path: pathlib.Path) -> np.ndarray:
    return np.asarray(Image.open(path).convert("RGB")).astype(np.float64) / 255.0


def pixels(img: np.ndarray, rects) -> np.ndarray:
    h, w, _ = img.shape
    parts = [img[int(h * y0):int(h * y1), int(w * x0):int(w * x1)].reshape(-1, 3) for x0, y0, x1, y1 in rects]
    return np.concatenate(parts)


def luma(c: np.ndarray) -> np.ndarray:
    return c[..., 0] * 0.2126 + c[..., 1] * 0.7152 + c[..., 2] * 0.0722


def match_curve(src: np.ndarray, ref: np.ndarray) -> np.ndarray:
    """256-entry monotone curve mapping src's distribution onto ref's (CDF matching), smoothed,
    with a gentle shoulder above the source's range so brighter-than-fitted colours keep order."""
    xs = np.linspace(0.0, 1.0, 256)
    qs = np.linspace(0.0, 1.0, 1001)
    sq = np.quantile(src, qs)
    rq = np.quantile(ref, qs)
    curve = np.interp(xs, sq, rq)
    top_in, top_out = sq[-11], rq[-11]  # 99th percentile anchor
    slope = max((rq[-11] - rq[-101]) / max(sq[-11] - sq[-101], 1e-4), 0.15)
    above = xs > top_in
    t = xs[above] - top_in
    # Shoulder: starts at the fitted slope and bends towards white.
    room = 1.0 - top_out
    curve[above] = top_out + room * (1.0 - np.exp(-slope * t / max(room, 1e-4)))
    below = xs < sq[10]
    curve[below] = rq[10] * xs[below] / max(sq[10], 1e-4)
    k = np.exp(-0.5 * (np.arange(-6, 7) / 2.5) ** 2)
    k /= k.sum()
    padded = np.concatenate([np.full(6, curve[0]), curve, np.full(6, curve[-1])])
    curve = np.convolve(padded, k, mode="valid")
    return np.maximum.accumulate(np.clip(curve, 0.0, 1.0))


def hue_sat(c: np.ndarray):
    mx = c.max(-1)
    mn = c.min(-1)
    d = mx - mn
    sat = np.where(mx > 1e-6, d / np.maximum(mx, 1e-6), 0.0)
    r, g, b = c[..., 0], c[..., 1], c[..., 2]
    dd = np.maximum(d, 1e-6)
    h = np.where(mx == r, ((g - b) / dd) % 6.0, np.where(mx == g, (b - r) / dd + 2.0, (r - g) / dd + 4.0)) * 60.0
    return h, sat


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def quantile_map(a: np.ndarray, b: np.ndarray):
    """1D map of a's distribution onto b's: (src knots, dst knots), slope-1 tails."""
    qs = np.linspace(0.0, 1.0, 65)
    x = np.quantile(a, qs)
    y = np.quantile(b, qs)
    x = np.maximum.accumulate(x + np.arange(len(x)) * 1e-6)
    return np.concatenate([[x[0] - 1.0], x, [x[-1] + 1.0]]), np.concatenate([[y[0] - 1.0], y, [y[-1] + 1.0]])


def random_rotations(count: int, seed: int):
    rng = np.random.default_rng(seed)
    rots = [np.eye(3)]
    while len(rots) < count:
        q, _ = np.linalg.qr(rng.normal(size=(3, 3)))
        rots.append(q)
    return rots


class Grade:
    """Iterative distribution transfer (Pitie et al.): repeated 1D quantile matching along rotated
    axes moves the whole 3D colour distribution, so moss stays green and sky stays blue."""

    ITERS = 14
    SEED = 7

    def __init__(self, src: np.ndarray, ref: np.ndarray):
        self.steps = []
        x = src.copy()
        for rot in random_rotations(self.ITERS, self.SEED):
            xp, rp = x @ rot, ref @ rot
            maps = [quantile_map(xp[:, k], rp[:, k]) for k in range(3)]
            self.steps.append((rot, maps))
            x = self._step(x, rot, maps)
        self.lcurve = match_curve(luma(src), luma(ref))

    @staticmethod
    def _step(x: np.ndarray, rot: np.ndarray, maps) -> np.ndarray:
        xp = x @ rot
        xp = np.stack([np.interp(xp[..., k], *maps[k]) for k in range(3)], -1)
        return xp @ rot.T

    def transfer(self, c: np.ndarray) -> np.ndarray:
        x = c.copy()
        for rot, maps in self.steps:
            x = self._step(x, rot, maps)
        return np.clip(x, 0.0, 1.0)

    def apply(self, c: np.ndarray) -> np.ndarray:
        xs = np.linspace(0.0, 1.0, 256)
        cool = self.transfer(c)
        l0 = luma(c)
        l1 = np.interp(l0, xs, self.lcurve)
        warm = c * (l1 / np.maximum(l0, 1e-4))[..., None]
        wl = luma(warm)[..., None]
        warm = np.clip(wl + (warm - wl) * WARM_SAT_GAIN, 0.0, 1.0)
        h, s = hue_sat(c)
        hue_w = smooth(WARM_HUE[0] - 12.0, WARM_HUE[0], h) * (1.0 - smooth(WARM_HUE[1], WARM_HUE[1] + 14.0, h))
        hue_w = np.maximum(hue_w, 1.0 - smooth(0.0, 12.0, 360.0 - h))  # reds just under 360 deg
        w = (hue_w * smooth(WARM_SAT[0], WARM_SAT[1], s) * smooth(0.06, 0.16, c.max(-1)))[..., None]
        return cool * (1.0 - w) + warm * w

    def lut(self) -> np.ndarray:
        v = np.linspace(0.0, 1.0, N)
        r, g, b = np.meshgrid(v, v, v, indexing="ij")  # r, g, b axes
        out = self.apply(np.stack([r, g, b], -1))  # [r, g, b, 3]
        # A light 3D blur keeps the transfer's small kinks out of the gradients.
        k = np.array([0.25, 0.5, 0.25])
        for axis in range(3):
            pad = [(0, 0)] * 4
            pad[axis] = (1, 1)
            o = np.pad(out, pad, mode="edge")
            sl = [slice(None)] * 4
            parts = []
            for i in range(3):
                sl[axis] = slice(i, i + N)
                parts.append(o[tuple(sl)] * k[i])
            out = sum(parts)
        strip = np.zeros((N, N * N, 3))
        for bi in range(N):
            # rows = green, columns = red, slice = blue
            strip[:, bi * N:(bi + 1) * N] = out[:, :, bi].transpose(1, 0, 2)
        return strip


def apply_lut(strip: np.ndarray, c: np.ndarray) -> np.ndarray:
    """Trilinear lookup, as retro_post does it."""
    lut = np.stack([strip[:, b * N:(b + 1) * N] for b in range(N)], 0)  # [b, g, r, 3]
    p = np.clip(c, 0.0, 1.0) * (N - 1)
    i0 = np.floor(p).astype(int)
    i1 = np.minimum(i0 + 1, N - 1)
    f = p - i0
    out = 0.0
    for db in (0, 1):
        for dg in (0, 1):
            for dr in (0, 1):
                w = (f[..., 2] if db else 1 - f[..., 2]) * (f[..., 1] if dg else 1 - f[..., 1]) * (f[..., 0] if dr else 1 - f[..., 0])
                ib = (i1 if db else i0)[..., 2]
                ig = (i1 if dg else i0)[..., 1]
                ir = (i1 if dr else i0)[..., 0]
                out = out + lut[ib, ig, ir] * w[..., None]
    return out


def stats(c: np.ndarray) -> str:
    L = luma(c) * 255.0
    _, s = hue_sat(c)
    p = np.percentile(L, [5, 50, 95])
    m = c.mean(0) * 255.0
    return "lum p5/p50/p95 %3.0f %3.0f %3.0f  meanRGB %3.0f %3.0f %3.0f  sat %.2f" % (*p, *m, s.mean())


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("raw_ref")
    ap.add_argument("--sim", nargs="+", metavar="OUT_DIR FRAME", help="write graded copies of raw frames")
    a = ap.parse_args()
    src = pixels(load(pathlib.Path(a.raw_ref)), SRC_RECTS)
    ref = pixels(load(REF), REF_RECTS)
    g = Grade(src, ref)
    lut = g.lut()
    OUT.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(np.round(lut * 255.0).astype(np.uint8)).save(OUT)
    print(f"make_night_grade: wrote {OUT.relative_to(ROOT)}")
    print("REF        ", stats(ref))
    print("raw pose   ", stats(src))
    print("graded pose", stats(apply_lut(lut, src)))
    if a.sim:
        out_dir = pathlib.Path(a.sim[0])
        out_dir.mkdir(parents=True, exist_ok=True)
        for f in a.sim[1:]:
            img = load(pathlib.Path(f))
            Image.fromarray(np.round(apply_lut(lut, img) * 255.0).astype(np.uint8)).save(out_dir / pathlib.Path(f).name)


if __name__ == "__main__":
    sys.exit(main())
