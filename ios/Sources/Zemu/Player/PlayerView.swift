import SwiftUI
import UniformTypeIdentifiers
import ZemuCore

/** Hosts the engine's video view; moves it when the player falls back to another engine. */
struct EngineHost: UIViewRepresentable {
    let engineView: UIView

    func makeUIView(context: Context) -> UIView {
        let host = UIView()
        host.backgroundColor = .black
        attach(engineView, to: host)
        return host
    }

    func updateUIView(_ host: UIView, context: Context) {
        if engineView.superview !== host {
            host.subviews.forEach { $0.removeFromSuperview() }
            attach(engineView, to: host)
        }
    }

    private func attach(_ v: UIView, to host: UIView) {
        v.removeFromSuperview()
        v.frame = host.bounds
        v.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.addSubview(v)
    }
}

struct PlayerView: View {
    @Bindable var p: PlayerModel
    var app = AppModel.shared
    @State private var dropTargeted = false
    @State private var hoveringControls = false
    @State private var pickingSubtitle = false

    var body: some View {
        ZStack {
            // Video edge to edge; the controls stay clear of the notch and home indicator.
            Color.black.ignoresSafeArea()
            EngineHost(engineView: p.engine.view).ignoresSafeArea()
            // Taps on the video: single shows/hides the controls, double on either side seeks 10 s.
            GeometryReader { g in
                Color.clear.contentShape(Rectangle())
                    .gesture(SpatialTapGesture(count: 2).onEnded { v in
                        p.seekBy(v.location.x < g.size.width / 2 ? -10_000 : 10_000)
                        p.flash(v.location.x < g.size.width / 2 ? "−10 s" : "+10 s")
                    }.exclusively(before: TapGesture().onEnded {
                        p.controlsVisible ? p.hideControls() : p.showControls()
                    }))
            }

            if p.buffering && p.failure == nil {
                ProgressView().controlSize(.large).tint(.white)
            }
            if let n = p.notice {
                Text(n).font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 90)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }

            if !p.controlsVisible, p.scrubTargetMs != nil {
                VStack { Spacer(); SeekBar(p: p).padding(.horizontal, 40).padding(.bottom, 30) }
                    .background(LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .center, endPoint: .bottom))
                    .allowsHitTesting(false)
            }

            if p.controlsVisible || p.failure != nil { controls.transition(.opacity) }

