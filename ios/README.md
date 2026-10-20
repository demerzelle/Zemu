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
