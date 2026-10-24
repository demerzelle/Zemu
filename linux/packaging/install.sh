#!/bin/sh
# Installs Zemu for the current user (no root needed except to install Java and mpv).
#   sh install.sh             install, plus Java 17+ and mpv through your package manager
#   sh install.sh --no-deps   install only (used by Zemu's own updater)
#   sh install.sh --uninstall remove Zemu (your profiles and downloads are kept)
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
APP="$HOME/.local/share/zemu-app"
BIN="$HOME/.local/bin"
DESKTOP="$HOME/.local/share/applications/zemu.desktop"

if [ "${1:-}" = "--uninstall" ]; then
    rm -rf "$APP" "$BIN/zemu" "$DESKTOP"
    echo "Zemu removed. Settings stay in ~/.local/share/zemu and downloads in ~/Videos/Zemu."
    exit 0
fi

java_ok() {
    [ -x "$APP/jre/bin/java" ] && return 0
    command -v java >/dev/null 2>&1 || return 1
    v=$(java -version 2>&1 | sed -n 's/.*version "\([0-9]*\).*/\1/p' | head -1)
    [ "${v:-0}" -ge 17 ]
}

# No Java and no way to install one system-wide: a private Java 21 (Eclipse Temurin) just for Zemu.
fetch_jre() {
    case "$(uname -m)" in x86_64) a=x64 ;; aarch64|arm64) a=aarch64 ;; *) return 1 ;; esac
    echo "Downloading Java for Zemu (about 50 MB)..."
    mkdir -p "$APP/jre"
    curl -fL$([ -t 2 ] && echo "#" || echo sS) "https://api.adoptium.net/v3/binary/latest/21/ga/linux/$a/jre/hotspot/normal/eclipse" \
        | tar -xz -C "$APP/jre" --strip-components=1
}

if [ "${1:-}" != "--no-deps" ]; then
    need=""
    java_ok || need="java"
    command -v mpv >/dev/null 2>&1 || need="$need mpv"
    # Only when someone can type the sudo password (or it isn't needed); else a private Java below.
    if [ -n "$need" ] && { [ -t 0 ] || sudo -n true 2>/dev/null; }; then
        echo "Installing:$need (asks for your password)"
        SUDO=""; [ "$(id -u)" -ne 0 ] && SUDO=sudo
        if command -v apt-get >/dev/null 2>&1; then
            $SUDO apt-get update -q
            # yt-dlp lets mpv play trailers; it's optional.
            $SUDO apt-get install -y openjdk-17-jre mpv || $SUDO apt-get install -y default-jre mpv
            $SUDO apt-get install -y yt-dlp 2>/dev/null || true
        elif command -v dnf >/dev/null 2>&1; then
            $SUDO dnf install -y java-17-openjdk mpv yt-dlp || $SUDO dnf install -y java-latest-openjdk mpv
        elif command -v pacman >/dev/null 2>&1; then
            $SUDO pacman -S --needed --noconfirm jre-openjdk mpv yt-dlp
        elif command -v zypper >/dev/null 2>&1; then
            $SUDO zypper install -y java-17-openjdk mpv yt-dlp
        else
            echo "Install mpv with your package manager to play videos."
        fi
    fi
fi
java_ok || fetch_jre || { echo "Couldn't get Java. Install Java 17 or newer, then run this again."; exit 1; }
command -v mpv >/dev/null 2>&1 || echo "Note: install mpv to play videos (e.g. sudo apt install mpv)."

mkdir -p "$APP/bin" "$BIN" "$(dirname "$DESKTOP")"
cp "$HERE/zemu.jar" "$HERE/zemu.png" "$APP/"
cat > "$APP/bin/zemu" <<'LAUNCH'
#!/bin/sh
# Tuned for slow PCs: one GC thread, a capped heap and quick JIT keep CPU and RAM low.
JAVA=java; [ -x "$HOME/.local/share/zemu-app/jre/bin/java" ] && JAVA="$HOME/.local/share/zemu-app/jre/bin/java"
exec "$JAVA" -Xss2m -Xmx512m -XX:+UseSerialGC -XX:TieredStopAtLevel=1 -Dsun.java2d.uiScale.enabled=true \
    -jar "$HOME/.local/share/zemu-app/zemu.jar" "$@"
LAUNCH
chmod +x "$APP/bin/zemu"
ln -sf "$APP/bin/zemu" "$BIN/zemu"
sed -e "s#@BIN@#$APP/bin/zemu#" -e "s#@ICON@#$APP/zemu.png#" "$HERE/zemu.desktop" > "$DESKTOP"
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database -q "$(dirname "$DESKTOP")" || true
echo "Zemu installed. Open it from your apps menu, or run: zemu"
