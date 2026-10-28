#!/usr/bin/env bash
# Pre-render character sprites and turn them into pixel-art sheets.
#   GODOT=... tools/bake_sprites.sh [knight,villager,hollow,mourner]   (default: all)
set -euo pipefail
cd "$(dirname "$0")/.."
# Raw renders must never be imported (or exported) as project textures.
mkdir -p build && touch build/.gdignore
CHARS="${1:-}"
RC_BAKE_CHARS="$CHARS" xvfb-run -a -s "-screen 0 1280x720x24" "$GODOT" --path . --rendering-driver opengl3 --audio-driver Dummy \
	tools/sprite_baker/sprite_baker.tscn 2>&1 | grep -E "baked|SPRITE_BAKE_DONE|ERROR" || true
if [ -f tools/pixelize_sprites.py ]; then
	# A character with variants bakes into <name>_0, <name>_1, ... raw folders.
	targets=()
	for c in ${CHARS//,/ }; do
		for d in build/sprites_raw/"$c" build/sprites_raw/"$c"_*; do
			[ -d "$d" ] && targets+=("$(basename "$d")")
		done
	done
	python3 tools/pixelize_sprites.py ${targets[@]+"${targets[@]}"}
fi
