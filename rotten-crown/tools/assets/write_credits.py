#!/usr/bin/env python3
"""Write assets/models/CREDITS.md from build/asset_cache/*/info.json (models in KIT + world textures)."""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
import build_kit  # noqa: E402
import build_oga  # noqa: E402
import textures  # noqa: E402


def row(aid, out):
    p = os.path.join(ROOT, "build", "asset_cache", aid, "info.json")
    if not os.path.exists(p):  # asset cache not fetched in this checkout: keep the row already in CREDITS.md
        old = os.path.join(ROOT, "assets", "models", "CREDITS.md")
        for ln in open(old).read().splitlines():
            if ln.startswith(f"| `{out}` |"):
                return ln
        raise SystemExit(f"{aid}: no cache and no existing row")
    i = json.load(open(p))
    return f"| `{out}` | {aid} | {i['name']} | {', '.join(i['authors'])} | https://polyhaven.com/a/{aid} | CC0 |"


def main():
    lines = ["# Asset credits", "",
             "All assets below come from [Poly Haven](https://polyhaven.com) and are released under CC0 (public domain).",
             "They were decimated and re-textured offline with `tools/assets/` (process_model.py, textures.py);",
             "no attribution is required, it is given here out of courtesy.", "",
             "## Models (`assets/models/*.glb`)", "",
             "| file | id | name | authors | source | licence |", "|---|---|---|---|---|---|"]
    for name, aid, *_ in build_kit.KIT:
        lines.append(row(aid, name + ".glb"))
    lines += ["", "## Ground, wall, roof and bark textures (`assets/textures/world/*.png`)", "",
              "| file | id | name | authors | source | licence |", "|---|---|---|---|---|---|"]
    for tid in textures.DEFAULT:
        lines.append(row(tid, tid + ".png"))
    lines += ["", "## OpenGameArt houses and village props (`assets/models/oga_*.glb`)", "",
              "CC0 (public domain) packs from [OpenGameArt](https://opengameart.org), converted offline with",
              "`tools/assets/fetch_opengameart.py` + `process_blend.py` (re-textured to <= 256 px palette PNGs, decimated, re-scaled).", "",
              "| file | pack | author | source | licence |", "|---|---|---|---|---|"]
    for name, slug, *_ in build_oga.OGA:
        i = json.load(open(os.path.join(ROOT, "build", "asset_cache", "oga", slug, "info.json")))
        who = i["author"] + (f" (submitted by {i['submitter']})" if i.get("submitter") else "")
        lines.append(f"| `{name}.glb` | {i['title']} | {who} | {i['source']} | {i['license']} |")
    open(os.path.join(ROOT, "assets", "models", "CREDITS.md"), "w").write("\n".join(lines) + "\n")
    print("wrote CREDITS.md")


if __name__ == "__main__":
    main()
