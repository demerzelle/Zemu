import AppKit
import ZemuCore

/** Picture sizes. [zoom] > 1 enlarges the picture past the window edges. */
enum AspectMode: String, CaseIterable {
    case FIT, ZOOM, ZOOM_115, ZOOM_133, STRETCH, CENTER

    var label: String {
        switch self {
        case .FIT: "Fit"; case .ZOOM: "Fill window"; case .ZOOM_115: "Zoom 115%"; case .ZOOM_133: "Zoom 133%"
        case .STRETCH: "Stretch"; case .CENTER: "Original size"
        }
    }

    var zoom: Double {
        switch self { case .ZOOM_115: 1.15; case .ZOOM_133: 1.33; default: 1 }
    }
}

enum TrackKind: String { case audio, sub, video }

struct TrackInfo: Identifiable, Hashable {
    /** Engine-specific id (mpv track id, or AVMediaSelection index). */
    let id: Int
    let kind: TrackKind
    var label: String
    let lang: String?
    var selected: Bool
    let external: Bool
}

enum EngineEvent {
    case loaded
    case position(ms: Int64, durationMs: Int64, bufferedMs: Int64)
    case paused(Bool)
    case buffering(Bool)
    case tracksChanged
    case videoSize(CGSize)
    case ended
    /** [fatal] when nothing will play from this source (dead link, unknown format). */
    case failed(String, fatal: Bool)
}

struct EngineOptions {
    var softwareDecoding = false
    var audioLanguages: [String] = []
    var subtitleLanguages: [String] = []
    var autoSubtitles = false
    var headers: [String: String] = [:]
    var volume: Double = 100
    var speed: Double = 1
}

/** The built-in players: mpv (everything) and AVPlayer (MP4/HLS, when mpv isn't available). */
@MainActor
protocol PlaybackEngine: AnyObject {
    var name: String { get }
    var view: NSView { get }
    var onEvent: ((EngineEvent) -> Void)? { get set }

    func load(url: String, startMs: Int64, subtitles: [SubtitleTrack], options: EngineOptions)
    func setPaused(_ paused: Bool)
    func seek(toMs: Int64, exact: Bool)
    func setSpeed(_ speed: Double)
    func setVolume(_ volume: Double)
    func setMuted(_ muted: Bool)
    func tracks() -> [TrackInfo]
    /** nil turns subtitles off. */
    func select(_ track: TrackInfo?, kind: TrackKind)
    func applySubtitleStyle(_ s: AppSettings)
    func setAspect(_ mode: AspectMode)
    /** Snapshot of the current frame, for "Save frame". */
    func screenshot(to url: URL) -> Bool
    func stop()
}

enum Lang {
    static func label(_ code: String?) -> String? {
        guard let code, let n = Languages.normalize(code) else { return nil }
        return Languages.displayName(n)
    }
}
