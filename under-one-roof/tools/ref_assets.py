"""World sprites cut from the art reference (buildings, trees, boats, props).

Runs extract_ref.cut on the reference, upscales each cut-out to RES x and registers it in
the sprite metadata. Collision footprints follow the silhouette (a few horizontal bands of
the lower part of the sprite), so players walk around buildings the way they look.
Flipped / re-tinted variants give the village variety without new drawing styles.
"""
import os
import numpy as np
from PIL import Image, ImageOps, ImageEnhance
from extract_ref import OBJECTS, POLYS, FLAT, load_reference, cut, cut_poly
from stylize import upscale_ref, RES

# kind, door x as a fraction of the width (None = no door), footprint start (fraction of height)
META = {
    "inn": ("building", 0.62, 0.50),
    "market": ("building", 0.47, 0.62),
    "longhouse": ("building", None, 0.45),
    "cabin_a": ("building", 0.40, 0.55),
    "cabin_b": ("building", 0.52, 0.55),
    "cabin_c": ("building", 0.45, 0.55),
    "cabin_d": ("building", 0.52, 0.55),
    "thatch": ("building", 0.50, 0.62),
    "gazebo": ("building", None, 0.55),
    "manor": ("building", 0.44, 0.40),
    "carriage": ("prop", None, 0.55),
    "fountain": ("prop", None, 0.0),
    "ruin": ("prop", None, 0.45),
    "stump": ("prop", None, 0.4),
    "oak_a": ("tree", None, None),
    "oak_b": ("tree", None, None),
    "oak_c": ("tree", None, None),
    "pine_a": ("tree", None, None),
    "pine_b": ("tree", None, None),
    "boat_a": ("boat", None, None),
    "boat_b": ("boat", None, None),
    "boat_c": ("boat", None, None),
    "boat_d": ("boat", None, None),
}

# extra variants: new name -> (source, flip, brightness, colour)
VARIANTS = {
    "cabin_a_f": ("cabin_a", True, 1.0, 1.0),
    "cabin_b_f": ("cabin_b", True, 1.0, 1.0),
    "cabin_c_f": ("cabin_c", True, 1.0, 1.0),
    "cabin_d_f": ("cabin_d", True, 1.0, 1.0),
    "cabin_warm": ("cabin_c", False, 1.08, 1.25),       # repaired Ashford home
    "cabin_old": ("cabin_b", False, 0.82, 0.55),        # the abandoned farmhouse
    "longhouse_f": ("longhouse", True, 0.95, 1.0),
    "thatch_f": ("thatch", True, 1.0, 1.0),
    "oak_a_f": ("oak_a", True, 0.95, 1.0),
    "oak_b_f": ("oak_b", True, 1.04, 1.0),
    "oak_c_f": ("oak_c", True, 0.92, 1.05),
    "pine_a_f": ("pine_a", True, 1.0, 1.0),
    "pine_b_f": ("pine_b", True, 0.95, 1.0),
    "boat_a_f": ("boat_a", True, 1.0, 1.0),
    "boat_d_f": ("boat_d", True, 1.0, 1.0),
}


def footprint(alpha, start_frac, door_x):
    """Collision rects (world px) following the silhouette below start_frac * height."""
    h, w = alpha.shape
    y0 = int(h * start_frac)
    rects = []
    band = 8
    bottom = h - 3
    for y in range(y0, bottom, band):
        yb = min(bottom, y + band)
        cols = np.where((alpha[y:yb] > 128).mean(axis=0) > 0.5)[0]
        if len(cols) < 4:
            continue
        x0, x1 = int(cols.min()) + 2, int(cols.max()) - 2
        if x1 - x0 < 4:
            continue
        rects.append([x0, y, x1 - x0, yb - y])
    # merge equal-ish consecutive rects
    merged = []
    for r in rects:
        if merged and abs(merged[-1][0] - r[0]) <= 3 and abs((merged[-1][0] + merged[-1][2]) - (r[0] + r[2])) <= 3:
            m = merged[-1]
            m[3] = r[1] + r[3] - m[1]
            m[0] = min(m[0], r[0])
            m[2] = max(m[0] + m[2], r[0] + r[2]) - m[0]
        else:
            merged.append(r)
    return merged


