"""Blender script: Poly Haven glTF -> retro, phone-friendly GLB.

  $BLENDER -b --factory-startup --python tools/assets/process_model.py -- <asset_id> --tris N --tex PX [--name out] [--pieces] [--keep K]

Reads build/asset_cache/<id>/ (see fetch_polyhaven.py), writes assets/models/<name>.glb:
 - all transforms applied, real-world metres, origin at the base centre (min z = 0, +Y up in the GLB)
 - meshes joined per material and decimated (COLLAPSE) to about N triangles in total
   (--pieces: every source object stays a separate named mesh and N is the budget PER PIECE;
    --keep K keeps only the K largest pieces)
 - texture = diffuse x AO (arm.R), LANCZOS to PX + light unsharp, palette-quantised PNG embedded;
   normal/roughness/metal maps dropped (roughness 0.9, metallic 0); leaf/fern cards keep an alpha cut-out
Prints a RESULT line and writes build/kit_report/<name>.json.
"""
import json
import math
import os
import shutil
import subprocess
import sys
import urllib.parse

import bpy
import bmesh  # noqa: F401
import numpy as np
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
CACHE = os.path.join(ROOT, "build", "asset_cache")
TEXLIB = os.path.join(HERE, "texlib.py")
COLORS = 96
PRE_TRIS = 150000


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    a = {"id": None, "tris": 1000, "tex": 128, "name": None, "pieces": False, "keep": 0}
    i = 0
    while i < len(argv):
        t = argv[i]
        if t == "--tris":
            a["tris"] = int(argv[i + 1]); i += 2
        elif t == "--tex":
            a["tex"] = int(argv[i + 1]); i += 2
        elif t == "--name":
            a["name"] = argv[i + 1]; i += 2
        elif t == "--keep":
            a["keep"] = int(argv[i + 1]); i += 2
        elif t == "--pieces":
            a["pieces"] = True; i += 1
        else:
            a["id"] = t; i += 1
    if not a["id"]:
        raise SystemExit("usage: ... -- <asset_id> --tris N --tex PX [--name out] [--pieces] [--keep K]")
    a["name"] = a["name"] or a["id"]
    return a


def tri_count(obj):
    lt = np.empty(len(obj.data.polygons), dtype=np.int32)
    obj.data.polygons.foreach_get("loop_total", lt)
    return int((lt - 2).sum())


