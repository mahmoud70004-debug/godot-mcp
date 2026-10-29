"""Procedural pixel-art buildings, props, furniture and item icons.

Each sprite registers metadata used by the game (data/sprites.json):
  w, h        sprite size in px
  frames, fps optional horizontal animation strip
  oy          y (local px) of the footprint bottom; used as the node origin for y-sorting
  base        [x, y, w, h] collision rect in local px (omit for walk-through decor)
  door        [x, y] local px of the door threshold (buildings only)
  flat        true for ground decals that are drawn below actors
"""
import math
import zlib
from PIL import Image
from pixel import Spr, c, shade, mix, sheet, OUTLINE

META = {}
OUT = "."


def reg(name, spr, base=None, oy=None, door=None, frames=None, fps=0, flat=False):
    if frames:
        im = sheet(frames, len(frames))
        w, h = frames[0].w, frames[0].h
    else:
        im = spr.im
        w, h = spr.w, spr.h
    im.save(f"{OUT}/sprites/{name}.png")
    m = {"w": w, "h": h, "oy": oy if oy is not None else h}
    if base:
        m["base"] = base
    if door:
        m["door"] = door
    if frames:
        m["frames"] = len(frames)
        m["fps"] = fps
    if flat:
        m["flat"] = True
    META[name] = m


# --------------------------------------------------------------------------
# palette
WOOD = c("8e623e"); WOOD_D = c("6a4630"); WOOD_L = c("b0804e")
STONE = c("9a9aa4"); STONE_D = c("74747e"); STONE_L = c("bcbcc4")
SLATE = c("4a5268"); SLATE_D = c("363c4e"); SLATE_L = c("626c86")
WHITE = c("ece6d6"); GLASS = c("3a5a7a"); GLASS_L = c("8ab8d8")
GRASS = c("6aa84f"); GRASS_D = c("4e8a3e"); GRASS_L = c("8cc060")

WALLS = {
    "red": c("b04034"), "blue": c("4a76b0"), "yellow": c("dcb048"),
    "green": c("5f9a5c"), "white": c("e6e0cc"), "ochre": c("c08a3a"),
}


