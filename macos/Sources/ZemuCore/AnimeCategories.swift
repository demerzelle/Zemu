import Foundation

/** A row of anime grouped by a genre, a release year or a studio. */
public struct AnimeCategoryRow: Sendable {
    public let key: String
    public let title: String
    public let items: [Meta]

    public init(key: String, title: String, items: [Meta]) {
        self.key = key; self.title = title; self.items = items
    }
}

/**
 * Category rows for the Anime page. Genre rows use Kitsu's genre filter. The other rows are built from
 * the titles already loaded: genre mash-ups, acclaimed titles that aren't mainstream hits, what the user
 * watched, release years and studios. Kitsu reports studios only per title, so each title's studios
 * are fetched once and kept for the session.
 */
@MainActor
public final class AnimeCategories {
    static let defaultGenres = ["Action", "Comedy", "Romance", "Fantasy", "Sci-Fi", "Horror", "Slice of Life"]
    /** Adult or niche tags, left out of mash-up names. */
    private nonisolated static let skippedGenres: Set<String> = ["Hentai", "Ecchi", "Gore", "Mature", "Kids", "Doujinshi", "Anime Influenced", "Gender Bender"]
    private nonisolated static let headers = ["User-Agent": "Zemu/1.0"]
    private nonisolated static let rowLimit = 4
    private nonisolated static let minTitles = 4
    /** Studio lookups per session are capped so a large catalog doesn't mean hundreds of requests. */
    private static let studioTitleLimit = 48

    private let addons: AddonRepository
    private var studios: [String: [String]] = [:]

    public init(addons: AddonRepository) { self.addons = addons }

    /**
     * Rows for the Anime page, most personal first: because you watched, genre rows, genre mash-ups,
     * acclaimed titles that aren't mainstream hits, then years and studios. [watched] is the user's
     * recent anime, most recent first. [isEnabled] says whether a Kitsu list (by catalog id) is on in Addons.
     */
    public func load(topGenres: [String], watched: [Meta], isEnabled: (String) -> Bool) async -> [AnimeCategoryRow] {
        guard let kitsu = addons.kitsu else { return [] }
        let catalogs = kitsu.manifest.catalogs
        let genreOptions = catalogs.first { $0.id == "kitsu-anime-popular" }?.optionsFor("genre") ?? []
        // Genre rows come from the popular list, so they follow its switch.
        let popularOn = isEnabled("kitsu-anime-popular")
        let genres = popularOn ? Array((topGenres + Self.defaultGenres).filter { genreOptions.contains($0) }.distinct().prefix(6)) : []
        let baseIds = ["kitsu-anime-popular", "kitsu-anime-rating", "kitsu-anime-airing", "kitsu-anime-trending"]
            .filter { id in catalogs.contains { $0.id == id } && isEnabled(id) }

        async let genreLists = concurrentMap(genres) { g in
            (try? await self.addons.catalog(kitsu, type: "anime", id: "kitsu-anime-popular", extra: ["genre": g])) ?? []
        }
        async let baseLists = concurrentMap(baseIds) { id in
            (try? await self.addons.catalog(kitsu, type: "anime", id: id)) ?? []
        }
        let genreItems = await genreLists
        let baseItems = await baseLists
        let byId = Dictionary(uniqueKeysWithValues: zip(baseIds, baseItems))
        let pool = Array(baseItems.flatMap { $0 }.distinct(by: AnimeSeasons.groupKey).prefix(Self.studioTitleLimit))

        let genreRows = zip(genres, genreItems).filter { !$0.1.isEmpty }.map {
            AnimeCategoryRow(key: "anime-genre-\($0.0)", title: "\($0.0) Anime", items: $0.1)
        }
        let names = await studioNames(for: pool)

        var rows: [AnimeCategoryRow] = []
        if let row = Self.becauseRow(pool, watched: watched) { rows.append(row) }
        rows += genreRows
        rows += Self.mashUpRows(pool)
        if let row = Self.acclaimedRow(rated: byId["kitsu-anime-rating"] ?? [], popular: byId["kitsu-anime-popular"] ?? []) {
            rows.append(row)
        }
        rows += Self.yearRows(pool)
        rows += Self.studioRows(pool, studios: names)
        return rows
    }

    /** Fetches studios for titles not fetched yet, six at a time. Failed requests are retried next time. */
    private func studioNames(for metas: [Meta]) async -> [String: [String]] {
        let missing = metas.filter { studios[$0.id] == nil }
        for start in stride(from: 0, to: missing.count, by: 6) {
            let batch = Array(missing[start..<min(start + 6, missing.count)])
            let found = await concurrentMap(batch) { m in
                await Self.fetchStudios(kitsuId: m.id.removingPrefix("kitsu:"))
            }
            for (m, names) in zip(batch, found) {
                if let names { studios[m.id] = names }
            }
        }
        return studios
    }

