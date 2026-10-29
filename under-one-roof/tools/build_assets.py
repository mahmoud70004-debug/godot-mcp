"""Regenerate every procedural asset of Under One Roof.

Usage:  python3 tools/build_assets.py      (needs Pillow + numpy)
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

import gen_characters
import gen_sprites
import gen_world
import gen_audio


def main():
    a = os.path.join(ROOT, "assets")
    for d in ("chars", "portraits", "sprites", "ui", "world", "audio"):
        os.makedirs(os.path.join(a, d), exist_ok=True)
    chars = gen_characters.build(a)
    sprites, icons = gen_sprites.build(a)
    with open(os.path.join(ROOT, "data", "sprites.json"), "w") as f:
        json.dump({"sprites": sprites, "chars": chars, "icons": icons}, f, indent=0)
    world = gen_world.build(sprites, ROOT)
    gen_audio.build(os.path.join(a, "audio"))
    print(f"chars={len(chars)} sprites={len(sprites)} icons={len(icons)} objects={len(world['objects'])}")


if __name__ == "__main__":
    main()
