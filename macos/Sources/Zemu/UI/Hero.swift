import SwiftUI
import ZemuCore

/**
 * Full-bleed backdrop with left/bottom fade, as used behind Home, Browse and Details. When
 * [trailerAfter] is set, the title's trailer replaces the image after that delay.
 */
struct Backdrop: View {
    let meta: Meta?
    var trailerAfter: Double?
    var trailerSound = false

    @State private var showTrailer = false
    /** The hero preview plays the official trailers one after another. */
    @State private var trailerIndex = 0

    /** Trailers stay off while a video or a full-window trailer plays on top. */
    private var covered: Bool { AppModel.shared.player != nil || AppModel.shared.trailer != nil }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topTrailing) {
                ZStack {
                    if let m = meta, AppModel.shared.settings.heroArt {
                        RemoteImage(url: m.backdropUrl, maxPixel: 1920, alignment: .top)
                            .id(m.id)
                            .transition(.opacity)
                    }
                }
                .frame(width: geo.size.width * 0.78, height: geo.size.height)
                .animation(.easeInOut(duration: 0.5), value: meta?.id)

                if showTrailer, !covered, let m = meta, m.playableTrailer != nil {
                    let list = m.officialTrailers
                    let t = list.indices.contains(trailerIndex) ? list[trailerIndex].id : m.playableTrailer!
                    HeroTrailer(videoId: t, sound: trailerSound, paused: !AppModel.shared.appActive) {
                        if trailerIndex + 1 < list.count { trailerIndex += 1 } else { showTrailer = false }
                    }
                        .frame(width: geo.size.width * 0.78, height: geo.size.height)
                        .clipped()
                        .id(t)
                }

                LinearGradient(stops: [
                    .init(color: P.background, location: 0),
                    // Solid where the picture starts (22% in), so its edge never shows.
                    .init(color: P.background, location: 0.25),
                    .init(color: P.background.opacity(0.85), location: 0.42),
                    .init(color: P.background.opacity(0.35), location: 0.65),
                    .init(color: .clear, location: 1),
                ], startPoint: .leading, endPoint: .trailing)
                LinearGradient(stops: [.init(color: .clear, location: 0.5), .init(color: P.background, location: 1)], startPoint: .top, endPoint: .bottom)
            }
        }
        .allowsHitTesting(false)
        .task(id: "\(meta?.id ?? "")|\(trailerAfter ?? -1)|\(covered)") {
            showTrailer = false
            trailerIndex = 0
            if let url = meta?.backdropUrl { AppModel.shared.ambient = url }
            guard let after = trailerAfter, !covered, meta?.playableTrailer != nil else { return }
            try? await Task.sleep(nanoseconds: UInt64(after * 1e9))
            // Only start while Zemu is the frontmost app.
            while !Task.isCancelled, !AppModel.shared.appActive { try? await Task.sleep(nanoseconds: 500_000_000) }
            if !Task.isCancelled { showTrailer = true }
        }
    }
}

/** Title info for the hovered/featured title at the top of Home and Browse. */
struct HeroInfo: View {
    let meta: Meta?
    var matchPercent: Int?
    /** Small windows: logo, details line and buttons only. */
    var compact = false
    /** Tall windows: bigger logo and text. */
    var large = false
    var app = AppModel.shared

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let m = meta {
                VStack(alignment: .leading, spacing: compact ? 6 : 10) {
                    TitleLogo(meta: m, maxHeight: compact ? 50 : large ? 130 : 90, maxWidth: compact ? 260 : large ? 560 : 460)
                    MetaLine(meta: m, matchPercent: matchPercent)
                    if !compact {
                        if !m.genres.isEmpty {
                            Text(m.genres.prefix(4).joined(separator: "  •  ")).font(.z(size: large ? 14.5 : 13)).foregroundStyle(Palette.textSecondary)
                        }
                        Text(m.description ?? "").font(.z(size: large ? 16 : 14)).foregroundStyle(P.text.opacity(0.85))
                            .lineLimit(large ? 4 : 3).frame(maxWidth: large ? 680 : 580, alignment: .leading)
                    }
                    FlowLayout(spacing: 10) {
                        ZButton(title: "Play", icon: "play.fill", primary: true) { app.openDetails(m, play: true) }
                        ZButton(title: "More Info", icon: "info.circle") { app.openDetails(m) }
                        if let t = m.playableTrailer {
                            let playing = HeroTrailerState.shared.playingId == t
                            ZButton(title: playing ? "Watch Full Screen" : "Trailer", icon: "film") {
                                app.playTrailer(playing ? (HeroTrailerState.shared.playingId ?? t) : t, start: playing ? Int(HeroTrailerState.shared.seconds) : 0, queue: m.officialTrailers)
                            }
                        }
                        IconButton(icon: app.session.store.isInMyList(m.id) ? "checkmark" : "plus", help: "My List") { app.toggleMyList(m) }
                    }
                    .padding(.top, 4)
                }
                .zGlassPanel()
                .id(m.id)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: meta?.id)
        .padding(.leading, compact ? 24 : large ? 64 : 48)
        .padding(.trailing, 24)
        .frame(maxWidth: .infinity, alignment: .bottomLeading)
    }
}
