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
  or an episode (or hold Enter / A, or press X) for its options. Clicking anywhere off a menu closes it. Y opens Search. Pages without the
  side menu have a Back button in the top-left corner. Resting the mouse on a poster for 3 seconds
  shows it at the top of the page.
- **Scrolling rows with the mouse**: arrow buttons at a row's ends, or hovering near an end
  scrolls it smoothly (Settings → Browsing → Scrolling rows with the mouse, with the hover speed). Only while the mouse is
  in use.
- **Top 10 Today** rows: movies and series on Home, each on its own page, anime on Anime. With a
  TMDB key (Settings) they're TMDB's trending today; without one, Cinemeta's popular titles. Anime
  is Kitsu's trending list.
- **Playback** uses Zemu's own player, the same as on Android TV (seek bar with intro/credits
  marks, audio and subtitle tracks, speed, picture size, sleep timer, skip intro, next episode),
  drawn over mpv's video inside Zemu's window. Enter (A) pauses and opens the controls, left/right
  (D-pad) scrub, Esc (B) or the Back button in the top bar closes; Space pauses, F full screen, M mute, N next episode, J or S
  subtitles, A audio track; on a controller LB/RB jump 10 s, X/Y change subtitles/audio and Menu
  plays the next episode. With a controller connected, its buttons are shown under the controls.
  Right-clicking Subtitles (or holding Enter on it) opens its menu; Subtitle position… at the top moves the subtitles up or down (↑/↓) with a live preview, e.g.
  off text burned into the picture or into the black bars.
- **Full screen** (F11, Alt+Enter, or the player's Full screen button) covers the whole display,
  top bar and dock included; there the mouse pointer hides after 5 seconds without moving. The
  window can also be resized down to 480×270. Using the arrow keys or a controller hides the
  pointer anywhere; moving the mouse brings it back.
- **Sound packs**: Settings → Sounds & touch → Sound pack picks Lo-fi (the default), Wood,
  Bubbles, Soft keys, Cosmic or Retro. The packs are made by `tools/make_sound_packs.py`.
- **While a video plays** the screen stays on and the computer doesn't sleep; pausing lets it.
- **Size** follows the desktop's display scale (Settings → Displays). Settings → Appearance →
  UI zoom (60–200%) makes everything bigger or smaller on top of that.
- **Downloads** are on. Hold Enter on a stream for "Download for offline", use "⬇ Download season"
  next to the season buttons, or "Download" in a card's or episode's menu. Every download asks
  first and shows where it goes, with Change folder. The default folder is set in Settings →
  Updates & storage (your XDG videos folder's Zemu subfolder until you pick one); shows are saved as
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

Green or blocky video that otherwise plays smoothly is the GPU's decoder struggling with that
file: turn on Settings → Video & audio formats → "Prefer software video decoders".

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
