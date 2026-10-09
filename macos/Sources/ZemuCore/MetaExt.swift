import Foundation

public extension Meta {
    var title: String { name ?? "" }
    var imdbId: String {
        if id.hasPrefix("tt") { return id.before(":") }
        if let f = imdbIdField, f.hasPrefix("tt") { return f }
        return id.before(":")
    }
    var isImdb: Bool { id.hasPrefix("tt") }
    var isAnime: Bool { id.hasPrefix("kitsu:") }
    var rating: Double? { imdbRating.flatMap { Double($0) }.flatMap { $0 > 0 ? $0 : nil } }
    var year: Int? { releaseInfo?.firstMatch(of: /\d{4}/).flatMap { Int($0.output) } }

    var runtimeLabel: String? {
        guard let raw = runtime else { return nil }
        if raw.contains("h") { return raw }
        guard let mins = raw.firstMatch(of: /\d+/).flatMap({ Int($0.output) }) else { return raw }
        return mins >= 60 ? "\(mins / 60)h \(mins % 60)m" : "\(mins)m"
    }

    var posterUrl: String? { poster ?? (isImdb ? "https://images.metahub.space/poster/medium/\(imdbId)/img" : nil) }
    var backdropUrl: String? { background ?? (isImdb ? "https://images.metahub.space/background/medium/\(imdbId)/img" : posterUrl) }
    var logoUrl: String? { logo ?? (isImdb ? "https://images.metahub.space/logo/medium/\(imdbId)/img" : nil) }

    /** Small copy for persistence (history / My List) without the episode list. */
    func slim() -> Meta {
        var m = self
        m.videos = []
        m.trailers = Array(trailers.prefix(1))
        m.trailerStreams = Array(trailerStreams.prefix(1))
        m.cast = Array(cast.prefix(6))
        return m
    }

    /** YouTube id of the first trailer, if any. */
    var trailerId: String? {
        trailers.first(where: { !($0.source ?? "").isEmpty })?.source
            ?? trailerStreams.first(where: { !($0.ytId ?? "").isEmpty })?.ytId
    }

    /** "yyyy-MM-dd" from the ISO release timestamp. */
    var releasedDate: String? {
        guard let r = released, r.count >= 10 else { return nil }
        return String(r.prefix(10))
    }

    /** Video id to probe when checking whether a title has cached streams. */
    var probeVideoId: String { type == "series" && isImdb && !id.contains(":") ? "\(id):1:1" : id }

    /** Episodes in watch order (specials last), for "next episode" and resume. */
    var orderedEpisodes: [Video] {
        let regular = videos.filter { ($0.season ?? 1) > 0 }.sorted { ($0.season ?? 0, $0.episodeNumber) < ($1.season ?? 0, $1.episodeNumber) }
        return regular.isEmpty ? videos : regular
    }
}

public extension String {
    func before(_ s: String) -> String { range(of: s).map { String(self[..<$0.lowerBound]) } ?? self }
    func after(_ s: String, or fallback: String? = nil) -> String {
        range(of: s).map { String(self[$0.upperBound...]) } ?? (fallback ?? self)
    }
    func removingPrefix(_ p: String) -> String { hasPrefix(p) ? String(dropFirst(p.count)) : self }
    func removingSuffix(_ p: String) -> String { hasSuffix(p) ? String(dropLast(p.count)) : self }
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nilIfBlank: String? { trimmed.isEmpty ? nil : self }
}

public extension Array {
    func distinct<K: Hashable>(by key: (Element) -> K) -> [Element] {
        var seen = Set<K>()
        return filter { seen.insert(key($0)).inserted }
    }
}

public extension Array where Element: Hashable {
    func distinct() -> [Element] { distinct(by: { $0 }) }
}

/** Seeded random generator so daily rows shuffle the same way all day. */
public struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64
    public init(seed: Int64) { state = UInt64(bitPattern: seed) &+ 0x9E3779B97F4A7C15 }
    public mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

/** Stable across launches (Swift's hashValue is randomized per process). */
public func stableHash(_ s: String) -> Int64 {
    var h: UInt64 = 1469598103934665603
    for b in s.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
    return Int64(bitPattern: h)
}
