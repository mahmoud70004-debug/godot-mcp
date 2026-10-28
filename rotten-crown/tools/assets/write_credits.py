#!/usr/bin/env python3
"""Write assets/models/CREDITS.md from build/asset_cache/*/info.json (models in KIT + world textures)."""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
import build_kit  # noqa: E402
import textures  # noqa: E402


def row(aid, out):
    p = os.path.join(ROOT, "build", "asset_cache", aid, "info.json")
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
    open(os.path.join(ROOT, "assets", "models", "CREDITS.md"), "w").write("\n".join(lines) + "\n")
    print("wrote CREDITS.md")


if __name__ == "__main__":
    main()
