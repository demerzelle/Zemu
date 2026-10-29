import AVFoundation
import SwiftUI
import ZemuCore

/**
 * AVPlayer fallback for when libmpv isn't available. Plays MP4/MOV/HLS (no MKV, DTS, TrueHD or
 * side-loaded subtitles), which covers some direct links.
 */
@MainActor
final class AVEngine: PlaybackEngine {
    let name = "AVPlayer"
    var onEvent: ((EngineEvent) -> Void)?
    let player = AVPlayer()
    private let playerView = AVVideoView()
    var view: NSView { playerView }
    private var observers: [NSKeyValueObservation] = []
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?

    init() {
        playerView.playerLayer.player = player
        player.automaticallyWaitsToMinimizeStalling = true
    }

    func load(url: String, startMs: Int64, subtitles: [SubtitleTrack], options: EngineOptions) {
        guard let u = URL(string: url) else { onEvent?(.failed("Bad URL", fatal: true)); return }
        let asset = AVURLAsset(url: u, options: ["AVURLAssetHTTPHeaderFieldsKey": options.headers.merging(["User-Agent": HTTP.userAgent]) { a, _ in a }])
        let item = AVPlayerItem(asset: asset)
        observers = [
            item.observe(\.status) { [weak self] item, _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    switch item.status {
                    case .readyToPlay:
                        if startMs > 0 { self.seek(toMs: startMs, exact: false) }
                        self.selectPreferred(options)
                        self.onEvent?(.loaded)
                        self.onEvent?(.tracksChanged)
                    case .failed:
                        self.onEvent?(.failed(item.error?.localizedDescription ?? "AVPlayer can't open this stream", fatal: true))
                    default: break
                    }
                }
            },
            item.observe(\.presentationSize) { [weak self] item, _ in
                MainActor.assumeIsolated { if item.presentationSize.width > 0 { self?.onEvent?(.videoSize(item.presentationSize)) } }
            },
            player.observe(\.timeControlStatus) { [weak self] p, _ in
                MainActor.assumeIsolated {
                    self?.onEvent?(.buffering(p.timeControlStatus == .waitingToPlayAtSpecifiedRate))
                    self?.onEvent?(.paused(p.timeControlStatus == .paused))
                }
            },
        ]
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] t in
            MainActor.assumeIsolated {
                guard let self, let item = self.player.currentItem else { return }
                let d = item.duration.seconds.isFinite ? item.duration.seconds : 0
                let buffered = item.loadedTimeRanges.map { $0.timeRangeValue.end.seconds }.max() ?? t.seconds
                self.onEvent?(.position(ms: Int64(t.seconds * 1000), durationMs: Int64(d * 1000), bufferedMs: Int64(buffered * 1000)))
            }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onEvent?(.ended) }
        }
        player.replaceCurrentItem(with: item)
        player.volume = Float(options.volume / 100)
        player.defaultRate = Float(options.speed)
        player.play()
        if options.speed != 1 { player.rate = Float(options.speed) }
    }

    private func selectPreferred(_ options: EngineOptions) {
        guard let item = player.currentItem else { return }
        Task {
            if let group = try? await item.asset.loadMediaSelectionGroup(for: .audible),
               let pick = options.audioLanguages.lazy.compactMap({ l in group.options.first { Languages.normalize($0.extendedLanguageTag ?? "") == l } }).first {
                item.select(pick, in: group)
            }
            if options.autoSubtitles, let group = try? await item.asset.loadMediaSelectionGroup(for: .legible),
               let pick = options.subtitleLanguages.lazy.compactMap({ l in group.options.first { Languages.normalize($0.extendedLanguageTag ?? "") == l } }).first {
                item.select(pick, in: group)
            }
            onEvent?(.tracksChanged)
        }
    }

    func setPaused(_ paused: Bool) { paused ? player.pause() : player.play() }

    func seek(toMs: Int64, exact: Bool) {
        let t = CMTime(value: max(0, toMs), timescale: 1000)
        player.seek(to: t, toleranceBefore: exact ? .zero : .positiveInfinity, toleranceAfter: exact ? .zero : .positiveInfinity)
    }

    func setSpeed(_ speed: Double) {
        player.defaultRate = Float(speed)
        if player.rate != 0 { player.rate = Float(speed) }
    }

    func setVolume(_ volume: Double) { player.volume = Float(volume / 100) }
    func setMuted(_ muted: Bool) { player.isMuted = muted }

    private func groups() -> [(TrackKind, AVMediaSelectionGroup)] {
        guard let asset = player.currentItem?.asset else { return [] }
        var out: [(TrackKind, AVMediaSelectionGroup)] = []
        // Synchronous accessors are fine here: selection groups are loaded by the time the item is ready.
        if let g = asset.mediaSelectionGroup(forMediaCharacteristic: .audible) { out.append((.audio, g)) }
        if let g = asset.mediaSelectionGroup(forMediaCharacteristic: .legible) { out.append((.sub, g)) }
        return out
    }

    func tracks() -> [TrackInfo] {
        guard let item = player.currentItem else { return [] }
        return groups().flatMap { kind, group in
            group.options.enumerated().map { i, o in
                TrackInfo(id: i, kind: kind, label: o.displayName, lang: o.extendedLanguageTag.flatMap(Languages.normalize),
                          selected: item.currentMediaSelection.selectedMediaOption(in: group) == o, external: false)
            }
        }
    }

    func select(_ track: TrackInfo?, kind: TrackKind) {
        guard let item = player.currentItem, let group = groups().first(where: { $0.0 == kind })?.1 else { return }
        if let track, group.options.indices.contains(track.id) { item.select(group.options[track.id], in: group) }
        else if group.allowsEmptySelection { item.select(nil, in: group) }
    }

    func applySubtitleStyle(_ s: AppSettings) {
        guard let item = player.currentItem else { return }
        let fg = Color(argb: s.subtitleColor)
        let ns = NSColor(fg).usingColorSpace(.sRGB) ?? .white
        var rules: [AVTextStyleRule] = []
        let attrs: [String: Any] = [
            kCMTextMarkupAttribute_ForegroundColorARGB as String: [1, ns.redComponent, ns.greenComponent, ns.blueComponent],
            kCMTextMarkupAttribute_RelativeFontSize as String: 100 * s.subtitleScale,
            kCMTextMarkupAttribute_CharacterBackgroundColorARGB as String: s.subtitleBackground == 0 ? [0, 0, 0, 0] : [s.subtitleBackground == 1 ? 0.6 : 1, 0, 0, 0],
            kCMTextMarkupAttribute_CharacterEdgeStyle as String: s.subtitleEdge == 2 ? kCMTextMarkupCharacterEdgeStyle_DropShadow : s.subtitleEdge == 1 ? kCMTextMarkupCharacterEdgeStyle_Uniform : kCMTextMarkupCharacterEdgeStyle_None,
            kCMTextMarkupAttribute_OrthogonalLinePositionPercentageRelativeToWritingDirection as String: 100 - 100 * s.subtitleBottom,
        ]
        if let r = AVTextStyleRule(textMarkupAttributes: attrs) { rules.append(r) }
        item.textStyleRules = rules
    }

    func setAspect(_ mode: AspectMode) {
        switch mode {
        case .ZOOM, .ZOOM_115, .ZOOM_133: playerView.playerLayer.videoGravity = .resizeAspectFill
        case .STRETCH: playerView.playerLayer.videoGravity = .resize
        default: playerView.playerLayer.videoGravity = .resizeAspect
        }
    }

    func screenshot(to url: URL) -> Bool {
        guard let asset = player.currentItem?.asset else { return false }
        let gen = AVAssetImageGenerator(asset: asset)
        gen.requestedTimeToleranceBefore = .zero
        gen.requestedTimeToleranceAfter = .zero
        guard let cg = try? gen.copyCGImage(at: player.currentTime(), actualTime: nil) else { return false }
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let png = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? png.write(to: url)) != nil
    }

    func stop() {
        onEvent = nil
        observers.forEach { $0.invalidate() }
        observers = []
        if let t = timeObserver { player.removeTimeObserver(t) }
        if let e = endObserver { NotificationCenter.default.removeObserver(e) }
        player.pause()
        player.replaceCurrentItem(with: nil)
    }
}

final class AVVideoView: NSView {
    let playerLayer = AVPlayerLayer()

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer = playerLayer
        playerLayer.backgroundColor = NSColor.black.cgColor
        playerLayer.videoGravity = .resizeAspect
    }

    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
