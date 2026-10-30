"""Cuts the family character sheet (assets/reference/family_reference.jpg) into frames.

The sheet is a grid of cells on a cream checkerboard. Every cell is segmented on its
own: pixels far from the light background palette (in Lab) are the figure; holes the
dark contour encloses (faces, aprons) are filled; the grey floor shadow under the feet
is dropped (the game draws its own). Returns RGBA crops trimmed to the figure.

CELLS lists every cell as (name, box) in sheet pixels; names are <character>_<n>.
"""
import os
import numpy as np
import cv2
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
SHEET = os.path.join(os.path.dirname(HERE), "assets", "reference", "family_reference.jpg")


def _grid(prefix, xs, ys):
    out = []
    for r in range(len(ys) - 1):
        for c in range(len(xs) - 1):
            out.append((f"{prefix}_{r}{c}", (xs[c], ys[r], xs[c + 1], ys[r + 1])))
    return out


CELLS = (
    _grid("son", [695, 770, 846, 921, 996, 1071, 1147], [216, 320, 407, 490])
    + _grid("auntA", [45, 124, 203], [216, 320, 407])
    + [("auntA_20", (45, 407, 203, 490))]
    + _grid("mother", [342, 420, 498], [216, 320, 407])
    + [("mother_20", (342, 407, 498, 490))]
    + _grid("grand", [560, 620, 681], [216, 320])
    + [("grand_10", (560, 320, 681, 410)), ("grand_20", (560, 410, 681, 492))]
    + _grid("aunt", [45, 126, 207, 288], [590, 680, 768])
    + _grid("father", [345, 460, 575], [590, 768])
    + _grid("teen", [645, 712, 777, 875], [593, 680, 768])
    + [("teen_read", (882, 642, 960, 762))]
    + _grid("sister", [1002, 1090, 1178, 1265], [590, 680, 768])
)


LINE_LAB = cv2.cvtColor(np.uint8([[[166, 148, 121]]]), cv2.COLOR_RGB2LAB)[0, 0].astype(np.float32)


def background_palette(lab):
    L, a, b = lab[..., 0], lab[..., 1], lab[..., 2]
    cand = (L > 175) & (np.abs(a - 128) < 12) & (b > 128) & (b < 160)
    s = lab[cand][::40].astype(np.float32)
    _, _, cent = cv2.kmeans(s, 6, None, (cv2.TERM_CRITERIA_EPS + cv2.TERM_CRITERIA_MAX_ITER, 50, 0.5), 4,
                            cv2.KMEANS_PP_CENTERS)
    return cent


def load():
    im = np.array(Image.open(SHEET).convert("RGB"))
    lab = cv2.cvtColor(im, cv2.COLOR_RGB2LAB).astype(np.float32)
    cent = background_palette(lab)
    dist = np.min(np.linalg.norm(lab[:, :, None, :] - cent[None, None], axis=3), axis=2)
    return im, lab, dist


