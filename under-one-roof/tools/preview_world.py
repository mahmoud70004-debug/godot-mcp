"""Compose ground chunks + objects into one image to eyeball the map layout.

Usage: python3 tools/preview_world.py OUT.png [x0 y0 x1 y1 tile-rect] [--flags a,b] [--scale S]
S = output pixels per world pixel (default 1; textures are stored at RES x).
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
    args = list(sys.argv[2:])
    flags, s = set(), 1.0
    if "--flags" in args:
        i = args.index("--flags"); flags = set(args[i + 1].split(",")); del args[i:i + 2]
    if "--scale" in args:
        i = args.index("--scale"); s = float(args[i + 1]); del args[i:i + 2]
    world = json.load(open(f"{ROOT}/data/world.json"))
    meta = json.load(open(f"{ROOT}/data/sprites.json"))["sprites"]
    gres = world.get("ground_res", 1)
    W, H = world["width"] * world["tile"], world["height"] * world["tile"]
    img = Image.new("RGBA", (int(W * s), int(H * s)), (0, 0, 0, 255))
    for x, y, name in world["ground"]:
        ch = Image.open(f"{ROOT}/assets/world/{name}").convert("RGBA")
        ch.putalpha(255)
        f = s / gres
        img.alpha_composite(ch.resize((max(1, int(ch.width * f)), max(1, int(ch.height * f))), Image.LANCZOS), (int(x * s), int(y * s)))
    objs = [o for o in world["objects"] if "sprite" in o and visible(o, flags)]
    objs.sort(key=lambda o: (0 if meta[o["sprite"]].get("flat") else 1, o["y"] + meta[o["sprite"]]["oy"]))
    cache = {}
    for o in objs:
        m = meta[o["sprite"]]
        if o["sprite"] not in cache:
            im = Image.open(f"{ROOT}/assets/sprites/{o['sprite']}.png").convert("RGBA")
            r = m.get("res", 1)
            if m.get("frames"):
                im = im.crop((0, 0, m["w"] * r, m["h"] * r))
            if o.get("flip"):
                from PIL import ImageOps; im = ImageOps.mirror(im)
            cache[o["sprite"]] = im.resize((max(1, int(m["w"] * s)), max(1, int(m["h"] * s))), Image.LANCZOS)
        im = cache[o["sprite"]]
        x, y = int(o["x"] * s), int(o["y"] * s)
        tmp = Image.new("RGBA", img.size, (0, 0, 0, 0)); tmp.paste(im, (x, y))
        img.alpha_composite(tmp) if False else img.paste(im, (x, y), im)
    if len(args) >= 4:
        t = world["tile"] * s
        x0, y0, x1, y1 = (int(int(v) * t) for v in args[:4])
        img = img.crop((x0, y0, x1, y1))
    img.convert("RGB").save(out)

main()
