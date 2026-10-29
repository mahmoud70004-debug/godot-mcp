"""Larger, more detailed buildings and harbour props for the redesigned Hrafnvik
(matches the world reference: front gables, two-tone houses, slate roofs, trims, boats).
Registered through gen_sprites.reg so the game sees them in data/sprites.json.
"""
import zlib
import numpy as np
from PIL import Image, ImageDraw
from pixel import Spr, c, shade, mix

reg = None  # injected by gen_sprites.build

WHITE = c("efe9da")
TRIM = c("f4efe2")
GLASS = c("2f4a68")
GLASS_L = c("9cc8e6")
STONE = c("9a9aa2"); STONE_D = c("6e6e78"); STONE_L = c("c2c2c8")
WOOD = c("8e623e"); WOOD_D = c("5e3e28"); WOOD_L = c("b0804e")
SLATE = (c("3f4860"), c("2c3346"), c("59637e"))
WALLS = {"red": c("a83a30"), "blue": c("3f6fae"), "yellow": c("d9a63c"), "green": c("4f8a54"),
         "white": c("e4ddc8"), "ochre": c("b8803a"), "grey": c("8a8478")}


def seed(name):
    return zlib.crc32(name.encode()) & 0xffff


def sel_outline(s, factor=0.38):
    a = np.array(s.im).astype(np.int16)
    m = a[:, :, 3] > 200
    h, w = m.shape
    out = a.copy()
    shifted = []
    for dx, dy in ((0, 1), (0, -1), (1, 0), (-1, 0)):
        mm = np.zeros_like(m)
        cc = np.zeros_like(a)
        ys = slice(max(0, dy), h + min(0, dy)); yd = slice(max(0, -dy), h + min(0, -dy))
        xs = slice(max(0, dx), w + min(0, dx)); xd = slice(max(0, -dx), w + min(0, -dx))
        mm[yd, xd] = m[ys, xs]
        cc[yd, xd] = a[ys, xs]
        shifted.append((mm, cc))
    edge = np.zeros_like(m)
    for mm, cc in shifted:
        sel = mm & ~m & ~edge
        col = (cc[..., :3] * factor + np.array([16, 10, 12])).clip(0, 255)
        out[sel, :3] = col[sel]
        out[sel, 3] = 255
        edge |= sel
    s.im = Image.fromarray(out.astype(np.uint8))
    s.d = ImageDraw.Draw(s.im)


def shadow_under(s, x, y, w, h, alpha=80):
    s.shadow(x, y, w, h, alpha)


