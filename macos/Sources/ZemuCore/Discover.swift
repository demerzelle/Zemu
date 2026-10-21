import Foundation

/** Any streaming service: TMDB provider [ids] ("|" = any of them), its name and logo. */
public struct Provider: Hashable, Sendable {
    public let ids: String
    public let label: String
    public var logo: String?
    public init(ids: String, label: String, logo: String? = nil) { self.ids = ids; self.label = label; self.logo = logo }
}

/** The big streaming services; ids are TMDB watch-provider ids ("|" = any, for renamed services). */
public enum StreamingService {
    public static let all: [Provider] = [
        Provider(ids: "8", label: "Netflix"), Provider(ids: "15", label: "Hulu"), Provider(ids: "337", label: "Disney+"),
        Provider(ids: "1899|384", label: "HBO Max"), Provider(ids: "9|119", label: "Prime Video"), Provider(ids: "350", label: "Apple TV"),
        Provider(ids: "2303|2616|531", label: "Paramount+"), Provider(ids: "386|387", label: "Peacock"), Provider(ids: "526", label: "AMC+"),
        Provider(ids: "99", label: "Shudder"), Provider(ids: "283", label: "Crunchyroll"),
    ]
    public static let crunchyroll = all[10], netflix = all[0], hulu = all[1]
}

/** A studio (movies, TMDB company id) or a network (series, TMDB network id). */
public struct Studio: Hashable, Sendable {
    public let key: String
    public let label: String
    public let type: String
    public let id: Int

    /** The TMDB discover parameter for this studio. */
    public var param: (String, String) { (type == "series" ? "with_networks" : "with_companies", String(id)) }

    public static let all: [Studio] = [
        ("a24", "A24", "movie", 41077), ("pixar", "Pixar", "movie", 3), ("wb", "Warner Bros.", "movie", 174),
        ("marvel", "Marvel Studios", "movie", 420), ("disney", "Walt Disney Pictures", "movie", 2), ("universal", "Universal", "movie", 33),
        ("paramount", "Paramount", "movie", 4), ("lucasfilm", "Lucasfilm", "movie", 1), ("ghibli", "Studio Ghibli", "movie", 10342),
        ("blumhouse", "Blumhouse", "movie", 3172), ("neon", "Neon", "movie", 90733), ("dreamworks", "DreamWorks Animation", "movie", 521),
        ("legendary", "Legendary", "movie", 923), ("searchlight", "Searchlight", "movie", 43), ("lionsgate", "Lionsgate", "movie", 1632),
        ("columbia", "Columbia", "movie", 5), ("newline", "New Line", "movie", 12), ("focus", "Focus Features", "movie", 10146),
        ("illumination", "Illumination", "movie", 6704),
        ("hbo", "HBO", "series", 49), ("amc", "AMC", "series", 174), ("fx", "FX", "series", 88), ("netflix-tv", "Netflix", "series", 213),
        ("bbc", "BBC One", "series", 4), ("showtime", "Showtime", "series", 67), ("adultswim", "Adult Swim", "series", 80),
        ("appletv", "Apple TV", "series", 2552), ("disneyplus", "Disney+", "series", 2739), ("hulu-tv", "Hulu", "series", 453),
        ("prime-tv", "Prime Video", "series", 1024), ("paramountplus", "Paramount+", "series", 4330), ("peacock-tv", "Peacock", "series", 3353),
        ("max-tv", "HBO Max", "series", 3186), ("cartoon", "Cartoon Network", "series", 56), ("comedy", "Comedy Central", "series", 47),
        ("nbc", "NBC", "series", 6), ("abc", "ABC", "series", 2), ("cbs", "CBS", "series", 16), ("fox", "FOX", "series", 19),
    ].map { Studio(key: $0.0, label: $0.1, type: $0.2, id: $0.3) }

    public static func of(_ key: String?) -> Studio? { all.first { $0.key == key } }
    public static func forType(_ type: String) -> [Studio] { all.filter { $0.type == type } }
}

/** How to load one row: a TMDB discover query ([tmdb]) or an addon catalog. */
public struct RowSpec: Codable, Hashable, Sendable {
    public var key: String
    public var title: String
    public var priority: Int
    /** "movie" or "series" (the titles' type). */
    public var type: String
    public var tmdb: [String: String]?
    public var addonId: String?
    public var catalogType: String?
    public var catalogId: String?
    public var extra: [String: String] = [:]
    public var limit = 40
    /** "See more" opens the grid for this service (provider ids) / studio. */
    public var service: String?
    public var serviceLabel: String?
    public var studio: String?

    public init(key: String, title: String, priority: Int, type: String, tmdb: [String: String]? = nil, addonId: String? = nil,
                catalogType: String? = nil, catalogId: String? = nil, extra: [String: String] = [:], limit: Int = 40,
                service: String? = nil, serviceLabel: String? = nil, studio: String? = nil) {
        self.key = key; self.title = title; self.priority = priority; self.type = type; self.tmdb = tmdb; self.addonId = addonId
        self.catalogType = catalogType; self.catalogId = catalogId; self.extra = extra; self.limit = limit
        self.service = service; self.serviceLabel = serviceLabel; self.studio = studio
    }
}

/** TMDB discover parameters shared by rows and the grid. */
public enum DiscoverParams {
    public static var region: String { Locale.current.region?.identifier.count == 2 ? Locale.current.region!.identifier : "US" }

    static func today() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    public static func service(_ ids: String) -> [String: String] {
        ["with_watch_providers": ids, "watch_region": region, "with_watch_monetization_types": "flatrate"]
    }

    public static func dateField(_ type: String) -> String { type == "series" ? "first_air_date" : "primary_release_date" }

