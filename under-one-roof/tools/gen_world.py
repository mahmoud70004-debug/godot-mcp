"""Builds the world of Hrafnvik, following the art reference (assets/reference/world_reference.jpg).

Layout (tiles, 16px; outdoor area 150 x 92):
  north      dense forest under the mountains; Elias' manor with fountain, pond and a
             gazebo garden (north-west); the waterfall where the eastern river begins
  centre     cobbled market square with the inn, Henrik's market, longhouses, the
             monument and stalls; church and graveyard, smithy; cobbled main street
  south      fishermen's quarter on the sand: weathered cabins, warehouse, boathouse,
             a T-shaped pier and a small pier with rowing boats; the open sea
  west       farm fields and paddock, the herbalist's thatched cottage in the woods,
             a river crossed by wooden bridges flowing into the bay, beach and old mine
  east       Gideon's worn cabin by the eastern river; gated bridge to the hills, the
             abandoned farmhouse and barn; the wreck on the eastern shore
  x >= 152   interiors (home, inn, study, farmhouse, barn)

Buildings, trees and boats are cut-outs from the reference (ref_*); props are painted.
Outputs data/map.txt, data/world.json and assets/world/ground_*.png chunks.

Terrain chars
  .  grass   h meadow   g tall grass   f farmland   =  dirt path   p cobbles   k stone path
  s  sand    b bridge   d pier         S stairs     ~  sea         r river     P pond
  ^  impassable forest  o/O/c/D floors V/U/Y/W walls X void
"""
import json
import random
import numpy as np
from paint_ground import paint, save_chunks, value_noise

TS = 16
W, H = 192, 100
OUT_W, OUT_H = 150, 92
IX = 35
BLOCKED = set("~rP#^WVUYX")
CRISP = set("bdoOcDVUYWXS")

g = np.full((H, W), ".", dtype="<U1")
rng = random.Random(1887)
objects = []
spots = {}
zones = []
occupied = np.zeros((H, W), dtype=bool)   # footprints (no decor here)
covered = np.zeros((H, W), dtype=bool)    # whole building sprites (no tree canopies here)
SPR = {}


# ---------------------------------------------------------------- helpers
def fill(x0, y0, x1, y1, ch):
    g[max(0, y0):y1 + 1, max(0, x0):x1 + 1] = ch


def disc(cx, cy, r, ch):
    for y in range(int(cy - r), int(cy + r) + 1):
        for x in range(int(cx - r), int(cx + r) + 1):
            if 0 <= x < W and 0 <= y < H and (x - cx) ** 2 + (y - cy) ** 2 <= r * r:
                g[y, x] = ch


def path(points, width, ch="="):
    """Paint a road; crossing a river or pond builds a wooden bridge."""
    for (x0, y0), (x1, y1) in zip(points, points[1:]):
        steps = int(max(abs(x1 - x0), abs(y1 - y0)) * 2 + 1)
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
                    elif cur in "bdS~^":
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


def _bases(m):
    if "bases" in m:
        return m["bases"]
    if "base" in m:
        return [m["base"]]
    return []


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
        rects = _bases(m) or [[0, int(m["oy"] * 0.6), m["w"], int(m["oy"] * 0.4)]]
        for (bx, by, bw, bh) in rects:
            x0, y0 = (o["x"] + bx) // TS, (o["y"] + by) // TS
            x1, y1 = (o["x"] + bx + bw - 1) // TS, (o["y"] + by + bh - 1) // TS
            occupied[max(0, y0):y1 + 1, max(0, x0):x1 + 1] = True
    return o


def at(sprite, cx, bottom, **kw):
    """Place a sprite by the centre of its footprint (tile x) and its ground line (tile y)."""
    m = SPR[sprite]
    return place(sprite, 0, 0, px=int(cx * TS - m["w"] / 2), py=int(bottom * TS - m["oy"]), **kw)