def shingles(s, pts, base, dark, light, rows=3):
    """Fill a polygon with slate shingles."""
    s.poly(pts, base)
    ys = [p[1] for p in pts]
    xs = [p[0] for p in pts]
    mask = Image.new("L", (s.w, s.h), 0)
    ImageDraw.Draw(mask).polygon(pts, fill=255)
    mk = mask.load()
    for y in range(min(ys), max(ys) + 1):
        for x in range(min(xs), max(xs) + 1):
            if 0 <= x < s.w and 0 <= y < s.h and mk[x, y]:
                if (y - min(ys)) % rows == rows - 1:
                    s.p(x, y, dark)
                elif (x + ((y - min(ys)) // rows) * 3) % 6 == 0:
                    s.p(x, y, dark)
                elif (x * 7 + y * 13) % 29 == 0:
                    s.p(x, y, light)


def planks(s, x, y, w, h, col, vertical=True, weathered=False):
    s.r(x, y, w, h, col)
    dark = shade(col, 0.8)
    light = shade(col, 1.1)
    if vertical:
        for xx in range(x, x + w, 4):
            s.vl(xx, y, h, dark)
            s.vl(xx + 1, y, h, light)
    else:
        for yy in range(y + 2, y + h, 3):
            s.hl(x, yy, w, dark)
    for k in range(3):
        s.hl(x, y + k, w, shade(col, 0.62 + k * 0.12))   # eave shadow
    if weathered:
        s.speckle(x, y, w, h, [shade(col, 0.7), mix(col, c("8a8a80"), 0.6)], 0.09)


def window(s, x, y, w=10, h=12, shutters=None, box=None, broken=False, boarded=False, lit=False):
    s.r(x - 2, y - 2, w + 4, h + 4, TRIM)
    s.r(x - 1, y + h + 1, w + 2, 2, shade(TRIM, 0.8))
    glass = c("e8c46a") if lit else (c("1c2430") if broken else GLASS)
    s.r(x, y, w, h, glass)
    if not broken and not lit:
        s.r(x, y, w // 2, h // 2, mix(GLASS, GLASS_L, 0.35))
        s.p(x + 1, y + 1, GLASS_L)
        s.p(x + 2, y + 1, GLASS_L)
    s.vl(x + w // 2, y, h, TRIM)
    s.hl(x, y + h // 2, w, TRIM)
    if broken:
        s.line(x + 1, y + 2, x + 4, y + h - 1, c("5a6a7a"))
    if boarded:
        s.line(x - 2, y + 1, x + w + 1, y + h - 3, WOOD_L, 2)
        s.line(x - 2, y + h - 3, x + w + 1, y + 1, WOOD, 2)
    if shutters:
        s.r(x - 5, y - 1, 3, h + 2, shutters)
        s.r(x + w + 2, y - 1, 3, h + 2, shutters)
        for yy in range(y, y + h, 3):
            s.hl(x - 5, yy, 3, shade(shutters, 0.8))
            s.hl(x + w + 2, yy, 3, shade(shutters, 0.8))
    if box:
        s.r(x - 2, y + h + 2, w + 4, 3, WOOD_D)
        for i in range(0, w + 4, 2):
            s.p(x - 2 + i, y + h + 1, box[(i // 2) % len(box)])
            s.p(x - 1 + i, y + h + 1, c("4e8a3e"))


def door(s, x, y, w=12, h=18, col=WOOD_D, canopy=None, lamp=False):
    s.r(x - 2, y - 2, w + 4, h + 2, TRIM)
    s.r(x, y, w, h, col)
    for i in range(2, w, 3):
        s.vl(x + i, y, h, shade(col, 0.82))
    s.hl(x, y + h // 3, w, shade(col, 0.75))
    s.p(x + w - 3, y + h // 2 + 1, c("e0c060"))
    s.r(x - 3, y + h, w + 6, 2, STONE_L)
    if canopy:
        s.poly([(x - 4, y - 2), (x + w + 3, y - 2), (x + w + 1, y - 6), (x - 2, y - 6)], canopy)
    if lamp:
        s.r(x + w + 4, y + 2, 3, 4, c("f6d878"))
        s.hl(x + w + 3, y + 1, 5, c("2a2a2a"))


def chimney(s, x, y, h=12, col=c("8a4a3a")):
    s.r(x, y, 7, h, col)
    for yy in range(y + 2, y + h, 3):
        s.hl(x, yy, 7, shade(col, 0.82))
    s.r(x - 1, y, 9, 2, STONE_D)


def house_long(name, w, h, wall, roof=SLATE, windows=2, shabby=False, broken=False, flowers=None,
               shutters=None, annex=None, door_col=WOOD_D, lit=False):
    s = Spr(w, h, seed(name))
    if shabby:
        wall = mix(wall, c("8a8478"), 0.5)
    main_w = w - (annex[0] if annex else 0)
    roof_h = int(h * 0.46)
    wall_y = roof_h - 2
    wall_h = h - wall_y - 4
    planks(s, 3, wall_y, main_w - 6, wall_h, wall, weathered=shabby)
    s.vl(3, wall_y, wall_h, TRIM if not shabby else c("b8b0a0"))
    s.vl(4, wall_y, wall_h, TRIM if not shabby else c("b8b0a0"))
    s.vl(main_w - 5, wall_y, wall_h, TRIM if not shabby else c("b8b0a0"))
    s.vl(main_w - 4, wall_y, wall_h, TRIM if not shabby else c("b8b0a0"))
    for xx in range(3, main_w - 3, 5):
        s.r(xx, h - 6, 4, 2, STONE if (xx // 5) % 2 else STONE_L)
    if annex:
        aw, acol = annex
        ax = main_w - 4
        ay = wall_y + 8
        planks(s, ax, ay, aw + 1, h - ay - 4, acol)
        s.vl(w - 3, ay, h - ay - 4, TRIM)
        shingles(s, [(ax - 2, ay + 2), (w, ay + 2), (w, ay - 6), (ax + 2, ay - 9)], *SLATE)
        window(s, ax + aw // 2 - 3, ay + 8, 8, 9, box=flowers)
    # roof: 3/4 view slope with visible gable ends
    inset = 7
    pts = [(0, roof_h + 1), (main_w - 1, roof_h + 1), (main_w - 1 - inset, 6), (inset, 6)]
    if not shabby:
        chimney(s, main_w - 26, 0, 14)
    else:
        chimney(s, main_w - 24, 1, 12, c("6a5a50"))
    shingles(s, pts, *roof)
    s.line(inset, 6, main_w - 1 - inset, 6, roof[2])
    s.line(0, roof_h + 1, inset, 6, shade(roof[1], 0.8))
    s.line(main_w - 1, roof_h + 1, main_w - 1 - inset, 6, shade(roof[1], 0.8))
    s.hl(0, roof_h + 1, main_w, shade(roof[1], 0.7))
    if shabby:
        rng = s.rng
        for _ in range(main_w // 9):
            px, py = rng.randrange(inset + 2, main_w - inset - 9), rng.randrange(8, roof_h - 4)
            s.r(px, py, rng.randrange(4, 9), rng.randrange(3, 5), rng.choice([c("6a5040"), c("5a6a40"), c("806850")]))
        s.speckle(0, 6, main_w, roof_h - 4, [c("5a8a3a"), c("4a7a32")], 0.07)
    dx = main_w // 2 - 6
    door(s, dx, h - 4 - 20, 12, 18, door_col, canopy=None if shabby else roof[1], lamp=not shabby)
    wy = wall_y + 7
    slots = [main_w // 4 - 5, main_w - main_w // 4 - 5] if windows >= 2 else [main_w - main_w // 4 - 5]
    for i, wx in enumerate(slots):
        window(s, wx, wy, 10, 11, shutters=shutters, box=flowers, broken=broken, boarded=shabby and i == 0, lit=lit)
    if shabby:
        s.line(8, h - 12, 15, h - 16, shade(wall, 0.55))
        s.r(main_w - 16, wall_y + 6, 7, 6, c("7a6a50"))
        s.vl(main_w - 13, wall_y + 6, 6, c("5a4a38"))
    sel_outline(s)
    s.shadow(2, h - 7, w - 2, 8)
    base = [3, wall_y + 6, w - 6, h - wall_y - 9]
    reg(name, s, base=base, oy=h - 3, door=[main_w // 2, h - 3], extra={"smoke": [main_w - 22, 0]})


def house_gable(name, w, h, wall, roof=SLATE, flowers=None, shutters=None, lit=False):
    """Front-gable Nordic house (reference: the blue house)."""
    s = Spr(w, h, seed(name))
    gable_top = 8
    eave_y = int(h * 0.42)
    # roof sides peeking out left and right of the gable
    shingles(s, [(0, eave_y + 4), (w // 2, gable_top - 6), (w - 1, eave_y + 4), (w - 6, eave_y + 6), (w // 2, gable_top), (5, eave_y + 6)], *roof)
    planks(s, 5, eave_y, w - 10, h - eave_y - 4, wall)
    # gable triangle in wall colour with trim
    s.poly([(6, eave_y + 1), (w // 2, gable_top + 2), (w - 7, eave_y + 1)], wall)
    for xx in range(6, w - 6, 4):
        top = eave_y - int((w // 2 - abs(xx - w // 2)) * (eave_y - gable_top) / (w // 2))
        s.vl(xx, max(top + 2, gable_top + 4), eave_y - max(top, gable_top + 2), shade(wall, 0.82))
    s.line(5, eave_y + 2, w // 2, gable_top, TRIM, 2)
    s.line(w - 6, eave_y + 2, w // 2, gable_top, TRIM, 2)
    chimney(s, w - 20, gable_top + 2, 10)
    # attic window
    window(s, w // 2 - 4, eave_y - 18, 8, 9)
    s.vl(5, eave_y, h - eave_y - 4, TRIM)
    s.vl(w - 6, eave_y, h - eave_y - 4, TRIM)
    for xx in range(5, w - 5, 5):
        s.r(xx, h - 6, 4, 2, STONE if (xx // 5) % 2 else STONE_L)
    door(s, w // 2 - 6, h - 24, 12, 18, WOOD_D, canopy=roof[1], lamp=True)
    for wx in (10, w - 20):
        window(s, wx, eave_y + 8, 10, 11, shutters=shutters, box=flowers, lit=lit)
    sel_outline(s)
    s.shadow(3, h - 7, w - 4, 8)
    reg(name, s, base=[5, eave_y + 6, w - 10, h - eave_y - 9], oy=h - 3, door=[w // 2, h - 3], extra={"smoke": [w - 16, gable_top + 2]})


def turf_house(name, w, h, wall, windows=1):
    s = Spr(w, h, seed(name))
    roof_h = int(h * 0.5)
    stone_side = c("8a8478")
    s.r(2, roof_h - 4, w - 4, h - roof_h, stone_side)
    s.speckle(2, roof_h - 4, w - 4, h - roof_h, [STONE_D, STONE_L], 0.35)
    # gabled timber front in the middle
    fx, fw = 10, w - 20
    planks(s, fx, roof_h - 2, fw, h - roof_h - 2, wall)
    s.poly([(fx, roof_h - 1), (w // 2, roof_h - 14), (fx + fw - 1, roof_h - 1)], wall)
    s.line(fx, roof_h, w // 2, roof_h - 14, TRIM)
    s.line(fx + fw - 1, roof_h, w // 2, roof_h - 14, TRIM)
    # turf
    g = c("6aa84f")
    s.ell(0, 2, w, roof_h + 2, g)
    s.r(0, roof_h // 2, w, roof_h // 2, g)
    s.speckle(0, 0, w, roof_h, [c("4e8a3e"), c("8cc060"), c("7ab858")], 0.4)
    for xx in range(2, w - 2, 3):
        s.p(xx, 2 + abs(xx - w // 2) // 6, c("9ad070"))
    # re-draw the front over the turf
    s.poly([(fx + 2, roof_h + 1), (w // 2, roof_h - 11), (fx + fw - 3, roof_h + 1)], wall)
    planks(s, fx + 2, roof_h, fw - 4, h - roof_h - 4, wall)
    door(s, w // 2 - 5, h - 22, 10, 17, WOOD_D)
    if windows:
        window(s, fx + 4, roof_h + 4, 7, 8)
    chimney(s, w - 16, 0, 9, STONE)
    sel_outline(s)
    s.shadow(2, h - 7, w - 2, 8)
    reg(name, s, base=[2, roof_h, w - 4, h - roof_h - 5], oy=h - 3, door=[w // 2, h - 3], extra={"smoke": [w - 12, 0]})


def church():
    w, h = 96, 136
    s = Spr(w, h, 7)
    body_y = 66
    shingles(s, [(0, body_y + 20), (w - 1, body_y + 20), (w - 9, body_y - 8), (8, body_y - 8)], *SLATE)
    planks(s, 4, body_y + 18, w - 8, h - body_y - 22, WHITE)
    for xx in range(4, w - 4, 6):
        s.r(xx, h - 7, 5, 3, STONE if (xx // 6) % 2 else STONE_L)
    for wx in (10, w - 21):
        s.r(wx, body_y + 30, 10, 20, GLASS)
        s.ell(wx, body_y + 26, 10, 9, GLASS)
        s.vl(wx + 5, body_y + 26, 24, c("c8a84a"))
        s.hl(wx, body_y + 38, 10, c("c8a84a"))
        s.p(wx + 2, body_y + 31, GLASS_L)
    tx, tw = w // 2 - 14, 28
    planks(s, tx, 40, tw, h - 44, c("f6f2e8"))
    s.vl(tx, 40, h - 44, STONE_L)
    s.vl(tx + tw - 1, 40, h - 44, STONE_L)
    s.r(tx + 8, 48, 12, 13, c("23232c"))
    s.ell(tx + 8, 45, 12, 8, c("23232c"))
    s.r(tx + 11, 52, 6, 6, c("d0a848"))
    s.poly([(tx - 4, 42), (tx + tw + 3, 42), (w // 2, 3)], SLATE[1])
    s.poly([(tx - 1, 41), (w // 2, 6), (w // 2, 41)], SLATE[0])
    s.r(w // 2 - 1, 0, 3, 8, c("e6c35a"))
    s.r(w // 2 - 3, 2, 7, 2, c("e6c35a"))
    s.ell(w // 2 - 5, 66, 10, 10, c("c8a84a"))
    s.ell(w // 2 - 4, 67, 8, 8, GLASS)
    door(s, w // 2 - 7, h - 26, 14, 21, c("5a3020"))
    s.ell(w // 2 - 7, h - 30, 14, 9, c("5a3020"))
    sel_outline(s)
    s.shadow(2, h - 8, w - 2, 8)
    reg("church", s, base=[4, body_y + 24, w - 8, h - body_y - 27], oy=h - 3, door=[w // 2, h - 3])


def manor():
    w, h = 184, 128
    s = Spr(w, h, 11)
    cream = c("eee2c4")
    roof_h = 52
    for cx in (28, w - 38):
        chimney(s, cx, 0, 18, c("9a5a4a"))
    shingles(s, [(0, roof_h + 2), (w - 1, roof_h + 2), (w - 12, 10), (11, 10)], c("3a4260"), c("283048"), c("56607e"))
    for dx in (34, w // 2 - 7, w - 48):
        s.r(dx, 24, 14, 18, cream)
        s.poly([(dx - 3, 25), (dx + 16, 25), (dx + 7, 14)], c("283048"))
        window(s, dx + 3, 28, 8, 9)
    wall_y = roof_h
    s.r(4, wall_y, w - 8, h - wall_y - 4, cream)
    for yy in range(wall_y + 4, h - 5, 5):
        s.hl(4, yy, w - 8, shade(cream, 0.94))
    for k in range(3):
        s.hl(4, wall_y + k, w - 8, shade(cream, 0.7 + k * 0.1))
    for yy in range(wall_y, h - 5, 5):
        alt = (yy // 5) % 2
        s.r(4, yy, 6 if alt else 8, 4, STONE_L)
        s.r(w - 12 if alt else w - 10, yy, 8, 4, STONE_L)
    for xx in range(4, w - 4, 6):
        s.r(xx, h - 8, 5, 4, STONE if (xx // 6) % 2 else STONE_L)
    for row, wy in enumerate((wall_y + 8, wall_y + 36)):
        for wx in range(18, w - 18, 26):
            if abs(wx + 5 - w // 2) < 18 and row == 1:
                continue
            window(s, wx, wy, 10, 14, shutters=c("3a5a4a"), box=[c("d04a5a"), c("f0c040")] if row == 1 else None)
    px = w // 2 - 20
    s.poly([(px - 3, wall_y + 28), (px + 43, wall_y + 28), (w // 2, wall_y + 15)], TRIM)
    s.r(px, wall_y + 28, 40, 4, TRIM)
    for cx in (px + 2, px + 33):
        s.r(cx, wall_y + 32, 5, h - wall_y - 38, c("faf6ec"))
        s.vl(cx + 4, wall_y + 32, h - wall_y - 38, STONE_L)
    door(s, w // 2 - 8, h - 27, 16, 21, c("5a2a2a"), lamp=True)
    s.r(px - 4, h - 6, 48, 2, STONE_L)
    s.r(px - 7, h - 4, 54, 2, STONE)
    sel_outline(s)
    s.shadow(2, h - 8, w - 2, 9)
    reg("manor", s, base=[4, wall_y + 8, w - 8, h - wall_y - 11], oy=h - 3, door=[w // 2, h - 3], extra={"smoke": [32, 0]})


def inn():
    w, h = 124, 100
    s = Spr(w, h, 3)
    roof_h = 40
    for cx in (14, w - 26):
        chimney(s, cx, 0, 14)
    shingles(s, [(0, roof_h + 2), (w - 1, roof_h + 2), (w - 9, 8), (8, 8)], c("70362c"), c("4e2420"), c("94503e"))
    wall = c("6a4632")
    planks(s, 4, roof_h, w - 8, h - roof_h - 4, wall, vertical=False)
    s.hl(4, roof_h + 26, w - 8, shade(wall, 0.6))   # floor beam between storeys
    for xx in range(4, w - 4, 6):
        s.r(xx, h - 6, 5, 2, STONE if (xx // 6) % 2 else STONE_L)
    for wx in range(12, w - 12, 22):
        window(s, wx, roof_h + 8, 10, 10, box=[c("e05050"), c("f0d040"), c("e070c0")], lit=True)
    for wx in (12, 32, w - 42, w - 22):
        window(s, wx, roof_h + 34, 10, 12, lit=True)
    door(s, w // 2 - 7, h - 24, 14, 19, c("4a2a1a"), canopy=c("4e2420"), lamp=True)
    sx = w // 2 + 14
    s.hl(sx - 3, roof_h + 30, 16, c("2a2a2a"))
    s.r(sx, roof_h + 32, 14, 10, c("d0a060"))
    s.r(sx + 3, roof_h + 34, 6, 6, c("f0e0b0"))
    s.r(sx + 9, roof_h + 35, 2, 4, c("f0e0b0"))
    # small porch with barrels
    s.r(6, h - 16, 10, 12, WOOD)
    s.ell(6, h - 18, 10, 4, WOOD_L)
    sel_outline(s)
    s.shadow(2, h - 7, w - 2, 8)
    reg("inn", s, base=[4, roof_h + 10, w - 8, h - roof_h - 13], oy=h - 3, door=[w // 2, h - 3], extra={"smoke": [18, 0]})


def warehouse():
    w, h = 108, 80
    s = Spr(w, h, 5)
    roof_h = 34
    shingles(s, [(0, roof_h + 2), (w - 1, roof_h + 2), (w - 8, 4), (7, 4)], *SLATE)
    planks(s, 4, roof_h, w - 8, h - roof_h - 4, c("8a3a30"))
    s.r(w // 2 - 16, h - 34, 32, 30, c("4a2a20"))
    s.line(w // 2 - 16, h - 34, w // 2 + 15, h - 5, WOOD_L)
    s.line(w // 2 + 15, h - 34, w // 2 - 16, h - 5, WOOD_L)
    s.vl(w // 2, h - 34, 30, c("2a1a14"))
    s.r(w // 2 - 3, roof_h - 10, 6, 8, c("3a2a20"))  # hoist beam
    window(s, 12, roof_h + 8, 10, 8)
    window(s, w - 22, roof_h + 8, 10, 8)
    sel_outline(s)
    s.shadow(2, h - 7, w - 2, 8)
    reg("warehouse", s, base=[4, roof_h + 8, w - 8, h - roof_h - 11], oy=h - 3, door=[w // 2, h - 3])


def smithy():
    w, h = 92, 76
    s = Spr(w, h, 9)
    chimney(s, w - 24, 0, 22, STONE_D)
    shingles(s, [(0, 36), (w - 1, 36), (w - 8, 10), (7, 10)], c("4a4038"), c("342c26"), c("5e544a"))
    planks(s, 4, 34, w - 8, h - 38, c("5a3e2c"))
    s.r(10, 42, 34, 26, c("1e1612"))
    s.r(15, 54, 24, 14, STONE_D)
    s.r(19, 55, 16, 6, c("f08a2a"))
    s.r(22, 56, 10, 4, c("f8d050"))
    for k in range(4):
        s.p(20 + k * 4, 52 - k % 2, c("f8a040"))
    door(s, w - 30, h - 24, 12, 19, WOOD_D)
    for xx in range(4, w - 4, 6):
        s.r(xx, h - 6, 5, 2, STONE)
    sel_outline(s)
    s.shadow(2, h - 7, w - 2, 8)
    reg("smithy", s, base=[4, 40, w - 8, h - 43], oy=h - 3, door=[w - 24, h - 3], extra={"smoke": [w - 20, 0]})


def barn():
    w, h = 124, 112
    s = Spr(w, h, 13)
    red = mix(c("9e382c"), c("8a7a70"), 0.3)
    gy = 38
    s.poly([(0, gy + 3), (w // 2, 0), (w - 1, gy + 3)], c("4a3a34"))
    planks(s, 6, gy, w - 12, h - gy - 4, red, weathered=True)
    s.poly([(9, gy), (w // 2, 9), (w - 10, gy)], red)
    for xx in range(12, w - 12, 4):
        top = gy - int((w // 2 - abs(xx - w // 2)) * (gy - 9) / (w // 2))
        s.vl(xx, max(top + 1, 10), gy - max(top, 9), shade(red, 0.82))
    s.line(6, gy + 2, w // 2, 6, TRIM, 2)
    s.line(w - 7, gy + 2, w // 2, 6, TRIM, 2)
    s.r(w // 2 - 9, 18, 18, 15, c("3a2620"))
    s.line(w // 2 - 9, 18, w // 2 + 8, 32, TRIM)
    dx, dy, dw, dh = w // 2 - 24, h - 50, 48, 46
    s.r(dx - 2, dy - 2, dw + 4, dh + 2, c("d8d0c0"))
    s.r(dx, dy, dw, dh, shade(red, 0.85))
    for half in (0, dw // 2):
        s.line(dx + half, dy, dx + half + dw // 2 - 1, dy + dh - 1, c("d8d0c0"))
        s.line(dx + half + dw // 2 - 1, dy, dx + half, dy + dh - 1, c("d8d0c0"))
    s.vl(w // 2, dy, dh, c("d8d0c0"))
    # the mark Clara recognises
    s.ell(w // 2 + 8, dy + 6, 6, 6, c("f0e0b0"))
    s.p(w // 2 + 10, dy + 8, red)
    window(s, 15, gy + 18, 10, 10, broken=True)
    s.speckle(6, gy, w - 12, h - gy, [c("4e7a34"), c("5e8a3e")], 0.02)
    sel_outline(s)
    s.shadow(2, h - 7, w - 2, 8)
    reg("barn", s, base=[6, gy + 8, w - 12, h - gy - 11], oy=h - 3, door=[w // 2, h - 3])


def shed(name, col):
    s = Spr(44, 40, seed(name))
    shingles(s, [(0, 18), (43, 18), (39, 3), (4, 3)], c("5a5048"), c("403830"), c("6e6458"))
    planks(s, 3, 16, 38, 20, col)
    door(s, 15, 19, 12, 15, WOOD_D)
    sel_outline(s)
    s.shadow(1, 33, 42, 6)
    reg(name, s, base=[3, 22, 38, 14], oy=37)


def mine_entrance():
    s = Spr(56, 48, 33)
    s.ell(0, 4, 56, 44, STONE_D)
    s.speckle(0, 4, 56, 44, [STONE, c("5a5a64")], 0.4)
    s.ell(14, 16, 28, 32, c("140f0c"))
    s.r(14, 32, 28, 16, c("140f0c"))
    s.r(12, 16, 4, 32, WOOD)
    s.r(40, 16, 4, 32, WOOD)
    s.r(10, 14, 36, 5, WOOD_L)
    s.line(16, 26, 40, 40, WOOD_L, 2)
    s.line(16, 40, 40, 26, WOOD_L, 2)
    sel_outline(s)
    reg("mine_entrance", s, base=[0, 24, 56, 22], oy=46)


def harbour_props():
    # big fishing boat with cabin (reference: red hull)
    s = Spr(72, 64, 41)
    s.poly([(2, 44), (69, 44), (61, 60), (10, 60)], c("e8e0d0"))
    s.r(4, 44, 64, 4, c("b0382e"))
    s.r(9, 54, 54, 4, c("2f4a78"))
    s.r(20, 30, 20, 14, c("efe6d4"))
    s.r(20, 28, 22, 3, c("8a3a30"))
    window(s, 24, 34, 6, 5)
    window(s, 32, 34, 6, 5)
    s.r(48, 2, 2, 42, WOOD_D)
    s.poly([(51, 6), (51, 36), (68, 38)], c("f2ead8"))
    s.line(49, 3, 4, 44, c("6a6a6a"))
    s.line(49, 3, 69, 44, c("6a6a6a"))
    s.r(66, 46, 4, 4, c("e05030"))
    sel_outline(s)
    reg("fishing_boat", s, oy=62, extra={"reflect": True})
    # two-mast trading vessel
    s = Spr(96, 84, 43)
    s.poly([(2, 60), (93, 60), (84, 80), (12, 80)], c("6a4630"))
    s.r(4, 60, 88, 4, c("2a2a30"))
    s.r(10, 70, 76, 3, c("c8a050"))
    for mx, top in ((32, 4), (64, 10)):
        s.r(mx, top, 2, 58 - top, WOOD_D)
        s.poly([(mx - 16, top + 8), (mx + 18, top + 8), (mx + 20, top + 40), (mx - 18, top + 40)], c("efe6d0"))
        s.hl(mx - 16, top + 20, 34, c("d8cdb4"))
        s.hl(mx - 17, top + 32, 36, c("d8cdb4"))
    s.line(33, 4, 2, 60, c("5a5a5a"))
    s.line(65, 10, 93, 60, c("5a5a5a"))
    for wx in range(14, 84, 10):
        s.r(wx, 64, 4, 3, c("1c1c20"))
    sel_outline(s)
    reg("trade_ship", s, oy=82, extra={"reflect": True})
    # net drying rack
    s = Spr(40, 30, 45)
    for px in (2, 36):
        s.r(px, 2, 2, 27, WOOD_D)
    s.hl(2, 3, 36, WOOD)
    for x in range(4, 36):
        for y in range(5, 22):
            if (x + y) % 4 == 0 or (x - y) % 4 == 0:
                s.p(x, y, c("8a9a8a"))
    for x in range(4, 36, 6):
        s.p(x, 22 + (x // 6) % 2, c("e0c040"))  # floats
    sel_outline(s)
    reg("net_rack", s, base=[1, 24, 38, 5], oy=29)
    # rope coil, buoy, lobster pots
    s = Spr(14, 10, 46)
    s.ell(0, 1, 14, 9, c("b8a070"))
    s.ell(3, 3, 8, 5, c("8a7450"))
    s.ell(5, 4, 4, 3, c("b8a070"))
    sel_outline(s)
    reg("rope", s, oy=10, flat=True)
    s = Spr(10, 14, 47)
    s.ell(0, 3, 10, 11, c("e0503a"))
    s.hl(0, 8, 10, c("f4f0e8"))
    s.r(4, 0, 2, 4, c("4a4a4a"))
    sel_outline(s)
    reg("buoy", s, oy=14, extra={"reflect": True})
    s = Spr(18, 14, 48)
    s.r(1, 3, 16, 10, c("8a6a42"))
    for x in range(2, 17, 3):
        s.vl(x, 3, 10, c("c8b080"))
    s.ell(1, 0, 16, 6, c("8a6a42"))
    sel_outline(s)
    reg("lobster_pot", s, base=[1, 7, 16, 6], oy=13)
    # laundry line
    s = Spr(48, 30, 49)
    s.r(1, 2, 2, 27, WOOD_D); s.r(45, 2, 2, 27, WOOD_D)
    s.line(2, 4, 46, 6, c("e8e0d0"))
    for (x, col) in ((7, c("f0ece0")), (16, c("8a3a3a")), (26, c("3f6aa0")), (36, c("e0c060"))):
        s.r(x, 5, 7, 10, col)
        s.hl(x, 5, 7, shade(col, 0.8))
    sel_outline(s)
    reg("laundry", s, base=[0, 25, 48, 4], oy=29)
    # vegetable garden patch
    s = Spr(48, 32, 50)
    s.r(0, 0, 48, 32, c("7a5236"))
    for y in range(3, 30, 6):
        s.hl(1, y, 46, c("5e3e28"))
        for x in range(3, 46, 5):
            s.r(x, y - 3, 3, 3, c("5aa04a"))
            s.p(x + 1, y - 4, c("7ac060"))
    sel_outline(s, 0.6)
    reg("garden", s, oy=32, flat=True)
    # gull (2 frames)
    fr = []
    for f in range(2):
        g = Spr(12, 8, 51 + f)
        if f == 0:
            g.line(0, 2, 5, 5, c("f4f4f4"), 1); g.line(11, 2, 6, 5, c("f4f4f4"), 1)
        else:
            g.line(0, 5, 5, 4, c("f4f4f4"), 1); g.line(11, 5, 6, 4, c("f4f4f4"), 1)
        g.r(5, 4, 2, 2, c("f4f4f4"))
        g.p(6, 5, c("e0a030"))
        fr.append(g)
    reg("gull", None, frames=fr, fps=4, oy=8)
    # water sparkle (4 frames)
    fr = []
    for f in range(4):
        g = Spr(8, 4, 60 + f)
        w_ = [0, 2, 4, 2][f]
        if w_:
            g.r(4 - w_, 1, w_ * 2, 1, c("f4fbff", 200))
        fr.append(g)
    reg("sparkle", None, frames=fr, fps=5, oy=4, flat=True)
    # small islet rocks in the sea
    s = Spr(40, 22, 61)
    s.ell(0, 6, 40, 16, STONE_D)
    s.ell(3, 2, 30, 14, STONE)
    s.ell(8, 3, 14, 7, STONE_L)
    s.speckle(0, 0, 40, 22, [c("5a8a4a")], 0.04)
    sel_outline(s)
    reg("islet", s, oy=20, extra={"reflect": True})
    # wooden footbridge railing (decor on bridges)
    s = Spr(48, 10, 62)
    s.r(0, 2, 48, 2, WOOD_L)
    for x in range(0, 48, 8):
        s.r(x, 0, 2, 10, WOOD_D)
    sel_outline(s)
    reg("railing", s, oy=10)


def shop():
    """Henrik's store on the square: big display window, hanging sign, awning."""
    w, h = 84, 80
    s = Spr(w, h, 71)
    roof_h = 36
    chimney(s, w - 22, 0, 12)
    shingles(s, [(0, roof_h + 2), (w - 1, roof_h + 2), (w - 8, 6), (7, 6)], c("3f5a46"), c("2c4232"), c("587a60"))
    wall = c("3f6a5a")
    planks(s, 4, roof_h, w - 8, h - roof_h - 4, wall)
    # display window with goods
    s.r(8, roof_h + 12, 30, 22, TRIM)
    s.r(10, roof_h + 14, 26, 18, GLASS)
    for k, col in enumerate((c("e0c060"), c("c05a3a"), c("7ab0d0"), c("e8e0d0"), c("9a6a3a"))):
        s.r(12 + k * 5, roof_h + 24, 4, 6, col)
    s.r(10, roof_h + 14, 12, 8, mix(GLASS, GLASS_L, 0.35))
    # striped awning
    for i in range(0, 34, 6):
        s.r(6 + i, roof_h + 6, 6, 6, c("c0403a") if (i // 6) % 2 == 0 else TRIM)
    door(s, w - 30, h - 24, 12, 19, c("5a3a22"), lamp=True)
    # hanging sign: a coin and a parcel
    s.hl(w - 40, roof_h + 4, 14, c("2a2a2a"))
    s.r(w - 38, roof_h + 6, 12, 9, c("d0a060"))
    s.ell(w - 36, roof_h + 8, 5, 5, c("e8c040"))
    s.r(w - 31, roof_h + 9, 4, 4, c("8a5a32"))
    for xx in range(4, w - 4, 5):
        s.r(xx, h - 6, 4, 2, STONE if (xx // 5) % 2 else STONE_L)
    sel_outline(s)
    s.shadow(2, h - 7, w - 2, 8)
    reg("shop", s, base=[4, roof_h + 8, w - 8, h - roof_h - 11], oy=h - 3, door=[w - 24, h - 3], extra={"smoke": [w - 18, 0]})


def boathouse():
    """Fishing-gear store by the water: tarred planks, net hung on the wall, oars."""
    w, h = 72, 60
    s = Spr(w, h, 72)
    shingles(s, [(0, 26), (w - 1, 26), (w - 7, 4), (6, 4)], c("4a4038"), c("342c26"), c("5e544a"))
    planks(s, 3, 24, w - 6, h - 28, c("4a3a30"))
    s.r(w // 2 - 14, h - 28, 28, 24, c("2a1e18"))
    s.vl(w // 2, h - 28, 24, c("6a5040"))
    for x in range(6, 24):
        for y in range(30, 46):
            if (x + y) % 4 == 0 or (x - y) % 4 == 0:
                s.p(x, y, c("9aa894"))
    s.line(w - 12, 30, w - 6, 52, WOOD_L, 2)
    s.line(w - 8, 30, w - 14, 52, WOOD_L, 2)
    s.r(w - 16, 50, 6, 3, c("e05030"))
    sel_outline(s)
    s.shadow(2, h - 6, w - 2, 7)
    reg("boathouse", s, base=[3, 30, w - 6, h - 33], oy=h - 3)


def stable():
    """Elias' stable and carriage house: neat, painted, with a weather vane."""
    w, h = 96, 72
    s = Spr(w, h, 73)
    shingles(s, [(0, 32), (w - 1, 32), (w - 8, 6), (7, 6)], c("3a4260"), c("283048"), c("56607e"))
    s.r(w // 2 - 1, 0, 2, 8, c("2a2a2a"))
    s.poly([(w // 2, 0), (w // 2 + 8, 2), (w // 2, 4)], c("d0a848"))
    planks(s, 4, 30, w - 8, h - 34, c("efe2c4"))
    for dx in (10, w - 34):
        s.r(dx, h - 30, 24, 26, c("7a3a2a"))
        s.line(dx, h - 30, dx + 23, h - 5, c("efe2c4"))
        s.line(dx + 23, h - 30, dx, h - 5, c("efe2c4"))
    s.r(w // 2 - 5, 38, 10, 8, GLASS)
    s.ell(w // 2 - 8, 6 + 14, 16, 10, c("efe2c4"))
    s.ell(w // 2 - 4, 6 + 16, 8, 6, c("3a2a20"))
    for xx in range(4, w - 4, 6):
        s.r(xx, h - 6, 5, 2, STONE_L)
    sel_outline(s)
    s.shadow(2, h - 7, w - 2, 8)
    reg("stable", s, base=[4, 36, w - 8, h - 39], oy=h - 3)


def estate_gate():
    """Two stone pillars with lanterns and a wrought-iron arch (walk-through)."""
    w, h = 56, 52
    s = Spr(w, h, 74)
    for px in (0, w - 10):
        s.r(px, 14, 10, 36, STONE_L)
        s.r(px, 14, 10, 3, STONE)
        for y in range(18, 50, 6):
            s.hl(px, y, 10, STONE)
        s.r(px + 2, 6, 6, 8, c("2a2a2a"))
        s.r(px + 3, 8, 4, 4, c("f6d878"))
    for x in range(10, w - 10):
        y = 14 - int(8 * (1 - ((x - w / 2) / (w / 2 - 10)) ** 2))
        s.p(x, y, c("2a2a30"))
        s.p(x, y + 1, c("2a2a30"))
    for x in range(14, w - 12, 6):
        s.vl(x, 12, 4, c("2a2a30"))
    sel_outline(s)
    reg("estate_gate", s, oy=h - 2, extra={"posts": True})


def build(register):
    global reg
    reg = register
    for name, col, fl, sh in (("house_red", "red", [c("f0f0f0"), c("f0c040")], None),
                              ("house_blue", "blue", [c("e05050"), c("f0f0f0")], c("2c4e80")),
                              ("house_yellow", "yellow", [c("e05080"), c("8040c0")], c("4f8a54")),
                              ("house_green", "green", [c("f0d040"), c("f0f0f0")], None),
                              ("house_white", "white", [c("e05050"), c("4080e0")], c("a83a30"))):
        house_long(name, 88, 80, WALLS[col], flowers=fl, shutters=sh)
    house_long("house_redyellow", 104, 80, WALLS["red"], flowers=[c("f0f0f0")], annex=(30, WALLS["yellow"]))
    house_long("house_red_small", 70, 70, WALLS["red"], windows=1, roof=(c("4a5a4a"), c("3a4a3a"), c("5a6a5a")))
    house_gable("house_blue_gable", 72, 92, WALLS["blue"], flowers=[c("e05050"), c("f0f0f0")])
    house_gable("house_yellow_gable", 72, 92, WALLS["yellow"], shutters=c("3f6aa0"), flowers=[c("e05080")])
    house_gable("house_red_gable", 72, 92, WALLS["red"], flowers=[c("f0f0f0"), c("f0c040")])
    house_gable("house_green_gable", 68, 88, WALLS["green"])
    house_gable("house_white_gable", 68, 88, WALLS["white"], shutters=c("2c4e80"))
    house_long("house_gideon", 70, 72, c("7a6a5a"), shabby=True, door_col=c("5a4a3a"))
    house_long("house_gideon_fixed", 70, 72, c("7a8aa0"), flowers=[c("e05050"), c("f0d040")], shutters=c("4f8a54"), lit=True)
    # after Elias pays the debts: new roof and door, walls still worn and unpainted
    house_long("house_gideon_repaired", 70, 72, c("8a7a66"), roof=(c("5a4a44"), c("40342e"), c("7a6656")), door_col=c("7a4a2a"), shutters=c("6a5a48"))
    house_long("farmhouse", 84, 76, c("8a8a80"), shabby=True, broken=True)
    turf_house("turf_house", 72, 64, c("6a4a32"))
    turf_house("turf_house_b", 76, 66, c("8a3a30"))
    church(); manor(); inn(); warehouse(); smithy(); barn()
    shed("shed", c("7a5a3a")); shed("shed_red", c("9a3a30"))
    mine_entrance()
    shop(); boathouse(); stable(); estate_gate()
    harbour_props()
