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
import gen_menu


def make_icons(a):
    """App icons from the current Gideon portrait (desktop + Android adaptive layers)."""
    from PIL import Image, ImageDraw
    face = Image.open(os.path.join(a, "chars", "gideon.png")).crop((0, 0, 20, 24)).convert("RGBA")
    # desktop / legacy launcher icon 192x192
    ic = Image.new("RGBA", (192, 192), (0, 0, 0, 0))
    d = ImageDraw.Draw(ic)
    d.rounded_rectangle([0, 0, 191, 191], 34, fill=(95, 60, 34, 255))
    d.rounded_rectangle([10, 10, 181, 181], 26, fill=(238, 222, 184, 255))
    big = face.resize((20 * 7, 24 * 7), Image.NEAREST)
    ic.alpha_composite(big, (26, 18))
    ic.save(os.path.join(ROOT, "icon.png"))
    # adaptive icon: transparent foreground with the face inside the 66% safe zone, plain background
    fg = Image.new("RGBA", (432, 432), (0, 0, 0, 0))
    big = face.resize((20 * 11, 24 * 11), Image.NEAREST)
    fg.alpha_composite(big, ((432 - big.width) // 2, (432 - big.height) // 2 + 4))
    os.makedirs(os.path.join(a, "icons"), exist_ok=True)
    fg.save(os.path.join(a, "icons", "adaptive_foreground.png"))
    bg = Image.new("RGBA", (432, 432), (226, 196, 140, 255))
    db = ImageDraw.Draw(bg)
    for y in range(300, 432):
        db.line([(0, y), (431, y)], fill=(58, 120, 180, 255) if y > 330 else (236, 214, 166, 255))
    bg.save(os.path.join(a, "icons", "adaptive_background.png"))


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
    make_icons(a)
    gen_menu.build(ROOT)
    # translations + Japanese font subsets (Arabic text -> English / Japanese)
    import subprocess
    for script in ("i18n_extract.py", "i18n_build.py", "subset_fonts.py"):
        subprocess.run([sys.executable, os.path.join(HERE, script)], check=True)
    print(f"chars={len(chars)} sprites={len(sprites)} icons={len(icons)} objects={len(world['objects'])}")


if __name__ == "__main__":
    main()
