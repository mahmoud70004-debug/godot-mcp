#!/usr/bin/env python3
"""Fetch + process the OpenGameArt (CC0) houses and village props, then print the budget table.

  python3 tools/assets/build_oga.py [name ...]      # default: everything (sequential, Blender headless)
Env: BLENDER. Needs network for the first run (fetch_opengameart.py) and py7zr (or a 7z binary) for the .7z pack.
Columns: out name, pack slug, source file inside the pack folder, process_blend.py flags.
The pack "medieval-buildings-pack" has no real-world scale: --scale 0.385 makes its doors 2 m tall.
"""
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
B = "https://opengameart.org/sites/default/files/"

# slug -> (page slug, [file urls]); the page slug is also the pack's credit page
PACKS = {
    "medieval-house-pack": ("medieval-house-pack", [B + "75519_House1Upload_blend.zip", B + "75861_House2_1Upload_blend.zip",
                                                    B + "75862_House3Upload_blend.zip", B + "75864_House4Upload_blend.zip"]),
    "modular-medieval-house-pack-01": ("modular-medieval-house-pack-01", [B + "MedievalHousePack01.zip"]),
    "medieval-buildings-pack": ("medieval-buildings-pack", [B + "medieval_buildings_pack.7z"]),
}

H = "medieval-house-pack/x_%s/%s.blend"
MB = "medieval-buildings-pack/x_medieval_buildings_pack/medieval_buildings_pack/medieval_buildings_pack.blend"
MH = "modular-medieval-house-pack-01/x_MedievalHousePack01/CREATEDMODULARBUILDINGS/%s.blend"
WS = "house_wood_window_stick_*"

OGA = [
    # (out name, pack slug, source (relative to build/asset_cache/oga), flags)
    ("oga_house_1", "medieval-house-pack", H % ("75519_House1Upload_blend", "House1Upload"), "--tris 3000 --tex 256 --ground"),
    ("oga_house_2", "medieval-house-pack", H % ("75861_House2_1Upload_blend", "House2_1Upload"), "--tris 3000 --tex 256 --ground"),
    ("oga_house_3", "medieval-house-pack", H % ("75862_House3Upload_blend", "House3Upload"), "--tris 3000 --tex 256 --ground"),
    ("oga_house_4", "medieval-house-pack", H % ("75864_House4Upload_blend", "House4Upload"), "--tris 3000 --tex 256 --ground"),
    ("oga_house_5", "modular-medieval-house-pack-01", MH % "house01", "--tris 2600 --tex 256 --ground"),
    ("oga_house_6", "modular-medieval-house-pack-01", MH % "house02", "--tris 2600 --tex 256 --ground"),
    # village props (medieval-buildings-pack)
    ("oga_cottage", "medieval-buildings-pack", MB, "--objs house_wood,house_wood_door,house_wood_window_stick_left,house_wood_window_stick_right --scale 0.385 --tris 600 --tex 256"),
    ("oga_longhouse", "medieval-buildings-pack", MB, "--objs house_wood_2,house_wood_2_door,house_wood_2_window_stick_* --scale 0.385 --tris 900 --tex 256"),
    ("oga_well", "medieval-buildings-pack", MB, "--objs well --height 2.7 --tris 400 --tex 128"),
    ("oga_stall", "medieval-buildings-pack", MB, "--objs canopy_wood --scale 0.385 --tris 200 --tex 128"),
    ("oga_tent", "medieval-buildings-pack", MB, "--objs canopy_cloth --scale 0.35 --tris 200 --tex 128"),
    ("oga_outhouse", "medieval-buildings-pack", MB, "--objs outhouse --height 2.5 --tris 150 --tex 128"),
    ("oga_watchtower", "medieval-buildings-pack", MB, "--objs watchtower_wood --height 7.0 --tris 600 --tex 128"),
    ("oga_fence", "medieval-buildings-pack", MB, "--objs fence_wood,fence_wood_pillar --height 1.35 --tris 120 --tex 128"),
    ("oga_gate", "medieval-buildings-pack", MB, "--objs gate_wood --scale 0.25 --tris 150 --tex 128"),
    ("oga_palisade", "medieval-buildings-pack", MB, "--objs wall_wood --height 3.0 --tris 300 --tex 128"),
]


def fetch():
    for slug, (page, urls) in PACKS.items():
        info = os.path.join(ROOT, "build", "asset_cache", "oga", slug, "info.json")
        if not os.path.exists(info):
            subprocess.run([sys.executable, os.path.join(HERE, "fetch_opengameart.py"), page] + urls + ["--slug", slug], check=True)


def main():
    blender = os.environ.get("BLENDER", "blender")
    only = sys.argv[1:]
    fetch()
    rows = []
    for name, slug, src, flags in OGA:
        if only and name not in only:
            continue
        cmd = [blender, "-b", "--factory-startup", "--python", os.path.join(HERE, "process_blend.py"), "--",
               "oga/" + src, "--name", name] + flags.split()
        r = subprocess.run(["nice"] + cmd, capture_output=True, text=True)
        rep = os.path.join(ROOT, "build", "kit_report", name + ".json")
        if r.returncode != 0 or not os.path.exists(rep):
            print(name, "FAILED\n", r.stdout[-1500:], r.stderr[-800:])
            continue
        d = json.load(open(rep))
        rows.append(d)
        print(f"{name}: tris {d['tris']} tex {d['tex_px']}px glb {d['glb_kb']}KB dims {d['dims_m']}")
    subprocess.run([sys.executable, os.path.join(HERE, "write_import.py")], check=True)
    print("\n| asset | tris | tex px | glb KB |\n|---|---|---|---|")
    for d in rows:
        print(f"| {d['name']} | {d['tris']} | {d['tex_px']} | {d['glb_kb']} |")


if __name__ == "__main__":
    main()
