"""Builds the world of Hrafnvik.

Outputs
  data/map.txt          terrain grid (one char per 16x16 tile) - used for collisions
  data/world.json       objects, doors, spots (named positions), zones, interactables
  assets/world/ground.png  the painted ground layer (terrain with organic edges)

Terrain chars
  .  grass        h hill grass     g tall/overgrown grass   f farmland
  =  dirt path    p cobblestone    s sand                   b bridge   d dock
  ~  sea          r river/stream   P pond                   # cliff    ^ mountain rock
  o  wood floor   O old floor      c parquet                D doormat
  V  wallpaper    U plank wall     Y fine wallpaper         W wall top X void
"""
import json
import math
import random
import numpy as np
from PIL import Image

TS = 16
W, H = 160, 84
BLOCKED = set("~rP#^WVUYX")
CRISP = set("bdoOcDVUYWX#^")

g = np.full((H, W), ".", dtype="<U1")
rng = random.Random(1887)
objects = []
spots = {}
zones = []
occupied = np.zeros((H, W), dtype=bool)  # tiles reserved by buildings / decor


# ---------------------------------------------------------------- helpers
def fill(x0, y0, x1, y1, ch):
    g[max(0, y0):y1 + 1, max(0, x0):x1 + 1] = ch


def disc(cx, cy, r, ch):
    for y in range(int(cy - r), int(cy + r) + 1):
        for x in range(int(cx - r), int(cx + r) + 1):
            if 0 <= x < W and 0 <= y < H and (x - cx) ** 2 + (y - cy) ** 2 <= r * r:
                g[y, x] = ch


def path(points, width, ch="="):
    for (x0, y0), (x1, y1) in zip(points, points[1:]):
        steps = max(abs(x1 - x0), abs(y1 - y0)) * 2 + 1
        for i in range(steps + 1):
            t = i / steps
            x, y = x0 + (x1 - x0) * t, y0 + (y1 - y0) * t
            for dy in range(width):
                for dx in range(width):
                    xi, yi = int(round(x)) + dx, int(round(y)) + dy
                    if 0 <= xi < W and 0 <= yi < H and g[yi, xi] not in "bd":
                        g[yi, xi] = ch