def cut_cell(im, lab, dist, box, inset=4):
    x0, y0, x1, y1 = box[0] + inset, box[1] + inset, box[2] - inset, box[3] - inset
    rgb = im[y0:y1, x0:x1]
    L = lab[y0:y1, x0:x1, 0]
    ch = np.hypot(lab[y0:y1, x0:x1, 1] - 128, lab[y0:y1, x0:x1, 2] - 128)
    fg = (dist[y0:y1, x0:x1] > 18).astype(np.uint8)
    # grid lines: tan, thin (< 5 px), straight and long - removed by colour and shape
    tan = (np.linalg.norm(lab[y0:y1, x0:x1] - LINE_LAB, axis=2) < 24).astype(np.uint8)
    lines = np.zeros_like(tan)
    for k_long, k_thick in (((22, 1), (22, 6)), ((1, 22), (6, 22))):
        run = cv2.morphologyEx(tan, cv2.MORPH_OPEN, cv2.getStructuringElement(cv2.MORPH_RECT, k_long))
        thick = cv2.morphologyEx(tan, cv2.MORPH_OPEN, cv2.getStructuringElement(cv2.MORPH_RECT, k_thick))
        lines |= run & (1 - thick)
    lines = cv2.dilate(lines, np.ones((3, 3), np.uint8))
    fg &= (1 - lines)
    # floor shadow: soft, low-chroma grey-beige below the figure
    shadow = (ch < 16) & (L > 120) & (L < 200)
    fg = cv2.morphologyEx(fg, cv2.MORPH_CLOSE, np.ones((2, 2), np.uint8))
    n, lbl, stats, _ = cv2.connectedComponentsWithStats(fg, 8)
    if n <= 1:
        raise ValueError("empty cell")
    big = max(range(1, n), key=lambda i: stats[i, cv2.CC_STAT_AREA])
    keep = np.zeros_like(fg)
    bx, by, bw, bh = stats[big, :4]
    for i in range(1, n):
        sx, sy, sw, sh, area = stats[i]
        near = sx < bx + bw + 30 and sx + sw > bx - 30 and sy < by + bh + 6 and sy + sh > by - 2
        if i == big or (area >= 12 and near):
            keep[lbl == i] = 1
    # fill holes enclosed by the contour
    flood = keep.copy()
    pad = np.pad(flood, 1)
    ff = pad.copy()
    cv2.floodFill(ff, None, (0, 0), 1)
    holes = (ff[1:-1, 1:-1] == 0)
    keep = keep | holes.astype(np.uint8)
    # drop the shadow: shadow-coloured pixels in the lowest part that are not enclosed
    ys, xs = np.where(keep)
    top, bottom = ys.min(), ys.max()
    low = np.zeros_like(keep, bool)
    low[int(bottom - (bottom - top) * 0.22):] = True
    keep[(shadow & low & ~holes)] = 0
    keep = cv2.morphologyEx(keep, cv2.MORPH_OPEN, np.ones((2, 2), np.uint8))
    n, lbl, stats, _ = cv2.connectedComponentsWithStats(keep, 8)
    big = max(range(1, n), key=lambda i: stats[i, cv2.CC_STAT_AREA])
    bx, by, bw, bh = stats[big, :4]
    final = np.zeros_like(keep)
    for i in range(1, n):
        sx, sy, sw, sh, area = stats[i]
        cx, cy = sx + sw / 2, sy + sh / 2
        line = min(sw, sh) <= 3 and max(sw, sh) >= 10
        near = bx - 30 < cx < bx + bw + 30 and sy < by + bh + 4 and sy + sh > by - 2
        if i == big or (area >= 10 and near and not line):
            final[lbl == i] = 1
    # JPEG halo: light background-coloured pixels on the silhouette edge
    d = dist[y0:y1, x0:x1]
    for _ in range(2):
        edge = final.astype(bool) & ~cv2.erode(final, np.ones((3, 3), np.uint8)).astype(bool)
        final[edge & (d < 32) & (L > 165)] = 0
    ys, xs = np.where(final)
    ty0, ty1, tx0, tx1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
    rgba = np.dstack([rgb, final * 255]).astype(np.uint8)[ty0:ty1, tx0:tx1]
    return Image.fromarray(rgba, "RGBA")


def cut_all():
    im, lab, dist = load()
    out = {}
    for name, box in CELLS:
        try:
            out[name] = cut_cell(im, lab, dist, box)
        except ValueError:
            pass
    return out


if __name__ == "__main__":
    import sys
    from PIL import ImageDraw
    dst = sys.argv[1]
    frames = cut_all()
    cols = 10
    cw, chh = 110, 130
    rows = (len(frames) + cols - 1) // cols
    sheet = Image.new("RGBA", (cols * cw, rows * chh), (90, 130, 80, 255))
    d = ImageDraw.Draw(sheet)
    for i, (n, f) in enumerate(frames.items()):
        x, y = (i % cols) * cw, (i // cols) * chh
        sheet.alpha_composite(f, (x + (cw - f.width) // 2, y + 14))
        d.text((x + 2, y + 1), f"{n} {f.width}x{f.height}", fill=(255, 255, 255))
    sheet.save(dst)
