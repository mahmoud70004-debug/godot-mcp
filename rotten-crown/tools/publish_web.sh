#!/usr/bin/env bash
# Export the Web build and copy it to <repo>/docs, which GitHub Pages serves:
#   https://mahmoud70004-debug.github.io/godot-mcp/
#   GODOT=$(tools/setup_godot.sh) tools/publish_web.sh
# Then commit docs/ and push. The engine .wasm is byte-identical between
# exports, so git stores it once; only the small .pck changes per build.
set -euo pipefail
cd "$(dirname "$0")/.."
tools/export_web.sh release
SITE="../docs"
mkdir -p "$SITE"
find "$SITE" -maxdepth 1 -type f -name 'index*' -delete
cp build/web/* "$SITE/"
touch "$SITE/.nojekyll"
echo "Published $(cat build/web/build.txt) to $(cd "$SITE" && pwd)"
