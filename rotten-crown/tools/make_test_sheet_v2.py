#!/usr/bin/env python3
"""Generates a synthetic sprite sheet v2 (indexed, trimmed; PLAN.md C10) for runtime regression tests.

Output: tools/galleries/test_sheet_v2/test_sheet.png (L8 index atlas), test_sheet_palette.png (RGBA 256 x 2),
the two .png.import files and test_sheet.tres. Each frame shows the direction digit (big), the frame digit
(small), an arrow turning with the direction and a red bar on the feet row, inside rects of varying size.
Palette note: the palette texture is sampled with the shader hint source_color, so its .png.import keeps the
default sRGB handling (no special flags); the index atlas is read linearly.
Usage: python3 tools/make_test_sheet_v2.py
"""
import math
from pathlib import Path

from PIL import Image, ImageDraw

OUT = Path(__file__).resolve().parent / "galleries" / "test_sheet_v2"
BOX_W, BOX_H, FOOT = 48, 64, 4
DIRS = 8
ANIMS = {"idle": (3, 4.0, True), "walk": (4, 8.0, True)}

FONT = {
    "0": ["111", "101", "101", "101", "111"], "1": ["010", "110", "010", "010", "111"],
    "2": ["111", "001", "111", "100", "111"], "3": ["111", "001", "111", "001", "111"],
    "4": ["101", "101", "111", "001", "001"], "5": ["111", "100", "111", "001", "111"],
    "6": ["111", "100", "111", "101", "111"], "7": ["111", "001", "010", "010", "010"],
}
# index values: 1-3 body ramp, 4 arrow, 5 direction digit, 6 frame digit, 7 feet bar
PALETTES = [
    {1: (40, 60, 110), 2: (70, 100, 170), 3: (120, 150, 220), 4: (240, 210, 60), 5: (255, 255, 255), 6: (90, 220, 120), 7: (230, 40, 40)},
    {1: (110, 40, 60), 2: (170, 70, 100), 3: (220, 120, 150), 4: (60, 210, 240), 5: (255, 255, 255), 6: (220, 200, 90), 7: (230, 40, 40)},
]


def glyph(d, ch, x, y, scale, val):
    for gy, row in enumerate(FONT[ch]):
        for gx, c in enumerate(row):
            if c == "1":
                d.rectangle([x + gx * scale, y + gy * scale, x + gx * scale + scale - 1, y + gy * scale + scale - 1], fill=val)


