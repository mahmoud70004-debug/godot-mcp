"""Builds the world of Hrafnvik (redesign following the coastal-village reference).

Layout (tiles, 16px): a terraced coastal village under snowy mountains.
  north    mountains, a high plateau with the herbalist's turf house
           and the waterfall; a cliff band with stone stairs separates it from the village
  centre   market square with the church and Henrik's shop, a cobbled main street to the harbour,
           houses in red/blue/yellow/green/white, smithy, gardens, farms
  south    the harbour bay with long piers, fishing boats and a trading vessel, the inn and
           the warehouse; a beach with a small dock and an old mine below the south-west cliffs
  north-east  Elias' manor on its own terrace above the village
  east     Gideon's worn home at the eastern edge, the river and bridge (gated until ch.4),
           the eastern hills with the abandoned farm, the barn and the shipwreck coast
  x>=152   interiors (home, inn, study, farmhouse, barn)

Outputs data/map.txt, data/world.json, assets/world/ground.png and water_mask.png.

Terrain chars
  .  grass   h hill grass   g tall grass   f farmland   =  dirt path   p cobbles   k stone path
  s  sand    b bridge       d dock         S stairs     ~  sea         r river     P pond
  #  cliff   ^ mountain     o/O/c/D floors V/U/Y/W walls X void
"""
import json
import random
import numpy as np
from paint_ground import paint, value_noise

TS = 16
W, H = 192, 100
OUT_W, OUT_H = 150, 92          # outdoor area used for the camera
IX = 35                         # interiors are the old interior layout shifted by 35 tiles
BLOCKED = set("~rP#^WVUYX")
CRISP = set("bdoOcDVUYWX#^S")

g = np.full((H, W), ".", dtype="<U1")
rng = random.Random(1887)
objects = []
spots = {}
zones = []
occupied = np.zeros((H, W), dtype=bool)
SPR = {}
cliff_y = {}


# ---------------------------------------------------------------- helpers
def fill(x0, y0, x1, y1, ch):
    g[max(0, y0):y1 + 1, max(0, x0):x1 + 1] = ch


def disc(cx, cy, r, ch):
    for y in range(int(cy - r), int(cy + r) + 1):
        for x in range(int(cx - r), int(cx + r) + 1):
            if 0 <= x < W and 0 <= y < H and (x - cx) ** 2 + (y - cy) ** 2 <= r * r:
                g[y, x] = ch


def path(points, width, ch="="):
    """Paint a road. Crossing a river or pond automatically builds a bridge."""
    for (x0, y0), (x1, y1) in zip(points, points[1:]):
        steps = max(abs(x1 - x0), abs(y1 - y0)) * 2 + 1
        for i in range(steps + 1):
            t = i / steps
            x, y = x0 + (x1 - x0) * t, y0 + (y1 - y0) * t
            for dy in range(width):
                for dx in range(width):
                    xi, yi = int(round(x)) + dx, int(round(y)) + dy
                    if not (0 <= xi < W and 0 <= yi < H):
                        continue
                    cur = g[yi, xi]
                    if cur in "rP":
                        g[yi, xi] = "b"
                    elif cur in "bdS#^~":
                        continue
                    else:
                        g[yi, xi] = ch


