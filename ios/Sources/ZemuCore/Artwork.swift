import Foundation

/** A title's extra art: landscape backdrops and its title logo (transparent PNG). */
public struct TitleArt: Codable, Sendable, Equatable {
    public var backdrops: [String] = []
    public var logo: String?
}

/** One screensaver slide: a title, one of its backdrops and its logo. */
public struct ScreensaverSlide: Sendable, Equatable {
    public let meta: Meta
    public let image: String
    public let logo: String?
}

/**
 * Backdrops and logos from fanart.tv first, then TMDB `/images`, for the screensaver and for
 * titles whose addon has no logo. What's found is kept in a small file so later runs start
 * immediately.
 */
@MainActor
public final class Artwork {
    private let tmdb: Tmdb
    private let fanartKey: () -> String
    private let file = AppPaths.support.appendingPathComponent("title_art.json")
    private lazy var cache: [String: TitleArt] = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode([String: TitleArt].self, from: $0) } ?? [:]
    private var inFlight: [String: Task<Void, Never>] = [:]

    public init(tmdb: Tmdb, fanartKey: @escaping () -> String) {
        self.tmdb = tmdb
        self.fanartKey = fanartKey
    }

    /** Lookups need a TMDB or fanart.tv key. */
    public var enabled: Bool { tmdb.enabled || !fanartKey().trimmed.isEmpty }

    /** One slide per title with known art (a random backdrop each time), without network calls. */
    public func slides(_ titles: [Meta]) -> [ScreensaverSlide] {
        titles.compactMap { m in
            guard let art = cache[m.id], let image = art.backdrops.randomElement() else { return nil }
            return ScreensaverSlide(meta: m, image: image, logo: art.logo ?? m.logoUrl)
        }
    }

    /** Looks up titles not seen before (a few at a time) and saves what was found. */
    public func refresh(_ titles: [Meta]) async {
        guard enabled else { return }
        let todo = Array(titles.filter { cache[$0.id] == nil && inFlight[$0.id] == nil }.distinct(by: \.id).prefix(40))
        guard !todo.isEmpty else {
            for m in titles { await inFlight[m.id]?.value }
            return
        }
        for chunk in stride(from: 0, to: todo.count, by: 4).map({ Array(todo[$0..<min($0 + 4, todo.count)]) }) {
            let tasks = chunk.map { m in
                let t = Task { [weak self] in
                    guard let self else { return }
                    let art = await self.lookup(m)
                    self.cache[m.id] = art
                    self.inFlight[m.id] = nil
                }
                inFlight[m.id] = t
                return t
            }
            for t in tasks { await t.value }
        }
        // Suggestions change daily; keep the file from growing forever.
        if cache.count > 600 { for k in cache.keys.prefix(cache.count - 600) { cache[k] = nil } }
        let snapshot = cache, file = self.file
        DispatchQueue.global(qos: .utility).async { try? JSONEncoder().encode(snapshot).write(to: file, options: .atomic) }
    }

    /** [m]'s logo from fanart.tv or TMDB (looked up once, then remembered), for when the addon has none. */
    public func logo(_ m: Meta) async -> String? {
        if cache[m.id] == nil { await refresh([m]) }
        return cache[m.id]?.logo
    }

    private func lookup(_ m: Meta) async -> TitleArt {
        let fan = await fanart(m)
        if let fan, !fan.backdrops.isEmpty, fan.logo != nil { return fan }
        let t: (backdrops: [String], logo: String?) = (try? await tmdb.art(m)) ?? ([], nil)
        return TitleArt(backdrops: fan?.backdrops.isEmpty == false ? fan!.backdrops : t.backdrops, logo: fan?.logo ?? t.logo)
    }

    /** fanart.tv: movies by IMDb/TMDB id, shows by TheTVDB id (found through TMDB). */
    private func fanart(_ m: Meta) async -> TitleArt? {
        let key = fanartKey().trimmed
        guard !key.isEmpty else { return nil }
        let series = m.type == "series"
        let path: String
        if series {
            guard let tvdb = try? await tmdb.tvdbId(m) else { return nil }
            path = "tv/\(tvdb)"
        } else {
            guard let id = m.imdbId.hasPrefix("tt") ? m.imdbId : m.tmdbId else { return nil }
            path = "movies/\(id)"
        }
        guard let o = await HTTP.json("https://webservice.fanart.tv/v3/\(path)?api_key=\(key.urlEncoded)") else { return nil }
        func images(_ f: String) -> [JSONValue] { o[f]?.array ?? [] }
        let backdrops = images(series ? "showbackground" : "moviebackground").compactMap { $0["url"]?.string }.prefix(6)
        let logos = images(series ? "hdtvlogo" : "hdmovielogo")
        let logo = (logos.first { $0["lang"]?.string == "en" } ?? logos.first)?["url"]?.string
        return TitleArt(backdrops: Array(backdrops), logo: logo)
    }
}
