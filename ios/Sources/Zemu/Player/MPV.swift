import UIKit
import Libmpv
import ZemuCore

/**
 * libmpv-backed player (MPVKit, linked into the app). Video is drawn by mpv's gpu-next output
 * through MoltenVK into a CAMetalLayer; decoding uses VideoToolbox when possible.
 */
@MainActor
final class MPV: PlaybackEngine {
    // MARK: Library

    nonisolated static let available = true

    nonisolated static var version: String? {
        guard let h = mpv_create() else { return nil }
        defer { mpv_terminate_destroy(h) }
        mpv_initialize(h)
        guard let v = mpv_get_property_string(h, "mpv-version") else { return nil }
        defer { mpv_free(v) }
        return String(cString: v)
    }

    // MARK: State

    let name = "mpv"
    var onEvent: ((EngineEvent) -> Void)?
    nonisolated(unsafe) private(set) var handle: OpaquePointer?
    private let videoView = MPVVideoView()
    var view: UIView { videoView }

    nonisolated private let events = DispatchQueue(label: "zemu.mpv.events")
    private var pendingSubs: [SubtitleTrack] = []
    private var autoSubs = false
    private var subLangs: [String] = []
    private var position: Double = 0
    private var duration: Double = 0
    private var cacheTime: Double = 0
    nonisolated(unsafe) private var destroyed = false

    private enum Prop: UInt64 {
        case timePos = 1, duration, pause, pausedForCache, cacheTime, eofReached, trackCount, dwidth, dheight, seeking
    }

    init() {
        guard let h = mpv_create() else { return }
        handle = h
        var layer = videoView.layer
        mpv_set_option(h, "wid", MPV_FORMAT_INT64, &layer)
        let opts: [(String, String)] = [
            ("vo", "gpu-next"),
            ("gpu-api", "vulkan"),
            ("gpu-context", "moltenvk"),
            ("hwdec", "videotoolbox"),
            ("keep-open", "yes"),
            ("idle", "yes"),
            ("input-default-bindings", "no"),
            ("input-vo-keyboard", "no"),
            ("osc", "no"),
            ("terminal", "no"),
            ("config", "no"),
            ("ytdl", "no"),
            ("load-scripts", "no"),
            // Zemu draws its own UI; mpv's built-in Lua scripts aren't needed.
            ("load-stats-overlay", "no"),
            ("load-console", "no"),
            ("load-auto-profiles", "no"),
            ("load-select", "no"),
            ("load-positioning", "no"),
            ("load-commands", "no"),
            ("load-context-menu", "no"),
            ("user-agent", HTTP.userAgent),
            ("cache", "yes"),
            ("demuxer-max-bytes", "400MiB"),
            ("demuxer-max-back-bytes", "100MiB"),
            ("demuxer-readahead-secs", "60"),
            ("network-timeout", "30"),
            ("sub-auto", "no"),
            ("audio-client-name", "Zemu"),
            ("audio-pitch-correction", "yes"),
            ("screenshot-format", "png"),
            ("video-rotate", "no"),
            ("tone-mapping", "auto"),
            ("target-colorspace-hint", "yes"),
        ]
        for (k, v) in opts { mpv_set_option_string(h, k, v) }
        mpv_request_log_messages(h, "error")
        guard mpv_initialize(h) >= 0 else { mpv_terminate_destroy(h); handle = nil; return }

        observe("time-pos", .timePos, MPV_FORMAT_DOUBLE)
        observe("duration", .duration, MPV_FORMAT_DOUBLE)
        observe("pause", .pause, MPV_FORMAT_FLAG)
        observe("paused-for-cache", .pausedForCache, MPV_FORMAT_FLAG)
        observe("demuxer-cache-time", .cacheTime, MPV_FORMAT_DOUBLE)
        observe("eof-reached", .eofReached, MPV_FORMAT_FLAG)
        observe("track-list/count", .trackCount, MPV_FORMAT_INT64)
        observe("dwidth", .dwidth, MPV_FORMAT_INT64)
        observe("dheight", .dheight, MPV_FORMAT_INT64)
        observe("seeking", .seeking, MPV_FORMAT_FLAG)

        let ctx = Unmanaged.passUnretained(self).toOpaque()
        mpv_set_wakeup_callback(h, { ctx in
            guard let ctx else { return }
            let me = Unmanaged<MPV>.fromOpaque(ctx).takeUnretainedValue()
            me.events.async { me.drainEvents() }
        }, ctx)
    }

