import Foundation

// Shapes follow the Stremio addon protocol (github.com/Stremio/stremio-addon-sdk/tree/master/docs/api).

public struct Meta: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var type: String
    /** TMDB id (Cinemeta), used for cast data and skip-intro lookups. */
    public var tmdbId: String?
    /** IMDb id when [id] is another scheme (e.g. Kitsu metas). */
    public var imdbIdField: String?
    public var name: String?
    public var poster: String?
    public var background: String?
    public var logo: String?
    public var description: String?
    public var releaseInfo: String?
    public var imdbRating: String?
    public var genres: [String]
    public var runtime: String?
    public var cast: [String]
    public var director: [String]
    public var released: String?
    public var videos: [Video]
    public var trailers: [Trailer]
    public var trailerStreams: [TrailerStream]

    enum CodingKeys: String, CodingKey {
        case id, type, name, poster, background, logo, description, releaseInfo, imdbRating, genres, runtime
        case cast, director, released, videos, trailers, trailerStreams
        case tmdbId = "moviedb_id"
        case imdbIdField = "imdb_id"
    }

    public init(
        id: String, type: String = "movie", tmdbId: String? = nil, imdbIdField: String? = nil, name: String? = nil,
        poster: String? = nil, background: String? = nil, logo: String? = nil, description: String? = nil,
        releaseInfo: String? = nil, imdbRating: String? = nil, genres: [String] = [], runtime: String? = nil,
        cast: [String] = [], director: [String] = [], released: String? = nil, videos: [Video] = [],
        trailers: [Trailer] = [], trailerStreams: [TrailerStream] = []
    ) {
        self.id = id; self.type = type; self.tmdbId = tmdbId; self.imdbIdField = imdbIdField; self.name = name
        self.poster = poster; self.background = background; self.logo = logo; self.description = description
        self.releaseInfo = releaseInfo; self.imdbRating = imdbRating; self.genres = genres; self.runtime = runtime
        self.cast = cast; self.director = director; self.released = released; self.videos = videos
        self.trailers = trailers; self.trailerStreams = trailerStreams
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.str(.id) ?? ""
        type = c.str(.type) ?? "movie"
        tmdbId = c.str(.tmdbId)
        imdbIdField = c.str(.imdbIdField)
        name = c.str(.name)
        poster = c.str(.poster)
        background = c.str(.background)
        logo = c.str(.logo)
        description = c.str(.description)
        releaseInfo = c.str(.releaseInfo)
        imdbRating = c.str(.imdbRating)
        genres = c.strList(.genres)
        runtime = c.str(.runtime)
        cast = c.strList(.cast)
        director = c.strList(.director)
        released = c.str(.released)
        videos = c.list(.videos, Video.self)
        trailers = c.list(.trailers, Trailer.self)
        trailerStreams = c.list(.trailerStreams, TrailerStream.self)
    }
}

public struct TrailerStream: Codable, Hashable, Sendable {
    public var title: String?
    public var ytId: String?
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = c.str(.title); ytId = c.str(.ytId)
    }
}

public struct Trailer: Codable, Hashable, Sendable {
    public var source: String?
    public var type: String?
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        source = c.str(.source); type = c.str(.type)
    }
}

public struct Video: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var title: String?
    public var name: String?
    public var season: Int?
    public var episode: Int?
    public var number: Int?
    public var released: String?
    public var thumbnail: String?
    public var overview: String?
    public var description: String?

    public init(id: String, title: String? = nil, season: Int? = nil, episode: Int? = nil) {
        self.id = id; self.title = title; self.season = season; self.episode = episode
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.str(.id) ?? ""
        title = c.str(.title); name = c.str(.name)
        season = c.int(.season); episode = c.int(.episode); number = c.int(.number)
        released = c.str(.released); thumbnail = c.str(.thumbnail)
        overview = c.str(.overview); description = c.str(.description)
    }

    public var episodeNumber: Int { episode ?? number ?? 0 }
    public var displayTitle: String { title ?? name ?? "Episode \(episodeNumber)" }
    public var synopsis: String? { overview ?? description }
    /** "S1 E2 · Title", or just the title for things without seasons. */
    public var label: String { season != nil ? "S\(season!) E\(episodeNumber) · \(displayTitle)" : displayTitle }
}

public struct Stream: Codable, Hashable, Sendable {
    public var name: String?
    public var title: String?
    public var description: String?
    public var url: String?
    public var infoHash: String?
    public var fileIdx: Int?
    public var externalUrl: String?
    public var ytId: String?
    public var behaviorHints: StreamBehaviorHints?
    public var subtitles: [SubtitleTrack]

