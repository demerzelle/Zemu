import Foundation

/** A cast member from any source. [personKey] opens the person page ("tmdb:123", "imdb:nm123", "name:Full Name"). */
public struct CastPerson: Hashable, Sendable {
    public var name: String
    public var role: String?
    public var photo: String?
    public var personKey: String?
    public init(name: String, role: String?, photo: String?, personKey: String?) {
        self.name = name; self.role = role; self.photo = photo; self.personKey = personKey
    }
}

/** Person page data from the free sources. */
public struct FreePerson: Sendable {
    public var name: String
    public var photo: String?
    public var description: String?
    public var born: String?
    public var credits: [Meta]
}

/**
 * Cast and filmographies without any API key:
 *  - TVmaze (series cast with photos and characters)
 *  - Wikidata (movie cast lists and actor filmographies, by IMDb ids)
 *  - IMDb's public search suggestions (head shots)
 */
@MainActor
public final class FreeCast {
    private var castCache: [String: [CastPerson]] = [:]
    private var photoCache: [String: String] = [:]
    private var personCache: [String: FreePerson] = [:]

    public init() {}

    private static let headers = ["User-Agent": "Zemu/1.0 (macOS media app)"]

    private func get(_ url: String) async -> JSONValue? { await HTTP.json(url, headers: Self.headers) }

    private func sparql(_ query: String) async -> [JSONValue] {
        var c = URLComponents(string: "https://query.wikidata.org/sparql")!
        c.queryItems = [URLQueryItem(name: "query", value: query), URLQueryItem(name: "format", value: "json")]
        return await get(c.url!.absoluteString)?["results"]?["bindings"]?.array ?? []
    }

    private func commonsThumb(_ url: String?) -> String? { url.map { $0.replacingOccurrences(of: "http://", with: "https://") + "?width=300" } }

    /** IMDb head shot for a name (also returns the IMDb person id). */
    public func imdbPerson(_ name: String) async -> (id: String?, image: String?) {
        let lower = name.lowercased()
        let first = lower.first { $0.isLetter || $0.isNumber } ?? "x"
        guard let d = await get("https://v3.sg.media-imdb.com/suggestion/\(first)/\(lower.urlEncoded).json")?["d"]?.array?
            .first(where: { $0["id"]?.string?.hasPrefix("nm") == true }) else { return (nil, nil) }
        let img = d["i"]?["imageUrl"]?.string?.replacingOccurrences(of: "._V1_.jpg", with: "._V1_UX300_.jpg")
        return (d["id"]?.string, img)
    }

    public func photoFor(_ name: String) async -> String? {
        if let c = photoCache[name] { return c.isEmpty ? nil : c }
        let photo = await imdbPerson(name).image
        photoCache[name] = photo ?? ""
        return photo
    }

    public func cast(_ meta: Meta) async -> [CastPerson] {
        if let c = castCache[meta.id] { return c }
        let imdb = meta.imdbId.hasPrefix("tt") ? meta.imdbId : nil
        var list: [CastPerson] = []
        if let imdb {
            if meta.type == "series" { list = await tvmaze(imdb) }
            if list.isEmpty { list = await wikidataCast(imdb, meta) }
        }
        if list.isEmpty { list = meta.cast.map { CastPerson(name: $0, role: nil, photo: nil, personKey: "name:\($0)") } }
        castCache[meta.id] = list
        return list
    }

    private func tvmaze(_ imdb: String) async -> [CastPerson] {
        guard let id = await get("https://api.tvmaze.com/lookup/shows?imdb=\(imdb)")?["id"]?.text,
              let cast = await get("https://api.tvmaze.com/shows/\(id)/cast")?.array else { return [] }
        return cast.compactMap { c -> CastPerson? in
            guard let name = c["person"]?["name"]?.string else { return nil }
            return CastPerson(name: name, role: c["character"]?["name"]?.string,
                              photo: c["person"]?["image"]?["medium"]?.string ?? c["character"]?["image"]?["medium"]?.string,
                              personKey: "name:\(name)")
        }.distinct(by: \.name)
    }

