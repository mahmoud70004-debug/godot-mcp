#!/usr/bin/env python3
"""Write assets/models/<name>.glb.import for every GLB (import script, LODs, no light baking).
Godot fills in uid/path on the next `--import`. Run after process_model.py / build_kit.py."""
import glob
import os
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
MODELS = os.path.join(ROOT, "assets", "models")

TEMPLATE = """[remap]

importer="scene"
importer_version=1
type="PackedScene"

[deps]

source_file="res://assets/models/{name}.glb"

[params]

nodes/root_type=""
nodes/root_name=""
nodes/apply_root_scale=true
nodes/root_scale=1.0
nodes/import_as_skeleton_bones=false
import_script/path="res://tools/assets/model_import.gd"
meshes/ensure_tangents=false
meshes/generate_lods=true
meshes/create_shadow_meshes=true
meshes/light_baking=0
meshes/lightmap_texel_size=0.2
meshes/force_disable_compression=false
skins/use_named_skins=true
animation/import=false
gltf/naming_version=1
gltf/embedded_image_handling=3
"""


def main():
    n = 0
    for p in sorted(glob.glob(os.path.join(MODELS, "*.glb"))):
        name = os.path.splitext(os.path.basename(p))[0]
        imp = p + ".import"
        if os.path.exists(imp) and "--force" not in sys.argv:
            continue  # keep Godot's uid/path; --force rewrites from the template
        with open(imp, "w") as f:
            f.write(TEMPLATE.format(name=name))
        n += 1
    print(f"wrote {n} .glb.import files (existing ones kept; --force rewrites)")


if __name__ == "__main__":
    main()
