#!/usr/bin/env bash
# Export the Android APK to build/android/rotten_crown.apk using the "Android" preset.
#   GODOT=/path/to/godot tools/export_android.sh [release|debug]
# Requires tools/setup_android.sh to have been run (JDK, SDK, templates, keystore, editor settings).
#
# NOTE: the release build is signed with the standard Android DEBUG keystore. That is fine for
# a sideload test build (adb install / download from the Pages site) but it is NOT a Play Store
# signature; a real store release needs its own private keystore (never commit it).
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
MODE="${1:-release}"
case "$MODE" in release | debug) ;; *) echo "usage: $0 [release|debug]" >&2; exit 2 ;; esac
KEYSTORE="${ANDROID_DEBUG_KEYSTORE:-$HOME/.local/share/godot/keystores/debug.keystore}"
[ -f "$KEYSTORE" ] || { echo "missing $KEYSTORE; run tools/setup_android.sh" >&2; exit 1; }
export GODOT_ANDROID_KEYSTORE_DEBUG_PATH="$KEYSTORE"
export GODOT_ANDROID_KEYSTORE_DEBUG_USER="androiddebugkey"
export GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD="android"
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$KEYSTORE"
export GODOT_ANDROID_KEYSTORE_RELEASE_USER="androiddebugkey"
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="android"
OUT="build/android/rotten_crown.apk"
mkdir -p build/android
rm -f "$OUT" "$OUT.idsig"
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
"$GODOT" --headless --path . "--export-${MODE}" "Android" "$OUT"
ls -la build/android
