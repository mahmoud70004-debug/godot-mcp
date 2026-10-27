#!/usr/bin/env bash
# Render review frames with the same renderer the web build uses (OpenGL /
# Compatibility) on a virtual display. Each shot is "name:x,y,z,yaw,pitch".
#   GODOT=... tools/render_shots.sh out_dir scene.tscn "spawn:1.2,0,29,0,0" ...
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="$1"; SCENE="$2"; shift 2
mkdir -p "$OUT"
for shot in "$@"; do
	name="${shot%%:*}"; pose="${shot#*:}"
	tmp="$(mktemp -d)"
	RC_SHOT="$pose" timeout 180 xvfb-run -a -s "-screen 0 1280x720x24" "$GODOT" --path . --rendering-driver opengl3 \
		--write-movie "$tmp/f.png" --fixed-fps 10 --quit-after 30 "$SCENE" >/dev/null 2>&1 || true
	last="$(ls "$tmp"/f*.png | tail -1)"
	cp "$last" "$OUT/$name.png"
	rm -rf "$tmp"
	echo "$OUT/$name.png"
done
