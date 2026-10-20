#!/usr/bin/env bash
# Builds an unsigned Zemu.ipa for sideloading (AltStore, SideStore, Sideloadly sign it with your Apple ID).
# Needs full Xcode (xcode-select -p should point into Xcode.app) and XcodeGen (brew install xcodegen).
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate --quiet
xcodebuild -quiet -project Zemu.xcodeproj -scheme Zemu -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  build

APP=build/Build/Products/Release-iphoneos/Zemu.app
rm -rf build/ipa && mkdir -p build/ipa/Payload
cp -R "$APP" build/ipa/Payload/
(cd build/ipa && zip -qry ../../Zemu.ipa Payload)
echo "→ $(pwd)/Zemu.ipa ($(du -h Zemu.ipa | cut -f1))"