    private func observe(_ name: String, _ id: Prop, _ format: mpv_format) {
        guard let h = handle else { return }
        mpv_observe_property(h, id.rawValue, name, format)
    }

    // MARK: Commands

    @discardableResult
    func command(_ args: [String]) -> Int32 {
        guard let h = handle else { return -1 }
        var cargs = args.map { UnsafePointer(strdup($0)) } + [nil]
        defer { cargs.forEach { free(UnsafeMutablePointer(mutating: $0)) } }
        return mpv_command(h, &cargs)
    }

    func set(_ name: String, _ value: String) {
        guard let h = handle else { return }
        mpv_set_property_string(h, name, value)
    }

    func get(_ name: String) -> String? {
        guard let h = handle, let v = mpv_get_property_string(h, name) else { return nil }
        defer { mpv_free(v) }
        return String(cString: v)
    }

    func getFlag(_ name: String) -> Bool {
        guard let h = handle else { return false }
        var v: Int32 = 0
        mpv_get_property(h, name, MPV_FORMAT_FLAG, &v)
        return v != 0
    }

    // MARK: PlaybackEngine

    func load(url: String, startMs: Int64, subtitles: [SubtitleTrack], options: EngineOptions) {
        guard handle != nil else {
            onEvent?(.failed("mpv isn't available", fatal: true))
            return
        }
        pendingSubs = subtitles
        autoSubs = options.autoSubtitles
        subLangs = options.subtitleLanguages
        position = 0; duration = 0; cacheTime = 0
        set("hwdec", options.softwareDecoding ? "no" : "videotoolbox")
        set("alang", options.audioLanguages.joined(separator: ","))
        set("slang", options.subtitleLanguages.joined(separator: ","))
        set("sid", options.autoSubtitles ? "auto" : "no")
        set("start", startMs > 0 ? String(format: "%.3f", Double(startMs) / 1000) : "none")
        set("http-header-fields", options.headers.map { "\($0.key): \($0.value.replacingOccurrences(of: ",", with: "\\,"))" }.joined(separator: ","))
        set("volume", String(options.volume))
        set("speed", String(options.speed))
        set("pause", "no")
        command(["loadfile", url, "replace"])
    }

    func setPaused(_ paused: Bool) {
        if !paused && getFlag("eof-reached") { command(["seek", "0", "absolute"]) }
        set("pause", paused ? "yes" : "no")
    }

    func seek(toMs: Int64, exact: Bool) {
        command(["seek", String(format: "%.3f", Double(max(0, toMs)) / 1000), exact ? "absolute+exact" : "absolute+keyframes"])
    }

    func setSpeed(_ speed: Double) { set("speed", String(speed)) }
    func setVolume(_ volume: Double) { set("volume", String(volume)) }
    func setMuted(_ muted: Bool) { set("mute", muted ? "yes" : "no") }

    func tracks() -> [TrackInfo] {
        let count = Int(get("track-list/count") ?? "0") ?? 0
        var out: [TrackInfo] = []
        for i in 0..<count {
            let p = "track-list/\(i)/"
            guard let type = get(p + "type"), let kind = TrackKind(rawValue: type), kind != .video,
                  let id = Int(get(p + "id") ?? "") else { continue }
            let lang = get(p + "lang")
            let title = get(p + "title")?.nilIfBlank
            let external = get(p + "external") == "yes"
            var extra: [String] = []
            if kind == .audio {
                if let codec = get(p + "codec") { extra.append(MPV.codecName(codec)) }
                if let ch = Int(get(p + "demux-channel-count") ?? "") { extra.append(MPV.channelLabel(ch)) }
            }
            if get(p + "forced") == "yes" { extra.append("Forced") }
            if external { extra.append("external") }
            let base: String
            if let l = Lang.label(lang), let t = title, !t.lowercased().contains(l.lowercased()) { base = "\(l) — \(t)" }
            else { base = title ?? Lang.label(lang) ?? "Track \(id)" }
            out.append(TrackInfo(id: id, kind: kind, label: ([base] + extra).joined(separator: " · "),
                                 lang: lang.flatMap { Languages.normalize($0) }, selected: get(p + "selected") == "yes", external: external))
        }
        return out
    }

