#!/usr/bin/env bash
# Bake the procedural world into binary scenes (see tools/bake_world.gd).
#   GODOT=... tools/bake_world.sh [overworld|prologue]
set -euo pipefail
cd "$(dirname "$0")/.."
# A real renderer is required: under --headless the dummy RenderingServer keeps no MultiMesh
# instance data, so every baked grass patch would be saved with zero transforms.
RC_BAKE="${1:-}" xvfb-run -a -s "-screen 0 640x360x24" "$GODOT" --path . --rendering-driver opengl3 --audio-driver Dummy \
	tools/bake_world.tscn 2>&1 | grep -vE "^Godot Engine|^OpenGL API|^$" || true
