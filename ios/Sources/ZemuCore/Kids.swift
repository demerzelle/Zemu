import Foundation
import Observation
import CryptoKit

/**
 * Parental controls, shared by every profile. Kids Mode is on while a kid profile (Profile.kids)
 * is in use; then only kids' titles with an [allowed] rating show, and Settings, addons and
 * switching profile need the parent code.
 */
public struct KidsSettings: Codable, Equatable, Sendable {
    /** Shows the kid-profile option and these settings at all. */
    public var enabled = false
    /** Ratings a kid may watch; Ratings.unrated lets through kids' shows nobody has rated. */
    public var allowed: Set<String> = Ratings.defaultAllowed
    /** Salted SHA-256 of the parent code; empty until one is set. */
    public var pinHash = ""

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = (try? c.decodeIfPresent(Bool.self, forKey: .enabled)) ?? false
        allowed = (try? c.decodeIfPresent(Set<String>.self, forKey: .allowed)) ?? Ratings.defaultAllowed
        pinHash = (try? c.decodeIfPresent(String.self, forKey: .pinHash)) ?? ""
    }

    public static func hash(_ pin: String) -> String {
        SHA256.hash(data: Data("zemu-kids:\(pin)".utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/**
 * Works out and remembers each title's US rating and whether it's a kids' title. Ratings come from
 * OMDb or TMDB when there's a key, else Wikidata for movies; anime uses Kitsu. Also gives the
 * rating badge on title pages.
 */
@MainActor @Observable
public final class KidsGate {
    private let tmdb: Tmdb
    private let scores: Scores
    private let settings: () -> KidsSettings
    private let on: () -> Bool
    @ObservationIgnored private let file = AppPaths.support.appendingPathComponent("kid_ratings.json")
    /** Title id to "<rating>|<1 if a kids' title>"; the rating is "" when none was found. */
    private var known: [String: String]
    @ObservationIgnored private var pending: Set<String> = []
    @ObservationIgnored private var wikidata: [String: String] = [:]
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    public init(tmdb: Tmdb, scores: Scores, settings: @escaping () -> KidsSettings, on: @escaping () -> Bool) {
        self.tmdb = tmdb; self.scores = scores; self.settings = settings; self.on = on
        known = (try? Data(contentsOf: AppPaths.support.appendingPathComponent("kid_ratings.json")))
            .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
    }

    public var active: Bool { on() }

    /** Service, studio and "see more" cards aren't titles and always pass. */
    private func isTitle(_ id: String) -> Bool { id.hasPrefix("tt") || id.hasPrefix("tmdb:") || id.hasPrefix("kitsu:") }

    private func verdict(_ entry: String) -> Bool {
        let p = entry.split(separator: "|", omittingEmptySubsequences: false)
        return Ratings.allows(settings().allowed, cert: p.first.map(String.init) ?? "", kidsGenre: entry.hasSuffix("|1"))
    }

    /** Allowed from what's already known (nil = not looked up yet). */
    public func knownAllowed(_ m: Meta) -> Bool? {
        guard active, isTitle(m.id) else { return true }
        return known[m.id].map(verdict)
    }

    /** [items] minus titles not allowed in Kids Mode. Unknown titles are looked up and appear once allowed. */
    public func safe<T>(_ items: [T], _ meta: (T) -> Meta) -> [T] {
        guard active else { return items }
        let unknown = items.map(meta).filter { isTitle($0.id) && known[$0.id] == nil && !pending.contains($0.id) }
        if !unknown.isEmpty { Task { await self.lookUp(unknown) } }
        return items.filter { knownAllowed(meta($0)) == true }
    }

    public func safe(_ items: [Meta]) -> [Meta] { safe(items) { $0 } }

    /** Looks up a title's verdict (Details pages in Kids Mode). */
    public func allowed(_ m: Meta) async -> Bool {
        if let k = knownAllowed(m) { return k }
        await lookUp([m])
        return knownAllowed(m) ?? false
    }

    /** The title's US rating for a badge ("PG-13"), looked up if needed; nil when unrated or unknown. */
    public func certification(_ m: Meta) async -> String? {
        guard isTitle(m.id) else { return nil }
        if known[m.id] == nil { await lookUp([m]) }
        guard let e = known[m.id], let cert = e.split(separator: "|", omittingEmptySubsequences: false).first.map(String.init), Ratings.isRating(cert) else { return nil }
        return cert
    }

    private func lookUp(_ metas: [Meta]) async {
        let todo = metas.filter { !pending.contains($0.id) }.distinct(by: \.id)
        guard !todo.isEmpty else { return }
        todo.forEach { pending.insert($0.id) }
        defer { todo.forEach { pending.remove($0.id) } }
        await prefetchWikidata(todo)
        for chunk in stride(from: 0, to: todo.count, by: 6).map({ Array(todo[$0..<min($0 + 6, todo.count)]) }) {
            await withTaskGroup(of: Void.self) { g in
                for m in chunk {
                    g.addTask { @MainActor in
                        // Network errors aren't remembered, so they're retried next time.
                        if let e = try? await self.lookup(m) { self.known[m.id] = e }
                    }
                }
            }
        }
        scheduleSave()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard let self, !Task.isCancelled else { return }
            let snapshot = self.known, file = self.file
            DispatchQueue.global(qos: .utility).async { try? JSONEncoder().encode(snapshot).write(to: file, options: .atomic) }
        }
    }

    /** Movie ratings found on Wikidata ahead of time, many titles per request (IMDb id → rating). */
    private func prefetchWikidata(_ metas: [Meta]) async {
        guard !tmdb.enabled, !scores.enabled else { return }
        let ids = metas.filter { $0.type == "movie" && $0.id.hasPrefix("tt") && known[$0.id] == nil }
            .map(\.imdbId).filter { wikidata[$0] == nil }.distinct()
        guard !ids.isEmpty else { return }
        let q = "SELECT ?id ?l WHERE { VALUES ?id { \(ids.map { "\"\($0)\"" }.joined(separator: " ")) } ?i wdt:P345 ?id . ?i wdt:P1657 ?r . ?r rdfs:label ?l FILTER(lang(?l)=\"en\") }"
        guard let v = await HTTP.json("https://query.wikidata.org/sparql?query=\(q.urlEncoded)&format=json") else { return }
        ids.forEach { wikidata[$0] = "" }
        for r in v["results"]?["bindings"]?.array ?? [] {
            if let id = r["id"]?["value"]?.string, let l = r["l"]?["value"]?.string { wikidata[id] = l }
        }
    }

    /** "<rating>|<kids flag>" for a title. */
    private func lookup(_ m: Meta) async throws -> String {
        if m.id.hasPrefix("kitsu:") {
            let id = m.id.split(separator: ":")[1]
            let age = await HTTP.json("https://kitsu.io/api/edge/anime/\(id)")?["data"]?["attributes"]?["ageRating"]?.string ?? ""
            // Anime: only all-ages (G) counts as a kids' title.
            return "\(Ratings.normalize(age))|\(age.uppercased() == "G" ? 1 : 0)"
        }
        var genres = m.genres
        if genres.isEmpty, m.id.hasPrefix("tt") {
            genres = await HTTP.json("https://v3-cinemeta.strem.io/meta/\(m.type)/\(m.imdbId).json")?["meta"]?["genres"]?.stringList ?? []
        }
        let omdb = m.id.hasPrefix("tt") ? await scores.of(m.imdbId)?.rated : nil
        let cert: String
        if let omdb { cert = omdb }
        else if tmdb.enabled { cert = try await tmdb.usCertification(m) ?? "" }
        else if m.type == "movie", m.id.hasPrefix("tt") {
            await prefetchWikidata([m])
            cert = wikidata[m.imdbId] ?? ""
        } else { cert = "" }
        return "\(Ratings.normalize(cert))|\(Ratings.isKidsGenre(genres) ? 1 : 0)"
    }
}
