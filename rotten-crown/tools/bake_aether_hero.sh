#!/usr/bin/env bash
# Sculpt the redwood trunks in Blender and bake the close-up meshes:
#   tools/bake_aether_hero.sh   (needs GODOT and tools/setup_blender.sh)
# Writes data/trees/trunk_<style>.json (coarse trunk), data/trees/hero_<style>.res (close-up mesh).
set -euo pipefail
cd "$(dirname "$0")/.."
BL=$(tools/setup_blender.sh)
"$BL" -b --factory-startup -P tools/blender/trees/aether_trees.py -- export
"${GODOT:?set GODOT}" --headless --path . --import >/dev/null 2>&1 || true
"$GODOT" --headless --path . -s tools/bake_aether_hero.gd