    func select(_ track: TrackInfo?, kind: TrackKind) {
        let prop = kind == .audio ? "aid" : "sid"
        set(prop, track.map { String($0.id) } ?? "no")
    }

    func applySubtitleStyle(_ s: AppSettings) {
        set("sub-scale", String(s.subtitleScale))
        set("sub-color", MPV.hex(s.subtitleColor))
        switch s.subtitleBackground {
        case 1: set("sub-border-style", "background-box"); set("sub-back-color", "#99000000")
        case 2: set("sub-border-style", "background-box"); set("sub-back-color", "#FF000000")
        default: set("sub-border-style", "outline-and-shadow")
        }
        switch s.subtitleEdge {
        case 0: set("sub-border-size", "0"); set("sub-shadow-offset", "0")
        case 2: set("sub-border-size", "0"); set("sub-shadow-offset", "2.5"); set("sub-shadow-color", "#C0000000")
        default: set("sub-border-size", "2.6"); set("sub-shadow-offset", "0")
        }
        set("sub-border-color", "#FF000000")
        // sub-margin-y is in scaled pixels of a 720-line frame.
        set("sub-margin-y", String(Int(s.subtitleBottom * 720)))
        set("sub-ass-override", s.keepStyledSubtitles ? "scale" : "force")
        set("sub-delay", String(s.subtitleDelay))
    }

    func setAspect(_ mode: AspectMode) {
        set("keepaspect", mode == .STRETCH ? "no" : "yes")
        set("panscan", mode == .ZOOM ? "1.0" : "0")
        set("video-zoom", mode.zoom > 1 ? String(log2(mode.zoom)) : "0")
        set("video-unscaled", mode == .CENTER ? "downscale-big" : "no")
    }

    func screenshot(to url: URL) -> Bool {
        command(["screenshot-to-file", url.path, "video"]) >= 0
    }

    func stop() {
        guard !destroyed, let h = handle else { return }
        destroyed = true
        onEvent = nil
        command(["stop"])
        mpv_set_wakeup_callback(h, nil, nil)
        handle = nil
        let me = self
        events.async {
            mpv_terminate_destroy(h)
            _ = me // keep self (and the view) alive until mpv is gone
        }
    }

    // MARK: Events

