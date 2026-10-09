#!/bin/bash
# Builds Zemu.app (release) into ./build. libmpv and its dependencies are copied into the app
# so it runs on Macs without Homebrew. Pass --no-mpv to skip that (the app then uses mpv from
# Homebrew if present, or AVPlayer).
set -euo pipefail
cd "$(dirname "$0")/.."

BUNDLE_MPV=1
[[ "${1:-}" == "--no-mpv" ]] && BUNDLE_MPV=0

swift build -c release --product Zemu
BIN="$(swift build -c release --product Zemu --show-bin-path)/Zemu"

APP=build/Zemu.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN" "$APP/Contents/MacOS/Zemu"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/logo_mark.png Resources/logo_wordmark.png "$APP/Contents/Resources/"

# App icon from the 1024px master.
ICONSET=build/AppIcon.iconset
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
# macOS icons leave a margin around the artwork.
sips -z 824 824 Resources/AppIcon-1024.png --out build/icon-824.png >/dev/null
sips --padToHeightWidth 1024 1024 build/icon-824.png --out build/icon-1024.png >/dev/null
for s in 16 32 128 256 512; do
  sips -z $s $s build/icon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) build/icon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

if [[ $BUNDLE_MPV == 1 ]]; then
  MPV_LIB=""
  for p in /opt/homebrew/lib/libmpv.2.dylib /usr/local/lib/libmpv.2.dylib; do [[ -f $p ]] && MPV_LIB=$p && break; done
  if [[ -n "$MPV_LIB" ]]; then
    python3 scripts/bundle_dylibs.py "$APP/Contents/Frameworks" "$MPV_LIB"
  else
    echo "warning: libmpv not found (brew install mpv); the app will fall back to AVPlayer" >&2
  fi
fi

# Ad-hoc signature so macOS runs the app and keeps its permissions (notifications) between launches.
codesign --force --sign - "$APP/Contents/Frameworks/"*.dylib 2>/dev/null || true
codesign --force --sign - --options runtime --entitlements Resources/Zemu.entitlements "$APP"
echo "Built $APP ($(du -sh "$APP" | cut -f1))"
