"""Texture synthesis by image quilting (Efros & Freeman 2001) + seamless wrap.

Used to turn small material samples taken from the art-direction reference
(assets/reference/world_reference.jpg) into large tileable ground textures.
"""
import numpy as np


def _min_cut_vertical(err):
    """Minimum-error vertical seam through an (h, w) error surface."""
    h, w = err.shape
    cost = err.copy()
    for y in range(1, h):
        left = np.r_[np.inf, cost[y - 1, :-1]]
        right = np.r_[cost[y - 1, 1:], np.inf]
        cost[y] += np.minimum(np.minimum(left, cost[y - 1]), right)
    path = np.zeros(h, int)
    path[-1] = int(np.argmin(cost[-1]))
    for y in range(h - 2, -1, -1):
        x = path[y + 1]
        lo, hi = max(0, x - 1), min(w, x + 2)
        path[y] = lo + int(np.argmin(cost[y, lo:hi]))
    mask = np.zeros((h, w), bool)
    for y in range(h):
        mask[y, path[y]:] = True    # True = take the new patch
    return mask


def quilt(sample, size, patch=40, overlap=10, seed=0, candidates=60):
    """sample: (H, W, 3) uint8.  Returns (size, size, 3) uint8."""
    rng = np.random.default_rng(seed)
    s = sample.astype(np.float32)
    H, W, _ = s.shape
    patch = min(patch, H - 1, W - 1)
    overlap = min(overlap, patch // 3)
    step = patch - overlap
    n = (size - overlap) // step + 1
    out = np.zeros((n * step + overlap, n * step + overlap, 3), np.float32)
    for i in range(n):
        for j in range(n):
            y, x = i * step, j * step
            best, best_err = None, np.inf
            for _ in range(candidates):
                sy, sx = rng.integers(0, H - patch + 1), rng.integers(0, W - patch + 1)
                p = s[sy:sy + patch, sx:sx + patch]
                e = 0.0
                if j > 0:
                    e += np.sum((p[:, :overlap] - out[y:y + patch, x:x + overlap]) ** 2)
                if i > 0:
                    e += np.sum((p[:overlap] - out[y:y + overlap, x:x + patch]) ** 2)
                e *= rng.uniform(1.0, 1.15)       # a little randomness avoids obvious repeats
                if e < best_err:
                    best_err, best = e, p
            p = best.copy()
            mask = np.ones((patch, patch), bool)
            if j > 0:
                err = np.sum((p[:, :overlap] - out[y:y + patch, x:x + overlap]) ** 2, axis=2)
                mask[:, :overlap] &= _min_cut_vertical(err)
            if i > 0:
                err = np.sum((p[:overlap] - out[y:y + overlap, x:x + patch]) ** 2, axis=2).T
                mask[:overlap, :] &= _min_cut_vertical(err).T
            region = out[y:y + patch, x:x + patch]
            region[mask] = p[mask]
    return np.clip(out[:size, :size], 0, 255).astype(np.uint8)


def make_tileable(tex, band=48):
    """Cross-fades the texture with a half-shifted copy near its borders so it wraps."""
    t = tex.astype(np.float32)
    h, w, _ = t.shape
    shifted = np.roll(np.roll(t, h // 2, 0), w // 2, 1)
    yy = np.minimum(np.arange(h), h - 1 - np.arange(h))[:, None]
    xx = np.minimum(np.arange(w), w - 1 - np.arange(w))[None, :]
    d = np.minimum(yy, xx).astype(np.float32)
    a = np.clip(d / band, 0, 1)[..., None]           # 1 inside, 0 at the border
    a = a * a * (3 - 2 * a)
    return np.clip(t * a + shifted * (1 - a), 0, 255).astype(np.uint8)
