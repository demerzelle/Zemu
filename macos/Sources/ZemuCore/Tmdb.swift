import Foundation

public struct TmdbPerson: Decodable, Hashable, Sendable {
    public var id: Int64 = 0
    public var name: String = ""
    public var character: String?
    public var job: String?
    public var profilePath: String?
    public var roles: [String] = []

    enum CodingKeys: String, CodingKey { case id, name, character, job, roles; case profilePath = "profile_path" }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.int64(.id) ?? 0
        name = c.str(.name) ?? ""
        character = c.str(.character)
        job = c.str(.job)
        profilePath = c.str(.profilePath)
        roles = (c.value(.roles)?.array ?? []).compactMap { $0["character"]?.string }
    }

    public var photo: String? { profilePath.map { "https://image.tmdb.org/t/p/w185\($0)" } }
    public var role: String? { character?.nilIfBlank ?? roles.first }
}

public struct TmdbCredit: Decodable, Hashable, Sendable {
    public var id: Int64 = 0
    public var mediaType = "movie"
    public var title: String?
    public var name: String?
    public var character: String?
    public var job: String?
    public var posterPath: String?
    public var releaseDate: String?
    public var firstAirDate: String?
    public var vote: Double = 0
    public var voteCount: Int = 0
    public var popularity: Double = 0
    public var genreIds: [Int] = []

    enum CodingKeys: String, CodingKey {
        case id, title, name, character, job, popularity
        case mediaType = "media_type", posterPath = "poster_path", releaseDate = "release_date", firstAirDate = "first_air_date"
        case vote = "vote_average", voteCount = "vote_count", genreIds = "genre_ids"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.int64(.id) ?? 0
        mediaType = c.str(.mediaType) ?? "movie"
        title = c.str(.title); name = c.str(.name); character = c.str(.character); job = c.str(.job)
        posterPath = c.str(.posterPath); releaseDate = c.str(.releaseDate); firstAirDate = c.str(.firstAirDate)
        vote = c.value(.vote)?.double ?? 0
        voteCount = c.int(.voteCount) ?? 0
        popularity = c.value(.popularity)?.double ?? 0
        genreIds = (c.value(.genreIds)?.array ?? []).compactMap(\.int)
    }

    public var displayTitle: String { title ?? name ?? "" }
    public var year: String? { (releaseDate ?? firstAirDate).flatMap { $0.count >= 4 ? String($0.prefix(4)) : nil } }
    public var poster: String? { posterPath.map { "https://image.tmdb.org/t/p/w342\($0)" } }
    public var isSeries: Bool { mediaType == "tv" }
}

/** A TMDB collection: a franchise such as "Harry Potter Collection", with its movies in release order. */
public struct TmdbCollection: Sendable {
    public let id: Int64
    public let name: String
    public let parts: [TmdbCredit]
}

public struct TmdbPersonDetails: Sendable {
    public var id: Int64
    public var name: String
    public var biography: String?
    public var birthday: String?
    public var deathday: String?
    public var placeOfBirth: String?
    public var department: String?
    public var profilePath: String?
    var castCredits: [TmdbCredit]
    var crewCredits: [TmdbCredit]

    public var photo: String? { profilePath.map { "https://image.tmdb.org/t/p/h632\($0)" } }

    /** Acting (or directing, for directors) credits, best known first, without talk shows and cameos as "Self". */
    public var credits: [TmdbCredit] {
        let acting = castCredits.filter { c in
            let ch = c.character ?? ""
            return ch.range(of: "Self", options: .caseInsensitive) == nil && !ch.contains("Himself") && !ch.contains("Herself") &&
                !c.genreIds.contains(10767) && !c.genreIds.contains(10763) // talk, news
        }
        let directing = crewCredits.filter { $0.job == "Director" || $0.job == "Creator" }
        let all = department == "Directing" || acting.isEmpty ? directing + acting : acting + directing
        return all.distinct { "\($0.mediaType)/\($0.id)" }
            .stableSorted { Double($0.voteCount) * 0.7 + $0.popularity * 10 > Double($1.voteCount) * 0.7 + $1.popularity * 10 }
    }
}