def trunk(alpha):
    """Small collision rect around a tree trunk (bottom-most opaque columns)."""
    h, w = alpha.shape
    rows = np.where((alpha > 128).any(axis=1))[0]
    yb = int(rows.max())
    cols = np.where(alpha[max(0, yb - 6):yb + 1] > 128)[1]
    cx = int(np.median(cols)) if len(cols) else w // 2
    return [[cx - 6, yb - 6, 12, 6]], yb


def register(reg_fn, out_dir):
    """Cuts, upscales and registers every reference sprite. reg_fn(name, image, meta)."""
    import cv2
    ref = load_reference()
    base_imgs = {}
    for name, box in OBJECTS.items():
        try:
            base_imgs[name] = cut(ref, name, box)
        except ValueError:
            pass
    for name, (kind, spec, rw) in POLYS.items():
        base_imgs[name] = cut_poly(ref, name, kind, spec, rw)
    for vname, (src, flip, bright, colour) in VARIANTS.items():
        im = base_imgs[src]
        if flip:
            im = ImageOps.mirror(im)
        rgb, a = im.convert("RGB"), im.getchannel("A")
        rgb = ImageEnhance.Brightness(rgb).enhance(bright)
        rgb = ImageEnhance.Color(rgb).enhance(colour)
        im = rgb.convert("RGBA")
        im.putalpha(a)
        base_imgs[vname] = im
        src_meta = META[src]
        door = src_meta[1]
        META[vname] = (src_meta[0], (1 - door) if (door is not None and flip) else door, src_meta[2])
    for name, im in base_imgs.items():
        kind, door_f, start = META[name]
        w, h = im.size
        alpha = np.array(im.getchannel("A"))
        meta = {"w": w, "h": h, "res": RES}
        if kind == "building":
            meta["bases"] = footprint(alpha, start, door_f)
            meta["oy"] = h - 3
            meta["shadow"] = [w * 0.5, h - 6, w * 0.95, 26]
            if door_f is not None:
                meta["door"] = [int(w * door_f), h - 3]
        elif kind == "prop":
            meta["bases"] = footprint(alpha, start, None) if start else [[2, 2, w - 4, h - 4]]
            meta["oy"] = h - 2
            meta["shadow"] = [w * 0.5, h - 3, w * 0.9, 12]
        elif kind == "tree":
            meta["bases"], yb = trunk(alpha)
            meta["oy"] = yb
            meta["shadow"] = [w * 0.55, yb - 4, w * 0.95, h * 0.35]
            meta["tree"] = True
        elif kind == "boat":
            meta["oy"] = h - 2
            meta["reflect"] = True
        reg_fn("ref_" + name, upscale_ref(im), meta)
    # flat pieces: rectangular crops with soft edges, drawn under everything, walkable
    for name, (x0, y0, x1, y1) in FLAT.items():
        rgb = cv2.cvtColor(ref[y0:y1, x0:x1], cv2.COLOR_BGR2RGB)
        h, w = rgb.shape[:2]
        a = np.full((h, w), 255, np.float32)
        ramp = np.minimum.outer(np.minimum(np.arange(h), np.arange(h)[::-1]), np.minimum(np.arange(w), np.arange(w)[::-1]))
        a = np.clip(ramp / 3.0, 0, 1) * 255
        im = Image.fromarray(np.dstack([rgb, a.astype(np.uint8)]), "RGBA")
        reg_fn("ref_" + name, upscale_ref(im), {"w": w, "h": h, "res": RES, "oy": h - 2, "flat": True})
    return list(base_imgs) + list(FLAT)
