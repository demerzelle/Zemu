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
