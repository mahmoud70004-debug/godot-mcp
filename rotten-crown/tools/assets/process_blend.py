"""Blender script: .blend/.fbx/.obj/.dae source -> retro, phone-friendly GLB (sibling of process_model.py).

  $BLENDER -b --factory-startup --python tools/assets/process_blend.py -- <source> --name out --tris N --tex PX
      [--objs a,b*,c] [--scale S | --height H] [--ground] [--cache DIR]

<source> is a path (absolute, or relative to build/asset_cache). Pipeline, same conventions as process_model.py:
 - import (blend: opened; fbx/obj/dae: imported); --objs keeps only the named meshes (fnmatch patterns), the rest is dropped
 - parents cleared, armature/other modifiers dropped or applied (rest pose), transforms applied
 - real-world scale: --scale S multiplies, --height H scales the result to H metres tall (packs use arbitrary units)
 - --ground: z=0 of the source is the ground; geometry entirely below z=-0.05 is cut (buried foundations); else min z = 0
 - materials merged by base-colour texture image (or colour), joined, split per material and decimated (COLLAPSE)
   in proportion to about N triangles in total
 - texture = base colour image, LANCZOS to <= PX (never upscaled) + light unsharp, palette-quantised PNG embedded,
   nearest filtering; roughness 0.9, metallic 0, no normal maps
 - origin at the base centre, +Y up in the GLB; writes assets/models/<name>.glb and build/kit_report/<name>.json
"""
import fnmatch
import json
import math
import os
import shutil
import subprocess
import sys

import bpy
import bmesh
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
CACHE = os.path.join(ROOT, "build", "asset_cache")
TEXLIB = os.path.join(HERE, "texlib.py")
COLORS = 96
PY = shutil.which("python3") or "/usr/bin/python3"
CLEAN_ENV = {k: v for k, v in os.environ.items() if not k.startswith("PYTHON")}


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    a = {"src": None, "name": None, "tris": 3000, "tex": 256, "objs": None, "scale": 1.0, "height": 0.0, "ground": False}
    i = 0
    while i < len(argv):
        t = argv[i]
        if t in ("--tris", "--tex"):
            a[t[2:]] = int(argv[i + 1]); i += 2
        elif t in ("--scale", "--height"):
            a[t[2:]] = float(argv[i + 1]); i += 2
        elif t == "--name":
            a["name"] = argv[i + 1]; i += 2
        elif t == "--objs":
            a["objs"] = argv[i + 1].split(","); i += 2
        elif t == "--ground":
            a["ground"] = True; i += 1
        else:
            a["src"] = t; i += 1
    if not a["src"] or not a["name"]:
        raise SystemExit("usage: ... -- <source> --name out [--tris N --tex PX --objs a,b --scale S|--height H --ground]")
    if not os.path.isabs(a["src"]):
        a["src"] = os.path.join(CACHE, a["src"])
    return a


def tri_count(obj):
    lt = np.empty(len(obj.data.polygons), dtype=np.int32)
    obj.data.polygons.foreach_get("loop_total", lt)
    return int((lt - 2).sum())