/** Extra details shown on the Details page. */
public struct TitleExtras: Sendable {
    public var directors: [TmdbPerson]
    public var creators: [TmdbPerson]
    public var studios: [String]
    public var cast: [TmdbPerson]
}

public struct TmdbError: LocalizedError {
    public let message: String
    public var errorDescription: String? { message }
}

/**
 * Minimal TMDB client. Works with either a v3 API key or a v4 "API Read Access Token", both free
 * from themoviedb.org → Settings → API.
 */
@MainActor
public final class Tmdb {
    private let key: () -> String
    private var extrasCache: [String: TitleExtras] = [:]
    private var imdbCache: [String: String] = [:]

    public init(key: @escaping () -> String) { self.key = key }

    public var enabled: Bool { !key().trimmed.isEmpty }

    private func get(_ path: String, _ query: String = "", key override: String? = nil) async throws -> Data {
        let k = (override ?? key()).trimmed
        let bearer = k.hasPrefix("eyJ")
        var url = "https://api.themoviedb.org/3\(path)"
        if !query.isEmpty { url += "?\(query)" }
        if !bearer { url += (url.contains("?") ? "&" : "?") + "api_key=\(k)" }
        do {
            return try await HTTP.data(url, headers: bearer ? ["Authorization": "Bearer \(k)"] : [:])
        } catch let e as HTTPError where e.status == 401 {
            throw TmdbError(message: "TMDB rejected the API key")
        }
    }

    /** Checks a key before saving it. */
    public func validate(_ key: String) async -> Bool { (try? await get("/configuration", key: key)) != nil }

    private func tmdbIdFor(_ meta: Meta) async throws -> Int64? {
        if let id = meta.tmdbId.flatMap({ Int64($0) }) { return id }
        guard meta.imdbId.hasPrefix("tt") else { return nil }
        let v = JSONValue.parse(try await get("/find/\(meta.imdbId)", "external_source=imdb_id"))
        let movies = v?["movie_results"]?.array ?? [], tv = v?["tv_results"]?.array ?? []
        let first = meta.type == "series" ? (tv.first ?? movies.first) : (movies.first ?? tv.first)
        return first?["id"]?.int64
    }

    public func extras(_ meta: Meta) async throws -> TitleExtras? {
        guard enabled else { return nil }
        if let c = extrasCache[meta.id] { return c }
        guard let id = try await tmdbIdFor(meta) else { return nil }
        let tv = meta.type == "series"
        let raw = tv ? try await get("/tv/\(id)", "append_to_response=aggregate_credits") : try await get("/movie/\(id)", "append_to_response=credits")
        guard let v = JSONValue.parse(raw) else { return nil }
        let credits = tv ? v["aggregate_credits"] : v["credits"]
        func people(_ j: JSONValue?) -> [TmdbPerson] {
            guard let j, let d = try? JSONEncoder().encode(j) else { return [] }
            return (try? JSONDecoder().decode([TmdbPerson].self, from: d)) ?? []
        }
        let names = ((v["production_companies"]?.array ?? []) + (v["networks"]?.array ?? [])).compactMap { $0["name"]?.string }
        let ex = TitleExtras(
            directors: Array(people(credits?["crew"]).filter { $0.job == "Director" }.distinct(by: \.id).prefix(3)),
            creators: Array(people(v["created_by"]).prefix(3)),
            studios: Array(names.distinct().prefix(3)),
            cast: Array(people(credits?["cast"]).distinct(by: \.id).prefix(20))
        )
        extrasCache[meta.id] = ex
        return ex
    }

