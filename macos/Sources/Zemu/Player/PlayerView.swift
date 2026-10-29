import SwiftUI
import UniformTypeIdentifiers
import ZemuCore

/** Hosts the engine's video view; moves it when the player falls back to another engine or goes to PiP. */
struct EngineHost: NSViewRepresentable {
    let engineView: NSView
    /** Only the active host claims the video view (the player or the PiP window, never both). */
    var active = true

    func makeNSView(context: Context) -> NSView {
        let host = NSView()
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.black.cgColor
        if active { attach(engineView, to: host) }
        return host
    }

    func updateNSView(_ host: NSView, context: Context) {
        if active && engineView.superview !== host {
            host.subviews.forEach { $0.removeFromSuperview() }
            attach(engineView, to: host)
        }
    }

    private func attach(_ v: NSView, to host: NSView) {
        v.removeFromSuperview()
        v.frame = host.bounds
        v.autoresizingMask = [.width, .height]
        host.addSubview(v)
    }
}

/** The main window, and full screen while playing. */
@MainActor
enum PlayerWindow {
    /** The main window, recorded by RootView. */
    static weak var host: NSWindow?
    static var window: NSWindow? { host ?? NSApp.mainWindow }
    /** Full screen was entered automatically for playback (and is left with it). */
    private(set) static var enteredFullScreen = false

    static var isFullScreen: Bool { window?.styleMask.contains(.fullScreen) ?? false }

    static func toggleFullScreen() {
        if AppModel.shared.pip { AppModel.shared.exitPiP() }
        enteredFullScreen = false
        window?.toggleFullScreen(nil)
    }

    static func enterFullScreenForPlayback() {
        guard !isFullScreen else { return }
        enteredFullScreen = true
        window?.toggleFullScreen(nil)
    }

    static func leavePlayback() {
        if enteredFullScreen && isFullScreen { window?.toggleFullScreen(nil) }
        enteredFullScreen = false
    }
}

/** Records the hosting NSWindow (full screen, focus engine) and turns on mouse-moved events. */
struct WindowReader: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { capture(v) }
        return v
    }
    func updateNSView(_ v: NSView, context: Context) {
        if PlayerWindow.host == nil { DispatchQueue.main.async { capture(v) } }
    }
    private func capture(_ v: NSView) {
        guard let w = v.window else { return }
        PlayerWindow.host = w
        w.acceptsMouseMovedEvents = true
    }
}

struct PlayerView: View {
    @Bindable var p: PlayerModel
    var app = AppModel.shared
    @State private var dropTargeted = false
    @State private var hoveringControls = false
    @State private var lastPointer: CGPoint?

