"""Title-screen panorama: Hrafnvik at dusk, painted as pixel art in layers.

Layers (all 420x180, drawn 1:1 then scaled up in-game):
  menu_sky.png      dithered dusk gradient with a few early stars
  menu_clouds.png   soft clouds (840 wide, scrolls and wraps)
  menu_scene.png    mountains, hills, the village, church, harbour and a dark foreground
  menu_lights.png   warm window lights (pulsed in-game)
  menu_sea.png      the bay with light reflections (shimmer shader in-game)
plus data/menu.json with chimney positions for smoke.
"""
import json
import math
import random
from PIL import Image, ImageDraw
from pixel import c, shade, mix

W, H = 420, 180
SEA_Y = 132
rng = random.Random(1887)


def new(w=W, h=H):
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    return im, ImageDraw.Draw(im)


def sky():
    im, d = new()
    top, mid, low = c("1f2446"), c("5a4a7a"), c("f0a868")
    for y in range(H):
        t = y / (SEA_Y + 4)
        col = mix(top, mid, t / 0.55) if t < 0.55 else mix(mid, low, min(1, (t - 0.55) / 0.45))
        for x in range(W):
            # ordered dithering between neighbouring bands
            bayer = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]][y % 4][x % 4] / 16.0
            jitter = 0.04 * (bayer - 0.5)
            cc = mix(top, mid, min(1, max(0, t / 0.55 + jitter))) if t < 0.55 else mix(mid, low, min(1, max(0, (t - 0.55) / 0.45 + jitter)))
            d.point((x, y), cc)
    for _ in range(40):
        x, y = rng.randrange(0, W), rng.randrange(0, 50)
        d.point((x, y), c("f4eedc", 200 if rng.random() < 0.5 else 120))
    # a pale moon rising
    d.ellipse([318, 18, 330, 30], fill=c("f6efd6"))
    d.ellipse([321, 18, 333, 30], fill=mix(top, mid, 0.2))
    im.save(f"{OUT}/menu_sky.png")


