"""Turns hard-edged procedural sprites into the soft, painted look of the art reference.

painterize(img) -> 4x larger RGBA image:
  1. Scale2x (EPX) twice: rounds stair-stepped diagonals into smooth curves
  2. a light bilateral blur inside colour regions (soft shading, no visible pixels)
  3. fine texture noise and an unsharp mask for crisp, painted edges
The game draws these at 1/4 scale, so their size in the world does not change.
"""
import numpy as np
import cv2
from PIL import Image


def _scale2x(a):
    """EPX/Scale2x on an (h, w, 4) uint8 array."""
    h, w, _ = a.shape
    p = np.pad(a, ((1, 1), (1, 1), (0, 0)), mode="edge")
    A = p[:-2, 1:-1]   # up
    B = p[1:-1, 2:]    # right
    C = p[1:-1, :-2]   # left
    D = p[2:, 1:-1]    # down
    P = a
    eq = lambda x, y: np.all(x == y, axis=2)
    o1 = np.where((eq(C, A) & ~eq(C, D) & ~eq(A, B))[..., None], A, P)
    o2 = np.where((eq(A, B) & ~eq(A, C) & ~eq(B, D))[..., None], B, P)
    o3 = np.where((eq(D, C) & ~eq(D, B) & ~eq(C, A))[..., None], C, P)
    o4 = np.where((eq(B, D) & ~eq(B, A) & ~eq(D, C))[..., None], D, P)
    out = np.zeros((h * 2, w * 2, 4), np.uint8)
    out[0::2, 0::2] = o1
    out[0::2, 1::2] = o2
    out[1::2, 0::2] = o3
    out[1::2, 1::2] = o4
    return out


def painterize(img, seed=0, texture=0.035):
    a = np.array(img.convert("RGBA"))
    a = _scale2x(_scale2x(a))
    rgb = a[..., :3].astype(np.uint8)
    alpha = a[..., 3]
    # soften flat colour regions (edge-preserving)
    rgb = cv2.bilateralFilter(rgb, 5, 28, 3)
    # painted grain
    rng = np.random.default_rng(seed)
    n = rng.normal(0, 255 * texture, rgb.shape[:2]).astype(np.float32)
    n = cv2.GaussianBlur(n, (3, 3), 0)
    rgb = np.clip(rgb.astype(np.float32) + n[..., None], 0, 255)
    # unsharp mask for crisp edges
    blur = cv2.GaussianBlur(rgb, (0, 0), 1.2)
    rgb = np.clip(rgb * 1.45 - blur * 0.45, 0, 255).astype(np.uint8)
    # smooth, slightly feathered silhouette
    al = cv2.GaussianBlur(alpha, (3, 3), 0.8)
    return Image.fromarray(np.dstack([rgb, al]))
