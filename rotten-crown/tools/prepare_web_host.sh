#!/usr/bin/env bash
# Assemble only Rotten Crown's already-exported site for an independent host.
# The game export is produced separately with tools/publish_web.sh; this script
# does not rebuild the world, Android APK, shaders, or game logic.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SITE="$ROOT/docs"
OUT="$ROOT/rotten-crown/build/netlify"

for file in index.html index.js index.wasm index.pck index.service.worker.js build.txt rotten_crown.apk; do
  test -s "$SITE/$file" || { echo "Missing or empty game export: $SITE/$file" >&2; exit 1; }
done
# This fixed output directory is under the project's ignored build directory.
rm -rf -- "$OUT"
mkdir -p "$OUT"
cp "$SITE"/index.* "$OUT/"
cp "$SITE/build.txt" "$SITE/rotten_crown.apk" "$OUT/"
python3 - "$OUT" <<'PY'
from pathlib import Path
import re
import sys

out = Path(sys.argv[1])
html = (out / "index.html").read_text(encoding="utf-8")
match = re.search(r'"index\.pck"\s*:\s*(\d+)', html)
size = (out / "index.pck").stat().st_size
if not match or int(match.group(1)) != size:
    raise SystemExit("HTML PCK size does not match index.pck; re-export the web build first")
print(f"Rotten Crown web export ready: {size} byte PCK at {out}")
PY
