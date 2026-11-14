#!/usr/bin/env bash
# Export the Web (HTML5) build to build/web/.
#   GODOT=/path/to/godot tools/export_web.sh [release|debug]
# Requires Godot 4.7.1 + its web export templates (web_nothreads_*.zip) in
# ~/.local/share/godot/export_templates/4.7.1.stable/
# The build label shown on the title screens (V7, V8, ...) is config/build_label in project.godot:
# bump it when a new numbered update ships. The UTC build stamp is written here on every export.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
MODE="${1:-release}"
mkdir -p build/web
rm -f build/web/*
# One stamp per build: project setting (read by the game's title screen), the launch page and build.txt.
STAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
sed -i "s|^config/build_stamp=.*|config/build_stamp=\"${STAMP}\"|" project.godot
# The launch page (custom HTML shell) inlines its fonts and stills; rebuild it first.
python3 tools/build_web_shell.py
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
"$GODOT" --headless --path . "--export-${MODE}" "Web" build/web/index.html
echo "$STAMP" > build/web/build.txt
# Godot's PWA service worker serves cached files first and lets a new worker wait until every tab
# is closed, so a phone keeps an old build for days. Make a new worker take over at once and
# fetch its files past the HTTP cache.
python3 - <<'PY'
import pathlib
p = pathlib.Path("build/web/index.service.worker.js")
s = p.read_text(encoding="utf-8")
install_old = "event.waitUntil(caches.open(CACHE_NAME).then((cache) => cache.addAll(CACHED_FILES)));"
install_new = "self.skipWaiting();\n\tevent.waitUntil(caches.open(CACHE_NAME).then((cache) => cache.addAll(CACHED_FILES.map((f) => new Request(f, { cache: 'reload' })))));"
activate_old = "return ('navigationPreload' in self.registration) ? self.registration.navigationPreload.enable() : Promise.resolve();\n\t}));"
activate_new = "return ('navigationPreload' in self.registration) ? self.registration.navigationPreload.enable() : Promise.resolve();\n\t}).then(() => self.clients.claim()));"
for old, new in ((install_old, install_new), (activate_old, activate_new)):
    if old not in s:
        raise SystemExit("export_web: service worker template changed, update the patch in tools/export_web.sh")
    s = s.replace(old, new, 1)
p.write_text(s, encoding="utf-8")
PY
ls -la build/web
