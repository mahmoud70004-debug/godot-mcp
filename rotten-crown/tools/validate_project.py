#!/usr/bin/env python3
"""Static sanity checks for the Rotten Crown Godot project.

Catches the wiring mistakes that otherwise only show up when Godot opens a
scene: missing res:// files, undeclared ExtResource/SubResource ids, broken
node parents and NodePaths, $Path / %Unique lookups that do not exist in the
scene a script is attached to, and .tres properties the script does not
declare.

Usage:  python3 tools/validate_project.py   (from the project root)
Exit code is non-zero when problems are found.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
problems: list[str] = []


def res_to_path(res: str) -> Path:
    return ROOT / res[len("res://"):]


def report(msg: str) -> None:
    problems.append(msg)


# --- Scripts -------------------------------------------------------------------

class ScriptInfo:
    def __init__(self, path: Path):
        self.path = path
        self.text = path.read_text(encoding="utf-8")
        m = re.search(r"^class_name\s+(\w+)", self.text, re.M)
        self.class_name = m.group(1) if m else None
        m = re.search(r"^extends\s+(\S+)", self.text, re.M)
        self.extends = m.group(1) if m else None
        self.vars = set(re.findall(r"^(?:@export\S*\s+)*(?:@onready\s+)?(?:static\s+)?var\s+(\w+)", self.text, re.M))
        self.vars |= set(re.findall(r"^@export\S*(?:\([^)]*\))?\s+var\s+(\w+)", self.text, re.M))
        self.dollar_paths = set(re.findall(r"\$([A-Za-z0-9_/]+)", self.text))
        self.unique_names = set(re.findall(r"%([A-Z][A-Za-z0-9_]*)", self.text))
        # Ignore format specifiers inside strings such as "%d" / "%s".
        self.unique_names = {u for u in self.unique_names if not re.fullmatch(r"[dsfxXic]", u)}


scripts: dict[str, ScriptInfo] = {}
class_map: dict[str, ScriptInfo] = {}
for gd in ROOT.rglob("*.gd"):
    if ".godot" in gd.parts:
        continue
    info = ScriptInfo(gd)
    res = "res://" + gd.relative_to(ROOT).as_posix()
    scripts[res] = info
    if info.class_name:
        if info.class_name in class_map:
            report(f"duplicate class_name {info.class_name}: {gd} and {class_map[info.class_name].path}")
        class_map[info.class_name] = info


def script_chain_vars(info: ScriptInfo | None) -> set[str]:
    seen = set()
    while info:
        seen |= info.vars
        parent = info.extends
        if parent and parent.startswith('"res://'):
            info = scripts.get(parent.strip('"'))
        else:
            info = class_map.get(parent) if parent else None
    return seen


# --- res:// references -------------------------------------------------------

for f in list(ROOT.rglob("*")):
    if f.is_dir() or ".godot" in f.parts or f.suffix not in {".gd", ".tscn", ".tres", ".godot", ".cfg", ".gdshader"}:
        continue
    for ref in re.findall(r'res://[A-Za-z0-9_./-]+', f.read_text(encoding="utf-8")):
        ref = ref.rstrip(".")
        if ref.startswith("res://build/"):
            continue  # generated, git-ignored output (sprite renders, exports)
        if not res_to_path(ref).exists():
            report(f"{f.relative_to(ROOT)}: missing file {ref}")


# --- Scenes & resources ------------------------------------------------------

HEADER = re.compile(r"^\[(\w+)(.*)\]\s*$")
ATTR = re.compile(r'(\w+)=("(?:[^"\\]|\\.)*"|PackedStringArray\([^)]*\)|ExtResource\("[^"]*"\)|\S+)')
COMMON_NODE_PROPS = {"position", "rotation", "scale", "transform", "visible", "unique_name_in_owner"}


def parse_blocks(text: str):
    blocks = []
    current = None
    for line in text.splitlines():
        m = HEADER.match(line)
        if m:
            attrs = {k: v.strip('"') for k, v in ATTR.findall(m.group(2))}
            current = {"kind": m.group(1), "attrs": attrs, "props": {}, "raw": m.group(2)}
            blocks.append(current)
        elif current is not None and " = " in line and not line.startswith((" ", "\t")):
            key, value = line.split(" = ", 1)
            current["props"][key.strip()] = value.strip()
    return blocks


scene_cache: dict[str, dict] = {}


def load_scene(res: str) -> dict:
    if res in scene_cache:
        return scene_cache[res]
    path = res_to_path(res)
    if path.suffix in (".scn", ".res"):
        # Binary (baked) scenes are opaque: no node checks, any override allowed.
        info = {"blocks": [], "ext": {}, "sub": set(), "nodes": {".": {"raw": ""}}, "unique": set(),
                "root_script": None, "root_instance": None, "text": "", "binary": True}
        scene_cache[res] = info
        return info
    text = path.read_text(encoding="utf-8")
    blocks = parse_blocks(text)
    ext = {b["attrs"].get("id"): b["attrs"] for b in blocks if b["kind"] == "ext_resource"}
    sub = {b["attrs"].get("id") for b in blocks if b["kind"] == "sub_resource"}
    nodes = {}
    unique = set()
    root_script = None
    root_instance = None
    for b in blocks:
        if b["kind"] != "node":
            continue
        name = b["attrs"]["name"]
        parent = b["attrs"].get("parent")
        if parent is None:
            node_path = "."
        elif parent == ".":
            node_path = name
        else:
            node_path = f"{parent}/{name}"
        b["path"] = node_path
        nodes[node_path] = b
        if b["props"].get("unique_name_in_owner") == "true":
            unique.add(name)
        if parent is None:
            sm = re.search(r'ExtResource\("([^"]+)"\)', b["props"].get("script", ""))
            if sm and sm.group(1) in ext:
                root_script = ext[sm.group(1)]["path"]
            im = re.search(r'instance=ExtResource\("([^"]+)"\)', b["raw"])
            if im and im.group(1) in ext:
                root_instance = ext[im.group(1)]["path"]
    info = {"blocks": blocks, "ext": ext, "sub": sub, "nodes": nodes, "unique": unique,
            "root_script": root_script, "root_instance": root_instance, "text": text}
    scene_cache[res] = info
    return info


def resolve(base: str, rel: str) -> str:
    parts = [] if base == "." else base.split("/")
    for p in rel.split("/"):
        if p == "..":
            if parts:
                parts.pop()
        elif p and p != ".":
            parts.append(p)
    return "/".join(parts) if parts else "."


def scene_has_path(scene: dict, path: str) -> bool:
    """True if path exists, descending into instanced sub-scenes when needed."""
    if path in scene["nodes"]:
        return True
    for node_path, b in scene["nodes"].items():
        im = re.search(r'instance=ExtResource\("([^"]+)"\)', b["raw"])
        if not im or im.group(1) not in scene["ext"]:
            continue
        prefix = "" if node_path == "." else node_path + "/"
        if path.startswith(prefix) and path != node_path:
            sub = load_scene(scene["ext"][im.group(1)]["path"])
            if scene_has_path(sub, path[len(prefix):]):
                return True
    return False


for f in sorted(ROOT.rglob("*.tscn")) + sorted(ROOT.rglob("*.tres")):
    if ".godot" in f.parts:
        continue
    res = "res://" + f.relative_to(ROOT).as_posix()
    scene = load_scene(res)
    rel = f.relative_to(ROOT)
    for rid in re.findall(r'ExtResource\("([^"]+)"\)', scene["text"]):
        if rid not in scene["ext"]:
            report(f"{rel}: undeclared ExtResource id {rid}")
    for sid in re.findall(r'SubResource\("([^"]+)"\)', scene["text"]):
        if sid not in scene["sub"]:
            report(f"{rel}: undeclared SubResource id {sid}")
    # Node parents and NodePath exports.
    for b in scene["blocks"]:
        if b["kind"] != "node":
            continue
        parent = b["attrs"].get("parent")
        if parent not in (None, ".") and parent not in scene["nodes"]:
            report(f"{rel}: node {b['attrs']['name']} has unknown parent '{parent}'")
        for key, value in b["props"].items():
            nm = re.fullmatch(r'NodePath\("([^"]*)"\)', value)
            if nm and nm.group(1):
                target = resolve(b["path"], nm.group(1))
                if not scene_has_path(scene, target):
                    report(f"{rel}: {b['path']}.{key} -> NodePath('{nm.group(1)}') not found")
        # Property overrides on instanced scenes must exist on the instanced root script.
        im = re.search(r'instance=ExtResource\("([^"]+)"\)', b["raw"])
        if im and im.group(1) in scene["ext"]:
            inst = load_scene(scene["ext"][im.group(1)]["path"])
            if inst.get("binary"):
                continue
            allowed = script_chain_vars(scripts.get(inst["root_script"])) | COMMON_NODE_PROPS
            for key in b["props"]:
                if key not in allowed and "/" not in key:
                    report(f"{rel}: instance {b['attrs']['name']} sets unknown property '{key}'")
        # Properties on nodes with one of our scripts (not built-in ones) are hard to
        # validate without engine metadata, but script-only names can be checked.
        sm = re.search(r'ExtResource\("([^"]+)"\)', b["props"].get("script", ""))
        if sm and sm.group(1) in scene["ext"]:
            sinfo = scripts.get(scene["ext"][sm.group(1)]["path"])
            if sinfo is None:
                continue
            for dpath in sinfo.dollar_paths:
                if not scene_has_path(scene, resolve(b["path"], dpath)):
                    report(f"{rel}: {sinfo.path.name} uses ${dpath} but node '{b['path']}' has no such child")
            if b["attrs"].get("parent") is None:
                for u in sinfo.unique_names:
                    if u not in scene["unique"]:
                        report(f"{rel}: {sinfo.path.name} uses %{u} but no unique node with that name")
    # Custom resources: every property must be declared by the script.
    if f.suffix == ".tres":
        res_block = next((b for b in scene["blocks"] if b["kind"] == "resource"), None)
        sm = re.search(r'ExtResource\("([^"]+)"\)', (res_block or {"props": {}})["props"].get("script", ""))
        if res_block and sm:
            sinfo = scripts.get(scene["ext"][sm.group(1)]["path"])
            allowed = script_chain_vars(sinfo) | {"script", "resource_name", "resource_local_to_scene"}
            for key in res_block["props"]:
                if key not in allowed:
                    report(f"{rel}: property '{key}' not declared in {sinfo.path.name if sinfo else '?'}")


# --- project.godot -------------------------------------------------------------

project = (ROOT / "project.godot").read_text(encoding="utf-8")
actions_declared = set(re.findall(r"^(\w+)=\{", project, re.M))
for res, info in scripts.items():
    for action in re.findall(r'(?:is_action_\w+|get_vector|action_press|action_release|get_axis)\(([^)]*)\)', info.text):
        for name in re.findall(r'&?"(\w+)"', action):
            if name.startswith("ui_"):
                continue
            if name not in actions_declared:
                report(f"{info.path.relative_to(ROOT)}: input action '{name}' not in project.godot")

if problems:
    print(f"{len(problems)} problem(s):")
    for p in problems:
        print("  -", p)
    sys.exit(1)
print(f"OK - {len(scripts)} scripts, {len(scene_cache)} scenes/resources checked, no problems found.")
