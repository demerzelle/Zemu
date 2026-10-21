#!/bin/bash
# Publishes a Zemu update on GitHub Releases. Installed Android TV apps offer it on their next
# launch and install it themselves; Roku apps say it's available.
#
#   ./release.sh 1.0.2 "What changed (shown in the update prompt)"
#
# Bumps the version (Android + Roku), builds Zemu-AndroidTV-<v>.apk/.zip and Zemu-Roku-<v>.zip,
# commits, tags v<v>, pushes, and creates the release with the gh CLI.
# Android only accepts the update if it's signed with the same key as the installed app: build
# every release on this Mac (its ~/.android/debug.keystore) or switch both to one release key.
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

# Version: Android versionCode must go up for Android to accept the update.
CODE=$(( $(sed -n 's/.*versionCode = \([0-9]*\).*/\1/p' app/build.gradle.kts) + 1 ))
sed -i '' -e "s/versionCode = [0-9]*/versionCode = $CODE/" -e "s/versionName = \"[^\"]*\"/versionName = \"$V\"/" app/build.gradle.kts
sed -i '' -e "s/^major_version=.*/major_version=$MAJOR/" -e "s/^minor_version=.*/minor_version=$MINOR/" -e "s/^build_version=.*/build_version=$PATCH/" roku/manifest

OUT="build/release-$V"
rm -rf "$OUT" && mkdir -p "$OUT"

./gradlew -q :app:assembleRelease
cp app/build/outputs/apk/release/app-release.apk "$OUT/Zemu-AndroidTV-$V.apk"
(cd "$OUT" && zip -q "Zemu-AndroidTV-$V.zip" "Zemu-AndroidTV-$V.apk")

(cd roku && npx --prefix tools bsc --project bsconfig.json >/dev/null && rm -f out/zemu.zip && cd out/staging && zip -qr -9 ../zemu.zip . -x '.*')
cp roku/out/zemu.zip "$OUT/Zemu-Roku-$V.zip"

git commit -qam "Release $V"
git tag "v$V"
git push -q origin HEAD "v$V"
gh release create "v$V" "$OUT"/* --title "Zemu $V" --notes "${NOTES:-Zemu $V}"
echo "Published v$V. Android TV apps will offer it on their next launch."
