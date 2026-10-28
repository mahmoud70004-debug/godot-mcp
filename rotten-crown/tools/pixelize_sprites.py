#!/usr/bin/env python3
"""Turn raw pre-rendered character frames into a pixel-art sprite sheet + SpriteSheetData .tres.

Usage: python3 tools/pixelize_sprites.py [--raw DIR] [--out DIR] [chars...]
Raw layout: <raw>/<char>/<anim>_<dir>_<frame>.png + meta.json (see tools/sprite_baker).
Output:     <out>/<char>/<char>.png and <char>.tres
"""
import argparse
import json
import os
import sys

import numpy as np
from PIL import Image

OUTLINE_DARKEN = 0.55  # selective inner outline keeps 55% of brightness (-45%)
OUTER_COLOR = (14, 12, 24)  # near-black, slightly blue
CONTRAST = 1.18
PAD = 1


def load_frames(raw_dir, meta):
    frames = {}
    for anim, info in meta["anims"].items():
        for d in range(int(meta["dirs"])):
            for f in range(int(info["frames"])):
                path = os.path.join(raw_dir, "%s_%d_%d.png" % (anim, d, f))
                frames[(anim, d, f)] = Image.open(path).convert("RGBA")
    return frames


def union_bbox(frames):
    x0 = y0 = 10**9
    x1 = y1 = -1
    for im in frames.values():
        bb = im.getchannel("A").point(lambda a: 255 if a > 127 else 0).getbbox()
        if bb is None:
            continue
        x0, y0 = min(x0, bb[0]), min(y0, bb[1])
        x1, y1 = max(x1, bb[2]), max(y1, bb[3])
    return x0, y0, x1, y1


def resize_premult(im, size, resample):
    """Resize RGBA with premultiplied colour so transparent pixels do not bleed."""
    a = np.asarray(im, dtype=np.float32) / 255.0
    pm = a.copy()
    pm[..., :3] *= a[..., 3:4]
    pim = Image.fromarray((pm * 255.0 + 0.5).astype(np.uint8), "RGBA")
    out = np.asarray(pim.resize(size, resample), dtype=np.float32) / 255.0
    alpha = out[..., 3:4]
    rgb = np.where(alpha > 1e-4, out[..., :3] / np.maximum(alpha, 1e-4), 0.0)
    res = np.concatenate([np.clip(rgb, 0, 1), alpha], axis=-1)
    return Image.fromarray((res * 255.0 + 0.5).astype(np.uint8), "RGBA")


def downscale(im, size):
    big = (size[0] * 2, size[1] * 2)
    step = resize_premult(im, big, Image.BOX)
    return resize_premult(step, size, Image.NEAREST)


def hard_alpha(arr):
    arr = arr.copy()
    arr[..., 3] = np.where(arr[..., 3] >= 128, 255, 0)
    return arr


def contrast(rgb, mean):
    out = (rgb - mean) * CONTRAST + mean
    # gentle highlight lift so steel pops
    lum = out.mean(axis=-1, keepdims=True)
    out = out + np.clip(lum - 0.55, 0, 1) * 0.35
    return np.clip(out, 0, 1)


def neighbours_transparent(mask):
    """mask True where opaque (padded). Returns True where any 4-neighbour is transparent."""
    p = np.pad(mask, 1, constant_values=False)
    return ~(p[:-2, 1:-1] & p[2:, 1:-1] & p[1:-1, :-2] & p[1:-1, 2:])


def outline(arr):
    """arr: float RGBA HxWx4 already padded. Inner selective outline + 1px outer dark outline."""
    opaque = arr[..., 3] > 0.5
    edge = opaque & neighbours_transparent(opaque)
    arr = arr.copy()
    arr[edge, :3] *= OUTLINE_DARKEN
    p = np.pad(opaque, 1, constant_values=False)
    grow = (p[:-2, 1:-1] | p[2:, 1:-1] | p[1:-1, :-2] | p[1:-1, 2:])
    outer = grow & ~opaque
    arr[outer, :3] = np.array(OUTER_COLOR, dtype=np.float32) / 255.0
    arr[outer, 3] = 1.0
    return arr


def build_palette(images, n_colors):
    pix = np.concatenate([a[a[..., 3] > 0.5][:, :3] for a in images])
    pix8 = (pix * 255.0 + 0.5).astype(np.uint8)
    # Keep the outer outline colour exact: reserve one slot for it.
    side = int(np.ceil(np.sqrt(len(pix8))))
    pad = np.zeros((side * side, 3), np.uint8)
    pad[: len(pix8)] = pix8
    pad[len(pix8):] = pix8[-1]
    merged = Image.fromarray(pad.reshape(side, side, 3), "RGB")
    q = merged.quantize(colors=n_colors - 1, method=Image.MEDIANCUT, dither=Image.NONE)
    pal = np.array(q.getpalette()[: 3 * (n_colors - 1)], dtype=np.uint8).reshape(-1, 3)
    pal = np.concatenate([pal, np.array([OUTER_COLOR], np.uint8)])
    return pal


def apply_palette(arr, pal):
    out = np.zeros(arr.shape, np.uint8)
    opaque = arr[..., 3] > 0.5
    rgb = (arr[..., :3] * 255.0).astype(np.float32)
    idx = np.argmin(((rgb[opaque][:, None, :] - pal[None, :, :].astype(np.float32)) ** 2).sum(-1), axis=1)
    out[opaque, :3] = pal[idx]
    out[opaque, 3] = 255
    return out