    /** Studio names for one Kitsu title, or nil when the request failed. */
    nonisolated static func fetchStudios(kitsuId: String) async -> [String]? {
        guard let json = await HTTP.json("https://kitsu.io/api/edge/anime/\(kitsuId)?include=productions.company", headers: headers) else {
            return nil
        }
        return studios(fromKitsu: json)
    }

    /** Studio names from a Kitsu anime response requested with include=productions.company. */
    public nonisolated static func studios(fromKitsu json: JSONValue) -> [String] {
        guard let included = json["included"]?.array else { return [] }
        var companyNames: [String: String] = [:]
        var studioCompanyIds: [String] = []
        for item in included {
            let type = item["type"]?.text
            if type == "producers", let id = item["id"]?.text, let name = item["attributes"]?["name"]?.string {
                companyNames[id] = name
            } else if type == "mediaProductions", item["attributes"]?["role"]?.text == "studio",
                      let id = item["relationships"]?["company"]?["data"]?["id"]?.text {
                studioCompanyIds.append(id)
            }
        }
        return studioCompanyIds.compactMap { companyNames[$0] }.distinct()
    }

    /** Titles that share the most genres with the most recent anime the user watched. */
    public nonisolated static func becauseRow(_ pool: [Meta], watched: [Meta]) -> AnimeCategoryRow? {
        for seed in watched {
            guard let name = seed.name, !seed.genres.isEmpty else { continue }
            let seedKey = AnimeSeasons.groupKey(seed)
            let seedGenres = Set(seed.genres)
            let similar = pool
                .filter { AnimeSeasons.groupKey($0) != seedKey }
                .map { ($0, Set($0.genres).intersection(seedGenres).count) }
                .filter { $0.1 >= 2 }
                .stableSorted { $0.1 > $1.1 }
                .prefix(16)
                .map { $0.0 }
            if similar.count >= minTitles {
                return AnimeCategoryRow(key: "anime-because-\(seedKey)", title: "Because you watched \(name)", items: similar)
            }
        }
        return nil
    }

    /** Genre pairs that many titles share, e.g. "Action × Fantasy". */
    public nonisolated static func mashUpRows(_ pool: [Meta]) -> [AnimeCategoryRow] {
        var counts: [String: Int] = [:]
        for m in pool {
            let genres = mashUpGenres(m)
            for i in genres.indices {
                for j in genres.indices where j > i { counts["\(genres[i]) × \(genres[j])", default: 0] += 1 }
            }
        }
        let best = counts.filter { $0.value >= minTitles }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(2)
        return best.map { pair in
            let parts = pair.key.components(separatedBy: " × ")
            let items = pool.filter { m in parts.allSatisfy { m.genres.contains($0) } }
            return AnimeCategoryRow(key: "anime-mash-\(pair.key)", title: pair.key, items: items)
        }
    }

    private nonisolated static func mashUpGenres(_ m: Meta) -> [String] {
        Array(Set(m.genres.filter { !skippedGenres.contains($0) })).sorted()
    }

    /** Highly rated titles that aren't on the popular list: acclaimed, but not mainstream hits. */
    public nonisolated static func acclaimedRow(rated: [Meta], popular: [Meta]) -> AnimeCategoryRow? {
        let popularKeys = Set(popular.map(AnimeSeasons.groupKey))
        let gems = rated.filter { !popularKeys.contains(AnimeSeasons.groupKey($0)) }.distinct(by: AnimeSeasons.groupKey)
        guard gems.count >= minTitles else { return nil }
        return AnimeCategoryRow(key: "anime-acclaimed", title: "Acclaimed, not yet mainstream", items: gems)
    }

    /** Titles grouped by release year: the newest years that have enough titles. */
    public nonisolated static func yearRows(_ pool: [Meta]) -> [AnimeCategoryRow] {
        var byYear: [Int: [Meta]] = [:]
        for m in pool {
            if let y = m.year { byYear[y, default: []].append(m) }
        }
        return byYear.filter { $0.value.count >= minTitles }
            .sorted { $0.key > $1.key }
            .prefix(rowLimit)
            .map { AnimeCategoryRow(key: "anime-year-\($0.key)", title: "Anime from \($0.key)", items: $0.value) }
    }

    /** Titles grouped by studio: the studios with the most titles first. */
    public nonisolated static func studioRows(_ pool: [Meta], studios: [String: [String]]) -> [AnimeCategoryRow] {
        var byStudio: [String: [Meta]] = [:]
        for m in pool {
            for name in (studios[m.id] ?? []).distinct() { byStudio[name, default: []].append(m) }
        }
        return byStudio.filter { $0.value.count >= minTitles }
            .sorted { $0.value.count != $1.value.count ? $0.value.count > $1.value.count : $0.key < $1.key }
            .prefix(rowLimit)
            .map { AnimeCategoryRow(key: "anime-studio-\($0.key)", title: "Studio · \($0.key)", items: $0.value) }
    }
}
