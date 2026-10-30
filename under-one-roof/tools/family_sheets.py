"""Game sprite sheets for the family, cut from assets/reference/family_reference.jpg.

The reference sheet draws each family member in a handful of poses. Here they are
scaled to the world (one art pixel ~ one world pixel), kept crisp, and laid out in the
game's sheet format (4 columns x 5 rows of FRAME):
  row 0 down, row 1 left, row 2 right, row 3 up  -> idle, step A, idle, step B
  row 4 actions                                   -> 16, 17, 18, 19
Poses the reference does not draw are derived from the closest drawn one:
  "<cell>:A" / ":B"  walking step (one leg lifted, body bob) from a standing pose
  ":flip"            mirrored (left <-> right)
  ":back"            back view from a front view (face and beard covered by hair/hood)
  ":side"            side view from a front view (narrowed)
  ":low"             the same pose 2 px lower (second frame of a tool swing)
"""
import numpy as np
import cv2
from PIL import Image, ImageOps
from extract_family import cut_all, load
from stylize import RES

FRAME_W, FRAME_H = 32, 32            # world px (texture: x RES)
FEET_Y = 31                          # world px from the frame top

# which reference cells make up each game character; height = standing height in world px
FAMILY = {
    # the eldest son -> Gideon
    "son": dict(height=30, front="son_00",
                down=["son_00", "son_21", "son_10", "son_22"],
                right=["son_15:stand", "son_12", "son_15:stand", "son_15"],
                up=["son_20:back", "son_20:back:A", "son_20:back", "son_20:back:B"],
                action=["son_24", "son_24:low", "son_25", "son_23"]),
    # the mother -> Margaret
    "mother": dict(height=30, front="mother_00",
                   down=["mother_00", "mother_00:A", "mother_01", "mother_00:B"],
                   right=["mother_01:side", "mother_01:side:A", "mother_01:side", "mother_01:side:B"],
                   up=["mother_00:back", "mother_00:back:A", "mother_00:back", "mother_00:back:B"],
                   action=["mother_10", "mother_11", "mother_20", "mother_10"]),
    # the little sister -> Clara
    "sister": dict(height=24, front="sister_00",
                   down=["sister_00", "sister_01", "sister_10", "sister_11"],
                   right=["sister_02", "sister_02:A", "sister_02", "sister_02:B"],
                   up=["sister_00:back", "sister_00:back:A", "sister_00:back", "sister_00:back:B"],
                   action=["sister_12", "sister_12", "sister_12", "sister_02"]),
    # the grandfather -> Edmund
    "grand": dict(height=31, front="grand_00", beard=True,
                  down=["grand_00", "grand_00:A", "grand_01", "grand_00:B"],
                  right=["grand_01:flip", "grand_01:flip:A", "grand_01:flip", "grand_01:flip:B"],
                  up=["grand_01:back", "grand_01:back:A", "grand_01:back", "grand_01:back:B"],
                  action=["grand_10", "grand_10:low", "grand_20", "grand_20"]),
    # the father -> Leif the blacksmith (hammer)
    "father": dict(height=32, front="father_00", beard=True,
                   down=["father_00", "father_00:A", "father_00", "father_00:B"],
                   right=["father_00:side", "father_00:side:A", "father_00:side", "father_00:side:B"],
                   up=["father_00:back", "father_00:back:A", "father_00:back", "father_00:back:B"],
                   action=["father_01", "father_01:low", "father_00", "father_01"]),
    # the teenage brother -> Jonas
    "teen": dict(height=29, front="teen_10",
                 down=["teen_10", "teen_01", "teen_00", "teen_02"],
                 right=["teen_11:stand", "teen_11", "teen_11:stand", "teen_11:B"],
                 up=["teen_10:back", "teen_10:back:A", "teen_10:back", "teen_10:back:B"],
                 action=["teen_12", "teen_12", "teen_12", "teen_12"]),
    # the aunt in the yellow oilskin -> the fisherwoman on the beach
    "aunt": dict(height=28, front="aunt_00",
                 down=["aunt_00", "auntA_10", "auntA_00", "auntA_10:flip"],
                 right=["aunt_12", "auntA_11", "aunt_12", "auntA_11:A"],
                 up=["aunt_01", "aunt_11", "auntA_01", "aunt_11:A"],
                 action=["auntA_20", "auntA_20", "auntA_20", "auntA_20"]),
}

# framed head portraits drawn on the reference (inside the wooden frames)
PORTRAITS = {
    "son": (1194, 374, 1262, 444),
    "aunt": (52, 143, 106, 197),
    "mother": (344, 145, 399, 205),
    "grand": (572, 156, 610, 199),
    "father": (348, 523, 404, 579),
    "teen": (647, 523, 705, 579),
    "sister": (1004, 531, 1046, 572),
}

# family member -> game characters using the sheet
CAST = {"son": ["gideon", "gideon_outfit"], "mother": ["margaret"], "sister": ["clara"], "grand": ["edmund"],
        "father": ["leif"], "teen": ["jonas"], "aunt": ["fisher_c"]}


