import Foundation

/** What this Mac can decode and display, used to rank streams ("Best for this Mac"). */
public struct DeviceCapabilities: Sendable {
    public var maxResolution: Int
    public var hevc: Bool
    public var av1: Bool
    public var dolbyVision: Bool
    public var hdr10: Bool
    public var hdr10Plus: Bool
    public var playableAudio: Set<AudioCodec>
    /** Hardware decoders, shown in Settings (software decoding still plays everything else). */
    public var hardwareHevc: Bool
    public var hardwareAv1: Bool

    public init(maxResolution: Int, hevc: Bool, av1: Bool, dolbyVision: Bool, hdr10: Bool, hdr10Plus: Bool,
                playableAudio: Set<AudioCodec>, hardwareHevc: Bool, hardwareAv1: Bool) {
        self.maxResolution = maxResolution; self.hevc = hevc; self.av1 = av1; self.dolbyVision = dolbyVision
        self.hdr10 = hdr10; self.hdr10Plus = hdr10Plus; self.playableAudio = playableAudio
        self.hardwareHevc = hardwareHevc; self.hardwareAv1 = hardwareAv1
    }

    public func canPlay(_ a: AudioCodec) -> Bool { playableAudio.contains(a) }

    /** Everything decodes and plays: used for tests and when detection isn't possible. */
    public static let permissive = DeviceCapabilities(
        maxResolution: 2160, hevc: true, av1: true, dolbyVision: true, hdr10: true, hdr10Plus: true,
        playableAudio: Set(AudioCodec.allCases), hardwareHevc: true, hardwareAv1: true
    )
}

public enum SortOption: String, CaseIterable, Sendable {
    case best, resolution, sizeDesc, sizeAsc, seeders
    public var label: String {
        switch self {
        case .best: "Best match"; case .resolution: "Highest quality"; case .sizeDesc: "Largest size"
        case .sizeAsc: "Smallest size"; case .seeders: "Most seeded"
        }
    }
}

public enum SizeBucket: String, CaseIterable, Sendable {
    case under2, gb2to5, gb5to10, gb10to20, gb20to40, over40

    public var label: String {
        switch self {
        case .under2: "Under 2 GB"; case .gb2to5: "2 – 5 GB"; case .gb5to10: "5 – 10 GB"
        case .gb10to20: "10 – 20 GB"; case .gb20to40: "20 – 40 GB"; case .over40: "40 GB +"
        }
    }

    var range: (Double, Double) {
        switch self {
        case .under2: (0, 2); case .gb2to5: (2, 5); case .gb5to10: (5, 10)
        case .gb10to20: (10, 20); case .gb20to40: (20, 40); case .over40: (40, .greatestFiniteMagnitude)
        }
    }

    public static func of(_ bytes: Int64?) -> SizeBucket? {
        guard let bytes else { return nil }
        let gb = Double(bytes) / 1_073_741_824
        return allCases.first { gb >= $0.range.0 && gb < $0.range.1 }
    }
}

public enum FacetKind: String, CaseIterable, Sendable {
    case quality, audioLang, subLang, size, hdr, codec, audio, channels, source, service, addon
    public var label: String {
        switch self {
        case .quality: "Quality"; case .audioLang: "Audio language"; case .subLang: "Subtitles"; case .size: "Size"
        case .hdr: "HDR"; case .codec: "Video codec"; case .audio: "Audio format"; case .channels: "Channels"
        case .source: "Source"; case .service: "Debrid service"; case .addon: "Addon"
        }
    }
}

public struct FilterState: Equatable, Sendable {
    public var sort: SortOption = .best
    public var selected: [FacetKind: Set<String>] = [:]
    /** Only streams this Mac can decode and display natively. */
    public var deviceFriendlyOnly = false
    public var hideCam = true

    public init(sort: SortOption = .best) { self.sort = sort }

    public var activeCount: Int { selected.values.filter { !$0.isEmpty }.count + (deviceFriendlyOnly ? 1 : 0) }

    public func toggle(_ kind: FacetKind, _ value: String) -> FilterState {
        var s = self
        var cur = selected[kind] ?? []
        if cur.contains(value) { cur.remove(value) } else { cur.insert(value) }
        s.selected[kind] = cur
        return s
    }

    public func clear(_ kind: FacetKind) -> FilterState {
        var s = self
        s.selected[kind] = nil
        return s
    }
}

public struct FacetOption: Hashable, Sendable {
    public var value: String
    public var label: String
    public var count: Int
}

public struct RankedStream: Hashable, Identifiable, Sendable {
    public var stream: ParsedStream
    public var score: Double
    public var recommended: Bool
    public var deviceFriendly: Bool
    public var id: String { stream.key }
}