def make_frame(anim, k, f, nframes):
    im = Image.new("L", (BOX_W, BOX_H), 0)
    d = ImageDraw.Draw(im)
    bob = [0, 3, 1, 4][f % 4] if anim == "walk" else [0, 2, 0][f % 3]
    half_w = (14 if anim == "idle" else 11) + (f % 3) * 2
    top = 10 + bob
    bottom = BOX_H - FOOT - 1
    cx = BOX_W // 2
    for x in range(cx - half_w, cx + half_w):
        t = (x - (cx - half_w)) / (2 * half_w)
        d.line([x, top, x, bottom], fill=1 + min(int(t * 3), 2))
    # feet bar on the feet row
    d.line([cx - half_w, bottom, cx + half_w - 1, bottom], fill=7)
    glyph(d, str(k), cx - 6, top + 6, 4, 5)
    glyph(d, str(f), cx - 3, top + 32, 2, 6)
    # arrow: 0 = pointing down (toward the viewer), then clockwise
    a = math.radians(k * 360 / DIRS)
    ax, ay = cx, top - 2
    tipx, tipy = ax + math.sin(a) * 7, ay + math.cos(a) * 7
    d.line([ax, ay, tipx, tipy], fill=4, width=2)
    d.ellipse([tipx - 2, tipy - 2, tipx + 2, tipy + 2], fill=4)
    bbox = im.getbbox()
    return im.crop(bbox), bbox[0], bbox[1]


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    frames = []  # (image, box_x, box_y)
    anims = {}
    for name, (n, fps, loop) in ANIMS.items():
        anims[name] = (len(frames), n, fps, loop)
        for k in range(DIRS):
            for f in range(n):
                frames.append(make_frame(name, k, f, n))
    # shelf packing
    width = 256
    x = y = shelf = 0
    pos = []
    for im, _, _ in frames:
        w, h = im.size
        if x + w > width:
            x, y, shelf = 0, y + shelf, 0
        pos.append((x, y))
        x += w + 1
        shelf = max(shelf, h + 1)
    height = y + shelf
    atlas = Image.new("L", (width, height), 0)
    ints = []
    for (im, bx, by), (px, py) in zip(frames, pos):
        atlas.paste(im, (px, py))
        ints += [px, py, im.size[0], im.size[1], bx, by]
    atlas.save(OUT / "test_sheet.png")
    pal = Image.new("RGBA", (256, len(PALETTES)), (0, 0, 0, 0))
    for v, p in enumerate(PALETTES):
        for i, c in p.items():
            pal.putpixel((i, v), c + (255,))
    pal.save(OUT / "test_sheet_palette.png")
    import_tpl = (
        '[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n'
        'path="res://.godot/imported/%(n)s.png-%(h)s.ctex"\nmetadata={\n"vram_texture": false\n}\n\n[deps]\n\n'
        'source_file="res://tools/galleries/test_sheet_v2/%(n)s.png"\n'
        'dest_files=["res://.godot/imported/%(n)s.png-%(h)s.ctex"]\n\n[params]\n\n'
        "compress/mode=0\ncompress/high_quality=false\ncompress/lossy_quality=0.7\ncompress/hdr_compression=1\n"
        "compress/normal_map=0\ncompress/channel_pack=0\nmipmaps/generate=false\nmipmaps/limit=-1\n"
        'roughness/mode=0\nroughness/src_normal=""\nprocess/fix_alpha_border=false\nprocess/premult_alpha=false\n'
        "process/normal_map_invert_y=false\nprocess/hdr_as_srgb=false\nprocess/hdr_clamp_exposure=false\n"
        "process/size_limit=0\ndetect_3d/compress_to=0\n"
    )
    for n in ("test_sheet", "test_sheet_palette"):
        path = OUT / (n + ".png.import")
        if not path.exists():  # keep the uid/hash Godot wrote on first import
            path.write_text(import_tpl % {"n": n, "h": "0" * 32})
    anim_txt = ", ".join(
        '"%s": {"start": %d, "frames": %d, "fps": %.1f, "loop": %s}' % (n, s, c, fps, str(lp).lower())
        for n, (s, c, fps, lp) in anims.items()
    )
    tres = (
        '[gd_resource type="Resource" script_class="SpriteSheetData" load_steps=4 format=3]\n\n'
        '[ext_resource type="Script" path="res://src/rendering/sprite_sheet_data.gd" id="1_script"]\n'
        '[ext_resource type="Texture2D" path="res://tools/galleries/test_sheet_v2/test_sheet.png" id="2_tex"]\n'
        '[ext_resource type="Texture2D" path="res://tools/galleries/test_sheet_v2/test_sheet_palette.png" id="3_pal"]\n\n'
        "[resource]\nscript = ExtResource(\"1_script\")\ntexture = ExtResource(\"2_tex\")\npalette = ExtResource(\"3_pal\")\n"
        "variants = %d\nframe_size = Vector2i(%d, %d)\nframes = PackedInt32Array(%s)\ndirections = %d\nanims = {%s}\n"
        "pixel_size = 0.03\nfoot_offset_px = %d\n"
        % (len(PALETTES), BOX_W, BOX_H, ", ".join(map(str, ints)), DIRS, anim_txt, FOOT)
    )
    (OUT / "test_sheet.tres").write_text(tres)
    print("atlas", atlas.size, "frames", len(frames))


if __name__ == "__main__":
    main()
