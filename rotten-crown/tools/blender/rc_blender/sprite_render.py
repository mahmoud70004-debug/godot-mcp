"""Render a rigged character in 8 directions x animation frames for tools/pixelize_sprites.py.

Output contract (PLAN C4 + C10):
  <out>/<char>/<anim>_<dir>_<frame>.png     (RGBA, transparent background)
  <out>/<char>/<anim>_<dir>_<frame>_id.png  (material ids: value = pass_index * 16, 0 = background)
  <out>/<char>/meta.json = {"dirs", "render_px", "camera_size", "height_px", "palette", "anims",
                            "materials", "variants"}
Direction convention (PLAN C2): direction k shows the character yawed by k * TAU / dirs
counter-clockwise seen from above, k = 0 facing the camera. Blender's camera sits on -Y
(Godot's +Z) and characters face -Y, so the yaw is simply k * TAU / dirs about +Z.
"""
import json
import math
import os
import time
import urllib.request

import bpy
from mathutils import Vector

HDRI_URL = "https://dl.polyhaven.org/file/ph-assets/HDRIs/hdr/1k/%s_1k.hdr"


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def setup_render(render_px=512, samples=16):
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = samples
    sc.cycles.use_denoising = True
    sc.cycles.max_bounces = 4
    sc.cycles.diffuse_bounces = 2
    sc.cycles.glossy_bounces = 2
    sc.cycles.transparent_max_bounces = 4
    sc.render.use_persistent_data = True
    sc.render.resolution_x = sc.render.resolution_y = render_px
    sc.render.film_transparent = True
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.view_settings.view_transform = "AgX"
    sc.view_settings.look = "AgX - Medium High Contrast"
    return sc


ID_SCALE = 16.0 / 255.0


def enable_material_ids():
    """Compositor branch writing the material index pass as an 8-bit grey PNG per render."""
    sc = bpy.context.scene
    sc.view_layers[0].use_pass_material_index = True
    sc.use_nodes = True
    nt = sc.node_tree
    nt.nodes.clear()
    rl = nt.nodes.new("CompositorNodeRLayers")
    comp = nt.nodes.new("CompositorNodeComposite")
    nt.links.new(rl.outputs["Image"], comp.inputs["Image"])
    nt.links.new(rl.outputs["Alpha"], comp.inputs["Alpha"])
    mul = nt.nodes.new("CompositorNodeMath")
    mul.operation = "MULTIPLY"
    mul.inputs[1].default_value = ID_SCALE
    nt.links.new(rl.outputs["IndexMA"], mul.inputs[0])
    out = nt.nodes.new("CompositorNodeOutputFile")
    out.format.file_format = "PNG"
    out.format.color_mode = "BW"
    out.format.color_depth = "8"
    out.format.color_management = "OVERRIDE"
    out.format.view_settings.view_transform = "Standard"
    out.format.view_settings.look = "None"
    nt.links.new(mul.outputs[0], out.inputs[0])
    return out


def material_table(materials):
    """materials: list of (material, shades). Assigns pass indices 1.. and returns the meta table."""
    table = {}
    for i, (m, shades) in enumerate(materials, start=1):
        m.pass_index = i
        table[str(i)] = {"name": m.name, "shades": shades}
    return table


def world_hdri(name, cache_dir, strength=0.35, tint=(1.0, 1.0, 1.0)):
    """Poly Haven CC0 HDRI for believable reflections on metal (cached on disk)."""
    os.makedirs(cache_dir, exist_ok=True)
    path = os.path.join(cache_dir, name + "_1k.hdr")
    if not os.path.exists(path):
        urllib.request.urlretrieve(HDRI_URL % name, path)
    world = bpy.data.worlds.new("world")
    bpy.context.scene.world = world
    world.use_nodes = True
    nt = world.node_tree
    env = nt.nodes.new("ShaderNodeTexEnvironment")
    env.image = bpy.data.images.load(path)
    bg = nt.nodes["Background"]
    bg.inputs["Strength"].default_value = strength
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.blend_type = "MULTIPLY"
    mix.inputs["Factor"].default_value = 1.0
    nt.links.new(env.outputs["Color"], mix.inputs[6])
    mix.inputs[7].default_value = tuple(tint) + (1,)
    nt.links.new(mix.outputs[2], bg.inputs["Color"])


