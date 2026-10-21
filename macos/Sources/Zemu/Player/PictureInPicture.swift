import SwiftUI
import AppKit
import ZemuCore

/**
 * Picture in Picture: the video moves into a small floating window that stays above other apps
 * and on every Space. It can be dragged anywhere and resized (keeping the video's shape), and
 * remembers its size and place. Zemu stays usable underneath.
 */
final class PiPPanel: NSPanel {
    var keyHandler: ((NSEvent) -> Bool)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func handleKey(_ e: NSEvent) -> Bool { keyHandler?(e) ?? false }
}

@MainActor
final class PiPController: NSObject, NSWindowDelegate {
    static let shared = PiPController()
    private var panel: PiPPanel?
    private var closingByApp = false

    var isShowing: Bool { panel != nil }

    func show(_ p: PlayerModel) {
        if panel != nil { return }
        let size = Self.size(for: p.videoSize, width: 480)
        let panel = PiPPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        [.closeButton, .miniaturizeButton, .zoomButton].forEach { panel.standardWindowButton($0)?.isHidden = true }
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .black
        panel.hasShadow = true
        panel.minSize = NSSize(width: 240, height: 135)
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: PiPView(p: p))
        if let ratio = p.videoSize { panel.contentAspectRatio = ratio }
        else { panel.contentAspectRatio = NSSize(width: 16, height: 9) }
        panel.keyHandler = { [weak p] e in
            guard let p else { return false }
            switch e.keyCode {
            case 49: p.togglePlay(); return true // space
            case 53: AppModel.shared.exitPiP(); return true // esc: back to the full player
            case 123: p.seekBy(-10_000); return true
            case 124: p.seekBy(10_000); return true
            default: return false
            }
        }
        // Remember where the user put it; first time, the bottom-right corner.
        if !panel.setFrameUsingName("ZemuPiP") {
            let screen = (PlayerWindow.host?.screen ?? NSScreen.main)?.visibleFrame ?? .zero
            panel.setFrameOrigin(NSPoint(x: screen.maxX - size.width - 24, y: screen.minY + 24))
        }
        panel.setFrameAutosaveName("ZemuPiP")
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func updateAspect(_ size: CGSize?) {
        guard let panel, let size, size.width > 0, size.height > 0 else { return }
        panel.contentAspectRatio = size
        // Fit the current width to the new shape.
        var f = panel.frame
        let h = (f.width * size.height / size.width).rounded()
        f.origin.y += f.height - h
        f.size.height = h
        panel.setFrame(f, display: true, animate: true)
    }

    func close() {
        guard let panel else { return }
        closingByApp = true
        panel.saveFrame(usingName: "ZemuPiP")
        panel.close()
        self.panel = nil
        closingByApp = false
    }

    /** Closing the window (⌘W) stops playback. */
    func windowWillClose(_ notification: Notification) {
        guard !closingByApp else { return }
        panel = nil
        AppModel.shared.pip = false
        AppModel.shared.player?.close()
    }

    static func size(for video: CGSize?, width: CGFloat) -> NSSize {
        let ratio = video.map { $0.height / max($0.width, 1) } ?? 9.0 / 16
        return NSSize(width: width, height: (width * ratio).rounded())
    }
}

/** Drags the window and turns a double-click into "back to the app". */
private struct DragArea: NSViewRepresentable {
    let onDoubleClick: () -> Void

    final class V: NSView {
        var onDoubleClick: (() -> Void)?
        override func mouseDown(with e: NSEvent) {
            if e.clickCount == 2 { onDoubleClick?() } else { window?.performDrag(with: e) }
        }
        override var mouseDownCanMoveWindow: Bool { true }
    }

    func makeNSView(context: Context) -> V { let v = V(); v.onDoubleClick = onDoubleClick; return v }
    func updateNSView(_ v: V, context: Context) { v.onDoubleClick = onDoubleClick }
}

private struct PiPView: View {
    let p: PlayerModel
    var app = AppModel.shared
    @State private var hover = false

    var body: some View {
        ZStack {
            Color.black
            EngineHost(engineView: p.engine.view, active: app.pip)
            DragArea { app.exitPiP() }
            if p.buffering && p.failure == nil { ProgressView().controlSize(.small).tint(.white).allowsHitTesting(false) }
            if hover || !p.isPlaying {
                ZStack {
                    LinearGradient(colors: [.black.opacity(0.55), .clear, .black.opacity(0.65)], startPoint: .top, endPoint: .bottom)
                        .allowsHitTesting(false)
                    VStack {
                        HStack {
                            pipButton("xmark", help: "Stop") { p.close() }
                            Spacer()
                            pipButton("pip.exit", help: "Back to Zemu (double-click)") { app.exitPiP() }
                        }
                        Spacer()
                        HStack(spacing: 22) {
                            pipButton("gobackward.10", help: "Back 10 seconds") { p.seekBy(-10_000) }
                            pipButton(p.isPlaying ? "pause.fill" : "play.fill", help: "Play/Pause", big: true) { p.togglePlay() }
                            pipButton("goforward.10", help: "Forward 10 seconds") { p.seekBy(10_000) }
                        }
                        Spacer()
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.25))
                                Capsule().fill(P.accent).frame(width: g.size.width * CGFloat(p.durationMs > 0 ? min(1, Double(p.positionMs) / Double(p.durationMs)) : 0))
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { loc in p.seek(toFraction: Double(loc.x / g.size.width)) }
                        }
                        .frame(height: 4)
                    }
                    .padding(10)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: hover)
        .onHover { hover = $0 }
        .onChange(of: p.videoSize) { _, s in PiPController.shared.updateAspect(s) }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }

    private func pipButton(_ icon: String, help: String, big: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.z(size: big ? 22 : 13, weight: .bold))
                .frame(width: big ? 46 : 28, height: big ? 46 : 28)
                .background(Circle().fill(Color.black.opacity(0.5)))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
