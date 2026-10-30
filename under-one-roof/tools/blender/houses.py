"""Nordic village houses modelled in Blender and rendered for the game.

Run with the Blender Python module (bpy), e.g.:
    /home/user/bpyenv/venv/bin/python tools/blender/houses.py OUT_DIR [name ...]

Every house is real geometry: stone foundation, log walls with round logs, a pitched
roof with thickness, overhang and barge boards (wood shingles, Icelandic turf or straw
thatch), framed windows with crossbars, shutters and flower boxes, a plank door with a
step, a brick chimney, a wall lantern and a firewood stack. It is lit by a low northern
sun from the upper left and rendered with Cycles from the game's own 3/4 top-down
camera (orthographic, 1 m = one 16 px tile), 4 render pixels per world pixel.
tools/blender_pixel.py then turns the renders into pixel art (tools/build_assets.py).

Writes OUT_DIR/<name>.png (RGBA) and OUT_DIR/houses.json with, per house, the world-px
size, the door position and the ground footprint.
"""
import json
import math
import os
import random
import sys

import bpy
from mathutils import Vector

TILT = math.radians(50.0)          # camera angle from straight down
PX_PER_M = 16 * 4                  # 16 world px per metre, 4 render px per world px

# ------------------------------------------------------------------ palette (from the reference)
def hexc(h, a=1.0):
    """sRGB hex -> linear RGBA (Blender colour inputs are linear)."""
    h = h.lstrip("#")
    def lin(c):
        c = c / 255.0
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    return tuple(lin(int(h[i:i + 2], 16)) for i in (0, 2, 4)) + (a,)


HOUSES = {
    # Gideon's home before the repair: weathered grey logs, patched roof, a boarded window
    "cabin_a": dict(w=4.6, d=5.0, h=2.3, pitch=46, wall="logs", wall_col="6f6a62", trim="d9d2c2", roof="shingle",
                    roof_col="4a4440", door_col="5a4632", door_x=-0.55, windows=[(1.05, False), (-1.7, True)],
                    chimney=0.9, damaged=True, firewood=True, lantern=False, seed=1),
    # the repaired home: fresh warm logs, a red door, flowers under the windows
    "cabin_warm": dict(w=4.8, d=5.0, h=2.3, pitch=46, wall="logs", wall_col="9a6a40", trim="efe6d2", roof="shingle",
                       roof_col="5c3a2c", door_col="a8382e", door_x=-0.6, windows=[(1.1, False), (-1.75, False)],
                       chimney=0.9, flowers=True, firewood=True, lantern=True, seed=2),
    # the family's home at the ending: painted falu red, white trim, a new porch lamp
    "cabin_c_f": dict(w=4.8, d=5.0, h=2.3, pitch=46, wall="planks", wall_col="8e2f26", trim="f2ede2", roof="shingle",
                      roof_col="3c3a3e", door_col="2f4a6a", door_x=0.6, windows=[(-1.1, False), (1.75, False)],
                      chimney=-0.9, flowers=True, lantern=True, seed=3),
    # fishermen and villagers
    "cabin_b": dict(w=4.6, d=5.2, h=2.2, pitch=48, wall="logs", wall_col="5e5952", trim="cfc6b4", roof="turf",
                    roof_col="5f7f3a", door_col="4a3a2c", door_x=0.0, windows=[(-1.35, False), (1.35, False)],
                    chimney=-1.0, firewood=True, seed=4),
    "cabin_b_f": dict(w=4.6, d=5.2, h=2.2, pitch=48, wall="planks", wall_col="b48a3c", trim="f0e8d8", roof="turf",
                      roof_col="5a7a36", door_col="3f5a3a", door_x=-0.3, windows=[(1.2, False), (-1.6, False)],
                      chimney=1.0, flowers=True, seed=5),
    "cabin_c": dict(w=4.8, d=5.0, h=2.3, pitch=46, wall="planks", wall_col="34506e", trim="e8e2d4", roof="shingle",
                    roof_col="3a3a40", door_col="8a6a3a", door_x=-0.5, windows=[(1.15, False), (-1.8, False)],
                    chimney=0.9, lantern=True, seed=6),
    "cabin_d": dict(w=5.8, d=5.2, h=2.3, pitch=44, wall="logs", wall_col="73695c", trim="d8d0bc", roof="shingle",
                    roof_col="4e4038", door_col="5a4030", door_x=0.1, windows=[(-1.6, False), (1.8, False)],
                    chimney=-1.4, firewood=True, lantern=True, seed=7),
    "cabin_d_f": dict(w=5.8, d=5.2, h=2.3, pitch=44, wall="planks", wall_col="c9b48a", trim="f4eee2", roof="turf",
                      roof_col="62823e", door_col="6a3a2a", door_x=-0.1, windows=[(1.6, False), (-1.8, False)],
                      chimney=1.4, flowers=True, seed=8),
    # the abandoned farmhouse: rotten grey wood, broken roof, boarded windows
    "cabin_old": dict(w=4.6, d=5.2, h=2.2, pitch=48, wall="planks", wall_col="5a544c", trim="8a8276", roof="shingle",
                      roof_col="3e3a36", door_col="3a3028", door_x=0.0, windows=[(-1.35, True), (1.35, True)],
                      chimney=-1.0, damaged=True, seed=9),
    # Astrid's cottage: whitewashed walls, deep straw thatch
    "thatch": dict(w=5.2, d=5.4, h=2.2, pitch=50, wall="plaster", wall_col="e8e0cc", trim="6a4a30", roof="thatch",
                   roof_col="c49a3a", door_col="6a4a30", door_x=0.0, windows=[(-1.5, False), (1.5, False)],
                   chimney=None, flowers=True, seed=10),
    "thatch_f": dict(w=5.2, d=5.4, h=2.2, pitch=50, wall="plaster", wall_col="ddd2b6", trim="5a3e2a", roof="thatch",
                     roof_col="b8902e", door_col="4a6a3a", door_x=0.4, windows=[(-1.4, False), (1.8, False)],
                     chimney=None, flowers=True, seed=11),
    # long turf-roofed storehouses
    "longhouse": dict(w=7.8, d=4.6, h=2.1, pitch=40, wall="planks", wall_col="7a5a3a", trim="d8ccb0", roof="turf",
                      roof_col="58783a", door_col=None, door_x=0.0, windows=[(-2.6, False), (0.0, False), (2.6, False)],
                      chimney=2.2, firewood=True, ridge_x=True, seed=12),
    "longhouse_f": dict(w=7.8, d=4.6, h=2.1, pitch=40, wall="logs", wall_col="6a5e50", trim="cfc4ac", roof="shingle",
                        roof_col="4a4038", door_col=None, door_x=0.0, windows=[(-2.6, False), (0.0, True), (2.6, False)],
                        chimney=-2.2, ridge_x=True, seed=13),
}


