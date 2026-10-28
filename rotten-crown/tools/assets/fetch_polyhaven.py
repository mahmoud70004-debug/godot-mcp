#!/usr/bin/env python3
"""Download CC0 Poly Haven assets into build/asset_cache/<id>/ (build/ is git- and Godot-ignored).

  python3 tools/assets/fetch_polyhaven.py <asset_id>... [--type models|textures] [--res 1k]

Models: the glTF at <res> plus every file of its "include" dict (bin + textures) and any alpha maps.
Textures: Diffuse, AO and arm jpgs at <res>.
Also writes info.json (name, authors, categories) per asset. Existing files are skipped.
"""
import argparse
import json
import os
import sys
import urllib.request

API = "https://api.polyhaven.com"
ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
CACHE = os.path.join(ROOT, "build", "asset_cache")


def get_json(url):
    req = urllib.request.Request(url, headers={"User-Agent": "rotten-crown-asset-fetch/1.0"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)


def download(url, dest):
    if os.path.exists(dest) and os.path.getsize(dest) > 0:
        return False
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    req = urllib.request.Request(url, headers={"User-Agent": "rotten-crown-asset-fetch/1.0"})
    tmp = dest + ".part"
    with urllib.request.urlopen(req, timeout=120) as r, open(tmp, "wb") as f:
        while True:
            chunk = r.read(1 << 16)
            if not chunk:
                break
            f.write(chunk)
    os.replace(tmp, dest)
    return True


def fetch(asset_id, kind, res):
    out = os.path.join(CACHE, asset_id)
    os.makedirs(out, exist_ok=True)
    # keep Godot from importing the multi-GB scan cache (build/ is also git-ignored)
    open(os.path.join(ROOT, "build", ".gdignore"), "a").close()
    files = get_json(f"{API}/files/{asset_id}")
    info = get_json(f"{API}/info/{asset_id}")
    with open(os.path.join(out, "info.json"), "w") as f:
        json.dump({
            "id": asset_id,
            "name": info.get("name", asset_id),
            "authors": list((info.get("authors") or {}).keys()),
            "categories": info.get("categories", []),
            "type": kind,
            "res": res,
            "source": f"https://polyhaven.com/a/{asset_id}",
            "license": "CC0",
        }, f, indent=1)
    n = 0
    if kind == "models":
        g = files["gltf"][res]["gltf"]
        n += download(g["url"], os.path.join(out, os.path.basename(g["url"])))
        for rel, meta in g.get("include", {}).items():
            n += download(meta["url"], os.path.join(out, rel))
        # Leaf/fern cards keep their cut-out in a separate alpha map that the glTF does not reference.
        for key, by_res in files.items():
            if "alpha" in key.lower() and isinstance(by_res, dict) and res in by_res:
                fmt = by_res[res].get("png") or by_res[res].get("jpg")
                if fmt:
                    n += download(fmt["url"], os.path.join(out, "textures", os.path.basename(fmt["url"])))
    else:
        for key in ("Diffuse", "AO", "arm"):
            try:
                m = files[key][res]["jpg"]
            except KeyError:
                continue
            n += download(m["url"], os.path.join(out, os.path.basename(m["url"])))
    print(f"{asset_id}: {kind} {res} ok ({n} new files)")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ids", nargs="+")
    ap.add_argument("--type", choices=["models", "textures"], default="models")
    ap.add_argument("--res", default="1k")
    a = ap.parse_args()
    bad = 0
    for i in a.ids:
        try:
            fetch(i, a.type, a.res)
        except Exception as e:  # noqa: BLE001
            bad += 1
            print(f"{i}: FAILED {e}", file=sys.stderr)
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
