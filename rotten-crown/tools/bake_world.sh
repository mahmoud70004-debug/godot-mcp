#!/usr/bin/env bash
# Bake the procedural world into binary scenes (see tools/bake_world.gd).
#   GODOT=... tools/bake_world.sh [overworld|prologue]
set -euo pipefail
cd "$(dirname "$0")/.."
RC_BAKE="${1:-}" "$GODOT" --headless --path . tools/bake_world.tscn 2>&1 | grep -vE "^Godot Engine|^$" || true