    public func person(_ id: Int64) async throws -> TmdbPersonDetails {
        guard let v = JSONValue.parse(try await get("/person/\(id)", "append_to_response=combined_credits")) else { throw TmdbError(message: "Bad TMDB response") }
        func credits(_ j: JSONValue?) -> [TmdbCredit] {
            guard let j, let d = try? JSONEncoder().encode(j) else { return [] }
            return (try? JSONDecoder().decode([TmdbCredit].self, from: d)) ?? []
        }
        return TmdbPersonDetails(
            id: v["id"]?.int64 ?? id, name: v["name"]?.string ?? "", biography: v["biography"]?.string,
            birthday: v["birthday"]?.string, deathday: v["deathday"]?.string, placeOfBirth: v["place_of_birth"]?.string,
            department: v["known_for_department"]?.string, profilePath: v["profile_path"]?.string,
            castCredits: credits(v["combined_credits"]?["cast"]), crewCredits: credits(v["combined_credits"]?["crew"])
        )
    }

    /** The collection a movie belongs to, or nil when it isn't in one. */
    public func collection(for meta: Meta) async throws -> TmdbCollection? {
        guard enabled, meta.type == "movie", let id = try await tmdbIdFor(meta) else { return nil }
        guard let info = JSONValue.parse(try await get("/movie/\(id)")),
              let cid = info["belongs_to_collection"]?["id"]?.int64,
              let raw = JSONValue.parse(try await get("/collection/\(cid)")) else { return nil }
        let parts = (raw["parts"]?.array ?? []).compactMap { p -> TmdbCredit? in
            guard let d = try? JSONEncoder().encode(p) else { return nil }
            return try? JSONDecoder().decode(TmdbCredit.self, from: d)
        }
        return TmdbCollection(id: cid, name: raw["name"]?.string ?? "", parts: parts.stableSorted { ($0.releaseDate ?? "9999") < ($1.releaseDate ?? "9999") })
    }

    /**
     * Screensaver and logo art: 16:9 backdrops (text-free ones first) and the English (or
     * language-free) title logo, if TMDB has one.
     */
    public func art(_ meta: Meta) async throws -> (backdrops: [String], logo: String?) {
        guard enabled, let id = try await tmdbIdFor(meta) else { return ([], nil) }
        guard let raw = JSONValue.parse(try await get(meta.type == "series" ? "/tv/\(id)/images" : "/movie/\(id)/images", "include_image_language=en,null")) else { return ([], nil) }
        let logos = (raw["logos"]?.array ?? []).stableSorted { a, b in a["iso_639_1"]?.string == "en" && b["iso_639_1"]?.string != "en" }
        let logo = logos.lazy.compactMap { $0["file_path"]?.string }.first
            .map { "https://image.tmdb.org/t/p/w500\($0.replacingOccurrences(of: ".svg", with: ".png"))" }
        let backdrops = (raw["backdrops"]?.array ?? []).compactMap { o -> (String, Bool, Double)? in
            guard let p = o["file_path"]?.string else { return nil }
            return (p, o["iso_639_1"]?.string == nil, o["vote_average"]?.double ?? 0)
        }
        .sorted { $0.1 != $1.1 ? $0.1 : $0.2 > $1.2 }
        .prefix(6).map { "https://image.tmdb.org/t/p/w1280\($0.0)" }
        return (Array(backdrops), logo)
    }

    /** The US rating ("PG-13", "TV-Y7"), "" when TMDB has none, nil without a key. Throws on network errors. */
    public func usCertification(_ meta: Meta) async throws -> String? {
        guard enabled else { return nil }
        let tv: Bool, id: Int64
        if meta.id.hasPrefix("tmdb:") {
            guard let r = Tmdb.tmdbRef(meta.id, type: meta.type) else { return "" }
            (tv, id) = r
        } else {
            guard let i = try await tmdbIdFor(meta) else { return "" }
            tv = meta.type == "series"; id = i
        }
        guard let root = JSONValue.parse(try await get(tv ? "/tv/\(id)/content_ratings" : "/movie/\(id)/release_dates")),
              let us = (root["results"]?.array ?? []).first(where: { $0["iso_3166_1"]?.string == "US" }) else { return "" }
        if tv { return us["rating"]?.string ?? "" }
        return (us["release_dates"]?.array ?? []).lazy.compactMap { $0["certification"]?.string }.first ?? ""
    }