def noise1(n, scale, amp, seed):
    r = random.Random(seed)
    pts = [r.uniform(-1, 1) for _ in range(n // scale + 3)]
    out = []
    for i in range(n):
        k, t = divmod(i, scale)
        t /= scale
        t = t * t * (3 - 2 * t)
        out.append((pts[k] * (1 - t) + pts[k + 1] * t) * amp)
    return out


def place(sprite, tx, ty, oid=None, show_if=None, interact=None, reserve=True, extra=None, px=0, py=0):
    m = SPR[sprite]
    o = {"sprite": sprite, "x": int(tx * TS + px), "y": int(ty * TS + py)}
    if oid:
        o["id"] = oid
    if show_if:
        o["show_if"] = show_if
    if interact:
        o["interact"] = interact
    if m.get("reflect"):
        o["reflect"] = True
    if extra:
        o.update(extra)
    objects.append(o)
    if reserve:
        x0 = o["x"] // TS
        y0 = (o["y"] + int(m["oy"] * 0.5)) // TS
        x1 = (o["x"] + m["w"] - 1) // TS
        y1 = (o["y"] + m["oy"] - 1) // TS
        occupied[max(0, y0):y1 + 1, max(0, x0):x1 + 1] = True
    return o


def check_footprint(name, o):
    m = SPR[o["sprite"]]
    if "base" not in m:
        return
    bx, by, bw, bh = m["base"]
    for y in range((o["y"] + by) // TS, (o["y"] + by + bh - 1) // TS + 1):
        for x in range((o["x"] + bx) // TS, (o["x"] + bx + bw - 1) // TS + 1):
            if g[y, x] in "=pkbdS":
                print(f"WARN {name} footprint covers road {g[y, x]} at {x},{y}")


def building(sprite, tx, ty, door_to=None, door_id=None, oid=None, show_if=None, smoke=True, door_path=True):
    o = place(sprite, tx, ty, oid=oid, show_if=show_if)
    check_footprint(sprite, o)
    if sprite.startswith("house") or sprite.startswith("turf") or sprite in ("shop", "smithy", "inn"):
        if not show_if:
            DRESSED.append((sprite, o))
    m = SPR[sprite]
    if smoke and "smoke" in m and not show_if:
        sx, sy = m["smoke"]
        place("smoke", 0, 0, px=o["x"] + sx - 6, py=o["y"] + sy - 22, reserve=False)
    if "door" in m:
        dx, dy = m["door"]
        door_tx, door_ty = (o["x"] + dx) // TS, (o["y"] + dy) // TS
        if door_path:
            for k in range(0, 2):
                if g[door_ty + k, door_tx] in ".hg":
                    g[door_ty + k, door_tx] = "k"
        if door_to:
            objects.append({
                "type": "door", "id": door_id or f"door_{sprite}_{tx}", "to": door_to,
                "x": o["x"] + dx - 8, "y": o["y"] + dy - 6, "w": 16, "h": 14,
            })
        occupied[door_ty:door_ty + 2, door_tx] = True
    return o


HOUSE_PROPS = ["barrel", "crate", "woodpile", "flowers_a", "flowers_b", "bush", "bush_berry", "lobster_pot", "bench"]
DRESSED = []


def dress_buildings():
    """Little lived-in details around every village house: barrels, firewood, flower beds..."""
    for (sprite, o) in DRESSED:
        m = SPR[sprite]
        x0, x1 = o["x"] // TS - 1, (o["x"] + m["w"]) // TS + 1
        yb = (o["y"] + m["oy"]) // TS
        r = random.Random(o["x"] * 31 + o["y"])
        cands = [(x0, yb - 1), (x0, yb), (x1, yb - 1), (x1, yb), (x0 + 1, yb + 1), (x1 - 1, yb + 1), (x0, yb - 2), (x1, yb - 2)]
        r.shuffle(cands)
        placed = 0
        for (x, y) in cands:
            if placed >= 3 or not (0 <= x < 150 and 0 <= y < H):
                continue
            if g[y, x] not in ".h" or occupied[y, x]:
                continue
            if np.isin(g[max(0, y - 1):y + 2, max(0, x - 1):x + 2], list("=pkbdS")).any():
                continue
            k = r.choice(HOUSE_PROPS)
            place(k, x, y, reserve=k not in ("flowers_a", "flowers_b"))
            occupied[y, x] = True
            placed += 1


def spot(name, x_px, y_px, facing="down"):
    spots[name] = {"x": int(x_px), "y": int(y_px), "dir": facing}


def tspot(name, tx, ty, facing="down"):
    spot(name, tx * TS + 8, ty * TS + 8, facing)


def interact(iid, tx, ty, tw=1, th=1, show_if=None, label=None):
    o = {"type": "interact", "id": iid, "x": int(tx * TS), "y": int(ty * TS), "w": int(tw * TS), "h": int(th * TS)}
    if show_if:
        o["show_if"] = show_if
    if label:
        o["label"] = label
    objects.append(o)


def zone(zid, name, x0, y0, x1, y1, indoor=False, music="village"):
    zones.append({"id": zid, "name": name, "rect": [x0 * TS, y0 * TS, (x1 - x0 + 1) * TS, (y1 - y0 + 1) * TS],
                  "indoor": indoor, "music": music})


def walkable(x, y):
    return 0 <= x < W and 0 <= y < H and g[y, x] not in BLOCKED


def nearest_walkable(x, y, avoid_occupied=True):
    for r in range(0, 8):
        for dy in range(-r, r + 1):
            for dx in range(-r, r + 1):
                xx, yy = x + dx, y + dy
                if walkable(xx, yy) and not (avoid_occupied and occupied[yy, xx]):
                    return xx, yy
    return x, y


# ---------------------------------------------------------------- terrain
def build_terrain():
    fill(0, 0, W - 1, H - 1, "X")
    fill(0, 0, 149, H - 1, ".")
    mtn = noise1(150, 9, 1.6, 3)
    for x in range(150):
        fill(x, 0, x, int(5 + mtn[x]), "^")
    # the high plateau north of the village and the estate terrace
    cl = noise1(150, 6, 2.2, 4)
    for x in range(0, 118):
        cy = int(round((22 if x < 86 else 30) + cl[x]))
        cliff_y[x] = cy
        for y in range(int(6 + mtn[x]), cy):
            g[y, x] = "h"
        g[cy, x] = "#"
        g[cy + 1, x] = "#"
        g[cy + 2, x] = "#"
    for y in range(cliff_y[85], cliff_y[88] + 3):
        g[y, 86] = "#"
        g[y, 87] = "#"
    # eastern countryside beyond the river
    for x in range(118, 150):
        for y in range(int(6 + mtn[x]), 70):
            g[y, x] = "h"
    # sea, beaches and the harbour bay
    coast = noise1(150, 7, 1.4, 5)
    for x in range(150):
        if x <= 46:
            cy = 77 + coast[x]
        elif x <= 52:
            cy = 77 - (x - 46) * 2.2 + coast[x] * 0.3
        elif x <= 112:
            cy = 64 + coast[x] * 0.4
        elif x <= 121:
            cy = 64 + (x - 112) * 1.4
        else:
            cy = 77 + coast[x]
        cy = int(cy)
        for y in range(cy, H):
            g[y, x] = "~"
        if x <= 46 or x >= 122:
            for y in range(cy - 4, cy):
                if g[y, x] in ".h":
                    g[y, x] = "s"
        elif 104 <= x <= 116:
            for y in range(cy - 2, cy):
                g[y, x] = "#"
        else:
            g[cy - 1, x] = "s"
    # low cliffs above the south-west beach
    for x in range(0, 42):
        g[69, x] = "#"
        g[70, x] = "#"
    # river between village and the eastern hills
    rx = noise1(H, 8, 0.8, 9)
    for y in range(4, H):
        x = int(117 + rx[y])
        if g[y, x] == "~":
            break
        g[y, x] = "r"
        g[y, x + 1] = "r"
    # waterfall stream: plateau river -> falls -> pond -> stream to the beach
    for y in range(5, cliff_y[40] + 3):
        g[y, 40] = "r"
        g[y, 41] = "r"
    disc(41, cliff_y[40] + 6, 3.2, "P")
    sx = noise1(H, 6, 1.2, 13)
    for y in range(cliff_y[40] + 9, H):
        x = int(41 + sx[y])
        if g[y, x] == "~":
            break
        g[y, x] = "r"
        g[y, x + 1] = "r"
    # stairs through the cliff bands
    for (x, y0, y1) in ((61, cliff_y[61], cliff_y[61] + 2), (62, cliff_y[61], cliff_y[61] + 2),
                        (28, cliff_y[28], cliff_y[28] + 2), (29, cliff_y[28], cliff_y[28] + 2),
                        (100, cliff_y[100], cliff_y[100] + 2), (101, cliff_y[100], cliff_y[100] + 2),
                        (31, 69, 70), (32, 69, 70)):
        for y in range(y0, y1 + 1):
            g[y, x] = "S"
    # roads ---------------------------------------------------------------
    path([(0, 44), (20, 44), (40, 44), (52, 43)], 2)                         # west road
    path([(72, 43), (90, 44), (116, 44), (121, 44)], 2)                      # east road + river bridge
    path([(61, cliff_y[61] + 3), (61, 34)], 2, "k")                          # north stairs -> square
    path([(61, 46), (61, 60)], 2, "k")                                       # main street: square -> harbour
    path([(61, cliff_y[61] - 1), (60, 18)], 2)                               # stairs -> plateau
    path([(28, cliff_y[28] - 1), (24, 18), (19, 17)], 1)                     # plateau: to Astrid
    path([(28, 19), (40, 19), (52, 19), (60, 19)], 1)                        # plateau path (bridge above falls)
    path([(60, 19), (72, 18), (78, 18)], 1)                                  # to the hill bench
    path([(100, cliff_y[100] + 3), (100, 43)], 2)                            # estate drive
    path([(100, cliff_y[100] - 1), (100, 18)], 2, "k")
    path([(28, cliff_y[28] + 3), (30, 30), (31, 41), (36, 43)], 1)           # west stairs -> smithy
    path([(30, 45), (31, 56), (31, 68)], 2)                                  # to the beach stairs
    path([(31, 71), (25, 74), (20, 75)], 1)                                  # beach path
    path([(8, 45), (8, 50)], 1)                                              # field track
    path([(104, 45), (104, 52), (108, 52)], 1)                                          # to Gideon's home
    path([(121, 45), (128, 41), (134, 35), (137, 27)], 1)                    # old farm track
    path([(128, 41), (130, 52), (132, 62), (134, 70)], 1)                    # down to the wreck coast
    path([(84, 44), (85, 52), (85, 59)], 1)                                  # to the warehouse
    fill(52, 34, 72, 46, "p")                                                # market square
    mn = value_noise(H, W, 6, 91)                                            # meadow colour patches
    for y in range(24, 70):
        for x in range(0, 117):
            if g[y, x] == "." and mn[y, x] > 0.62:
                g[y, x] = "h"
    fill(46, 60, 104, 62, "k")                                               # harbour promenade
    for y in range(50, 63):                                                  # west fields
        for x in range(3, 25):
            if g[y, x] == ".":
                g[y, x] = "f"
    tn = value_noise(H, W, 4, 77)
    for y in range(12, 44):                                                  # overgrown farm
        for x in range(121, 149):
            if g[y, x] == "h" and tn[y, x] > 0.32:
                g[y, x] = "g"
    # docks
    fill(61, 63, 62, 81, "d")
    fill(61, 72, 86, 73, "d")
    fill(85, 63, 86, 81, "d")
    fill(98, 63, 99, 74, "d")
    fill(19, 74, 20, 81, "d")


def build_interiors():
    def room(x0, y0, x1, y1, floor, face, door_x):
        fill(x0, y0, x1, y1, "W")
        fill(x0 + 1, y0 + 1, x1 - 1, y0 + 2, face)
        fill(x0 + 1, y0 + 3, x1 - 1, y1 - 1, floor)
        g[y1, door_x] = "D"
        g[y1, door_x + 1] = "D"

    room(121 + IX, 2, 134 + IX, 12, "o", "V", 127 + IX)      # Ashford home
    room(138 + IX, 2, 155 + IX, 14, "o", "Y", 146 + IX)      # inn
    room(121 + IX, 16, 138 + IX, 27, "c", "Y", 129 + IX)     # Elias' study
    room(142 + IX, 17, 153 + IX, 26, "O", "U", 147 + IX)     # abandoned farmhouse
    room(121 + IX, 31, 138 + IX, 43, "O", "U", 129 + IX)     # barn


# ---------------------------------------------------------------- objects
def build_objects():
    # mountains (backdrop) and the waterfall
    x, i = -60, 0
    while x < 150 * TS - 40:
        name = "mountain_a" if i % 2 == 0 else "mountain_b"
        last = x + SPR[name]["w"] > 152 * TS
        if last:
            x = 152 * TS - SPR[name]["w"]
        place(name, 0, 0, px=x, py=-34 - (i % 3) * 10, reserve=False)
        if last:
            break
        x += SPR[name]["w"] - 90 - (i % 2) * 30
        i += 1
    place("waterfall", 40, cliff_y[40] - 2, px=-2, py=-4, reserve=False, interact="paint_waterfall")
    tspot("paint_waterfall", 45, cliff_y[40] + 5, "left")
    interact("paint_waterfall", 43, cliff_y[40] + 3, 3, 4)

    # --- the church beside the market square, with its small graveyard ---
    building("church", 52, 25, "spawn_church_none", door_id="door_church")
    for (gx, gy) in ((45, 27), (47, 27), (49, 27), (45, 30), (47, 30), (49, 30)):
        place("grave" if (gx + gy) % 2 else "gravestone", gx, gy, px=3)
    for fx in range(44, 51):
        place("fence", fx, 32)
    place("fence_post", 44, 26); place("fence_post", 50, 26)
    interact("graves", 44, 26, 7, 6)
    interact("paint_church", 58, 35, 3, 2)
    # --- plateau: herbalist, hill bench ---
    building("turf_house", 15, 12, "herbalist_closed", door_id="door_astrid")
    place("garden", 21, 13, reserve=False)
    place("bench", 76, 16, interact="paint_hills_view")
    tspot("paint_hills", 77, 17.5, "up")
    building("house_white_gable", 70, 7)
    place("rock_snow", 34, 9); place("rock_big", 82, 11)

    # --- Elias' estate on its terrace ---
    building("manor", 94, 9, "spawn_study_in", door_id="door_manor")
    building("stable", 107, 18)
    place("estate_gate", 99, cliff_y[100] - 3, px=-4, reserve=False)
    for ly in (19, 23, 27):
        place("lamp", 98, ly, px=6, py=-14)
        place("lamp", 102, ly, px=6, py=-14)
    for fx in list(range(89, 99)) + list(range(103, 116)):
        place("fence", fx, cliff_y[fx] - 1 if fx < 118 else 28)
    for (bx, by) in ((91, 19), (91, 23), (95, 21), (96, 25), (106, 25), (110, 25), (114, 25)):
        place("bush_berry" if (bx + by) % 3 == 0 else "bush", bx, by)
    for (fx, fy) in ((97, 19), (99, 22), (104, 19), (106, 22), (102, 24), (93, 26), (110, 26)):
        place("flowers_b" if fx % 2 else "flowers_a", fx, fy, reserve=False)
    place("well", 104, 22, interact="estate_fountain")
    interact("estate_garden", 93, 21, 4, 3)
    place("carriage", 103, 20, oid="carriage_estate", show_if=["ch3", "!elias_fled"])

    # --- village houses ---
    building("house_red_gable", 20, 25)
    building("house_blue_gable", 66, 26, "runa_closed", door_id="door_runa")
    building("house_redyellow", 76, 24)
    building("smithy", 33, 35)
    building("shop", 74, 35, "shop_closed", door_id="door_shop")
    building("boathouse", 100, 56)
    building("house_green", 86, 34)
    building("house_white", 104, 33)
    building("house_yellow", 43, 47)
    building("house_green_gable", 23, 46)
    building("house_white_gable", 76, 48)
    building("house_blue", 94, 46)
    building("house_red_small", 5, 30)
    building("house_blue", 44, 36)
    building("house_red_gable", 11, 24)
    building("turf_house", 25, 57)
    building("house_red", 52, 48)
    place("garden", 82, 46, reserve=False)
    building("shed", 14, 45)
    building("shed_red", 20, 37)
    building("turf_house_b", 49, 54, "bjorn_closed", door_id="door_bjorn")
    building("inn", 64, 52, "spawn_inn_in", door_id="door_inn")
    building("warehouse", 87, 53, "warehouse_closed", door_id="door_warehouse")
    building("house_gideon", 106, 47, "spawn_home_in", door_id="door_home", show_if=["!roof_fixed"])
    building("house_gideon_repaired", 106, 47, show_if=["roof_fixed", "!ending"])
    building("house_gideon_fixed", 106, 47, show_if=["ending"])
    building("farmhouse", 125, 30, "spawn_farmhouse_in", door_id="door_farmhouse", smoke=False)
    building("barn", 134, 17, "spawn_barn_in", door_id="door_barn", smoke=False)
    place("mine_entrance", 11, 67, interact="mine")

    # gardens, laundry lines and little fences around houses
    place("garden", 50, 28, reserve=False); place("garden", 28, 26, reserve=False)
    place("garden", 81, 37, reserve=False); place("garden", 99, 47, reserve=False)
    place("laundry", 49, 47); place("laundry", 82, 30); place("laundry", 110, 52)
    for fx in range(26, 30):
        place("fence", fx, 30)
    for fx in range(80, 84):
        place("fence", fx, 40)

    # --- market square ---
    place("monument", 57, 38, px=-2, interact="monument")
    place("well", 67, 38)
    place("stall_red", 53, 35, interact="stall_fish")
    place("stall_blue", 69, 35, interact="stall_bread")
    place("stall_green", 69, 42)
    place("cart", 53, 41, oid="henrik_cart", interact="henrik_cart")
    for (lx, ly) in ((52, 37), (72, 37), (59, 46), (64, 46), (60, 33), (100, 42), (68, 59), (62, 58), (90, 43), (112, 43), (32, 43)):
        place("lamp", lx, ly, px=3, py=-14)
    place("bench", 63, 35, px=0)
    place("bench_coat", 64, 45, oid="coat_bench", show_if=["ch2", "!got_key"], interact="elias_coat")
    place("bench", 64, 45, show_if=["!ch2"])
    place("bench", 64, 45, show_if=["got_key"])
    place("carriage", 66, 40, oid="carriage_square", show_if=["ch2", "!ch3"])
    place("barrel", 72, 44); place("crates", 52, 44); place("barrel", 71, 34)

    # --- harbour ---
    place("fishing_boat", 63, 64, px=6, py=-6, reserve=False)
    place("trade_ship", 87, 66, px=4, py=-8, reserve=False)
    place("sailboat", 73, 74, px=0, py=2, reserve=False)
    place("sailboat", 100, 66, px=6, reserve=False)
    place("rowboat", 63, 68, px=2, py=2, reserve=False, interact="bjorn_boat")
    place("rowboat", 59, 77, reserve=False); place("rowboat", 83, 75, reserve=False)
    place("rowboat", 22, 76, px=2, reserve=False); place("rowboat", 14, 74, reserve=False)
    for (bx, by) in ((70, 69), (78, 77), (92, 70), (55, 72), (104, 72)):
        place("buoy", bx, by, reserve=False)
    for (px_, py_) in ((61, 81), (62, 81), (85, 81), (86, 81), (87, 72), (98, 74), (99, 74), (19, 81), (20, 81)):
        place("post", px_, py_, px=5, py=2, reserve=False)
    for (ix, iy) in ((36, 86), (112, 80), (140, 86), (128, 90)):
        place("islet", ix, iy, reserve=False)
    place("net_rack", 46, 58); place("net_rack", 76, 59)
    place("fish_rack", 56, 57); place("fish_rack", 82, 57)
    place("lobster_pot", 58, 60, reserve=False); place("lobster_pot", 59, 61, reserve=False)
    place("rope", 63, 63, reserve=False); place("rope", 84, 62, reserve=False)
    place("crates", 83, 59, interact="harbor_crates"); place("crate", 81, 60); place("barrel", 78, 61)
    place("barrel", 95, 60); place("crates", 95, 57, interact="warehouse_drop")
    interact("harbor_crates", 83, 59, 2, 2)
    interact("warehouse_drop", 94, 57, 3, 3)
    tspot("crate_pile", 84, 61)
    interact("fishing_spot", 61, 81, 2, 1)
    interact("fishing_spot", 85, 81, 2, 1)
    interact("fishing_spot", 98, 74, 2, 1)
    interact("paint_harbor", 61, 79, 2, 2)
    interact("bjorn_boat", 61, 68, 2, 2)

    # --- Gideon's yard ---
    place("woodpile", 101, 49, interact="woodpile")
    place("chopping_block", 103, 52, interact="chop_wood")
    place("fence_broken", 111, 50, oid="broken_fence", show_if=["!fence_fixed"], interact="broken_fence")
    place("fence", 111, 50, show_if=["fence_fixed"])
    for fx in (112, 113):
        place("fence", fx, 50)
    place("fence_post", 114, 50, px=2)
    place("barrel", 105, 51, px=-4)
    tspot("home_yard", 109.5, 55)

    # --- smithy ---
    place("anvil", 39, 39, interact="anvil")
    place("barrel", 32, 39)

    # --- herbs ---
    herb_spots = [(12, 18), (22, 20), (8, 14), (33, 15), (48, 12), (80, 13), (26, 40), (124, 50), (140, 46), (128, 12)]
    for i, (hx, hy) in enumerate(herb_spots):
        hx, hy = nearest_walkable(hx, hy)
        place("herb", hx, hy, oid=f"herb_{i}", interact=f"herb_{i}", show_if=[f"!d_herb_{i}"])

    # --- west farm & paddock ---
    for fx in range(2, 20):
        place("fence", fx, 36)
        place("fence", fx, 42)
    for fx in range(2, 25):
        place("fence", fx, 49)
    place("haystack", 16, 38)
    for (sx_, sy_) in ((5, 38), (9, 39), (12, 38)):
        place("sheep", sx_, sy_, oid=f"sheep_{sx_}", interact="sheep", reserve=False, extra={"wander": 24})
    place("horse", 7, 40, interact="horse", reserve=False, extra={"wander": 14})
    place("sign", 1, 42, interact="sign_west")

    # --- east: gate, farm, barn, wreck ---
    place("gate", 115, 44, oid="bridge_gate_a", show_if=["!bridge_open"], interact="bridge_gate", py=-6,
          extra={"block": [0, 0, 16, 32]})
    place("footprints", 133, 26, oid="footprints", reserve=False, interact="footprints")
    place("fence_broken", 124, 28); place("fence_post", 127, 28); place("fence_broken", 130, 28)
    place("iron_chest", 143, 24, oid="iron_chest", show_if=["q_smith_started", "!got_iron_tools"], interact="iron_chest")
    place("haystack", 143, 20); place("shed", 144, 30)
    place("rock_big", 122, 14); place("rock_big", 146, 38)
    place("wreck", 131, 72, interact="wreck")
    place("debris", 127, 74, reserve=False); place("debris", 140, 75, reserve=False)
    interact("barn_window", 134, 24, 2, 2)
    place("smoke", 125, 27, oid="farm_smoke", show_if=["ch3", "!ending"], reserve=False, px=8 + 54, py=-6)

    # --- interiors (same furniture as before, shifted to the interior block) ---
    place("bed_patched", 122 + IX, 5, interact="gideon_bed", show_if=["!debts_paid"])
    place("bed", 122 + IX, 5, interact="gideon_bed", show_if=["debts_paid"])
    place("wall_map", 124 + IX, 2, reserve=False, py=12, show_if=["debts_paid"])
    place("lantern_prop", 129 + IX, 8, reserve=False, py=-2, show_if=["debts_paid"])
    place("rug", 125 + IX, 8, reserve=False, show_if=["debts_paid", "!home_rug"], px=8, py=8)
    place("bed", 132 + IX, 5, px=2)
    place("fireplace", 126 + IX, 3, py=4)
    place("table_meal", 128 + IX, 8, interact="home_table")
    place("chair", 127 + IX, 8, px=6, py=6); place("chair", 130 + IX, 8, px=6, py=6)
    place("sewing_table", 122 + IX, 9, px=2)
    place("easel", 131 + IX, 9, interact="clara_easel")
    place("bucket", 125 + IX, 6, oid="leak_bucket", show_if=["!roof_fixed"], interact="leak_bucket")
    place("wall_window", 123 + IX, 2, reserve=False, py=8); place("wall_window", 132 + IX, 2, reserve=False, py=8)
    place("wardrobe", 133 + IX, 9, px=4)
    place("rug", 125 + IX, 8, reserve=False, show_if=["home_rug"], px=8, py=8)
    for i in range(3):
        place("wall_painting", 129 + i + IX, 2, oid=f"home_painting_{i}", reserve=False, py=10, show_if=[f"painting_{i + 1}"])
    interact("gideon_bed", 122 + IX, 5, 1, 2)
    place("counter", 140 + IX, 5, px=4, py=6)
    place("fireplace", 151 + IX, 3, py=4)
    for (tx, ty) in ((141 + IX, 9), (148 + IX, 9)):
        place("table", tx, ty, interact="inn_table")
        place("chair", tx - 1, ty, px=6, py=4); place("chair", tx + 2, ty, px=4, py=4)
    place("barrel", 153 + IX, 6); place("barrel", 153 + IX, 8)
    place("wall_painting", 144 + IX, 2, reserve=False, py=10)
    place("wall_window", 141 + IX, 2, reserve=False, py=8); place("wall_window", 149 + IX, 2, reserve=False, py=8)
    place("bookshelf", 122 + IX, 17, py=8); place("bookshelf", 124 + IX, 17, py=8, px=4); place("bookshelf", 135 + IX, 17, py=8)
    place("desk", 128 + IX, 20, interact="study_desk")
    place("chair", 129 + IX, 22, px=2)
    place("cabinet", 132 + IX, 17, py=8, oid="cabinet_locked", show_if=["!cabinet_open"], interact="study_cabinet")
    place("cabinet_open", 132 + IX, 17, py=8, show_if=["cabinet_open"], interact="study_cabinet")
    place("wall_map", 126 + IX, 17, reserve=False, interact="study_map", py=10)
    place("rug", 127 + IX, 23, reserve=False)
    place("fireplace", 136 + IX, 22)
    place("bed_fancy", 122 + IX, 23)
    place("lantern_prop", 133 + IX, 21, reserve=False)
    place("table", 144 + IX, 20); place("old_chair", 143 + IX, 21); place("old_chair", 147 + IX, 20, px=4)
    place("floorboard", 150 + IX, 22, interact="floorboard", reserve=False)
    place("bed_patched", 151 + IX, 19, px=2)
    place("bucket", 143 + IX, 24)
    place("papers", 145 + IX, 24, reserve=False, interact="farm_papers")
    place("hay_pile", 122 + IX, 34); place("hay_pile", 135 + IX, 34, px=4); place("hay_pile", 134 + IX, 39)
    place("fireplace", 126 + IX, 32, py=4)
    place("old_chair", 128 + IX, 36, px=4)
    place("table", 130 + IX, 36)
    place("wood_box", 131 + IX, 35, px=4, py=-4, show_if=["ch5", "!got_box"], interact="edmund_box")
    place("crates", 123 + IX, 39); place("barrel", 136 + IX, 41, px=-2); place("lantern_prop", 133 + IX, 36, reserve=False)
    place("old_chair", 125 + IX, 40)

    def exit_door(did, tx, ty, to):
        objects.append({"type": "door", "id": did, "to": to, "x": tx * TS + 2, "y": ty * TS + 4, "w": 28, "h": 12})

    exit_door("exit_home", 127 + IX, 12, "spawn_home_out")
    exit_door("exit_inn", 146 + IX, 14, "spawn_inn_out")
    exit_door("exit_study", 129 + IX, 27, "spawn_manor_out")
    exit_door("exit_farmhouse", 147 + IX, 26, "spawn_farmhouse_out")
    exit_door("exit_barn", 129 + IX, 43, "spawn_barn_out")
    tspot("spawn_home_in", 127.5 + IX, 11, "up")
    tspot("spawn_inn_in", 146.5 + IX, 13, "up")
    tspot("spawn_study_in", 129.5 + IX, 26, "up")
    tspot("spawn_farmhouse_in", 147.5 + IX, 25, "up")
    tspot("spawn_barn_in", 129.5 + IX, 42, "up")
    tspot("game_start", 123.5 + IX, 7.5, "down")


def doors_out():
    for o in objects:
        if o.get("type") == "door" and o["id"].startswith("door_"):
            spot(f"spawn_{o['id'][5:]}_out", o["x"] + 8, o["y"] + 26, "down")


def npc_spots():
    t = tspot
    t("margaret_home", 124.5 + IX, 9.5, "right"); t("clara_home", 131 + IX, 10.5, "left")
    t("edmund_home", 127.5 + IX, 5.5, "down")
    t("sigrid_inn", 143 + IX, 5, "down")
    t("elias_study", 130 + IX, 21, "down"); t("edmund_barn", 129 + IX, 36.5, "left")
    t("study_desk_spot", 127.5 + IX, 22, "up"); t("cabinet_spot", 133 + IX, 20.6, "up")
    t("floorboard_spot", 150.5 + IX, 22.5, "down"); t("bed", 123.5 + IX, 7.5, "left")
    # village
    t("bjorn_dock", 61.5, 66, "down"); t("bjorn_harbor", 70, 61, "left")
    t("bjorn_boat_spot", 61.5, 69, "right")
    t("leif_smithy", 37, 41, "left"); t("astrid_cottage", 19, 18.5, "down")
    t("einar_church", 57.5, 35.5, "down"); t("runa_house", 69, 33, "down")
    t("henrik_cart", 57, 42.5, "left"); t("jonas_harbor", 56, 62, "right"); t("jonas_square", 65, 37, "left")
    t("halldor_estate", 102, 19.5, "down"); t("gunnar_field", 12, 44, "down"); t("olafur_road", 2, 43.5, "right")
    t("elias_square", 65, 43, "left"); t("elias_estate", 99, 19.5, "down")
    t("clara_square", 60, 36.5, "down"); t("clara_paint", 61.5, 75, "down"); t("margaret_shop", 55, 40, "right")
    t("woodpile_spot", 102.5, 51.5, "up"); t("fence_spot", 111.5, 51.6, "up"); t("coat_spot", 64.5, 46.4, "up")
    t("ending_view", 108.5, 55, "up"); t("church_door", 55, 34.5, "up")
    # the east and the night chase
    t("worker_a", 132.5, 27, "right"); t("worker_b", 133, 29, "right")
    t("elias_farm", 135, 27.5, "right"); t("edmund_farm", 140.5, 26.5, "left")
    t("gideon_farm", 138.5, 28.5, "left"); t("jonas_farm", 136, 30, "up")
    t("follow_start", 110, 45, "right")
    t("elias_walk_0", 114, 44.5, "right"); t("elias_walk_1", 122, 44.5, "right"); t("elias_walk_2", 128, 41, "right")
    t("elias_walk_3", 134, 35, "up"); t("elias_walk_4", 137.5, 25.5, "up")
    t("barn_window", 134.5, 26, "up")
    # nudge every outdoor spot onto a walkable tile
    for name, s in spots.items():
        tx, ty = s["x"] // TS, s["y"] // TS
        if not walkable(tx, ty):
            nx, ny = nearest_walkable(tx, ty, avoid_occupied=False)
            print(f"note: moved spot {name} from {tx},{ty} to {nx},{ny}")
            s["x"], s["y"] = nx * TS + 8, ny * TS + 8


def build_zones():
    zone("home_in", "منزل آل آشفورد", 121 + IX, 2, 134 + IX, 12, indoor=True, music="melancholy")
    zone("inn_in", "نُزل سيغريد", 138 + IX, 2, 155 + IX, 14, indoor=True, music="inn")
    zone("study_in", "مكتب إلياس", 121 + IX, 16, 138 + IX, 27, indoor=True, music="estate")
    zone("farmhouse_in", "بيت المزرعة المهجور", 142 + IX, 17, 153 + IX, 26, indoor=True, music="mystery")
    zone("barn_in", "الحظيرة", 121 + IX, 31, 138 + IX, 43, indoor=True, music="mystery")
    zone("harbor", "الميناء", 46, 56, 116, 91)
    zone("church", "الكنيسة", 43, 22, 59, 33)
    zone("square", "ساحة القرية", 50, 32, 74, 48)
    zone("estate", "ضيعة إلياس", 88, 6, 117, 31, music="estate")

    zone("home", "منزل غيديون", 100, 45, 116, 56)
    zone("farm", "المزرعة المهجورة", 121, 12, 149, 36, music="mystery")
    zone("wreck", "حطام السفينة", 119, 60, 149, 91, music="mystery")
    zone("hills", "التلال الشرقية", 119, 0, 149, 91, music="mystery")
    zone("falls", "الشلال", 30, 5, 49, 32)
    zone("plateau", "المرتفعات الشمالية", 0, 5, 87, 23)
    zone("fields", "الحقول الغربية", 0, 24, 26, 64)
    zone("beach", "الشاطئ", 0, 65, 46, 91)
    zone("village", "هرافنفيك", 0, 0, 149, 99)


def scatter_decor():
    free = lambda x, y: g[y, x] in ".hg" and not occupied[y, x]

    def forest(x0, y0, x1, y1, density, kinds, step=2):
        for y in range(y0, y1 + 1, step):
            for x in range(x0, x1 + 1, step):
                xx, yy = x + rng.randrange(0, step), y + rng.randrange(0, step)
                if xx >= W or yy >= H or not free(xx, yy):
                    continue
                near = g[max(0, yy - 1):yy + 3, max(0, xx - 1):xx + 2]
                if np.isin(near, list("=pkbdsrSP#")).any():
                    continue
                if occupied[max(0, yy - 2):yy + 3, max(0, xx - 1):xx + 2].any():
                    continue
                if rng.random() < density:
                    k = rng.choice(kinds)
                    place(k, xx, yy, px=-8, py=-SPR[k]["oy"] + 14)
                    occupied[max(0, yy - 1):yy + 1, xx:xx + 2] = True
    pines = ["pine", "pine_dark", "pine"]
    forest(0, 6, 150, 10, 0.75, pines)                       # mountain foot
    forest(0, 11, 12, 22, 0.55, pines)
    forest(30, 11, 50, 18, 0.45, pines + ["pine_small"])
    forest(78, 6, 88, 21, 0.5, pines)
    forest(110, 6, 117, 30, 0.55, pines)
    forest(118, 6, 150, 13, 0.6, pines + ["pine_small"])
    forest(119, 44, 150, 60, 0.45, pines + ["pine_small", "oak"])
    forest(0, 24, 4, 36, 0.5, pines)
    forest(36, 24, 42, 34, 0.4, ["oak", "pine"])
    forest(26, 52, 40, 66, 0.35, ["oak", "pine_small", "pine"])
    forest(100, 56, 116, 62, 0.35, ["pine", "oak"])
    forest(84, 24, 92, 32, 0.25, ["oak"])
    forest(14, 26, 22, 35, 0.35, ["pine", "oak"])
    forest(88, 36, 99, 45, 0.3, ["oak", "pine"])
    forest(44, 24, 52, 35, 0.3, ["pine", "oak"])
    forest(74, 26, 86, 34, 0.25, ["oak"])
    forest(52, 6, 90, 21, 0.18, ["pine", "pine_small"])
    forest(0, 24, 116, 66, 0.12, ["pine", "oak", "pine_small", "pine_dark"], step=3)
    forest(0, 63, 40, 68, 0.3, ["pine_small", "oak"])
    # rocks along the cliff bases, bushes, flowers
    for x in range(0, 118):
        cy = cliff_y.get(x)
        if cy and rng.random() < 0.3 and free(x, cy + 3):
            place(rng.choice(["rock", "rock_big", "rock"]), x, cy + 3, py=-6)
        if cy and rng.random() < 0.25 and free(x, cy - 1):
            place(rng.choice(["rock", "bush"]), x, cy - 1, py=4)
    for _ in range(620):
        x, y = rng.randrange(0, 150), rng.randrange(6, 72)
        if not free(x, y):
            continue
        if np.isin(g[max(0, y - 1):y + 2, max(0, x - 1):x + 2], list("=pkbdS")).any():
            continue
        k = rng.random()
        if k < 0.22:
            place(rng.choice(["rock", "rock", "rock_big"]), x, y)
        elif k < 0.48:
            place(rng.choice(["bush", "bush_berry"]), x, y)
        else:
            place(rng.choice(["flowers_a", "flowers_b"]), x, y, reserve=False)
    shell_i = 0
    for _ in range(800):
        x, y = rng.randrange(0, 150), rng.randrange(60, 92)
        if g[y, x] == "s" and not occupied[y, x] and shell_i < 8:
            place("shell", x, y, oid=f"shell_{shell_i}", interact=f"shell_{shell_i}", show_if=[f"!shell_{shell_i}_taken"], px=3, py=4)
            shell_i += 1
            occupied[y, x] = True
    # sparkles on the water
    for _ in range(70):
        x, y = rng.randrange(0, 150), rng.randrange(64, 99)
        if g[y, x] == "~":
            place("sparkle", x, y, px=rng.randrange(0, 8), py=rng.randrange(0, 12), reserve=False)


def hidden_collectibles():
    coins = [(9, 15), (45, 21), (73, 30), (113, 40), (24, 57), (52, 12), (140, 50), (130, 25), (100, 59), (6, 46), (146, 14), (33, 74)]
    for k, (x, y) in enumerate(coins):
        x, y = nearest_walkable(x, y)
        place("coin_pickup", x, y, oid=f"coin_{k}", interact=f"coin_{k}", show_if=[f"!coin_{k}_taken"], reserve=False, px=3, py=3)
        occupied[y, x] = True
    for gid, (x, y) in {"lost_compass": (57, 62), "collect_letter_church": (51, 31),
                        "collect_journal_1": (145, 33), "collect_journal_2": (141, 74),
                        "collect_carving": (24, 19), "collect_fishing_gear": (24, 73),
                        "collect_property_farm": (152 + IX - 35 + 35, 24), "collect_photo_inn": (154 + IX, 12)}.items():
        if gid == "collect_property_farm":
            x = 152 + IX
        x, y = nearest_walkable(x, y)
        cond = [f"!{gid}_taken"] + (["got_detector"] if gid in ("collect_carving", "collect_fishing_gear") else [])
        place("glint", x, y, oid=gid, interact=gid, show_if=cond, reserve=False, px=2, py=2, extra={"glint": True})


def build(sprite_meta, out_root):
    SPR.update(sprite_meta)
    build_terrain()
    build_interiors()
    build_objects()
    doors_out()
    npc_spots()
    build_zones()
    hidden_collectibles()
    dress_buildings()
    scatter_decor()
    for name, s in spots.items():
        tx, ty = s["x"] // TS, s["y"] // TS
        if g[ty, tx] in BLOCKED:
            print("WARN spot on blocked tile:", name, tx, ty, g[ty, tx])
    with open(f"{out_root}/data/map.txt", "w") as f:
        f.write("\n".join("".join(r) for r in g))
    world = {"tile": TS, "width": W, "height": H, "blocked": "".join(sorted(BLOCKED)),
             "outdoor": [0, 0, OUT_W * TS, OUT_H * TS],
             "objects": objects, "spots": spots, "zones": zones}
    with open(f"{out_root}/data/world.json", "w") as f:
        json.dump(world, f, ensure_ascii=False, indent=0)
    ground, mask = paint(g, TS, CRISP)
    ground.save(f"{out_root}/assets/world/ground.png")
    mask.save(f"{out_root}/assets/world/water_mask.png")
    return world
