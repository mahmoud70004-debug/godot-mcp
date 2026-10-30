"""Blender renders -> pixel art at the game's density (stylize.RES px per world px).

A render made at 4 px per world pixel is reduced to RES with an area filter, sharpened,
reduced to a palette of its own most important colours (k-means), given crisp alpha and
a selective dark contour (a darker shade of the neighbouring colour, never flat black),
which is what makes a 3D model read as hand-placed pixels.
"""
import numpy as np
import cv2
from PIL import Image, ImageFilter
from stylize import RES


def pixelize(path, colours=40, src_px=4):
    im = Image.open(path).convert("RGBA")
    w, h = im.size
    tw, th = w * RES // src_px, h * RES // src_px
    small = im.convert("RGBa").resize((tw, th), Image.LANCZOS).convert("RGBA")
    small = small.filter(ImageFilter.UnsharpMask(radius=1.2, percent=70, threshold=2))
    a = np.array(small)
    alpha = a[..., 3] >= 120
    px = a[alpha][:, :3].astype(np.float32)
    k = min(colours, max(2, len(px) // 20))
    crit = (cv2.TERM_CRITERIA_EPS + cv2.TERM_CRITERIA_MAX_ITER, 30, 0.5)
    _, labels, centres = cv2.kmeans(px, k, None, crit, 3, cv2.KMEANS_PP_CENTERS)
    q = centres[labels.flatten()].astype(np.uint8)
    out = np.zeros_like(a)
    out[alpha, :3] = q
    out[alpha, 3] = 255
    # selective contour: transparent pixels touching the house take a dark shade of it
    m = alpha.astype(np.uint8)
    ring = cv2.dilate(m, np.ones((3, 3), np.uint8)) & (1 - m)
    blur = cv2.blur(out[..., :3].astype(np.float32) * m[..., None], (3, 3))
    cnt = cv2.blur(m.astype(np.float32), (3, 3))[..., None]
    shade = (blur / np.maximum(cnt, 1e-3) * 0.38).astype(np.uint8)
    out[ring > 0, :3] = shade[ring > 0]
    out[ring > 0, 3] = 235
    return Image.fromarray(out, "RGBA")
