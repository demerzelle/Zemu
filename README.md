# Zemu

An Android TV client for the [Stremio addon protocol](https://github.com/Stremio/stremio-addon-sdk/tree/master/docs/api)
with a Netflix-style interface and **cached-only** debrid streams.

## Features

- **Netflix-style TV UI** (Jetpack Compose for TV): a full-bleed hero that follows focus, poster rows, a collapsible side menu, and a details page with backdrop, logo, episodes and recommendations.
- **Trailers**: after you rest on a title, its trailer fades in muted behind the hero (Home and title pages). Hold OK on any poster, or press Trailer, to watch full screen with sound. Toggle autoplay and sound in Settings → Trailers.
- **Built-in ratings**: the IMDb rating on every poster and page, plus a personal "% Match".
- **Recommendations that change daily**:
  - "Picked for You Today" (your best matches, with the rest reshuffled daily).
  - "Because you watched…" / "Because you saved…" (rotating titles from your history and My List).
  - "Today's Spotlight: {genre}" and "Hidden Gems: {genre}" (well-rated titles outside the most popular).
  - "Best of {year}" (a different year every day) and "New This Month".
  - "New Episodes for You" (fresh episodes of series you've watched).
  - Title pages show "More Like This" (up to 50) and "Top {genre} Picks".
- **Readable summaries**: long descriptions scroll themselves. On title pages you can also focus the text and scroll it with Up/Down.
- **Movies, Series and Anime pages**, each with a hero for the focused title. Anime uses the Kitsu addon (installed automatically) with separate Anime Series and Anime Movies sections.
- **Themes**: 10 preset themes plus a custom accent/background color picker (Settings → Theme).
- **Hold OK on any card** for a menu: Details, Episodes, View trailer, My List, Mark as watched/unwatched, Remove from history.
- **Player menu bar**: play/pause, ±10 s, audio track, subtitles (with live subtitle styling), speed, picture size (Fit / Zoom / Stretch / Center), like/dislike (feeds recommendations), My List and next episode. OK pauses and opens it. Back or Up closes it, and Back again leaves the player. Left/Right scrub 15 s, speeding up to 60 s the longer you hold or the faster you press.
- **Next-episode autoplay** with a countdown, plus an optional "Are you still watching?" check that you can switch off right from the prompt.
- **Profiles**: separate profiles, each with its own addons, history, My List, likes, recommendations and settings. "Who's watching?" appears at launch once there's more than one. Pick a premade avatar or upload a photo from your phone.
- **Animated themes**: RGB, Snowfall, Rain, Lightning storm, Cyberpunk, Halloween, Christmas, Aurora, Fireflies, Matrix and Sakura (Settings → Theme).
- **Cast & crew** (needs a free TMDB API key in Settings): actor photos, director, studio, and tappable actors that open their other movies and series.
- **Skip intro / recap**: community timestamps from [TheIntroDB](https://theintrodb.org) (shows and movies) and [AniSkip](https://aniskip.com) (anime). The next-episode card starts when the credits do.
- **Subtitles everywhere**: if your addons have none in your language, OpenSubtitles and a few language-specific addons are searched automatically.
- **Voice search** (devices with a mic), **touch screens** (tap, long-press, swipe), and a **Continue Watching** row on the Android TV home screen plus a phone widget.
- **Other devices profile** (optional): built from your debrid account's recent history (Real-Debrid, AllDebrid, Premiumize, TorBox, Debrid-Link), with its own Continue Watching and recommendations.
- **Any metadata provider**: Cinemeta can be removed or replaced; pick the provider in Settings → Metadata provider.
- **Autoplay something similar** when a movie or a series finale ends.
- **Cast without a key**: photos and filmographies from TVmaze, Wikidata and IMDb (TMDB key optional, for richer data).
- **Cached-only**: only streams your debrid service has already cached are listed. Raw torrents and "download" links never show up. Catalogs show every title; only the stream list is limited to cached results.
- **Stream filters**: audio language, subtitle language (embedded and external), size, quality, HDR / Dolby Vision, video codec, audio format, channels, source, debrid service and addon. Each option shows a live count.
- **"Best for this TV"**: the app reads the TV's decoders, HDR support, display modes and HDMI audio passthrough, and ranks streams by what will actually play well.
- **Player that recovers from decoding errors**:
  - If a stream fails with `ERROR_CODE_DECODING_FAILED` or similar, the player retries automatically. It plays Dolby Vision as its HDR10 base layer, then tries software video decoders, then FFmpeg audio (DTS, TrueHD, E-AC3…).
  - If none of that works, it moves on to the next-best cached stream.
  - Fixes that work are remembered for your TV (Settings → Playback).
  - As a last resort, it offers an external player (VLC, Just Player…).
- **Addon browser** (side menu → Addons), like Stremio's:
  - Installed, Official and Community catalogs, plus stremio-addons.net (~700 addons), with type filters and search.
  - Install / Uninstall / Configure. Configure opens the addon's own setup page in the app with a D-pad cursor, and its Install button (or "copy URL") installs straight into Zemu.
  - You can also paste a URL, or send one from your phone.

## Setup on the TV

1. Install and open Zemu. Cinemeta (catalogs, metadata, ratings) and OpenSubtitles are installed automatically.
2. Open **Addons** in the side menu and install a stream addon configured with your debrid account (Real-Debrid, AllDebrid, Premiumize, TorBox, Debrid-Link…). AIOStreams, Comet, MediaFusion and Torrentio all work.
   - Use **Configure** to set it up on the TV, or paste the manifest URL you already have (e.g. your AIOStreams instance's URL).
   - To avoid typing with the remote, open the address shown on the Addons screen (e.g. `http://192.168.1.20:8765`) on your phone and paste the URL there. This phone page only works while the Addons screen is open on the TV.
3. Set your preferred audio and subtitle languages in **Settings → Languages**.

## How "cached" is decided

A stream is shown only if **both** are true:

- it has a direct `http(s)` URL (not an `infoHash` torrent), and
- the addon marks it as cached (`[RD+]`, `⚡`, `✅`, "cached", "instant") and does **not** mark it as uncached ("download", `⏳`, `⬇`, "uncached").

See `app/src/main/java/com/zemu/tv/streams/StreamParser.kt`. Plain HTTP addons without debrid markers are hidden unless you turn on **Treat direct links as cached** in Settings.

## Build

Requires JDK 17–21 and the Android SDK (API 35). The easiest way is to open this folder in Android Studio and click Run.

From a terminal, use a Java 17–21 runtime. Gradle 8.11 can't run on Java 25, which is what recent Android Studio versions bundle:

```bash
export JAVA_HOME=~/Library/Java/JavaVirtualMachines/jbr-21.0.11/Contents/Home
./gradlew assembleDebug                  # APK: app/build/outputs/apk/debug/app-debug.apk
./gradlew test                           # stream-parser unit tests
adb connect <tv-ip> && adb install -r app/build/outputs/apk/debug/app-debug.apk
```

## Project layout

```
data/        Stremio protocol models, addon client & repository, persistence, cached-availability checks
streams/     Stream parsing, language detection, device capabilities, filter + ranking engine
recommend/   Taste profile, similarity scoring, % Match
player/      Media3 player activity + external-player handoff
ui/          Compose for TV screens: home, details, browse, search, my list, settings
```

Zemu doesn't host or index any content. It only plays what the addons you install return.
