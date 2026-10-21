import Foundation

public struct Scored: Hashable, Sendable {
    public var meta: Meta
    public var score: Double
    public var matchPercent: Int { min(99, max(50, Int((55 + score * 44).rounded()))) }
}

/** Genre affinity learned from watch history and My List. */
public struct TasteProfile: Sendable {
    public var genreWeights: [String: Double]
    public var seen: Set<String>
    public var isEmpty: Bool { genreWeights.isEmpty }

    public func affinity(_ m: Meta) -> Double {
        guard !isEmpty, !m.genres.isEmpty, let max = genreWeights.values.max() else { return 0 }
        let top = m.genres.prefix(3)
        return min(1, Swift.max(0, top.reduce(0) { $0 + (genreWeights[$1] ?? 0) } / (max * Double(top.count))))
    }

    public func topGenres(_ n: Int) -> [String] {
        genreWeights.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.prefix(n).map(\.key)
    }

    public static func from(history: [WatchEntry], myList: [Meta], rated: [Meta] = [], ratings: [String: Int] = [:]) -> TasteProfile {
        var w: [String: Double] = [:]
        for (i, e) in history.enumerated() {
            // A thumbs-down title shouldn't pull its genres up just because it was watched.
            if (ratings[e.meta.id] ?? 0) < 0 { continue }
            let weight = pow(0.92, Double(i)) * (0.5 + min(1, max(0, e.progress)))
            for g in e.meta.genres { w[g, default: 0] += weight }
        }
        for m in myList { for g in m.genres { w[g, default: 0] += 0.6 } }
        for m in rated {
            guard let r = ratings[m.id] else { continue }
            for g in m.genres { w[g, default: 0] += r > 0 ? 1.5 : -1.0 }
        }
        let disliked = Set(ratings.filter { $0.value < 0 }.keys)
        return TasteProfile(genreWeights: w.filter { $0.value > 0 }, seen: Set(history.map(\.meta.id)).union(disliked))
    }
}

/** A recommendation row for Home. */
public struct SuggestionRow: Sendable {
    public var key: String
    public var title: String
    public var items: [Meta]
    /** Lower comes first on Home. */
    public var priority: Int
    public var match: [String: Int] = [:]
    public var subtitles: [String: String] = [:]
    public var landscape = false
}

@MainActor
public final class Recommender {
    private let addons: AddonRepository
    private var cache: [String: [Meta]] = [:]

    private static let defaultSpotlight = [
        "Action", "Comedy", "Drama", "Thriller", "Sci-Fi", "Animation", "Horror",
        "Romance", "Crime", "Adventure", "Fantasy", "Mystery", "Documentary", "Family",
    ]

    public init(addons: AddonRepository) { self.addons = addons }

    /** Local calendar day number; changes at midnight so daily rows rotate. */
    public nonisolated static func daySeed() -> Int64 {
        let now = Date()
        return Int64((now.timeIntervalSince1970 + Double(TimeZone.current.secondsFromGMT(for: now))) / 86_400)
    }