def clouds():
    im, d = new(840, H)
    for k in range(14):
        cx, cy = rng.randrange(0, 840), rng.randrange(18, 92)
        w = rng.randrange(40, 90)
        base = c("f2b28a", 210) if cy > 60 else c("9a7aa6", 200)
        hl = c("ffd4a8", 220) if cy > 60 else c("c49ab8", 210)
        for i in range(5):
            ox, oy = rng.randrange(-w // 2, w // 2), rng.randrange(-4, 4)
            r = rng.randrange(6, 12)
            for wrap in (0, -840, 840):
                d.ellipse([cx + ox - r * 2 + wrap, cy + oy - r, cx + ox + r * 2 + wrap, cy + oy + r], fill=base)
                d.ellipse([cx + ox - r * 2 + 2 + wrap, cy + oy - r, cx + ox + r * 2 - 4 + wrap, cy + oy - r + 3], fill=hl)
    im.save(f"{OUT}/menu_clouds.png")


def mountains(d):
    peaks = [(40, 52), (110, 38), (175, 58), (250, 34), (330, 48), (395, 60)]
    for px, py in peaks:
        half = int((SEA_Y - py) * 1.25)
        d.polygon([(px - half, SEA_Y - 30), (px, py), (px + half, SEA_Y - 30)], fill=c("4e5880"))
        d.polygon([(px, py), (px + half, SEA_Y - 30), (px + half // 5, SEA_Y - 30)], fill=c("3c4468"))
        sn = 12 + (SEA_Y - py) // 7
        d.polygon([(px - sn, py + sn), (px - sn // 2, py + sn - 3), (px, py + sn + 2), (px + sn // 2, py + sn - 2),
                   (px + sn, py + sn), (px, py)], fill=c("f6e2d2"))
        d.polygon([(px, py), (px + sn, py + sn), (px + 2, py + sn - 2)], fill=c("b8b0c8"))
        d.line([(px - sn, py + sn), (px, py)], fill=c("ffd8b0"))   # warm rim light from the setting sun


def hills(d):
    pts = [(0, 104)]
    for x in range(0, W + 10, 10):
        pts.append((x, 100 + int(8 * math.sin(x * 0.03) + 5 * math.sin(x * 0.11))))
    pts += [(W, SEA_Y), (0, SEA_Y)]
    d.polygon(pts, fill=c("2f5a46"))
    for x in range(0, W, 7):
        y = 100 + int(8 * math.sin(x * 0.03) + 5 * math.sin(x * 0.11))
        if rng.random() < 0.7:
            h = rng.randrange(7, 13)
            d.polygon([(x - 3, y + 2), (x, y - h), (x + 3, y + 2)], fill=c("1f4436"))
    # nearer slope where the village sits
    pts = [(120, SEA_Y)]
    for x in range(120, W + 6, 6):
        pts.append((x, 112 + int(6 * math.sin(x * 0.045))))
    pts += [(W, SEA_Y)]
    d.polygon(pts, fill=c("4a7a4a"))
    for x in range(124, W, 3):
        y = 112 + int(6 * math.sin(x * 0.045))
        d.point((x, y), c("6a9a5a"))


HOUSES = []


def house(d, x, y, w, h, wall, roof=c("2e3346"), gable=False):
    """Small 3/4 house; returns window rectangles for the lights layer."""
    wins = []
    d.rectangle([x, y - h, x + w, y], fill=wall)
    d.line([(x + w, y - h), (x + w, y)], fill=shade(wall, 0.7))
    for xx in range(x + 2, x + w, 3):
        d.line([(xx, y - h + 1), (xx, y)], fill=shade(wall, 0.88))
    if gable:
        d.polygon([(x - 1, y - h), (x + w // 2, y - h - w // 2 - 1), (x + w + 1, y - h)], fill=roof)
        d.polygon([(x + 2, y - h), (x + w // 2, y - h - w // 2 + 2), (x + w - 2, y - h)], fill=wall)
        wins.append((x + w // 2 - 1, y - h - 4, 2, 2))
    else:
        d.polygon([(x - 2, y - h), (x + 1, y - h - 5), (x + w - 1, y - h - 5), (x + w + 2, y - h)], fill=roof)
        d.line([(x + 1, y - h - 5), (x + w - 1, y - h - 5)], fill=shade(roof, 1.4))
    chim = (x + w - 4, y - h - (w // 2 if gable else 5) - 3)
    d.rectangle([chim[0], chim[1], chim[0] + 1, chim[1] + 3], fill=c("5a3a30"))
    HOUSES.append(chim)
    for i, wx in enumerate(range(x + 2, x + w - 2, 4)):
        if i % 2 == 0 or w < 10:
            wins.append((wx, y - h + 3, 2, 2))
    d.rectangle([x + w // 2 - 1, y - 3, x + w // 2, y - 1], fill=c("3a2418"))
    return wins


def scene_and_lights():
    im, d = new()
    li, dl = new()
    mountains(d)
    hills(d)
    windows = []
    # church on the slope
    cx, cy = 236, 114
    d.rectangle([cx, cy - 10, cx + 14, cy], fill=c("e8e0cc"))
    d.polygon([(cx - 1, cy - 10), (cx + 2, cy - 14), (cx + 12, cy - 14), (cx + 15, cy - 10)], fill=c("2e3346"))
    d.rectangle([cx + 4, cy - 22, cx + 9, cy - 10], fill=c("f2ecdc"))
    d.polygon([(cx + 3, cy - 22), (cx + 6, cy - 31), (cx + 10, cy - 22)], fill=c("2e3346"))
    d.line([(cx + 6, cy - 34), (cx + 6, cy - 31)], fill=c("e8c060"))
    d.line([(cx + 5, cy - 33), (cx + 7, cy - 33)], fill=c("e8c060"))
    windows += [(cx + 6, cy - 18, 1, 2), (cx + 2, cy - 7, 2, 3), (cx + 10, cy - 7, 2, 3)]
    # houses climbing the slope (back rows first)
    rows = [
        (118, [(258, 9, 7, "white", 0), (272, 10, 8, "red", 1), (290, 9, 7, "yellow", 0), (338, 12, 8, "blue", 1)]),
        (124, [(150, 10, 7, "red", 0), (166, 9, 8, "blue", 1), (204, 10, 7, "yellow", 0), (306, 11, 8, "white", 0), (322, 9, 7, "red", 1), (356, 10, 7, "green", 0)]),
        (130, [(134, 11, 8, "yellow", 1), (182, 12, 9, "red", 0), (218, 10, 8, "blue", 0), (250, 14, 9, "ochre", 0), (282, 11, 8, "green", 1), (372, 12, 9, "red", 0), (392, 10, 8, "white", 1)]),
    ]
    walls = {"red": c("a83a30"), "blue": c("3f6fae"), "yellow": c("d9a63c"), "white": c("e4ddc8"), "green": c("4f8a54"), "ochre": c("b8803a")}
    for y, hs in rows:
        for (x, w, h, col, gable) in hs:
            windows += house(d, x, y, w, h, walls[col], gable=bool(gable))
    # the small grey Ashford house at the eastern edge, a little apart
    windows += house(d, 404, 128, 9, 7, c("7a6e62"), roof=c("4a4440"))
    # harbour: quay, piers and boats (front layer, drawn over the sea)
    d.rectangle([128, SEA_Y - 2, W, SEA_Y], fill=c("6a5a48"))
    fr, d = new()
    for px in (170, 214, 300):
        d.rectangle([px, SEA_Y, px + 3, SEA_Y + 18], fill=c("6a4a30"))
        for k in range(SEA_Y + 3, SEA_Y + 18, 5):
            d.line([(px - 1, k), (px + 4, k)], fill=c("4a3220"))
    boats = [(180, SEA_Y + 10, 16, c("e8e0d0"), c("b0382e")), (226, SEA_Y + 14, 12, c("6a4630"), c("2a2a30")), (312, SEA_Y + 8, 18, c("e8e0d0"), c("2f4a78"))]
    for bx, by, bw, hull, stripe in boats:
        d.polygon([(bx, by), (bx + bw, by), (bx + bw - 3, by + 4), (bx + 3, by + 4)], fill=hull)
        d.line([(bx, by), (bx + bw, by)], fill=stripe)
        d.line([(bx + bw // 2, by - 14), (bx + bw // 2, by)], fill=c("4a3220"))
        d.polygon([(bx + bw // 2 + 1, by - 13), (bx + bw // 2 + 1, by - 2), (bx + bw - 1, by - 3)], fill=c("f0e6d2"))
        windows.append((bx + 3, by - 2, 1, 1))  # a lantern on deck
    # dark foreground on the left: cliff, grass and a lamp post framing the menu
    fg = [(0, 70), (40, 78), (70, 96), (96, 112), (122, 126), (140, H), (0, H)]
    d.polygon(fg, fill=c("1c2a26"))
    for x in range(0, 130, 4):
        y = int(70 + x * 0.42 + (x * x) * 0.0012)
        if rng.random() < 0.8:
            d.line([(x, y), (x + rng.randrange(-1, 2), y - rng.randrange(2, 6))], fill=c("2c4436"))
    for (tx, ty, th) in ((18, 82, 30), (34, 86, 24), (58, 98, 26)):
        d.rectangle([tx, ty - 6, tx + 1, ty], fill=c("161e1c"))
        for k in range(4):
            hw = 3 + k * 2
            d.polygon([(tx - hw, ty - 6 - k * 5), (tx + 1, ty - th + k * 4 - 6), (tx + 1 + hw, ty - 6 - k * 5)], fill=c("152620"))
    d.rectangle([104, 92, 105, 122], fill=c("141414"))
    d.rectangle([101, 86, 108, 92], fill=c("141414"))
    windows.append((102, 87, 5, 4))
    sd = ImageDraw.Draw(im)
    for (x, y, w, h) in windows:
        (d if y > SEA_Y - 4 or x < 110 else sd).rectangle([x, y, x + w - 1, y + h - 1], fill=c("f6c86a"))
        dl.rectangle([x - 1, y - 1, x + w, y + h], fill=c("ffd27a", 90))
        dl.rectangle([x, y, x + w - 1, y + h - 1], fill=c("fff0b8", 255))
    im.save(f"{OUT}/menu_scene.png")
    fr.save(f"{OUT}/menu_front.png")
    li.save(f"{OUT}/menu_lights.png")
    return windows


def sea(windows):
    im, d = new()
    for y in range(SEA_Y, H):
        t = (y - SEA_Y) / (H - SEA_Y)
        d.line([(0, y), (W, y)], fill=mix(c("c8846a"), c("232a52"), min(1, t * 2.2)))
    for y in range(SEA_Y + 3, H, 4):
        for x in range(rng.randrange(0, 12), W, rng.randrange(18, 34)):
            d.line([(x, y), (x + rng.randrange(2, 5), y)], fill=c("f4c49a", 70 if y > SEA_Y + 16 else 110))
    # long streaks under each lit window: light reflected on the water
    for (x, y, w, h) in windows:
        if y > 100:
            for k in range(SEA_Y + 2, min(H, SEA_Y + 24), 2):
                if rng.random() < 0.75:
                    d.line([(x + rng.randrange(-1, 2), k), (x + w + rng.randrange(0, 2), k)], fill=c("ffd27a", 150 - (k - SEA_Y) * 5))
    # moon path
    for k in range(SEA_Y + 1, H, 2):
        d.line([(320 + rng.randrange(-3, 3), k), (330 + rng.randrange(-2, 4), k)], fill=c("f6efd6", 90))
    im.save(f"{OUT}/menu_sea.png")


def build(out_root):
    global OUT
    OUT = f"{out_root}/assets/ui"
    HOUSES.clear()
    sky()
    clouds()
    windows = scene_and_lights()
    sea(windows)
    json.dump({"size": [W, H], "sea_y": SEA_Y, "chimneys": HOUSES}, open(f"{out_root}/data/menu.json", "w"))