    var body: some View {
        ZStack {
            Color.black
            EngineHost(engineView: p.engine.view, active: !app.pip)
            // Clicks on the video: single toggles play, double toggles full screen.
            Color.clear.contentShape(Rectangle())
                .onTapGesture(count: 2) { PlayerWindow.toggleFullScreen() }
                .onTapGesture(count: 1) { p.togglePlay(); p.showControls() }

            if p.buffering && p.failure == nil {
                ProgressView().controlSize(.large).tint(.white)
            }
            if let n = p.notice {
                Text(n).font(.z(size: 14, weight: .semibold))
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
            if p.subtitlePositionOpen { SubtitlePositionOverlay(p: p) }
        }
        .zFocusScope("player")
        .animation(.easeInOut(duration: 0.2), value: p.controlsVisible)
        .animation(.easeInOut(duration: 0.2), value: p.notice)
        .onContinuousHover { phase in
            // SwiftUI also reports hover when views change under a still cursor (controls fading out,
            // position redraws), which made the controls reappear on their own in full screen.
            guard case .active = phase, !hoveringControls else { return }
            let now = NSEvent.mouseLocation
            defer { lastPointer = now }
            guard let last = lastPointer, hypot(now.x - last.x, now.y - last.y) > 3 else { return }
            p.showControls()
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            _ = providers.first?.loadObject(ofClass: URL.self) { url, _ in
                if let url { Task { @MainActor in p.addSubtitleFile(url) } }
            }
            return true
        }
        .overlay(dropTargeted ? Rectangle().strokeBorder(P.accent, lineWidth: 4) : nil)
        .onAppear {
            p.showControls()
            if app.settings.playerFullScreen { PlayerWindow.enterFullScreenForPlayback() }
        }
        .onDisappear {
            if !app.pip { PlayerWindow.leavePlayback() }
        }
    }

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                IconButton(icon: "chevron.left", help: "Back (Esc / Ⓑ)", size: 40) { p.close() }
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.title).font(.z(size: 22, weight: .black)).lineLimit(1)
                    if let l = p.label { Text(l).font(.z(size: 14)).foregroundStyle(Palette.textSecondary).lineLimit(1) }
                    Text("\(p.streamLabel)  ·  \(p.engineName)").font(.z(size: 12)).foregroundStyle(Palette.textMuted).lineLimit(1)
                }
                Spacer()
                AirPlayButton(p: p).frame(width: 40, height: 40)
            }
            .padding(.horizontal, 32)
            .padding(.top, 28)
            .padding(.bottom, 40)
            .background(LinearGradient(colors: [.black.opacity(0.8), .clear], startPoint: .top, endPoint: .bottom))

            Spacer()

            VStack(spacing: 14) {
                SeekBar(p: p, focusable: true)
                buttons
                hint
            }
            .padding(.horizontal, 24)
            .padding(.top, 50)
            .padding(.bottom, 22)
            .background(LinearGradient(colors: [.clear, .black.opacity(0.9)], startPoint: .top, endPoint: .bottom))
            .onHover { hoveringControls = $0; if $0 { p.showControls() } }
        }
    }

    private var hint: some View {
        let inMenu = FocusEngine.shared.focused?.scope == "player"
        return Text(inMenu ? "←→ choose · Return / Ⓐ select · ↓ / Ⓑ hide"
                    : "Space / Ⓐ play · ←→ seek · Ⓧ subtitles · Ⓨ audio · LB/RB ±10s · T / View: Picture in Picture")
            .font(.z(size: 11)).foregroundStyle(Palette.textMuted).lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
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
                IconButton(icon: "camera", help: "Save frame to Pictures (⌘S)") { p.saveFrame() }
                pipButton
                fullScreenButton
            }
            HStack(spacing: 10) {
                leftButtons
                Spacer(minLength: 8)
                subtitleMenu
                playerMenu("ellipsis", "More", title: "More") { moreItems }
                pipButton
                fullScreenButton
            }
            HStack(spacing: 8) {
                IconButton(icon: p.isPlaying ? "pause.fill" : "play.fill", help: "Play/Pause", size: 38, preferred: true) { p.togglePlay() }
                Spacer(minLength: 4)
                playerMenu("ellipsis", "More", title: "More") { moreItems }
                pipButton
            }
        }
    }

    private var leftButtons: some View {
        HStack(spacing: 12) {
            IconButton(icon: p.isPlaying ? "pause.fill" : "play.fill", help: p.isPlaying ? "Pause (Space)" : "Play (Space)", size: 44, preferred: true) { p.togglePlay() }
            IconButton(icon: "gobackward.10", help: "Back 10 seconds (J)") { p.seekBy(-10_000) }
            IconButton(icon: "goforward.10", help: "Forward 10 seconds (L)") { p.seekBy(10_000) }
            VolumeControl(p: p)
            if p.nextUp != nil { IconButton(icon: "forward.end.fill", help: "Next episode (N)") { p.playNextNow() } }
        }
    }

    private var pipButton: some View {
        IconButton(icon: "pip.enter", help: "Picture in Picture (T)") { app.enterPiP() }
    }

    private var fullScreenButton: some View {
        IconButton(icon: PlayerWindow.isFullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right", help: "Full screen (F)") { PlayerWindow.toggleFullScreen() }
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
            ActionItem(label: "Subtitle Position…", icon: "arrow.up.and.down") { p.openSubtitlePosition() },
            ActionItem(label: "Subtitle Style…", icon: "textformat") { p.subtitleStyleOpen = true; p.showControls() },
            ActionItem(label: "Add Subtitle File…", icon: "doc.badge.plus") { addSubtitleFile() },
            ActionItem(label: "Delay −0.1 s (Z)", icon: "minus", keepOpen: true) { p.adjustSubtitleDelay(-0.1) },
            ActionItem(label: "Delay +0.1 s (X)", icon: "plus", keepOpen: true) { p.adjustSubtitleDelay(0.1) },
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
            ActionItem(label: "Full Screen", icon: "arrow.up.left.and.arrow.down.right") { PlayerWindow.toggleFullScreen() },
        ]
    }

    private var audioMenu: some View {
        playerMenu("speaker.wave.2.fill", "Audio (A)", title: "Audio") { audioItems }
    }

    private var subtitleMenu: some View {
        playerMenu("captions.bubble.fill", "Subtitles (S)", title: "Subtitles", active: p.currentSubtitleLabel != "Off") { subtitleItems }
            .popover(isPresented: $p.subtitleStyleOpen, arrowEdge: .top) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Subtitle Style").font(.z(size: 14, weight: .bold))
                    Text("Changes apply right away.").font(.z(size: 12)).foregroundStyle(.secondary)
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
        playerMenu("aspectratio", "Picture: \(p.aspect.label) (P)", title: "Picture size", active: p.aspect != .FIT) {
            choiceItems(AspectMode.allCases.map { ($0, $0.label) }, current: p.aspect) { p.setAspect($0) }
        }
    }

    private func playerMenu(_ icon: String, _ help: String, title: String, active: Bool = false, items: @escaping () -> [ActionItem]) -> some View {
        ZMenu(title: title, items: items) { lit in
            Image(systemName: icon).font(.z(size: 15, weight: .semibold))
                .frame(width: 38, height: 38)
                .foregroundStyle(active ? P.onAccent : .white)
                .background(Circle().fill(active ? P.accent.opacity(0.9) : Color.white.opacity(lit ? 0.26 : 0.14)))
                .scaleEffect(lit ? 1.08 : 1)
                .help(help)
        }
    }

    private func addSubtitleFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ["srt", "ass", "ssa", "vtt", "sub"].compactMap { UTType(filenameExtension: $0) }
        if panel.runModal() == .OK, let url = panel.url { p.addSubtitleFile(url) }
    }

    // MARK: Overlays

    @ViewBuilder
    private var overlays: some View {
        if let seg = p.activeSegment, p.countdown == nil, !p.stillWatchingPrompt {
            HStack(spacing: 6) {
                ZButton(title: seg.type.skipLabel + "  (Return / Ⓐ)", icon: "forward.end.fill", primary: true) { p.skipSegment() }
                ZButton(title: "Dismiss") { p.dismissSegment() }
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.55)))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.trailing, 40).padding(.bottom, p.controlsVisible ? 170 : 50)
        }
        if let next = p.upNext, let seconds = p.countdown {
            let recommended = p.nextUp == nil
            VStack(alignment: .leading, spacing: 4) {
                Text(recommended ? "Up next · recommended for you" : "Next episode").font(.z(size: 12.5)).foregroundStyle(Palette.textSecondary)
                Text(recommended ? next.displayTitle : "S\(next.season ?? 0) E\(next.episodeNumber) · \(next.displayTitle)").font(.z(size: 17, weight: .bold)).lineLimit(2)
                Text(seconds > 0 ? "Playing in \(seconds)s" : "Starting…").font(.z(size: 13)).foregroundStyle(Palette.textSecondary)
                HStack(spacing: 10) {
                    ZButton(title: "Play Now", icon: "play.fill", primary: true) { p.playNextNow() }
                    ZButton(title: "Cancel") { p.cancelCountdown() }
                }
                .padding(.top, 10)
                Text("Return / Ⓐ play now · Esc / Ⓑ cancel").font(.z(size: 11)).foregroundStyle(Palette.textMuted).padding(.top, 4)
            }
            .padding(20)
            .frame(width: 380, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(P.surface.opacity(0.95)))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.trailing, 40).padding(.bottom, p.controlsVisible ? 170 : 40)
        }
        if p.stillWatchingPrompt {
            dialog {
                Text("Are you still watching?").font(.z(size: 26, weight: .black))
                Text(p.title).foregroundStyle(Palette.textSecondary).padding(.bottom, 12)
                ZButton(title: "Continue Watching", primary: true, preferred: true) { p.answerStillWatching(true) }
                ZButton(title: "Continue and Don't Ask Again") { p.answerStillWatching(true, dontAskAgain: true) }
                ZButton(title: "Back to Browsing") { p.answerStillWatching(false) }
            }
            .onAppear { FocusEngine.shared.focusPreferred(scope: "player") }
        }
        if let f = p.failure {
            dialog {
                Text("This video can't be played here").font(.z(size: 24, weight: .black))
                Text(f.detail).font(.z(size: 13)).foregroundStyle(Palette.textSecondary).padding(.bottom, 12).textSelection(.enabled)
                HStack(spacing: 10) {
                    ZButton(title: "Open in \(ExternalPlayer.installed.first ?? "External Player")", icon: "arrow.up.forward.app", primary: true, preferred: true) { p.openExternally() }
                    ZButton(title: "Retry", icon: "arrow.clockwise") { p.retry() }
                    ZButton(title: "Copy Link", icon: "link") { p.copyStreamURL() }
                    ZButton(title: "Back") { p.close() }
                }
            }
            .onAppear { FocusEngine.shared.focusPreferred(scope: "player") }
        }
    }

    private func dialog<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        ZStack {
            Color.black.opacity(0.6)
            VStack(alignment: .leading, spacing: 10, content: content)
                .padding(28)
                .frame(width: 560, alignment: .leading)
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
                Text("\(PlayerModel.formatTime(t))   (\(delta >= 0 ? "+" : "−")\(PlayerModel.formatTime(abs(delta))))").font(.z(size: 16, weight: .bold))
            }
            HStack(spacing: 12) {
                Text(PlayerModel.formatTime(shown)).font(.z(size: 13, weight: .medium).monospacedDigit()).frame(width: 64, alignment: .leading)
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
                                .font(.z(size: 12, weight: .semibold).monospacedDigit())
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
                Text("-" + PlayerModel.formatTime(p.durationMs - shown)).font(.z(size: 13, weight: .medium).monospacedDigit()).frame(width: 70, alignment: .trailing)
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

private struct VolumeControl: View {
    let p: PlayerModel
    @State private var hover = false

    var body: some View {
        HStack(spacing: 6) {
            IconButton(icon: p.muted || p.volume == 0 ? "speaker.slash.fill" : p.volume < 50 ? "speaker.wave.1.fill" : "speaker.wave.3.fill", help: "Mute (M) · ↑↓ volume") { p.toggleMute() }
            if hover {
                Slider(value: Binding(get: { p.muted ? 0 : p.volume }, set: { p.setVolume($0) }), in: 0...130)
                    .frame(width: 110)
                    .tint(P.accent)
                    .transition(.opacity.combined(with: .move(edge: .leading)))
            }
        }
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hover = h } }
    }
}