    private static func dateString(daysAgo: Int) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date().addingTimeInterval(-Double(daysAgo) * 86_400))
    }

    /** Several pages of a Cinemeta catalog, cached for the session. */
    private func pages(_ type: String, _ catalog: String, _ extra: [String: String], _ count: Int, startSkip: Int = 0) async -> [Meta] {
        let key = "\(type)/\(catalog)/\(extra.sorted { $0.key < $1.key })/\(count)/\(startSkip)"
        if let c = cache[key] { return c }
        guard let cinemeta = addons.cinemeta else { return [] }
        var out: [Meta] = []
        var skip = startSkip
        for _ in 0..<count {
            var e = extra
            if skip > 0 { e["skip"] = String(skip) }
            let page = (try? await addons.catalog(cinemeta, type: type, id: catalog, extra: e)) ?? []
            if page.isEmpty { break }
            out += page
            skip += page.count
        }
        let result = out.distinct(by: \.id)
        if !result.isEmpty { cache[key] = result }
        return result
    }

    /** Popular + top-rated titles for a genre: up to ~200 candidates. */
    public func pool(_ type: String, _ genre: String?, pageCount: Int = 2) async -> [Meta] {
        let extra = genre.map { ["genre": $0] } ?? [:]
        async let a = pages(type, "top", extra, pageCount)
        async let b = pages(type, "imdbRating", extra, pageCount)
        return (await a + b).distinct(by: \.id)
    }

    public nonisolated static func similarity(_ a: Meta, _ b: Meta) -> Double {
        let ga = Set(a.genres), gb = Set(b.genres)
        let jaccard = ga.isEmpty || gb.isEmpty ? 0 : Double(ga.intersection(gb).count) / Double(ga.union(gb).count)
        let rating = (b.rating ?? 6.0) / 10
        let yearSim: Double = {
            guard let ya = a.year, let yb = b.year else { return 0.5 }
            return min(1, max(0, 1 - Double(abs(ya - yb)) / 30))
        }()
        let people = Set(a.cast.prefix(6) + a.director).intersection(Set(b.cast.prefix(6) + b.director)).count
        return min(1, max(0, 0.5 * jaccard + 0.25 * rating + 0.15 * yearSim + Double(min(people, 2)) * 0.05))
    }

    /** Kitsu (anime) titles for a genre, from the popular and top-rated catalogs. */
    private func animePool(_ genre: String?) async -> [Meta] {
        guard let kitsu = addons.kitsu else { return [] }
        let supported = kitsu.manifest.catalogs.first { $0.id == "kitsu-anime-popular" }?.optionsFor("genre") ?? []
        let extra = genre.flatMap { supported.contains($0) ? ["genre": $0] : nil } ?? [:]
        let key = "kitsu/\(extra.values.joined())"
        if let c = cache[key] { return c }
        async let a = (try? addons.catalog(kitsu, type: "anime", id: "kitsu-anime-popular", extra: extra)) ?? []
        async let b = (try? addons.catalog(kitsu, type: "anime", id: "kitsu-anime-rating", extra: extra)) ?? []
        let result = (await a + b).distinct(by: \.id)
        if !result.isEmpty { cache[key] = result }
        return result
    }

    public func moreLikeThis(_ meta: Meta, exclude: Set<String> = [], limit: Int = 50) async -> [Scored] {
        let genres: [String?] = meta.genres.isEmpty ? [nil] : Array(meta.genres.prefix(3))
        let candidates = await concurrentMap(genres) { g in meta.isAnime ? await self.animePool(g) : await self.pool(meta.type, g) }.flatMap { $0 }
        return candidates.distinct(by: \.id)
            .filter { $0.id != meta.id && !exclude.contains($0.id) }
            .map { Scored(meta: $0, score: Self.similarity(meta, $0)) }
            .stableSorted { $0.score > $1.score }
            .prefix(limit).map { $0 }
    }

    /** Highly rated titles in the same genres that aren't already in [exclude]: a second row for Details. */
    public func genreFavorites(_ meta: Meta, exclude: Set<String>, limit: Int = 40) async -> (String, [Scored])? {
        guard let genre = meta.genres.first, !meta.isAnime else { return nil }
        let items = await pool(meta.type, genre, pageCount: 3)
            .filter { $0.id != meta.id && !exclude.contains($0.id) && ($0.rating ?? 0) >= 6.5 }
            .stableSorted { ($0.rating ?? 0) > ($1.rating ?? 0) }
            .prefix(limit)
            .map { Scored(meta: $0, score: Self.similarity(meta, $0)) }
        return items.isEmpty ? nil : (genre, items)
    }

    /** Best matches, with the long tail reshuffled every day so the row feels fresh. */
    public func topPicks(_ profile: TasteProfile, limit: Int = 40, seed: Int64 = Recommender.daySeed()) async -> [Scored] {
        if profile.isEmpty { return [] }
        let genres = profile.topGenres(4)
        let pairs = ["movie", "series"].flatMap { t in genres.map { (t, $0) } }
        let candidates = await concurrentMap(pairs) { await self.pool($0.0, $0.1) }.flatMap { $0 }
        let ranked = candidates.distinct(by: \.id)
            .filter { !profile.seen.contains($0.id) }
            .map { Scored(meta: $0, score: 0.6 * profile.affinity($0) + 0.4 * (($0.rating ?? 6) / 10)) }
            .stableSorted { $0.score > $1.score }
        var rng = SeededRandom(seed: seed)
        let head = Array(ranked.prefix(8))
        let tail = Array(ranked.dropFirst(8).prefix(140)).shuffled(using: &rng).prefix(limit - head.count)
        return head + tail
    }

    /** Netflix-style "% Match" for any title. */
    public nonisolated static func matchPercent(_ m: Meta, _ profile: TasteProfile) -> Int {
        let r = (m.rating ?? 6.5) / 10
        let x = profile.isEmpty ? r : 0.55 * profile.affinity(m) + 0.45 * r
        return min(99, max(50, Int((50 + x * 49).rounded())))
    }

    /**
     * Home rows that change day by day: personal picks, "because you watched", a genre
     * spotlight, hidden gems, a "best of" year, new releases and new episodes of your shows.
     */
    public func dailyRows(_ profile: TasteProfile, history: [WatchEntry], myList: [Meta], liked: [Meta] = []) async -> [SuggestionRow] {
        let seed = Recommender.daySeed()
        var rnd = SeededRandom(seed: seed)
        guard let cinemeta = addons.cinemeta else { return [] }
        let movieGenres = cinemeta.manifest.catalogs.first { $0.type == "movie" && $0.id == "top" }?.optionsFor("genre") ?? []
        let yearOptions = cinemeta.manifest.catalogs.first { $0.type == "movie" && $0.id == "year" }?.optionsFor("genre") ?? []
        let seen = profile.seen
        func scoredRow(_ key: String, _ title: String, _ priority: Int, _ items: [Scored]) -> SuggestionRow {
            SuggestionRow(key: key, title: title, items: items.map(\.meta), priority: priority,
                          match: Dictionary(items.map { ($0.meta.id, $0.matchPercent) }, uniquingKeysWith: { a, _ in a }))
        }
        func plainRow(_ key: String, _ title: String, _ priority: Int, _ items: [Meta]) -> SuggestionRow {
            SuggestionRow(key: key, title: title, items: items, priority: priority,
                          match: Dictionary(items.map { ($0.id, Self.matchPercent($0, profile)) }, uniquingKeysWith: { a, _ in a }))
        }

        var jobs: [() async -> SuggestionRow?] = []

        // Picked for you today
        jobs.append {
            let picks = await self.topPicks(profile, seed: seed)
            return picks.isEmpty ? nil : scoredRow("picks", "We think you might like…", 2, picks)
        }

        // Because you watched … (two recent titles, rotating daily)
        let recent = Array(history.map(\.meta).distinct(by: \.id).prefix(12))
        var shuffleRng = SeededRandom(seed: seed)
        let becauseOf = Array(recent.shuffled(using: &shuffleRng).prefix(2))
        for (i, src) in becauseOf.enumerated() {
            jobs.append {
                let like = await self.moreLikeThis(src, exclude: seen, limit: 40)
                return like.isEmpty ? nil : scoredRow("because-\(src.id)", "Because you watched \(src.title)", i == 0 ? 5 : 9, like)
            }
        }

        // Because you liked … (titles you gave a thumbs up), rotating daily
        var likeRng = SeededRandom(seed: seed + 2)
        let likedChoices = liked.filter { l in !becauseOf.contains { $0.id == l.id } }
        if let src = likedChoices.shuffled(using: &likeRng).first {
            jobs.append {
                let like = await self.moreLikeThis(src, exclude: seen, limit: 40)
                return like.isEmpty ? nil : scoredRow("liked-\(src.id)", "Because you liked \(src.title)", 8, like)
            }
        }

        // Because you added … to My List
        var listRng = SeededRandom(seed: seed + 1)
        if let src = myList.filter({ m in !becauseOf.contains { $0.id == m.id } }).shuffled(using: &listRng).first {
            jobs.append {
                let like = await self.moreLikeThis(src, exclude: seen.union(myList.map(\.id)), limit: 40)
                return like.isEmpty ? nil : scoredRow("mylist-\(src.id)", "Because you saved \(src.title)", 10, like)
            }
        }

        // Today's genre spotlight, weighted toward your taste
        let spotlightChoices = (profile.topGenres(6) + Self.defaultSpotlight).distinct().filter { movieGenres.isEmpty || movieGenres.contains($0) }
        if !spotlightChoices.isEmpty {
            let spotlight = spotlightChoices[Int(rnd.next() % UInt64(spotlightChoices.count))]
            jobs.append {
                let items = (await self.pool("movie", spotlight) + self.pool("series", spotlight)).distinct(by: \.id)
                    .filter { !seen.contains($0.id) }
                    .map { m -> Scored in
                        var r = SeededRandom(seed: seed &+ stableHash(m.id))
                        let jitter = Double(r.next() % 10_000) / 10_000
                        return Scored(meta: m, score: 0.5 * ((m.rating ?? 6) / 10) + 0.3 * profile.affinity(m) + 0.2 * jitter)
                    }
                    .stableSorted { $0.score > $1.score }
                    .prefix(40)
                return items.isEmpty ? nil : scoredRow("spotlight", "Today's Spotlight: \(spotlight)", 6, Array(items))
            }
        }

        // Hidden gems: well rated but outside the most popular titles
        let gemChoices = profile.topGenres(3).isEmpty ? Self.defaultSpotlight : profile.topGenres(3)
        let gemGenre = gemChoices[Int(rnd.next() % UInt64(gemChoices.count))]
        if movieGenres.isEmpty || movieGenres.contains(gemGenre) {
            jobs.append {
                let popular = Set(await self.pages("movie", "top", ["genre": gemGenre], 2).map(\.id))
                var gemRng = SeededRandom(seed: seed + 2)
                let gems = await self.pages("movie", "imdbRating", ["genre": gemGenre], 3, startSkip: 48)
                    .filter { !popular.contains($0.id) && !seen.contains($0.id) && ($0.rating ?? 0) >= 7.2 }
                    .shuffled(using: &gemRng)
                    .prefix(30)
                return gems.isEmpty ? nil : plainRow("gems", "Hidden Gems: \(gemGenre)", 12, Array(gems))
            }
        }

        // Best of a different year every day
        let thisYear = Int(Self.dateString(daysAgo: 0).prefix(4))!
        let years = yearOptions.compactMap(Int.init).filter { (1975...(thisYear - 2)).contains($0) }
        if !years.isEmpty {
            let year = years[Int(rnd.next() % UInt64(years.count))]
            jobs.append {
                let best = await self.pages("movie", "year", ["genre": String(year)], 2)
                    .filter { ($0.rating ?? 0) >= 6.3 }
                    .stableSorted { ($0.rating ?? 0) > ($1.rating ?? 0) }
                    .prefix(30)
                return best.isEmpty ? nil : plainRow("year", "Best of \(year)", 14, Array(best))
            }
        }

        // New this month (movies and series released in the last ~6 weeks)
        jobs.append {
            let cutoff = Self.dateString(daysAgo: 45)
            let today = Self.dateString(daysAgo: 0)
            let fresh = (await self.pages("movie", "year", ["genre": String(thisYear)], 3) + self.pages("series", "year", ["genre": String(thisYear)], 3))
                .filter { m in m.releasedDate.map { $0 >= cutoff && $0 <= today } ?? false }
                .stableSorted { ($0.releasedDate ?? "") > ($1.releasedDate ?? "") }
                .prefix(40)
            return fresh.isEmpty ? nil : plainRow("fresh", "New This Month", 8, Array(fresh))
        }

        // New episodes of series you've watched
        let seriesIds = Array(history.filter { $0.meta.type == "series" && $0.meta.isImdb }.map(\.meta.id).distinct().prefix(25))
        if !seriesIds.isEmpty {
            jobs.append {
                let recentCutoff = Self.dateString(daysAgo: 21)
                let today = Self.dateString(daysAgo: 0)
                let watchedVideos = Set(history.map(\.videoId))
                let metas = (try? await self.addons.catalogDetailed(cinemeta, type: "series", id: "last-videos", extra: ["lastVideosIds": seriesIds.joined(separator: ",")])) ?? []
                let entries: [(Meta, String)] = metas.compactMap { m in
                    guard let latest = m.videos.filter({ v in v.released.map { String($0.prefix(10)) <= today } ?? false })
                        .max(by: { ($0.released ?? "") < ($1.released ?? "") }) else { return nil }
                    if String((latest.released ?? "").prefix(10)) < recentCutoff || watchedVideos.contains(latest.id) { return nil }
                    var mm = m
                    mm.background = latest.thumbnail ?? m.background
                    mm.videos = []
                    return (mm, "New · S\(latest.season ?? 0) E\(latest.episodeNumber)")
                }
                if entries.isEmpty { return nil }
                return SuggestionRow(key: "new-episodes", title: "New Episodes for You", items: entries.map(\.0), priority: 1,
                                     subtitles: Dictionary(entries.map { ($0.0.id, $0.1) }, uniquingKeysWith: { a, _ in a }), landscape: true)
            }
        }

        // Run the jobs concurrently on the main actor (they're network-bound).
        var rows: [Int: SuggestionRow] = [:]
        await withTaskGroup(of: (Int, SuggestionRow?).self) { group in
            for (i, job) in jobs.enumerated() { group.addTask { @MainActor in (i, await job()) } }
            for await (i, row) in group { if let row { rows[i] = row } }
        }
        return rows.sorted { $0.key < $1.key }.map { _, row in
            var r = row
            r.items = r.items.distinct(by: \.id)
            return r
        }.filter { !$0.items.isEmpty }
    }
}

/** Runs [transform] for every element concurrently on the main actor, keeping the input order. */
@MainActor
func concurrentMap<T, R>(_ items: [T], _ transform: @escaping @MainActor (T) async -> R) async -> [R] {
    await withTaskGroup(of: (Int, R).self) { group in
        for (i, item) in items.enumerated() { group.addTask { @MainActor in (i, await transform(item)) } }
        var out: [(Int, R)] = []
        for await r in group { out.append(r) }
        return out.sorted { $0.0 < $1.0 }.map(\.1)
    }
}