    /** TheTVDB id of a series (fanart.tv indexes shows by it). */
    public func tvdbId(_ meta: Meta) async throws -> String? {
        guard enabled, meta.type == "series", let id = try await tmdbIdFor(meta) else { return nil }
        return JSONValue.parse(try await get("/tv/\(id)/external_ids"))?["tvdb_id"]?.text
    }

    private var discoverCache: [String: (at: Date, list: [Meta])] = [:]

    /**
     * TMDB `/discover` as app titles. Ids are "tmdb:<movie|tv>:<id>" and are turned into IMDb ids
     * only when opened (imdbFor), so rows load with one request each. Cached for 30 minutes.
     */
    public func discover(type: String, params: [String: String], page: Int = 1) async throws -> [Meta] {
        guard enabled else { return [] }
        let media = type == "series" ? "tv" : "movie"
        let all = params.merging(["page": String(page), "include_adult": "false"]) { a, _ in a }
        let query = all.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value.urlEncoded)" }.joined(separator: "&")
        let key = "\(media)?\(query)"
        if let c = discoverCache[key], Date().timeIntervalSince(c.at) < 1800 { return c.list }
        let names = type == "series" ? Self.tvGenres : Self.movieGenres
        let list = (JSONValue.parse(try await get("/discover/\(media)", query))?["results"]?.array ?? []).compactMap { o -> Meta? in
            guard let id = o["id"]?.int64, let poster = o["poster_path"]?.string else { return nil }
            let date = o["release_date"]?.string ?? o["first_air_date"]?.string
            let vote = o["vote_average"]?.double ?? 0, votes = o["vote_count"]?.int ?? 0
            return Meta(
                id: "tmdb:\(media):\(id)", type: type, tmdbId: String(id), name: o["title"]?.string ?? o["name"]?.string,
                poster: "https://image.tmdb.org/t/p/w342\(poster)",
                background: o["backdrop_path"]?.string.map { "https://image.tmdb.org/t/p/w1280\($0)" },
                description: o["overview"]?.string,
                releaseInfo: date.flatMap { $0.count >= 4 ? String($0.prefix(4)) : nil },
                imdbRating: votes >= 20 && vote > 0 ? String(format: "%.1f", vote) : nil,
                genres: (o["genre_ids"]?.array ?? []).compactMap { $0.int.flatMap { names[$0] } },
                released: date
            )
        }
        discoverCache[key] = (Date(), list)
        return list
    }

    private var providers: [Provider]?
    private static let channelWords = [" Channel", " with Ads", "Amazon Video", "Apple TV Store", "Google Play", "YouTube", "Fandango", "Vudu", "Microsoft Store", "Spectrum On Demand", "DIRECTV"]

    /** Every streaming service TMDB knows in [region], most popular first (add-on channels and ad tiers left out). */
    public func allProviders(region: String) async -> [Provider] {
        if let providers { return providers }
        guard enabled else { return [] }
        var byId: [Int: (name: String, logo: String?, priority: Int)] = [:]
        for m in ["movie", "tv"] {
            guard let d = try? await get("/watch/providers/\(m)", "watch_region=\(region)") else { continue }
            for p in JSONValue.parse(d)?["results"]?.array ?? [] {
                guard let id = p["provider_id"]?.int, let name = p["provider_name"]?.string,
                      !Self.channelWords.contains(where: { name.localizedCaseInsensitiveContains($0) }) else { continue }
                let pr = p["display_priority"]?.int ?? 999
                if byId[id] == nil || pr < byId[id]!.priority { byId[id] = (name, p["logo_path"]?.string, pr) }
            }
        }
        let found = byId.sorted { $0.value.priority < $1.value.priority }
            .map { Provider(ids: String($0.key), label: $0.value.name, logo: $0.value.logo.map { "https://image.tmdb.org/t/p/w300\($0)" }) }
        if !found.isEmpty { providers = found }
        return found
    }

    private var studioLogos: [String: String] = [:]

    /** A studio's or network's own logo (a wordmark on a transparent background). */
    public func studioLogo(_ studio: Studio) async -> String? {
        if let l = studioLogos[studio.key] { return l }
        guard enabled, let d = try? await get(studio.type == "series" ? "/network/\(studio.id)" : "/company/\(studio.id)"),
              let path = JSONValue.parse(d)?["logo_path"]?.string else { return nil }
        let url = "https://image.tmdb.org/t/p/w500\(path.replacingOccurrences(of: ".svg", with: ".png"))"
        studioLogos[studio.key] = url
        return url
    }

    /** (is TV, TMDB id) from Zemu's "tmdb:<movie|tv>:<id>" or a TMDB addon's "tmdb:<id>". */
    nonisolated public static func tmdbRef(_ key: String, type: String) -> (Bool, Int64)? {
        let p = key.split(separator: ":")
        guard let last = p.last, let id = Int64(last) else { return nil }
        return (p.count > 2 ? p[1] == "tv" : type == "series", id)
    }

    /** The IMDb id of a "tmdb:<movie|tv>:<id>" title, or an addon's "tmdb:<id>" one ([type] says which). */
    public func imdbFor(_ tmdbKey: String, type: String = "movie") async throws -> String? {
        guard let (tv, id) = Tmdb.tmdbRef(tmdbKey, type: type) else { return nil }
        let media = tv ? "tv" : "movie"
        let k = "\(media)/\(id)"
        if let c = imdbCache[k] { return c }
        guard let imdb = JSONValue.parse(try await get("/\(media)/\(id)/external_ids"))?["imdb_id"]?.string, imdb.hasPrefix("tt") else { return nil }
        imdbCache[k] = imdb
        return imdb
    }

    /** TMDB genre ids, named the way Cinemeta names them. */
    nonisolated public static let movieGenres: [Int: String] = [
        28: "Action", 12: "Adventure", 16: "Animation", 35: "Comedy", 80: "Crime", 99: "Documentary", 18: "Drama", 10751: "Family",
        14: "Fantasy", 36: "History", 27: "Horror", 10402: "Music", 9648: "Mystery", 10749: "Romance", 878: "Sci-Fi", 53: "Thriller",
        10752: "War", 37: "Western",
    ]
    nonisolated public static let tvGenres: [Int: String] = [
        10759: "Action", 16: "Animation", 35: "Comedy", 80: "Crime", 99: "Documentary", 18: "Drama", 10751: "Family", 10762: "Kids",
        9648: "Mystery", 10764: "Reality", 10765: "Sci-Fi", 10768: "War", 37: "Western",
    ]

    /** TMDB genre id for a genre name on a "movie" or "series" page, if TMDB has it. */
    nonisolated public static func genreId(_ type: String, _ name: String) -> Int? {
        if let id = (type == "series" ? tvGenres : movieGenres).first(where: { $0.value.caseInsensitiveCompare(name) == .orderedSame })?.key { return id }
        if type == "series" && ["Fantasy", "Science Fiction"].contains(name) { return 10765 }
        if type == "series" && name == "Adventure" { return 10759 }
        return nil
    }

    /** IMDb id for a TMDB title, so it can open in the app's Details page. */
    public func imdbIdFor(_ credit: TmdbCredit) async throws -> String? {
        let k = "\(credit.mediaType)/\(credit.id)"
        if let c = imdbCache[k] { return c }
        let path = credit.isSeries ? "/tv/\(credit.id)/external_ids" : "/movie/\(credit.id)/external_ids"
        guard let imdb = JSONValue.parse(try await get(path))?["imdb_id"]?.string, imdb.hasPrefix("tt") else { return nil }
        imdbCache[k] = imdb
        return imdb
    }
}