def building(sprite, cx, bottom, door_to=None, door_id=None, oid=None, show_if=None, smoke=False):
    o = at(sprite, cx, bottom, oid=oid, show_if=show_if)
    m = SPR[sprite]
    x0, y0 = o["x"] // TS, o["y"] // TS
    x1, y1 = (o["x"] + m["w"]) // TS, (o["y"] + m["oy"]) // TS
    covered[max(0, y0):y1 + 1, max(0, x0):x1 + 1] = True
    for (bx, by, bw, bh) in _bases(m):
        for y in range((o["y"] + by) // TS, (o["y"] + by + bh - 1) // TS + 1):
            for x in range((o["x"] + bx) // TS, (o["x"] + bx + bw - 1) // TS + 1):
                if g[y, x] in "=pkbdS":
                    print(f"WARN {sprite} footprint covers road {g[y, x]} at {x},{y}")
    if smoke and "smoke" in m:
        sx, sy = m["smoke"]
        place("smoke", 0, 0, px=o["x"] + sx - 6, py=o["y"] + sy - 22, reserve=False)
    if "door" in m:
        dx, dy = m["door"]
        door_tx, door_ty = (o["x"] + dx) // TS, (o["y"] + dy) // TS
        for k in range(0, 2):
            if g[door_ty + k, door_tx] in ".hg":
                g[door_ty + k, door_tx] = "k"
        if door_to:
            objects.append({"type": "door", "id": door_id, "to": door_to,
                            "x": o["x"] + dx - 8, "y": o["y"] + dy - 6, "w": 16, "h": 14})
        occupied[door_ty:door_ty + 2, door_tx] = True
    return o


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
    """Closest free tile, preferring tiles below (in front of) the original one."""
    for r in range(0, 8):
        ring = [(dx, dy) for dy in range(-r, r + 1) for dx in range(-r, r + 1)]
        ring.sort(key=lambda d: (abs(d[0]) + abs(d[1]), d[1] < 0, abs(d[0])))
        for dx, dy in ring:
            xx, yy = x + dx, y + dy
            if walkable(xx, yy) and not (avoid_occupied and occupied[yy, xx]):
                return xx, yy
    return x, y


# ---------------------------------------------------------------- terrain
RIVER_A = {}   # y -> x of the eastern river
RIVER_B = {}   # x -> y of the western river


def build_terrain():
    fill(0, 0, W - 1, H - 1, "X")
    fill(0, 0, 149, H - 1, ".")
    edge = noise1(150, 9, 1.4, 3)
    for x in range(150):
        fill(x, 0, x, int(2 + edge[x]), "^")
    # the sea
    coast = noise1(150, 7, 1.2, 5)
    for x in range(150):
        if x < 50:
            cy = 71 + coast[x]
        elif x < 58:
            cy = 71 - (x - 50) * 0.8 + coast[x] * 0.3
        elif x < 114:
            cy = 64.5 + coast[x] * 0.4
        elif x < 122:
            cy = 64.5 + (x - 114) * 1.4
        else:
            cy = 76 + coast[x]
        cy = int(cy)
        for y in range(cy, H):
            g[y, x] = "~"
        depth = 5 if (58 <= x < 114) else 4
        for y in range(cy - depth, cy):
            if g[y, x] in ".h":
                g[y, x] = "s"
    # eastern river from the waterfall pool down to the sea
    disc(117, 7, 2.6, "P")
    rx = noise1(H, 9, 0.9, 9)
    for y in range(8, H):
        x = int(116.5 + rx[y])
        if g[y, x] == "~":
            break
        RIVER_A[y] = x
        g[y, x] = "r"; g[y, x + 1] = "r"; g[y, x + 2] = "r"
    # western river: from the west edge, east through the woods, then south into the bay
    ry = noise1(150, 8, 1.1, 11)
    for x in range(0, 47):
        y = int(54 + ry[x])
        RIVER_B[x] = y
        for k in range(3):
            g[y + k, x] = "r"
    for y in range(int(54 + ry[46]), 72):
        x = 46 + int(min(4, max(0, (y - 54) * 0.35)))
        for k in range(3):
            if g[y, x + k] != "~":
                g[y, x + k] = "r"
    # the manor pond
    disc(25, 15, 3.2, "P")
    # roads ---------------------------------------------------------------
    fill(66, 25, 101, 37, "p")                                   # market square
    path([(84, 4), (84, 25)], 3, "p")                            # main street north
    path([(84, 37), (84, 59)], 3, "p")                           # main street to the harbour
    path([(0, 40), (30, 40), (52, 39), (66, 33)], 2)             # west road
    path([(40, 21), (40, 32), (44, 39)], 2, "k")                 # manor drive
    path([(101, 33), (113, 33), (121, 33)], 2)                   # east road + gated bridge
    path([(121, 33), (128, 31), (132, 26)], 1)                   # to the farmhouse
    path([(132, 26), (138, 22)], 1)                              # to the barn
    path([(124, 34), (126, 48), (128, 62), (130, 74)], 1)        # down to the wreck shore
    path([(24, 40), (24, 52), (23, 60), (18, 66)], 1)            # south across the river to the beach
    path([(15, 40), (15, 47)], 1)                                # to the herbalist
    path([(84, 13), (96, 10), (104, 8)], 1)                      # to the view bench
    path([(101, 30), (110, 40), (111, 48)], 1)                   # to Gideon's home
    path([(60, 48), (70, 47)], 1)                                # church path
    path([(117, 12), (116, 33)], 1)                              # river path to the waterfall
    for y in range(0, 92):                                       # don't let the river path flood bridges
        pass
    for y in range(36, 49):                                      # west fields
        for x in range(3, 22):
            if g[y, x] == "." and y not in (40, 41):
                g[y, x] = "f" if 42 <= y <= 48 else g[y, x]
    tn = value_noise(H, W, 4, 77)
    for y in range(12, 40):                                      # overgrown farm
        for x in range(120, 149):
            if g[y, x] == "." and tn[y, x] > 0.36:
                g[y, x] = "g"
    mn = value_noise(H, W, 7, 91)
    for y in range(4, 70):
        for x in range(0, 150):
            if g[y, x] == "." and mn[y, x] > 0.64:
                g[y, x] = "h"
    # piers (reference: a long jetty with a T-head and two side fingers)
    fill(86, 60, 87, 71, "d")
    fill(86, 69, 103, 70, "d")
    fill(102, 64, 103, 75, "d")
    fill(70, 61, 71, 66, "d")


def build_interiors():
    def room(x0, y0, x1, y1, floor, face, door_x):
        fill(x0, y0, x1, y1, "W")
        fill(x0 + 1, y0 + 1, x1 - 1, y0 + 2, face)
        fill(x0 + 1, y0 + 3, x1 - 1, y1 - 1, floor)
        g[y1, door_x] = "D"
        g[y1, door_x + 1] = "D"

    # cozy, compact rooms (outer wall incl.); the door is a gap in the bottom wall
    room(121 + IX, 2, 133 + IX, 11, "o", "V", 126 + IX)     # Ashford home
    room(138 + IX, 2, 152 + IX, 12, "o", "V", 144 + IX)     # Sigrid's inn
    room(121 + IX, 16, 133 + IX, 25, "c", "Y", 127 + IX)    # Elias' study
    room(142 + IX, 17, 151 + IX, 25, "O", "U", 146 + IX)    # the abandoned farmhouse
    room(121 + IX, 31, 134 + IX, 41, "O", "U", 127 + IX)    # the barn


# ---------------------------------------------------------------- objects
def build_objects():
    # --- Elias' estate (north-west): manor, fountain, pond, gazebo garden ---
    building("ref_manor", 40, 20, "spawn_study_in", door_id="door_manor", smoke=False)
    at("ref_fountain", 30, 22, interact="estate_fountain")
    building("ref_gazebo", 58, 15)
    place("garden", 54, 16, reserve=False); place("garden", 60, 16, reserve=False)
    interact("estate_garden", 53, 15, 4, 3)
    for (fx, fy) in ((50, 18), (63, 18), (52, 20), (61, 20)):
        place("flowers_a" if fx % 2 else "flowers_b", fx, fy, reserve=False)
    for fx in range(20, 37):
        place("fence", fx, 24)
    for fx in range(45, 66):
        place("fence", fx, 24)
    at("ref_carriage", 46, 23, oid="carriage_estate", show_if=["ch3", "!elias_fled"])
    for ly in (25, 29, 33):
        place("lamp", 38, ly, px=6, py=-14); place("lamp", 42, ly, px=6, py=-14)
    building("stable", 12, 22)

    # --- market square ---
    building("ref_inn", 75, 25, "spawn_inn_in", door_id="door_inn", smoke=True)
    building("ref_market", 92, 24, "shop_closed", door_id="door_shop")
    building("ref_longhouse", 99.5, 24)
    building("ref_longhouse_f", 92, 46)
    building("ref_cabin_d", 100, 46, "runa_closed", door_id="door_runa")
    building("church", 71, 47, "spawn_church_none", door_id="door_church")
    for (gx, gy) in ((61, 42), (63, 42), (65, 42), (61, 45), (63, 45), (65, 45)):
        place("grave" if (gx + gy) % 2 else "gravestone", gx, gy, px=3)
    interact("graves", 60, 41, 7, 6)
    interact("paint_church", 70, 48, 3, 2)
    building("smithy", 60, 31)
    place("anvil", 63, 31, interact="anvil")
    at("monument", 82, 31, interact="monument")
    at("well", 90, 31)
    place("stall_red", 68, 27, interact="stall_fish")
    place("stall_blue", 96, 27, interact="stall_bread")
    place("stall_green", 96, 33)
    place("cart", 69, 33, oid="henrik_cart", interact="henrik_cart")
    place("bench", 76, 34)
    place("bench_coat", 87, 35, oid="coat_bench", show_if=["ch2", "!got_key"], interact="elias_coat")
    place("bench", 87, 35, show_if=["!ch2"]); place("bench", 87, 35, show_if=["got_key"])
    at("ref_carriage", 78, 37, oid="carriage_square", show_if=["ch2", "!ch3"])
    for (lx, ly) in ((66, 25), (101, 25), (66, 37), (101, 37), (82, 47), (82, 55), (88, 59), (98, 59), (110, 34)):
        place("lamp", lx, ly, px=3, py=-14)
    for (bx, by) in ((72, 25), (79, 25), (86, 25), (95, 37), (67, 30)):
        place(rng.choice(["barrel", "crates", "crate"]), bx, by)

    # --- fishermen's quarter & harbour ---
    building("ref_cabin_c", 64, 61, "bjorn_closed", door_id="door_bjorn")
    building("ref_cabin_b_f", 76, 60)
    building("boathouse", 94, 60)
    building("warehouse", 108, 60, "warehouse_closed", door_id="door_warehouse")
    building("ref_cabin_d_f", 56, 52)
    building("ref_thatch_f", 64, 52)
    for (fx, fy) in ((72, 52), (79, 52), (98, 52), (105, 52)):
        place("laundry" if fx % 2 else "net_rack", fx, fy)
    place("net_rack", 80, 62); place("fish_rack", 59, 62); place("fish_rack", 99, 62)
    place("lobster_pot", 72, 63, reserve=False); place("lobster_pot", 73, 64, reserve=False)
    place("rope", 88, 62, reserve=False); place("rope", 101, 66, reserve=False)
    place("crates", 89, 61, interact="harbor_crates"); place("crate", 91, 62); place("barrel", 84, 62)
    place("barrel", 110, 62); place("crates", 112, 61, interact="warehouse_drop")
    interact("harbor_crates", 89, 61, 2, 2)
    interact("warehouse_drop", 111, 60, 3, 3)
    tspot("crate_pile", 90, 63)
    at("ref_boat_a", 74, 66, reserve=False)
    at("ref_boat_b", 90, 68, reserve=False)
    at("ref_boat_c", 97, 67, reserve=False)
    at("ref_boat_d", 99, 73, reserve=False)
    at("ref_boat_a_f", 107, 69, reserve=False)
    at("ref_boat_d_f", 64, 73, reserve=False)
    place("sailboat", 110, 72, reserve=False)
    at("ref_boat_c", 68, 64, reserve=False, interact="bjorn_boat")
    interact("bjorn_boat", 67, 62, 3, 2)
    for (bx, by) in ((80, 70), (94, 77), (112, 68), (60, 70)):
        place("buoy", bx, by, reserve=False)
    for (ix, iy) in ((36, 84), (120, 84), (140, 86), (70, 86)):
        place("islet", ix, iy, reserve=False)
    interact("fishing_spot", 86, 71, 2, 1)
    interact("fishing_spot", 102, 75, 2, 1)
    interact("fishing_spot", 70, 66, 2, 1)
    interact("paint_harbor", 94, 69, 3, 2)

    # --- Gideon's home on the eastern edge ---
    building("ref_cabin_a", 110, 50, "spawn_home_in", door_id="door_home", show_if=["!roof_fixed"])
    building("ref_cabin_warm", 110, 50, show_if=["roof_fixed", "!ending"])
    building("ref_cabin_c_f", 110, 50, show_if=["ending"])
    objects.append({"type": "door", "id": "door_home_fixed", "to": "spawn_home_in",
                    "x": objects[-1]["x"] + SPR["ref_cabin_c_f"]["door"][0] - 8,
                    "y": objects[-1]["y"] + SPR["ref_cabin_c_f"]["door"][1] - 6, "w": 16, "h": 14, "show_if": ["roof_fixed"]})
    place("woodpile", 104, 51, interact="woodpile")
    place("chopping_block", 105, 53, interact="chop_wood")
    place("fence_broken", 113, 52, oid="broken_fence", show_if=["!fence_fixed"], interact="broken_fence")
    place("fence", 113, 52, show_if=["fence_fixed"])
    place("fence", 114, 52)
    place("barrel", 107, 51, px=-4)
    tspot("home_yard", 108.5, 54)

    # --- west: farm fields, paddock, herbalist ---
    for fx in range(2, 22):
        place("fence", fx, 34)
    for fx in range(2, 22):
        place("fence", fx, 49)
    place("haystack", 18, 36)
    for (sx_, sy_) in ((5, 36), (9, 37), (12, 36)):
        place("sheep", sx_, sy_, oid=f"sheep_{sx_}", interact="sheep", reserve=False, extra={"wander": 24})
    place("horse", 7, 37, interact="horse", reserve=False, extra={"wander": 14})
    place("sign", 1, 41, interact="sign_west")
    building("ref_thatch", 15, 50, "herbalist_closed", door_id="door_astrid")
    place("garden", 19, 47, reserve=False)
    building("ref_cabin_b", 30, 36)
    building("shed", 8, 31)

    # --- beach & old mine south of the river ---
    place("mine_entrance", 6, 59, interact="mine")
    at("ref_ruin", 34, 62, interact="ruins")
    place("rowboat", 26, 70, reserve=False); place("rowboat", 10, 69, reserve=False)

    # --- the waterfall and the view bench (north) ---
    place("waterfall", 116, 1, px=2, reserve=False)
    interact("paint_waterfall", 114, 8, 3, 3)
    tspot("paint_waterfall", 114, 10, "right")
    place("bench", 104, 7, interact="paint_hills_view")
    tspot("paint_hills", 105, 8.5, "up")

    # --- east: gate, farm, barn, wreck ---
    place("gate", 117, 33, oid="bridge_gate_a", show_if=["!bridge_open"], interact="bridge_gate", py=-6,
          extra={"block": [0, 0, 16, 32]})
    building("ref_cabin_old", 129, 27, "spawn_farmhouse_in", door_id="door_farmhouse")
    building("barn", 140, 21, "spawn_barn_in", door_id="door_barn")
    place("footprints", 137, 23, oid="footprints", reserve=False, interact="footprints")
    place("fence_broken", 125, 30); place("fence_post", 128, 30); place("fence_broken", 133, 30)
    place("iron_chest", 145, 25, oid="iron_chest", show_if=["q_smith_started", "!got_iron_tools"], interact="iron_chest")
    place("haystack", 146, 18)
    at("ref_ruin", 146, 34)
    place("wreck", 128, 74, interact="wreck")
    place("debris", 124, 78, reserve=False); place("debris", 136, 79, reserve=False)
    interact("barn_window", 136, 18, 2, 3)
    place("smoke", 128, 18, oid="farm_smoke", show_if=["ch3", "!ending"], reserve=False, px=4, py=-6)

    # --- interiors: cozy Nordic homes (tools/gen_interiors.py props) ---
    def i(sprite, cx, bottom, **kw):
        kw.setdefault("reserve", False)
        return at(sprite, cx + IX, bottom, **kw)

    # the Ashford home: hearth at the heart, beds in the corners, kitchen by the door
    i("hearth", 127, 5.45)
    i("rug_fur", 127, 7.25)
    i("window_curtains", 123, 4.75)
    i("shelf_jars", 124.85, 4.6)
    i("lantern_wall", 125.25, 4.2, show_if=["debts_paid"])
    i("herbs_hanging", 129.3, 4.45, show_if=["!debts_paid"])
    i("wall_map", 129.3, 4.4, show_if=["debts_paid"])
    for k in range(3):
        i("wall_painting", 130.7 + k * 0.95, 4.2, oid=f"home_painting_{k}", show_if=[f"painting_{k + 1}"])
    i("bed_worn", 122.75, 7.15, interact="gideon_bed", show_if=["!debts_paid"])
    i("bed_quilt", 122.75, 7.15, interact="gideon_bed", show_if=["debts_paid"])
    i("cupboard", 130.2, 6.1)
    i("bed_quilt_red", 132.2, 7.4)
    i("kitchen_counter", 123.3, 10.15)
    i("rug_round", 127.6, 10.0)
    i("table_feast", 127.6, 9.45, interact="home_table")
    i("stool", 129.45, 9.25)
    i("easel", 131.9, 10.0, interact="clara_easel")
    i("bucket", 125.2, 6.55, oid="leak_bucket", show_if=["!roof_fixed"], interact="leak_bucket")
    i("rug_long", 127.0, 11.0, show_if=["debts_paid", "!home_rug"])
    i("rug_long", 127.0, 11.0, show_if=["home_rug"])
    interact("gideon_bed", 122 + IX, 5, 2, 2)

    # Sigrid's inn: the bar, an open fire in the middle, long tables
    i("window_curtains", 140.3, 4.75); i("window_curtains", 150.8, 4.75)
    i("shelf_bottles", 142.6, 4.5); i("fish_trophy", 146.3, 4.0); i("net_hanging", 148.6, 4.85)
    i("lantern_wall", 144.5, 4.3); i("lantern_wall", 139.4, 4.3)
    i("kitchen_counter", 141.5, 6.65)
    i("barrel_stack", 140.1, 9.6)
    i("rug_round", 145.5, 9.4)
    i("firepit", 145.5, 8.6)
    i("table_inn", 149.2, 7.0, interact="inn_table"); i("bench_in", 149.2, 7.95)
    i("table_inn", 149.2, 10.3, interact="inn_table"); i("bench_in", 149.2, 11.25)
    i("table_feast", 141.9, 11.0, interact="inn_table")
    i("stool", 139.7, 10.85); i("plant_pot", 151.4, 11.8)

    # Elias' study: books, the locked cabinet, the desk under the map
    i("bookshelf_tall", 122.95, 19.65); i("bookshelf_tall", 124.85, 19.65); i("bookshelf_tall", 132.0, 19.65)
    i("wall_map", 126.8, 18.45, interact="study_map")
    i("window_curtains", 128.45, 18.75)
    i("cabinet", 130.05, 19.95, oid="cabinet_locked", show_if=["!cabinet_open"], interact="study_cabinet")
    i("cabinet_open", 130.05, 19.95, show_if=["cabinet_open"], interact="study_cabinet")
    i("rug_long", 127.5, 23.6)
    i("desk", 127.5, 21.55, interact="study_desk")
    i("globe", 123.0, 22.6); i("armchair", 124.7, 24.3); i("candlestick", 132.4, 22.0); i("plant_pot", 132.4, 24.7)
    i("lantern_wall", 133.4 - 0.9, 18.2)

    # the abandoned farmhouse: dust, cobwebs, a broken household
    i("cobweb", 143.5, 18.95); i("cobweb", 150.5, 18.95)
    i("shelf_jars", 147.0, 18.8)
    i("table_old", 145.0, 21.9); i("old_chair", 143.5, 22.6); i("old_chair", 146.7, 21.2)
    i("bed_worn", 149.8, 22.3)
    i("floorboard", 149.0, 24.25, interact="floorboard")
    i("bucket", 143.6, 24.5)
    i("papers", 145.3, 24.0, interact="farm_papers")
    i("crate", 150.4, 24.75)

    # the barn: hay and stalls, and Edmund's hidden corner by the stove
    i("lantern_wall", 124.2, 33.6); i("lantern_wall", 131.6, 33.6)
    i("herbs_hanging", 128.2, 33.45); i("net_hanging", 126.0, 33.9)
    i("hay_pile", 123.2, 35.6); i("hay_pile", 132.7, 35.6); i("hay_pile", 132.7, 38.7)
    i("stall_fence", 131.2, 37.0)
    i("iron_stove", 124.0, 36.3)
    i("bedroll", 123.1, 40.0)
    i("table_old", 127.6, 37.45)
    i("stool", 125.8, 37.3); i("stool", 129.4, 37.3)
    i("candlestick", 126.6, 36.4)
    i("wood_box", 128.6, 36.7, show_if=["ch5", "!got_box"], interact="edmund_box")
    i("crates", 122.8, 40.75); i("barrel_stack", 132.4, 40.8); i("firewood_in", 124.8, 40.8)

    def exit_door(did, tx, ty, to):
        objects.append({"type": "door", "id": did, "to": to, "x": tx * TS + 2, "y": ty * TS + 4, "w": 28, "h": 12})

    exit_door("exit_home", 126 + IX, 11, "spawn_home_out")
    exit_door("exit_inn", 144 + IX, 12, "spawn_inn_out")
    exit_door("exit_study", 127 + IX, 25, "spawn_manor_out")
    exit_door("exit_farmhouse", 146 + IX, 25, "spawn_farmhouse_out")
    exit_door("exit_barn", 127 + IX, 41, "spawn_barn_out")
    tspot("spawn_home_in", 127.0 + IX, 10.35, "up")
    tspot("spawn_inn_in", 145.0 + IX, 11.4, "up")
    tspot("spawn_study_in", 128.0 + IX, 24.4, "up")
    tspot("spawn_farmhouse_in", 147.0 + IX, 24.4, "up")
    tspot("spawn_barn_in", 128.0 + IX, 40.4, "up")
    tspot("game_start", 124.1 + IX, 7.2, "down")


def doors_out():
    for o in objects:
        if o.get("type") == "door" and o["id"].startswith("door_") and not o["id"].endswith("_fixed"):
            spot(f"spawn_{o['id'][5:]}_out", o["x"] + 8, o["y"] + 26, "down")


def npc_spots():
    t = tspot
    t("margaret_home", 123.3 + IX, 8.75, "down"); t("clara_home", 130.6 + IX, 10.1, "right")
    t("edmund_home", 127.5 + IX, 6.9, "down")
    t("sigrid_inn", 141.5 + IX, 5.35, "down")
    t("elias_study", 129.0 + IX, 20.7, "down"); t("edmund_barn", 130.3 + IX, 37.7, "left")
    t("study_desk_spot", 127.5 + IX, 22.4, "up"); t("cabinet_spot", 130.0 + IX, 21.0, "up")
    t("floorboard_spot", 147.9 + IX, 24.0, "right"); t("bed", 124.1 + IX, 7.2, "left")
    # village
    t("bjorn_dock", 86.5, 66, "down"); t("bjorn_harbor", 82, 63, "left"); t("bjorn_boat_spot", 68, 63.5, "down")
    t("bjorn_inn_evening", 78, 27, "down")
    t("leif_smithy", 62, 32, "left"); t("astrid_cottage", 18, 51, "down"); t("astrid_herbs", 30, 46, "left")
    t("einar_church", 70, 48.5, "down"); t("runa_house", 100, 47.5, "down"); t("runa_square", 94, 30, "left")
    t("henrik_cart", 71, 34, "left"); t("jonas_harbor", 80, 63.5, "right"); t("jonas_square", 85, 29, "left")
    t("jonas_inn_evening", 73, 26.5, "right")
    t("halldor_estate", 44, 22.5, "down"); t("gunnar_field", 12, 41, "down"); t("olafur_road", 2, 40.5, "right")
    t("elias_square", 79, 35.5, "left"); t("elias_estate", 37, 22.5, "down")
    t("clara_square", 83, 33, "down"); t("clara_paint", 86.5, 68, "down"); t("margaret_shop", 90, 26, "down")
    t("woodpile_spot", 105.5, 52, "up"); t("fence_spot", 113.5, 53.6, "up"); t("coat_spot", 87.5, 36.4, "up")
    t("ending_view", 108.5, 54, "up"); t("church_door", 71, 48, "up")
    # the east and the night chase
    t("worker_a", 135.5, 26, "right"); t("worker_b", 136, 28, "right")
    t("elias_farm", 138, 26.5, "right"); t("edmund_farm", 142.5, 23, "left")
    t("gideon_farm", 141.5, 26.5, "left"); t("jonas_farm", 139, 28, "up")
    t("follow_start", 108, 37, "right")
    t("elias_walk_0", 112, 33.5, "right"); t("elias_walk_1", 122, 33.5, "right"); t("elias_walk_2", 128, 31.5, "right")
    t("elias_walk_3", 135, 24, "right"); t("elias_walk_4", 140, 22, "up")
    t("barn_window", 137, 21, "up")
    # ambient villagers' routines
    for name, (x, y) in {"amb_fish_1": (95, 62), "amb_fish_2": (60, 63), "amb_fish_3": (103, 73), "amb_fish_4": (77, 63),
                         "amb_farm_1": (10, 44), "amb_farm_2": (16, 38), "amb_trade_1": (93, 29), "amb_trade_2": (70, 30),
                         "amb_child_1": (80, 31), "amb_child_2": (58, 56), "amb_square_1": (88, 33), "amb_square_2": (74, 36),
                         "amb_inn_1": (70, 26.5), "amb_inn_2": (80, 26.5), "amb_road_1": (50, 40), "amb_road_2": (100, 34)}.items():
        t(name, x, y, "down")
    for name, s in spots.items():
        tx, ty = s["x"] // TS, s["y"] // TS
        exit_spot = name.startswith("spawn_") and name.endswith("_out")   # stands on the doorstep on purpose
        if not walkable(tx, ty) or (occupied[ty, tx] and tx < 150 and not exit_spot):
            nx, ny = nearest_walkable(tx, ty, avoid_occupied=tx < 150 and not exit_spot)
            print(f"note: moved spot {name} from {tx},{ty} to {nx},{ny}")
            s["x"], s["y"] = nx * TS + 8, ny * TS + 8


def build_zones():
    zone("home_in", "منزل آل آشفورد", 121 + IX, 2, 133 + IX, 11, indoor=True, music="melancholy")
    zone("inn_in", "نُزل سيغريد", 138 + IX, 2, 152 + IX, 12, indoor=True, music="inn")
    zone("study_in", "مكتب إلياس", 121 + IX, 16, 133 + IX, 25, indoor=True, music="estate")
    zone("farmhouse_in", "بيت المزرعة المهجور", 142 + IX, 17, 151 + IX, 25, indoor=True, music="mystery")
    zone("barn_in", "الحظيرة", 121 + IX, 31, 134 + IX, 41, indoor=True, music="mystery")
    zone("harbor", "الميناء", 52, 50, 116, 91)
    zone("church", "الكنيسة", 58, 38, 76, 49)
    zone("square", "ساحة القرية", 64, 12, 103, 38)
    zone("estate", "ضيعة إلياس", 18, 3, 66, 24, music="estate")
    zone("home", "منزل غيديون", 102, 40, 116, 56)
    zone("farm", "المزرعة المهجورة", 120, 10, 149, 38, music="mystery")
    zone("wreck", "حطام السفينة", 118, 60, 149, 91, music="mystery")
    zone("hills", "التلال الشرقية", 118, 0, 149, 91, music="mystery")
    zone("falls", "الشلال", 104, 0, 120, 14)
    zone("fields", "الحقول الغربية", 0, 25, 34, 52)
    zone("beach", "الشاطئ", 0, 53, 51, 91)
    zone("village", "هرافنفيك", 0, 0, 149, 99)


def scatter_trees():
    """Forests of reference oaks and firs. Trunks block movement; canopies never cover roofs."""
    oaks = ["ref_oak_a", "ref_oak_b", "ref_oak_c", "ref_oak_a_f", "ref_oak_b_f", "ref_oak_c_f"]
    pines = ["ref_pine_a", "ref_pine_b", "ref_pine_a_f", "ref_pine_b_f"]

    def can_tree(name, cx, by):
        m = SPR[name]
        x0 = int((cx * TS - m["w"] * 0.42) // TS)
        x1 = int((cx * TS + m["w"] * 0.42) // TS)
        y0 = int((by * TS - m["oy"] * 0.85) // TS)
        if not (-2 <= x0 and x1 < 152 and by >= 2 and by < H):
            return False
        if covered[max(0, y0):by + 1, max(0, x0):x1 + 1].any():
            return False
        tile = g[by, int(cx)]
        if tile not in ".hg^":
            return False
        near = g[max(0, by - 1):by + 2, max(0, int(cx) - 1):int(cx) + 2]
        if np.isin(near, list("=pkbdsSrP~")).any():
            return False
        if occupied[max(0, by - 1):by + 2, max(0, int(cx) - 1):int(cx) + 2].any():
            return False
        return True

    def forest(x0, y0, x1, y1, density, kinds, step):
        for y in range(y0, y1 + 1, step):
            for x in range(x0, x1 + 1, step):
                cx = x + rng.uniform(0, step)
                by = int(y + rng.uniform(0, step))
                if rng.random() > density:
                    continue
                name = rng.choice(kinds)
                if can_tree(name, cx, by):
                    at(name, cx, by + 0.6)
                    occupied[by, int(cx)] = True

    big = oaks * 2 + pines
    forest(0, 2, 149, 6, 1.0, big, 3)             # northern forest edge
    forest(0, 5, 149, 10, 0.9, big, 4)
    forest(0, 3, 18, 33, 0.9, big, 4)             # north-west woods
    forest(0, 50, 45, 70, 0.75, oaks + pines, 5)  # woods along the western river
    forest(26, 41, 58, 53, 0.55, oaks, 6)         # between the fields and the church
    forest(66, 3, 82, 13, 0.7, big, 5)
    forest(88, 3, 112, 12, 0.6, big, 5)
    forest(102, 13, 114, 31, 0.55, big, 5)        # east of the square
    forest(118, 2, 149, 12, 0.9, big, 4)          # eastern hills
    forest(118, 38, 149, 74, 0.85, big, 4)
    forest(142, 10, 149, 40, 0.9, big, 4)         # eastern forest wall
    forest(46, 49, 54, 62, 0.5, pines, 4)


def vegetable_gardens():
    """The reference's kitchen garden beside homes and farms (flat, walkable)."""
    m = SPR["ref_garden"]
    tw, th = int(np.ceil(m["w"] / TS)), int(np.ceil(m["h"] / TS))

    def fits(x0, y0):
        if x0 < 1 or y0 < 1 or x0 + tw + 1 >= 150 or y0 + th + 1 >= H:
            return False
        sl = (slice(y0 - 1, y0 + th + 1), slice(x0 - 1, x0 + tw + 1))
        return np.isin(g[sl], list(".hg")).all() and not covered[sl].any() and not occupied[sl].any()

    placed = 0
    for ax, ay in [(99, 52), (22, 49), (36, 36), (124, 34), (56, 48), (112, 44)]:
        spots_ = sorted(((dx, dy) for dx in range(-8, 9) for dy in range(-6, 7)), key=lambda d: abs(d[0]) + abs(d[1]))
        for dx, dy in spots_:
            x0, y0 = ax + dx - tw // 2, ay + dy - th
            if fits(x0, y0):
                at("ref_garden", x0 + tw / 2, y0 + th)
                occupied[y0:y0 + th, x0:x0 + tw] = True
                placed += 1
                break
        else:
            print(f"note: no room for a vegetable garden near {ax},{ay}")
    print(f"vegetable gardens: {placed}")


def scatter_decor():
    free = lambda x, y: g[y, x] in ".hg" and not occupied[y, x]
    for _ in range(700):
        x, y = rng.randrange(0, 150), rng.randrange(4, 76)
        if not free(x, y):
            continue
        if np.isin(g[max(0, y - 1):y + 2, max(0, x - 1):x + 2], list("=pkbdS")).any():
            continue
        k = rng.random()
        if k < 0.12:
            place(rng.choice(["rock", "rock", "rock_big"]), x, y)
        elif k < 0.3:
            place(rng.choice(["bush", "bush_berry"]), x, y)
        elif k < 0.36 and x < 118:
            at("ref_stump", x + 0.5, y + 0.8)
        else:
            place(rng.choice(["flowers_a", "flowers_b"]), x, y, reserve=False)
    shell_i = 0
    for _ in range(1500):
        x, y = rng.randrange(0, 150), rng.randrange(55, 92)
        if g[y, x] == "s" and not occupied[y, x] and shell_i < 8:
            place("shell", x, y, oid=f"shell_{shell_i}", interact=f"shell_{shell_i}", show_if=[f"!shell_{shell_i}_taken"], px=3, py=4)
            shell_i += 1
            occupied[y, x] = True


def village_polish():
    """Cobbled lanes in the village, harbour clutter, lamps, wildflowers, light snow, grass."""
    # lanes inside the village become laid stone; tracks out into the country stay dirt
    lanes = []
    for y in range(18, 64):
        for x in range(54, 116):
            if g[y, x] == "=":
                g[y, x] = "k"
                lanes.append((x, y))
    # classic lamps along the lanes, never too close to each other
    lit = []
    for (x, y) in lanes:
        if (x * 7 + y * 13) % 5:
            continue
        for (nx, ny) in ((x + 1, y), (x - 1, y), (x, y + 1)):
            if g[ny, nx] in ".hg" and not occupied[ny, nx] and not covered[ny, nx] \
                    and all(abs(nx - lx) + abs(ny - ly) > 9 for (lx, ly) in lit):
                place("lamp", nx, ny, px=3, py=-14)
                lit.append((nx, ny))
                break

    def sand_spot(cx, cy, w=3, h=2, r=5):
        for d in sorted(((dx, dy) for dx in range(-r, r + 1) for dy in range(-r, r + 1)), key=lambda q: abs(q[0]) + abs(q[1])):
            x0, y0 = cx + d[0], cy + d[1]
            area = g[y0:y0 + h, x0:x0 + w]
            if area.size == w * h and (area == "s").all() and not occupied[y0:y0 + h, x0:x0 + w].any():
                occupied[y0:y0 + h, x0:x0 + w] = True
                return x0, y0
        return None

    # nets drying by the piers, barrels and crates along the waterfront
    for (cx, cy) in ((84, 60), (100, 61), (68, 60), (93, 62), (61, 64)):
        p = sand_spot(cx, cy)
        if p:
            at("net_posts", p[0] + 1.3, p[1] + 1.8)
    for (cx, cy) in ((89, 63), (76, 61), (105, 62), (64, 62)):
        p = sand_spot(cx, cy, 2, 2)
        if p:
            at("barrel_stack", p[0] + 1, p[1] + 1.6)
    # life in the market square: planters and barrels, never on anyone's spot
    def clear_of_spots(x, y, r=1.8):
        return all(abs(sp["x"] / TS - x) > r or abs(sp["y"] / TS - y) > r for sp in spots.values())
    for (sprite, x, y) in (("plant_pot", 79.6, 31.2), ("plant_pot", 84.4, 31.2), ("plant_pot", 88.6, 32.0),
                           ("plant_pot", 91.4, 32.0), ("barrel_stack", 70.8, 27.6), ("barrel_stack", 97.6, 35.2),
                           ("plant_pot", 75.0, 36.4), ("plant_pot", 96.0, 26.4)):
        if g[int(y), int(x)] in "pk" and clear_of_spots(x, y):
            at(sprite, x, y)
            occupied[int(y), int(x)] = True
    # wear of the paths: pebbles along the edges, a few puddles reflecting the sky
    for _ in range(900):
        x, y = rng.randrange(0, 150), rng.randrange(2, 80)
        if g[y, x] not in "=k" or occupied[y, x]:
            continue
        edge = np.isin(g[max(0, y - 1):y + 2, max(0, x - 1):x + 2], list(".hg")).any()
        r = rng.random()
        if edge and r < 0.35:
            at(f"pebbles_{rng.randrange(3)}", x + rng.random(), y + rng.random(), reserve=False)
        elif g[y, x] == "=" and r < 0.06:
            at(f"puddle_{rng.randrange(2)}", x + 0.5, y + 0.8, reserve=False)
    # nature: tufts around trunks and along lanes, wildflowers, a dusting of old snow
    trees = [o for o in objects if SPR.get(o.get("sprite", ""), {}).get("tree")]
    for o in trees:
        m = SPR[o["sprite"]]
        bx, by = (o["x"] + m["w"] * 0.5) / TS, (o["y"] + m["oy"]) / TS
        for k in range(rng.randrange(2, 5)):
            x, y = bx + rng.uniform(-2.2, 2.2), by + rng.uniform(-0.2, 1.4)
            tx, ty = int(x), int(y)
            if 0 <= tx < 150 and 0 <= ty < H and g[ty, tx] in ".hg":
                at(f"grass_tuft_{rng.randrange(3)}", x, y, reserve=False)
    for _ in range(1400):
        x, y = rng.randrange(0, 150), rng.randrange(2, 80)
        if g[y, x] not in ".hg" or occupied[y, x] or covered[y, x]:
            continue
        near_lane = np.isin(g[max(0, y - 1):y + 2, max(0, x - 1):x + 2], list("=kp")).any()
        r = rng.random()
        if near_lane and r < 0.5:
            at(f"grass_tuft_{rng.randrange(3)}", x + rng.random(), y + rng.random(), reserve=False)
        elif r < 0.16:
            at(f"wildflowers_{rng.randrange(3)}", x + rng.random(), y + rng.random(), reserve=False)
        elif r < 0.30:
            at(f"grass_tuft_{rng.randrange(3)}", x + rng.random(), y + rng.random(), reserve=False)
        elif r < 0.30 + (0.08 if y < 20 else 0.025):
            place(f"snow_{rng.randrange(3)}", x, y, reserve=False, px=rng.randrange(-6, 6), py=rng.randrange(-4, 4))


def hidden_collectibles():
    coins = [(9, 15), (45, 30), (73, 40), (113, 40), (24, 57), (52, 12), (140, 50), (130, 20), (100, 57), (6, 46), (146, 14), (33, 66)]
    for k, (x, y) in enumerate(coins):
        x, y = nearest_walkable(x, y)
        place("coin_pickup", x, y, oid=f"coin_{k}", interact=f"coin_{k}", show_if=[f"!coin_{k}_taken"], reserve=False, px=3, py=3)
        occupied[y, x] = True
    herb_spots = [(12, 26), (22, 30), (8, 18), (33, 45), (48, 28), (80, 10), (26, 44), (124, 50), (140, 46), (128, 12)]
    for i, (hx, hy) in enumerate(herb_spots):
        hx, hy = nearest_walkable(hx, hy)
        place("herb", hx, hy, oid=f"herb_{i}", interact=f"herb_{i}", show_if=[f"!d_herb_{i}"])
    for gid, (x, y) in {"lost_compass": (72, 64), "collect_letter_church": (66, 46),
                        "collect_journal_1": (145, 30), "collect_journal_2": (138, 76),
                        "collect_carving": (28, 30), "collect_fishing_gear": (40, 68),
                        "collect_property_farm": (150 + IX, 24), "collect_photo_inn": (151 + IX, 8),
                        "collect_nameboard_b": (69, 64)}.items():
        x, y = nearest_walkable(x, y)
        cond = [f"!{gid}_taken"] + (["got_detector"] if gid in ("collect_carving", "collect_fishing_gear") else [])
        if gid == "collect_nameboard_b":
            cond.append("got_nameboard_a")
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
    vegetable_gardens()
    scatter_trees()
    scatter_decor()
    village_polish()
    for name, s in spots.items():
        tx, ty = s["x"] // TS, s["y"] // TS
        if g[ty, tx] in BLOCKED:
            print("WARN spot on blocked tile:", name, tx, ty, g[ty, tx])
    with open(f"{out_root}/data/map.txt", "w") as f:
        f.write("\n".join("".join(r) for r in g))
    img = paint(g, TS, CRISP)
    chunks = save_chunks(img, f"{out_root}/assets/world")
    world = {"tile": TS, "width": W, "height": H, "blocked": "".join(sorted(BLOCKED)),
             "outdoor": [0, 0, OUT_W * TS, OUT_H * TS], "ground": chunks, "ground_res": 2,
             "objects": objects, "spots": spots, "zones": zones}
    with open(f"{out_root}/data/world.json", "w") as f:
        json.dump(world, f, ensure_ascii=False, indent=0)
    return world