def select_only(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def load(path):
    ext = os.path.splitext(path)[1].lower()
    if ext == ".blend":
        bpy.ops.wm.open_mainfile(filepath=path)
    else:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        if ext == ".fbx":
            bpy.ops.import_scene.fbx(filepath=path)
        elif ext == ".obj":
            bpy.ops.wm.obj_import(filepath=path)
        elif ext == ".dae":
            bpy.ops.wm.collada_import(filepath=path)
        elif ext in (".gltf", ".glb"):
            bpy.ops.import_scene.gltf(filepath=path)
        else:
            raise SystemExit("unsupported source " + ext)


def prepare(a):
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    if a["objs"]:
        keep = [o for o in meshes if any(fnmatch.fnmatchcase(o.name, p) for p in a["objs"])]
    else:
        keep = [o for o in meshes if not o.hide_render]
    if not keep:
        raise SystemExit("no meshes selected")
    for o in list(bpy.context.scene.objects):
        if o not in keep:
            bpy.data.objects.remove(o, do_unlink=True)
    for o in keep:
        o.hide_set(False)
        o.hide_viewport = False
        o.select_set(False)
    bpy.ops.object.select_all(action="DESELECT")
    for o in keep:
        o.select_set(True)
    bpy.context.view_layer.objects.active = keep[0]
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    bpy.ops.object.make_single_user(object=True, obdata=True)
    for o in keep:
        for m in list(o.modifiers):
            select_only(o)
            if m.type == "ARMATURE":
                o.modifiers.remove(m)  # rest pose
            else:
                try:
                    bpy.ops.object.modifier_apply(modifier=m.name)
                except RuntimeError:
                    o.modifiers.remove(m)
        if o.data.shape_keys:
            for kb in list(o.data.shape_keys.key_blocks)[::-1]:
                o.shape_key_remove(kb)
    bpy.ops.object.select_all(action="DESELECT")
    for o in keep:
        o.select_set(True)
    bpy.context.view_layer.objects.active = keep[0]
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return keep


def bounds(objs):
    mn = np.array([1e9] * 3)
    mx = np.array([-1e9] * 3)
    for o in objs:
        vs = np.empty(len(o.data.vertices) * 3, dtype=np.float32)
        o.data.vertices.foreach_get("co", vs)
        vs = vs.reshape(-1, 3)
        if len(vs):
            mn = np.minimum(mn, vs.min(0))
            mx = np.maximum(mx, vs.max(0))
    return mn, mx


def scale_objs(objs, s):
    for o in objs:
        vs = np.empty(len(o.data.vertices) * 3, dtype=np.float32)
        o.data.vertices.foreach_get("co", vs)
        o.data.vertices.foreach_set("co", (vs * s).astype(np.float32))
        o.data.update()


def cut_below(obj, z):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    drop = [f for f in bm.faces if all(v.co.z < z for v in f.verts)]
    bmesh.ops.delete(bm, geom=drop, context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bm.to_mesh(obj.data)
    bm.free()


def _norm(s):
    s = s.lower()
    for pre in ("mat_", "tex_"):
        if s.startswith(pre):
            s = s[len(pre):]
    for ext in (".jpg", ".jpeg", ".png", ".tga"):
        s = s.replace(ext, "")
    if s.rsplit(".", 1)[-1].isdigit():
        s = s.rsplit(".", 1)[0]
    return "".join(c for c in s if c.isalnum())


MATCHES = {}


def guess_image(name):
    """Old Blender-Internal packs lose the material->texture link on import; match by (fuzzy) name."""
    import difflib
    want = _norm(name)
    imgs = [i for i in bpy.data.images if i.size[0] > 0 and i.name != "Render Result"]
    best, score = None, 0.0
    for i in imgs:
        have = _norm(i.name)
        s = difflib.SequenceMatcher(None, want, have).ratio()
        if have == want:
            s = 2.0
        elif want in have or have in want:
            s = 1.0 + s
        if s > score:
            best, score = i, s
    if best is not None and score >= 0.8:
        MATCHES[name] = best.name
        return best
    print("NOMATCH", name)  # falls back to the flat colour
    return None


def mat_info(m):
    """-> (key, image or None, colour)"""
    col = (0.5, 0.5, 0.5, 1.0)
    img = None
    if m and m.use_nodes:
        for n in m.node_tree.nodes:
            if n.type == "BSDF_PRINCIPLED":
                col = tuple(n.inputs["Base Color"].default_value)
                for l in n.inputs["Base Color"].links:
                    nn = l.from_node
                    if nn.type == "TEX_IMAGE" and nn.image:
                        img = nn.image
                    else:  # mix/multiply chain: first image feeding it
                        for n2 in m.node_tree.nodes:
                            if n2.type == "TEX_IMAGE" and n2.image:
                                img = n2.image
                                break
    elif m:
        col = tuple(m.diffuse_color)
    if img is None and m and not (m.use_nodes and any(n.type == "TEX_IMAGE" for n in m.node_tree.nodes)):
        img = guess_image(m.name)
    if img is not None:
        base = img.name.rsplit(".", 1)[0] if img.name.rsplit(".", 1)[-1].isdigit() else img.name
        key = "img:" + os.path.splitext(base)[0] + f":{img.size[0]}x{img.size[1]}"
    else:
        key = "col:" + ",".join(f"{c:.2f}" for c in col[:3])
    return key, img, col


def split_by_material(obj):
    select_only(obj)
    if len(obj.data.materials) <= 1:
        return [obj]
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.separate(type="MATERIAL")
    bpy.ops.object.mode_set(mode="OBJECT")
    return list(bpy.context.selected_objects)


def weld(obj):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
    bm.to_mesh(obj.data)
    bm.free()


def collapse_to(obj, budget):
    for _ in range(4):
        cur = tri_count(obj)
        if cur <= budget * 1.1:
            return
        md = obj.modifiers.new("dec", "DECIMATE")
        md.decimate_type = "COLLAPSE"
        md.ratio = max(0.0005, budget / cur)
        md.use_collapse_triangulate = True
        select_only(obj)
        bpy.ops.object.modifier_apply(modifier=md.name)


def run():
    a = parse_args()
    load(a["src"])
    objs = prepare(a)
    src_tris = sum(tri_count(o) for o in objs)

    merged = {}
    for o in objs:
        keys = []
        for m in o.data.materials:
            key, img, col = mat_info(m)
            if key not in merged:
                merged[key] = {"img": img, "col": col, "name": (m.name if m else "mat"), "mat": bpy.data.materials.new("m%d" % len(merged))}
            keys.append(key)
        for i, key in enumerate(keys):
            o.data.materials[i] = merged[key]["mat"]
        if not keys:
            o.data.materials.append(bpy.data.materials.new("none"))

    mn, mx = bounds(objs)
    s = a["scale"]
    if a["height"] > 0:
        s = a["height"] / max(1e-6, (mx[2] - mn[2]))
    if abs(s - 1.0) > 1e-6:
        scale_objs(objs, s)

    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    if len(objs) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    if a["ground"]:
        cut_below(obj, -0.05)
    parts = split_by_material(obj)
    tot = sum(tri_count(p) for p in parts)
    for p in parts:
        weld(p)
    for p in parts:
        t = tri_count(p)
        pb = max(24, a["tris"] * t / max(1, tot))
        collapse_to(p, pb)
        print("PART", p.name, t, "->", tri_count(p), "budget", int(pb))
    select_only(parts[0])
    for p in parts:
        p.select_set(True)
    if len(parts) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bm.to_mesh(me)
    bm.free()
    while me.color_attributes:
        me.color_attributes.remove(me.color_attributes[0])
    while len(me.uv_layers) > 1:
        me.uv_layers.remove(me.uv_layers[-1])
    try:
        bpy.ops.mesh.customdata_custom_splitnormals_clear()
    except Exception:  # noqa: BLE001
        pass
    select_only(obj)
    try:
        bpy.ops.object.shade_smooth_by_angle(angle=math.radians(40))
    except Exception:  # noqa: BLE001
        bpy.ops.object.shade_smooth()

    # origin at base centre (--ground: source z=0 stays the ground)
    vs = np.empty(len(me.vertices) * 3, dtype=np.float32)
    me.vertices.foreach_get("co", vs)
    vs = vs.reshape(-1, 3)
    lo, hi = vs.min(0), vs.max(0)
    base_z = 0.0 if a["ground"] else lo[2]
    vs -= np.array([(lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2, base_z], dtype=np.float32)
    me.vertices.foreach_set("co", vs.reshape(-1))
    me.update()
    for c in list(obj.users_collection):  # sources hide/exclude collections: export from the scene root
        c.objects.unlink(obj)
    bpy.context.scene.collection.objects.link(obj)
    obj.hide_viewport = False
    obj.hide_set(False)
    obj.location = (0, 0, 0)
    obj.name = a["name"]
    me.name = a["name"]

    # materials: processed textures
    tmp_dir = os.path.join(ROOT, "build", "model_tex", a["name"])
    shutil.rmtree(tmp_dir, ignore_errors=True)
    os.makedirs(tmp_dir)
    mat_tris = {}
    for p in me.polygons:
        mat_tris[p.material_index] = mat_tris.get(p.material_index, 0) + len(p.vertices) - 2
    total = max(1, sum(mat_tris.values()))
    tex_report = []
    by_mat = {id(e["mat"]): (k, e) for k, e in merged.items()}
    for idx, tris in mat_tris.items():
        old = me.materials[idx]
        key, e = by_mat[id(old)]
        mat = bpy.data.materials.new(e["name"] + "_retro")
        mat.use_nodes = True
        nt = mat.node_tree
        for n in list(nt.nodes):
            if n.type not in ("OUTPUT_MATERIAL", "BSDF_PRINCIPLED"):
                nt.nodes.remove(n)
        bsdf = nt.nodes["Principled BSDF"]
        bsdf.inputs["Roughness"].default_value = 0.9
        bsdf.inputs["Metallic"].default_value = 0.0
        try:
            bsdf.inputs["Specular IOR Level"].default_value = 0.2
        except KeyError:
            pass
        mat.use_backface_culling = False
        img = e["img"]
        if img is not None:
            raw = os.path.join(tmp_dir, f"raw_{idx}.png")
            img.filepath_raw = raw
            img.file_format = "PNG"
            img.save()
            share = tris / total
            px = a["tex"] if share >= 0.15 else max(32, a["tex"] // 2)
            px = min(px, max(img.size[0], img.size[1]))
            out = os.path.join(tmp_dir, f"tex_{idx}_{px}.png")
            subprocess.run([PY, "-I", TEXLIB, "albedo", "--diff", raw, "--px", str(px), "--out", out, "--colors", str(COLORS)],
                           check=True, env=CLEAN_ENV, stdout=subprocess.DEVNULL)
            tn = nt.nodes.new("ShaderNodeTexImage")
            tn.image = bpy.data.images.load(out)
            tn.image.colorspace_settings.name = "sRGB"
            tn.interpolation = "Closest"
            tn.extension = "REPEAT"
            nt.links.new(tn.outputs["Color"], bsdf.inputs["Base Color"])
            tex_report.append({"material": e["name"], "px": list(tn.image.size), "kb": os.path.getsize(out) // 1024})
        else:
            bsdf.inputs["Base Color"].default_value = e["col"]
        me.materials[idx] = mat

    out_path = os.path.join(ROOT, "assets", "models", a["name"] + ".glb")
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    kw = dict(filepath=out_path, export_format="GLB", use_selection=True, export_image_format="AUTO",
              export_yup=True, export_cameras=False, export_lights=False, export_texcoords=True,
              export_normals=True, export_materials="EXPORT", export_extras=False, export_apply=False)
    try:
        bpy.ops.export_scene.gltf(export_vertex_color="NONE", **kw)
    except TypeError:
        bpy.ops.export_scene.gltf(**kw)
    rep = {"name": a["name"], "id": os.path.relpath(a["src"], CACHE), "tris": tri_count(obj), "tex": tex_report,
           "tex_px": max([max(t["px"]) for t in tex_report] or [0]),
           "glb_kb": round(os.path.getsize(out_path) / 1024, 1), "dims_m": [round(x, 2) for x in obj.dimensions],
           "source_tris": src_tris, "scale": round(s, 4)}
    os.makedirs(os.path.join(ROOT, "build", "kit_report"), exist_ok=True)
    with open(os.path.join(ROOT, "build", "kit_report", a["name"] + ".json"), "w") as f:
        json.dump(rep, f, indent=1)
    print("MATCHES", json.dumps(MATCHES))
    print("RESULT", json.dumps(rep))


run()
