"""Regenerate every asset of Under One Roof.

Art direction: assets/reference/world_reference.jpg. Buildings, trees and boats are cut
from it; ground materials are synthesised from it; everything else (characters, props,
icons) is generated procedurally and then painted to match it (tools/stylize.py).
All textures are stored at stylize.RES x world resolution.

Usage:  python3 tools/build_assets.py      (needs Pillow, numpy, opencv-python-headless)
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

from PIL import Image
import gen_characters
import gen_people
import gen_sprites
import gen_world
import gen_audio
import gen_materials
import ref_assets
from stylize import painted, painted_frames, RES


def clean(folder, keep_ext=(".import",)):
    os.makedirs(folder, exist_ok=True)
    for f in os.listdir(folder):
        p = os.path.join(folder, f)
        if f.endswith(".png"):
            os.remove(p)


def make_icons(a):
    """App icons from the painted Gideon portrait (desktop + Android adaptive layers)."""
    from PIL import ImageDraw
    face = gen_people.bust(gen_characters.CHARACTERS["gideon"], (140, 156))
    ic = Image.new("RGBA", (192, 192), (0, 0, 0, 0))
    d = ImageDraw.Draw(ic)
    d.rounded_rectangle([0, 0, 191, 191], 34, fill=(95, 60, 34, 255))
    d.rounded_rectangle([10, 10, 181, 181], 26, fill=(238, 222, 184, 255))
    ic.alpha_composite(face.resize((140, 168), Image.LANCZOS), (26, 18))
    ic.save(os.path.join(ROOT, "icon.png"))
    fg = Image.new("RGBA", (432, 432), (0, 0, 0, 0))
    big = face.resize((220, 264), Image.LANCZOS)
    fg.alpha_composite(big, ((432 - big.width) // 2, (432 - big.height) // 2 + 4))
    os.makedirs(os.path.join(a, "icons"), exist_ok=True)
    fg.save(os.path.join(a, "icons", "adaptive_foreground.png"))
    bg = Image.new("RGBA", (432, 432), (226, 196, 140, 255))
    db = ImageDraw.Draw(bg)
    for y in range(300, 432):
        db.line([(0, y), (431, y)], fill=(58, 120, 180, 255) if y > 330 else (236, 214, 166, 255))
    bg.save(os.path.join(a, "icons", "adaptive_background.png"))


def portrait(bust, out_path):
    """Framed bust portrait for the dialogue box."""
    from PIL import ImageDraw
    big = Image.new("RGBA", bust.size, (230, 214, 178, 255))
    big.alpha_composite(bust)
    framed = Image.new("RGBA", (big.width + 12, big.height + 12), (120, 74, 40, 255))
    d = ImageDraw.Draw(framed)
    d.rectangle([0, 0, framed.width - 1, framed.height - 1], outline=(70, 40, 22, 255), width=3)
    d.rectangle([4, 4, framed.width - 5, framed.height - 5], outline=(168, 112, 62, 255), width=1)
    framed.alpha_composite(big, (6, 6))
    framed.save(out_path)


def main():
    a = os.path.join(ROOT, "assets")
    tmp = tempfile.mkdtemp()
    for d in ("chars", "portraits", "sprites", "ui"):
        os.makedirs(os.path.join(tmp, d), exist_ok=True)
        clean(os.path.join(a, d)) if d in ("chars", "portraits", "sprites") else os.makedirs(os.path.join(a, d), exist_ok=True)

    # characters: drawn in the reference style at RES x (tools/gen_people.py)
    chars = {}
    for name, p in gen_characters.CHARACTERS.items():
        gen_people.sheet(p).save(os.path.join(a, "chars", f"{name}.png"))
        portrait(gen_people.bust(p), os.path.join(a, "portraits", f"{name}.png"))
        chars[name] = {"frame_w": gen_characters.FW, "frame_h": gen_characters.FH, "rows": 5, "res": RES}

    # props / interiors / icons: procedural -> painted
    sprites, icons = gen_sprites.build(tmp)
    for name, m in sprites.items():
        src = Image.open(os.path.join(tmp, "sprites", f"{name}.png"))
        if m.get("frames"):
            out = painted_frames(src, m["w"], m["h"], seed=len(name))
        else:
            out = painted(src, seed=len(name))
        out.save(os.path.join(a, "sprites", f"{name}.png"))
        m["res"] = RES
    painted_frames(Image.open(os.path.join(tmp, "ui", "icons.png")), 16, 16).save(os.path.join(a, "ui", "icons.png"))

    # reference cut-outs (buildings, trees, boats)
    gen_materials.build()

    def reg(name, img, meta):
        img.save(os.path.join(a, "sprites", f"{name}.png"))
        sprites[name] = meta
    ref_assets.register(reg, os.path.join(a, "sprites"))

    with open(os.path.join(ROOT, "data", "sprites.json"), "w") as f:
        json.dump({"sprites": sprites, "chars": chars, "icons": icons, "res": RES}, f, indent=0)
    world = gen_world.build(sprites, ROOT)
    gen_audio.build(os.path.join(a, "audio"))
    make_icons(a)
    shutil.rmtree(tmp, ignore_errors=True)
    for script in ("i18n_extract.py", "i18n_build.py", "subset_fonts.py"):
        subprocess.run([sys.executable, os.path.join(HERE, script)], check=True)
    print(f"chars={len(chars)} sprites={len(sprites)} icons={len(icons)} objects={len(world['objects'])}")


if __name__ == "__main__":
    main()
