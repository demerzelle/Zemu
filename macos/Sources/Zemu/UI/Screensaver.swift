import SwiftUI
import ZemuCore

/**
 * Library screensaver: after the app sits idle (Settings → Appearance), a full-screen slideshow of
 * suggested titles. Any input wakes the app; Return plays the title showing.
 */
@MainActor @Observable
final class Screensaver {
    static let shared = Screensaver()

    private(set) var slides: [ScreensaverSlide] = []
    var current: ScreensaverSlide?
    var showing: Bool { !slides.isEmpty }
    @ObservationIgnored private var lastInput = Date()
    @ObservationIgnored private var monitor: Any?
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var titles: [Meta] = []

    func start() {
        // Keys come through InputRouter (keyInput), so they're seen before any other key handling.
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .rightMouseDown, .scrollWheel]) { [weak self] e in
            guard let self else { return e }
            self.lastInput = Date()
            guard self.showing else { return e }
            self.dismiss()
            // The waking click never reaches the app underneath.
            return e.type == .mouseMoved ? e : nil
        }
        loop = Task { [weak self] in
            // Let startup's own loading (rows, images) finish before fetching art.
            try? await Task.sleep(nanoseconds: 45_000_000_000)
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await self?.tick()
            }
        }
    }

    private func tick() async {
        let app = AppModel.shared
        let s = app.settings
        // Kid profiles have no screensaver (it shows any title); nothing covers a video or trailer.
        guard s.screensaver, !app.profiles.kidsOn, app.player == nil, app.trailer == nil, NSApp.isActive, !showing else { return }
        if titles.isEmpty { titles = app.session.home.screensaverTitles(); await app.session.artwork.refresh(titles) }
        guard Date().timeIntervalSince(lastInput) >= Double(s.screensaverIdleSec) else { return }
        let found = app.session.artwork.slides(titles)
        // Skip when nothing has art yet.
        if found.isEmpty { lastInput = Date() } else { withAnimation(.easeInOut(duration: 0.6)) { slides = found } }
        titles = app.session.home.screensaverTitles()
        Task { await app.session.artwork.refresh(titles) }
    }

    /** A key: counts as activity, and only wakes the app while the screensaver shows (Return plays what's showing). True when swallowed. */
    func keyInput(_ e: NSEvent) -> Bool { gamepadInput(play: [36, 76].contains(e.keyCode)) }

    /** A controller button: counts as activity, and only wakes the app while the screensaver shows. Returns true when swallowed. */
    func gamepadInput(play: Bool) -> Bool {
        lastInput = Date()
        guard showing else { return false }
        let m = current?.meta
        dismiss()
        if play, let m { AppModel.shared.openDetails(m, play: true) }
        return true
    }

    func dismiss() {
        lastInput = Date()
        withAnimation(.easeInOut(duration: 0.3)) { slides = [] }
        current = nil
    }
}

struct ScreensaverView: View {
    let slides: [ScreensaverSlide]
    var saver = Screensaver.shared
    var settings = AppModel.shared.settings
    @State private var index = 0

    var body: some View {
        ZStack {
            Color.black
            if slides.indices.contains(index) {
                SlideView(slide: slides[index], seconds: Double(settings.screensaverImageSec), showTitle: settings.screensaverShowTitle)
                    .id(index)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: Double(settings.screensaverFadeTenths) / 10), value: index)
        .onAppear { saver.current = slides.first }
        .task {
            while slides.count > 1, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(settings.screensaverImageSec) * 1_000_000_000)
                index = (index + 1) % slides.count
                saver.current = slides[index]
            }
        }
    }

    private struct SlideView: View {
        let slide: ScreensaverSlide
        let seconds: Double
        let showTitle: Bool
        @State private var zoom: CGFloat = 1

        var body: some View {
            ZStack(alignment: .bottomLeading) {
                // Slow push-in while the slide shows.
                RemoteImage(url: slide.image, maxPixel: 2560)
                    .scaleEffect(zoom)
                    .onAppear { withAnimation(.linear(duration: seconds + 2)) { zoom = 1.08 } }
                if showTitle {
                    LinearGradient(stops: [.init(color: .clear, location: 0.45), .init(color: .black.opacity(0.85), location: 1)], startPoint: .top, endPoint: .bottom)
                    let m = slide.meta
                    VStack(alignment: .leading, spacing: 12) {
                        if let logo = slide.logo {
                            RemoteImage(url: logo, maxPixel: 900, contentMode: .fit, alignment: .bottomLeading).frame(maxWidth: 460, maxHeight: 130, alignment: .bottomLeading)
                        } else {
                            Text(m.title).font(.z(size: 44, weight: .black)).lineLimit(2)
                        }
                        let info = [m.releaseInfo, m.genres.prefix(3).joined(separator: " · ").nilIfBlank, m.imdbRating.map { "IMDb \($0)" }].compactMap { $0 }
                        if !info.isEmpty { Text(info.joined(separator: "   ")).font(.z(size: 16)).foregroundStyle(.white.opacity(0.8)) }
                        Button { Screensaver.shared.dismiss(); AppModel.shared.openDetails(m, play: true) } label: {
                            Label("Watch now  ·  Return", systemImage: "play.fill").font(.z(size: 16, weight: .bold))
                                .padding(.horizontal, 18).padding(.vertical, 10)
                                .foregroundStyle(P.onAccent)
                                .background(RoundedRectangle(cornerRadius: 8).fill(P.accent))
                        }
                        .buttonStyle(.plain)
                    }
                    .foregroundStyle(.white)
                    .padding(.leading, 64).padding(.bottom, 56)
                }
            }
            .clipped()
        }
    }
}
