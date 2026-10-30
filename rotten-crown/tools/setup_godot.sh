#!/usr/bin/env bash
# Download Godot 4.7.1 (Linux) and ONLY its web export templates.
#   tools/setup_godot.sh [install_dir]     -> prints the path to the godot binary
set -euo pipefail
VERSION="4.7.1"
DIR="${1:-$HOME/.cache/godot-$VERSION}"
BASE="https://github.com/godotengine/godot/releases/download/${VERSION}-stable"
BIN="$DIR/Godot_v${VERSION}-stable_linux.x86_64"
TEMPLATES="$HOME/.local/share/godot/export_templates/${VERSION}.stable"
mkdir -p "$DIR" "$TEMPLATES"
if [ ! -x "$BIN" ]; then
	curl -sSL -o "$DIR/godot.zip" "$BASE/Godot_v${VERSION}-stable_linux.x86_64.zip"
	unzip -q -o "$DIR/godot.zip" -d "$DIR" && rm "$DIR/godot.zip"
fi
if [ ! -f "$TEMPLATES/web_nothreads_release.zip" ]; then
	python3 -I "$(dirname "$0")/fetch_zip_members.py" "$BASE/Godot_v${VERSION}-stable_export_templates.tpz" "$TEMPLATES" \
		templates/version.txt templates/web_nothreads_release.zip templates/web_nothreads_debug.zip >&2
fi
echo "$BIN"