public enum StreamFilter {
    public static let MULTI = "multi"
    public static let UNSPECIFIED = "und"
    public static let NONE = "none"
    public static let UNKNOWN = "?"

    private static let qualityOrder = ["4K", "1440p", "1080p", "720p", "SD", "Unknown"]
    private static let GB: Double = 1_073_741_824

    public static func values(_ kind: FacetKind, _ s: ParsedStream, _ externalSubs: Set<String>) -> Set<String> {
        switch kind {
        case .quality: return [s.resolutionLabel]
        case .audioLang:
            var v = Set(s.audioLanguages)
            if s.multiAudio { v.insert(MULTI) }
            if v.isEmpty { v.insert(UNSPECIFIED) }
            return v
        case .subLang:
            var v = Set(s.subtitleLanguages)
            if s.multiSubs { v.insert(MULTI) }
            v.formUnion(externalSubs)
            if v.isEmpty { v.insert(NONE) }
            return v
        case .size: return [SizeBucket.of(s.sizeBytes)?.rawValue ?? UNKNOWN]
        case .hdr: return s.hdr.isEmpty ? ["SDR"] : Set(s.hdr.map(\.label))
        case .codec: return [s.codec.label]
        case .audio: return s.audio.isEmpty ? [UNKNOWN] : Set(s.audio.map(\.label))
        case .channels: return [s.channels ?? UNKNOWN]
        case .source: return [s.source.label]
        case .service: return [s.debridService ?? "Direct"]
        case .addon: return [s.addonName]
        }
    }

    public static func label(_ kind: FacetKind, _ value: String, _ externalSubs: Set<String> = []) -> String {
        if value == MULTI { return "Multi-language" }
        if value == UNSPECIFIED { return "Not specified" }
        if value == NONE { return "None listed" }
        if value == UNKNOWN { return "Unknown" }
        switch kind {
        case .audioLang: return Languages.displayName(value)
        case .subLang: return Languages.displayName(value) + (externalSubs.contains(value) ? "  (incl. external)" : "")
        case .size: return SizeBucket(rawValue: value)?.label ?? value
        default: return value
        }
    }

    private static func matches(_ s: ParsedStream, _ state: FilterState, _ ext: Set<String>, exclude: FacetKind? = nil) -> Bool {
        state.selected.allSatisfy { kind, sel in kind == exclude || sel.isEmpty || !values(kind, s, ext).isDisjoint(with: sel) }
    }

    private static func base(_ all: [ParsedStream], _ state: FilterState, _ caps: DeviceCapabilities, _ settings: AppSettings) -> [ParsedStream] {
        all.filter { s in
            !(state.hideCam && s.source == .cam) &&
                (!state.deviceFriendlyOnly || isDeviceFriendly(s, caps)) &&
                (settings.maxSizeGb <= 0 || Double(s.sizeBytes ?? 0) <= Double(settings.maxSizeGb) * GB)
        }
    }

    public static func apply(_ all: [ParsedStream], _ state: FilterState, _ caps: DeviceCapabilities, _ settings: AppSettings, _ externalSubs: Set<String>) -> [RankedStream] {
        let ranked = base(all, state, caps, settings)
            .filter { matches($0, state, externalSubs) }
            .map { RankedStream(stream: $0, score: score($0, caps, settings, externalSubs), recommended: false, deviceFriendly: isDeviceFriendly($0, caps)) }
        let bestKey = ranked.max { $0.score < $1.score }?.stream.key
        let sorted: [RankedStream]
        switch state.sort {
        case .best: sorted = ranked.stableSorted { $0.score > $1.score }
        case .resolution: sorted = ranked.stableSorted { ($0.stream.resolution, $0.score) > ($1.stream.resolution, $1.score) }
        case .sizeDesc: sorted = ranked.stableSorted { ($0.stream.sizeBytes ?? 0) > ($1.stream.sizeBytes ?? 0) }
        case .sizeAsc: sorted = ranked.stableSorted { ($0.stream.sizeBytes ?? .max) < ($1.stream.sizeBytes ?? .max) }
        case .seeders: sorted = ranked.stableSorted { ($0.stream.seeders ?? -1) > ($1.stream.seeders ?? -1) }
        }
        return sorted.map { r in
            var r = r
            if r.stream.key == bestKey { r.recommended = true }
            return r
        }
    }

