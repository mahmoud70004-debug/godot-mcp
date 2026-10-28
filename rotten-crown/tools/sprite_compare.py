#!/usr/bin/env python3
"""Side-by-side review image: the same sprite frames from an old and a new sheet, 4x nearest zoom.

Usage: python3 tools/sprite_compare.py OLD.png NEW.png OUT.png [--old-tres F] [--new-tres F]
           [--frames anim:dir:frame,...] [--zoom 4]
Frame sizes and anim rows are read from the .tres next to each PNG (default NAME.tres).
"""
import argparse
import os
import re

from PIL import Image


def read_tres(png, tres):
    path = tres or os.path.splitext(png)[0] + ".tres"
    text = open(path).read()
    w, h = map(int, re.search(r"frame_size = Vector2i\((\d+), (\d+)\)", text).groups())
    rows = {m[0]: int(m[1]) for m in re.findall(r'"(\w+)": \{"row": (\d+)', text)}
    return (w, h), rows


def grab(sheet, size, rows, anim, d, f):
    w, h = size
    r = rows[anim] + d
    return sheet.crop((f * w, r * h, (f + 1) * w, (r + 1) * h))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("old")
    ap.add_argument("new")
    ap.add_argument("out")
    ap.add_argument("--old-tres", default="")
    ap.add_argument("--new-tres", default="")
    ap.add_argument("--frames", default="idle:0:0,walk:2:2,cheer:1:2")
    ap.add_argument("--zoom", type=int, default=4)
    a = ap.parse_args()
    sheets = []
    for png, tres in ((a.old, a.old_tres), (a.new, a.new_tres)):
        size, rows = read_tres(png, tres)
        sheets.append((Image.open(png).convert("RGBA"), size, rows))
    specs = [s.split(":") for s in a.frames.split(",")]
    cells = []
    for anim, d, f in specs:
        pair = []
        for sheet, size, rows in sheets:
            fr = grab(sheet, size, rows, anim, int(d), int(f))
            pair.append(fr.resize((fr.width * a.zoom, fr.height * a.zoom), Image.NEAREST))
        cells.append(pair)
    gap = 12
    cw = max(im.width for p in cells for im in p)
    ch = max(im.height for p in cells for im in p)
    canvas = Image.new("RGBA", (len(cells) * (2 * cw + gap) + gap, ch + 2 * gap), (58, 62, 72, 255))
    x = gap
    for pair in cells:
        for im in pair:
            canvas.alpha_composite(im, (x + (cw - im.width) // 2, gap + ch - im.height))
            x += cw
        x += gap
    canvas.convert("RGB").save(a.out)
    print("wrote", a.out, canvas.size, "(old | new per frame)")


if __name__ == "__main__":
    main()
