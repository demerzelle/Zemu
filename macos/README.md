# Zemu for Mac

Native macOS (SwiftUI) port of the Zemu Android TV app: a Stremio-addon client with a
Netflix-style interface and **cached-only** debrid streams. Everything from the Android app is
here (see `../README.md`), plus Mac-specific features.

## What's the same as Android

Home with daily recommendation rows, Movies / Series / Anime pages with filters, search,
My List, title pages with episodes, cast (TMDB or free sources), "More Like This", hero trailers,
the cached-only stream list with every filter and "Best for this Mac" ranking, profiles,
debrid linking (Real-Debrid / AllDebrid code login or API key → Torrentio), the addon browser
with Configure, skip intro/recap/credits, next-episode autoplay, "Are you still watching?",
"play something similar", subtitle styling, 11 color themes + custom, and the animated themes.

## What's new on Mac

- **mpv player** (libmpv, bundled): MKV, HEVC/AV1, DTS/TrueHD, ASS subtitles, hardware decoding
  via VideoToolbox. Falls back to the next cached stream, then IINA/VLC/Infuse. AVPlayer is used
  when mpv isn't available.
- **Fully keyboard and gamepad driven** (Xbox, PlayStation, Switch Pro, MFi): arrow keys / D-pad
  move a focus highlight anywhere (the page scrolls to follow), Return / Ⓐ selects, Esc / Ⓑ goes
  back, O / Ⓧ opens a title's options, Ⓨ search, LB/RB switch pages. Every dropdown also opens
  as an in-app menu, and text fields open an on-screen keyboard from a controller. In the player:
  ←→ / D-pad seek (accelerating), Return / Ⓐ opens the controls (navigate them with arrows),
  Ⓧ/Ⓨ subtitles/audio, LB/RB ±10 s, LT/RT scrub. Full map: Settings → Keyboard & Controller.
- **Picture in Picture**: the PiP button (or T, or the controller's View button) moves the video
  into a floating window above all apps and Spaces. Drag it anywhere, resize it from any edge
  (it keeps the video's shape), double-click or ⤢ to return. It also turns on automatically
  when you switch away from Zemu while a video plays (Settings → Playback).
- **Keyboard extras**: Space play/pause, ↑/↓ volume, F full screen, S/A cycle subtitles/audio,
  C subtitle style, Z/X subtitle delay, [ ] speed, N next episode, P picture size, 0–9 jump to
  10 %…90 %, ⌘S save frame. ⌘1–⌘8 switch pages, ⌘F search, ⌘[ back.
- **Now Playing & media keys**: Control Center, AirPods and keyboard media keys control playback;
  the display stays awake while playing.
- **stremio:// links**: "Install" buttons on addon websites install straight into Zemu. You can
  also drop or paste (⇧⌘V) a manifest URL anywhere.
- **Configure pages** open in a real in-app browser (mouse and keyboard, no D-pad cursor).
- **New-episode notifications**, plus Continue Watching in the **Dock menu** and a **menu-bar extra**.
- **Open Stream URL…** (⌘O) plays any direct video link.
- Drop a subtitle file on the player to load it; right-click anything for its context menu.
- Profile photos from disk (file picker or drag & drop); profile **export/import** (Settings →
  Data & Backup).

## Build

Requires macOS 14+ and the Swift toolchain (Xcode or just the Command Line Tools).

```bash
brew install mpv              # only needed to build a bundle with mpv inside
./scripts/build-app.sh        # → build/Zemu.app (libmpv and its dependencies bundled)
swift run ZemuCoreTests       # parser / protocol / ranking tests (port of the Android tests)
swift run Zemu                # run unbundled during development
```

`build/Zemu.app` is self-contained: the mpv libraries are copied into
`Contents/Frameworks` and relinked, so other Macs don't need Homebrew. It's signed ad hoc; to
hand it to other people without Gatekeeper warnings, sign it with a Developer ID and notarize it.

**License note:** Homebrew's mpv and ffmpeg are GPL builds. Sharing the bundled app publicly
means GPL obligations (offering the source). For closed distribution, swap in an LGPL libmpv
build: only `Sources/CMpv` loads it, at runtime.

## Layout

```
Sources/ZemuCore/   Stremio protocol, models, stream parser + filter/ranking, recommender,
                    debrid auth, TMDB / free cast, skip segments, per-profile storage (no UI)
Sources/CMpv/       libmpv C headers + a runtime loader (dlopen), so mpv is optional
Sources/Zemu/       SwiftUI app: App/ (model, session, system integrations), UI/ (theme,
                    components), Screens/, Player/ (mpv + AVPlayer engines, player model and UI)
Sources/ZemuCoreTests/  test runner (the CLT toolchain has no XCTest)
scripts/            build-app.sh, bundle_dylibs.py
```

Data lives in `~/Library/Application Support/Zemu` (one JSON file per profile).
