# Zemu for iPhone and iPad

SwiftUI port of the Zemu Android TV app for iPhone and iPad (iOS 17+). It shares its code with the Mac app:

- `Sources/ZemuCore`: the Stremio protocol, stream parsing and ranking, recommendations and storage, copied from Zemu Next. It's the newer core that matches Android 1.0.1.
- `Sources/Zemu`: the Mac screens (`../macos/Sources/Zemu`), adapted for touch. `App/AppKitCompat.swift` maps the AppKit calls they use to UIKit, so the shared screens stay almost line-for-line the same as on Mac.

## What's different from Mac

- **Player**: mpv through [MPVKit](https://github.com/mpvkit/MPVKit) (gpu-next on Metal via MoltenVK), so MKV, HEVC, AV1, DTS, TrueHD and ASS subtitles play like on Android. AVPlayer is the fallback. Tap shows the controls, and a double-tap on the left or right side seeks 10 s. **Open in External Player** hands the stream to VLC, Infuse or Outplayer.
- **Navigation**: a sidebar on iPad and a tab bar on iPhone. Swipe right from the left edge to go back.
- **Not on iOS**: Picture in Picture, keyboard and game controller navigation, the menu bar and Dock menus.

## Build an unsigned .ipa for sideloading

Needs full Xcode (not just the Command Line Tools) and XcodeGen:

```bash
brew install xcodegen
./scripts/build-ipa.sh
```

This writes `Zemu.ipa`. Sideload it with AltStore, SideStore or Sideloadly, which sign it with your Apple ID. With a free Apple ID, apps expire after 7 days and need re-signing.

To run it in the Simulator or on a device from Xcode, run `xcodegen`, open `Zemu.xcodeproj`, pick your team under Signing, then Run.

## Apple TV

The `ZemuTV` target (tvOS 18+) builds the same screens and mpv player from `Sources/Zemu`, with `#if os(tvOS)` where the platform differs. `UI/FocusEngine.swift` maps the shared `zFocus` calls onto the tvOS focus engine and draws the iPad-sized layout at 1.5× so it fits a 1920×1080 TV.

- **Remote**: swipe or arrows move focus, click selects, hold opens a card's menu, Menu/Back goes back. In the player, left and right seek 10 s, and click or up/down shows the controls.
- **Add from a phone**: while Settings, Addons or a configure page is open, the TV shows an `http://192.168.x.x:8765` address and QR code. That page installs addon links and saves debrid and TMDB keys, like on Android. Anyone on your network can use it while it's showing.
- **Kid profiles**: turn on in a profile's editor. Only allowed kids' titles show, and Settings, Addons and leaving the profile need a 4-digit parent code.
- **Trailers** open in the YouTube app; without it, trailer buttons don't appear.
- **Addon configure pages** have no web view on tvOS, so they show a QR code to open on a phone.
- **Apple TV HD** turns off animated themes and liquid effects, and lowers HEVC/AV1 in stream ranking, to stay smooth.
- **Not on Apple TV** (tvOS lacks the APIs): no profile backup files, custom photo avatars, subtitle files, custom color picker, Save Frame, or new-episode banners.

```bash
./scripts/build-ipa.sh tv
```

This writes an unsigned `ZemuTV.ipa`. Sign and install it with Sideloadly or Xcode's Devices window. To run it from Xcode, run `xcodegen`, open `Zemu.xcodeproj`, pick the `ZemuTV` scheme and your team, then Run.