def select_only(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def load_gltf_info(folder):
    path = [f for f in os.listdir(folder) if f.endswith(".gltf")][0]
    with open(os.path.join(folder, path)) as f:
        d = json.load(f)
    return os.path.join(folder, path), d


def mat_sources(d, folder):
    """glTF material name -> dict(diff, arm, alpha, transform) with absolute paths."""
    out = {}

    def img_path(tex_index):
        src = d["textures"][tex_index]["source"]
        return os.path.join(folder, urllib.parse.unquote(d["images"][src]["uri"]))

    for m in d.get("materials", []):
        pbr = m.get("pbrMetallicRoughness", {})
        e = {"diff": None, "arm": None, "alpha": None, "xf": None}
        bc = pbr.get("baseColorTexture")
        if bc:
            e["diff"] = img_path(bc["index"])
            xf = bc.get("extensions", {}).get("KHR_texture_transform")
            if xf:
                e["xf"] = xf
        mr = pbr.get("metallicRoughnessTexture")
        if mr:
            p = img_path(mr["index"])
            if "_arm_" in os.path.basename(p):
                e["arm"] = p
        e["color"] = pbr.get("baseColorFactor", [0.8, 0.8, 0.8, 1.0])
        if e["diff"]:
            base = os.path.basename(e["diff"])
            if "_diff_" in base:
                for ext in (".png", ".jpg"):
                    cand = os.path.join(os.path.dirname(e["diff"]), base.replace("_diff_", "_alpha_").rsplit(".", 1)[0] + ext)
                    if os.path.exists(cand):
                        e["alpha"] = cand
                        break
        e["mask"] = e["alpha"] is not None
        out[m["name"]] = e
    return out


def apply_uv_transform(obj, sources):
    """Bake KHR_texture_transform (offset/scale) into the UVs (Godot ignores the extension)."""
    me = obj.data
    if not me.uv_layers:
        return
    uv = me.uv_layers.active.data
    n = len(me.loops)
    arr = np.empty(n * 2, dtype=np.float32)
    uv.foreach_get("uv", arr)
    arr = arr.reshape(-1, 2)
    ls = np.empty(len(me.polygons), dtype=np.int32)
    lt = np.empty(len(me.polygons), dtype=np.int32)
    mi = np.empty(len(me.polygons), dtype=np.int32)
    me.polygons.foreach_get("loop_start", ls)
    me.polygons.foreach_get("loop_total", lt)
    me.polygons.foreach_get("material_index", mi)
    loop_mat = np.repeat(mi, lt)
    for slot, mat in enumerate(obj.data.materials):
        if mat is None:
            continue
        key = mat.name if mat.name in sources else mat.name.rsplit(".", 1)[0]
        xf = sources.get(key, {}).get("xf")
        if not xf:
            continue
        off = xf.get("offset", [0, 0])
        sc = xf.get("scale", [1, 1])
        sel = loop_mat == slot
        u = arr[sel, 0]
        vg = 1.0 - arr[sel, 1]
        arr[sel, 0] = off[0] + sc[0] * u
        arr[sel, 1] = 1.0 - (off[1] + sc[1] * vg)
    uv.foreach_set("uv", arr.reshape(-1))
    me.update()


def bake_texture(src, px, out_dir, tag):
    if src["diff"] is None:
        return None
    base = os.path.splitext(os.path.basename(src["diff"]))[0]
    out = os.path.join(out_dir, f"{base}_{px}.png")
    cmd = [PY, "-I", TEXLIB, "albedo", "--diff", src["diff"], "--px", str(px), "--out", out, "--colors", str(COLORS)]
    if src["arm"]:
        cmd += ["--arm", src["arm"]]
    if src["mask"]:
        # alpha map replaces the diffuse's (absent) alpha: composite in a temp RGBA first
        rgba = out + ".rgba.png"
        subprocess.run([PY, "-I", "-c",
                        "from PIL import Image;import sys;"
                        "d=Image.open(sys.argv[1]).convert('RGB');a=Image.open(sys.argv[2]).convert('L').resize(d.size);"
                        "d.putalpha(a);d.save(sys.argv[3])", src["diff"], src["alpha"], rgba], check=True, env=CLEAN_ENV)
        cmd[cmd.index("--diff") + 1] = rgba
        cmd.append("--alpha")
    subprocess.run(cmd, check=True, env=CLEAN_ENV, stdout=subprocess.DEVNULL)
    if src["mask"]:
        os.remove(out + ".rgba.png")
    return out


def load_scene(a, gltf_path, sources):
    """Import + clean + pre-reduce once; the result is cached as predec.blend (scans can be 17M triangles)."""
    cache = os.path.join(CACHE, a["id"], "predec.blend")
    if os.path.exists(cache) and os.path.getmtime(cache) > os.path.getmtime(gltf_path):
        bpy.ops.wm.open_mainfile(filepath=cache)
        return [o for o in bpy.context.scene.objects if o.type == "MESH"]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=gltf_path)
    objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    for o in list(bpy.context.scene.objects):
        if o.type != "MESH":
            bpy.data.objects.remove(o, do_unlink=True)
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    bpy.ops.object.make_single_user(object=True, obdata=True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    for o in objs:
        cur = tri_count(o)
        if cur > PRE_TRIS:
            md = o.modifiers.new("pre", "DECIMATE")
            md.decimate_type = "COLLAPSE"
            md.ratio = PRE_TRIS / cur
            md.use_collapse_triangulate = True
            select_only(o)
            bpy.ops.object.modifier_apply(modifier=md.name)
    for o in objs:
        apply_uv_transform(o, sources)
    bpy.ops.wm.save_as_mainfile(filepath=cache, copy=True)
    return objs


def weld(obj):
    """glTF import splits vertices at every UV/normal seam, which shatters the mesh into islands
    and makes COLLAPSE stall. Positions only: UVs live in the loops and survive."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
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


def cull_cards(obj, budget, rng):
    """Foliage cards: collapse stalls on loose cards, so drop whole islands at random and grow the
    survivors (area-compensating) until the budget is met."""
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.faces.ensure_lookup_table()
    seen = set()
    islands = []
    for f in bm.faces:
        if f.index in seen:
            continue
        stack = [f]
        seen.add(f.index)
        comp = []
        while stack:
            cf = stack.pop()
            comp.append(cf)
            for e in cf.edges:
                for nf in e.link_faces:
                    if nf.index not in seen:
                        seen.add(nf.index)
                        stack.append(nf)
        islands.append(comp)
    total = sum(len(f.verts) - 2 for f in bm.faces)
    if len(islands) < 4 or total <= budget * 1.1:
        bm.free()
        return
    order = list(range(len(islands)))
    rng.shuffle(order)
    keep = []
    kept = 0
    for i in order:
        t = sum(len(f.verts) - 2 for f in islands[i])
        if kept + t > budget * 1.15 and keep:
            continue
        keep.append(i)
        kept += t
        if kept >= budget * 0.95:
            break
    keep_set = set(keep)
    drop = [f for i, isl in enumerate(islands) if i not in keep_set for f in isl]
    grow = min(3.5, math.sqrt(total / max(1, kept)))
    for i in keep:
        vs = {v for f in islands[i] for v in f.verts}
        c = sum((v.co for v in vs), Vector()) / len(vs)
        for v in vs:
            v.co = c + (v.co - c) * grow
    bmesh.ops.delete(bm, geom=drop, context="FACES")
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context="VERTS")
    bm.to_mesh(me)
    bm.free()


def split_by_material(obj):
    select_only(obj)
    if len(obj.data.materials) <= 1:
        return [obj]
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.separate(type="MATERIAL")
    bpy.ops.object.mode_set(mode="OBJECT")
    return list(bpy.context.selected_objects)


def part_material(obj):
    if not obj.data.polygons:
        return None
    mi = obj.data.polygons[0].material_index
    return obj.data.materials[mi] if mi < len(obj.data.materials) else None


def mat_key(sources, m):
    if m is None:
        return None
    return m.name if m.name in sources else m.name.rsplit(".", 1)[0]


def main():
    import random
    a = parse_args()
    folder = os.path.join(CACHE, a["id"])
    gltf_path, gdata = load_gltf_info(folder)
    sources = mat_sources(gdata, folder)
    objs = load_scene(a, gltf_path, sources)
    rng = random.Random(7)

    for o in objs:
        if o.data.shape_keys:
            for kb in list(o.data.shape_keys.key_blocks)[::-1]:
                o.shape_key_remove(kb)
    objs.sort(key=lambda o: -tri_count(o))
    if a["pieces"] and a["keep"] > 0:
        for o in objs[a["keep"]:]:
            bpy.data.objects.remove(o, do_unlink=True)
        objs = objs[:a["keep"]]
    groups = [[o] for o in objs] if a["pieces"] else [objs]
    all_tris = sum(tri_count(o) for o in objs)

    finals = []
    for g in groups:
        select_only(g[0])
        for o in g:
            o.select_set(True)
        if len(g) > 1:
            bpy.ops.object.join()
        obj = bpy.context.view_layer.objects.active
        parts = split_by_material(obj)
        info = []
        for p in parts:
            k = mat_key(sources, part_material(p))
            info.append((p, tri_count(p), bool(k and sources.get(k, {}).get("mask"))))
        a_tot = sum(t for _, t, al in info if al)
        s_tot = sum(t for _, t, al in info if not al)
        b = a["tris"]
        a_budget = b * 0.65 if (a_tot and s_tot) else (b if a_tot else 0)
        s_budget = b - a_budget if s_tot else 0
        for p, t, al in info:
            weld(p)
            if al:
                pb = max(12, a_budget * t / max(1, a_tot))
                cull_cards(p, pb, rng)
                collapse_to(p, pb)
            else:
                pb = max(30, s_budget * t / max(1, s_tot))
                collapse_to(p, pb)
                if tri_count(p) > pb * 1.3:  # loose twigs/branches: collapse stalls, thin them out instead
                    cull_cards(p, pb, rng)
            print("PART", p.name, part_material(p).name if part_material(p) else None, "alpha" if al else "solid", t, "->", tri_count(p), "budget", int(pb))
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
        loose = [v for v in bm.verts if not v.link_faces]
        bmesh.ops.delete(bm, geom=loose, context="VERTS")
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
        finals.append(obj)

    # origin at base centre
    for obj in finals:
        vs = np.empty(len(obj.data.vertices) * 3, dtype=np.float32)
        obj.data.vertices.foreach_get("co", vs)
        vs = vs.reshape(-1, 3)
        mn, mx = vs.min(0), vs.max(0)
        c = np.array([(mn[0] + mx[0]) / 2, (mn[1] + mx[1]) / 2, mn[2]], dtype=np.float32)
        vs -= c
        obj.data.vertices.foreach_set("co", vs.reshape(-1))
        obj.data.update()
        obj.location = (0, 0, 0) if not a["pieces"] else (float(c[0]), float(c[1]), float(c[2]))
        obj.name = a["name"] if not a["pieces"] else obj.name
        obj.data.name = obj.name

    # materials: rebuild with processed textures
    tmp_dir = os.path.join(ROOT, "build", "model_tex", a["name"])
    shutil.rmtree(tmp_dir, ignore_errors=True)
    os.makedirs(tmp_dir)
    final_mat_tris = {}
    for obj in finals:
        for p in obj.data.polygons:
            m = obj.data.materials[p.material_index]
            k0 = mat_key(sources, m)
            final_mat_tris[k0] = final_mat_tris.get(k0, 0) + len(p.vertices) - 2
    total_final = max(1, sum(final_mat_tris.values()))
    new_mats = {}
    tex_report = []
    for old_name, tris in final_mat_tris.items():
        key = old_name
        src = sources.get(key)
        mat = bpy.data.materials.new(old_name + "_retro")
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
        mat.use_backface_culling = True
        if src and src["diff"]:
            share = tris / total_final
            px = a["tex"] if (share >= 0.2 or src["mask"]) else max(32, a["tex"] // 2)
            png = bake_texture(src, px, tmp_dir, old_name)
            img = bpy.data.images.load(png)
            img.colorspace_settings.name = "sRGB"
            tn = nt.nodes.new("ShaderNodeTexImage")
            tn.image = img
            tn.interpolation = "Closest"
            tn.extension = "REPEAT"
            nt.links.new(tn.outputs["Color"], bsdf.inputs["Base Color"])
            if src["mask"]:
                nt.links.new(tn.outputs["Alpha"], bsdf.inputs["Alpha"])
                mat.blend_method = "CLIP"
                mat.alpha_threshold = 0.5
                mat.use_backface_culling = False
            tex_report.append({"material": old_name, "px": list(img.size), "alpha": bool(src["mask"]), "kb": os.path.getsize(png) // 1024})
        else:
            col = (src or {"color": [0.5, 0.5, 0.5, 1]})["color"]
            bsdf.inputs["Base Color"].default_value = col
        new_mats[old_name] = mat
    for obj in finals:
        olds = [m.name for m in obj.data.materials]
        for i, n in enumerate(olds):
            obj.data.materials[i] = new_mats[mat_key(sources, bpy.data.materials[n])]

    # export
    out_path = os.path.join(ROOT, "assets", "models", a["name"] + ".glb")
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for o in finals:
        o.select_set(True)
    kw = dict(filepath=out_path, export_format="GLB", use_selection=True, export_image_format="AUTO",
              export_yup=True, export_cameras=False, export_lights=False, export_texcoords=True,
              export_normals=True, export_materials="EXPORT", export_extras=False, export_apply=False)
    try:
        bpy.ops.export_scene.gltf(export_vertex_color="NONE", **kw)
    except TypeError:
        bpy.ops.export_scene.gltf(**kw)

    tris = sum(tri_count(o) for o in finals)
    dims = [round(x, 2) for x in max((o.dimensions for o in finals), key=lambda d: d.length)]
    rep = {"name": a["name"], "id": a["id"], "tris": tris, "tex": tex_report,
           "tex_px": max([max(t["px"]) for t in tex_report] or [0]),
           "glb_kb": round(os.path.getsize(out_path) / 1024, 1), "pieces": [o.name for o in finals], "dims_m": dims,
           "source_tris": all_tris}
    os.makedirs(os.path.join(ROOT, "build", "kit_report"), exist_ok=True)
    with open(os.path.join(ROOT, "build", "kit_report", a["name"] + ".json"), "w") as f:
        json.dump(rep, f, indent=1)
    print("RESULT", json.dumps(rep))


PY = shutil.which("python3") or "/usr/bin/python3"
CLEAN_ENV = {k: v for k, v in os.environ.items() if not k.startswith("PYTHON")}
main()
