#!/usr/bin/env bash
# Pre-render character sprites and turn them into pixel-art sheets.
#   GODOT=... tools/bake_sprites.sh [knight,villager,hollow,mourner]   (default: all)
set -euo pipefail
cd "$(dirname "$0")/.."
CHARS="${1:-}"
RC_BAKE_CHARS="$CHARS" xvfb-run -a -s "-screen 0 1280x720x24" "$GODOT" --path . --rendering-driver opengl3 \
	tools/sprite_baker/sprite_baker.tscn 2>&1 | grep -E "baked|SPRITE_BAKE_DONE|ERROR" || true
if [ -f tools/pixelize_sprites.py ]; then
	python3 tools/pixelize_sprites.py ${CHARS//,/ }
fi
