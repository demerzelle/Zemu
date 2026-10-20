import Foundation

public enum SegmentType: String, Sendable {
    case intro, recap, credits, preview
    public var skipLabel: String {
        switch self { case .intro: "Skip intro"; case .recap: "Skip recap"; case .credits: "Skip credits"; case .preview: "Skip preview" }
    }
}

/** [endMs] nil means "until the end". */
public struct Segment: Hashable, Sendable {
    public var type: SegmentType
    public var startMs: Int64
    public var endMs: Int64?
}

/**
 * Community skip timestamps:
 *  - TheIntroDB (theintrodb.org) for TV episodes and movies, by TMDB or IMDb id.
 *  - AniSkip (aniskip.com) for anime, by MyAnimeList id (resolved from Kitsu).
 */
@MainActor
public final class SkipSegments {
    private var malCache: [String: String?] = [:]
    private static let headers = ["User-Agent": "Zemu/1.0"]

    public init() {}

    public func find(_ meta: Meta, videoId: String, season: Int?, episode: Int?, durationMs: Int64) async -> [Segment] {
        let source = videoId.hasPrefix("kitsu:") ? videoId : meta.id
        if source.hasPrefix("kitsu:") {
            let kitsuId = source.removingPrefix("kitsu:").before(":")
            let parts = videoId.components(separatedBy: ":")
            let ep = (parts.count > 2 ? Int(parts[2]) : nil) ?? episode ?? 1
            return await aniSkip(kitsuId, ep, durationMs)
        }
        return await introDb(meta, season, episode, durationMs)
    }

    private func introDb(_ meta: Meta, _ season: Int?, _ episode: Int?, _ durationMs: Int64) async -> [Segment] {
        let idParam: String
        if let t = meta.tmdbId?.nilIfBlank { idParam = "tmdb_id=\(t)" }
        else if meta.imdbId.hasPrefix("tt") { idParam = "imdb_id=\(meta.imdbId)" }
        else { return [] }
        let ep = meta.type == "series" && season != nil && episode != nil ? "&season=\(season!)&episode=\(episode!)" : ""
        let dur = durationMs > 0 ? "&duration_ms=\(durationMs)" : ""
        guard let o = await HTTP.json("https://api.theintrodb.org/v3/media?\(idParam)\(ep)\(dur)", headers: Self.headers) else { return [] }
        let map: [(String, SegmentType)] = [("intro", .intro), ("recap", .recap), ("credits", .credits), ("preview", .preview)]
        return map.flatMap { key, type in
            (o[key]?.array ?? []).compactMap { s -> Segment? in
                let start = s["start_ms"]?.int64 ?? 0
                let end = s["end_ms"]?.int64
                if let end, end <= start { return nil }
                return Segment(type: type, startMs: start, endMs: end)
            }
        }.sorted { $0.startMs < $1.startMs }
    }

    private func aniSkip(_ kitsuId: String, _ episode: Int, _ durationMs: Int64) async -> [Segment] {
        guard let mal = await malIdFor(kitsuId) else { return [] }
        let len = durationMs > 0 ? Double(durationMs) / 1000 : 0
        guard let o = await HTTP.json("https://api.aniskip.com/v2/skip-times/\(mal)/\(episode)?types=op&types=ed&types=recap&types=mixed-op&types=mixed-ed&episodeLength=\(len)", headers: Self.headers),
              o["found"]?.bool == true else { return [] }
        return (o["results"]?.array ?? []).compactMap { r -> Segment? in
            guard let start = r["interval"]?["startTime"]?.double, let end = r["interval"]?["endTime"]?.double else { return nil }
            let type: SegmentType
            switch r["skipType"]?.string {
            case "op", "mixed-op": type = .intro
            case "ed", "mixed-ed": type = .credits
            case "recap": type = .recap
            default: return nil
            }
            return Segment(type: type, startMs: Int64(start * 1000), endMs: Int64(end * 1000))
        }.sorted { $0.startMs < $1.startMs }
    }

    private func malIdFor(_ kitsuId: String) async -> String? {
        if let c = malCache[kitsuId] { return c }
        let o = await HTTP.json("https://kitsu.io/api/edge/anime/\(kitsuId)/mappings?filter%5BexternalSite%5D=myanimelist/anime", headers: Self.headers)
        let mal = o?["data"]?[0]?["attributes"]?["externalId"]?.text
        malCache[kitsuId] = mal
        return mal
    }
}
