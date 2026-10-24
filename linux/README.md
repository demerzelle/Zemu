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
installs Java 17+ and mpv with apt, dnf, pacman or zypper if they're missing. `sh install.sh --uninstall`
removes it. Zemu updates itself from GitHub Releases.

## Using it

- **Keyboard or remote**: arrows move, Enter selects (hold Enter, or hold the mouse button, for a title's
  options), Esc or Backspace goes back, F11 toggles full screen. The mouse works too.
- **Playback** is in mpv, full screen: Space pauses, arrows seek, J subtitles, # audio track,
  Enter skips an intro/recap when offered, N plays the next episode, Q or Esc closes. Progress,
  Continue Watching, next-episode autoplay and falling back to the next cached stream all work as
  on Android. Trailers play in mpv too when `yt-dlp` is installed.
- **Downloads** are on: hold Enter on a stream and pick "Download for offline". Files go to
  `~/Videos/Zemu` (your XDG videos folder) and resume after network drops and restarts.
- **Configure** on an addon opens its page in your browser; paste the link it gives you into Addons.

Settings and profiles live in `~/.local/share/zemu`, caches in `~/.cache/zemu`.

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
../gradlew -p . test            # downloader and mpv tests
../gradlew -p . linuxTarball    # build/linux/Zemu-Linux-<version>.tar.gz
```
