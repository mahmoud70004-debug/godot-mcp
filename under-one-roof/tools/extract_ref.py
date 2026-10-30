"""Cuts world objects (buildings, trees, boats, props) out of the art-direction reference
(assets/reference/world_reference.jpg) as transparent sprites, using OpenCV GrabCut seeded
with a bounding box, then cleans the matte (hole filling, 1px erosion, soft edge).

Outputs assets/sprites/ref_<name>.png at reference scale (1 reference pixel = 1 world pixel).
"""
import os
import cv2
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REF = os.path.join(ROOT, "assets", "reference", "world_reference.jpg")

# name: (x0, y0, x1, y1) box around the object in the reference
OBJECTS = {
    # buildings
    "inn": (731, 0, 1006, 238),
    "market": (1097, 25, 1231, 183),
    "longhouse": (1097, 232, 1231, 338),
    "cabin_a": (828, 437, 924, 574),
    "cabin_b": (913, 336, 1012, 479),
    "cabin_c": (1093, 336, 1192, 467),
    "cabin_d": (1213, 336, 1333, 469),
    "thatch": (524, 237, 646, 399),
    "gazebo": (516, 12, 654, 166),
    "manor": (84, 0, 497, 252),
    # nature
    "oak_a": (296, 133, 480, 296),
    "oak_b": (372, 586, 533, 736),
    "oak_c": (128, 606, 303, 752),

    "ruin": (548, 671, 625, 732),
    "stump": (350, 697, 378, 726),
    # harbour
    "boat_a": (992, 507, 1049, 569),
    "boat_b": (1063, 577, 1100, 650),
    "boat_c": (1201, 584, 1276, 620),
    "boat_d": (1221, 633, 1344, 677),
    "fountain": (100, 148, 172, 196),
}

# extra hints: rectangles that are certainly background inside the box (other objects)
BG_HINTS = {
    "cabin_a": [(828, 520, 840, 574)],
    "carriage": [(430, 400, 455, 432)],
}
# rectangles that are certainly foreground (e.g. a trunk GrabCut tends to drop)
FG_HINTS = {
    "oak_a": [(368, 258, 392, 290)],
    "market": [(1180, 105, 1226, 172)],
}
# polygon cut-outs for objects GrabCut cannot separate (pines against the river):
# name: (polygon, reject-water)
POLYS = {
    "pine_a": ("pine", (641, 603, 664, 688, 618), True),
    "pine_b": ("pine", (771, 626, 794, 682, 748), True),
    "carriage": ("grabcut", [(362, 386), (378, 368), (447, 362), (453, 378), (452, 418), (440, 432), (360, 432)], False),
}


def pine_polygon(apex_x, top, right, bottom, left, tiers=5, seed=0):
    """Jagged, tiered fir silhouette inside the triangle apex/(left,right) at bottom."""
    rng = np.random.default_rng(seed)
    pts_r, pts_l = [], []
    h = bottom - top
    for t in range(tiers):
        y0 = top + h * t / tiers
        y1 = top + h * (t + 1) / tiers
        frac1 = (t + 1) / tiers
        wr = (right - apex_x) * frac1
        wl = (apex_x - left) * frac1
        pts_r += [(apex_x + wr * 0.55, y0 + (y1 - y0) * 0.35), (apex_x + wr * (0.95 + rng.uniform(0, 0.08)), y1)]
        pts_l += [(apex_x - wl * 0.55, y0 + (y1 - y0) * 0.35), (apex_x - wl * (0.95 + rng.uniform(0, 0.08)), y1)]
    return [(apex_x, top)] + pts_r + [(apex_x + 3, bottom + 4), (apex_x - 3, bottom + 4)] + pts_l[::-1]


