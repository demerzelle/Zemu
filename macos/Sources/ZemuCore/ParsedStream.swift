import Foundation

public enum Source: String, CaseIterable, Sendable {
    case remux, bluray, webDl, webrip, hdtv, dvd, cam, unknown

    public var label: String {
        switch self {
        case .remux: "Remux"; case .bluray: "BluRay"; case .webDl: "WEB-DL"; case .webrip: "WEBRip"
        case .hdtv: "HDTV"; case .dvd: "DVD"; case .cam: "CAM"; case .unknown: "Unknown"
        }
    }

    public var rank: Int {
        switch self {
        case .remux: 6; case .bluray: 5; case .webDl: 4; case .webrip: 3; case .hdtv: 2; case .dvd: 1; case .cam: -10; case .unknown: 0
        }
    }
}

public enum HdrFormat: String, CaseIterable, Sendable {
    case dolbyVision, hdr10Plus, hdr10, hlg
    public var label: String {
        switch self { case .dolbyVision: "Dolby Vision"; case .hdr10Plus: "HDR10+"; case .hdr10: "HDR10"; case .hlg: "HLG" }
    }
}

public enum VideoCodec: String, CaseIterable, Sendable {
    case av1, hevc, avc, unknown
    public var label: String {
        switch self { case .av1: "AV1"; case .hevc: "HEVC"; case .avc: "H.264"; case .unknown: "Unknown" }
    }
}

public enum AudioCodec: String, CaseIterable, Sendable {
    case atmos, truehd, dtsHd, dts, ddp, dd, flac, aac, opus

    public var label: String {
        switch self {
        case .atmos: "Atmos"; case .truehd: "TrueHD"; case .dtsHd: "DTS-HD"; case .dts: "DTS"; case .ddp: "DD+"
        case .dd: "DD"; case .flac: "FLAC"; case .aac: "AAC"; case .opus: "Opus"
        }
    }

    public var rank: Int {
        switch self {
        case .atmos: 6; case .truehd, .dtsHd: 5; case .dts, .ddp, .flac: 3; case .dd: 2; case .aac, .opus: 1
        }
    }
}

public struct ParsedStream: Hashable, Identifiable, Sendable {
    public var raw: Stream
    public var addonName: String
    public var key: String
    /** Best human-readable release name. */
    public var title: String
    /** 2160, 1440, 1080, 720, 480, or 0 when unknown. */
    public var resolution: Int
    public var source: Source
    public var hdr: Set<HdrFormat>
    public var codec: VideoCodec
    public var tenBit: Bool
    public var audio: Set<AudioCodec>
    public var channels: String?
    public var audioLanguages: [String]
    public var multiAudio: Bool
    public var subtitleLanguages: [String]
    public var multiSubs: Bool
    public var sizeBytes: Int64?
    public var seeders: Int?
    public var releaseGroup: String?
    /** Short debrid tag, e.g. "RD", or nil for direct links. */
    public var debridService: String?
    public var isCached: Bool

    public var id: String { key }

    public var resolutionLabel: String {
        switch resolution { case 2160: "4K"; case 1440: "1440p"; case 1080: "1080p"; case 720: "720p"; case 480: "SD"; default: "Unknown" }
    }

    public var sizeLabel: String? { sizeBytes.map(ParsedStream.formatSize) }

    public static func formatSize(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        return gb >= 1 ? String(format: "%.1f GB", gb) : String(format: "%.0f MB", Double(bytes) / 1_048_576)
    }
}
