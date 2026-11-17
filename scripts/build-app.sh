#!/bin/bash
# Builds build/PitCrew.app from source.
#   ./scripts/build-app.sh            build only
#   ./scripts/build-app.sh --install  build, copy to Applications, launch
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP="build/PitCrew.app"
ICONSET="build/AppIcon.iconset"

echo "› Compiling (release)…"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/PitCrew"

echo "› Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/PitCrew"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# App icon: resize the 1024px master into an .iconset, then pack it into .icns.
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z "$s" "$s" Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2))
  sips -z "$d" "$d" Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc signature: enough to run locally and to use "Launch at Login".
codesign --force --sign - "$APP" >/dev/null 2>&1 || echo "  (couldn't sign; the app still runs locally)"

echo "✓ Built $APP"

if [ "${1:-}" = "--install" ]; then
  DEST="/Applications"
  [ -w "$DEST" ] || DEST="$HOME/Applications"
  mkdir -p "$DEST"

  # Quit a running copy so it can be replaced.
  osascript -e 'quit app "PitCrew"' >/dev/null 2>&1 || true
  pkill -x PitCrew >/dev/null 2>&1 || true
  sleep 1

  rm -rf "$DEST/PitCrew.app"
  cp -R "$APP" "$DEST/"
  echo "✓ Installed to $DEST/PitCrew.app"
  open "$DEST/PitCrew.app"
  echo "✓ Launched. Look for the Pit Crew panel top-right and the icon in your menu bar."
fi
