"""Compose ground + objects into one image to eyeball the map layout.

Usage: python3 tools/preview_world.py OUT.png [x0 y0 x1 y1 tile-rect] [--flags a,b]
"""
import json, os, sys
from PIL import Image
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

def visible(o, flags):
    for f in o.get("show_if", []):
        if f.startswith("!") and f[1:] in flags: return False
        if not f.startswith("!") and f not in flags: return False
    return True

def main():
    out = sys.argv[1]
    flags = set()
    args = [a for a in sys.argv[2:]]
    if "--flags" in args:
        i = args.index("--flags"); flags = set(args[i + 1].split(",")); del args[i:i + 2]
    world = json.load(open(f"{ROOT}/data/world.json"))
    meta = json.load(open(f"{ROOT}/data/sprites.json"))["sprites"]
    img = Image.open(f"{ROOT}/assets/world/ground.png").convert("RGBA")
    objs = [o for o in world["objects"] if "sprite" in o and visible(o, flags)]
    objs.sort(key=lambda o: (0 if meta[o["sprite"]].get("flat") else 1, o["y"] + meta[o["sprite"]]["oy"]))
    for o in objs:
        m = meta[o["sprite"]]
        im = Image.open(f"{ROOT}/assets/sprites/{o['sprite']}.png")
        if m.get("frames"):
            im = im.crop((0, 0, m["w"], m["h"]))
        img.alpha_composite(im, (o["x"], o["y"])) if o["x"] >= 0 and o["y"] >= 0 else img.paste(im, (o["x"], o["y"]), im)
    if len(args) >= 4:
        x0, y0, x1, y1 = (int(v) * 16 for v in args[:4])
        img = img.crop((x0, y0, x1, y1))
    img.save(out)

main()
