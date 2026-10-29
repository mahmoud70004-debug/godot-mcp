#!/usr/bin/env bash
# Export the Web (HTML5) build to build/web/.
#   GODOT=/path/to/godot tools/export_web.sh [release|debug]
# Requires Godot 4.4.1 + its web export templates (web_nothreads_*.zip) in
# ~/.local/share/godot/export_templates/4.4.1.stable/
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
MODE="${1:-release}"
mkdir -p build/web
rm -f build/web/*
# The launch page (custom HTML shell) inlines its fonts and stills; rebuild it first.
python3 tools/build_web_shell.py
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
"$GODOT" --headless --path . "--export-${MODE}" "Web" build/web/index.html
# Cache-busting stamp so phones never run a stale build.
date -u +"%Y-%m-%dT%H:%M:%SZ" > build/web/build.txt
ls -la build/web