def sun(name, rotation_deg, color, energy, angle_deg=8.0):
    data = bpy.data.lights.new(name, "SUN")
    data.color = color
    data.energy = energy
    data.angle = math.radians(angle_deg)
    obj = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(obj)
    obj.rotation_euler = tuple(math.radians(a) for a in rotation_deg)
    return obj


def camera(camera_size, center_z):
    """Orthographic, slightly above eye level looking a little down (like the Godot baker)."""
    data = bpy.data.cameras.new("cam")
    data.type = "ORTHO"
    data.ortho_scale = camera_size
    obj = bpy.data.objects.new("cam", data)
    bpy.context.scene.collection.objects.link(obj)
    obj.location = Vector((0.0, -8.0, center_z + 0.55))
    direction = Vector((0.0, 0.0, center_z)) - obj.location
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = obj
    return obj


def render_character(char, root, pose_fn, anims, out_root, dirs=8, camera_size=2.7, height_px=150,
                     palette=48, only=None, dir_list=None, materials=None, variants=None):
    """anims: {name: {"frames", "fps", "loop", "duration"}}; pose_fn(anim, t) poses the rig.
    `only` limits to some anims, `dir_list` to some directions (previews)."""
    sc = bpy.context.scene
    out_dir = os.path.join(out_root, char)
    os.makedirs(out_dir, exist_ok=True)
    meta = {"dirs": dirs, "render_px": sc.render.resolution_x, "camera_size": camera_size,
            "height_px": height_px, "palette": palette, "anims": {}, "materials": materials or {},
            "variants": variants or []}
    id_out = enable_material_ids() if materials else None
    if id_out is not None:
        id_out.base_path = out_dir
    count = 0
    t_start = time.time()
    for anim, a in anims.items():
        meta["anims"][anim] = {"frames": a["frames"], "fps": a["fps"], "loop": a["loop"]}
        if only and anim not in only:
            continue
        for k in (dir_list if dir_list is not None else range(dirs)):
            root.rotation_euler.z = k * math.tau / dirs
            for f in range(a["frames"]):
                t = 0.0
                if a["frames"] > 1:
                    t = f / a["frames"] if a["loop"] else f / (a["frames"] - 1)
                pose_fn(anim, t)
                bpy.context.view_layer.update()
                name = "%s_%d_%d" % (anim, k, f)
                sc.render.filepath = os.path.join(out_dir, name + ".png")
                if id_out is not None:
                    id_out.file_slots[0].path = name + "_id"
                bpy.ops.render.render(write_still=True)
                if id_out is not None:
                    # The file output node appends the frame number.
                    os.replace(os.path.join(out_dir, "%s_id%04d.png" % (name, sc.frame_current)),
                               os.path.join(out_dir, name + "_id.png"))
                count += 1
    with open(os.path.join(out_dir, "meta.json"), "w") as fh:
        json.dump(meta, fh, indent=1)
    print("RENDERED %s: %d frames in %.1fs" % (char, count, time.time() - t_start))
    return count


def render_stills(char, root, pose_fn, spec, out_root, dir_list, dirs=8):
    """Iteration helper: spec "anim:t,anim:t" -> <out>/<char>_stills/<anim>_<t>_<dir>.png (no id maps)."""
    sc = bpy.context.scene
    out_dir = os.path.join(out_root, char + "_stills")
    os.makedirs(out_dir, exist_ok=True)
    for item in spec.split(","):
        anim, t = item.split(":")
        for k in dir_list:
            root.rotation_euler.z = k * math.tau / dirs
            pose_fn(anim, float(t))
            bpy.context.view_layer.update()
            sc.render.filepath = os.path.join(out_dir, "%s_%s_%d.png" % (anim, t, k))
            bpy.ops.render.render(write_still=True)
    print("STILLS %s -> %s" % (char, out_dir))
