#!/usr/bin/env bash
# Builds an unsigned Zemu.ipa for sideloading (AltStore, SideStore, Sideloadly sign it with your Apple ID).
# Needs full Xcode (xcode-select -p should point into Xcode.app) and XcodeGen (brew install xcodegen).
set -euo pipefail
cd "$(dirname "$0")/.."

# `build-ipa.sh tv` builds the Apple TV app (ZemuTV.ipa) instead.
if [ "${1:-}" = tv ]; then
  SCHEME=ZemuTV PLATFORM=tvOS SDK=appletvos
else
  SCHEME=Zemu PLATFORM=iOS SDK=iphoneos
fi

xcodegen generate --quiet
xcodebuild -quiet -project Zemu.xcodeproj -scheme "$SCHEME" -configuration Release \
  -destination "generic/platform=$PLATFORM" -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  build

APP=build/Build/Products/Release-$SDK/Zemu.app
rm -rf build/ipa && mkdir -p build/ipa/Payload
cp -R "$APP" build/ipa/Payload/
(cd build/ipa && zip -qry "../../$SCHEME.ipa" Payload)
echo "→ $(pwd)/$SCHEME.ipa ($(du -h "$SCHEME.ipa" | cut -f1))"