    /** Options for each facet with counts that respect every *other* active facet. */
    public static func facets(_ all: [ParsedStream], _ state: FilterState, _ caps: DeviceCapabilities, _ settings: AppSettings, _ externalSubs: Set<String>) -> [FacetKind: [FacetOption]] {
        let b = base(all, state, caps, settings)
        var out: [FacetKind: [FacetOption]] = [:]
        for kind in FacetKind.allCases {
            var counts: [String: Int] = [:]
            for s in b where matches(s, state, externalSubs, exclude: kind) {
                for v in values(kind, s, externalSubs) { counts[v, default: 0] += 1 }
            }
            for v in state.selected[kind] ?? [] where counts[v] == nil { counts[v] = 0 }
            let options = counts.map { FacetOption(value: $0.key, label: label(kind, $0.key, externalSubs), count: $0.value) }
            switch kind {
            case .quality:
                out[kind] = options.sorted { (qualityOrder.firstIndex(of: $0.value) ?? 99) < (qualityOrder.firstIndex(of: $1.value) ?? 99) }
            case .size:
                let order = SizeBucket.allCases.map(\.rawValue)
                out[kind] = options.sorted { (order.firstIndex(of: $0.value) ?? 99) < (order.firstIndex(of: $1.value) ?? 99) }
            default:
                out[kind] = options.sorted { ($0.count, $1.label) > ($1.count, $0.label) }
            }
        }
        return out
    }

    public static func isDeviceFriendly(_ s: ParsedStream, _ caps: DeviceCapabilities) -> Bool {
        let codecOk: Bool
        switch s.codec {
        case .av1: codecOk = caps.av1
        case .hevc: codecOk = caps.hevc
        default: codecOk = true
        }
        let dvOnly = s.hdr == [.dolbyVision]
        let hdrOk = s.hdr.isEmpty ? true : dvOnly ? caps.dolbyVision : (caps.hdr10 || caps.dolbyVision)
        let audioOk = s.audio.isEmpty || s.audio.contains { caps.canPlay($0) }
        return codecOk && hdrOk && audioOk
    }

    /** Heuristic "how good will this look and sound here, in my languages" score. */
    public static func score(_ s: ParsedStream, _ caps: DeviceCapabilities, _ settings: AppSettings, _ externalSubs: Set<String>) -> Double {
        var sc = 0.0
        let effective = min(s.resolution, caps.maxResolution)
        sc += effective >= 2160 ? 40 : effective >= 1440 ? 33 : effective >= 1080 ? 30 : effective >= 720 ? 18 : effective > 0 ? 8 : 12
        if s.resolution > caps.maxResolution { sc -= 6 } // bandwidth this screen can't show
        sc += Double(s.source.rank * 4)

        if s.hdr.contains(.dolbyVision) {
            let dvUsable = caps.dolbyVision && !settings.avoidDolbyVision
            sc += dvUsable ? 10 : (s.hdr.count == 1 ? -18 : 0)
            // Disc-based DV is usually dual-layer profile 7, which players rarely handle.
            if s.source == .remux || s.source == .bluray { sc -= 8 }
        }
        if s.hdr.contains(.hdr10Plus) && caps.hdr10Plus { sc += 3 }
        if s.hdr.contains(.hdr10) || s.hdr.contains(.hdr10Plus) { sc += caps.hdr10 ? 7 : -3 }

        switch s.codec {
        case .av1: sc += caps.av1 ? 3 : -35
        case .hevc: sc += caps.hevc ? 2 : -35
        default: break
        }
        if !s.audio.isEmpty {
            let playable = s.audio.filter { caps.canPlay($0) }
            sc += playable.isEmpty ? -20 : Double(playable.map(\.rank).max()!) * 1.5
        }

        let prefAudio = Set(settings.audioLanguages)
        if s.audioLanguages.contains(where: prefAudio.contains) { sc += 25 }
        else if s.multiAudio { sc += 12 }
        else if s.audioLanguages.isEmpty { sc += 6 } // usually the original language
        else { sc -= 15 }

        let prefSubs = Set(settings.subtitleLanguages)
        if !prefSubs.isEmpty && !(Set(s.subtitleLanguages).union(externalSubs)).isDisjoint(with: prefSubs) { sc += 4 }

        sc += Double(min(s.seeders ?? 0, 100)) / 25
        let gb = Double(s.sizeBytes ?? 0) / GB
        if gb > 0 && gb < 0.4 && s.resolution >= 1080 { sc -= 10 } // suspiciously small
        return sc
    }
}

public extension Array {
    /** Sort that keeps the original order of equal elements (like Kotlin's sortedBy). */
    func stableSorted(by areInIncreasingOrder: (Element, Element) -> Bool) -> [Element] {
        enumerated().sorted { a, b in
            if areInIncreasingOrder(a.element, b.element) { return true }
            if areInIncreasingOrder(b.element, a.element) { return false }
            return a.offset < b.offset
        }.map(\.element)
    }
}