def smooth_noise_1d(n, scale, amp, seed):
    r = random.Random(seed)
    pts = [r.uniform(-1, 1) for _ in range(n // scale + 3)]
    out = []
    for i in range(n):
        k, t = divmod(i, scale)
        t /= scale
        t = t * t * (3 - 2 * t)
        out.append((pts[k] * (1 - t) + pts[k + 1] * t) * amp)
    return out


SPR = {}


def place(sprite, tx, ty, oid=None, show_if=None, interact=None, reserve=True, extra=None, px=0, py=0):
    """Place a sprite with its top-left at tile (tx,ty) (+px/py pixel offset)."""
    m = SPR[sprite]
    o = {"sprite": sprite, "x": int(tx * TS + px), "y": int(ty * TS + py)}
    if oid:
        o["id"] = oid
    if show_if:
        o["show_if"] = show_if
    if interact:
        o["interact"] = interact
    if extra:
        o.update(extra)
    objects.append(o)
    if reserve:
        x0 = (o["x"]) // TS
        y0 = (o["y"]) // TS
        x1 = (o["x"] + m["w"] - 1) // TS
        y1 = (o["y"] + m["oy"] - 1) // TS
        occupied[max(0, y0 - 0):y1 + 1, max(0, x0):x1 + 1] = True
    return o


def building(sprite, tx, ty, door_to=None, door_id=None, oid=None, show_if=None, door_show_if=None):
    o = place(sprite, tx, ty, oid=oid, show_if=show_if)
    m = SPR[sprite]
    if door_to and "door" in m:
        dx, dy = m["door"]
        objects.append({
            "type": "door", "id": door_id or f"door_{sprite}_{tx}", "to": door_to,
            "x": o["x"] + dx - 8, "y": o["y"] + dy - 6, "w": 16, "h": 14,
            **({"show_if": door_show_if} if door_show_if else {}),
        })
        # keep the doorstep walkable & clear
        occupied[(o["y"] + dy) // TS, (o["x"] + dx) // TS] = True
        return (o["x"] + dx, o["y"] + dy)
    return None


def spot(name, x_px, y_px, facing="down"):
    spots[name] = {"x": int(x_px), "y": int(y_px), "dir": facing}


def tspot(name, tx, ty, facing="down"):
    spot(name, tx * TS + 8, ty * TS + 8, facing)


def interact(iid, tx, ty, tw=1, th=1, show_if=None, label=None):
    o = {"type": "interact", "id": iid, "x": tx * TS, "y": ty * TS, "w": tw * TS, "h": th * TS}
    if show_if:
        o["show_if"] = show_if
    if label:
        o["label"] = label
    objects.append(o)


def zone(zid, name, x0, y0, x1, y1, indoor=False, music="village"):
    zones.append({"id": zid, "name": name, "rect": [x0 * TS, y0 * TS, (x1 - x0 + 1) * TS, (y1 - y0 + 1) * TS],
                  "indoor": indoor, "music": music})


# ---------------------------------------------------------------- terrain
def build_terrain():
    fill(0, 0, W - 1, H - 1, "X")
    fill(0, 0, 115, H - 1, ".")
    # mountains along the north edge
    edge = smooth_noise_1d(116, 9, 1.6, 3)
    for x in range(116):
        fill(x, 0, x, int(4 + edge[x]), "^")
    # northern hills
    for x in range(116):
        for y in range(5, 10):
            if g[y, x] == ".":
                g[y, x] = "h"
    # sea: the south coast with a harbour bay
    coast = smooth_noise_1d(116, 7, 1.5, 5)
    for x in range(116):
        cy = 57 + coast[x]
        if 36 <= x <= 68:
            cy = 50 + coast[x] * 0.4          # harbour bay
        elif 30 <= x < 36:
            cy = 57 - (x - 30) * 1.1 + coast[x] * 0.5
        elif 68 < x <= 74:
            cy = 50 + (x - 68) * 0.6
        for y in range(int(cy), H):
            g[y, x] = "~"
        # beaches west of the harbour and around the wreck, cliffs elsewhere
        if x < 34 or 95 <= x:
            for y in range(int(cy) - 3, int(cy)):
                if g[y, x] in ".h":
                    g[y, x] = "s"
        elif 74 < x < 92:
            for y in range(int(cy) - 2, int(cy)):
                g[y, x] = "#"
        elif 34 <= x <= 68:
            for y in range(int(cy) - 1, int(cy)):
                g[y, x] = "s"
    # eastern coast cliffs shape
    for x in range(74, 92):
        for y in range(52, H):
            if g[y, x] not in "#":
                pass
    # river from the mountains to the sea (border between village and east hills)
    rx = smooth_noise_1d(H, 8, 0.8, 9)
    for y in range(3, H):
        x = int(91 + rx[y])
        g[y, x] = "r"
        g[y, x + 1] = "r"
    # east hills
    for y in range(5, 58):
        for x in range(94, 116):
            if g[y, x] == ".":
                g[y, x] = "h"
    # waterfall cliff and pond in the north-west
    fill(6, 9, 22, 10, "#")
    fill(14, 5, 15, 8, "r")
    disc(14.5, 13.5, 3.2, "P")
    # stream from the pond to the sea
    sx = smooth_noise_1d(H, 6, 1.0, 13)
    for y in range(15, H):
        x = int(14 + sx[y])
        if g[y, x] == "~":
            break
        g[y, x] = "r"
        g[y, x + 1] = "r"
    # roads ------------------------------------------------------------
    path([(0, 30), (12, 30), (30, 30), (34, 29)], 2)          # west road
    path([(49, 29), (70, 30), (89, 30)], 2)                   # east road to bridge
    fill(90, 30, 90, 31, "="); fill(91, 30, 93, 31, "b")      # bridge over the river
    fill(12, 30, 16, 31, "b")                                 # bridge over the stream
    path([(41, 23), (41, 15)], 2)                             # to the church
    path([(41, 35), (41, 48)], 2)                             # to the harbour
    path([(42, 44), (51, 44)], 2)                             # inn front
    path([(51, 44), (62, 47)], 2)                             # warehouse
    path([(75, 17), (75, 29)], 2)                             # estate drive
    path([(70, 31), (79, 37)], 2)                             # Gideon's home
    path([(32, 30), (28, 28), (27, 26)], 2)                   # blacksmith
    path([(21, 19), (24, 22), (30, 29)], 1)                   # herbalist trail
    path([(41, 40), (32, 43), (31, 46)], 1)                   # Bjorn's hut
    path([(94, 30), (99, 31), (104, 30), (108, 27)], 1)       # old farm track
    path([(99, 31), (101, 40), (104, 49)], 1)                 # down to the wreck
    path([(5, 31), (6, 38)], 1)                               # field track
    # town square
    fill(34, 24, 49, 34, "p")
    # farmland west
    for y in range(37, 46):
        for x in range(3, 18):
            if y % 2 == 0:
                g[y, x] = "f"
            else:
                g[y, x] = "f"
    # overgrown farm east
    tn = value_noise(H, W, 4, 77)
    for y in range(14, 38):
        for x in range(96, 115):
            if g[y, x] == "h" and tn[y, x] > 0.35:
                g[y, x] = "g"
    # docks
    fill(44, 47, 45, 58, "d")
    fill(44, 54, 60, 55, "d")
    fill(56, 47, 57, 58, "d")
    fill(38, 49, 41, 50, "d")


def build_interiors():
    def room(x0, y0, x1, y1, floor, face, door_x):
        fill(x0, y0, x1, y1, "W")
        fill(x0 + 1, y0 + 1, x1 - 1, y0 + 2, face)
        fill(x0 + 1, y0 + 3, x1 - 1, y1 - 1, floor)
        g[y1, door_x] = "D"
        g[y1, door_x + 1] = "D"

    room(121, 2, 134, 12, "o", "V", 127)      # Ashford home
    room(138, 2, 155, 14, "o", "Y", 146)      # inn
    room(121, 16, 138, 27, "c", "Y", 129)     # Elias' study
    room(142, 17, 153, 26, "O", "U", 147)     # abandoned farmhouse
    room(121, 31, 138, 43, "O", "U", 129)     # barn


# ---------------------------------------------------------------- objects
def build_objects():
    # mountains & waterfall (backdrop)
    x = -20
    i = 0
    while x < 116 * TS - 60:
        name = "mountain_a" if i % 2 == 0 else "mountain_b"
        if x + SPR[name]["w"] > 117 * TS:
            x = 117 * TS - SPR[name]["w"]
        place(name, 0, 0, px=x, py=-8 - (i % 3) * 6, reserve=False)
        x += SPR[name]["w"] - 40 - (i % 2) * 20
        i += 1
    place("waterfall", 13, 5, px=6, py=-6, reserve=False, interact="paint_waterfall")
    tspot("paint_waterfall", 17, 17, "up")

    # --- village buildings ---
    building("church", 38, 7, "spawn_church_none", door_id="door_church")
    spot("church_door", 38 * TS + 36, 7 * TS + 112 + 6)
    building("house_red", 26, 15)
    building("turf_house", 18, 15, "herbalist_closed", door_id="door_astrid")
    building("smithy", 22, 22)
    building("house_blue", 50, 16)
    building("house_yellow", 56, 21, "runa_closed", door_id="door_runa")
    building("house_white", 26, 33)
    building("house_green", 52, 31)
    building("house_red_small", 61, 30)
    building("turf_house_b", 27, 40, "bjorn_closed", door_id="door_bjorn")
    building("inn", 45, 38, "spawn_inn_in", door_id="door_inn")
    building("warehouse", 60, 42, "warehouse_closed", door_id="door_warehouse")
    building("house_yellow", 8, 23)
    building("house_blue", 64, 22)
    building("house_white", 57, 12)
    building("house_red", 68, 25)
    building("turf_house", 32, 36)
    building("house_yellow", 82, 24)
    building("house_green", 4, 48)
    # Gideon's home (shabby) and its repaired version after the ending
    building("house_gideon", 78, 34, "spawn_home_in", door_id="door_home", show_if=["!ending"])
    building("house_gideon_fixed", 78, 34, show_if=["ending"])
    # Elias' estate
    building("manor", 70, 9, "spawn_study_in", door_id="door_manor")
    # east: abandoned farm
    building("farmhouse", 99, 24, "spawn_farmhouse_in", door_id="door_farmhouse")
    building("barn", 105, 14, "spawn_barn_in", door_id="door_barn")

    # --- square ---
    place("monument", 41, 27, px=-2, interact="monument")
    place("stall_red", 35, 24, interact="stall_fish")
    place("stall_blue", 46, 24, interact="stall_bread")
    place("cart", 35, 31, oid="henrik_cart", interact="henrik_cart")
    place("stall_green", 46, 31)
    for (lx, ly) in ((34, 27), (49, 27), (40, 33), (44, 33), (40, 22), (75, 28), (51, 43), (90, 29)):
        place("lamp", lx, ly, px=3, py=-14)
    place("well", 38, 28)
    place("bench", 43, 22, px=0, py=4)
    place("bench_coat", 43, 34, oid="coat_bench", show_if=["ch2", "!got_key"], interact="elias_coat", px=4)
    place("bench", 43, 34, show_if=["!ch2"], px=4)
    place("bench", 43, 34, show_if=["got_key"], px=4)
    place("carriage", 47, 35, oid="carriage_square", show_if=["ch2", "!ch3"], px=4)
    place("carriage", 77, 18, oid="carriage_estate", show_if=["ch3", "!elias_fled"])
    place("barrel", 50, 26); place("crates", 33, 25)

    # graveyard by the church
    for (gx, gy) in ((47, 9), (49, 9), (47, 11), (49, 11), (51, 10)):
        place("grave" if (gx + gy) % 2 else "gravestone", gx, gy, px=3)
    for fx in range(46, 53):
        place("fence", fx, 13)
    interact("graves", 47, 9, 5, 4)
    tspot("paint_church", 40, 19, "up")

    # --- harbour ---
    place("sailboat", 48, 50, px=-4, py=8, reserve=False)
    place("sailboat", 59, 52, px=4, py=2, reserve=False)
    place("rowboat", 46, 57, px=4, reserve=False)
    place("rowboat", 39, 51, px=4, reserve=False, interact="bjorn_boat")
    place("rowboat", 20, 55, reserve=False)
    for (px_, py_) in ((44, 58), (45, 58), (56, 58), (57, 58), (60, 54), (60, 55)):
        place("post", px_, py_, px=5, py=4, reserve=False)
    place("fish_rack", 33, 47); place("fish_rack", 36, 40)
    place("crates", 58, 47, interact="harbor_crates"); place("crate", 64, 46); place("barrel", 54, 46)
    place("barrel", 55, 47)
    tspot("crate_pile", 58, 48)
    interact("harbor_crates", 58, 47, 2, 2)
    interact("warehouse_drop", 62, 46, 2, 1)
    interact("fishing_spot", 44, 58, 2, 1)
    interact("fishing_spot", 59, 54, 2, 2)
    tspot("paint_harbor", 45, 52, "down")
    interact("bjorn_boat", 39, 49, 3, 2)

    # --- Gideon's yard ---
    place("woodpile", 74, 36, interact="woodpile")
    place("chopping_block", 76, 38, interact="chop_wood")
    place("fence_broken", 82, 37, oid="broken_fence", show_if=["!fence_fixed"], interact="broken_fence")
    place("fence", 82, 37, show_if=["fence_fixed"])
    for fx in (83, 84):
        place("fence", fx, 37)
    place("fence_post", 85, 37, px=2)
    place("barrel", 77, 33, px=2)
    tspot("home_yard", 81.5, 40)

    # --- estate garden ---
    for fx in range(66, 74):
        place("fence", fx, 18)
    for fx in range(78, 88):
        place("fence", fx, 18)
    for (bx, by) in ((67, 12), (67, 15), (85, 12), (85, 15), (68, 19), (84, 20), (69, 21), (82, 21)):
        place("bush_berry" if (bx + by) % 3 == 0 else "bush", bx, by)
    for (fx, fy) in ((70, 20), (72, 21), (78, 20), (80, 22), (73, 19)):
        place("flowers_b" if fx % 2 else "flowers_a", fx, fy, reserve=False)
    place("well", 80, 20, interact="estate_fountain")
    interact("estate_garden", 69, 19, 4, 3)

    # --- smithy ---
    place("anvil", 27, 27, interact="anvil")
    place("barrel", 21, 26)

    # --- herbs and nature ---
    herb_spots = [(10, 18), (20, 20), (8, 13), (25, 11), (30, 8), (60, 9), (88, 12), (100, 40), (110, 44), (96, 10)]
    for i, (hx, hy) in enumerate(herb_spots):
        place("herb", hx, hy, oid=f"herb_{i}", interact=f"herb_{i}", show_if=[f"!d_herb_{i}"])

    # --- west farm & paddock ---
    for fx in range(2, 19):
        place("fence", fx, 36)
    for fx in range(3, 15):
        place("fence", fx, 19)
        place("fence", fx, 28)
    place("haystack", 16, 37, px=0, py=-6)
    for (sx, sy) in ((5, 21), (8, 24), (11, 22)):
        place("sheep", sx, sy, oid=f"sheep_{sx}", interact="sheep", reserve=False, extra={"wander": 24})
    place("horse", 7, 26, interact="horse", reserve=False, extra={"wander": 16})
    place("sign", 2, 28, interact="sign_west", px=0)

    # --- east: farm, barn, wreck ---
    place("gate", 90, 30, oid="bridge_gate_a", show_if=["!bridge_open"], interact="bridge_gate", px=0, py=-6,
          extra={"block": [0, 0, 16, 32]})
    place("footprints", 104, 21, oid="footprints", reserve=False, interact="footprints")
    place("fence_broken", 98, 22); place("fence_post", 100, 22); place("fence_broken", 102, 22)
    place("iron_chest", 111, 23, oid="iron_chest", show_if=["q_smith_started", "!got_iron_tools"], interact="iron_chest")
    place("haystack", 112, 19)
    place("rock_big", 96, 13); place("rock_big", 113, 33)
    place("wreck", 102, 51, interact="wreck")
    place("debris", 98, 53, reserve=False); place("debris", 108, 54, reserve=False)
    place("bench", 31, 7, interact="paint_hills_view")
    tspot("paint_hills", 32, 8.5, "up")
    interact("paint_harbor", 44, 57, 2, 1)
    interact("paint_church", 39, 18, 4, 2)
    interact("barn_window", 105, 19, 2, 2)
    place("smoke", 109, 12, oid="barn_smoke", show_if=["ch3", "!ending"], reserve=False, px=4)
    place("smoke", 80, 32, reserve=False, px=6, py=-6)
    place("smoke", 46, 36, reserve=False, px=0, py=-4)
    place("smoke", 26, 21, reserve=False, px=12, py=-2)

    # --- interiors ---
    # Ashford home
    place("bed_patched", 122, 5, interact="gideon_bed")
    place("bed", 132, 5, px=2)
    place("fireplace", 126, 3, py=4)
    place("table_meal", 128, 8, interact="home_table")
    place("chair", 127, 8, px=6, py=6); place("chair", 130, 8, px=6, py=6)
    place("sewing_table", 122, 9, px=2)
    place("easel", 131, 9, px=0, interact="clara_easel")
    place("bucket", 125, 6, oid="leak_bucket", show_if=["!roof_fixed"], interact="leak_bucket")
    place("wall_window", 123, 2, reserve=False, px=0, py=8); place("wall_window", 132, 2, reserve=False, py=8)
    place("wardrobe", 133, 9, px=4)
    place("rug", 125, 8, reserve=False, show_if=["home_rug"], px=8, py=8)
    for i in range(3):
        place("wall_painting", 129 + i, 2, oid=f"home_painting_{i}", reserve=False, py=10, show_if=[f"painting_{i + 1}"])
    interact("gideon_bed", 122, 5, 1, 2)
    # inn
    place("counter", 140, 5, px=4, py=6)
    place("fireplace", 151, 3, py=4)
    for (tx, ty) in ((141, 9), (148, 9)):
        place("table", tx, ty, interact="inn_table")
        place("chair", tx - 1, ty, px=6, py=4); place("chair", tx + 2, ty, px=4, py=4)
    place("barrel", 153, 6); place("barrel", 153, 8)
    place("wall_painting", 144, 2, reserve=False, py=10)
    place("wall_window", 141, 2, reserve=False, py=8); place("wall_window", 149, 2, reserve=False, py=8)
    # Elias' study
    place("bookshelf", 122, 17, py=8); place("bookshelf", 124, 17, py=8, px=4); place("bookshelf", 135, 17, py=8)
    place("desk", 128, 20, interact="study_desk")
    place("chair", 129, 22, px=2)
    place("cabinet", 132, 17, py=8, oid="cabinet_locked", show_if=["!cabinet_open"], interact="study_cabinet")
    place("cabinet_open", 132, 17, py=8, show_if=["cabinet_open"], interact="study_cabinet")
    place("wall_map", 126, 17, reserve=False, interact="study_map", py=10)
    place("rug", 127, 23, reserve=False)
    place("fireplace", 136, 22, py=0)
    place("bed_fancy", 122, 23)
    place("lantern_prop", 133, 21, reserve=False)
    # farmhouse
    place("table", 144, 20, px=0); place("old_chair", 143, 21); place("old_chair", 147, 20, px=4)
    place("floorboard", 150, 22, interact="floorboard", reserve=False)
    place("bed_patched", 151, 19, px=2)
    place("bucket", 143, 24)
    place("papers", 145, 24, reserve=False, interact="farm_papers")
    # barn
    place("hay_pile", 122, 34); place("hay_pile", 135, 34, px=4); place("hay_pile", 134, 39)
    place("fireplace", 126, 32, py=4)
    place("old_chair", 128, 36, px=4)
    place("table", 130, 36)
    place("wood_box", 131, 35, px=4, py=-4, show_if=["ch5", "!got_box"], interact="edmund_box")
    place("crates", 123, 39); place("barrel", 136, 41, px=-2); place("lantern_prop", 133, 36, reserve=False)
    place("old_chair", 125, 40)

    # --- doors from interiors back outside ---
    def exit_door(did, tx, ty, to):
        objects.append({"type": "door", "id": did, "to": to, "x": tx * TS + 2, "y": ty * TS + 4, "w": 28, "h": 12})

    exit_door("exit_home", 127, 12, "spawn_home_out")
    exit_door("exit_inn", 146, 14, "spawn_inn_out")
    exit_door("exit_study", 129, 27, "spawn_manor_out")
    exit_door("exit_farmhouse", 147, 26, "spawn_farmhouse_out")
    exit_door("exit_barn", 129, 43, "spawn_barn_out")

    # spawn points
    tspot("spawn_home_in", 127.5, 11, "up")
    tspot("spawn_inn_in", 146.5, 13, "up")
    tspot("spawn_study_in", 129.5, 26, "up")
    tspot("spawn_farmhouse_in", 147.5, 25, "up")
    tspot("spawn_barn_in", 129.5, 42, "up")
    tspot("game_start", 123.5, 7.5, "down")


def doors_out():
    """Outside spawn points one tile below each building door."""
    for o in objects:
        if o.get("type") == "door" and o["id"].startswith("door_"):
            name = o["id"][5:]
            spot(f"spawn_{name}_out", o["x"] + 8, o["y"] + 26, "down")


def npc_spots():
    t = tspot
    # home interior
    t("margaret_home", 124.5, 9.5, "right"); t("clara_home", 131, 10.5, "left")
    t("edmund_home", 127.5, 5.5, "down")
    # village
    t("bjorn_dock", 44.5, 52, "down"); t("bjorn_harbor", 52, 48, "left")
    t("sigrid_inn", 143, 5, "down"); t("leif_smithy", 26, 28.5, "left")
    t("astrid_cottage", 21, 20, "down"); t("einar_church", 40, 15.5, "down")
    t("runa_house", 58, 26, "down"); t("henrik_cart", 38, 32, "right")
    t("jonas_harbor", 37, 46, "right"); t("jonas_square", 45, 29, "left")
    t("halldor_estate", 78, 18, "down"); t("gunnar_field", 10, 34, "down")
    t("olafur_road", 3, 32, "right")
    t("elias_square", 46, 33, "left"); t("elias_estate", 74, 17.5, "down")
    t("elias_study", 130, 21, "down")
    t("edmund_barn", 129, 36.5, "left")
    t("clara_square", 43, 26, "down"); t("clara_paint", 44, 51, "down")
    t("margaret_shop", 36, 28, "right")
    t("worker_a", 103, 30, "left"); t("worker_b", 104, 31, "left")
    t("elias_farm", 102, 30, "right"); t("edmund_farm", 108, 28, "left")
    t("gideon_farm", 106, 30, "left")
    t("jonas_farm", 101, 32, "up")
    # cutscene waypoints: following Elias at night
    t("follow_start", 86, 31, "right")
    t("elias_walk_0", 88, 30, "right"); t("elias_walk_1", 96, 30.5, "right"); t("elias_walk_2", 102, 30, "right")
    t("elias_walk_3", 106, 27.5, "up"); t("elias_walk_4", 109, 24, "up")
    t("barn_window", 106, 21, "up")
    t("ending_view", 79, 39.5, "up")
    t("woodpile_spot", 74.5, 38.5, "up"); t("fence_spot", 82.5, 38.6, "up"); t("coat_spot", 44.5, 35.6, "up")
    t("study_desk_spot", 127.5, 22, "up"); t("cabinet_spot", 133, 20.6, "up"); t("floorboard_spot", 150.5, 22.5, "down")
    t("bed", 123.5, 7.5, "left"); t("bjorn_boat_spot", 40, 49.5, "down")
    t("bridge_view", 88, 31, "right")


def build_zones():
    zone("home_in", "منزل آل آشفورد", 121, 2, 134, 12, indoor=True, music="home")
    zone("inn_in", "نُزل سيغريد", 138, 2, 155, 14, indoor=True, music="inn")
    zone("study_in", "مكتب إلياس", 121, 16, 138, 27, indoor=True, music="estate")
    zone("farmhouse_in", "بيت المزرعة المهجور", 142, 17, 153, 26, indoor=True, music="mystery")
    zone("barn_in", "الحظيرة", 121, 31, 138, 43, indoor=True, music="mystery")
    # outdoor named areas (first match wins, so specific ones come first)
    zone("harbor", "الميناء", 30, 40, 70, 62)
    zone("square", "ساحة القرية", 32, 22, 51, 36)
    zone("church", "الكنيسة", 34, 5, 54, 21)
    zone("estate", "ضيعة إلياس", 64, 6, 89, 23, music="estate")
    zone("home", "منزل غيديون", 72, 31, 89, 42)
    zone("farm", "المزرعة المهجورة", 95, 11, 115, 36, music="mystery")
    zone("wreck", "حطام السفينة", 94, 44, 115, 62, music="mystery")
    zone("hills", "التلال الشرقية", 93, 0, 115, 62, music="mystery")
    zone("fields", "الحقول الغربية", 0, 17, 22, 50)
    zone("falls", "الشلال", 4, 4, 26, 18)
    zone("beach", "الشاطئ", 0, 50, 34, 62)
    zone("village", "هرافنفيك", 0, 0, 115, 83)


def scatter_decor():
    free = lambda x, y: g[y, x] in ".hg" and not occupied[y, x]
    # forest belts
    def forest(x0, y0, x1, y1, density, kinds):
        for y in range(y0, y1 + 1, 2):
            for x in range(x0, x1 + 1, 2):
                jx, jy = rng.randrange(0, 2), rng.randrange(0, 2)
                xx, yy = x + jx, y + jy
                if xx >= W or yy >= H or not free(xx, yy):
                    continue
                # keep paths and doors breathable
                near = g[max(0, yy - 1):yy + 3, max(0, xx - 1):xx + 2]
                if np.isin(near, list("=pbdsr#")).any():
                    continue
                if occupied[max(0, yy - 2):yy + 3, max(0, xx - 1):xx + 2].any():
                    continue
                if rng.random() < density:
                    k = rng.choice(kinds)
                    place(k, xx, yy, px=-5, py=-SPR[k]["oy"] + 14)
                    occupied[max(0, yy - 1):yy + 1, xx:xx + 2] = True
    forest(0, 6, 115, 9, 0.75, ["pine", "pine_dark", "pine"])
    forest(0, 10, 7, 22, 0.6, ["pine", "pine_dark"])
    forest(19, 10, 36, 13, 0.45, ["pine", "oak", "pine_small"])
    forest(55, 9, 66, 14, 0.5, ["pine", "oak"])
    forest(86, 6, 90, 28, 0.6, ["pine", "pine_dark"])
    forest(86, 33, 90, 50, 0.6, ["pine", "pine_dark", "oak"])
    forest(94, 5, 115, 13, 0.55, ["pine", "pine_dark", "pine_small"])
    forest(94, 36, 115, 46, 0.45, ["pine", "pine_dark", "pine_small"])
    forest(20, 46, 30, 52, 0.4, ["oak", "pine_small"])
    forest(64, 24, 72, 28, 0.3, ["oak"])
    forest(18, 36, 24, 46, 0.4, ["oak", "pine"])
    forest(66, 36, 72, 48, 0.4, ["oak", "pine"])
    # rocks, bushes, flowers
    for _ in range(170):
        x, y = rng.randrange(0, 115), rng.randrange(6, 58)
        if not free(x, y):
            continue
        if np.isin(g[max(0, y - 1):y + 2, max(0, x - 1):x + 2], list("=pbd")).any():
            continue
        k = rng.random()
        if k < 0.28:
            place(rng.choice(["rock", "rock", "rock_big"]) if g[y, x] != "s" else "rock", x, y)
        elif k < 0.52:
            place(rng.choice(["bush", "bush_berry"]), x, y)
        else:
            place(rng.choice(["flowers_a", "flowers_b"]), x, y, reserve=False)
    # shells and driftwood on beaches
    shell_i = 0
    for _ in range(400):
        x, y = rng.randrange(0, 115), rng.randrange(44, 62)
        if g[y, x] == "s" and not occupied[y, x] and shell_i < 8:
            place("shell", x, y, oid=f"shell_{shell_i}", interact=f"shell_{shell_i}", show_if=[f"!shell_{shell_i}_taken"], px=3, py=4)
            shell_i += 1
            occupied[y, x] = True


def hidden_collectibles():
    """Coins, letters and journal pages hidden around the world."""
    coins = [(9, 15), (33, 21), (63, 28), (86, 40), (24, 49), (52, 12), (112, 40), (97, 27), (68, 45), (6, 44), (110, 12), (33, 52)]
    k = 0
    for (x, y) in coins:
        if g[y, x] in BLOCKED or occupied[y, x]:
            continue
        place("coin_pickup", x, y, oid=f"coin_{k}", interact=f"coin_{k}", show_if=[f"!coin_{k}_taken"], reserve=False, px=3, py=3)
        k += 1
    print("coins placed:", k)
    # glints mark story collectibles; ids are referenced from data/story.gd
    for gid, (x, y) in {"lost_compass": (37, 49), "collect_letter_church": (36, 16),
                        "collect_journal_1": (110, 26), "collect_journal_2": (106, 55),
                        "collect_carving": (60, 18), "collect_fishing_gear": (31, 50),
                        "collect_property_farm": (152, 24), "collect_photo_inn": (154, 12)}.items():
        if g[y, x] in BLOCKED:
            print("WARN collectible on blocked tile", gid, x, y, g[y, x])
        cond = [f"!{gid}_taken"] + (["got_detector"] if gid in ("collect_carving", "collect_fishing_gear") else [])
        place("glint", x, y, oid=gid, interact=gid, show_if=cond, reserve=False, px=2, py=2,
              extra={"glint": True})


# ---------------------------------------------------------------- painter
def value_noise(h, w, cell, seed):
    r = np.random.RandomState(seed)
    gh, gw = h // cell + 2, w // cell + 2
    grid = r.rand(gh, gw)
    ys = np.arange(h) / cell
    xs = np.arange(w) / cell
    y0 = ys.astype(int); x0 = xs.astype(int)
    ty = ys - y0; tx = xs - x0
    ty = ty * ty * (3 - 2 * ty); tx = tx * tx * (3 - 2 * tx)
    a = grid[y0][:, x0]; b = grid[y0][:, x0 + 1]
    c_ = grid[y0 + 1][:, x0]; d = grid[y0 + 1][:, x0 + 1]
    top = a * (1 - tx) + b * tx
    bot = c_ * (1 - tx) + d * tx
    return top * (1 - ty[:, None]) + bot * ty[:, None]


def paint():
    PH, PW = H * TS, W * TS
    rs = np.random.RandomState(42)
    Y, X = np.mgrid[0:PH, 0:PW]
    chars = sorted(set("".join(g.flatten())) | set(".hgf=psbd~rP#^oOcDVUYWX"))
    idx = {ch: i for i, ch in enumerate(chars)}
    gi = np.vectorize(idx.get)(g)

    wx = (value_noise(PH, PW, 10, 1) - 0.5) * 9
    wy = (value_noise(PH, PW, 10, 2) - 0.5) * 9
    tc = gi[Y // TS, X // TS]
    txw = np.clip(((X + wx) // TS).astype(int), 0, W - 1)
    tyw = np.clip(((Y + wy) // TS).astype(int), 0, H - 1)
    tw = gi[tyw, txw]
    crisp_ids = [idx[ch] for ch in CRISP if ch in idx]
    crisp_c = np.isin(tc, crisp_ids)
    crisp_w = np.isin(tw, crisp_ids)
    T = np.where(crisp_c | crisp_w, tc, tw)

    img = np.zeros((PH, PW, 3), dtype=np.float32)
    n1 = value_noise(PH, PW, 24, 3)
    n2 = value_noise(PH, PW, 6, 4)
    rnd = rs.rand(PH, PW)

    def put(ch, rgb):
        if ch in idx:
            m = T == idx[ch]
            img[m] = rgb[m] if rgb.ndim == 3 else rgb

    def blend3(c1, c2, c3, a, b):
        c1, c2, c3 = (np.array(v, dtype=np.float32) for v in (c1, c2, c3))
        out = c1[None, None, :] * (1 - a[..., None]) + c2[None, None, :] * a[..., None]
        return out * (1 - b[..., None]) + c3[None, None, :] * b[..., None]

    # grass
    grass = blend3((104, 166, 76), (122, 182, 86), (86, 146, 66), n1, (n2 > 0.72) * 0.6)
    grass[(rnd < 0.05)] = (82, 140, 60)
    grass[(rnd > 0.985)] = (146, 200, 104)
    tuft = (((X % 7) == 3) & ((Y % 9) < 2) & (n2 > 0.55))
    grass[tuft] = (74, 128, 56)
    put(".", grass)
    hill = blend3((112, 158, 78), (134, 170, 88), (94, 136, 70), n1, (n2 > 0.7) * 0.5)
    hill[(rnd < 0.05)] = (88, 126, 62)
    hill[tuft] = (80, 116, 58)
    put("h", hill)
    tall = blend3((78, 130, 60), (96, 146, 66), (64, 108, 52), n1, n2 * 0.4)
    blades = ((X + (Y // 3)) % 4 == 0) & (rnd < 0.6)
    tall[blades] = (58, 98, 46)
    tall[(rnd > 0.97)] = (170, 180, 96)
    put("g", tall)
    farm = np.zeros((PH, PW, 3), np.float32)
    farm[:] = (122, 86, 56)
    farm[(Y % 8) < 3] = (98, 68, 44)
    farm[((Y % 8) == 5) & (X % 6 < 2)] = (90, 150, 70)
    put("f", farm)
    # paths
    dirt = blend3((200, 166, 116), (186, 150, 102), (214, 182, 132), n1, (n2 > 0.75) * 0.5)
    dirt[rnd < 0.03] = (160, 128, 90)
    dirt[rnd > 0.99] = (230, 210, 170)
    put("=", dirt)
    # cobblestones
    row = Y // 6
    offs = (row % 2) * 4
    cx = (X + offs) // 8
    stone_rand = np.random.RandomState(9).rand(PH // 6 + 1, PW // 8 + 2)
    sv = stone_rand[row, cx]
    cob = blend3((168, 160, 150), (150, 142, 134), (186, 178, 166), sv, (sv > 0.8) * 0.5)
    mortar = ((Y % 6) == 0) | (((X + offs) % 8) == 0)
    cob[mortar] = (118, 112, 106)
    put("p", cob)
    sand = blend3((236, 218, 168), (226, 204, 150), (244, 230, 190), n1, (n2 > 0.8) * 0.4)
    sand[rnd < 0.02] = (200, 180, 130)
    put("s", sand)
    # mountain rock / cliffs
    rockc = blend3((112, 116, 132), (96, 100, 116), (136, 140, 152), n1, (rnd < 0.15) * 0.6)
    put("^", rockc)
    strata = ((Y + (n2 * 6).astype(int)) % 5 == 0)
    cliff = blend3((134, 118, 104), (112, 98, 88), (88, 76, 70), n2, strata * 0.7)
    cliff[(rnd < 0.04)] = (160, 146, 128)
    cm = T == idx["#"]
    top_edge = cm & ~np.roll(cm, 3, axis=0)
    lip = cm & ~np.roll(cm, 1, axis=0)
    cliff[top_edge] = (156, 142, 124)
    cliff[lip] = (86, 140, 64)
    bot = cm & ~np.roll(cm, -2, axis=0)
    cliff[bot] = cliff[bot] * 0.7
    put("#", cliff)
    # wood: bridge, docks, floors
    plank_v = np.zeros((PH, PW, 3), np.float32)
    plank_v[:] = (150, 104, 64)
    plank_v[(X % 6) == 0] = (104, 70, 44)
    plank_v[((X % 6) == 3) & (rnd < 0.1)] = (176, 128, 82)
    put("b", plank_v)
    plank_h = np.zeros((PH, PW, 3), np.float32)
    plank_h[:] = (156, 110, 68)
    plank_h[(Y % 5) == 0] = (102, 70, 44)
    plank_h[((Y % 5) == 2) & ((X + (Y // 5) * 7) % 23 == 0)] = (102, 70, 44)
    put("d", plank_h)
    floor = np.zeros((PH, PW, 3), np.float32)
    floor[:] = (168, 122, 78)
    floor[(Y % 6) == 0] = (124, 86, 54)
    floor[((Y % 6) == 3) & ((X + (Y // 6) * 11) % 29 == 0)] = (124, 86, 54)
    floor[rnd < 0.02] = (186, 140, 92)
    put("o", floor)
    old = np.zeros((PH, PW, 3), np.float32)
    old[:] = (126, 104, 82)
    old[(Y % 6) == 0] = (78, 62, 48)
    old[rnd < 0.06] = (104, 88, 70)
    old[(n2 > 0.8)] = (150, 136, 100)
    put("O", old)
    parq = np.zeros((PH, PW, 3), np.float32)
    parq[:] = (128, 70, 50)
    parq[((X // 4 + Y // 4) % 2) == 0] = (146, 84, 58)
    parq[(X % 4 == 0) | (Y % 4 == 0)] = (100, 54, 40)
    put("c", parq)
    mat = np.zeros((PH, PW, 3), np.float32)
    mat[:] = (150, 60, 50)
    mat[(X % 4) < 2] = (170, 80, 60)
    put("D", mat)
    # walls
    wallp = np.zeros((PH, PW, 3), np.float32)
    wallp[:] = (220, 206, 168)
    wallp[(X % 8) == 0] = (200, 184, 146)
    wallp[(Y % TS) > 10] = (130, 92, 60)
    wallp[(Y % TS) == 11] = (100, 70, 46)
    put("V", wallp)
    fine = np.zeros((PH, PW, 3), np.float32)
    fine[:] = (96, 112, 92)
    fine[((X % 8) == 0) | (((X + 4) % 8 == 0) & ((Y % 8) == 4))] = (122, 140, 112)
    fine[(Y % TS) > 10] = (92, 54, 40)
    fine[(Y % TS) == 11] = (200, 170, 100)
    put("Y", fine)
    plankw = np.zeros((PH, PW, 3), np.float32)
    plankw[:] = (110, 80, 56)
    plankw[(X % 7) == 0] = (78, 56, 40)
    plankw[rnd < 0.05] = (90, 66, 46)
    put("U", plankw)
    put("W", np.zeros((PH, PW, 3), np.float32) + np.array((58, 40, 32), np.float32))
    put("X", np.zeros((PH, PW, 3), np.float32) + np.array((14, 12, 16), np.float32))

    # water (sea, river, pond) with depth from distance to land
    water_ids = [idx[ch] for ch in "~rP" if ch in idx]
    wm = np.isin(T, water_ids)
    land = ~wm
    dist = np.full((PH, PW), 40, np.float32)
    cur = land.copy()
    for d in range(1, 40):
        nxt = cur.copy()
        nxt[1:, :] |= cur[:-1, :]; nxt[:-1, :] |= cur[1:, :]
        nxt[:, 1:] |= cur[:, :-1]; nxt[:, :-1] |= cur[:, 1:]
        newly = nxt & ~cur
        dist[newly] = d
        cur = nxt
        if d > 30:
            break
    t = np.clip(dist / 30.0, 0, 1)[..., None]
    shallow = np.array((96, 194, 206), np.float32)
    deep = np.array((38, 102, 166), np.float32)
    water = shallow * (1 - t) + deep * t
    river = (T == idx.get("r", -1)) | (T == idx.get("P", -1))
    water[river] = water[river] * 0.6 + np.array((84, 170, 210), np.float32) * 0.4
    waves = (np.sin(X * 0.21 + np.sin(Y * 0.05) * 3) > 0.92) & ((Y % 9) == 0) & (rnd < 0.7)
    water[waves] = water[waves] * 0.5 + 0.5 * np.array((210, 236, 245), np.float32)
    foam = dist <= 2
    water[foam] = (226, 244, 246)
    foam2 = (dist == 3) & (rnd < 0.5)
    water[foam2] = (180, 228, 236)
    # darker water under docks & below cliffs
    dock = T == idx.get("d", -1)
    shadow = np.zeros_like(dock)
    for k in range(1, 5):
        shadow[k:, :] |= dock[:-k, :]
    water[shadow & wm] *= 0.72
    img[wm] = water[wm]

    # ambient shading: darken grass just under cliffs / mountains, light rim on cliff tops
    blk = np.isin(T, [idx[ch] for ch in "#^" if ch in idx])
    under = np.zeros_like(blk)
    for k in range(1, 4):
        under[k:, :] |= blk[:-k, :]
    under &= ~blk & ~wm
    img[under] *= 0.8
    # bridge rails
    bm = T == idx.get("b", -1)
    edge_top = bm & ~np.roll(bm, 2, axis=0)
    edge_bot = bm & ~np.roll(bm, -2, axis=0)
    img[edge_top | edge_bot] = (92, 60, 38)
    # dock edges
    de = dock & (~np.roll(dock, 1, axis=0) | ~np.roll(dock, -1, axis=0) | ~np.roll(dock, 1, axis=1) | ~np.roll(dock, -1, axis=1))
    img[de] = (96, 64, 40)

    out = np.clip(img, 0, 255).astype(np.uint8)
    return Image.fromarray(out, "RGB")


def build(sprite_meta, out_root):
    SPR.update(sprite_meta)
    build_terrain()
    build_interiors()
    build_objects()
    doors_out()
    npc_spots()
    build_zones()
    hidden_collectibles()
    scatter_decor()
    # sanity: every spot must be on a walkable tile
    for name, s in spots.items():
        tx, ty = s["x"] // TS, s["y"] // TS
        if g[ty, tx] in BLOCKED:
            print("WARN spot on blocked tile:", name, tx, ty, g[ty, tx])
    with open(f"{out_root}/data/map.txt", "w") as f:
        f.write("\n".join("".join(r) for r in g))
    world = {"tile": TS, "width": W, "height": H, "blocked": "".join(sorted(BLOCKED)),
             "objects": objects, "spots": spots, "zones": zones}
    with open(f"{out_root}/data/world.json", "w") as f:
        json.dump(world, f, ensure_ascii=False, indent=0)
    paint().save(f"{out_root}/assets/world/ground.png")
    return world