    public static func popular() -> [String: String] { ["sort_by": "popularity.desc"] }
    public static func newest(_ type: String) -> [String: String] {
        ["sort_by": "\(dateField(type)).desc", "\(dateField(type)).lte": today(), "vote_count.gte": "10"]
    }
    public static func mostFavorited() -> [String: String] { ["sort_by": "vote_count.desc"] }
    public static func topRated(_ minVotes: Int = 300) -> [String: String] { ["sort_by": "vote_average.desc", "vote_count.gte": String(minVotes)] }
}

/**
 * Rotating categories for a page: streaming services, studios, genres and decades. A different mix
 * each time ([seed]). Needs a TMDB key.
 */
public enum Categories {
    static let movieGenres = ["Action", "Comedy", "Horror", "Sci-Fi", "Thriller", "Animation", "Romance", "Drama", "Crime", "Fantasy", "Mystery", "Documentary", "Family", "Adventure"]
    static let seriesGenres = ["Drama", "Comedy", "Crime", "Sci-Fi", "Animation", "Mystery", "Documentary", "Reality", "Action"]

    /** [page] is "home", "movie", "series" or "anime"; [taste] genres come up more often; [mine] are your services. */
    public static func tmdbRows(page: String, seed: Int64, taste: [String], mine: [Provider] = []) -> [RowSpec] {
        var rnd = SeededRandom(seed: seed)
        var out: [RowSpec] = []
        if page == "anime" {
            for (i, s) in [StreamingService.crunchyroll, StreamingService.netflix, StreamingService.hulu].enumerated() {
                out.append(RowSpec(key: "anime/svc-\(s.ids)", title: "Anime on \(s.label)", priority: 20 + i, type: "series",
                                   tmdb: DiscoverParams.service(s.ids).merging(DiscoverParams.popular()) { a, _ in a }.merging(["with_genres": "16", "with_original_language": "ja"]) { a, _ in a },
                                   service: s.ids, serviceLabel: s.label))
            }
            return out
        }
        let types = page == "home" ? ["movie", "series"] : [page]
        let services = (mine.isEmpty ? StreamingService.all.filter { $0.ids != StreamingService.crunchyroll.ids } : mine).shuffled(using: &rnd)
        var p = 20
        func add(_ type: String, _ key: String, _ title: String, _ params: [String: String], limit: Int = 40, service: Provider? = nil, studio: Studio? = nil) {
            out.append(RowSpec(key: "\(type)/\(key)", title: title, priority: p, type: type, tmdb: params, limit: limit,
                               service: service?.ids, serviceLabel: service?.label, studio: studio?.key))
            p += 1
        }
        func merged(_ a: [String: String], _ b: [String: String]) -> [String: String] { a.merging(b) { x, _ in x } }
        let providerRows = min(page == "home" ? 3 : 4, services.count)
        for (i, s) in services.prefix(providerRows).enumerated() {
            let type = types[i % types.count]
            let kinds: [(String, String, [String: String])] = [
                ("top", "Top 20 on \(s.label)", DiscoverParams.popular()),
                ("new", "New on \(s.label)", DiscoverParams.newest(type)),
                ("fav", "Most Favorited on \(s.label)", DiscoverParams.mostFavorited()),
                ("rated", "Top Rated on \(s.label)", DiscoverParams.topRated()),
            ]
            let (k, title, params) = kinds[Int(rnd.next() % UInt64(kinds.count))]
            add(type, "svc-\(s.ids)-\(k)", page == "home" ? "\(title) · \(type == "series" ? "Series" : "Movies")" : title,
                merged(DiscoverParams.service(s.ids), params), limit: k == "top" ? 20 : 40, service: s)
        }
        for type in types {
            for st in Studio.forType(type).shuffled(using: &rnd).prefix(page == "home" ? 1 : 3) {
                let kinds: [(String, String, [String: String])] = [
                    ("top", "Top 20 from \(st.label)", DiscoverParams.popular()),
                    ("new", "New from \(st.label)", DiscoverParams.newest(type)),
                    ("best", "Best of \(st.label)", DiscoverParams.topRated(150)),
                ]
                let (k, title, params) = kinds[Int(rnd.next() % UInt64(kinds.count))]
                add(type, "studio-\(st.key)-\(k)", title, merged([st.param.0: st.param.1], params), limit: k == "top" ? 20 : 40, studio: st)
            }
        }
        if page != "home" {
            let type = page
            let pool = type == "series" ? seriesGenres : movieGenres
            let genres = (taste.filter { pool.contains($0) } + pool.shuffled(using: &rnd)).distinct()
            // A genre on a service, e.g. "Horror on Shudder".
            if !services.isEmpty, let g = genres.first, let id = Tmdb.genreId(type, g) {
                let s = services[providerRows % services.count]
                add(type, "svcgenre-\(s.ids)-\(g)", "\(g) on \(s.label)", merged(merged(DiscoverParams.service(s.ids), DiscoverParams.popular()), ["with_genres": String(id)]), service: s)
            }
            if genres.count > 1, let id = Tmdb.genreId(type, genres[1]) {
                add(type, "acclaimed-\(genres[1])", "Acclaimed \(genres[1])", merged(DiscoverParams.topRated(1500), ["with_genres": String(id)]))
            }
            let decade = [1970, 1980, 1990, 2000, 2010][Int(rnd.next() % 5)]
            let f = DiscoverParams.dateField(type)
            add(type, "decade-\(decade)", decade == 2000 ? "Best of the 2000s" : "Best of the \(decade % 100)s",
                merged(DiscoverParams.topRated(500), ["\(f).gte": "\(decade)-01-01", "\(f).lte": "\(decade + 9)-12-31"]))
        }
        return out
    }
}
