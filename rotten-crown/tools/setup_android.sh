#!/usr/bin/env bash
# Prepare everything needed to export an Android APK with Godot 4.7.1 (idempotent).
#   tools/setup_android.sh [install_dir]     (default: $HOME/.cache/android)
#
# Installs / configures:
#   * a JDK >= 17 (Godot 4.7 recommends 17 and supports newer ones). An existing
#     JDK (with keytool + jarsigner) of version >= 17 is reused, e.g. the preinstalled 21;
#     otherwise Temurin 17 is downloaded into <install_dir>/jdk-17.
#   * Android SDK (cmdline-tools, platform-tools, build-tools;36.0.0, platforms;android-36)
#     in <install_dir>/sdk, licences accepted non-interactively. The prebuilt-template
#     export (gradle build OFF) only really needs apksigner/zipalign from build-tools.
#   * the Android members of the Godot 4.7.1 export templates in
#     ~/.local/share/godot/export_templates/4.7.1.stable/
#   * the standard Android DEBUG keystore (alias androiddebugkey, password android).
#     It is public knowledge, not a secret, and must NOT be committed.
#   * Godot editor settings (export/android/*) in ~/.config/godot/editor_settings-4.7.tres,
#     merged without touching other settings.
set -euo pipefail

VERSION="4.7.1"
BASE="https://github.com/godotengine/godot/releases/download/${VERSION}-stable"
DIR="${1:-$HOME/.cache/android}"
SDK="$DIR/sdk"
TEMPLATES="$HOME/.local/share/godot/export_templates/${VERSION}.stable"
KEYSTORE="$HOME/.local/share/godot/keystores/debug.keystore"
SETTINGS="$HOME/.config/godot/editor_settings-4.7.tres"
CMDLINE_URL="https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip"
BUILD_TOOLS="36.0.0"
PLATFORM="android-36"
TOOLS_DIR="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$DIR" "$TEMPLATES" "$(dirname "$KEYSTORE")" "$(dirname "$SETTINGS")"

log() { echo "[setup_android] $*" >&2; }

# ---------------------------------------------------------------- JDK
jdk_ok() { # $1 = JAVA_HOME candidate
	[ -x "$1/bin/keytool" ] && [ -x "$1/bin/jarsigner" ] && [ -x "$1/bin/java" ] || return 1
	local v
	v="$("$1/bin/java" -version 2>&1 | sed -n 's/.*version "\([0-9]*\).*/\1/p' | head -1)"
	[ -n "$v" ] && [ "$v" -ge 17 ]
}
JDK=""
for c in "$DIR/jdk-17" "${JAVA_HOME:-}" /usr/lib/jvm/java-21-openjdk-amd64 /usr/lib/jvm/java-17-openjdk-amd64; do
	if [ -n "$c" ] && jdk_ok "$c"; then JDK="$c"; break; fi
done
if [ -z "$JDK" ]; then
	log "downloading Temurin JDK 17"
	mkdir -p "$DIR/jdk-17.tmp"
	curl -fsSL -o "$DIR/jdk.tgz" "https://api.adoptium.net/v3/binary/latest/17/ga/linux/x64/jdk/hotspot/normal/eclipse"
	tar -xzf "$DIR/jdk.tgz" -C "$DIR/jdk-17.tmp" --strip-components=1
	rm -rf "$DIR/jdk-17" "$DIR/jdk.tgz"
	mv "$DIR/jdk-17.tmp" "$DIR/jdk-17"
	JDK="$DIR/jdk-17"
fi
export JAVA_HOME="$JDK"
export PATH="$JDK/bin:$PATH"
log "JDK: $JDK"

