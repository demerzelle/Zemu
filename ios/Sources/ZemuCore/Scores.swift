import Foundation

/** Critic scores and the US rating of a title. */
public struct TitleScores: Sendable, Equatable {
    /** "PG-13", "TV-14", … (nil when unrated). */
    public var rated: String?
    /** Rotten Tomatoes Tomatometer, 0–100. */
    public var rottenTomatoes: Int?
    /** Metascore, 0–100. */
    public var metacritic: Int?
}

/**
 * Scores from OMDb (omdbapi.com; a free key, 1,000 lookups a day). Without a key nothing is
 * fetched. Remembered for the session.
 */
@MainActor
public final class Scores {
    private let key: () -> String
    private var cache: [String: TitleScores] = [:]

    public init(key: @escaping () -> String) { self.key = key }

    public var enabled: Bool { !key().trimmed.isEmpty }

    public func of(_ imdbId: String) async -> TitleScores? {
        guard enabled, imdbId.hasPrefix("tt") else { return nil }
        if let c = cache[imdbId] { return c }
        guard let o = await HTTP.json("https://www.omdbapi.com/?i=\(imdbId.urlEncoded)&apikey=\(key().trimmed.urlEncoded)"),
              o["Response"]?.string != "False" else { return nil }
        var ratings: [String: String] = [:]
        for r in o["Ratings"]?.array ?? [] { if let s = r["Source"]?.string, let v = r["Value"]?.string { ratings[s] = v } }
        let s = TitleScores(
            rated: o["Rated"]?.string.flatMap { Ratings.isRating($0) ? $0 : nil },
            rottenTomatoes: ratings["Rotten Tomatoes"].flatMap { Int($0.replacingOccurrences(of: "%", with: "")) },
            metacritic: ratings["Metacritic"].flatMap { Int($0.split(separator: "/").first ?? "") } ?? o["Metascore"]?.string.flatMap { Int($0) }
        )
        cache[imdbId] = s
        return s
    }
}

/** US movie and TV ratings. */
public enum Ratings {
    public static let unrated = "NR"
    public static let movie = ["G", "PG", "PG-13", "R"]
    public static let tv = ["TV-Y", "TV-Y7", "TV-G", "TV-PG", "TV-14"]
    public static let defaultAllowed: Set<String> = ["G", "PG", "TV-Y", "TV-Y7", "TV-G", unrated]

    /** "tv-y7 " → "TV-Y7"; Kitsu's anime ratings map onto the movie ones. */
    public static func normalize(_ cert: String) -> String {
        switch cert.trimmed.uppercased() {
        case "TV-Y7-FV": return "TV-Y7"
        case "R18": return "NC-17"
        case let c: return c
        }
    }

    /** Kids' content only: family or kids genres (Animation alone isn't enough: think adult cartoons). */
    public static func isKidsGenre(_ genres: [String]) -> Bool {
        genres.contains { ["family", "kids", "children"].contains($0.lowercased()) }
    }

    public static func allows(_ allowed: Set<String>, cert: String, kidsGenre: Bool) -> Bool {
        kidsGenre && (cert.isEmpty ? allowed.contains(unrated) : allowed.contains(normalize(cert)))
    }

    /** A US movie or TV rating ("PG-13", "TV-MA"), as opposed to "N/A", "Not Rated", "Unrated". */
    public static func isRating(_ cert: String) -> Bool { (movie + tv + ["NC-17", "TV-MA"]).contains(normalize(cert)) }
}