            overlays
        }
        .zFocusScope("player")
        .animation(.easeInOut(duration: 0.2), value: p.controlsVisible)
        .animation(.easeInOut(duration: 0.2), value: p.notice)
        .onContinuousHover { phase in
            if case .active = phase, !hoveringControls { p.showControls() }
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            _ = providers.first?.loadObject(ofClass: URL.self) { url, _ in
                if let url { Task { @MainActor in p.addSubtitleFile(url) } }
            }
            return true
        }
        .overlay(dropTargeted ? Rectangle().strokeBorder(P.accent, lineWidth: 4) : nil)
        .fileImporter(isPresented: $pickingSubtitle, allowedContentTypes: ["srt", "ass", "ssa", "vtt", "sub"].compactMap { UTType(filenameExtension: $0) }) { r in
            guard let url = try? r.get() else { return }
            // Copy out of the security scope so mpv can read it whenever it likes.
            let local = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
            let ok = url.startAccessingSecurityScopedResource()
            defer { if ok { url.stopAccessingSecurityScopedResource() } }
            try? FileManager.default.removeItem(at: local)
            if (try? FileManager.default.copyItem(at: url, to: local)) != nil { p.addSubtitleFile(local) }
        }
        .persistentSystemOverlays(.hidden)
        .statusBarHidden()
        .onAppear { p.showControls() }
    }

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                IconButton(icon: "chevron.left", help: "Back", size: 40) { p.close() }
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.title).font(.system(size: 22, weight: .black)).lineLimit(1)
                    if let l = p.label { Text(l).font(.system(size: 14)).foregroundStyle(Palette.textSecondary).lineLimit(1) }
                    Text("\(p.streamLabel)  ·  \(p.engineName)").font(.system(size: 12)).foregroundStyle(Palette.textMuted).lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 40)
            .background(LinearGradient(colors: [.black.opacity(0.8), .clear], startPoint: .top, endPoint: .bottom))

            Spacer()

            VStack(spacing: 14) {
                SeekBar(p: p, focusable: true)
                buttons
            }
            .padding(.horizontal, 20)
            .padding(.top, 50)
            .padding(.bottom, 12)
            .background(LinearGradient(colors: [.clear, .black.opacity(0.9)], startPoint: .top, endPoint: .bottom))
            .onHover { hoveringControls = $0; if $0 { p.showControls() } }
        }
    }

    /** The full button row, or a compact one with the extras in a "More" menu when the window is narrow. */
    private var buttons: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                leftButtons
                Spacer(minLength: 12)
                audioMenu
                subtitleMenu
                speedMenu
                pictureMenu
                IconButton(icon: p.rating > 0 ? "hand.thumbsup.fill" : "hand.thumbsup", help: "Like", active: p.rating > 0) { p.rate(p.rating > 0 ? 0 : 1) }
                IconButton(icon: p.rating < 0 ? "hand.thumbsdown.fill" : "hand.thumbsdown", help: "Dislike", active: p.rating < 0) { p.rate(p.rating < 0 ? 0 : -1) }
                IconButton(icon: p.inMyList ? "heart.fill" : "heart", help: p.inMyList ? "In My List" : "Add to My List", active: p.inMyList) { p.toggleMyList() }
                IconButton(icon: "camera", help: "Save frame to Photos") { p.saveFrame() }
            }
            HStack(spacing: 10) {
                leftButtons
                Spacer(minLength: 8)
                subtitleMenu
                playerMenu("ellipsis", "More", title: "More") { moreItems }
            }
            HStack(spacing: 8) {
                IconButton(icon: p.isPlaying ? "pause.fill" : "play.fill", help: "Play/Pause", size: 38, preferred: true) { p.togglePlay() }
                Spacer(minLength: 4)
                playerMenu("ellipsis", "More", title: "More") { moreItems }
            }
        }
    }

    private var leftButtons: some View {
        HStack(spacing: 12) {
            IconButton(icon: p.isPlaying ? "pause.fill" : "play.fill", help: p.isPlaying ? "Pause" : "Play", size: 44, preferred: true) { p.togglePlay() }
            IconButton(icon: "gobackward.10", help: "Back 10 seconds") { p.seekBy(-10_000) }
            IconButton(icon: "goforward.10", help: "Forward 10 seconds") { p.seekBy(10_000) }
            if p.nextUp != nil { IconButton(icon: "forward.end.fill", help: "Next episode") { p.playNextNow() } }
        }
    }

    private var audioItems: [ActionItem] {
        let tracks = p.audioTracks()
        if tracks.isEmpty { return [ActionItem(label: "No audio tracks", action: {})] }
        return tracks.map { t in ActionItem(label: t.label, checked: t.selected) { p.select(t, kind: .audio) } }
    }

    private var subtitleItems: [ActionItem] {
        let tracks = p.subtitleTracks()
        var items = [ActionItem(label: "Off", checked: !tracks.contains(where: \.selected)) { p.select(nil, kind: .sub) }]
        items += tracks.map { t in ActionItem(label: t.label, checked: t.selected) { p.select(t, kind: .sub) } }
        items += [
            ActionItem(label: "Subtitle Style…", icon: "textformat") { p.subtitleStyleOpen = true; p.showControls() },
            ActionItem(label: "Add Subtitle File…", icon: "doc.badge.plus") { addSubtitleFile() },
            ActionItem(label: "Delay −0.1 s", icon: "minus", keepOpen: true) { p.adjustSubtitleDelay(-0.1) },
            ActionItem(label: "Delay +0.1 s", icon: "plus", keepOpen: true) { p.adjustSubtitleDelay(0.1) },
            ActionItem(label: "Reset Delay", icon: "arrow.uturn.backward") { p.adjustSubtitleDelay(-app.settings.subtitleDelay) },
        ]
        return items
    }

    /** Everything that doesn't fit in a narrow window. */
    private var moreItems: [ActionItem] {
        [
            ActionItem(label: "Audio: \(p.currentAudioLabel)", icon: "speaker.wave.2") { app.showMenu("Audio") { audioItems } },
            ActionItem(label: "Speed: \(p.speedLabel)", icon: "gauge.with.needle") {
                app.showMenu("Speed") { choiceItems([0.5, 0.75, 1, 1.25, 1.5, 1.75, 2].map { ($0, $0 == 1 ? "Normal" : "\($0)x") }, current: p.speed) { p.changeSpeed($0) } }
            },
            ActionItem(label: "Picture: \(p.aspect.label)", icon: "aspectratio") {
                app.showMenu("Picture size") { choiceItems(AspectMode.allCases.map { ($0, $0.label) }, current: p.aspect) { p.setAspect($0) } }
            },
            ActionItem(label: p.rating > 0 ? "Liked" : "Like", icon: "hand.thumbsup", checked: p.rating > 0) { p.rate(p.rating > 0 ? 0 : 1) },
            ActionItem(label: p.rating < 0 ? "Disliked" : "Dislike", icon: "hand.thumbsdown", checked: p.rating < 0) { p.rate(p.rating < 0 ? 0 : -1) },
            ActionItem(label: p.inMyList ? "Remove from My List" : "Add to My List", icon: "heart") { p.toggleMyList() },
            ActionItem(label: "Save Frame", icon: "camera") { p.saveFrame() },
        ]
    }

    private var audioMenu: some View {
        playerMenu("speaker.wave.2.fill", "Audio", title: "Audio") { audioItems }
    }

    private var subtitleMenu: some View {
        playerMenu("captions.bubble.fill", "Subtitles", title: "Subtitles", active: p.currentSubtitleLabel != "Off") { subtitleItems }
            .popover(isPresented: $p.subtitleStyleOpen, arrowEdge: .top) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Subtitle Style").font(.system(size: 14, weight: .bold))
                    Text("Changes apply right away.").font(.system(size: 12)).foregroundStyle(.secondary)
                    SubtitleStyleEditor { p.applySubtitleStyle() }
                }
                .padding(16)
            }
    }

    private var speedMenu: some View {
        playerMenu("gauge.with.needle", "Speed: \(p.speedLabel)", title: "Speed", active: p.speed != 1) {
            choiceItems([0.5, 0.75, 1, 1.25, 1.5, 1.75, 2].map { ($0, $0 == 1 ? "Normal" : "\($0)x") }, current: p.speed) { p.changeSpeed($0) }
        }
    }

    private var pictureMenu: some View {
        playerMenu("aspectratio", "Picture: \(p.aspect.label)", title: "Picture size", active: p.aspect != .FIT) {
            choiceItems(AspectMode.allCases.map { ($0, $0.label) }, current: p.aspect) { p.setAspect($0) }
        }
    }

    private func playerMenu(_ icon: String, _ help: String, title: String, active: Bool = false, items: @escaping () -> [ActionItem]) -> some View {
        ZMenu(title: title, items: items) { lit in
            Image(systemName: icon).font(.system(size: 15, weight: .semibold))
                .frame(width: 38, height: 38)
                .foregroundStyle(active ? P.onAccent : .white)
                .background(Circle().fill(active ? P.accent.opacity(0.9) : Color.white.opacity(lit ? 0.26 : 0.14)))
                .scaleEffect(lit ? 1.08 : 1)
                .help(help)
        }
    }

    private func addSubtitleFile() { pickingSubtitle = true }

    // MARK: Overlays

    @ViewBuilder
    private var overlays: some View {
        if let seg = p.activeSegment, p.countdown == nil, !p.stillWatchingPrompt {
            HStack(spacing: 6) {
                ZButton(title: seg.type.skipLabel, icon: "forward.end.fill", primary: true) { p.skipSegment() }
                ZButton(title: "Dismiss") { p.dismissSegment() }
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.55)))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.trailing, 20).padding(.bottom, p.controlsVisible ? 150 : 40)
        }
        if let next = p.upNext, let seconds = p.countdown {
            let recommended = p.nextUp == nil
            VStack(alignment: .leading, spacing: 4) {
                Text(recommended ? "Up next · recommended for you" : "Next episode").font(.system(size: 12.5)).foregroundStyle(Palette.textSecondary)
                Text(recommended ? next.displayTitle : "S\(next.season ?? 0) E\(next.episodeNumber) · \(next.displayTitle)").font(.system(size: 17, weight: .bold)).lineLimit(2)
                Text(seconds > 0 ? "Playing in \(seconds)s" : "Starting…").font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
                HStack(spacing: 10) {
                    ZButton(title: "Play Now", icon: "play.fill", primary: true) { p.playNextNow() }
                    ZButton(title: "Cancel") { p.cancelCountdown() }
                }
                .padding(.top, 10)
            }
            .padding(20)
            .frame(maxWidth: 380, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(P.surface.opacity(0.95)))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.horizontal, 20).padding(.bottom, p.controlsVisible ? 150 : 30)
        }
        if p.stillWatchingPrompt {
            dialog {
                Text("Are you still watching?").font(.system(size: 26, weight: .black))
                Text(p.title).foregroundStyle(Palette.textSecondary).padding(.bottom, 12)
                ZButton(title: "Continue Watching", primary: true, preferred: true) { p.answerStillWatching(true) }
                ZButton(title: "Continue and Don't Ask Again") { p.answerStillWatching(true, dontAskAgain: true) }
                ZButton(title: "Back to Browsing") { p.answerStillWatching(false) }
            }
        }
        if let f = p.failure {
            dialog {
                Text("This video can't be played here").font(.system(size: 24, weight: .black))
                Text(f.detail).font(.system(size: 13)).foregroundStyle(Palette.textSecondary).padding(.bottom, 12).textSelection(.enabled)
                FlowLayout(spacing: 10) {
                    ZButton(title: "Open in \(ExternalPlayer.installed.first ?? "External Player")", icon: "arrow.up.forward.app", primary: true, preferred: true) { p.openExternally() }
                    ZButton(title: "Retry", icon: "arrow.clockwise") { p.retry() }
                    ZButton(title: "Copy Link", icon: "link") { p.copyStreamURL() }
                    ZButton(title: "Back") { p.close() }
                }
            }
        }
    }

    private func dialog<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 10, content: content)
                .padding(24)
                .frame(maxWidth: 560, alignment: .leading)
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 16).fill(P.surface))
        }
    }
}