def cut(img, name, box):
    x0, y0, x1, y1 = box
    pad = 6
    X0, Y0 = max(0, x0 - pad), max(0, y0 - pad)
    X1, Y1 = min(img.shape[1], x1 + pad), min(img.shape[0], y1 + pad)
    crop = img[Y0:Y1, X0:X1].copy()
    mask = np.zeros(crop.shape[:2], np.uint8)
    rect = (x0 - X0, y0 - Y0, x1 - x0, y1 - y0)
    # objects touching the image border: let the box reach the edge
    rect = (max(1, rect[0]), max(1, rect[1]), min(rect[2], crop.shape[1] - rect[0] - 1), min(rect[3], crop.shape[0] - rect[1] - 1))
    bgd, fgd = np.zeros((1, 65), np.float64), np.zeros((1, 65), np.float64)
    cv2.grabCut(crop, mask, rect, bgd, fgd, 6, cv2.GC_INIT_WITH_RECT)
    for (bx0, by0, bx1, by1) in BG_HINTS.get(name, []):
        mask[by0 - Y0:by1 - Y0, bx0 - X0:bx1 - X0] = cv2.GC_BGD
    for (bx0, by0, bx1, by1) in FG_HINTS.get(name, []):
        mask[by0 - Y0:by1 - Y0, bx0 - X0:bx1 - X0] = cv2.GC_FGD
    if name in BG_HINTS or name in FG_HINTS:
        cv2.grabCut(crop, mask, None, bgd, fgd, 3, cv2.GC_INIT_WITH_MASK)
    m = np.where((mask == cv2.GC_FGD) | (mask == cv2.GC_PR_FGD), 255, 0).astype(np.uint8)
    if m.sum() == 0:
        print("  grabcut found nothing for", name)
        m[rect[1]:rect[1] + rect[3], rect[0]:rect[0] + rect[2]] = 255
    # keep the largest connected component, fill holes
    n, lab, stats, _ = cv2.connectedComponentsWithStats(m)
    if n > 1:
        big = 1 + int(np.argmax(stats[1:, cv2.CC_STAT_AREA]))
        m = np.where(lab == big, 255, 0).astype(np.uint8)
    inv = 255 - m
    ff = inv.copy()
    h, w = m.shape
    fmask = np.zeros((h + 2, w + 2), np.uint8)
    for corner in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)):
        if ff[corner[1], corner[0]]:
            cv2.floodFill(ff, fmask, corner, 0)
    m = m | ff
    m = cv2.erode(m, np.ones((2, 2), np.uint8))
    alpha = cv2.GaussianBlur(m, (3, 3), 0)
    rgba = np.dstack([cv2.cvtColor(crop, cv2.COLOR_BGR2RGB), alpha])
    ys, xs = np.where(alpha > 10)
    if len(ys) == 0:
        raise ValueError("empty matte for " + name)
    rgba = rgba[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    return Image.fromarray(rgba)


def cut_poly(img, name, kind, spec, reject_water):
    poly = pine_polygon(*spec) if kind == "pine" else spec
    xs = [p[0] for p in poly]; ys = [p[1] for p in poly]
    X0, Y0, X1, Y1 = int(min(xs)), int(min(ys)), int(max(xs)) + 1, int(max(ys)) + 1
    crop = img[Y0:Y1, X0:X1].copy()
    m = np.zeros(crop.shape[:2], np.uint8)
    cv2.fillPoly(m, [np.array([(x - X0, y - Y0) for x, y in poly], np.int32)], 255)
    if kind == "grabcut":
        gm = np.where(m > 0, cv2.GC_PR_FGD, cv2.GC_BGD).astype(np.uint8)
        bgd, fgd = np.zeros((1, 65), np.float64), np.zeros((1, 65), np.float64)
        cv2.grabCut(crop, gm, None, bgd, fgd, 6, cv2.GC_INIT_WITH_MASK)
        m = np.where((gm == cv2.GC_FGD) | (gm == cv2.GC_PR_FGD), 255, 0).astype(np.uint8)
    if reject_water:
        hsv = cv2.cvtColor(crop, cv2.COLOR_BGR2HSV)
        water = (hsv[..., 0] > 85) & (hsv[..., 0] < 110) & (hsv[..., 1] > 60) & (hsv[..., 2] > 150)
        m[water] = 0
    m = cv2.morphologyEx(m, cv2.MORPH_OPEN, np.ones((2, 2), np.uint8))
    alpha = cv2.GaussianBlur(m, (3, 3), 0)
    return Image.fromarray(np.dstack([cv2.cvtColor(crop, cv2.COLOR_BGR2RGB), alpha]))


# painted people standing in front of buildings: removed (inpainted) before cutting
PEOPLE = [(920, 174, 974, 208), (1153, 144, 1175, 186), (1208, 148, 1230, 182), (244, 146, 268, 186)]


def load_reference():
    img = cv2.imread(REF)
    m = np.zeros(img.shape[:2], np.uint8)
    for (x0, y0, x1, y1) in PEOPLE:
        m[y0:y1, x0:x1] = 255
    return cv2.inpaint(img, m, 6, cv2.INPAINT_TELEA)


def build(out_dir):
    img = load_reference()
    sizes = {}
    for name, (kind, spec, rw) in POLYS.items():
        sp = cut_poly(img, name, kind, spec, rw)
        sp.save(os.path.join(out_dir, f"ref_{name}.png"))
        sizes[name] = sp.size
    for name, box in OBJECTS.items():
        try:
            sp = cut(img, name, box)
        except ValueError as e:
            print("FAILED", e)
            continue
        sp.save(os.path.join(out_dir, f"ref_{name}.png"))
        sizes[name] = sp.size
    return sizes


if __name__ == "__main__":
    import sys
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "assets", "sprites")
    print(build(out))
