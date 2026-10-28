"""Mesh building helpers for scripted Blender models (Z up, characters face -Y)."""
import math

import bmesh
import bpy
from mathutils import Vector


def _link(obj, collection=None):
    (collection or bpy.context.scene.collection).objects.link(obj)
    return obj


def mesh_object(name, bm, material=None, smooth=True, collection=None):
    mesh = bpy.data.meshes.new(name)
    bm.normal_update()
    bm.to_mesh(mesh)
    bm.free()
    if smooth:
        for poly in mesh.polygons:
            poly.use_smooth = True
    obj = bpy.data.objects.new(name, mesh)
    if material is not None:
        mesh.materials.append(material)
    return _link(obj, collection)


def ring_points(rx, ry, segments, front=0.0, back=0.0, power=6.0, offset=(0.0, 0.0)):
    """Ellipse ring in XY. `front` pushes a keel/ridge out towards -Y (breastplate ridge,
    shin ridge); `back` flattens (negative) or bulges (positive) the +Y side."""
    pts = []
    for i in range(segments):
        a = math.tau * i / segments
        x = rx * math.cos(a)
        y = ry * math.sin(a)
        s = math.sin(a)
        if s < 0.0 and front:
            y -= front * (-s) ** power
        if s > 0.0 and back:
            y += back * s ** 2
        pts.append((x + offset[0], y + offset[1]))
    return pts


def loft(name, rings, material=None, segments=24, cap_bottom=True, cap_top=True, smooth=True):
    """Tube through rings. Each ring: dict(z, rx, ry, [front, back, power, x, y]) or a
    precomputed list of (x, y) points with key 'pts'. Rings close to a point when rx == 0."""
    bm = bmesh.new()
    loops = []
    for r in rings:
        z = r["z"]
        if r.get("rx", 1.0) <= 1e-5 and "pts" not in r:
            loops.append([bm.verts.new((r.get("x", 0.0), r.get("y", 0.0), z))])
            continue
        pts = r.get("pts") or ring_points(r["rx"], r["ry"], segments, r.get("front", 0.0), r.get("back", 0.0),
                                          r.get("power", 6.0), (r.get("x", 0.0), r.get("y", 0.0)))
        loops.append([bm.verts.new((p[0], p[1], z)) for p in pts])
    for a, b in zip(loops, loops[1:]):
        if len(a) == 1 and len(b) == 1:
            continue
        if len(a) == 1 or len(b) == 1:
            tip, ring = (a[0], b) if len(a) == 1 else (b[0], a)
            n = len(ring)
            for i in range(n):
                f = (ring[i], ring[(i + 1) % n], tip) if len(a) == 1 else (ring[(i + 1) % n], ring[i], tip)
                bm.faces.new(f if len(b) == 1 else f[::-1])
            continue
        n = len(a)
        for i in range(n):
            bm.faces.new((a[i], a[(i + 1) % n], b[(i + 1) % n], b[i]))
    if cap_bottom and len(loops[0]) > 2:
        bm.faces.new(list(reversed(loops[0])))
    if cap_top and len(loops[-1]) > 2:
        bm.faces.new(loops[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return mesh_object(name, bm, material, smooth)


def box(name, size, center=(0, 0, 0), material=None, bevel=0.0, rotation=(0, 0, 0), smooth=False):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    if bevel > 0.0:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel, segments=2, affect="EDGES", profile=0.5)
    obj = mesh_object(name, bm, material, smooth)
    obj.location = center
    obj.rotation_euler = rotation
    return obj


def sphere(name, radius, center=(0, 0, 0), material=None, scale=(1, 1, 1), segments=16, rings=10):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segments, v_segments=rings, radius=radius)
    bmesh.ops.scale(bm, vec=Vector(scale), verts=bm.verts)
    obj = mesh_object(name, bm, material)
    obj.location = center
    return obj


def cylinder(name, r_bottom, r_top, height, center=(0, 0, 0), material=None, segments=12, rotation=(0, 0, 0)):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segments, radius1=r_bottom, radius2=r_top, depth=height)
    obj = mesh_object(name, bm, material)
    obj.location = center
    obj.rotation_euler = rotation
    return obj


def lames(name, z_top, z_bottom, count, rx, ry, material, flare=0.012, overlap=0.25, taper=1.0,
          front=0.0, x=0.0, y=0.0, segments=20):
    """Stacked overlapping armour bands (segmented plates, as on the reference knight's arms).
    Each band flares at its lower edge; `taper` scales the radius of the lowest band."""
    parts = []
    h = (z_top - z_bottom) / count
    for i in range(count):
        t = i / max(count - 1, 1)
        k = 1.0 + (taper - 1.0) * t
        top = z_top - i * h + h * overlap * 0.5
        bot = z_top - (i + 1) * h - h * overlap * 0.5
        rings = [
            dict(z=top, rx=rx * k * 0.96, ry=ry * k * 0.96, front=front, x=x, y=y),
            dict(z=(top + bot) * 0.5, rx=rx * k, ry=ry * k, front=front, x=x, y=y),
            dict(z=bot, rx=rx * k + flare, ry=ry * k + flare, front=front, x=x, y=y),
        ]
        parts.append(loft("%s_%d" % (name, i), rings, material, segments, cap_bottom=False, cap_top=False))
    return join(parts, name)


def join(objs, name):
    objs = [o for o in objs if o is not None]
    if not objs:
        return None
    if len(objs) == 1:
        objs[0].name = name
        return objs[0]
    ctx = {"active_object": objs[0], "selected_editable_objects": objs, "object": objs[0]}
    with bpy.context.temp_override(**ctx):
        bpy.ops.object.join()
    objs[0].name = name
    return objs[0]


def apply_transform(obj):
    mw = obj.matrix_world.copy()
    obj.data.transform(mw)
    obj.matrix_world.identity()


def solidify(obj, thickness, offset=-1.0):
    mod = obj.modifiers.new("solidify", "SOLIDIFY")
    mod.thickness = thickness
    mod.offset = offset
    return mod


def bevel_mod(obj, width=0.004, segments=2, angle_deg=35.0):
    mod = obj.modifiers.new("bevel", "BEVEL")
    mod.width = width
    mod.segments = segments
    mod.limit_method = "ANGLE"
    mod.angle_limit = math.radians(angle_deg)
    return mod