/** Seek bar with buffered range, hover preview time and click/drag to seek. Focusable: ←→ scrub. */
private struct SeekBar: View {
    let p: PlayerModel
    var focusable = false
    @State private var hoverX: CGFloat?
    @State private var dragFraction: Double?
    @State private var focused = false

    var body: some View {
        let duration = max(p.durationMs, 1)
        let shown = p.scrubTargetMs ?? dragFraction.map { Int64(Double(duration) * $0) } ?? p.positionMs
        let thick = hoverX != nil || focused
        VStack(alignment: .leading, spacing: 6) {
            if let t = p.scrubTargetMs {
                let delta = t - p.positionMs
                Text("\(PlayerModel.formatTime(t))   (\(delta >= 0 ? "+" : "−")\(PlayerModel.formatTime(abs(delta))))").font(.system(size: 16, weight: .bold))
            }
            HStack(spacing: 12) {
                Text(PlayerModel.formatTime(shown)).font(.system(size: 13, weight: .medium).monospacedDigit()).frame(width: 64, alignment: .leading)
                GeometryReader { g in
                    let w = g.size.width
                    let frac = { (ms: Int64) in CGFloat(min(1, max(0, Double(ms) / Double(duration)))) }
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.25)).frame(height: thick ? 8 : 5)
                        Capsule().fill(Color.white.opacity(0.35)).frame(width: w * frac(p.bufferedMs), height: thick ? 8 : 5)
                        Capsule().fill(P.accent).frame(width: w * frac(p.positionMs), height: thick ? 8 : 5)
                        Circle().fill(p.scrubTargetMs != nil || focused ? .white : P.accent).overlay(Circle().strokeBorder(.white, lineWidth: 2))
                            .frame(width: thick || p.scrubTargetMs != nil ? 18 : 12)
                            .offset(x: w * frac(shown) - 8)
                        if let x = hoverX, p.durationMs > 0 {
                            Text(PlayerModel.formatTime(Int64(Double(duration) * Double(x / w))))
                                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                                .padding(.horizontal, 6).padding(.vertical, 3)
                                .background(RoundedRectangle(cornerRadius: 5).fill(Color.black.opacity(0.8)))
                                .offset(x: min(max(0, x - 28), w - 56), y: -24)
                        }
                    }
                    .frame(height: 20)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        if case .active(let pt) = phase { hoverX = pt.x } else { hoverX = nil }
                    }
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { v in dragFraction = Double(max(0, min(1, v.location.x / w))) }
                        .onEnded { v in
                            p.seek(toFraction: Double(max(0, min(1, v.location.x / w))))
                            dragFraction = nil
                        })
                }
                .frame(height: 20)
                .modifier(SeekFocus(enabled: focusable, p: p, focused: $focused))
                Text("-" + PlayerModel.formatTime(p.durationMs - shown)).font(.system(size: 13, weight: .medium).monospacedDigit()).frame(width: 70, alignment: .trailing)
            }
        }
    }
}

private struct SeekFocus: ViewModifier {
    let enabled: Bool
    let p: PlayerModel
    @Binding var focused: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.zFocus(activate: { p.togglePlay() }, onFocusChange: { focused = $0 }, onMove: { dir in
                switch dir {
                case .left: p.scrub(-1, isRepeat: false); p.showControls(); return true
                case .right: p.scrub(1, isRepeat: false); p.showControls(); return true
                default: return false
                }
            }, ring: false)
        } else {
            content
        }
    }
}
