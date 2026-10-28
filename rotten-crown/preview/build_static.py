#!/usr/bin/env python3
"""Generate static development-preview files for GitHub Pages."""
import argparse
from pathlib import Path
import shutil

from server import CACHE, PREVIEW, make_pack, prepare_template


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path, help="Output directory outside the project source")
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    prepare_template()
    for name in ("index.html", "godot.audio.worklet.js", "godot.audio.position.worklet.js"):
        shutil.copyfile(PREVIEW / name, output / name)
    for name in ("godot.js", "godot.wasm"):
        shutil.copyfile(CACHE / name, output / name)
    (output / "game.pck").write_bytes(make_pack())
    print(f"Static preview ready: {output}")


if __name__ == "__main__":
    main()
