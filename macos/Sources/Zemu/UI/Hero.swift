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

    /** Trailers stay off while a video or a full-window trailer plays on top. */
    private var covered: Bool { AppModel.shared.player != nil || AppModel.shared.trailer != nil }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topTrailing) {
                ZStack {
                    if let m = meta {
                        RemoteImage(url: m.backdropUrl, maxPixel: 1920, alignment: .top)
                            .id(m.id)
                            .transition(.opacity)
                    }
                }
                .frame(width: geo.size.width * 0.78, height: geo.size.height)
                .animation(.easeInOut(duration: 0.5), value: meta?.id)

                if showTrailer, !covered, let t = meta?.trailerId {
                    HeroTrailer(videoId: t, sound: trailerSound) { showTrailer = false }
                        .frame(width: geo.size.width * 0.78, height: geo.size.height)
                        .clipped()
                        .id(t)
                }

                LinearGradient(stops: [
                    .init(color: P.background, location: 0),
                    .init(color: P.background.opacity(0.92), location: 0.3),
                    .init(color: P.background.opacity(0.35), location: 0.6),
                    .init(color: .clear, location: 1),
                ], startPoint: .leading, endPoint: .trailing)
                LinearGradient(stops: [.init(color: .clear, location: 0.5), .init(color: P.background, location: 1)], startPoint: .top, endPoint: .bottom)
            }
        }
        .allowsHitTesting(false)
        .task(id: "\(meta?.id ?? "")|\(trailerAfter ?? -1)|\(covered)") {
            showTrailer = false
            guard let after = trailerAfter, !covered, meta?.trailerId != nil else { return }
            try? await Task.sleep(nanoseconds: UInt64(after * 1e9))
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
    var app = AppModel.shared

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let m = meta {
                VStack(alignment: .leading, spacing: compact ? 6 : 10) {
                    TitleLogo(meta: m, maxHeight: compact ? 50 : 84, maxWidth: compact ? 260 : 440)
                    MetaLine(meta: m, matchPercent: matchPercent)
                    if !compact {
                        if !m.genres.isEmpty {
                            Text(m.genres.prefix(4).joined(separator: "  •  ")).font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
                        }
                        Text(m.description ?? "").font(.system(size: 14)).foregroundStyle(Color.white.opacity(0.85))
                            .lineLimit(3).frame(maxWidth: 560, alignment: .leading)
                    }
                    FlowLayout(spacing: 10) {
                        ZButton(title: "Play", icon: "play.fill", primary: true) { app.openDetails(m, play: true) }
                        ZButton(title: "More Info", icon: "info.circle") { app.openDetails(m) }
                        if let t = m.trailerId {
                            let playing = HeroTrailerState.shared.playingId == t
                            ZButton(title: playing ? "Watch Full Screen" : "Trailer", icon: "film") {
                                app.playTrailer(t, start: playing ? Int(HeroTrailerState.shared.seconds) : 0)
                            }
                        }
                        IconButton(icon: app.session.store.isInMyList(m.id) ? "checkmark" : "plus", help: "My List") { app.toggleMyList(m) }
                    }
                    .padding(.top, 4)
                }
                .id(m.id)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: meta?.id)
        .padding(.leading, compact ? 24 : 48)
        .padding(.trailing, 24)
        .frame(maxWidth: .infinity, alignment: .bottomLeading)
    }
}
