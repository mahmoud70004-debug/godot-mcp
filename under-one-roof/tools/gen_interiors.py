"""Cozy interior props for the Nordic coastal homes, in the pixel density of the family
sprites (one art pixel = one world pixel, stored crisp at stylize.RES x).

Besides the usual sprite metadata (w, h, oy, base, frames, fps) props may carry:
  light   [x, y, radius, [r, g, b, a]]  warm flickering glow (fires, candles, lanterns)
  embers  [x, y, width]                 sparks rising from a fire
  wall    true                          hung on the wall (drawn behind actors, no collision)
"""
import os
from PIL import Image
from pixel import Spr, c, shade, mix

OAK, OAK_D, OAK_L, OAK_DD = c("9a6a40"), c("6e4a2c"), c("c08e5a"), c("4a2e1c")
PINE, PINE_D, PINE_L = c("b8854e"), c("8a5e34"), c("d8a868")
STONE, STONE_D, STONE_L = c("8e8a86"), c("625e5c"), c("b4b0a8")
CLOTH_R, CLOTH_R_D = c("a83a32"), c("7a2824")
CREAM = c("eee2c4")
IRON, IRON_L = c("3a3a40"), c("6a6a74")
FIRE = [c("f8e070"), c("f8a830"), c("e05a20"), c("a02a18")]
WARM = [255, 186, 110, 105]

META = {}


def wood_box(s, x, y, w, h, top_h, col=OAK, dark=OAK_D, light=OAK_L):
    """Furniture block seen from the top-down 3/4 view: lit top, darker front."""
    s.r(x, y, w, top_h, col)
    s.hl(x, y, w, light)
    s.r(x, y + top_h, w, h - top_h, dark)
    s.hl(x, y + top_h, w, shade(dark, 0.8))
    s.vl(x, y, h, shade(col, 1.1))


def grain(s, x, y, w, h, col, every=5):
    for yy in range(y + 2, y + h - 1, every):
        for xx in range(x + 1, x + w - 1):
            if (xx * 7 + yy * 3) % 11 == 0:
                s.p(xx, yy, col)