# ------------------------------------------------------------------ materials
def mat(name, col, rough=0.8, kind=None, col2=None, scale=1.0):
    """Principled material, optionally textured with procedural bands / bricks / noise."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = rough
    base = hexc(col)
    alt = hexc(col2) if col2 else tuple(c * 0.72 for c in base[:3]) + (1,)
    if kind is None:
        bsdf.inputs["Base Color"].default_value = base
        return m
    tc = nt.nodes.new("ShaderNodeTexCoord")
    mp = nt.nodes.new("ShaderNodeMapping")
    mp.inputs["Scale"].default_value = (scale, scale, scale)
    nt.links.new(tc.outputs["Object"], mp.inputs["Vector"])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = alt
    ramp.color_ramp.elements[1].color = base
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = (14.0 if kind == "turf" else 6.0) * scale
    noise.inputs["Detail"].default_value = 6.0
    nt.links.new(mp.outputs["Vector"], noise.inputs["Vector"])
    if kind in ("bricks", "shingles", "shingles_x"):   # shingles, stones and bricks
        br = nt.nodes.new("ShaderNodeTexBrick")
        br.inputs["Color1"].default_value = base
        br.inputs["Color2"].default_value = alt
        br.inputs["Mortar"].default_value = tuple(c * 0.45 for c in base[:3]) + (1,)
        br.inputs["Scale"].default_value = 1.0
        br.inputs["Mortar Size"].default_value = 0.012
        br.inputs["Brick Width"].default_value = 0.32 / scale
        br.inputs["Row Height"].default_value = 0.14 / scale
        br.offset = 0.5
        if kind in ("shingles", "shingles_x"):
            # rows of wooden shingles run along the ridge and step down the slope
            br.inputs["Brick Width"].default_value = 0.42
            br.inputs["Row Height"].default_value = 0.3
            br.inputs["Mortar Size"].default_value = 0.035
            br.inputs["Mortar"].default_value = tuple(c * 0.25 for c in base[:3]) + (1,)
            br.inputs["Color2"].default_value = tuple(c * 0.6 for c in base[:3]) + (1,)
            br.inputs["Bias"].default_value = 0.0
            rot = nt.nodes.new("ShaderNodeMapping")
            rot.inputs["Rotation"].default_value = (0, 0, math.pi / 2 if kind == "shingles" else 0.0)
            nt.links.new(tc.outputs["Object"], rot.inputs["Vector"])
            nt.links.new(rot.outputs["Vector"], br.inputs["Vector"])
        else:
            nt.links.new(tc.outputs["Object"], br.inputs["Vector"])
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.inputs["Factor"].default_value = 0.12 if kind.startswith("shingles") else 0.25
        nt.links.new(br.outputs["Color"], mix.inputs["A"])
        nt.links.new(noise.outputs["Color"], mix.inputs["B"])
        nt.links.new(mix.outputs["Result"], bsdf.inputs["Base Color"])
        bump = nt.nodes.new("ShaderNodeBump")
        bump.inputs["Strength"].default_value = 1.0 if kind.startswith("shingles") else 0.6
        nt.links.new(br.outputs["Fac"], bump.inputs["Height"])
        nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    elif kind in ("grain", "straw"):           # wood planks / thatch straw
        wv = nt.nodes.new("ShaderNodeTexWave")
        wv.wave_type = "BANDS"
        wv.bands_direction = "Z" if kind == "straw" else "X"
        wv.inputs["Scale"].default_value = 14.0 * scale if kind == "straw" else 3.0 * scale
        wv.inputs["Distortion"].default_value = 9.0 if kind == "straw" else 2.0
        wv.inputs["Detail"].default_value = 3.0
        nt.links.new(mp.outputs["Vector"], wv.inputs["Vector"])
        mix = nt.nodes.new("ShaderNodeMath")
        mix.operation = "MULTIPLY_ADD"
        mix.inputs[1].default_value = 0.7
        nt.links.new(wv.outputs["Fac"], mix.inputs[0])
        nt.links.new(noise.outputs["Fac"], mix.inputs[2])
        nt.links.new(mix.outputs[0], ramp.inputs["Fac"])
        nt.links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
        bump = nt.nodes.new("ShaderNodeBump")
        bump.inputs["Strength"].default_value = 0.9 if kind == "straw" else 0.35
        nt.links.new(wv.outputs["Fac"], bump.inputs["Height"])
        nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    else:                                      # noise: plaster, turf, stone
        nt.links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
        nt.links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
        bump = nt.nodes.new("ShaderNodeBump")
        bump.inputs["Strength"].default_value = 1.0 if kind == "turf" else 0.15
        nt.links.new(noise.outputs["Fac"], bump.inputs["Height"])
        nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    return m


# ------------------------------------------------------------------ geometry helpers
def box(name, size, loc, material, rot=(0, 0, 0), bevel=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.name = name
    o.scale = size
    bpy.ops.object.transform_apply(scale=True)
    if bevel:
        mod = o.modifiers.new("bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 2
    o.data.materials.append(material)
    return o


def cyl(name, r, length, loc, material, axis="X"):
    rot = {"X": (0, math.pi / 2, 0), "Y": (math.pi / 2, 0, 0), "Z": (0, 0, 0)}[axis]
    bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=r, depth=length, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.name = name
    o.data.materials.append(material)
    bpy.ops.object.shade_smooth()
    return o


def prism(name, w, d, base_z, rise, material, x0=0.0):
    """Solid gable (triangle) block: width w along x, depth d along y."""
    import bmesh
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    hw = w / 2
    vs = [bm.verts.new(v) for v in (
        (x0 - hw, 0, base_z), (x0 + hw, 0, base_z), (x0, 0, base_z + rise),
        (x0 - hw, d, base_z), (x0 + hw, d, base_z), (x0, d, base_z + rise))]
    for f in ((0, 1, 2), (3, 5, 4), (0, 3, 4, 1), (1, 4, 5, 2), (2, 5, 3, 0)):
        bm.faces.new([vs[i] for i in f])
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(o)
    o.data.materials.append(material)
    return o


def prism_x(name, w, d, base_z, rise, material):
    """Gable block with the ridge along x: triangle in the y-z plane, length w."""
    import bmesh
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    hw = w / 2
    vs = [bm.verts.new(v) for v in (
        (-hw, 0, base_z), (-hw, d, base_z), (-hw, d / 2, base_z + rise),
        (hw, 0, base_z), (hw, d, base_z), (hw, d / 2, base_z + rise))]
    for f in ((0, 2, 1), (3, 4, 5), (0, 1, 4, 3), (0, 3, 5, 2), (1, 2, 5, 4)):
        bm.faces.new([vs[i] for i in f])
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(o)
    o.data.materials.append(material)
    return o


# ------------------------------------------------------------------ house
def build_house(p):
    rnd = random.Random(p["seed"])
    W, D, H = p["w"], p["d"], p["h"]
    pitch = math.radians(p["pitch"])
    ridge_x = p.get("ridge_x", False)          # long houses: ridge parallel to the front
    trim = mat("trim", p["trim"], 0.7)
    dark = mat("dark", "2a221c", 0.9)
    stone = mat("stone", "8e8a84", 0.95, "bricks", "5e5a56", scale=0.8)
    glass = mat("glass", "2a3a52", 0.15)
    glass.node_tree.nodes["Principled BSDF"].inputs["Metallic"].default_value = 0.3
    iron = mat("iron", "2c2c30", 0.4)
    wood_kind = "grain"
    walls = mat("walls", p["wall_col"], 0.85, "noise" if p["wall"] == "plaster" else wood_kind, scale=1.2)

    # foundation
    box("foundation", (W + 0.25, D + 0.25, 0.45), (0, D / 2, 0.18), stone, bevel=0.03)
    z0 = 0.4
    # walls: a solid core plus visible log / plank / plaster skin on the front
    box("walls", (W, D, H), (0, D / 2, z0 + H / 2), walls)
    if p["wall"] == "logs":
        n = int(H / 0.26)
        logm = mat("logs", p["wall_col"], 0.85, "grain", scale=2.5)
        for i in range(n):
            z = z0 + 0.13 + i * (H / n)
            cyl(f"log{i}", 0.135, W + 0.28, (0, -0.02, z), logm, "X")
            cyl(f"logs{i}", 0.135, D + 0.1, (-W / 2 - 0.02, D / 2, z), logm, "Y")
            cyl(f"logt{i}", 0.135, D + 0.1, (W / 2 + 0.02, D / 2, z), logm, "Y")
            # log ends at the corners
            for sx in (-1, 1):
                box(f"end{i}{sx}", (0.2, 0.2, 0.22), (sx * (W / 2 + 0.06), -0.06, z), logm)
    elif p["wall"] == "planks":
        n = int(W / 0.24)
        plm = mat("planks", p["wall_col"], 0.85, "grain", scale=2.0)
        for i in range(n):
            x = -W / 2 + 0.12 + i * (W / n)
            box(f"board{i}", (W / n - 0.03, 0.05, H), (x, -0.03, z0 + H / 2), plm)
        for sx in (-1, 1):                      # corner boards in the trim colour
            box(f"corner{sx}", (0.16, 0.1, H + 0.05), (sx * (W / 2 + 0.02), -0.04, z0 + H / 2), trim)
    else:                                      # plaster with dark timber frame
        for sx in (-1, 1):
            box(f"post{sx}", (0.16, 0.08, H), (sx * (W / 2 - 0.05), -0.04, z0 + H / 2), trim)
        box("sill", (W, 0.08, 0.14), (0, -0.04, z0 + 0.07), trim)
        box("lintel", (W, 0.08, 0.14), (0, -0.04, z0 + H - 0.07), trim)

    # roof
    roof_kind = p["roof"]
    rc = p["roof_col"]
    if roof_kind == "shingle":
        roofm = mat("roof", rc, 0.8, "shingles_x" if ridge_x else "shingles", None, scale=1.0)
    elif roof_kind == "turf":
        roofm = mat("roof", rc, 0.95, "turf", "2e4a1c", scale=1.4)
    else:
        roofm = mat("roof", rc, 0.95, "straw", "7a5a22", scale=1.0)
    ov = 0.38                                  # overhang
    thick = 0.16 if roof_kind == "shingle" else (0.32 if roof_kind == "turf" else 0.5)
    span = (D if ridge_x else W) / 2 + ov
    rise = math.tan(pitch) * (D / 2 if ridge_x else W / 2)
    slope_len = span / math.cos(pitch)
    zr = z0 + H
    if ridge_x:
        # ridge along x: slopes face the camera (front) and away (back)
        for sy in (-1, 1):
            ang = -sy * pitch
            cy = D / 2 + sy * (span / 2) - sy * 0.0
            box(f"roof{sy}", (W + 2 * ov, slope_len, thick),
                (0, D / 2 + sy * span / 2 * 1.0 - sy * (ov / 2) * 0 , zr + rise / 2 + thick / 2),
                roofm, rot=(ang, 0, 0), bevel=0.04 if roof_kind != "shingle" else 0.0)
        prism_x("gablefill", W, D, zr, rise, walls)  # the attic under the roof, gables at the sides
        box("ridge", (W + 2 * ov + 0.1, 0.22, 0.16), (0, D / 2, zr + rise + thick * 0.9), dark)
        for sx in (-1, 1):                         # barge boards on the side gables
            for sy in (-1, 1):
                box(f"barge{sx}{sy}", (0.08, slope_len + 0.1, 0.1),
                    (sx * (W / 2 + ov), D / 2 + sy * span / 2, zr + rise / 2 + thick + 0.02), dark, rot=(-sy * pitch, 0, 0))
        if roof_kind == "turf":
            tuft = mat("tuft", "7aa046", 0.95)
            flower = mat("flower", "e8d050", 0.6)
            for i in range(70):
                t = rnd.uniform(0.1, 0.95)
                x = rnd.uniform(-W / 2 - ov + 0.2, W / 2 + ov - 0.2)
                y = D / 2 - span * t
                z = zr + rise * (1 - t) + thick + 0.02
                bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=rnd.uniform(0.08, 0.16), location=(x, y, z))
                bpy.context.active_object.data.materials.append(flower if rnd.random() < 0.15 else tuft)
    else:
        for sx in (-1, 1):
            box(f"roof{sx}", (slope_len, D + 2 * ov, thick),
                (sx * span / 2 - sx * 0.0, D / 2, zr + rise / 2 + thick / 2),
                roofm, rot=(0, sx * pitch, 0), bevel=0.04 if roof_kind != "shingle" else 0.0)
        # gable triangle on the front with vertical boards / plaster
        g = prism("gable", W, D, zr, rise, walls)
        if p["wall"] != "plaster":
            gm = mat("gableboards", p["wall_col"], 0.85, "grain", scale=2.4)
            nb = int(W / 0.22)
            for i in range(nb):
                x = -W / 2 + 0.11 + i * (W / nb)
                hgt = rise * (1 - abs(x) / (W / 2))
                if hgt > 0.08:
                    box(f"gb{i}", (W / nb - 0.03, 0.05, hgt), (x, -0.04, zr + hgt / 2), gm)
        # barge boards along the gable edges and a ridge cap
        for sx in (-1, 1):
            box(f"barge{sx}", (slope_len + 0.1, 0.07, 0.09),
                (sx * span / 2, -ov - 0.02, zr + rise / 2 + thick + 0.02), trim if roof_kind == "shingle" else dark,
                rot=(0, sx * pitch, 0))
        box("ridge", (0.22, D + 2 * ov + 0.1, 0.16), (0, D / 2, zr + rise + thick * 0.9), dark)
        if roof_kind == "turf":
            # tufts of grass and flowers on the sod roof
            tuft = mat("tuft", "7aa046", 0.95)
            flower = mat("flower", "e8d050", 0.6)
            for i in range(60):
                sx = rnd.choice((-1, 1))
                t = rnd.uniform(0.1, 0.95)
                x = sx * span * t
                y = rnd.uniform(-ov + 0.2, D + ov - 0.2)
                z = zr + rise * (1 - t) + thick + 0.02
                bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=rnd.uniform(0.08, 0.16), location=(x, y, z))
                o = bpy.context.active_object
                o.data.materials.append(flower if rnd.random() < 0.15 else tuft)
    # damage: missing shingles and moss
    if p.get("damaged"):
        hole = mat("hole", "1c1814", 1.0)
        moss = mat("moss", "4e6a32", 1.0)
        for i in range(5):
            sx = rnd.choice((-1, 1))
            t = rnd.uniform(0.2, 0.8)
            x = sx * span * t
            y = rnd.uniform(0.3, D - 0.3)
            z = zr + rise * (1 - t) + thick + 0.01
            box(f"hole{i}", (rnd.uniform(0.25, 0.5), rnd.uniform(0.3, 0.6), 0.04), (x, y, z), hole if i % 2 else moss,
                rot=(0, sx * pitch, 0))

    # chimney
    if p.get("chimney") is not None:
        bm = mat("brick", "8a4a3a", 0.9, "bricks", "5e3026", scale=2.2)
        cx = p["chimney"]
        top = zr + rise + 0.75
        box("chimney", (0.5, 0.5, top - zr), (cx, D * 0.62, zr + (top - zr) / 2), bm, bevel=0.02)
        box("chimcap", (0.62, 0.62, 0.1), (cx, D * 0.62, top), stone)

    # door
    door_x = p.get("door_x", 0.0)
    if p.get("door_col"):
        dm = mat("door", p["door_col"], 0.75, "grain", scale=4.0)
        box("doorframe", (1.02, 0.12, 1.9), (door_x, -0.07, z0 + 0.95), trim)
        box("door", (0.82, 0.12, 1.78), (door_x, -0.12, z0 + 0.89), dm)
        for i in range(4):
            box(f"plank{i}", (0.02, 0.13, 1.72), (door_x - 0.3 + i * 0.2, -0.13, z0 + 0.88), dark)
        cyl("handle", 0.035, 0.08, (door_x + 0.28, -0.22, z0 + 0.9), iron, "Y")
        box("step", (1.1, 0.5, 0.18), (door_x, -0.32, 0.12), stone, bevel=0.03)
        if p.get("lantern"):
            lm = mat("lantern", "f6c860", 0.3)
            lm.node_tree.nodes["Principled BSDF"].inputs["Emission Color"].default_value = hexc("ffcc66")
            lm.node_tree.nodes["Principled BSDF"].inputs["Emission Strength"].default_value = 3.0
            box("lamp", (0.16, 0.16, 0.24), (door_x + 0.75, -0.2, z0 + 1.75), lm)
            box("lamptop", (0.22, 0.22, 0.06), (door_x + 0.75, -0.2, z0 + 1.9), iron)

    # windows
    for (wx, boarded) in p["windows"]:
        wz = z0 + 1.25
        box(f"wframe{wx}", (0.92, 0.12, 0.92), (wx, -0.08, wz), trim)
        if boarded:
            bd = mat("boards", "6a5a44", 0.9, "grain", scale=3.0)
            box(f"wdark{wx}", (0.74, 0.1, 0.74), (wx, -0.11, wz), dark)
            for i in range(3):
                box(f"wb{wx}{i}", (0.95, 0.06, 0.16), (wx, -0.16, wz - 0.25 + i * 0.25), bd, rot=(0, rnd.uniform(-0.15, 0.15), 0))
        else:
            box(f"wglass{wx}", (0.74, 0.1, 0.74), (wx, -0.1, wz), glass)
            box(f"wbarv{wx}", (0.05, 0.13, 0.74), (wx, -0.13, wz), trim)
            box(f"wbarh{wx}", (0.74, 0.13, 0.05), (wx, -0.13, wz), trim)
            box(f"wsill{wx}", (1.05, 0.22, 0.07), (wx, -0.15, wz - 0.5), trim)
            sh = mat("shutter", p.get("door_col") or "4a6a3a", 0.8, "grain", scale=4.0)
            for sx in (-1, 1):
                box(f"shut{wx}{sx}", (0.3, 0.06, 0.88), (wx + sx * 0.64, -0.08, wz), sh)
            if p.get("flowers"):
                box(f"fbox{wx}", (0.9, 0.22, 0.16), (wx, -0.2, wz - 0.6), mat("fbox", "6a4a30", 0.8))
                for i in range(7):
                    col = rnd.choice(["d8423a", "e8c040", "f0f0f0", "c85aa0"])
                    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=0.07,
                                                          location=(wx - 0.36 + i * 0.12, -0.22, wz - 0.48 + rnd.uniform(0, 0.05)))
                    bpy.context.active_object.data.materials.append(mat("fl", col, 0.6))

    # firewood stacked against the side
    if p.get("firewood"):
        fw = mat("firewood", "8a6a44", 0.9)
        ends = mat("woodends", "d8b882", 0.9)
        for r in range(3):
            for c in range(4 - (r % 2)):
                cyl(f"fw{r}{c}", 0.1, 0.6, (W / 2 + 0.25, 0.3 + c * 0.21 + (r % 2) * 0.1, 0.12 + r * 0.19), fw, "Y")
                cyl(f"fe{r}{c}", 0.095, 0.02, (W / 2 + 0.25, 0.0 + c * 0.21 + (r % 2) * 0.1, 0.12 + r * 0.19), ends, "Y")
    return dict(W=W, D=D, door_x=door_x if p.get("door_col") else None, has_door=bool(p.get("door_col")))


# ------------------------------------------------------------------ scene / render
def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 48
    sc.cycles.use_denoising = True
    sc.render.film_transparent = True
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    world = bpy.data.worlds.new("sky")
    sc.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = hexc("b8c8dc")
    bg.inputs["Strength"].default_value = 0.32
    sun_data = bpy.data.lights.new("sun", "SUN")
    sun_data.energy = 4.6
    sun_data.angle = math.radians(5)
    sun_data.color = (1.0, 0.93, 0.82)
    sun = bpy.data.objects.new("sun", sun_data)
    sc.collection.objects.link(sun)
    # low sun from the upper left, behind the viewer's left shoulder
    # light travels from the upper left and slightly in front, down to the right and back
    d = Vector((0.75, 0.55, -0.9)).normalized()
    sun.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    return sc


def project(v):
    """World point -> (u, v) on the camera plane, in metres (v up)."""
    return v.x, v.z * math.sin(TILT) + v.y * math.cos(TILT)


def render_house(name, p, out_dir):
    sc = reset()
    info = build_house(p)
    bpy.context.view_layer.update()
    us, vs = [], []
    for o in sc.objects:
        if o.type != "MESH":
            continue
        for v in o.data.vertices:
            u, vv = project(o.matrix_world @ v.co)
            us.append(u)
            vs.append(vv)
    m = 0.15
    umin, umax, vmin, vmax = min(us) - m, max(us) + m, min(vs) - m, max(vs) + m
    wm, hm = umax - umin, vmax - vmin
    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = "ORTHO"
    cam_data.sensor_fit = "HORIZONTAL"
    cam_data.ortho_scale = wm
    cam = bpy.data.objects.new("cam", cam_data)
    sc.collection.objects.link(cam)
    sc.camera = cam
    ucen, vcen = (umin + umax) / 2, (vmin + vmax) / 2
    target = Vector((ucen, vcen / math.cos(TILT), 0.0))
    view_dir = Vector((0, math.sin(TILT), -math.cos(TILT)))       # camera looks along this
    cam.location = target - view_dir * 30
    cam.rotation_euler = (TILT, 0, 0)
    sc.render.resolution_x = int(round(wm * PX_PER_M))
    sc.render.resolution_y = int(round(hm * PX_PER_M))
    sc.render.resolution_percentage = 100
    sc.render.filepath = os.path.join(out_dir, f"{name}.png")
    bpy.ops.render.render(write_still=True)

    def to_px(u, v):
        return (u - umin) * 16.0, (vmax - v) * 16.0               # world px
    w_px, h_px = wm * 16.0, hm * 16.0
    fx0, fy0 = to_px(-info["W"] / 2, info["D"] * math.cos(TILT))
    fx1, fy1 = to_px(info["W"] / 2, 0.0)
    meta = {"w": int(round(w_px)), "h": int(round(h_px)),
            "ground": [round(fx0, 1), round(fy0, 1), round(fx1 - fx0, 1), round(fy1 - fy0, 1)],
            "front_y": round(fy1, 1)}
    if info["has_door"]:
        dx, dy = to_px(info["door_x"], -0.32 * math.cos(TILT))
        meta["door"] = [round(dx, 1), round(dy, 1)]
    return meta


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "/tmp/houses"
    os.makedirs(out, exist_ok=True)
    names = sys.argv[2:] or list(HOUSES)
    meta_path = os.path.join(out, "houses.json")
    meta = json.load(open(meta_path)) if os.path.exists(meta_path) else {}
    for n in names:
        meta[n] = render_house(n, HOUSES[n], out)
        print("rendered", n, meta[n])
        json.dump(meta, open(meta_path, "w"), indent=1)


if __name__ == "__main__":
    main()