def window(s, x, y, w=8, h=8, broken=False, boarded=False, box=None):
    s.r(x - 1, y - 1, w + 2, h + 2, WHITE)
    s.r(x, y, w, h, c("1e2a3a") if broken else GLASS)
    if not broken:
        s.r(x, y, w // 2 - 1, h // 2 - 1, mix(GLASS, GLASS_L, 0.4))
        s.p(x + 1, y + 1, GLASS_L)
    s.vl(x + w // 2 - 1, y, h, WHITE)
    s.hl(x, y + h // 2 - 1, w, WHITE)
    if broken:
        s.line(x, y + 2, x + 3, y + h - 1, c("4a5a6a"))
    if boarded:
        s.line(x - 1, y, x + w, y + h - 2, WOOD_L, 2)
        s.line(x - 1, y + h - 2, x + w, y, WOOD, 2)
    if box:
        s.r(x - 1, y + h + 1, w + 2, 3, WOOD_D)
        for i in range(0, w + 2, 2):
            s.p(x - 1 + i, y + h, box[i // 2 % len(box)])


def door(s, x, y, w=8, h=12, col=WOOD_D, arch=False):
    s.r(x - 1, y - 1, w + 2, h + 1, WHITE if not arch else STONE_L)
    s.r(x, y, w, h, col)
    for i in range(2, w, 3):
        s.vl(x + i, y, h, shade(col, 0.82))
    s.p(x + w - 2, y + h // 2, c("e0c060"))
    if arch:
        s.r(x, y - 2, w, 2, col)


def roof_rows(s, x, y, w, h, col, dark, light, patchy=False):
    s.r(x, y, w, h, col)
    for yy in range(y + 2, y + h, 3):
        s.hl(x, yy, w, dark)
        off = (yy // 3) % 2 * 3
        for xx in range(x + off, x + w, 6):
            s.p(xx, yy - 1, dark)
    s.hl(x, y, w, light)
    s.hl(x, y + h - 1, w, shade(dark, 0.8))
    if patchy:
        rng = s.rng
        for _ in range(w // 10):
            px, py = rng.randrange(x + 2, x + w - 8), rng.randrange(y + 2, y + h - 5)
            s.r(px, py, rng.randrange(4, 8), rng.randrange(3, 5), rng.choice([c("6a5040"), c("5a6a40"), c("806850")]))
        s.speckle(x, y, w, h, [c("5a8a3a"), c("4a7a32")], 0.06)


def planks(s, x, y, w, h, col, vertical=True, weathered=False):
    s.r(x, y, w, h, col)
    dark = shade(col, 0.82)
    if vertical:
        for xx in range(x + 3, x + w, 4):
            s.vl(xx, y, h, dark)
    else:
        for yy in range(y + 2, y + h, 3):
            s.hl(x, yy, w, dark)
    s.hl(x, y, w, shade(col, 0.7))  # shadow under eaves
    s.hl(x, y + 1, w, shade(col, 0.85))
    if weathered:
        s.speckle(x, y, w, h, [shade(col, 0.7), mix(col, c("9a9a90"), 0.5)], 0.08)


def house(name, w, h, wall, roof=(SLATE, SLATE_D, SLATE_L), windows=2, shabby=False, chimney=True,
          broken=False, flowers=None, door_col=WOOD_D, turf=False):
    s = Spr(w, h, seed=zlib.crc32(name.encode()) & 0xffff)
    roof_h = int(h * 0.48)
    wall_y = roof_h - 2
    wall_h = h - wall_y - 3
    if shabby:
        wall = mix(wall, c("8a8478"), 0.45)
    # wall
    planks(s, 2, wall_y, w - 4, wall_h, wall, weathered=shabby)
    s.r(2, h - 5, w - 4, 2, STONE_D)
    s.vl(2, wall_y, wall_h, WHITE if not shabby else c("b0a890"))
    s.vl(w - 3, wall_y, wall_h, WHITE if not shabby else c("b0a890"))
    # roof
    if turf:
        s.r(0, 4, w, roof_h - 3, GRASS)
        s.speckle(0, 4, w, roof_h - 3, [GRASS_D, GRASS_L, c("7ab858")], 0.35)
        s.hl(0, roof_h, w, GRASS_D)
        for xx in range(1, w - 1, 3):
            s.p(xx, 3, GRASS_L)
        if chimney:
            s.r(w - 16, 0, 6, 8, STONE)
            s.hl(w - 16, 0, 6, STONE_D)
    else:
        if chimney:
            cx = w - 14
            s.r(cx, 0, 6, 10, c("8a4a3a"))
            s.hl(cx - 1, 0, 8, STONE_D)
        roof_rows(s, 0, 5, w, roof_h - 4, *roof, patchy=shabby)
    # door
    dx = w // 2 - 4
    dy = h - 3 - 14
    door(s, dx, dy, 8, 12, door_col)
    s.r(dx - 1, h - 3, 10, 2, STONE_L)
    # windows
    wy = wall_y + 5
    slots = []
    if windows >= 2:
        slots = [w // 4 - 4, w - w // 4 - 4]
    elif windows == 1:
        slots = [w - w // 4 - 4]
    for i, wx in enumerate(slots):
        window(s, wx, wy, broken=broken, boarded=(shabby and i == 0), box=flowers)
    if shabby:
        # crooked broken plank and a patch
        s.line(6, h - 10, 12, h - 13, shade(wall, 0.6))
        s.r(w - 12, wall_y + 4, 6, 5, c("7a6a50"))
    s.outline()
    s.shadow(2, h - 6, w - 2, 6)
    base = [2, wall_y + 4, w - 4, h - wall_y - 6]
    reg(name, s, base=base, oy=h - 2, door=[w // 2, h - 2])


def church():
    w, h = 72, 112
    s = Spr(w, h, seed=7)
    body_y = 52
    # nave roof + walls
    roof_rows(s, 0, body_y - 16, w, 26, SLATE, SLATE_D, SLATE_L)
    planks(s, 3, body_y + 8, w - 6, h - body_y - 11, WHITE)
    s.r(3, h - 5, w - 6, 2, STONE_D)
    for wx in (8, w - 16):
        s.r(wx, body_y + 18, 8, 14, GLASS)
        s.r(wx + 1, body_y + 16, 6, 2, GLASS)
        s.p(wx + 2, body_y + 19, GLASS_L)
        s.vl(wx + 3, body_y + 16, 16, c("c8b060"))
    # tower
    tx, tw = w // 2 - 11, 22
    planks(s, tx, 30, tw, h - 33, c("f2eee2"))
    s.vl(tx, 30, h - 33, STONE_L)
    s.vl(tx + tw - 1, 30, h - 33, STONE_L)
    s.r(tx + 6, 36, 10, 10, c("2a2a34"))  # belfry
    s.r(tx + 9, 39, 4, 5, c("c8a040"))     # bell
    s.poly([(tx - 3, 31), (tx + tw + 2, 31), (w // 2, 2)], SLATE_D)
    s.poly([(tx - 1, 30), (w // 2, 4), (w // 2, 30)], SLATE)
    s.r(w // 2 - 1, 0, 2, 6, c("e0c060"))
    s.r(w // 2 - 3, 1, 6, 1, c("e0c060"))
    # round window
    s.ell(w // 2 - 4, 52, 8, 8, c("c8a040"))
    s.ell(w // 2 - 3, 53, 6, 6, GLASS)
    # door
    door(s, w // 2 - 5, h - 19, 10, 16, WOOD_D, arch=True)
    s.r(w // 2 - 7, h - 3, 14, 2, STONE_L)
    s.outline()
    s.shadow(2, h - 6, w - 2, 6)
    reg("church", s, base=[3, body_y + 12, w - 6, h - body_y - 14], oy=h - 2, door=[w // 2, h - 2])


def manor():
    w, h = 152, 104
    s = Spr(w, h, seed=11)
    cream = c("efe4c8")
    roof_y, roof_h = 8, 40
    for cx in (22, w - 30):
        s.r(cx, 0, 8, 14, c("9a5a4a"))
        s.hl(cx - 1, 0, 10, STONE_D)
    roof_rows(s, 0, roof_y, w, roof_h, c("3e4660"), c("2c3246"), c("58627e"))
    # dormers
    for dx in (30, w // 2 - 6, w - 42):
        s.r(dx, roof_y + 12, 12, 14, cream)
        s.poly([(dx - 2, roof_y + 12), (dx + 13, roof_y + 12), (dx + 6, roof_y + 4)], c("2c3246"))
        window(s, dx + 2, roof_y + 15, 8, 8)
    wall_y = roof_y + roof_h - 2
    s.r(3, wall_y, w - 6, h - wall_y - 3, cream)
    for yy in range(wall_y + 3, h - 4, 4):
        s.hl(3, yy, w - 6, shade(cream, 0.94))
    s.hl(3, wall_y, w - 6, shade(cream, 0.7))
    # stone quoins
    for yy in range(wall_y, h - 4, 4):
        s.r(3, yy, 4 if (yy // 4) % 2 else 6, 3, STONE_L)
        s.r(w - 9 if (yy // 4) % 2 else w - 7, yy, 6, 3, STONE_L)
    s.r(3, h - 6, w - 6, 3, STONE_D)
    for row, wy in enumerate((wall_y + 6, wall_y + 28)):
        for wx in range(14, w - 14, 22):
            if abs(wx + 4 - w // 2) < 14 and row == 1:
                continue
            window(s, wx, wy, 8, 12, box=[c("d04a5a"), c("f0c040")] if row == 1 else None)
    # portico
    px = w // 2 - 16
    s.poly([(px - 2, wall_y + 22), (px + 34, wall_y + 22), (w // 2, wall_y + 12)], WHITE)
    s.r(px, wall_y + 22, 32, 3, WHITE)
    for cx in (px + 1, px + 27):
        s.r(cx, wall_y + 25, 4, h - wall_y - 30, c("f8f4ea"))
        s.vl(cx + 3, wall_y + 25, h - wall_y - 30, STONE_L)
    door(s, w // 2 - 6, h - 22, 12, 17, c("5a2a2a"))
    s.r(px - 2, h - 5, 36, 2, STONE_L)
    s.r(px - 4, h - 3, 40, 2, STONE)
    s.outline()
    s.shadow(2, h - 7, w - 2, 7)
    reg("manor", s, base=[3, wall_y + 6, w - 6, h - wall_y - 8], oy=h - 2, door=[w // 2, h - 2])


def inn():
    w, h = 104, 84
    s = Spr(w, h, seed=3)
    roof_h = 34
    for cx in (12, w - 22):
        s.r(cx, 0, 7, 12, c("8a4a3a"))
        s.hl(cx - 1, 0, 9, STONE_D)
    roof_rows(s, 0, 6, w, roof_h, c("7a3a30"), c("5a2a24"), c("9a5040"))
    wall = c("6e4a34")
    planks(s, 3, roof_h + 4, w - 6, h - roof_h - 7, wall, vertical=False)
    s.r(3, h - 5, w - 6, 2, STONE_D)
    for wx in range(10, w - 10, 18):
        window(s, wx, roof_h + 9, 8, 8, box=[c("e05050"), c("f0d040"), c("e070c0")])
    for wx in (10, 28, w - 36, w - 18):
        window(s, wx, roof_h + 27, 8, 10)
    door(s, w // 2 - 6, h - 19, 12, 16, c("4a2a1a"))
    # hanging sign with a mug
    sx = w // 2 + 10
    s.hl(sx - 2, roof_h + 24, 12, c("2a2a2a"))
    s.r(sx, roof_h + 26, 12, 9, c("d0a060"))
    s.r(sx + 3, roof_h + 28, 5, 5, c("f0e0b0"))
    s.r(sx + 8, roof_h + 29, 1, 3, c("f0e0b0"))
    # lantern
    s.r(w // 2 - 10, roof_h + 26, 3, 4, c("f8d060"))
    s.r(w // 2 - 6, h - 3, 12, 2, STONE_L)
    s.outline()
    s.shadow(2, h - 6, w - 2, 6)
    reg("inn", s, base=[3, roof_h + 8, w - 6, h - roof_h - 10], oy=h - 2, door=[w // 2, h - 2])


def warehouse():
    w, h = 84, 62
    s = Spr(w, h, seed=5)
    roof_rows(s, 0, 2, w, 26, SLATE, SLATE_D, SLATE_L)
    planks(s, 3, 26, w - 6, h - 29, c("8a3a30"))
    s.r(3, h - 5, w - 6, 2, STONE_D)
    s.r(w // 2 - 12, h - 26, 24, 23, c("4a2a20"))
    s.line(w // 2 - 12, h - 26, w // 2 + 11, h - 4, WOOD_L)
    s.line(w // 2 + 11, h - 26, w // 2 - 12, h - 4, WOOD_L)
    s.vl(w // 2, h - 26, 23, c("2a1a14"))
    window(s, 10, 32, 8, 6)
    window(s, w - 18, 32, 8, 6)
    s.outline()
    s.shadow(2, h - 6, w - 2, 6)
    reg("warehouse", s, base=[3, 30, w - 6, h - 32], oy=h - 2, door=[w // 2, h - 2])


def smithy():
    w, h = 72, 60
    s = Spr(w, h, seed=9)
    s.r(w - 18, 0, 8, 18, STONE_D)
    s.r(w - 19, 0, 10, 2, STONE)
    roof_rows(s, 0, 8, w, 22, c("4a4038"), c("342c26"), c("5e544a"))
    planks(s, 3, 28, w - 6, h - 31, c("5a3e2c"))
    s.r(3, h - 5, w - 6, 2, STONE_D)
    # open forge
    s.r(8, 34, 26, 20, c("1e1612"))
    s.r(12, 44, 18, 10, STONE_D)
    s.r(15, 45, 12, 5, c("f08a2a"))
    s.r(17, 46, 8, 3, c("f8d050"))
    door(s, w - 24, h - 17, 10, 14, WOOD_D)
    s.outline()
    s.shadow(2, h - 6, w - 2, 6)
    reg("smithy", s, base=[3, 32, w - 6, h - 34], oy=h - 2, door=[w - 19, h - 2])


def barn():
    w, h = 104, 92
    s = Spr(w, h, seed=13)
    red = mix(c("a03a2e"), c("8a7a70"), 0.3)
    gy = 30
    s.poly([(0, gy + 2), (w // 2, 0), (w - 1, gy + 2)], c("4a3a34"))
    s.poly([(5, gy + 2), (w // 2, 5), (w - 6, gy + 2)], red)
    planks(s, 5, gy, w - 10, h - gy - 3, red, weathered=True)
    s.poly([(8, gy), (w // 2, 8), (w - 9, gy)], red)
    for xx in range(10, w - 10, 4):
        top = gy - int((w // 2 - abs(xx - w // 2)) * gy / (w // 2)) + 9
        s.vl(xx, max(top, 9), gy - max(top, 9), shade(red, 0.82))
    # hayloft
    s.r(w // 2 - 7, 14, 14, 12, c("3a2620"))
    s.line(w // 2 - 7, 14, w // 2 + 6, 25, WHITE)
    # big doors
    dx, dy, dw, dh = w // 2 - 20, h - 40, 40, 37
    s.r(dx - 1, dy - 1, dw + 2, dh + 1, c("d8d0c0"))
    s.r(dx, dy, dw, dh, shade(red, 0.85))
    for half in (0, dw // 2):
        s.line(dx + half, dy, dx + half + dw // 2 - 1, dy + dh - 1, c("d8d0c0"))
        s.line(dx + half + dw // 2 - 1, dy, dx + half, dy + dh - 1, c("d8d0c0"))
    s.vl(w // 2, dy, dh, c("d8d0c0"))
    # small window (Gideon peeks through it)
    window(s, 12, gy + 14, 8, 8, broken=True)
    s.r(5, h - 5, w - 10, 2, STONE_D)
    s.speckle(5, gy, w - 10, h - gy, [c("4e7a34"), c("5e8a3e")], 0.02)
    s.outline()
    s.shadow(2, h - 6, w - 2, 6)
    reg("barn", s, base=[5, gy + 6, w - 10, h - gy - 8], oy=h - 2, door=[w // 2, h - 2])


def market_stall(name, awning):
    s = Spr(36, 36, seed=17)
    s.r(4, 10, 2, 22, WOOD_D)
    s.r(30, 10, 2, 22, WOOD_D)
    for i in range(0, 36, 6):
        s.r(i, 4, 6, 9, awning if (i // 6) % 2 == 0 else WHITE)
    s.hl(0, 12, 36, shade(awning, 0.7))
    for i in range(0, 36, 6):
        s.r(i + 1, 13, 4, 2, awning if (i // 6) % 2 == 0 else WHITE)
    s.r(2, 22, 32, 10, WOOD)
    s.hl(2, 22, 32, WOOD_L)
    s.vl(18, 23, 9, WOOD_D)
    goods = [c("e8d070"), c("7ac0e0"), c("e06040"), c("a0d060"), c("f0f0f0")]
    for i in range(5):
        s.r(5 + i * 6, 18, 4, 4, goods[(i + len(name)) % 5])
    s.outline()
    s.shadow(1, 30, 34, 6)
    reg(name, s, base=[2, 24, 32, 8], oy=34)


def cart():
    s = Spr(44, 32, seed=19)
    s.poly([(4, 18), (8, 4), (36, 4), (40, 18)], c("e8dcc0"))
    for xx in range(10, 36, 6):
        s.vl(xx, 5, 13, c("d0c4a8"))
    s.r(2, 17, 40, 8, WOOD)
    s.hl(2, 17, 40, WOOD_L)
    for wx in (6, 30):
        s.ell(wx, 21, 10, 10, WOOD_D)
        s.ell(wx + 3, 24, 4, 4, WOOD_L)
    s.r(40, 20, 4, 2, WOOD_D)
    s.r(14, 12, 4, 5, c("6a8ac0"))
    s.r(20, 13, 5, 4, c("c06a4a"))
    s.outline()
    s.shadow(2, 27, 42, 5)
    reg("cart", s, base=[3, 20, 38, 9], oy=30)


def carriage():
    w, h = 72, 40
    s = Spr(w, h, seed=21)
    navy = c("24305a")
    # horse
    hb = c("6a4228")
    s.r(4, 18, 20, 10, hb)
    s.r(2, 10, 7, 12, hb)
    s.r(0, 10, 4, 5, hb)
    s.r(5, 8, 3, 3, c("2a1a12"))
    for lx in (5, 10, 17, 22):
        s.r(lx, 28, 2, 8, shade(hb, 0.8))
        s.r(lx, 35, 2, 1, c("1a1a1a"))
    s.r(22, 18, 4, 2, c("2a1a12"))
    # carriage body
    s.r(28, 6, 40, 4, shade(navy, 0.8))
    s.r(30, 10, 36, 18, navy)
    s.hl(30, 10, 36, c("c8a040"))
    s.hl(30, 27, 36, c("c8a040"))
    window(s, 34, 13, 10, 8)
    window(s, 52, 13, 10, 8)
    s.r(24, 20, 6, 2, WOOD_D)
    for wx in (30, 54):
        s.ell(wx, 24, 13, 13, c("2a2a2a"))
        s.ell(wx + 4, 28, 5, 5, c("c8a040"))
    s.outline()
    s.shadow(2, h - 6, w - 2, 6)
    reg("carriage", s, base=[2, 26, w - 4, 10], oy=h - 2)


def boat(name, sail):
    if not sail:
        s = Spr(32, 14, seed=23)
        s.poly([(0, 3), (31, 3), (27, 12), (4, 12)], c("9a5a34"))
        s.hl(1, 3, 30, c("c08050"))
        s.r(3, 4, 26, 3, c("5a3a24"))
        s.hl(4, 8, 24, c("e8e0d0"))
        s.r(14, 4, 4, 2, WOOD_L)
        s.outline()
        reg(name, s, oy=14)
        return
    s = Spr(56, 64, seed=29)
    hull = c("e8e0d0")
    s.poly([(2, 44), (53, 44), (47, 60), (8, 60)], hull)
    s.r(2, 44, 52, 3, c("b04034"))
    s.r(6, 55, 44, 3, c("3a5a8a"))
    s.r(27, 2, 2, 44, WOOD_D)
    s.poly([(30, 6), (30, 40), (50, 40)], c("f0e8d8"))
    s.poly([(26, 10), (26, 40), (10, 40)], c("e0d4c0"))
    s.line(28, 2, 2, 44, c("6a6a6a"))
    s.line(28, 2, 53, 44, c("6a6a6a"))
    s.r(14, 40, 10, 4, WOOD)
    s.outline()
    reg(name, s, oy=62)


def wreck():
    s = Spr(72, 40, seed=31)
    s.poly([(4, 30), (20, 10), (60, 6), (70, 22), (64, 34), (10, 36)], c("5a4030"))
    for xx in range(14, 62, 6):
        s.line(xx, 10, xx - 4, 34, c("3a2a20"))
    s.poly([(20, 14), (56, 10), (62, 22), (24, 28)], c("2a1e18"))
    s.line(40, 0, 36, 20, WOOD_D, 2)
    s.speckle(4, 6, 66, 32, [c("4a6a3a"), c("c8b890")], 0.05)
    s.outline()
    s.shadow(0, 32, 72, 8)
    reg("wreck", s, base=[6, 20, 60, 16], oy=38)


# ---- nature ---------------------------------------------------------------
def pine(name, w, h, dark):
    s = Spr(w, h, seed=zlib.crc32(name.encode()) & 0xfff)
    g1 = c("2f6a4a") if dark else c("3d8050")
    g2 = shade(g1, 0.78)
    g3 = shade(g1, 1.2)
    s.r(w // 2 - 2, h - 9, 4, 7, c("6a4428"))
    layers = 4 if h > 30 else 3
    for i in range(layers):
        top = int(i * (h - 10) / (layers + 0.6))
        bottom = top + int((h - 8) / layers) + 6
        half = int((i + 1.4) * (w / 2) / (layers + 0.4))
        s.poly([(w // 2 - half, bottom), (w // 2, top), (w // 2 + half - 1, bottom)], g1)
        s.poly([(w // 2, top + 2), (w // 2 + half - 1, bottom), (w // 2, bottom)], g2)
        s.line(w // 2 - half + 2, bottom - 1, w // 2 - 1, top + 3, g3)
    s.outline()
    s.shadow(w // 2 - 7, h - 5, 14, 5)
    reg(name, s, base=[w // 2 - 3, h - 6, 6, 4], oy=h - 2)


def oak():
    w, h = 34, 38
    s = Spr(w, h, seed=37)
    s.r(15, 22, 5, 13, c("6a4428"))
    g = c("5a9a48")
    for (x, y, r) in [(4, 8, 14), (14, 3, 16), (18, 10, 14), (8, 14, 16), (2, 12, 10)]:
        s.ell(x, y, r, r, g)
    s.speckle(2, 3, 30, 26, [shade(g, 0.8), shade(g, 1.15)], 0.25)
    s.outline()
    s.shadow(8, h - 6, 20, 6)
    reg("oak", s, base=[14, h - 6, 7, 4], oy=h - 2)


def bush(name, col, berries=None):
    s = Spr(18, 14, seed=zlib.crc32(name.encode()) & 0xfff)
    s.ell(0, 3, 10, 10, col)
    s.ell(7, 1, 11, 12, col)
    s.speckle(0, 1, 18, 12, [shade(col, 0.8), shade(col, 1.15)], 0.3)
    if berries:
        for (x, y) in [(4, 6), (10, 4), (13, 8), (7, 9)]:
            s.p(x, y, berries)
            s.p(x + 1, y, berries)
    s.outline()
    s.shadow(1, 10, 16, 4)
    reg(name, s, base=[2, 8, 14, 5], oy=13)


def rock(name, w, h, snow=False):
    s = Spr(w, h, seed=zlib.crc32(name.encode()) & 0xfff)
    s.ell(0, 2, w, h - 2, STONE_D)
    s.ell(1, 1, w - 3, h - 4, STONE)
    s.ell(3, 2, w // 2, h // 2 - 1, STONE_L)
    if snow:
        s.ell(2, 0, w - 6, h // 3, c("f4f8fa"))
    s.speckle(0, 0, w, h, [STONE_D], 0.06)
    s.outline()
    reg(name, s, base=[1, h // 2, w - 2, h // 2 - 1], oy=h - 1)


def mountain(name, w, h, seed):
    s = Spr(w, h, seed=seed)
    rng = s.rng
    peaks = [(int(w * f), int(h * g)) for f, g in ((0.2, 0.35), (0.5, 0.0), (0.8, 0.25))]
    peaks = [(x + rng.randrange(-6, 6), y) for x, y in peaks]
    pts = [(0, h)] + peaks + [(w - 1, h)]
    s.poly(pts, c("6a7896"))
    for (px, py) in peaks:
        s.poly([(px, py), (px + w // 4, h), (px, h)], c("56627e"))
        snow = h // 3
        s.poly([(px - snow // 2, py + snow), (px, py), (px + snow // 2, py + snow)], c("f2f6fa"))
        for k in range(0, snow // 2, 3):
            s.p(px - snow // 2 + k * 2, py + snow + 1, c("f2f6fa"))
    s.r(0, h - 8, w, 8, c("4a6a5a"))
    reg(name, s, oy=h)


def waterfall():
    frames = []
    for f in range(3):
        s = Spr(28, 64, seed=41)
        s.r(4, 0, 20, 58, c("7ac8e8"))
        for xx in range(4, 24, 3):
            for yy in range((f * 5 + xx * 7) % 12, 58, 12):
                s.r(xx, yy, 1, 5, c("e8f8ff"))
        s.ell(0, 52, 28, 12, c("f0faff"))
        s.ell(4, 54, 20, 8, c("c8eefa"))
        frames.append(s)
    reg("waterfall", None, frames=frames, fps=8, oy=64)


def flowers(name, cols):
    s = Spr(16, 16, seed=zlib.crc32(name.encode()) & 0xfff)
    for _ in range(9):
        x, y = s.rng.randrange(1, 14), s.rng.randrange(2, 14)
        s.p(x, y + 1, GRASS_D)
        s.p(x, y, s.rng.choice(cols))
    reg(name, s, oy=16, flat=True)


# ---- props ----------------------------------------------------------------
def simple_props():
    # fences
    s = Spr(16, 16)
    s.r(1, 3, 3, 12, WOOD); s.r(12, 3, 3, 12, WOOD)
    s.r(0, 5, 16, 2, WOOD_L); s.r(0, 10, 16, 2, WOOD_L)
    s.outline(); reg("fence", s, base=[0, 11, 16, 4], oy=15)
    s = Spr(16, 16)
    s.r(1, 3, 3, 12, WOOD); s.r(12, 6, 3, 9, WOOD_D)
    s.r(0, 5, 7, 2, WOOD_L); s.line(6, 10, 15, 13, WOOD_L, 2)
    s.outline(); reg("fence_broken", s, base=[0, 11, 16, 4], oy=15)
    s = Spr(6, 16)
    s.r(1, 1, 4, 14, WOOD); s.vl(1, 1, 14, WOOD_L)
    s.outline(); reg("fence_post", s, base=[0, 10, 6, 5], oy=15)
    # barrel / crates
    s = Spr(14, 16)
    s.ell(0, 1, 14, 14, WOOD); s.r(1, 4, 12, 9, WOOD); s.ell(1, 0, 12, 6, WOOD_L)
    s.hl(1, 5, 12, c("4a4a4a")); s.hl(1, 11, 12, c("4a4a4a"))
    s.outline(); s.shadow(1, 12, 13, 4); reg("barrel", s, base=[1, 9, 12, 6], oy=15)
    s = Spr(16, 16)
    s.r(1, 2, 14, 13, WOOD); s.r(1, 2, 14, 2, WOOD_L)
    s.line(1, 4, 14, 14, WOOD_D); s.line(14, 4, 1, 14, WOOD_D)
    s.outline(); s.shadow(1, 12, 15, 4); reg("crate", s, base=[1, 8, 14, 7], oy=15)
    s = Spr(18, 24)
    for (x, y) in ((1, 10), (2, 2)):
        s.r(x, y, 14, 12, WOOD); s.r(x, y, 14, 2, WOOD_L); s.line(x, y + 3, x + 13, y + 11, WOOD_D)
    s.outline(); s.shadow(1, 19, 17, 5); reg("crates", s, base=[1, 16, 16, 7], oy=23)
    # lamp post
    s = Spr(10, 32)
    s.r(4, 8, 2, 22, c("2a2a30")); s.r(2, 29, 6, 2, c("2a2a30"))
    s.r(1, 2, 8, 7, c("2a2a30")); s.r(2, 3, 6, 5, c("f8e090")); s.p(4, 4, WHITE)
    s.outline(); reg("lamp", s, base=[3, 27, 4, 4], oy=31)
    # monument in the square
    s = Spr(20, 34)
    s.r(2, 26, 16, 6, STONE_D); s.r(4, 22, 12, 5, STONE)
    s.poly([(6, 22), (14, 22), (12, 2), (8, 2)], STONE_L)
    s.vl(11, 4, 18, STONE)
    s.r(7, 12, 6, 4, c("b08a3a"))
    s.outline(); s.shadow(1, 29, 18, 5); reg("monument", s, base=[2, 25, 16, 7], oy=32)
    # signpost
    s = Spr(18, 22)
    s.r(8, 6, 2, 15, WOOD_D); s.poly([(1, 4), (14, 4), (17, 7), (14, 10), (1, 10)], WOOD_L)
    s.hl(3, 7, 9, WOOD_D)
    s.outline(); reg("sign", s, base=[7, 17, 4, 4], oy=21)
    # woodpile & chopping block
    s = Spr(28, 18)
    for row, y in enumerate((10, 5, 0)):
        for x in range(row * 3, 26 - row * 3, 6):
            s.ell(x, y + 2, 7, 7, c("a8743e")); s.ell(x + 2, y + 4, 3, 3, c("e0b878"))
    s.outline(); s.shadow(0, 13, 28, 5); reg("woodpile", s, base=[0, 10, 28, 7], oy=17)
    s = Spr(16, 16)
    s.ell(1, 8, 14, 7, WOOD_D); s.r(1, 6, 14, 6, WOOD); s.ell(1, 3, 14, 7, c("d0a068"))
    s.ell(4, 5, 8, 3, c("b08048"))
    s.line(9, 0, 6, 6, WOOD_L, 2); s.r(9, 0, 4, 3, STONE)
    s.outline(); reg("chopping_block", s, base=[1, 9, 14, 6], oy=15)
    # fish drying rack (Icelandic hjallur)
    s = Spr(34, 28)
    s.line(2, 26, 8, 2, WOOD_D, 2); s.line(14, 26, 8, 2, WOOD_D, 2)
    s.line(20, 26, 26, 2, WOOD_D, 2); s.line(32, 26, 26, 2, WOOD_D, 2)
    s.r(6, 3, 24, 2, WOOD)
    for x in range(8, 28, 4):
        s.r(x, 5, 2, 9, c("c8b898")); s.p(x, 13, c("a89878"))
    s.outline(); reg("fish_rack", s, base=[2, 22, 30, 5], oy=27)
    # well
    s = Spr(22, 28)
    s.ell(1, 16, 20, 11, STONE_D); s.r(1, 14, 20, 8, STONE); s.ell(1, 10, 20, 9, STONE_L)
    s.ell(4, 12, 14, 5, c("1e2a3a"))
    s.r(2, 0, 2, 16, WOOD_D); s.r(18, 0, 2, 16, WOOD_D); s.poly([(0, 3), (11, -3), (22, 3), (22, 5), (0, 5)], c("8a3a30"))
    s.outline(); s.shadow(0, 23, 22, 5); reg("well", s, base=[1, 17, 20, 9], oy=27)
    # haystack
    s = Spr(26, 20)
    s.ell(0, 4, 26, 16, c("d8b850")); s.ell(4, 0, 18, 12, c("e8cc68"))
    s.speckle(0, 0, 26, 20, [c("c0a040"), c("f0dc80")], 0.2)
    s.outline(); s.shadow(1, 15, 24, 5); reg("haystack", s, base=[1, 12, 24, 7], oy=19)
    # bench
    s = Spr(22, 12)
    s.r(1, 2, 20, 3, WOOD_L); s.r(1, 6, 20, 2, WOOD); s.r(2, 8, 2, 3, WOOD_D); s.r(18, 8, 2, 3, WOOD_D)
    s.outline(); reg("bench", s, base=[1, 6, 20, 5], oy=11)
    # bench with Elias' discarded coat
    s2 = Spr(22, 12); s2.paste(s, 0, 0)
    s2.r(6, 1, 9, 6, c("1e1e28")); s2.r(7, 1, 2, 2, c("3a3a4a")); s2.p(12, 4, c("c8a040"))
    reg("bench_coat", s2, base=[1, 6, 20, 5], oy=11)
    # anvil
    s = Spr(16, 12)
    s.r(2, 2, 12, 3, c("4a4a54")); s.r(0, 2, 3, 2, c("4a4a54")); s.r(5, 5, 6, 4, c("3a3a44")); s.r(3, 9, 10, 2, WOOD_D)
    s.hl(2, 2, 12, c("8a8a96"))
    s.outline(); reg("anvil", s, base=[2, 6, 12, 5], oy=11)
    # grave crosses
    s = Spr(10, 14)
    s.r(4, 1, 2, 12, STONE_L); s.r(1, 4, 8, 2, STONE_L); s.r(1, 12, 8, 2, c("5a8a3a"))
    s.outline(); reg("grave", s, base=[2, 10, 6, 3], oy=13)
    s = Spr(12, 14)
    s.r(1, 3, 10, 10, STONE); s.ell(1, 0, 10, 7, STONE); s.hl(3, 6, 6, STONE_D); s.hl(3, 8, 6, STONE_D)
    s.outline(); reg("gravestone", s, base=[1, 9, 10, 4], oy=13)
    # herb bush (collectable)
    s = Spr(14, 12)
    s.ell(0, 3, 14, 9, c("4e8a4e")); s.speckle(0, 3, 14, 9, [c("3e7a3e"), c("6aa86a")], 0.3)
    for (x, y) in ((3, 4), (7, 3), (10, 6), (5, 7)):
        s.p(x, y, c("b07ad8")); s.p(x, y - 1, c("d8a8f8"))
    s.outline(); reg("herb", s, oy=11)
    # sheep (2 frames)
    fr = []
    for f in range(2):
        s = Spr(18, 14)
        s.r(4, 10, 2, 3 - f, c("2a2a2a")); s.r(12, 10, 2, 2 + f, c("2a2a2a"))
        s.ell(2, 2, 14, 10, c("f0ece4")); s.speckle(2, 2, 14, 10, [c("d8d4cc")], 0.25)
        s.r(13, 3 + f, 5, 5, c("3a3a3a")); s.p(16, 4 + f, WHITE)
        s.outline(); s.shadow(2, 10, 14, 4)
        fr.append(s)
    reg("sheep", None, frames=fr, fps=2, oy=13)
    # horse in the paddock
    fr = []
    for f in range(2):
        s = Spr(28, 22)
        hb = c("8a5a32")
        s.r(4, 7, 16, 8, hb); s.r(18, 1 + f, 5, 9, hb); s.r(22, 2 + f, 4, 4, hb); s.r(17, 1 + f, 3, 7, c("e8e0c8"))
        for lx in (5, 8, 15, 18):
            s.r(lx, 15, 2, 6, shade(hb, 0.8))
        s.r(2, 7, 3, 7, c("e8e0c8"))
        s.outline(); s.shadow(3, 18, 22, 4)
        fr.append(s)
    reg("horse", None, frames=fr, fps=1, oy=21)
    # coin sparkle (collectable)
    fr = []
    for f in range(4):
        s = Spr(10, 10)
        s.ell(2, 2, 6, 6, c("e8b830")); s.ell(3, 3, 3, 3, c("f8e080"))
        if f in (1, 2):
            s.p(1 + f * 2, 1, WHITE); s.p(8 - f, 7, WHITE)
        s.outline()
        fr.append(s)
    reg("coin_pickup", None, frames=fr, fps=6, oy=10)
    # generic glint for hidden items
    fr = []
    for f in range(4):
        s = Spr(12, 12)
        r = [1, 3, 5, 3][f]
        s.r(6 - r, 5, r * 2, 2, c("ffffff", 220)); s.r(5, 6 - r, 2, r * 2, c("ffffff", 220))
        s.p(5, 5, c("fff6c0"))
        fr.append(s)
    reg("glint", None, frames=fr, fps=6, oy=12)
    # shell
    s = Spr(10, 8)
    s.poly([(1, 7), (5, 0), (9, 7)], c("f0c8b8"))
    for x in (3, 5, 7):
        s.line(5, 1, x, 7, c("d8a090"))
    s.outline(); reg("shell", s, oy=8)
    # footprints decal
    s = Spr(32, 16)
    for i, (x, y) in enumerate(((2, 10), (8, 4), (15, 9), (21, 3), (27, 8))):
        s.ell(x, y, 3, 5, c("3a2a1a", 150))
    reg("footprints", s, oy=16, flat=True)
    # loose floorboard decal
    s = Spr(16, 16)
    s.r(2, 6, 12, 4, c("5a3a22")); s.hl(2, 6, 12, c("2a1a10")); s.p(3, 7, c("c0a080")); s.p(12, 8, c("c0a080"))
    reg("floorboard", s, oy=16, flat=True)
    # iron chest
    s = Spr(18, 14)
    s.r(1, 4, 16, 9, c("5a5a64")); s.r(1, 2, 16, 4, c("6a6a74")); s.hl(1, 2, 16, c("8a8a96"))
    s.vl(4, 2, 11, c("3a3a44")); s.vl(13, 2, 11, c("3a3a44")); s.r(8, 6, 2, 3, c("c8a040"))
    s.outline(); reg("iron_chest", s, base=[1, 8, 16, 5], oy=13)
    # dark carriage-less marker: smoke puff for chimneys (3 frames)
    fr = []
    for f in range(4):
        s = Spr(12, 24)
        for k in range(3):
            y = 20 - k * 7 - f * 2
            if y > 0:
                s.ell(3 + (k + f) % 2 * 2, y, 6 + k, 6 + k, c("e8ecf0", 170 - k * 40))
        fr.append(s)
    reg("smoke", None, frames=fr, fps=3, oy=24)
    # driftwood / debris
    s = Spr(24, 10)
    s.line(1, 7, 22, 3, WOOD_D, 3); s.line(4, 3, 10, 8, c("8a7a6a"), 2)
    s.outline(); reg("debris", s, base=[1, 3, 22, 6], oy=9)
    # dock post
    s = Spr(6, 14)
    s.r(1, 1, 4, 12, WOOD_D); s.hl(1, 1, 4, WOOD_L)
    s.outline(); reg("post", s, base=[0, 8, 6, 5], oy=13)
    # gate across the eastern bridge (removed later in the story)
    s = Spr(16, 22)
    s.r(1, 2, 3, 19, WOOD_D); s.r(12, 2, 3, 19, WOOD_D)
    s.r(0, 6, 16, 3, WOOD); s.r(0, 13, 16, 3, WOOD); s.line(1, 15, 14, 7, WOOD_L, 2)
    s.r(6, 9, 4, 4, c("b04034"))
    s.outline(); reg("gate", s, base=[0, 14, 16, 7], oy=21)
    # landmark painting spot (easel-less marker: a little frame on a stick)
    s = Spr(12, 18)
    s.r(5, 8, 2, 9, WOOD_D); s.r(0, 0, 12, 9, c("c8a040")); s.r(1, 1, 10, 7, c("f4ecd8"))
    s.p(3, 4, c("4a8ac0")); s.p(6, 3, c("6aa84f")); s.p(8, 5, c("e06040"))
    s.outline(); reg("easel_small", s, base=[4, 14, 4, 3], oy=17)


def char_shadow():
    s = Spr(14, 5)
    s.ell(0, 0, 14, 5, (20, 30, 40, 80))
    reg("char_shadow", s, oy=5, flat=True)


def interior_props():
    def r(name, s, base=None, oy=None, flat=False):
        reg(name, s, base=base, oy=oy, flat=flat)

    # beds
    s = Spr(18, 30)
    s.r(1, 0, 16, 6, WOOD_D); s.r(1, 5, 16, 24, WOOD); s.r(2, 6, 14, 6, WHITE); s.r(2, 12, 14, 16, c("4a6aa0"))
    s.hl(2, 12, 14, c("6a8ac0")); s.speckle(2, 13, 14, 15, [c("3a5a90")], 0.1)
    s.outline(); r("bed", s, base=[1, 4, 16, 25], oy=29)
    s = Spr(18, 30)
    s.r(1, 0, 16, 6, WOOD_D); s.r(1, 5, 16, 24, WOOD); s.r(2, 6, 14, 6, c("d8d0c0")); s.r(2, 12, 14, 16, c("8a7060"))
    for k in range(3):
        s.r(3 + k * 4, 14 + k * 4, 5, 4, [c("a06050"), c("6a8a5a"), c("c0a060")][k])
    s.outline(); r("bed_patched", s, base=[1, 4, 16, 25], oy=29)
    s = Spr(30, 30)
    s.r(1, 0, 28, 6, c("5a2a2a")); s.r(1, 5, 28, 24, c("6a3a2a")); s.r(2, 6, 12, 6, WHITE); s.r(16, 6, 12, 6, WHITE)
    s.r(2, 12, 26, 16, c("8a2a3a")); s.hl(2, 12, 26, c("aa4a5a"))
    s.outline(); r("bed_fancy", s, base=[1, 4, 28, 25], oy=29)
    # tables & chairs
    s = Spr(28, 20)
    s.r(1, 2, 26, 10, WOOD_L); s.hl(1, 2, 26, c("d0a070")); s.r(2, 12, 3, 7, WOOD_D); s.r(23, 12, 3, 7, WOOD_D)
    s.outline(); r("table", s, base=[1, 6, 26, 12], oy=19)
    s = Spr(28, 20)
    s.paste(Spr(1, 1), 0, 0)
    s.r(1, 2, 26, 10, WOOD_L); s.hl(1, 2, 26, c("d0a070")); s.r(2, 12, 3, 7, WOOD_D); s.r(23, 12, 3, 7, WOOD_D)
    s.r(5, 3, 6, 4, WHITE); s.r(6, 4, 4, 2, c("c08a50")); s.r(16, 3, 3, 5, c("8ab0c8")); s.r(21, 4, 4, 3, c("e8d8a0"))
    s.outline(); r("table_meal", s, base=[1, 6, 26, 12], oy=19)
    s = Spr(10, 14)
    s.r(1, 0, 8, 6, WOOD); s.r(1, 6, 8, 3, WOOD_L); s.r(1, 9, 2, 4, WOOD_D); s.r(7, 9, 2, 4, WOOD_D)
    s.outline(); r("chair", s, base=[1, 7, 8, 6], oy=13)
    # fireplace (animated)
    fr = []
    for f in range(3):
        s = Spr(28, 30)
        s.r(0, 0, 28, 30, STONE); s.speckle(0, 0, 28, 30, [STONE_D, STONE_L], 0.25)
        s.r(0, 0, 28, 4, c("6a4a3a"))
        s.r(5, 12, 18, 16, c("1a1210"))
        s.r(7, 24, 14, 3, c("5a3a22"))
        flame = [(8, 20, 5, 5), (12, 17, 5, 8), (16, 19, 4, 6)]
        for i, (x, y, w, h) in enumerate(flame):
            dy = (f + i) % 3 - 1
            s.r(x, y + dy, w, h - dy, c("f08a2a"))
            s.r(x + 1, y + 2 + dy, w - 2, h - 3 - dy, c("f8d050"))
        s.outline()
        fr.append(s)
    reg("fireplace", None, frames=fr, fps=6, base=[0, 18, 28, 12], oy=29)
    # bookshelf, desk, cabinet
    s = Spr(28, 32)
    s.r(0, 0, 28, 32, WOOD_D); s.r(2, 2, 24, 28, c("3a2618"))
    rng = s.rng
    for shelf in range(3):
        y = 3 + shelf * 9
        x = 3
        while x < 25:
            bw = rng.randrange(2, 4)
            s.r(x, y + rng.randrange(0, 2), bw, 7, rng.choice([c("a03a2e"), c("3a5a8a"), c("4a7a3a"), c("c0a050"), c("6a4a7a")]))
            x += bw
        s.hl(2, y + 7, 24, WOOD)
    s.outline(); r("bookshelf", s, base=[0, 20, 28, 12], oy=31)
    s = Spr(30, 20)
    s.r(1, 2, 28, 10, c("5a3020")); s.hl(1, 2, 28, c("7a4a30")); s.r(2, 12, 4, 7, c("4a2418")); s.r(24, 12, 4, 7, c("4a2418"))
    s.r(5, 3, 8, 6, c("f0e8d0")); s.r(15, 4, 6, 5, c("e8dcc0")); s.r(23, 3, 2, 5, c("2a2a2a"))
    s.outline(); r("desk", s, base=[1, 6, 28, 12], oy=19)
    s = Spr(20, 32)
    s.r(1, 0, 18, 31, c("4a2a1a")); s.r(3, 3, 6, 25, c("5e3824")); s.r(11, 3, 6, 25, c("5e3824"))
    s.r(9, 13, 2, 4, c("c8a040")); s.r(8, 15, 4, 3, c("8a8a96"))
    s.outline(); r("cabinet", s, base=[1, 20, 18, 11], oy=31)
    s = Spr(20, 32)
    s.r(1, 0, 18, 31, c("4a2a1a")); s.r(3, 3, 14, 25, c("1a1008"))
    s.r(4, 6, 10, 3, c("e8dcc0")); s.r(5, 12, 9, 2, c("e0d0b0")); s.r(4, 18, 6, 4, c("c8b090"))
    s.outline(); r("cabinet_open", s, base=[1, 20, 18, 11], oy=31)
    s = Spr(22, 32)
    s.r(1, 0, 20, 31, WOOD); s.vl(11, 2, 28, WOOD_D); s.p(9, 15, c("c8a040")); s.p(13, 15, c("c8a040"))
    s.outline(); r("wardrobe", s, base=[1, 20, 20, 11], oy=31)
    # sewing table, easel, bucket, rug, counter, wall decor
    s = Spr(24, 20)
    s.r(1, 4, 22, 8, WOOD_L); s.r(2, 12, 3, 7, WOOD_D); s.r(19, 12, 3, 7, WOOD_D)
    s.r(4, 0, 8, 6, c("2a2a2a")); s.r(6, 1, 3, 2, c("c8a040")); s.r(14, 5, 7, 4, c("b04a6a")); s.r(15, 6, 2, 2, c("f0e0f0"))
    s.outline(); r("sewing_table", s, base=[1, 8, 22, 10], oy=19)
    s = Spr(16, 26)
    s.line(3, 25, 8, 1, WOOD_D, 2); s.line(13, 25, 8, 1, WOOD_D, 2); s.r(1, 6, 14, 11, c("f4ecd8"))
    s.r(2, 7, 12, 4, c("8ac0e8")); s.r(2, 11, 12, 5, c("6aa84f")); s.r(5, 9, 3, 3, c("e0b048"))
    s.outline(); r("easel", s, base=[2, 20, 12, 5], oy=25)
    s = Spr(10, 10)
    s.r(1, 2, 8, 7, c("7a7a84")); s.ell(1, 0, 8, 4, c("9a9aa4")); s.ell(2, 1, 6, 2, c("5a8ab0"))
    s.outline(); r("bucket", s, base=[1, 5, 8, 4], oy=9)
    s = Spr(40, 24)
    s.r(0, 0, 40, 24, c("8a3a3a")); s.r(2, 2, 36, 20, c("a84a40")); s.r(5, 5, 30, 14, c("c8a050")); s.r(8, 8, 24, 8, c("8a3a3a"))
    r("rug", s, oy=24, flat=True)
    s = Spr(56, 22)
    s.r(0, 2, 56, 18, WOOD_D); s.r(0, 0, 56, 5, WOOD_L); s.hl(0, 0, 56, c("d0a070"))
    for x in range(4, 52, 8):
        s.vl(x, 6, 13, shade(WOOD_D, 0.8))
    s.r(8, -1, 4, 3, c("f0e0b0")); s.r(40, -1, 6, 3, c("c08a50"))
    s.outline(); r("counter", s, base=[0, 6, 56, 15], oy=21)
    s = Spr(18, 14)
    s.r(0, 0, 18, 14, c("c8a040")); s.r(1, 1, 16, 12, c("e8dcb0"))
    s.line(3, 10, 8, 4, c("6a5a3a")); s.line(8, 4, 14, 8, c("6a5a3a")); s.p(12, 3, c("b04034"))
    r("wall_map", s, oy=14)
    s = Spr(16, 14)
    s.r(0, 0, 16, 14, c("8a6a3a")); s.r(1, 1, 14, 12, c("8ac0e8")); s.r(1, 8, 14, 5, c("4a8a4a")); s.poly([(3, 9), (7, 3), (11, 9)], c("eef2f6"))
    r("wall_painting", s, oy=14)
    s = Spr(16, 16)
    s.r(0, 0, 16, 16, WHITE); s.r(1, 1, 14, 14, GLASS); s.r(1, 1, 6, 6, mix(GLASS, GLASS_L, 0.4)); s.vl(7, 1, 14, WHITE); s.hl(1, 7, 14, WHITE)
    s.r(-1, 15, 18, 1, WOOD_D)
    r("wall_window", s, oy=16)
    # barn clutter
    s = Spr(26, 18)
    s.ell(0, 4, 26, 14, c("c8a850")); s.speckle(0, 4, 26, 14, [c("a88a3a"), c("e0c868")], 0.3)
    s.outline(); r("hay_pile", s, base=[1, 10, 24, 7], oy=17)
    s = Spr(12, 16)
    s.r(1, 6, 10, 3, WOOD); s.r(1, 0, 2, 15, WOOD_D); s.r(9, 6, 2, 9, WOOD_D); s.r(2, 9, 2, 6, WOOD_D)
    s.outline(); r("old_chair", s, base=[1, 8, 10, 7], oy=15)
    s = Spr(14, 12)
    s.r(1, 3, 12, 8, c("6a4a2a")); s.r(1, 1, 12, 3, c("8a6a3a")); s.r(6, 4, 2, 3, c("c8a040"))
    s.outline(); r("wood_box", s, base=[1, 5, 12, 6], oy=11)
    s = Spr(12, 14)
    s.r(5, 0, 2, 3, c("2a2a2a")); s.r(2, 3, 8, 9, c("2a2a2a")); s.r(3, 4, 6, 7, c("f8d070")); s.r(5, 6, 2, 3, WHITE)
    s.outline(); r("lantern_prop", s, oy=13)
    s = Spr(20, 10)
    s.r(1, 1, 18, 8, c("a87a50")); s.r(3, 2, 14, 6, c("e8d8b8"))
    s.outline(); r("papers", s, oy=10, flat=True)


def icons():
    I = {}

    def ic(name):
        s = Spr(16, 16, seed=zlib.crc32(name.encode()) & 0xfff)
        I[name] = s
        return s

    s = ic("hammer"); s.line(4, 14, 10, 6, WOOD, 2); s.r(7, 2, 8, 4, c("7a7a84")); s.hl(7, 2, 8, c("aaaab4"))
    s = ic("axe"); s.line(4, 14, 10, 4, WOOD, 2); s.poly([(9, 2), (14, 1), (14, 8), (10, 7)], c("8a8a96")); s.vl(14, 1, 7, c("d0d0da"))
    s = ic("rod"); s.line(2, 14, 13, 2, WOOD_L, 1); s.line(13, 2, 13, 11, c("e0e0e0")); s.r(12, 11, 2, 2, c("e04040")); s.r(3, 11, 3, 3, c("4a4a4a"))
    s = ic("fish"); s.ell(2, 5, 10, 6, c("7ab0c8")); s.poly([(11, 8), (15, 4), (15, 12)], c("5a90a8")); s.p(4, 7, c("1a1a1a")); s.hl(4, 9, 6, c("c8e0ea"))
    s = ic("firewood")
    for (x, y) in ((1, 8), (7, 8), (4, 3)):
        s.ell(x, y, 8, 7, c("a8743e")); s.ell(x + 2, y + 2, 4, 3, c("e0b878"))
    s = ic("iron_key"); s.ell(1, 2, 7, 7, c("5a5a64")); s.ell(3, 4, 3, 3, (0, 0, 0, 0)); s.r(7, 5, 8, 2, c("5a5a64")); s.r(12, 7, 2, 3, c("5a5a64")); s.r(9, 7, 2, 2, c("5a5a64"))
    s = ic("letter"); s.r(1, 3, 14, 10, c("f0e8d0")); s.line(1, 3, 8, 8, c("c0b090")); s.line(14, 3, 8, 8, c("c0b090")); s.r(7, 7, 3, 3, c("b03030"))
    s = ic("torn_letter"); s.poly([(1, 2), (14, 2), (12, 7), (14, 13), (1, 13)], c("e8dcc0")); s.hl(3, 5, 7, c("8a7a5a")); s.hl(3, 8, 6, c("8a7a5a")); s.hl(3, 11, 7, c("8a7a5a"))
    s = ic("deed"); s.r(2, 1, 12, 14, c("efe2c0")); s.r(2, 1, 12, 2, c("c8b080")); s.r(2, 13, 12, 2, c("c8b080"))
    for y in (4, 6, 8):
        s.hl(4, y, 8, c("6a5a3a"))
    s.ell(8, 9, 5, 5, c("b03030"))
    s = ic("compass"); s.ell(1, 1, 14, 14, c("c8a040")); s.ell(3, 3, 10, 10, c("f0ecd8")); s.line(8, 4, 8, 8, c("c03030")); s.line(8, 8, 8, 12, c("3a3a3a")); s.p(8, 8, c("2a2a2a"))
    s = ic("fabric"); s.r(2, 4, 12, 9, c("5a7ac0")); s.r(2, 4, 12, 3, c("7a9ae0")); s.r(10, 6, 4, 7, c("c05a7a"))
    s = ic("herbs"); s.line(8, 15, 8, 6, c("4a7a3a")); s.ell(3, 3, 6, 5, c("6aa84f")); s.ell(8, 1, 6, 5, c("5a9a48")); s.p(6, 4, c("b07ad8")); s.p(10, 3, c("b07ad8"))
    s = ic("coin"); s.ell(2, 2, 12, 12, c("e8b830")); s.ell(4, 4, 8, 8, c("f8d860")); s.vl(8, 5, 6, c("c89820"))
    s = ic("bread"); s.ell(1, 5, 14, 9, c("c88a40")); s.ell(2, 5, 12, 6, c("e0a860")); s.line(5, 6, 6, 9, c("a86a30")); s.line(9, 6, 10, 9, c("a86a30"))
    s = ic("lantern"); s.r(7, 0, 2, 3, c("2a2a2a")); s.r(3, 3, 10, 11, c("2a2a2a")); s.r(4, 4, 8, 9, c("f8d070")); s.r(7, 6, 2, 4, WHITE)
    s = ic("boots"); s.r(2, 2, 5, 10, c("5a3a22")); s.r(2, 10, 7, 4, c("5a3a22")); s.r(8, 3, 5, 9, c("6a4a2a")); s.r(8, 10, 7, 4, c("6a4a2a"))
    s = ic("paints"); s.r(1, 4, 14, 9, WOOD_L); s.ell(3, 6, 3, 3, c("e04040")); s.ell(7, 6, 3, 3, c("40a0e0")); s.ell(11, 6, 3, 3, c("f0d040")); s.line(3, 12, 13, 10, WOOD_D)
    s = ic("painting"); s.r(1, 2, 14, 12, c("c8a040")); s.r(2, 3, 12, 10, c("8ac0e8")); s.r(2, 9, 12, 4, c("4a8a4a")); s.poly([(4, 9), (8, 4), (12, 9)], c("eef2f6"))
    s = ic("journal_page"); s.r(3, 1, 10, 14, c("e0d4b0")); s.vl(3, 1, 14, c("b0a080"))
    for y in (4, 6, 8, 10, 12):
        s.hl(5, y, 6, c("5a4a3a"))
    s = ic("shell"); s.poly([(2, 13), (8, 2), (14, 13)], c("f0c8b8")); s.line(8, 3, 5, 13, c("d8a090")); s.line(8, 3, 11, 13, c("d8a090")); s.line(8, 3, 8, 13, c("d8a090"))
    s = ic("wooden_box"); s.r(1, 5, 14, 9, c("6a4a2a")); s.r(1, 3, 14, 3, c("8a6a3a")); s.r(7, 6, 2, 3, c("c8a040"))
    s = ic("silver_watch"); s.ell(2, 3, 12, 12, c("c0c4cc")); s.ell(4, 5, 8, 8, c("f4f4f0")); s.r(7, 0, 2, 3, c("c0c4cc")); s.line(8, 9, 8, 6, c("2a2a2a")); s.line(8, 9, 10, 9, c("2a2a2a"))
    s = ic("photograph"); s.r(1, 2, 14, 12, c("f0ecd8")); s.r(2, 3, 12, 9, c("8a7a6a")); s.ell(4, 5, 3, 3, c("d8c8a8")); s.ell(9, 5, 3, 3, c("d8c8a8")); s.r(4, 8, 3, 4, c("4a3a2a")); s.r(9, 8, 3, 4, c("4a3a2a"))
    s = ic("crate"); s.r(1, 2, 14, 12, WOOD); s.line(1, 2, 14, 13, WOOD_D); s.line(14, 2, 1, 13, WOOD_D); s.r(1, 2, 14, 2, WOOD_L)
    s = ic("lockpick"); s.line(2, 13, 11, 4, c("8a8a96"), 2); s.r(10, 2, 4, 2, c("8a8a96")); s.r(12, 3, 2, 3, c("8a8a96")); s.r(1, 11, 4, 4, WOOD)
    s = ic("planks"); s.r(1, 3, 14, 3, WOOD_L); s.r(1, 7, 14, 3, WOOD); s.r(1, 11, 14, 3, WOOD_D)
    s = ic("church_letter"); s.r(1, 3, 14, 10, c("f0e8d0")); s.r(6, 5, 4, 6, c("c8a040")); s.r(5, 6, 6, 2, c("c8a040"))
    s = ic("iron_tools"); s.line(3, 13, 12, 3, c("5a5a64"), 2); s.line(3, 3, 12, 13, c("5a5a64"), 2); s.r(1, 1, 4, 4, c("7a7a84"))
    s = ic("cargo_mark"); s.r(1, 3, 14, 10, WOOD); s.line(4, 5, 12, 11, c("f0e0b0")); s.line(12, 5, 4, 11, c("f0e0b0")); s.ell(6, 6, 4, 4, c("f0e0b0"))
    s = ic("outfit"); s.poly([(4, 2), (12, 2), (15, 6), (12, 7), (12, 14), (4, 14), (4, 7), (1, 6)], c("3a5a8a")); s.vl(8, 3, 11, c("c8a040"))
    s = ic("special_rod"); s.line(2, 14, 13, 2, c("c8a040"), 1); s.line(13, 2, 13, 11, c("e0e0e0")); s.r(12, 11, 2, 2, c("40c0e0")); s.r(3, 11, 3, 3, c("8a3a3a"))
    s = ic("detector"); s.line(3, 13, 11, 5, WOOD, 2); s.ell(9, 1, 6, 6, c("c8a040")); s.ell(11, 3, 2, 2, c("5a8ab0"))
    out = []
    names = list(I.keys())
    for n in names:
        I[n].outline()
        out.append(I[n])
    sh = sheet(out, 8)
    sh.save(f"{OUT}/ui/icons.png")
    return {n: i for i, n in enumerate(names)}


def build(out_dir):
    global OUT
    OUT = out_dir
    for name, col, flowers_ in (("house_red", "red", [c("f0f0f0"), c("f0c040")]),
                                ("house_blue", "blue", [c("e05050"), c("f0f0f0")]),
                                ("house_yellow", "yellow", [c("e05080"), c("8040c0")]),
                                ("house_green", "green", [c("f0d040"), c("f0f0f0")]),
                                ("house_white", "white", [c("e05050"), c("4080e0")])):
        house(name, 64, 62, WALLS[col], flowers=flowers_)
    house("house_red_small", 52, 54, WALLS["red"], windows=1, roof=(c("4a5a4a"), c("3a4a3a"), c("5a6a5a")))
    house("house_gideon", 50, 54, c("7a6a5a"), windows=2, shabby=True, chimney=True, door_col=c("5a4a3a"))
    house("house_gideon_fixed", 50, 54, c("7a8aa0"), windows=2, chimney=True, flowers=[c("e05050"), c("f0d040")])
    house("farmhouse", 64, 60, c("8a8a80"), windows=2, shabby=True, broken=True)
    house("turf_house", 56, 52, c("6a4a32"), windows=1, turf=True)
    house("turf_house_b", 60, 54, c("8a3a30"), windows=2, turf=True)
    church(); manor(); inn(); warehouse(); smithy(); barn()
    market_stall("stall_red", c("c0403a")); market_stall("stall_blue", c("3a6ac0")); market_stall("stall_green", c("3a9a5a"))
    cart(); carriage(); boat("rowboat", False); boat("sailboat", True); wreck()
    pine("pine", 26, 44, False); pine("pine_dark", 26, 44, True); pine("pine_small", 18, 30, False)
    oak()
    bush("bush", c("5a9a48")); bush("bush_berry", c("4e8a40"), c("d04050"))
    rock("rock", 16, 13); rock("rock_big", 28, 20); rock("rock_snow", 26, 18, snow=True)
    mountain("mountain_a", 200, 84, 1); mountain("mountain_b", 168, 72, 2)
    waterfall()
    flowers("flowers_a", [c("f0e060"), c("ffffff")]); flowers("flowers_b", [c("e06080"), c("c080f0")])
    simple_props(); interior_props(); char_shadow()
    icon_index = icons()
    return META, icon_index
