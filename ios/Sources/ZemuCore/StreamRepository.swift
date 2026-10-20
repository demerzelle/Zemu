import Foundation

public struct StreamLoadResult: Sendable {
    /** Only debrid-cached, directly playable streams. Uncached ones never leave this repository. */
    public var cached: [ParsedStream]
    public var totalFound: Int
    /** Streams dropped because they weren't cached (torrents, "download" links). */
    public var hiddenUncached: Int
    public var failedAddons: [String]
    public var noStreamAddons: Bool

    public static let empty = StreamLoadResult(cached: [], totalFound: 0, hiddenUncached: 0, failedAddons: [], noStreamAddons: true)
}

@MainActor
public final class StreamRepository {
    private let addons: AddonRepository
    private let store: UserStore
    private var cache: [String: (at: Date, result: StreamLoadResult)] = [:]
    private var subsCache: [String: [SubtitleTrack]] = [:]

    private static let cacheTTL: TimeInterval = 15 * 60
    private static let timeout: Double = 20
    private static let openSubtitles = "https://opensubtitles-v3.strem.io"

    /** Free, no-setup subtitle addons for languages OpenSubtitles covers poorly. */
    private static let languageFallbacks: [String: [String]] = [
        "es": ["https://stremio.fly.dev", "https://58196d6c26cf-stremio-tusubtitulo.baby-beamup.club"],
        "he": ["https://4b139a4b7f94-wizdom-stremio-v2.baby-beamup.club", "https://4b139a4b7f94-ktuvit-stremio.baby-beamup.club"],
        "pl": ["https://napisy24-stremio.top"],
    ]

    public init(addons: AddonRepository, store: UserStore) {
        self.addons = addons
        self.store = store
    }

    public func load(type: String, videoId: String, force: Bool = false) async -> StreamLoadResult {
        let key = "\(type)/\(videoId)"
        if !force, let c = cache[key], Date().timeIntervalSince(c.at) < Self.cacheTTL { return c.result }

        let targets = addons.addonsFor("stream", type: type, id: videoId)
        if targets.isEmpty { return .empty }

        let trustDirect = store.settings.trustDirectLinks
        let responses: [(Int, Addon, [Stream]?)] = await withTaskGroup(of: (Int, Addon, [Stream]?).self) { group in
            for (i, addon) in targets.enumerated() {
                let base = addon.baseUrl
                group.addTask {
                    let streams = try? await withTimeout(Self.timeout) { try await AddonClient.streams(base, type: type, id: videoId) }
                    return (i, addon, streams)
                }
            }
            var out: [(Int, Addon, [Stream]?)] = []
            for await r in group { out.append(r) }
            return out.sorted { $0.0 < $1.0 }
        }
        let parsed = responses.flatMap { _, addon, streams in
            (streams ?? []).map { StreamParser.parse($0, addonName: addon.manifest.name, trustDirectLinks: trustDirect) }
        }
        let result = StreamLoadResult(
            cached: parsed.filter(\.isCached).distinct(by: \.key),
            totalFound: parsed.count,
            hiddenUncached: parsed.filter { !$0.isCached }.count,
            failedAddons: responses.filter { $0.2 == nil }.map { $0.1.manifest.name },
            noStreamAddons: false
        )
        // Don't cache total failures so a retry actually retries.
        if result.failedAddons.count < targets.count { cache[key] = (Date(), result) }
        return result
    }

    public func hasCached(type: String, videoId: String) async -> Bool {
        !(await load(type: type, videoId: videoId).cached.isEmpty)
    }

    /**
     * Subtitles from installed addons. If those have nothing in a preferred language, well-known
     * free subtitle addons are asked directly (without installing them) so something turns up.
     */
    public func subtitles(type: String, videoId: String) async -> [SubtitleTrack] {
        let key = "\(type)/\(videoId)"
        if let c = subsCache[key] { return c }
        let installed = addons.addonsFor("subtitles", type: type, id: videoId)

        func fetch(_ bases: [String]) async -> [SubtitleTrack] {
            await withTaskGroup(of: [SubtitleTrack].self) { group in
                for base in bases {
                    group.addTask { (try? await withTimeout(Self.timeout) { try await AddonClient.subtitles(base, type: type, id: videoId) }) ?? [] }
                }
                var out: [SubtitleTrack] = []
                for await r in group { out += r }
                return out
            }
        }

        var subs = await fetch(installed.map(\.baseUrl)).filter { !$0.url.trimmed.isEmpty }
        let preferred = store.settings.subtitleLanguages.isEmpty ? ["en"] : store.settings.subtitleLanguages
        let covered = subs.contains { s in Languages.normalize(s.lang).map(preferred.contains) ?? false }
        if !covered && videoId.hasPrefix("tt") {
            let installedBases = Set(installed.map(\.baseUrl))
            let fallback = ([Self.openSubtitles] + preferred.flatMap { Self.languageFallbacks[$0] ?? [] })
                .distinct().filter { !installedBases.contains($0) }
            subs += await fetch(fallback).filter { !$0.url.trimmed.isEmpty }
        }
        subs = subs.distinct(by: \.url)
        subsCache[key] = subs
        return subs
    }

    public func invalidate() { cache.removeAll() }
}