    public init(name: String? = nil, title: String? = nil, description: String? = nil, url: String? = nil,
                infoHash: String? = nil, fileIdx: Int? = nil, behaviorHints: StreamBehaviorHints? = nil,
                subtitles: [SubtitleTrack] = []) {
        self.name = name; self.title = title; self.description = description; self.url = url
        self.infoHash = infoHash; self.fileIdx = fileIdx; self.behaviorHints = behaviorHints; self.subtitles = subtitles
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = c.str(.name); title = c.str(.title); description = c.str(.description)
        url = c.str(.url); infoHash = c.str(.infoHash); fileIdx = c.int(.fileIdx)
        externalUrl = c.str(.externalUrl); ytId = c.str(.ytId)
        behaviorHints = c.lenient(.behaviorHints, StreamBehaviorHints.self)
        subtitles = c.list(.subtitles, SubtitleTrack.self)
    }
}

public struct StreamBehaviorHints: Codable, Hashable, Sendable {
    public var bingeGroup: String?
    public var videoSize: Int64?
    public var filename: String?
    public var proxyHeaders: ProxyHeaders?

    public init(bingeGroup: String? = nil, videoSize: Int64? = nil, filename: String? = nil) {
        self.bingeGroup = bingeGroup; self.videoSize = videoSize; self.filename = filename
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bingeGroup = c.str(.bingeGroup); videoSize = c.int64(.videoSize); filename = c.str(.filename)
        proxyHeaders = c.lenient(.proxyHeaders, ProxyHeaders.self)
    }
}

public struct ProxyHeaders: Codable, Hashable, Sendable {
    public var request: [String: String]
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        request = (c.value(.request)?.object ?? [:]).compactMapValues { $0.text }
    }
}

public struct SubtitleTrack: Codable, Hashable, Sendable {
    public var id: String?
    public var url: String
    public var lang: String

    public init(id: String? = nil, url: String, lang: String) { self.id = id; self.url = url; self.lang = lang }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.str(.id); url = c.str(.url) ?? ""; lang = c.str(.lang) ?? ""
    }
}

struct CatalogResponse: Decodable {
    var metas: [Meta]
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        metas = c.list(.metas, Meta.self)
    }
    enum CodingKeys: String, CodingKey { case metas }
}

struct CatalogDetailedResponse: Decodable {
    var metasDetailed: [Meta]
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        metasDetailed = c.list(.metasDetailed, Meta.self)
    }
    enum CodingKeys: String, CodingKey { case metasDetailed }
}

struct MetaResponse: Decodable {
    var meta: Meta?
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        meta = c.lenient(.meta, Meta.self)
    }
    enum CodingKeys: String, CodingKey { case meta }
}

struct StreamResponse: Decodable {
    var streams: [Stream]
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        streams = c.list(.streams, Stream.self)
    }
    enum CodingKeys: String, CodingKey { case streams }
}

struct SubtitlesResponse: Decodable {
    var subtitles: [SubtitleTrack]
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        subtitles = c.list(.subtitles, SubtitleTrack.self)
    }
    enum CodingKeys: String, CodingKey { case subtitles }
}

// MARK: - Persisted user data

public struct InstalledAddon: Codable, Hashable, Sendable {
    public var transportUrl: String
    public var manifestJson: String
    public init(transportUrl: String, manifestJson: String) { self.transportUrl = transportUrl; self.manifestJson = manifestJson }
}

/** Identifies a played stream: [key] matches the exact release, [bingeGroup] the release group across episodes. */
public struct LastStream: Codable, Hashable, Sendable {
    public var key: String
    public var bingeGroup: String?
    /** The exact link that played (a debrid-resolved file), so resuming replays that same file. */
    public var url: String?
    public var headers: [String: String]?
    public var videoId: String?
    public var label: String?
    public init(key: String, bingeGroup: String?, url: String? = nil, headers: [String: String]? = nil, videoId: String? = nil, label: String? = nil) {
        self.key = key; self.bingeGroup = bingeGroup; self.url = url; self.headers = headers; self.videoId = videoId; self.label = label
    }
}

public struct WatchEntry: Codable, Hashable, Sendable {
    public var meta: Meta
    public var videoId: String
    public var label: String?
    public var positionMs: Int64
    public var durationMs: Int64
    public var updatedAt: Int64

    public init(meta: Meta, videoId: String, label: String?, positionMs: Int64, durationMs: Int64, updatedAt: Int64) {
        self.meta = meta; self.videoId = videoId; self.label = label
        self.positionMs = positionMs; self.durationMs = durationMs; self.updatedAt = updatedAt
    }

    public var progress: Double { durationMs > 0 ? Double(positionMs) / Double(durationMs) : 0 }
}

public func nowMs() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }
