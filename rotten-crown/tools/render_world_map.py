#!/usr/bin/env python3
"""Render the kingdom map from data/world/kingdom_map.json (world bible).

    python3 tools/render_world_map.py [out.png]

North is up (z grows upwards). Prints per-tier areas and a tree-count estimate so the
forest budget can be reasoned about before anything is built.
"""
import json
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
DATA = json.loads((ROOT / "data/world/kingdom_map.json").read_text())
OUT = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "docs/world_map.png"

S = 2  # pixels per metre
PANEL = 400
(MINX, MINZ), (MAXX, MAXZ) = DATA["bounds"]["min"], DATA["bounds"]["max"]
W, H = int((MAXX - MINX) * S), int((MAXZ - MINZ) * S)

COL = {
    "outside": (14, 20, 34),
    "T0": (88, 104, 110),
    "T1": (40, 74, 70),
    "T2": (20, 44, 46),
    "T3": (12, 34, 56),
    "amber": (70, 46, 22),
    "ring": (34, 62, 66),
    "road": (150, 128, 96),
    "road_new": (206, 184, 130),
    "wall": (176, 180, 188),
    "text": (232, 236, 244),
    "dim": (150, 160, 176),
}


def font(size, bold=False):
    name = "DejaVuSans-Bold.ttf" if bold else "DejaVuSans.ttf"
    try:
        return ImageFont.truetype("/usr/share/fonts/truetype/dejavu/" + name, size)
    except OSError:
        return ImageFont.load_default()


def px(x, z):
    return ((x - MINX) * S, (MAXZ - z) * S)


def seg_dist(gx, gz, a, b):
    ax, az = a
    bx, bz = b
    dx, dz = bx - ax, bz - az
    t = np.clip(((gx - ax) * dx + (gz - az) * dz) / max(dx * dx + dz * dz, 1e-9), 0, 1)
    return np.hypot(gx - (ax + t * dx), gz - (az + t * dz))


def tier_map():
    xs = np.arange(MINX, MAXX) + 0.5
    zs = np.arange(MINZ, MAXZ) + 0.5
    gx, gz = np.meshgrid(xs, zs)  # [z, x]
    (wx0, wz0), (wx1, wz1) = DATA["wall"]["min"], DATA["wall"]["max"]
    inside = (gx > wx0) & (gx < wx1) & (gz > wz0) & (gz < wz1)
    tier = np.full(gx.shape, 2, dtype=np.int8)  # default wood
    amber = np.zeros(gx.shape, dtype=bool)
    for zone in DATA["deep_zones"]:
        m = np.hypot(gx - zone["pos"][0], gz - zone["pos"][1]) < zone["r"]
        tier[m] = 3
        if zone.get("palette") == "amber":
            amber |= m
    t1 = np.zeros(gx.shape, dtype=bool)
    t0 = np.zeros(gx.shape, dtype=bool)
    mg = DATA["margins"]
    # wall ring
    d_wall = np.minimum.reduce([gx - wx0, wx1 - gx, gz - wz0, wz1 - gz])
    t1 |= d_wall < DATA["wall"]["ring_width"]
    # roads
    for road in DATA["roads"]:
        pts = road["pts"]
        for a, b in zip(pts, pts[1:]):
            t1 |= seg_dist(gx, gz, a, b) < mg["road"]
    # clearings, settlements, sites
    for c in DATA["clearings"]:
        d = np.hypot(gx - c["pos"][0], gz - c["pos"][1])
        t0 |= d < c["r"]
        t1 |= d < c["r"] + mg["clearing"]
    for c in DATA["settlements"] + DATA["future_sites"]:
        d = np.hypot(gx - c["pos"][0], gz - c["pos"][1])
        t0 |= d < c["r"]
        t1 |= d < c["r"] + mg["site"]
    for c in DATA["settlements"]:
        for fx0, fz0, fx1, fz1 in c.get("fields", []):
            t0 |= (gx > fx0) & (gx < fx1) & (gz > fz0) & (gz < fz1)
            t1 |= (gx > fx0 - mg["site"]) & (gx < fx1 + mg["site"]) & (gz > fz0 - mg["site"]) & (gz < fz1 + mg["site"])
    g = DATA["gate"]
    d = np.hypot(gx - g["pos"][0], gz - g["pos"][1])
    t0 |= d < g["clearing_radius"]
    t1 |= d < g["clearing_radius"] + mg["gate"]
    cx0, cz0, cx1, cz1 = DATA["citadel"]["rect"]
    t0 |= (gx > cx0) & (gx < cx1) & (gz > cz0) & (gz < cz1)
    t1 |= (gx > cx0 - mg["citadel"]) & (gx < cx1 + mg["citadel"]) & (gz > cz0 - mg["citadel"]) & (gz < cz1 + mg["citadel"])
    # dead trunks belong to the wall ring only inside the kingdom
    tier[t1] = 1
    tier[t0] = 0
    return tier, amber, inside


