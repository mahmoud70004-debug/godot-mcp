#!/usr/bin/env python3
"""Fetch + process the whole world asset kit, then print the budget table.

  python3 tools/assets/build_kit.py [name ...]      # default: everything (sequential, Blender headless)
Env: BLENDER (path to blender). Needs network for the first run (Poly Haven, CC0).
Columns: out name, Poly Haven id, triangle budget, texture px, extra process_model flags.
Pieces assets: --tris is per piece, --keep K keeps the K largest pieces (separate named meshes in the GLB).
"""
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))

KIT = [
    # big trees
    ("dead_tree_trunk", "dead_tree_trunk", 2500, 256, ""),
    ("dead_tree_trunk_02", "dead_tree_trunk_02", 2500, 256, ""),
    ("pine_tree_01", "pine_tree_01", 3800, 256, "--pieces --keep 2"),
    ("fir_tree_01", "fir_tree_01", 3800, 256, "--pieces --keep 2"),
    ("tree_small_02", "tree_small_02", 3000, 256, ""),
    # stumps, roots, branches, rocks
    ("tree_stump_01", "tree_stump_01", 1000, 256, ""),
    ("tree_stump_02", "tree_stump_02", 1000, 256, ""),
    ("pine_roots", "pine_roots", 700, 256, "--pieces --keep 2"),
    ("root_cluster_01", "root_cluster_01", 900, 128, ""),
    ("root_cluster_02", "root_cluster_02", 350, 128, "--pieces --keep 3"),
    ("single_root", "single_root", 600, 128, ""),
    ("dry_branches_medium_01", "dry_branches_medium_01", 250, 128, "--pieces --keep 3"),
    ("bark_debris_01", "bark_debris_01", 150, 128, "--pieces --keep 4"),
    ("fern_02", "fern_02", 200, 128, "--pieces --keep 4"),
    ("fir_sapling", "fir_sapling", 350, 128, "--pieces --keep 3"),
    ("boulder_01", "boulder_01", 1200, 256, ""),
    ("rock_moss_set_01", "rock_moss_set_01", 450, 256, "--pieces --keep 4"),
    ("rock_moss_set_02", "rock_moss_set_02", 450, 256, "--pieces --keep 4"),
    ("namaqualand_boulder_02", "namaqualand_boulder_02", 1000, 256, ""),
    ("rock_07", "rock_07", 800, 128, ""),
    ("rock_09", "rock_09", 800, 128, ""),
    # props
    ("Barrel_01", "Barrel_01", 500, 128, ""),
    ("wine_barrel_01", "wine_barrel_01", 500, 128, ""),
    ("wooden_barrels_01", "wooden_barrels_01", 450, 128, "--pieces --keep 3"),
    ("wooden_crate_01", "wooden_crate_01", 250, 64, ""),
    ("wooden_crate_02", "wooden_crate_02", 250, 64, ""),
    ("wooden_bucket_01", "wooden_bucket_01", 300, 64, ""),
    ("wooden_ladder", "wooden_ladder", 400, 64, ""),
    ("wooden_lantern_01", "wooden_lantern_01", 500, 128, ""),
    ("Lantern_01", "Lantern_01", 500, 128, ""),
    ("wooden_stool_01", "wooden_stool_01", 300, 64, ""),
    ("WoodenTable_01", "WoodenTable_01", 500, 128, ""),
    ("painted_wooden_bench", "painted_wooden_bench", 500, 128, ""),
    ("spinning_wheel_01", "spinning_wheel_01", 600, 128, ""),
    ("wooden_axe", "wooden_axe", 250, 64, ""),
    ("rusted_wheel_rim_01", "rusted_wheel_rim_01", 500, 128, ""),
    ("gothic_statue", "gothic_statue", 1500, 128, ""),
    ("brass_goblets", "brass_goblets", 130, 128, "--pieces --keep 3"),
]


def table():
    rows = []
    tot_t = tot_k = 0
    for name, *_ in KIT:
        p = os.path.join(ROOT, "build", "kit_report", name + ".json")
        if not os.path.exists(p):
            continue
        r = json.load(open(p))
        rows.append(r)
        tot_t += r["tris"]
        tot_k += r["glb_kb"]
    print(f"{'asset':26} {'tris':>6} {'tex px':>7} {'glb KB':>7}  pieces")
    for r in rows:
        print(f"{r['name']:26} {r['tris']:6d} {r['tex_px']:7d} {r['glb_kb']:7.1f}  {len(r['pieces'])}")
    print(f"{'TOTAL (' + str(len(rows)) + ' models)':26} {tot_t:6d} {'':7} {tot_k:7.1f}")


def main():
    blender = os.environ.get("BLENDER", "blender")
    only = set(sys.argv[1:])
    for name, aid, tris, px, flags in KIT:
        if only and name not in only:
            continue
        subprocess.run([sys.executable, os.path.join(HERE, "fetch_polyhaven.py"), aid, "--type", "models"], check=True, cwd=ROOT)
        cmd = [blender, "-b", "--factory-startup", "--python", os.path.join(HERE, "process_model.py"), "--",
               aid, "--tris", str(tris), "--tex", str(px), "--name", name] + flags.split()
        r = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
        line = [ln for ln in r.stdout.splitlines() if ln.startswith("RESULT")]
        if r.returncode != 0 or not line:
            print(f"{name}: FAILED\n{r.stdout[-1500:]}\n{r.stderr[-1500:]}", file=sys.stderr)
            continue
        d = json.loads(line[0][7:])
        print(f"{name}: {d['source_tris']} -> {d['tris']} tris, tex {d['tex_px']}px, {d['glb_kb']} KB, dims {d['dims_m']}", flush=True)
    subprocess.run([sys.executable, os.path.join(HERE, "write_import.py")], check=True)
    table()


if __name__ == "__main__":
    main()
