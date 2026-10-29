import AppKit
import OpenGL.GL3
import CMpv
import ZemuCore

/**
 * libmpv-backed player. Video is drawn through mpv's render API into a CAOpenGLLayer (the approach
 * IINA uses); decoding uses VideoToolbox when possible. libmpv is loaded at runtime from the app
 * bundle or Homebrew.
 */
@MainActor
final class MPV: PlaybackEngine {
    // MARK: Library

    /** Where libmpv was loaded from, or nil when it isn't available. */
    nonisolated static let libraryPath: String? = {
        var candidates: [String] = []
        if let fw = Bundle.main.privateFrameworksPath { candidates.append("\(fw)/libmpv.2.dylib") }
        candidates += ["/opt/homebrew/lib/libmpv.2.dylib", "/opt/homebrew/lib/libmpv.dylib", "/usr/local/lib/libmpv.2.dylib", "/usr/local/lib/libmpv.dylib"]
        let cStrings = candidates.map { strdup($0) } + [nil]
        defer { cStrings.forEach { free($0) } }
        let loaded = cStrings.withUnsafeBufferPointer { buf in
            buf.baseAddress!.withMemoryRebound(to: UnsafePointer<CChar>?.self, capacity: buf.count) { zm_mpv_load($0) }
        }
        return loaded.map { String(cString: $0) }
    }()

    nonisolated static var available: Bool { libraryPath != nil }

    nonisolated static var version: String? {
        guard available, let h = mpv_create() else { return nil }
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
    fileprivate var renderContext: OpaquePointer?
    private let videoView = MPVVideoView()
    var view: NSView { videoView }

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
        guard MPV.available, let h = mpv_create() else { return }
        handle = h
        let opts: [(String, String)] = [
            ("vo", "libmpv"),
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
        videoView.player = self
    }

    private func observe(_ name: String, _ id: Prop, _ format: mpv_format) {
        guard let h = handle else { return }
        mpv_observe_property(h, id.rawValue, name, format)
    }

    // MARK: Rendering

    /** Called by the layer with its GL context current. */
    fileprivate func createRenderContext() {
        guard let h = handle, renderContext == nil else { return }
        var initParams = mpv_opengl_init_params(get_proc_address: zm_gl_get_proc_address, get_proc_address_ctx: nil)
        let api = strdup(MPV_RENDER_API_TYPE_OPENGL)
        defer { free(api) }
        var rc: OpaquePointer?
        withUnsafeMutablePointer(to: &initParams) { ip in
            var params = [
                mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE, data: UnsafeMutableRawPointer(api)),
                mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, data: UnsafeMutableRawPointer(ip)),
                mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
            ]
            mpv_render_context_create(&rc, h, &params)
        }
        guard let rc else { return }
        renderContext = rc
        let layer = Unmanaged.passUnretained(videoView.glLayer).toOpaque()
        mpv_render_context_set_update_callback(rc, { ctx in
            guard let ctx else { return }
            let layer = Unmanaged<MPVLayer>.fromOpaque(ctx).takeUnretainedValue()
            DispatchQueue.main.async { layer.setNeedsDisplay() }
        }, layer)
    }

    fileprivate func render(fbo: GLint, width: GLint, height: GLint) {
        guard let rc = renderContext else { return }
        var target = mpv_opengl_fbo(fbo: Int32(fbo), w: Int32(width), h: Int32(height), internal_format: 0)
        var flip: Int32 = 1
        withUnsafeMutablePointer(to: &target) { t in
            withUnsafeMutablePointer(to: &flip) { f in
                var params = [
                    mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_FBO, data: UnsafeMutableRawPointer(t)),
                    mpv_render_param(type: MPV_RENDER_PARAM_FLIP_Y, data: UnsafeMutableRawPointer(f)),
                    mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
                ]
                mpv_render_context_render(rc, &params)
            }
        }
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
        // The usual 8% margin (scaled pixels of a 720-line frame); the position setting moves every
        // line from there with sub-pos, which works with the file's own style too ("scale").
        set("sub-margin-y", String(Int(0.08 * 720)))
        set("sub-pos", String(Int((100 - (s.subtitleBottom - 0.08) * 100).rounded())))
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

    /** Releases mpv. The render context has to go first, with the layer's GL context current. */
    func stop() {
        guard !destroyed, let h = handle else { return }
        destroyed = true
        onEvent = nil
        command(["stop"])
        videoView.glLayer.teardown { [renderContext] in
            if let rc = renderContext {
                mpv_render_context_set_update_callback(rc, nil, nil)
                mpv_render_context_free(rc)
            }
        }
        renderContext = nil
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

final class MPVVideoView: NSView {
    let glLayer = MPVLayer()
    weak var player: MPV? { didSet { glLayer.player = player } }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer = glLayer
        glLayer.backgroundColor = NSColor.black.cgColor
        glLayer.needsDisplayOnBoundsChange = true
        layerContentsRedrawPolicy = .duringViewResize
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        glLayer.contentsScale = window?.backingScaleFactor ?? 2
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        glLayer.contentsScale = window?.backingScaleFactor ?? 2
        glLayer.setNeedsDisplay()
    }

    // Clicks go to the SwiftUI controls on top.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class MPVLayer: CAOpenGLLayer, @unchecked Sendable {
    weak var player: MPV?
    private var cglContext: CGLContextObj?
    private var cglPixelFormat: CGLPixelFormatObj?

    override init() {
        super.init()
        isAsynchronous = false
        isOpaque = true
    }

    override init(layer: Any) { super.init(layer: layer) }
    required init?(coder: NSCoder) { fatalError() }

    /**
     * One pixel format and one GL context for the layer's whole life. mpv's render context is
     * tied to the GL context, and Core Animation would otherwise make a new one whenever the
     * view moves to another window (Picture in Picture), leaving the video black.
     */
    private lazy var sharedPixelFormat: CGLPixelFormatObj = {
        let attrs: [CGLPixelFormatAttribute] = [
            kCGLPFAOpenGLProfile, CGLPixelFormatAttribute(UInt32(kCGLOGLPVersion_3_2_Core.rawValue)),
            kCGLPFAAccelerated, kCGLPFADoubleBuffer, kCGLPFAAllowOfflineRenderers,
            kCGLPFAColorSize, CGLPixelFormatAttribute(32),
            CGLPixelFormatAttribute(0),
        ]
        var pf: CGLPixelFormatObj?
        var n: GLint = 0
        CGLChoosePixelFormat(attrs, &pf, &n)
        if pf == nil {
            let basic: [CGLPixelFormatAttribute] = [kCGLPFAOpenGLProfile, CGLPixelFormatAttribute(UInt32(kCGLOGLPVersion_3_2_Core.rawValue)), CGLPixelFormatAttribute(0)]
            CGLChoosePixelFormat(basic, &pf, &n)
        }
        return pf!
    }()

    private lazy var sharedContext: CGLContextObj = {
        var ctx: CGLContextObj?
        CGLCreateContext(sharedPixelFormat, nil, &ctx)
        var swap: GLint = 1
        CGLSetParameter(ctx!, kCGLCPSwapInterval, &swap)
        return ctx!
    }()

    override func copyCGLPixelFormat(forDisplayMask mask: UInt32) -> CGLPixelFormatObj { sharedPixelFormat }

    override func copyCGLContext(forPixelFormat pf: CGLPixelFormatObj) -> CGLContextObj {
        let ctx = sharedContext
        cglContext = ctx
        if cglPixelFormat == nil {
            cglPixelFormat = sharedPixelFormat
            CGLSetCurrentContext(ctx)
            let p = player
            MainActor.assumeIsolated { p?.createRenderContext() }
        }
        return ctx
    }

    // Keep the shared context alive when Core Animation lets go of it.
    override func releaseCGLContext(_ ctx: CGLContextObj) {}
    override func releaseCGLPixelFormat(_ pf: CGLPixelFormatObj) {}

    override func canDraw(inCGLContext ctx: CGLContextObj, pixelFormat pf: CGLPixelFormatObj, forLayerTime t: CFTimeInterval, displayTime ts: UnsafePointer<CVTimeStamp>?) -> Bool {
        true
    }

    override func draw(inCGLContext ctx: CGLContextObj, pixelFormat pf: CGLPixelFormatObj, forLayerTime t: CFTimeInterval, displayTime ts: UnsafePointer<CVTimeStamp>?) {
        var fbo: GLint = 0
        glGetIntegerv(GLenum(GL_DRAW_FRAMEBUFFER_BINDING), &fbo)
        var viewport = [GLint](repeating: 0, count: 4)
        glGetIntegerv(GLenum(GL_VIEWPORT), &viewport)
        let p = player
        let hasContext = MainActor.assumeIsolated { p?.renderContext != nil }
        if hasContext {
            MainActor.assumeIsolated { p?.render(fbo: fbo, width: viewport[2], height: viewport[3]) }
        } else {
            glClearColor(0, 0, 0, 1)
            glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
        }
        glFlush()
    }

    /** Runs [work] with this layer's GL context current (to free mpv's render context). */
    func teardown(_ work: () -> Void) {
        if let ctx = cglContext {
            CGLLockContext(ctx)
            CGLSetCurrentContext(ctx)
            work()
            CGLUnlockContext(ctx)
        } else {
            work()
        }
    }
}
