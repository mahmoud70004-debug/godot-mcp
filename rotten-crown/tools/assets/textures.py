#!/usr/bin/env python3
"""Ground/wall/roof/bark tiles: Poly Haven 1k -> seamless 128/256 px (diffuse x AO), written to
assets/textures/world/<id>.png with a nearest-friendly .png.import (VRAM compressed, mipmaps on).

  python3 tools/assets/textures.py [id[:px] ...]     # default: the whole world set below
Needs the 1k sources: python3 tools/assets/fetch_polyhaven.py <ids> --type textures
"""
import glob
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import texlib  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
CACHE = os.path.join(ROOT, "build", "asset_cache")
OUT = os.path.join(ROOT, "assets", "textures", "world")

# id -> px
DEFAULT = {
    "forest_floor": 256,
    "forest_leaves_02": 256,
    "brown_mud_leaves_01": 256,
    "dry_mud_field_001": 256,
    "grass_path_2": 256,
    "aerial_grass_rock": 256,
    "cobblestone_floor_04": 256,
    "castle_brick_02_white": 256,
    "clay_roof_tiles": 256,
    "brown_planks_05": 128,
    "damaged_plaster": 128,
    "bark_brown_02": 128,
}

IMPORT = """[remap]

importer="texture"
type="CompressedTexture2D"

[deps]

source_file="res://assets/textures/world/{name}.png"

[params]

compress/mode=2
compress/high_quality=false
compress/lossy_quality=0.7
compress/hdr_compression=1
compress/normal_map=0
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=0
"""


def find(folder, token):
    for t in ([token, "diffuse"] if token == "diff" else [token]):
        c = sorted(glob.glob(os.path.join(folder, f"*_{t}_*.jpg")))
        if c:
            return c[0]
    return None


def process(tid, px):
    folder = os.path.join(CACHE, tid)
    diff = find(folder, "diff")
    if not diff:
        print(f"{tid}: no diffuse in {folder}", file=sys.stderr)
        return False
    arm = find(folder, "arm")
    ao = None if arm else find(folder, "ao")
    im = texlib.albedo(diff, ao=ao, arm=arm, px=px, wrap=True)
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, tid + ".png")
    texlib.save_png(im, path)
    if not os.path.exists(path + ".import"):  # keep Godot's uid/path once imported
        with open(path + ".import", "w") as f:
            f.write(IMPORT.format(name=tid))
    print(f"{tid}: {im.size[0]}x{im.size[1]} {os.path.getsize(path) // 1024} KB (ao={'arm' if arm else 'ao' if ao else 'none'})")
    return True


def main():
    todo = dict(DEFAULT)
    if len(sys.argv) > 1:
        todo = {}
        for a in sys.argv[1:]:
            i, _, p = a.partition(":")
            todo[i] = int(p) if p else DEFAULT.get(i, 256)
    bad = [t for t, p in todo.items() if not process(t, p)]
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
