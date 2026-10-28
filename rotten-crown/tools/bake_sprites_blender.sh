#!/usr/bin/env bash
# Render characters in Blender (tools/blender/characters/) and pixelize them into v2 sheets.
#   BLENDER=... tools/bake_sprites_blender.sh [knight villager_man villager_woman villager_musician hollow mourner]
#   (default: all). Extra args after "--" go to the character script (e.g. -- --only toast).
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build && touch build/.gdignore
chars=()
extra=()
while [ $# -gt 0 ]; do
	if [ "$1" = "--" ]; then shift; extra=("$@"); break; fi
	chars+=("$1"); shift
done
[ ${#chars[@]} -eq 0 ] && chars=(knight villager_man villager_woman villager_musician hollow mourner)
for c in "${chars[@]}"; do
	case "$c" in
		knight) script=knight.py; args=() ;;
		villager_*) script=villager.py; args=(--type "${c#villager_}") ;;
		hollow|mourner) script=creature.py; args=(--type "$c") ;;
		*) echo "unknown character $c" >&2; exit 1 ;;
	esac
	"$BLENDER" -b --factory-startup --python "tools/blender/characters/$script" -- "${args[@]}" ${extra[@]+"${extra[@]}"} 2>&1 \
		| grep -E "RENDERED|Traceback|Error" || true
	python3 tools/pixelize_sprites.py "$c"
done
