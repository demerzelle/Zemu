#!/bin/bash
# Publishes a Zemu update on GitHub Releases. Installed Android TV apps offer it on their next
# launch and install it themselves; Roku apps say it's available.
#
#   ./release.sh 1.0.2 "What changed (shown in the update prompt)"
#
# Bumps the version (Android + Roku), builds Zemu-AndroidTV-<v>.apk/.zip, Zemu-Roku-<v>.zip and Zemu-Linux-<v>.tar.gz,
# commits, tags v<v>, pushes, and creates the release with the gh CLI.
# Android only accepts the update if it's signed with the same key as the installed app, so the
# script refuses to publish an APK signed with any other key (see RELEASE_CERT_SHA256).
set -euo pipefail
cd "$(dirname "$0")"

V="${1:-}"
NOTES="${2:-}"
[[ "$V" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "usage: ./release.sh X.Y.Z [notes]"; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "Commit or stash your changes first."; exit 1; }
git rev-parse "v$V" >/dev/null 2>&1 && { echo "v$V already exists."; exit 1; }

export JAVA_HOME="${JAVA_HOME:-$HOME/Library/Java/JavaVirtualMachines/jbr-21.0.11/Contents/Home}"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
IFS=. read -r MAJOR MINOR PATCH <<<"$V"
# The key every Zemu release so far is signed with (~/.android/debug.keystore on this Mac).
RELEASE_CERT_SHA256=cc3a785bf11988545454c1329d0545c526079f202c821d93b0c1a8d80afd282c

# Version: Android versionCode must go up for Android to accept the update.
CODE=$(( $(sed -n 's/.*versionCode = \([0-9]*\).*/\1/p' app/build.gradle.kts) + 1 ))
sed -i '' -e "s/versionCode = [0-9]*/versionCode = $CODE/" -e "s/versionName = \"[^\"]*\"/versionName = \"$V\"/" app/build.gradle.kts
sed -i '' -e "s/^major_version=.*/major_version=$MAJOR/" -e "s/^minor_version=.*/minor_version=$MINOR/" -e "s/^build_version=.*/build_version=$PATCH/" roku/manifest

OUT="build/release-$V"
rm -rf "$OUT" && mkdir -p "$OUT"

./gradlew -q :app:assembleRelease
APK=app/build/outputs/apk/release/app-release.apk
# Android keeps people's setup through an update only when the new APK has the same signing key.
# A different key means "App not installed", an uninstall, and a wiped setup, so refuse to publish.
SIGNER=$("$(ls -d "$ANDROID_HOME"/build-tools/*/ | tail -1)apksigner" verify --print-certs "$APK" | sed -n 's/.*SHA-256 digest: //p' | head -1)
[ "$SIGNER" = "$RELEASE_CERT_SHA256" ] || { git checkout -- app/build.gradle.kts roku/manifest; echo "APK is signed with $SIGNER, not the release key $RELEASE_CERT_SHA256. Installed copies couldn't update. Not publishing."; exit 1; }
cp "$APK" "$OUT/Zemu-AndroidTV-$V.apk"
# Same APK under a fixed name: .../releases/latest/download/Zemu-AndroidTV.apk always gets the newest (the Downloader code).
cp "$APK" "$OUT/Zemu-AndroidTV.apk"
(cd "$OUT" && zip -q "Zemu-AndroidTV-$V.zip" "Zemu-AndroidTV-$V.apk")

(cd roku && npx --prefix tools bsc --project bsconfig.json >/dev/null && rm -f out/zemu.zip && cd out/staging && zip -qr -9 ../zemu.zip . -x '.*')
cp roku/out/zemu.zip "$OUT/Zemu-Roku-$V.zip"

# Linux: Zemu's own updater looks for Zemu-Linux-<v>.tar.gz.
./gradlew -q -p linux linuxTarball
cp "linux/build/linux/Zemu-Linux-$V.tar.gz" "$OUT/"

git commit -qam "Release $V"
git tag "v$V"
git push -q origin HEAD "v$V"
gh release create "v$V" "$OUT"/* --title "Zemu $V" --notes "${NOTES:-Zemu $V}"
echo "Published v$V. Android TV apps will offer it on their next launch."
