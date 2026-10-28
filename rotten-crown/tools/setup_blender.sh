#!/usr/bin/env bash
# Download Blender 4.2 LTS (Linux x64) for the offline art pipeline (tools/blender/).
#   tools/setup_blender.sh [install_dir]     -> prints the path to the blender binary
# Cycles renders on the CPU; Eevee needs a GPU/EGL and is not used.
set -euo pipefail
VERSION="4.2.3"
DIR="${1:-$HOME/.cache/blender-$VERSION}"
BIN="$DIR/blender-$VERSION-linux-x64/blender"
if [ ! -x "$BIN" ]; then
	mkdir -p "$DIR"
	curl -sSL "https://download.blender.org/release/Blender4.2/blender-$VERSION-linux-x64.tar.xz" | tar -xJ -C "$DIR"
fi
echo "$BIN"