# ---------------------------------------------------------------- pixel helpers
def to_world(img, k):
    """Scale a cut-out to world pixels: premultiplied area filter, crisp alpha."""
    w, h = max(1, round(img.width * k)), max(1, round(img.height * k))
    a = np.array(img.convert("RGBa").resize((w, h), Image.LANCZOS).convert("RGBA"))
    a[..., 3] = np.where(a[..., 3] >= 110, 255, 0)
    return Image.fromarray(a, "RGBA")


def step(img, phase):
    """Walking step from a standing pose: one leg lifted a pixel, body bobs up."""
    a = np.array(img)
    h, w = a.shape[:2]
    hip = int(h * 0.64)
    out = np.zeros((h, w, 4), np.uint8)
    cols = np.where(a[hip:, :, 3].any(axis=0))[0]
    cx = int((cols.min() + cols.max()) / 2) if len(cols) else w // 2
    legs = a[hip:].copy()
    lift = slice(0, cx) if phase == "A" else slice(cx, w)
    lifted = np.zeros_like(legs)
    lifted[:-1, lift] = legs[1:, lift]
    keep = np.ones(w, bool)
    keep[lift] = False
    lifted[:, keep] = legs[:, keep]
    out[hip:] = lifted
    body = a[:hip]
    # body bob: one pixel up, drawn over the legs (the original lowest body row stays,
    # so no gap opens at the hips)
    out[:hip] = np.where(body[..., 3:] > 0, body, out[:hip])
    m = body[1:, :, 3:] > 0
    out[0:hip - 1] = np.where(m, body[1:], out[0:hip - 1])
    return Image.fromarray(out, "RGBA")


def back_view(img, beard=False):
    """Back of the head: face (and beard) painted over with the hair / hood colour."""
    a = np.array(img).astype(np.int32)
    h, w = a.shape[:2]
    head_h = int(h * (0.48 if beard else 0.40))
    r, g, b, al = a[..., 0], a[..., 1], a[..., 2], a[..., 3] > 0
    skin = al & (r > 150) & (r > g + 12) & (g > b) & (r - b > 35)
    skin[head_h:] = False
    ys, xs = np.where(skin)
    if len(ys) == 0:
        return img
    y0, y1, x0, x1 = ys.min(), ys.max(), xs.min(), xs.max()
    if beard:
        y1 = head_h
    hair_rows = a[max(0, y0 - 6):y0 + 1][al[max(0, y0 - 6):y0 + 1]]
    if len(hair_rows) == 0:
        return img
    hair = np.median(hair_rows[:, :3], axis=0)
    out = a.copy()
    lum = (0.3 * r + 0.59 * g + 0.11 * b)
    region = np.zeros_like(al)
    region[y0 - 1:y1 + 2, max(0, x0 - 1):x1 + 2] = True
    region &= al
    shade = 0.82 + 0.25 * np.clip(lum / max(1.0, lum[region].mean()), 0.6, 1.4) * 0.6
    for c in range(3):
        out[..., c] = np.where(region, np.clip(hair[c] * shade, 0, 255), out[..., c])
    # front details of the body (buttons, apron, scarf ends) stay; the outline stays
    return Image.fromarray(out.astype(np.uint8), "RGBA")


def side_view(img):
    a = img.resize((max(1, int(img.width * 0.72)), img.height), Image.NEAREST)
    return a


def lower(img, px=2):
    out = Image.new("RGBA", (img.width, img.height + px), (0, 0, 0, 0))
    out.paste(img, (0, px))
    return out


def outline(img):
    """Thin dark contour like the reference pixel art (on the outside, 1 px)."""
    a = np.array(img)
    al = (a[..., 3] > 0).astype(np.uint8)
    ring = cv2.dilate(al, np.ones((3, 3), np.uint8)) & (1 - al)
    a[ring > 0] = (40, 26, 22, 255)
    return Image.fromarray(a, "RGBA")


# ---------------------------------------------------------------- sheets
def stand(side, front):
    """A calm standing side view: the side pose's upper body over closed legs taken from
    the front standing pose (narrowed), so stopping never freezes mid-stride."""
    s, f = np.array(side), np.array(front)
    hs, hf = int(side.height * 0.6), int(front.height * 0.6)
    legs = Image.fromarray(f[hf:]).resize((max(1, int(front.width * 0.62)), front.height - hf), Image.NEAREST)
    top = s[:hs]
    cols = np.where(top[..., 3].max(axis=0) > 0)[0]
    lower_cols = np.where(top[-4:, :, 3].max(axis=0) > 0)[0]
    cx = int((lower_cols.min() + lower_cols.max()) / 2) if len(lower_cols) else side.width // 2
    h = hs + legs.height
    w = max(side.width, legs.width + 2)
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    out.paste(legs, (int(cx - legs.width / 2), hs), legs)
    out.alpha_composite(Image.fromarray(top), (0, 0))
    return out