    nonisolated private func drainEvents() {
        while true {
            guard let h = handle, !destroyed, let ev = mpv_wait_event(h, 0) else { return }
            let e = ev.pointee
            if e.event_id == MPV_EVENT_NONE { return }
            var out: EngineEvent?
            var prop: (UInt64, Double?)?
            switch e.event_id {
            case MPV_EVENT_FILE_LOADED:
                out = .loaded
            case MPV_EVENT_END_FILE:
                if let d = e.data?.assumingMemoryBound(to: mpv_event_end_file.self).pointee, d.reason == MPV_END_FILE_REASON_ERROR {
                    let msg = String(cString: mpv_error_string(d.error))
                    out = .failed(msg, fatal: true)
                }
            case MPV_EVENT_PROPERTY_CHANGE:
                if let p = e.data?.assumingMemoryBound(to: mpv_event_property.self).pointee {
                    var v: Double?
                    if let data = p.data {
                        switch p.format {
                        case MPV_FORMAT_DOUBLE: v = data.assumingMemoryBound(to: Double.self).pointee
                        case MPV_FORMAT_FLAG: v = Double(data.assumingMemoryBound(to: Int32.self).pointee)
                        case MPV_FORMAT_INT64: v = Double(data.assumingMemoryBound(to: Int64.self).pointee)
                        default: break
                        }
                    }
                    prop = (e.reply_userdata, v)
                }
            case MPV_EVENT_LOG_MESSAGE:
                if let m = e.data?.assumingMemoryBound(to: mpv_event_log_message.self).pointee {
                    let text = String(cString: m.text).trimmed
                    if !text.isEmpty { NSLog("mpv [%@] %@", String(cString: m.prefix), text) }
                }
            case MPV_EVENT_SHUTDOWN:
                return
            default: break
            }
            let event = out, property = prop
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.destroyed else { return }
                if let event { self.handleEvent(event) }
                if let property { self.handleProperty(property.0, property.1) }
            }
        }
    }

    private func handleEvent(_ e: EngineEvent) {
        if case .loaded = e {
            for s in pendingSubs {
                let lang = Languages.normalize(s.lang) ?? s.lang
                command(["sub-add", s.url, "auto", "\(Languages.displayName(lang)) (external)", lang])
            }
            // External subtitles arrive after mpv's own pick; choose one if asked to and nothing is on.
            if autoSubs && (get("sid") == "no" || get("sid") == nil) {
                let subs = tracks().filter { $0.kind == .sub }
                if let pick = subLangs.lazy.compactMap({ l in subs.first { $0.lang == l } }).first { select(pick, kind: .sub) }
            }
        }
        onEvent?(e)
    }

    private func handleProperty(_ id: UInt64, _ v: Double?) {
        guard let p = Prop(rawValue: id) else { return }
        switch p {
        case .timePos:
            position = v ?? 0
            emitPosition()
        case .duration:
            duration = v ?? 0
            emitPosition()
        case .cacheTime:
            cacheTime = v ?? 0
        case .pause:
            onEvent?(.paused((v ?? 0) != 0))
        case .pausedForCache:
            onEvent?(.buffering((v ?? 0) != 0))
        case .seeking:
            if (v ?? 0) != 0 { onEvent?(.buffering(true)) } else { onEvent?(.buffering(getFlag("paused-for-cache"))) }
        case .eofReached:
            if (v ?? 0) != 0 { onEvent?(.ended) }
        case .trackCount:
            onEvent?(.tracksChanged)
        case .dwidth, .dheight:
            if let w = Double(get("dwidth") ?? ""), let h = Double(get("dheight") ?? ""), w > 0, h > 0 {
                onEvent?(.videoSize(CGSize(width: w, height: h)))
            }
        }
    }

    private func emitPosition() {
        onEvent?(.position(ms: Int64(position * 1000), durationMs: Int64(duration * 1000), bufferedMs: Int64(max(position, cacheTime) * 1000)))
    }

    // MARK: Helpers

    static func hex(_ argb: UInt32) -> String { String(format: "#%08X", argb) }

    static func codecName(_ c: String) -> String {
        switch c.lowercased() {
        case "ac3": "Dolby Digital"; case "eac3": "Dolby Digital+"; case "truehd": "TrueHD"; case "dts": "DTS"
        case "aac": "AAC"; case "opus": "Opus"; case "flac": "FLAC"; case "mp3": "MP3"; case "vorbis": "Vorbis"
        default: c.uppercased()
        }
    }

    static func channelLabel(_ n: Int) -> String {
        switch n { case 1: "Mono"; case 2: "Stereo"; case 6: "5.1"; case 8: "7.1"; default: "\(n) ch" }
    }
}

// MARK: - Video view

/** mpv draws into this view's CAMetalLayer (passed as "wid"). */
final class MPVVideoView: UIView {
    override class var layerClass: AnyClass { MPVMetalLayer.self }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        isUserInteractionEnabled = false // touches go to the SwiftUI controls on top
        let l = layer as! MPVMetalLayer
        l.contentsScale = UIScreen.main.nativeScale
        l.framebufferOnly = true
    }

    required init?(coder: NSCoder) { fatalError() }
}

final class MPVMetalLayer: CAMetalLayer {
    // MoltenVK briefly sets the drawable to 1x1 to finish a presentation, which flickers and can stick.
    // https://github.com/mpv-player/mpv/pull/13651
    override var drawableSize: CGSize {
        get { super.drawableSize }
        set { if Int(newValue.width) > 1 && Int(newValue.height) > 1 { super.drawableSize = newValue } }
    }

    // mpv sets this from its render thread; EDR only turns on when it's set on the main thread.
    override var wantsExtendedDynamicRangeContent: Bool {
        get { super.wantsExtendedDynamicRangeContent }
        set {
            if Thread.isMainThread { super.wantsExtendedDynamicRangeContent = newValue }
            else { DispatchQueue.main.sync { super.wantsExtendedDynamicRangeContent = newValue } }
        }
    }
}