def reg(out, name, frames, oy, base=None, fps=0, **extra):
    frames = frames if isinstance(frames, list) else [frames]
    w, h = frames[0].w, frames[0].h
    strip = Image.new("RGBA", (w * len(frames), h), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        strip.alpha_composite(f.im, (i * w, 0))
    from stylize import RES
    strip.resize((strip.width * RES, strip.height * RES), Image.NEAREST).save(os.path.join(out, f"{name}.png"))
    m = {"w": w, "h": h, "oy": oy, "res": RES}
    if base:
        m["base"] = base
    if len(frames) > 1:
        m["frames"] = len(frames)
        m["fps"] = fps
    m.update(extra)
    META[name] = m


def flame(s, cx, by, f, size=1.0):
    """Layered flame tongues, animated by frame index f."""
    import math
    for i, (dx, hgt) in enumerate(((-3, 6), (0, 9), (3, 7), (-1, 5), (2, 5))):
        hh = int((hgt + ((f + i) % 3) - 1) * size)
        x = cx + dx
        for k in range(hh):
            t = k / max(1, hh)
            wdt = max(1, int((3 - 2.2 * t) * size))
            col = FIRE[0] if t < 0.3 else FIRE[1] if t < 0.6 else FIRE[2]
            sway = int(round(math.sin(f * 1.7 + i + k * 0.4) * t * 1.2))
            s.r(x - wdt // 2 + sway, by - k, wdt, 1, col)
    s.r(cx - 5, by, 11, 2, FIRE[3])


# ---------------------------------------------------------------- props
def hearth(out):
    """Stone fireplace with a wooden mantel, a kettle on the hook and a live fire."""
    frames = []
    for f in range(4):
        s = Spr(40, 40, seed=3)
        s.r(1, 6, 38, 34, STONE)
        for row in range(6, 40, 5):
            off = 0 if (row // 5) % 2 else 4
            for x in range(1 + off, 39, 8):
                s.r(x, row, 7, 4, mix(STONE, STONE_L if (x + row) % 3 else STONE_D, 0.35))
                s.hl(x, row, 7, STONE_L)
        s.r(0, 2, 40, 6, OAK)                         # mantel
        s.hl(0, 2, 40, OAK_L); s.hl(0, 7, 40, OAK_DD)
        s.r(4, 0, 4, 3, c("c0b8a8")); s.r(30, -1, 3, 4, c("e8dcc0")); s.r(31, -2, 1, 1, FIRE[0])   # jug, candle
        s.r(14, 0, 10, 2, c("6a8a5a"))                # dried herbs on the mantel
        s.r(8, 14, 24, 22, c("1c1210"))               # opening
        s.r(10, 16, 20, 4, c("2a1a14"))
        s.r(19, 14, 1, 7, IRON); s.ell(15, 20, 10, 7, IRON); s.hl(16, 21, 8, IRON_L)   # kettle
        s.r(10, 32, 20, 3, c("5a3a22")); s.r(12, 31, 16, 1, c("7a4a2a"))              # logs
        flame(s, 20, 31, f)
        s.r(4, 36, 32, 4, STONE_D); s.hl(4, 36, 32, STONE_L)                          # hearth stone
        s.outline()
        frames.append(s)
    reg(out, "hearth", frames, oy=39, base=[1, 22, 38, 17], fps=8,
        light=[20, 28, 92, WARM], embers=[20, 26, 10])


def firepit(out):
    """Round open fire ringed with stones in the middle of the inn."""
    frames = []
    for f in range(4):
        s = Spr(34, 26, seed=5)
        s.ell(1, 10, 32, 16, STONE_D)
        for i, (x, y) in enumerate(((2, 15), (7, 11), (14, 10), (21, 11), (27, 14), (28, 19), (22, 22), (13, 22), (5, 20))):
            s.ell(x, y, 6, 5, STONE if i % 2 else STONE_L)
        s.ell(7, 13, 20, 10, c("2a1a14"))
        s.r(10, 18, 14, 2, c("5a3a22")); s.r(12, 16, 10, 2, c("7a4a2a"))
        flame(s, 17, 18, f, 1.1)
        s.outline()
        frames.append(s)
    reg(out, "firepit", frames, oy=24, base=[3, 12, 28, 12], fps=8, light=[17, 14, 110, WARM], embers=[17, 10, 8])


def iron_stove(out):
    frames = []
    for f in range(3):
        s = Spr(20, 28, seed=6)
        s.r(8, 0, 4, 8, IRON); s.vl(9, 0, 8, IRON_L)
        s.r(2, 8, 16, 18, IRON); s.hl(2, 8, 16, IRON_L); s.r(1, 7, 18, 2, c("4a4a52"))
        s.r(5, 14, 10, 7, c("1a1210"))
        s.r(6, 15 + f % 2, 8, 5 - f % 2, FIRE[1]); s.r(8, 17, 4, 3, FIRE[0])
        s.r(3, 26, 3, 2, IRON); s.r(14, 26, 3, 2, IRON)
        s.outline()
        frames.append(s)
    reg(out, "iron_stove", frames, oy=27, base=[2, 16, 16, 11], fps=5, light=[10, 17, 64, [255, 170, 90, 120]])


def feast_table(out, name, items=True, cloth=True):
    s = Spr(44, 24, seed=7)
    wood_box(s, 1, 2, 42, 14, 10)
    grain(s, 1, 2, 42, 10, OAK_D)
    s.r(3, 14, 3, 9, OAK_DD); s.r(38, 14, 3, 9, OAK_DD)
    if cloth:
        s.r(14, 2, 16, 13, CREAM); s.hl(14, 2, 16, c("fff6e0")); s.r(14, 12, 16, 3, c("d8c8a4"))
        for x in range(15, 30, 3):
            s.p(x, 14, CLOTH_R)
    if items:
        s.ell(4, 4, 7, 4, c("d8d0c4")); s.ell(5, 5, 5, 2, c("c87a4a"))          # plate with fish
        s.ell(17, 3, 10, 6, c("c8964a")); s.ell(18, 4, 8, 3, c("e0b46a"))      # bread loaf
        s.r(32, 3, 3, 5, OAK_D); s.r(32, 3, 3, 1, c("e8e0d0"))                # wooden cups
        s.r(37, 5, 3, 5, OAK_D); s.r(37, 5, 3, 1, c("e8e0d0"))
        s.r(28, 3, 2, 4, c("f0e6c8")); s.p(28, 2, FIRE[0])                     # candle
        s.ell(9, 8, 5, 3, c("a8a8b0")); s.p(13, 9, c("6a6a72"))                # bowl + spoon
    s.outline()
    extra = {"light": [28, 3, 40, [255, 210, 130, 90]]} if items else {}
    reg(out, name, s, oy=23, base=[1, 8, 42, 14], **extra)


def bench(out):
    s = Spr(36, 10, seed=8)
    wood_box(s, 0, 1, 36, 5, 3, PINE, PINE_D, PINE_L)
    s.r(2, 5, 3, 5, PINE_D); s.r(31, 5, 3, 5, PINE_D)
    s.outline()
    reg(out, "bench_in", s, oy=9, base=[0, 3, 36, 6])


def stool(out):
    s = Spr(10, 11, seed=9)
    s.ell(0, 0, 10, 6, PINE); s.ell(1, 0, 8, 3, PINE_L)
    s.r(1, 5, 2, 6, PINE_D); s.r(7, 5, 2, 6, PINE_D); s.hl(2, 8, 6, PINE_D)
    s.outline()
    reg(out, "stool", s, oy=10, base=[1, 5, 8, 5])


def cupboard(out):
    """Dresser with blue-and-white plates, jars and a pitcher."""
    s = Spr(28, 38, seed=10)
    s.r(1, 0, 26, 38, OAK_D); s.r(0, 0, 28, 3, OAK); s.hl(0, 0, 28, OAK_L)
    for k, y in enumerate((4, 13)):
        s.r(3, y, 22, 8, c("3a2618"))
        s.hl(3, y + 8, 22, OAK)
        if k == 0:
            for x in (4, 10, 16):
                s.ell(x, y + 1, 6, 6, c("e8ecf0")); s.ell(x + 1, y + 2, 4, 4, c("4a6aa8")); s.p(x + 2, y + 3, c("e8ecf0"))
            s.r(22, y + 2, 2, 6, c("c08a3a"))
        else:
            for i, x in enumerate((4, 9, 14, 19)):
                col = [c("b04a3a"), c("c8a040"), c("6a8a4a"), c("8a6a9a")][i]
                s.r(x, y + 2, 4, 6, c("d8d0c0")); s.r(x, y + 4, 4, 4, col); s.hl(x, y + 2, 4, c("8a6a4a"))
    s.r(3, 23, 22, 13, OAK); s.vl(14, 23, 13, OAK_DD); s.hl(3, 23, 22, OAK_L)
    s.p(12, 29, c("d8b050")); s.p(16, 29, c("d8b050"))
    s.outline()
    reg(out, "cupboard", s, oy=37, base=[1, 26, 26, 11])


def kitchen_counter(out):
    s = Spr(40, 28, seed=11)
    s.r(0, 10, 40, 18, OAK_D); s.r(0, 8, 40, 5, OAK); s.hl(0, 8, 40, OAK_L)
    for x in (2, 14, 26):
        s.r(x, 14, 11, 12, OAK); s.r(x + 1, 15, 9, 10, mix(OAK, OAK_D, 0.4)); s.p(x + 5, 20, c("d8b050"))
    s.r(3, 5, 9, 5, IRON); s.ell(3, 3, 9, 4, IRON_L); s.ell(4, 4, 7, 2, c("8a5a3a"))      # pot
    s.r(15, 6, 10, 4, c("c89a64")); s.hl(15, 6, 10, c("e0b882")); s.r(18, 5, 4, 2, c("e05a3a"))  # board + carrot
    s.r(28, 2, 2, 7, c("a8a8b0")); s.r(31, 3, 2, 6, OAK_D); s.r(34, 1, 4, 8, c("c0b0a0"))  # ladle, spoon, jug
    s.p(29, 1, c("c8c8d0"))
    s.outline()
    reg(out, "kitchen_counter", s, oy=27, base=[0, 12, 40, 15])


def bookshelf(out):
    s = Spr(30, 38, seed=12)
    s.r(0, 0, 30, 38, OAK_DD); s.r(2, 2, 26, 33, c("2a1a10")); s.hl(0, 0, 30, OAK)
    rng = s.rng
    cols = [c("8a2a24"), c("2e4a7a"), c("3e6a3a"), c("b08a3a"), c("5a3a6a"), c("7a5a3a"), c("c8b890")]
    for shelf in range(4):
        y = 3 + shelf * 8
        x = 3
        while x < 26:
            bw = rng.randrange(2, 4)
            bh = rng.randrange(5, 8)
            col = rng.choice(cols)
            s.r(x, y + 7 - bh, bw, bh, col); s.vl(x, y + 7 - bh, bh, shade(col, 1.25))
            x += bw + (1 if rng.random() < 0.2 else 0)
        s.hl(2, y + 7, 26, OAK)
    s.r(20, 27, 5, 3, c("d8d0c0"))  # a jar
    s.outline()
    reg(out, "bookshelf_tall", s, oy=37, base=[0, 26, 30, 11])


def armchair(out):
    s = Spr(20, 20, seed=13)
    s.r(2, 0, 16, 10, CLOTH_R_D); s.r(3, 1, 14, 8, CLOTH_R)
    s.r(0, 6, 5, 11, CLOTH_R_D); s.r(15, 6, 5, 11, CLOTH_R_D)
    s.r(4, 9, 12, 7, CLOTH_R); s.hl(4, 9, 12, c("c8564a"))
    s.r(1, 17, 2, 3, OAK_DD); s.r(17, 17, 2, 3, OAK_DD)
    s.outline()
    reg(out, "armchair", s, oy=19, base=[0, 8, 20, 11])


def globe(out):
    s = Spr(12, 20, seed=14)
    s.ell(1, 0, 10, 10, c("3a6a9a")); s.r(3, 2, 3, 3, c("6a9a5a")); s.r(6, 5, 3, 2, c("6a9a5a")); s.p(3, 2, c("a8c8e8"))
    s.line(0, 5, 6, -1, c("c8a040")); s.r(5, 10, 2, 7, OAK_D); s.r(2, 17, 8, 3, OAK_D)
    s.outline()
    reg(out, "globe", s, oy=19, base=[2, 15, 8, 5])


def plant(out):
    s = Spr(14, 18, seed=15)
    s.r(3, 11, 8, 7, c("b0603a")); s.hl(2, 11, 10, c("c8784a"))
    for (x0, y0, x1, y1) in ((7, 11, 2, 2), (7, 11, 12, 1), (7, 11, 7, 0), (7, 11, 4, 4), (7, 11, 11, 5)):
        s.line(x0, y0, x1, y1, c("4a8a3a"))
    for (x, y) in ((1, 1), (11, 0), (6, -1), (3, 3), (10, 4)):
        s.ell(x, y + 1, 4, 3, c("5aa04a"))
    s.outline()
    reg(out, "plant_pot", s, oy=17, base=[3, 13, 8, 5])


def candlestick(out):
    frames = []
    for f in range(2):
        s = Spr(8, 16, seed=16)
        s.r(3, 4, 2, 8, c("f0e6c8")); s.r(2, 12, 4, 2, c("c8a040")); s.r(1, 14, 6, 2, c("a8862e"))
        s.r(3, 1 + f, 2, 3 - f, FIRE[1]); s.p(3, 2 + f, FIRE[0])
        s.outline()
        frames.append(s)
    reg(out, "candlestick", frames, oy=15, fps=4, light=[4, 2, 34, [255, 210, 130, 110]])


def lantern_wall(out):
    frames = []
    for f in range(2):
        s = Spr(10, 14, seed=17)
        s.r(4, 0, 2, 2, IRON); s.r(1, 2, 8, 2, IRON); s.r(2, 4, 6, 8, IRON)
        s.r(3, 5, 4, 6, c("f8d070") if f == 0 else c("f0c060")); s.r(4, 7, 2, 3, c("fff0b0"))
        s.r(1, 12, 8, 2, IRON)
        s.outline()
        frames.append(s)
    reg(out, "lantern_wall", frames, oy=14, fps=3, wall=True, light=[5, 8, 52, [255, 200, 120, 120]])


def wall_shelf(out, name, kind):
    s = Spr(30, 16, seed=18)
    s.r(0, 12, 30, 3, OAK); s.hl(0, 12, 30, OAK_L); s.r(2, 15, 2, 1, OAK_D); s.r(26, 15, 2, 1, OAK_D)
    if kind == "bottles":
        for i, x in enumerate(range(2, 28, 4)):
            col = [c("3a6a3a"), c("8a3a2a"), c("c8a040"), c("3a4a7a")][i % 4]
            h = 7 + (i % 3)
            s.r(x, 12 - h, 3, h, col); s.r(x + 1, 12 - h - 2, 1, 2, col); s.vl(x, 12 - h, h, shade(col, 1.4))
    elif kind == "jars":
        for i, x in enumerate(range(2, 28, 6)):
            s.r(x, 5, 5, 7, c("d8d0c0")); s.r(x, 8, 5, 4, [c("c87a3a"), c("6a8a4a"), c("b04a3a"), c("e0c060"), c("8a6a4a")][i % 5])
            s.r(x, 4, 5, 1, c("8a6a4a"))
    elif kind == "herbs":
        for i, x in enumerate(range(3, 28, 5)):
            s.vl(x + 1, 0, 3, c("8a6a4a"))
            s.r(x, 3, 3, 8, [c("6a8a4a"), c("8aa05a"), c("a0804a"), c("7a9a5a")][i % 4])
            s.p(x + 1, 11, c("5a7a3a"))
    s.outline()
    reg(out, name, s, oy=16, wall=True)


def window_curtains(out):
    s = Spr(20, 20, seed=19)
    s.r(1, 1, 18, 16, c("e8e0cc")); s.r(3, 3, 14, 12, c("9ac8e8")); s.r(3, 3, 6, 5, c("c8e4f4"))
    s.vl(10, 3, 12, c("e8e0cc")); s.hl(3, 9, 14, c("e8e0cc"))
    s.r(0, 0, 5, 19, CLOTH_R); s.r(15, 0, 5, 19, CLOTH_R); s.vl(2, 1, 17, CLOTH_R_D); s.vl(17, 1, 17, CLOTH_R_D)
    s.r(-1, 0, 22, 1, OAK_D); s.r(0, 17, 20, 3, OAK); s.hl(0, 17, 20, OAK_L)
    s.r(3, 15, 3, 2, c("c86a8a")); s.r(14, 15, 3, 2, c("e0c040"))   # little flower pots
    s.outline()
    reg(out, "window_curtains", s, oy=20, wall=True)


def fish_trophy(out):
    s = Spr(22, 12, seed=20)
    s.r(0, 0, 22, 12, OAK_D); s.r(1, 1, 20, 10, OAK)
    s.ell(3, 3, 13, 6, c("7a96a8")); s.poly([(15, 6), (20, 2), (20, 10)], c("5a7688")); s.p(5, 5, c("1a1a1a"))
    s.hl(5, 4, 8, c("a8c0d0"))
    s.outline()
    reg(out, "fish_trophy", s, oy=12, wall=True)


def rugs(out):
    s = Spr(60, 36, seed=21)        # braided oval rug
    for i, col in enumerate((c("7a2e28"), c("b8873a"), c("2e4a6a"), c("a83a32"), c("d8b870"), c("3e6a4a"), c("8a2e28"))):
        s.ell(i * 3, i * 2, 60 - i * 6, 36 - i * 4, col)
    for y in range(2, 34, 3):
        for x in range(2, 58, 4):
            if s.get(x, y)[3]:
                s.p(x, y, shade(s.get(x, y), 0.85))
    reg(out, "rug_round", s, oy=36, flat=True)
    s = Spr(72, 30, seed=22)        # long woven runner with fringes
    s.r(3, 0, 66, 30, c("8a2e28")); s.r(6, 3, 60, 24, c("b8873a")); s.r(9, 6, 54, 18, c("6a2a2a"))
    for x in range(10, 62, 8):
        s.poly([(x, 15), (x + 4, 9), (x + 8, 15), (x + 4, 21)], c("d8b870"))
        s.p(x + 4, 15, c("2e4a6a"))
    for y in range(1, 30, 2):
        s.hl(0, y, 3, c("d8c8a0")); s.hl(69, y, 3, c("d8c8a0"))
    reg(out, "rug_long", s, oy=30, flat=True)
    s = Spr(40, 28, seed=23)        # sheepskin by the fire
    s.ell(0, 2, 40, 24, c("e8e0d0")); s.ell(4, 0, 8, 8, c("e8e0d0")); s.ell(28, 0, 8, 8, c("e8e0d0"))
    s.ell(4, 20, 8, 8, c("e8e0d0")); s.ell(28, 20, 8, 8, c("e8e0d0"))
    s.speckle(0, 0, 40, 28, [c("d0c8b8"), c("f8f4ec")], 0.25)
    reg(out, "rug_fur", s, oy=28, flat=True)


def bed_cozy(out, name, blanket, dark):
    s = Spr(22, 34, seed=24)
    s.r(0, 0, 22, 6, OAK_D); s.hl(0, 0, 22, OAK); s.r(1, 6, 20, 26, OAK)
    s.r(2, 6, 18, 6, c("f4ecdc")); s.ell(3, 6, 8, 5, c("fffaf0")); s.ell(11, 6, 8, 5, c("fffaf0"))
    s.r(2, 12, 18, 18, blanket); s.hl(2, 12, 18, shade(blanket, 1.25))
    for y in range(15, 30, 4):
        s.hl(2, y, 18, dark)
    for x in range(5, 20, 5):
        s.vl(x, 13, 17, shade(blanket, 0.9))
    s.r(0, 32, 3, 2, OAK_DD); s.r(19, 32, 3, 2, OAK_DD)
    s.outline()
    reg(out, name, s, oy=33, base=[0, 4, 22, 29])


def barrels(out):
    s = Spr(30, 26, seed=25)
    for (x, y) in ((0, 8), (15, 8), (7, 0)):
        s.r(x + 1, y + 2, 13, 15, OAK); s.ell(x, y, 15, 5, OAK_L); s.ell(x + 2, y + 1, 11, 3, OAK_D)
        s.hl(x + 1, y + 6, 13, IRON); s.hl(x + 1, y + 13, 13, IRON)
        s.vl(x + 4, y + 3, 13, OAK_L)
    s.outline()
    reg(out, "barrel_stack", s, oy=25, base=[0, 14, 30, 11])


def stall_fence(out):
    s = Spr(48, 18, seed=26)
    for x in (0, 23, 45):
        s.r(x, 0, 3, 18, PINE_D); s.hl(x, 0, 3, PINE_L)
    for y in (3, 9):
        s.r(0, y, 48, 3, PINE); s.hl(0, y, 48, PINE_L)
    s.outline()
    reg(out, "stall_fence", s, oy=17, base=[0, 12, 48, 5])


def bedroll(out):
    s = Spr(18, 30, seed=27)
    s.r(1, 0, 16, 30, c("6a5a3a")); s.r(2, 1, 14, 6, c("c8b890")); s.r(2, 8, 14, 21, c("5a6a4a"))
    for y in range(10, 29, 4):
        s.hl(2, y, 14, c("4a5a3a"))
    reg(out, "bedroll", s, oy=30, flat=True)


def cobweb(out):
    s = Spr(16, 16, seed=28)
    col = (230, 230, 230, 150)
    for k in range(0, 16, 4):
        s.line(0, k, k, 0, col)
    s.line(0, 0, 15, 15, col); s.line(0, 0, 15, 7, col); s.line(0, 0, 7, 15, col)
    reg(out, "cobweb", s, oy=16, wall=True)


def wood_pile(out):
    s = Spr(24, 16, seed=29)
    for i, (x, y) in enumerate(((0, 8), (8, 8), (16, 8), (4, 2), (12, 2))):
        s.r(x, y, 8, 7, OAK if i % 2 else PINE); s.ell(x + 1, y + 1, 6, 5, c("d8b880")); s.ell(x + 3, y + 3, 2, 2, OAK_D)
    s.outline()
    reg(out, "firewood_in", s, oy=15, base=[0, 8, 24, 7])


def net_wall(out):
    s = Spr(34, 22, seed=30)
    col = c("a89a7a")
    s.hl(0, 0, 34, OAK_D)
    for x in range(0, 34, 4):
        s.line(x, 1, x + 4, 21, col)
        s.line(x + 4, 1, x, 21, col)
    for (x, y) in ((6, 8), (18, 12), (26, 6)):
        s.ell(x, y, 5, 5, c("d85a3a"))     # floats
    reg(out, "net_hanging", s, oy=22, wall=True)


# ---------------------------------------------------------------- outdoor details
def net_posts(out):
    """Fishing net hung to dry between two posts, with cork floats."""
    s = Spr(40, 30, seed=31)
    for x in (2, 35):
        s.r(x, 0, 3, 30, OAK_D); s.vl(x, 0, 30, OAK_L)
    s.hl(3, 2, 34, c("6a5a44"))
    col = c("b8a888")
    for x in range(5, 35, 4):
        s.line(x, 3, x + 3, 22, col); s.line(x + 3, 3, x, 22, col)
    s.hl(5, 22, 30, col)
    for (x, y) in ((8, 12), (17, 17), (27, 10), (31, 19)):
        s.ell(x, y, 4, 4, c("e06a3a")); s.p(x + 1, y + 1, c("f8a070"))
    s.outline()
    reg(out, "net_posts", s, oy=29, base=[0, 25, 40, 5])


def grass_tufts(out):
    for k in range(3):
        s = Spr(14, 12, seed=40 + k)
        for i in range(7 + k * 2):
            x = s.rng.randrange(1, 13)
            h = s.rng.randrange(5, 11)
            col = s.rng.choice([c("4e8a36"), c("6aa648"), c("88bc5a"), c("3e7a30")])
            lean = s.rng.choice([-2, -1, 0, 1, 2])
            s.line(x, 11, x + lean, 11 - h, col)
        reg(out, f"grass_tuft_{k}", s, oy=11)


def wildflowers(out):
    palettes = [[c("b05ab8"), c("d088d8")], [c("f4f0e8"), c("fffaf0")], [c("e8c040"), c("f8e070")]]
    for k, pal in enumerate(palettes):
        s = Spr(16, 12, seed=50 + k)
        for i in range(6):
            x, h = s.rng.randrange(1, 15), s.rng.randrange(4, 10)
            s.line(x, 11, x, 11 - h, c("4e8a36"))
            if k == 0:   # fireweed: a spike of blossoms
                for j in range(3):
                    s.p(x, 11 - h + j, pal[j % 2]); s.p(x + 1, 12 - h + j, pal[0])
            else:        # cotton grass / buttercups: a round head
                s.r(x - 1, 10 - h, 3, 2, pal[0]); s.p(x, 10 - h, pal[1])
        reg(out, f"wildflowers_{k}", s, oy=11)


def snow_patches(out):
    for k, (w, h) in enumerate(((34, 16), (22, 12), (46, 20))):
        s = Spr(w, h, seed=60 + k)
        for i in range(6 + k * 2):
            bw, bh = s.rng.randrange(w // 4, w // 2), s.rng.randrange(h // 3, h // 2 + 2)
            x, y = s.rng.randrange(0, w - bw), s.rng.randrange(0, h - bh)
            s.ell(x, y + 1, bw, bh, c("c8d4e0", 200))
            s.ell(x, y, bw, bh - 1, c("f4f8fc", 230))
        s.speckle(0, 0, w, h, [c("ffffff", 240), c("dce6f0", 220)], 0.12)
        reg(out, f"snow_{k}", s, oy=h, flat=True)


def build(out_dir):
    META.clear()
    for f in (hearth, firepit, iron_stove, bench, stool, cupboard, kitchen_counter, bookshelf, armchair, globe, plant,
              candlestick, lantern_wall, window_curtains, fish_trophy, rugs, barrels, stall_fence, bedroll, cobweb,
              wood_pile, net_wall, net_posts, grass_tufts, wildflowers, snow_patches):
        f(out_dir)
    feast_table(out_dir, "table_feast")
    feast_table(out_dir, "table_inn", items=True, cloth=False)
    feast_table(out_dir, "table_old", items=False, cloth=False)
    wall_shelf(out_dir, "shelf_bottles", "bottles")
    wall_shelf(out_dir, "shelf_jars", "jars")
    wall_shelf(out_dir, "herbs_hanging", "herbs")
    bed_cozy(out_dir, "bed_quilt", c("4a6a9a"), c("3a5a8a"))
    bed_cozy(out_dir, "bed_quilt_red", c("a84a3a"), c("8a3a2a"))
    bed_cozy(out_dir, "bed_worn", c("8a7a5a"), c("6a5a3a"))
    return dict(META)


if __name__ == "__main__":
    import sys
    os.makedirs(sys.argv[1], exist_ok=True)
    print(sorted(build(sys.argv[1])))