def _pose(cells, spec, k, beard, front=None):
    parts = spec.split(":")
    img = to_world(cells[parts[0]], k)
    for p in parts[1:]:
        if p == "stand" and front:
            img = stand(img, to_world(cells[front], k))
            continue
        if p == "flip":
            img = ImageOps.mirror(img)
        elif p == "back":
            img = back_view(img, beard)
        elif p == "side":
            img = side_view(img)
        elif p in ("A", "B"):
            img = step(img, p)
        elif p == "low":
            img = lower(img)
    return img


def _place(frame_img):
    """Feet at FEET_Y, centred on the feet (tools may stick out sideways)."""
    canvas = Image.new("RGBA", (FRAME_W, FRAME_H), (0, 0, 0, 0))
    a = np.array(frame_img)[..., 3] > 0
    h = a.shape[0]
    low = a[int(h * 0.7):]
    cols = np.where(low.any(axis=0))[0]
    cx = (cols.min() + cols.max()) / 2 if len(cols) else frame_img.width / 2
    x = int(round(FRAME_W / 2 - cx))
    y = FEET_Y - frame_img.height + 1
    if frame_img.height > FRAME_H:
        frame_img = frame_img.crop((0, frame_img.height - FRAME_H, frame_img.width, frame_img.height))
        y = 0
    canvas.alpha_composite(frame_img, (max(-frame_img.width, x), max(0, y))) if x >= 0 else canvas.paste(frame_img, (x, max(0, y)), frame_img)
    return canvas


def build_sheets():
    """Returns {family_member: RGBA sheet at RES x}, {family_member: portrait RGBA}."""
    cells = cut_all()
    im, _, _ = load()
    sheets, portraits = {}, {}
    for name, spec in FAMILY.items():
        k = spec["height"] / cells[spec["front"]].height
        beard = spec.get("beard", False)
        sheet = Image.new("RGBA", (FRAME_W * 4, FRAME_H * 5), (0, 0, 0, 0))
        rows = [spec["down"], [s + ":flip" if ":flip" not in s else s.replace(":flip", "") for s in spec["right"]],
                spec["right"], spec["up"], spec["action"]]
        for r, row in enumerate(rows):
            for c, s in enumerate(row):
                sheet.alpha_composite(_place(_pose(cells, s, k, beard, spec["front"])), (c * FRAME_W, r * FRAME_H))
        sheets[name] = sheet.resize((sheet.width * RES, sheet.height * RES), Image.NEAREST)
        portraits[name] = portrait_from_sprite(cells[spec["front"]])
    return sheets, portraits


def pixel_sheet(smooth, fw, fh):
    """A painted sheet (frames fw x fh at RES x) -> the family's crisp pixel style and frame."""
    out = Image.new("RGBA", (FRAME_W * 4, FRAME_H * 5), (0, 0, 0, 0))
    for r in range(5):
        for c in range(4):
            f = smooth.crop((c * fw * RES, r * fh * RES, (c + 1) * fw * RES, (r + 1) * fh * RES))
            f = outline(to_world(f, 1.0 / RES))
            ox = (FRAME_W - fw) // 2
            out.alpha_composite(f, (c * FRAME_W + ox, r * FRAME_H + (FRAME_H - fh)))
    return out.resize((out.width * RES, out.height * RES), Image.NEAREST)


def portrait_from_sprite(cell, size=72):
    """Dialogue portrait cut from the very figure the sprite is made of (head and
    shoulders of the front pose, at the reference's full resolution), so the face in
    the dialogue box is always the face walking around the world."""
    a = np.array(cell)
    rows = np.where(a[..., 3].max(axis=1) > 0)[0]
    top = int(rows.min())
    h = int((rows.max() - top) * 0.5)
    band = a[top:top + h]
    cols = np.where(band[..., 3].max(axis=0) > 0)[0]
    cx = int((cols.min() + cols.max()) / 2)
    half = max(h // 2 + 2, (cols.max() - cols.min()) // 2 + 2)
    crop = Image.fromarray(a).crop((cx - half, top - 2, cx + half, top - 2 + 2 * half))
    k = max(1, size // crop.width)
    big = crop.resize((crop.width * k, crop.height * k), Image.NEAREST)
    return big.resize((size, int(size * big.height / big.width)), Image.LANCZOS)


def outfit_variant(sheet):
    """Gideon in Runa's jacket: the maroon plaid shirt becomes deep blue wool."""
    a = np.array(sheet).astype(np.int32)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    shirt = (a[..., 3] > 0) & (r > g + 22) & (b > g + 4) & (r < 200)
    a[..., 0] = np.where(shirt, b * 0.7, r)
    a[..., 2] = np.where(shirt, np.clip(r * 1.15, 0, 255), b)
    return Image.fromarray(a.astype(np.uint8), "RGBA")


if __name__ == "__main__":
    import sys, os
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    sheets, portraits = build_sheets()
    big = Image.new("RGBA", (FRAME_W * RES * 4 * 4, FRAME_H * RES * 5 * 2), (96, 140, 80, 255))
    for i, (n, s) in enumerate(sheets.items()):
        big.alpha_composite(s, ((i % 4) * s.width, (i // 4) * s.height))
        portraits[n].save(os.path.join(out, f"portrait_{n}.png"))
    big.save(os.path.join(out, "family_sheets.png"))