def process(char, raw_root, out_root):
    raw_dir = os.path.join(raw_root, char)
    with open(os.path.join(raw_dir, "meta.json")) as fh:
        meta = json.load(fh)
    dirs = int(meta["dirs"])
    frames = load_frames(raw_dir, meta)
    x0, y0, x1, y1 = union_bbox(frames)
    crop_w, crop_h = x1 - x0, y1 - y0

    # Scale so the idle pose (front, frame 0) is height_px tall; the union crop shares it.
    ref = frames[("idle", 0, 0)] if ("idle", 0, 0) in frames else next(iter(frames.values()))
    rb = ref.getchannel("A").point(lambda a: 255 if a > 127 else 0).getbbox()
    ref_h = rb[3] - rb[1]
    scale = float(meta["height_px"]) / ref_h
    dw, dh = max(1, round(crop_w * scale)), max(1, round(crop_h * scale))

    small = {}
    for key, im in frames.items():
        s = np.asarray(downscale(im.crop((x0, y0, x1, y1)), (dw, dh)), dtype=np.float32) / 255.0
        s = hard_alpha(s * 255.0) / 255.0
        small[key] = s

    allpix = np.concatenate([s[s[..., 3] > 0.5][:, :3] for s in small.values()])
    mean = float(allpix.mean())
    fw, fh = dw + 2 * PAD, dh + 2 * PAD
    processed = {}
    for key, s in small.items():
        s = s.copy()
        s[..., :3] = contrast(s[..., :3], mean)
        s[..., :3] *= (s[..., 3:4] > 0.5)
        s = np.pad(s, ((PAD, PAD), (PAD, PAD), (0, 0)))
        processed[key] = outline(s)
    pal = build_palette(list(processed.values()), int(meta["palette"]))

    rows = len(meta["anims"]) * dirs
    cols = max(int(i["frames"]) for i in meta["anims"].values())
    sheet = np.zeros((rows * fh, cols * fw, 4), np.uint8)
    anims_out = {}
    row = 0
    for anim, info in meta["anims"].items():
        anims_out[anim] = {"row": row, "frames": int(info["frames"]), "fps": float(info["fps"]),
                           "loop": bool(info["loop"])}
        for d in range(dirs):
            for f in range(int(info["frames"])):
                sheet[(row + d) * fh:(row + d + 1) * fh, f * fw:(f + 1) * fw] = apply_palette(
                    processed[(anim, d, f)], pal)
        row += dirs

    out_dir = os.path.join(out_root, char)
    os.makedirs(out_dir, exist_ok=True)
    png_path = os.path.join(out_dir, char + ".png")
    Image.fromarray(sheet, "RGBA").save(png_path, optimize=True)

    metres_per_raw_px = float(meta["camera_size"]) / float(meta["render_px"])
    pixel_size = metres_per_raw_px / scale
    # feet line = bottom of the idle reference pose; rows below it (death pose, outline pad) are transparent
    foot_offset = int(round((y1 - rb[3]) * scale)) + PAD
    write_tres(out_dir, char, (fw, fh), dirs, anims_out, pixel_size, foot_offset, out_root)
    print("%s: sheet %dx%d, frame %dx%d, rows %d, cols %d, pixel_size %.5f, colours %d"
          % (char, sheet.shape[1], sheet.shape[0], fw, fh, rows, cols, pixel_size, len(pal)))


def res_path(out_dir, name):
    rel = os.path.relpath(os.path.join(out_dir, name), os.getcwd()).replace(os.sep, "/")
    if rel.startswith(".."):
        return name
    return "res://" + rel


def write_tres(out_dir, char, frame_size, dirs, anims, pixel_size, foot_offset, out_root):
    def anim_text(a):
        return '{"row": %d, "frames": %d, "fps": %.1f, "loop": %s}' % (
            a["row"], a["frames"], a["fps"], "true" if a["loop"] else "false")

    anims_text = ", ".join('"%s": %s' % (k, anim_text(v)) for k, v in anims.items())
    text = (
        '[gd_resource type="Resource" script_class="SpriteSheetData" load_steps=3 format=3]\n\n'
        '[ext_resource type="Script" path="res://src/rendering/sprite_sheet_data.gd" id="1_script"]\n'
        '[ext_resource type="Texture2D" path="%s" id="2_tex"]\n\n'
        '[resource]\n'
        'script = ExtResource("1_script")\n'
        'texture = ExtResource("2_tex")\n'
        'frame_size = Vector2i(%d, %d)\n'
        'directions = %d\n'
        'anims = {%s}\n'
        'pixel_size = %.6f\n'
        'foot_offset_px = %d\n'
    ) % (res_path(out_dir, char + ".png"), frame_size[0], frame_size[1], dirs, anims_text,
         pixel_size, foot_offset)
    with open(os.path.join(out_dir, char + ".tres"), "w") as fh:
        fh.write(text)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--raw", default="build/sprites_raw")
    ap.add_argument("--out", default="assets/sprites")
    ap.add_argument("chars", nargs="*")
    args = ap.parse_args()
    chars = args.chars or sorted(d for d in os.listdir(args.raw)
                                 if os.path.isfile(os.path.join(args.raw, d, "meta.json")))
    if not chars:
        print("no characters found in %s" % args.raw)
        return 1
    for c in chars:
        process(c, args.raw, args.out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