    private func wikidataCast(_ imdb: String, _ meta: Meta) async -> [CastPerson] {
        let rows = await sparql("""
            SELECT ?actorLabel ?img ?nm WHERE { ?film wdt:P345 "\(imdb)". ?film wdt:P161 ?actor.
              OPTIONAL { ?actor wdt:P18 ?img } OPTIONAL { ?actor wdt:P345 ?nm }
              SERVICE wikibase:label { bd:serviceParam wikibase:language "en". } } LIMIT 40
            """)
        let people = rows.compactMap { r -> CastPerson? in
            guard let name = r["actorLabel"]?["value"]?.string, !name.hasPrefix("Q") else { return nil }
            let nm = r["nm"]?["value"]?.string
            return CastPerson(name: name, role: nil, photo: commonsThumb(r["img"]?["value"]?.string), personKey: nm.map { "imdb:\($0)" } ?? "name:\(name)")
        }.distinct(by: \.name)
        // Wikidata has no billing order: put the stars Cinemeta lists first.
        let top = meta.cast.map { $0.lowercased() }
        return people.stableSorted { (top.firstIndex(of: $0.name.lowercased()) ?? .max) < (top.firstIndex(of: $1.name.lowercased()) ?? .max) }
    }

    /** Photo and name only, available almost immediately, for the top of the person page. */
    public func personHeader(_ key: String) async -> (name: String, photo: String?)? {
        if key.hasPrefix("name:") {
            let n = key.removingPrefix("name:")
            return (n, await photoFor(n))
        }
        guard key.hasPrefix("imdb:") else { return nil }
        let nm = key.removingPrefix("imdb:")
        guard let name = await sparql("SELECT ?aLabel WHERE { ?a wdt:P345 \"\(nm)\". SERVICE wikibase:label { bd:serviceParam wikibase:language \"en\". } } LIMIT 1")
            .first?["aLabel"]?["value"]?.string else { return nil }
        return (name, await photoFor(name))
    }

    /** [key] is "imdb:nm…" or "name:Full Name". */
    public func person(_ key: String) async -> FreePerson? {
        if let c = personCache[key] { return c }
        let name0 = key.hasPrefix("name:") ? key.removingPrefix("name:") : ""
        var nm: String? = key.hasPrefix("imdb:") ? key.removingPrefix("imdb:") : nil
        var imdbPhoto: String?
        if nm == nil && !name0.isEmpty {
            let p = await imdbPerson(name0)
            nm = p.id; imdbPhoto = p.image
        }
        guard let id = nm else { return nil }
        let info = await sparql("""
            SELECT ?aLabel ?aDescription ?img ?born WHERE { ?a wdt:P345 "\(id)".
              OPTIONAL { ?a wdt:P18 ?img } OPTIONAL { ?a wdt:P569 ?born }
              SERVICE wikibase:label { bd:serviceParam wikibase:language "en". } } LIMIT 1
            """).first
        let films = await sparql("""
            SELECT ?film ?filmLabel ?tt ?date ?inst WHERE { ?a wdt:P345 "\(id)". { ?film wdt:P161 ?a } UNION { ?film wdt:P57 ?a }
              ?film wdt:P345 ?tt. FILTER(STRSTARTS(?tt, "tt"))
              OPTIONAL { ?film wdt:P577 ?date } OPTIONAL { ?film wdt:P31 ?inst }
              SERVICE wikibase:label { bd:serviceParam wikibase:language "en". } } LIMIT 300
            """)
        let tvTypes: Set<String> = ["Q5398426", "Q117467246", "Q526877", "Q1259759", "Q581714", "Q63952888"]
        let grouped = Dictionary(grouping: films) { $0["tt"]?["value"]?.string ?? "" }
        let credits = grouped.compactMap { tt, rows -> Meta? in
            guard !tt.isEmpty else { return nil }
            let isTv = rows.contains { r in (r["inst"]?["value"]?.string?.components(separatedBy: "/").last).map(tvTypes.contains) ?? false }
            let year = rows.compactMap { $0["date"]?["value"]?.string.map { String($0.prefix(4)) } }.min()
            return Meta(id: tt, type: isTv ? "series" : "movie", name: rows.first?["filmLabel"]?["value"]?.string, releaseInfo: year)
        }.filter { !($0.name ?? "Q").hasPrefix("Q") }.sorted { ($0.releaseInfo ?? "") > ($1.releaseInfo ?? "") }
        let name = info?["aLabel"]?["value"]?.string ?? (name0.isEmpty ? id : name0)
        var photo = imdbPhoto
        if photo == nil { photo = await photoFor(name) }
        if photo == nil { photo = commonsThumb(info?["img"]?["value"]?.string) }
        let p = FreePerson(name: name, photo: photo, description: info?["aDescription"]?["value"]?.string,
                           born: info?["born"]?["value"]?.string.map { String($0.prefix(10)) }, credits: credits)
        personCache[key] = p
        return p
    }
}
