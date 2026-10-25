# Zemu for Linux

The Android TV app's own Kotlin code, running on the desktop with Compose Multiplatform. Everything
the Android app does is here except the animated themes (left out to keep it light) and a few
things only Android has: voice search, the TV home-screen row and the phone widget. Built to stay
smooth on slow PCs.

## Install

```bash
tar -xzf Zemu-Linux-<version>.tar.gz && sh zemu/install.sh
```

Installs into `~/.local/share/zemu-app`, adds Zemu to the apps menu and `~/.local/bin/zemu`, and
installs mpv and Java 17+ with apt, dnf, pacman or zypper if they're missing (without root, it
downloads a private Java just for Zemu). `sh install.sh --uninstall` removes it. Zemu updates itself
from GitHub Releases.

## Using it

- **Keyboard, mouse or Xbox controller.** Arrows / D-pad / left stick move, Enter or A selects,
  Esc, Backspace, B or the mouse's back button go back, F11 toggles full screen. Right-click a card
  or an episode (or hold Enter / A, or press X) for its options. Y opens Search. Pages without the
  side menu have a Back button in the top-left corner.
- **Playback** happens inside Zemu's window, with mpv doing the decoding: Space pauses, Enter (A)
  pauses or skips an intro/recap when offered, left/right (D-pad) seek 10 s, LB/RB 30 s, up/down
  change the volume, J (X) subtitles, A key (Y) audio track, N (Menu) next episode, M mute, F full
  screen, Esc (B) closes. Progress, Continue Watching, next-episode autoplay and falling back to
  the next cached stream all work as on Android. Trailers play in mpv when `yt-dlp` is installed.
- **Downloads** are on. Hold Enter on a stream for "Download for offline", use "⬇ Download season"
  next to the season buttons, or "Download" in a card's or episode's menu. Every download asks
  first and shows where it goes, with Change folder. The default folder is set in Settings →
  Downloads (your XDG videos folder's Zemu subfolder until you pick one); shows are saved as
  `<Show>/Season N/`. Downloads resume after network drops and restarts.
- **Configure** on an addon opens its page in your browser; paste the link it gives you into Addons.

Settings and profiles live in `~/.local/share/zemu`, caches in `~/.cache/zemu`.

## If videos keep freezing

Almost always the network: a debrid stream needs roughly 5–40 Mbit/s for 1080p. Check with
`curl -o /dev/null -w '%{speed_download}\n' https://speed.cloudflare.com/__down?bytes=50000000`
(bytes per second; 1 MB/s ≈ 8 Mbit/s). Ethernet beats Wi-Fi. On older Macs with Broadcom Wi-Fi
(BCM43xx), Ubuntu's built-in `b43` driver only manages 802.11g speeds; Broadcom's driver is much
faster: `sudo apt install broadcom-sta-dkms`, then reboot. On Intel graphics up to 2015, also
install `i965-va-driver` so H.264 is decoded by the GPU. Until then, filter streams to 720p in
Settings, or download first and watch the download.

## Light on slow machines

Animated themes and hero trailers are off, poster cache is small with no crossfades, focus changes
aren't animated, and the JVM runs with a 512 MB heap, the serial GC and quick JIT. mpv uses hardware
decoding when the GPU has it and cheap scalers; "Best for this TV" ranks HEVC/AV1 lower when the
GPU can't decode them (detected with `vainfo`).

## Build

JDK 17–21. The build compiles `../app/src/main/java` directly; Android-only files are replaced by
the ones in `src/main/kotlin` (listed in `build.gradle.kts`), and a few lines are patched at build
time (`patches` in `build.gradle.kts`, which fails the build if one stops matching).

```bash
../gradlew -p . run             # run it
../gradlew -p . test            # downloader, download planning and mpv tests
../gradlew -p . linuxTarball    # build/linux/Zemu-Linux-<version>.tar.gz
```