def dashed(draw, pts, fill, width=2, dash=10, gap=7):
    for a, b in zip(pts, pts[1:]):
        length = math.dist(a, b)
        if length == 0:
            continue
        ux, uy = (b[0] - a[0]) / length, (b[1] - a[1]) / length
        pos = 0.0
        while pos < length:
            end = min(pos + dash, length)
            draw.line([(a[0] + ux * pos, a[1] + uy * pos), (a[0] + ux * end, a[1] + uy * end)], fill=fill, width=width)
            pos += dash + gap


def circle(draw, pos, r, outline, width=2, dash=False):
    cx, cy = px(*pos)
    rr = r * S
    if not dash:
        draw.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], outline=outline, width=width)
        return
    n = 48
    pts = [(cx + rr * math.cos(2 * math.pi * i / n), cy + rr * math.sin(2 * math.pi * i / n)) for i in range(n + 1)]
    for i in range(0, n, 2):
        draw.line([pts[i], pts[i + 1]], fill=outline, width=width)


def label(draw, pos, text, size=15, bold=True, fill=None, anchor="mm", dy=0):
    x, y = px(*pos)
    f = font(size, bold)
    draw.text((x + 1, y + dy + 1), text, font=f, fill=(0, 0, 0), anchor=anchor)
    draw.text((x, y + dy), text, font=f, fill=fill or COL["text"], anchor=anchor)


def main():
    tier, amber, inside = tier_map()
    rgb = np.zeros(tier.shape + (3,), dtype=np.uint8)
    rgb[:] = COL["outside"]
    cols = {0: COL["T0"], 1: COL["T1"], 2: COL["T2"], 3: COL["T3"]}
    for k, c in cols.items():
        rgb[inside & (tier == k)] = c
    rgb[inside & (tier == 3) & amber] = COL["amber"]
    img = Image.fromarray(rgb[::-1])  # z up
    img = img.resize((W, H), Image.NEAREST)
    canvas = Image.new("RGB", (W + PANEL, H), (10, 14, 24))
    canvas.paste(img, (0, 0))
    d = ImageDraw.Draw(canvas)

    # world grid every 100 m
    for gx in range(-200, 261, 100):
        d.line([px(gx, MINZ), px(gx, MAXZ)], fill=(255, 255, 255, 18), width=1)
    for gz in range(0, 501, 100):
        d.line([px(MINX, gz), px(MAXX, gz)], fill=(60, 72, 96), width=1)
        label(d, (MINX + 1, gz + 6), f"z{gz}", 10, False, COL["dim"], "lm")

    # roads
    for road in DATA["roads"]:
        pts = [px(*p) for p in road["pts"]]
        if road["kind"] == "built":
            d.line(pts, fill=COL["road"], width=5, joint="curve")
        else:
            dashed(d, pts, COL["road_new"], 4)

    # wall + towers + gate
    (wx0, wz0), (wx1, wz1) = DATA["wall"]["min"], DATA["wall"]["max"]
    gx0, gx1 = DATA["gate"]["pos"][0] - DATA["gate"]["half_width"], DATA["gate"]["pos"][0] + DATA["gate"]["half_width"]
    d.line([px(wx0, wz0), px(gx0, wz0)], fill=COL["wall"], width=7)
    d.line([px(gx1, wz0), px(wx1, wz0)], fill=COL["wall"], width=7)
    d.line([px(wx0, wz0), px(wx0, wz1), px(wx1, wz1), px(wx1, wz0)], fill=COL["wall"], width=7)
    towers = [(wx0, wz0), (wx1, wz0), (wx0, wz1), (wx1, wz1)] + [(x, z) for z in (160, 270, 380) for x in (wx0, wx1)]
    for t in towers:
        x, y = px(*t)
        d.rectangle([x - 8, y - 8, x + 8, y + 8], fill=(120, 126, 140), outline=COL["wall"], width=2)
    gp = px(*DATA["gate"]["pos"])
    d.rectangle([gp[0] - 24, gp[1] - 14, gp[0] + 24, gp[1] + 14], outline=(255, 214, 120), width=3)
    label(d, (DATA["gate"]["pos"][0], DATA["gate"]["pos"][1] - 14), "KINGDOM GATE", 13, True, (255, 214, 120), dy=0)
    circle(d, DATA["gate"]["pos"], DATA["gate"]["clearing_radius"], (255, 214, 120), 1, dash=True)

    # citadel
    cx0, cz0, cx1, cz1 = DATA["citadel"]["rect"]
    d.rectangle([*px(cx0, cz1), *px(cx1, cz0)], outline=(190, 170, 220), width=3)
    wr = DATA["citadel"]["ward"]["rect"]
    d.rectangle([*px(wr[0], wr[3]), *px(wr[2], wr[1])], fill=(104, 94, 128), outline=(214, 196, 240), width=2)
    kr = DATA["citadel"]["keep"]["rect"]
    d.rectangle([*px(kr[0], kr[3]), *px(kr[2], kr[1])], fill=(70, 56, 96), outline=(214, 196, 240), width=2)
    label(d, ((wr[0] + wr[2]) / 2, (wr[1] + wr[3]) / 2), "OUTER WARD", 14)
    label(d, ((wr[0] + wr[2]) / 2, (wr[1] + wr[3]) / 2 - 11), "(feast hub)", 11, False, (226, 214, 244))
    label(d, ((kr[0] + kr[2]) / 2, (kr[1] + kr[3]) / 2), "ROYAL KEEP", 14)
    label(d, ((kr[0] + kr[2]) / 2, (kr[1] + kr[3]) / 2 - 11), "(sealed)", 11, False, (226, 214, 244))
    fg = DATA["citadel"]["front_gate"]
    fx, fy = px(*fg)
    d.polygon([(fx - 10, fy + 2), (fx + 10, fy + 2), (fx, fy + 16)], fill=(255, 214, 120))
    # old ward position (it moves)
    ox, oz = DATA["citadel"]["old_ward_origin"]
    dashed(d, [px(ox - 40, oz + 10), px(ox + 40, oz + 10), px(ox + 40, oz - 40), px(ox - 40, oz - 40), px(ox - 40, oz + 10)], (230, 120, 120), 2, 8, 6)
    label(d, (ox, oz - 15), "old Outer Ward", 12, False, (240, 150, 150))
    label(d, (ox, oz - 27), "(moves to the citadel)", 11, False, (240, 150, 150))

    # settlements, sites, clearings, deep zones
    for zone in DATA["deep_zones"]:
        circle(d, zone["pos"], zone["r"], (150, 120, 220) if zone.get("palette") != "amber" else (230, 160, 70), 2, dash=True)
        label(d, (zone["pos"][0], zone["pos"][1] - zone["r"] - 8), zone["name"], 12, False, (200, 188, 240) if zone.get("palette") != "amber" else (240, 190, 110))
    for s in DATA["settlements"]:
        circle(d, s["pos"], s["r"], (150, 230, 160), 3)
        label(d, s["pos"], s["name"], 15, True, (190, 245, 200))
        label(d, s["pos"], "built", 11, False, (150, 210, 160), dy=16)
        for fx0, fz0, fx1, fz1 in s.get("fields", []):
            dashed(d, [px(fx0, fz1), px(fx1, fz1), px(fx1, fz0), px(fx0, fz0), px(fx0, fz1)], (150, 230, 160), 2, 8, 6)
            label(d, ((fx0 + fx1) / 2, (fz0 + fz1) / 2), "pumpkin fields", 12, False, (170, 235, 180))
    for s in DATA["future_sites"]:
        circle(d, s["pos"], s["r"], (150, 200, 240), 2, dash=True)
        label(d, s["pos"], s["name"], 13, True, (180, 214, 246))
        label(d, s["pos"], "reserved", 10, False, (130, 170, 210), dy=14)
    for i, c in enumerate(DATA["clearings"], 1):
        circle(d, c["pos"], c["r"], (230, 230, 200), 2)
        label(d, c["pos"], str(i), 12, True, (240, 240, 210))
    for p in DATA["guard_posts"]:
        x, y = px(*p)
        d.polygon([(x, y - 8), (x - 7, y + 6), (x + 7, y + 6)], fill=(230, 150, 90), outline=(20, 20, 20))

    # spawn + outside
    sx, sy = px(*DATA["spawn"])
    star = [(sx + (13 if i % 2 == 0 else 6) * math.cos(math.pi / 5 * i - math.pi / 2),
             sy + (13 if i % 2 == 0 else 6) * math.sin(math.pi / 5 * i - math.pi / 2)) for i in range(10)]
    d.polygon(star, fill=(255, 226, 120), outline=(0, 0, 0))
    label(d, (DATA["spawn"][0], DATA["spawn"][1] - 12), "SPAWN (outside the curse)", 13, True, (255, 226, 120))
    label(d, (0, MINZ + 8), "outside the kingdom: clearer air, no curse", 13, False, COL["dim"])

    # compass + scale
    cx, cy = W - 60, 70
    d.polygon([(cx, cy - 34), (cx - 10, cy), (cx + 10, cy)], fill=COL["text"])
    d.text((cx, cy + 6), "N (+z)", font=font(13, True), fill=COL["text"], anchor="mt")
    bx, by = 40, H - 30
    d.line([(bx, by), (bx + 100 * S, by)], fill=COL["text"], width=4)
    d.text((bx + 50 * S, by - 8), "100 m", font=font(13, True), fill=COL["text"], anchor="ms")

    # legend panel
    x0 = W + 18
    y = 24
    d.text((x0, y), "ROTTEN CROWN", font=font(22, True), fill=COL["text"])
    y += 28
    d.text((x0, y), "World bible v1 - kingdom map", font=font(14), fill=COL["dim"])
    y += 34
    for k, name, sub in [(0, "Clearing", "no trees: villages, ward, gate"), (1, "Edge", "sparse: roads, clearings, wall ring"),
                         (2, "Wood", "default forest"), (3, "Deep", "dense, hallucinations strong")]:
        d.rectangle([x0, y, x0 + 26, y + 20], fill=cols[k], outline=COL["dim"])
        d.text((x0 + 36, y - 1), name, font=font(14, True), fill=COL["text"])
        d.text((x0 + 36, y + 15), sub, font=font(11), fill=COL["dim"])
        y += 42
    d.rectangle([x0, y, x0 + 26, y + 20], fill=COL["amber"], outline=COL["dim"])
    d.text((x0 + 36, y - 1), "Deep - amber", font=font(14, True), fill=COL["text"])
    d.text((x0 + 36, y + 15), "warm haze around the cellar", font=font(11), fill=COL["dim"])
    y += 50
    d.line([(x0, y + 8), (x0 + 26, y + 8)], fill=COL["road"], width=5)
    d.text((x0 + 36, y), "existing road", font=font(13), fill=COL["text"])
    y += 24
    dashed(d, [(x0, y + 8), (x0 + 26, y + 8)], COL["road_new"], 4, 6, 4)
    d.text((x0 + 36, y), "new trail", font=font(13), fill=COL["text"])
    y += 24
    x, yy = x0 + 13, y + 8
    d.polygon([(x, yy - 8), (x - 7, yy + 6), (x + 7, yy + 6)], fill=(230, 150, 90))
    d.text((x0 + 36, y), "guard post (ruined)", font=font(13), fill=COL["text"])
    y += 24
    circle(d, (MINX + (x0 + 13) / S, MAXZ - (y + 8) / S), 6, (230, 230, 200), 2)
    d.text((x0 + 36, y), "small clearing (encounter room)", font=font(13), fill=COL["text"])
    y += 40

    # stats
    area = {k: int(((tier == k) & inside).sum()) for k in range(4)}
    trees = {k: area[k] * DATA["tiers"][f"T{k}"]["trees_per_100m2"] / 100.0 for k in range(4)}
    total_area = sum(area.values())
    d.text((x0, y), "Forest budget estimate", font=font(15, True), fill=COL["text"])
    y += 24
    for k in range(4):
        d.text((x0, y), f"T{k}: {area[k] / 1000:5.1f}k m2 ({100 * area[k] / total_area:4.1f}%)  ~{int(trees[k]):>4} trees",
               font=ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 12), fill=COL["text"])
        y += 20
    d.text((x0, y + 4), f"Total ~{int(sum(trees.values()))} trees inside the walls", font=font(13, True), fill=(255, 226, 120))
    y += 26
    vis = math.pi * 60 ** 2
    d.text((x0, y), "In 60 m of fog the player sees about", font=font(12), fill=COL["dim"])
    d.text((x0, y + 16), f"{int(vis * 1.4 / 100)} trees in Wood, {int(vis * 2.2 / 100)} in Deep.", font=font(12), fill=COL["dim"])
    y += 52
    d.text((x0, y), "Travel (straight line from the gate):", font=font(12, True), fill=COL["text"])
    gate = DATA["gate"]["pos"]
    for nm, pos in [("Thornfield", DATA["settlements"][0]["pos"]), ("Hollowmere", DATA["settlements"][1]["pos"]),
                    ("Citadel gate", DATA["citadel"]["front_gate"]), ("Cellar", DATA["future_sites"][1]["pos"])]:
        y += 18
        dist = math.dist(gate, pos)
        d.text((x0, y), f"{nm:<13}{dist:5.0f} m  ~{dist / 3.2 / 60:.1f} min", font=ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 12), fill=COL["dim"])

    OUT.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(OUT)
    print("wrote", OUT, canvas.size)
    print("area m2:", area, "trees:", {k: int(v) for k, v in trees.items()}, "total", int(sum(trees.values())))
    # sanity: sites must stay inside the wall and clear of the citadel
    cx0, cz0, cx1, cz1 = DATA["citadel"]["rect"]
    for s in DATA["settlements"] + DATA["future_sites"] + DATA["clearings"]:
        x, z = s["pos"]
        r = s["r"]
        if not (wx0 + r < x < wx1 - r and wz0 + r < z < wz1 - r):
            print("WARN outside wall:", s["id"])
        for fx0, fz0, fx1, fz1 in s.get("fields", []):
            if fx1 > cx0 - 8 and fz1 > cz0 - 8 and fx0 < cx1 and fz0 < cz1:
                print("WARN fields touch citadel:", s["id"])
        nx, nz = min(max(x, cx0), cx1), min(max(z, cz0), cz1)
        if math.hypot(x - nx, z - nz) < r:
            print("WARN overlaps citadel:", s["id"])
    allsites = DATA["settlements"] + DATA["future_sites"]
    for i, a in enumerate(allsites):
        for b in allsites[i + 1:]:
            if math.dist(a["pos"], b["pos"]) < a["r"] + b["r"]:
                print("WARN overlap:", a["id"], b["id"])


main()