# ---------------------------------------------------------------- Android SDK
SDKMGR="$SDK/cmdline-tools/latest/bin/sdkmanager"
if [ ! -x "$SDKMGR" ]; then
	log "downloading Android cmdline-tools"
	mkdir -p "$SDK/cmdline-tools" "$DIR/cl.tmp"
	curl -fsSL -o "$DIR/cmdline-tools.zip" "$CMDLINE_URL"
	unzip -q -o "$DIR/cmdline-tools.zip" -d "$DIR/cl.tmp"
	rm -rf "$SDK/cmdline-tools/latest"
	mv "$DIR/cl.tmp/cmdline-tools" "$SDK/cmdline-tools/latest"
	rm -rf "$DIR/cl.tmp" "$DIR/cmdline-tools.zip"
fi
if [ ! -d "$SDK/build-tools/$BUILD_TOOLS" ] || [ ! -d "$SDK/platforms/$PLATFORM" ] || [ ! -x "$SDK/platform-tools/adb" ]; then
	log "accepting licences and installing SDK packages"
	yes | "$SDKMGR" --sdk_root="$SDK" --licenses >/dev/null 2>&1 || true
	yes | "$SDKMGR" --sdk_root="$SDK" "platform-tools" "build-tools;$BUILD_TOOLS" "platforms;$PLATFORM" 2>&1 | tr "\r" "\n" | grep -E "^(Warning|Error|Failed)|100%" >&2 || true
fi
[ -f "$SDK/build-tools/$BUILD_TOOLS/apksigner" ] || { log "SDK install failed"; exit 1; }

# ---------------------------------------------------------------- export templates
if [ ! -f "$TEMPLATES/android_release.apk" ] || [ ! -f "$TEMPLATES/android_debug.apk" ] \
	|| [ ! -f "$TEMPLATES/android_source.zip" ] || [ ! -f "$TEMPLATES/version.txt" ]; then
	log "fetching Android export templates (~450 MB) via HTTP ranges"
	python3 -I "$TOOLS_DIR/fetch_zip_members.py" "$BASE/Godot_v${VERSION}-stable_export_templates.tpz" "$TEMPLATES" \
		templates/version.txt templates/android_release.apk templates/android_debug.apk templates/android_source.zip >&2
fi

# ---------------------------------------------------------------- debug keystore
if [ ! -f "$KEYSTORE" ]; then
	log "creating debug keystore"
	keytool -genkeypair -keystore "$KEYSTORE" -storepass android -keypass android \
		-alias androiddebugkey -keyalg RSA -keysize 2048 -validity 10000 \
		-dname "CN=Android Debug,O=Android,C=US" >/dev/null 2>&1
fi

# ---------------------------------------------------------------- editor settings
# Godot creates the file on first editor start; create a minimal one if absent.
if [ ! -f "$SETTINGS" ]; then
	printf '[gd_resource type="EditorSettings" format=3]\n\n[resource]\n' > "$SETTINGS"
fi
python3 -I - "$SETTINGS" "$JDK" "$SDK" "$KEYSTORE" <<'PY'
import re, sys
path, jdk, sdk, ks = sys.argv[1:]
want = {
    "export/android/java_sdk_path": jdk,
    "export/android/android_sdk_path": sdk,
    "export/android/debug_keystore": ks,
    "export/android/debug_keystore_user": "androiddebugkey",
    "export/android/debug_keystore_pass": "android",
}
text = open(path).read()
for key, val in want.items():
    line = f'{key} = "{val}"'
    pat = re.compile(r'^' + re.escape(key) + r' = .*$', re.M)
    if pat.search(text):
        text = pat.sub(lambda m: line, text)
    else:
        text = text.rstrip("\n") + "\n" + line + "\n"
open(path, "w").write(text)
PY

cat >&2 <<MSG

[setup_android] done.
  JAVA_HOME                      = $JDK
  ANDROID_HOME (SDK)             = $SDK   (build-tools $BUILD_TOOLS, platform $PLATFORM)
  export templates               = $TEMPLATES
  debug keystore                 = $KEYSTORE (alias androiddebugkey, pass android; do not commit)
  Godot editor settings          = $SETTINGS
Export with:  GODOT=\$HOME/.cache/godot-$VERSION/Godot_v$VERSION-stable_linux.x86_64 tools/export_android.sh [release|debug]
MSG
echo "$SDK"