/**
 * Moving the subtitles on screen up or down while the video plays, e.g. off text burned into the
 * picture or into the black bars: only a slim bar at the top shows.
 */
private struct SubtitlePositionOverlay: View {
    let p: PlayerModel
    var app = AppModel.shared

    var body: some View {
        GeometryReader { g in
            ZStack {
                VStack {
                    HStack(spacing: 14) {
                        Text("Subtitle position").font(.z(size: 14, weight: .bold))
                        Button { p.moveSubtitles(0.01) } label: { Image(systemName: "chevron.up").frame(width: 28, height: 28) }
                            .buttonStyle(.plain).buttonRepeatBehavior(.enabled)
                        Text("\(Int((app.settings.subtitleBottom * 100).rounded()))%").font(.z(size: 14, weight: .semibold)).monospacedDigit()
                        Button { p.moveSubtitles(-0.01) } label: { Image(systemName: "chevron.down").frame(width: 28, height: 28) }
                            .buttonStyle(.plain).buttonRepeatBehavior(.enabled)
                        Text("Up/Down keys too").font(.z(size: 12)).foregroundStyle(Palette.textSecondary)
                        Button("Done") { p.subtitlePositionOpen = false }.buttonStyle(.plain).font(.z(size: 14, weight: .bold)).foregroundStyle(P.accent)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18).padding(.vertical, 8)
                    .background(Capsule().fill(.black.opacity(0.7)))
                    .padding(.top, 24)
                    Spacer()
                }
            }
            .frame(width: g.size.width, height: g.size.height)
        }
    }
}
