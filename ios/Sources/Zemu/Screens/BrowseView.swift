import SwiftUI
import ZemuCore

/** A catalog the page can show, e.g. Cinemeta "top" or Kitsu "kitsu-anime-airing". */
struct BrowseCatalog: Hashable {
    let id: String
    let label: String
    var paged = true
    var genres = true
}

enum BrowseSort: String, CaseIterable {
    case DEFAULT, RATING, NEWEST, OLDEST, MATCH
    var label: String {
        switch self { case .DEFAULT: "Default"; case .RATING: "Highest rated"; case .NEWEST: "Newest"; case .OLDEST: "Oldest"; case .MATCH: "Best match for you" }
    }
}

/** Anime pages split one mixed catalog into series and movies. */
enum AnimeSection: String, CaseIterable {
    case SERIES, MOVIES
    var label: String { self == .SERIES ? "Anime Series" : "Anime Movies" }
    var metaType: String { self == .SERIES ? "series" : "movie" }
}

struct BrowseFilters: Equatable {
    var catalog = ""
    var section = AnimeSection.SERIES
    var genre: String?
    var minRating: Double?
    /** Decade start year, e.g. 1990. -1 = before 1970. */
    var decade: Int?
    var sort = BrowseSort.DEFAULT
}

/** Backs the Movies, Series and Anime pages. [type] is "movie", "series" or "anime". */
@MainActor @Observable
final class BrowseModel {
    let type: String
    var isAnime: Bool { type == "anime" }
    @ObservationIgnored private unowned let s: Session

    private var raw: [Meta] = []
    private(set) var filters = BrowseFilters()
    private(set) var loading = false
    private(set) var endReached = false
    private(set) var error: String?
    private(set) var catalogs: [BrowseCatalog] = []
    private(set) var genres: [String] = []
    @ObservationIgnored private var addon: Addon?
    @ObservationIgnored private var job: Task<Void, Never>?
    @ObservationIgnored private var pages = 0
    private static let maxPages = 12

    init(_ s: Session, type: String) {
        self.s = s
        self.type = type
        Task {
            loading = true
            await s.addons.waitReady()
            if isAnime { await setupAnime() } else { setupCatalogs() }
            reload()
        }
    }

    var fetched: Int { raw.count }

    var items: [Meta] {
        let f = filters
        var list = raw
            .filter { !isAnime || $0.type == f.section.metaType }
            .filter { f.minRating == nil || ($0.rating ?? 0) >= f.minRating! }
            .filter { x in
                guard let d = f.decade else { return true }
                guard let y = x.year else { return false }
                return d == -1 ? y < 1970 : (d..<(d + 10)).contains(y)
            }
        switch f.sort {
        case .DEFAULT: break
        case .RATING: list = list.stableSorted { ($0.rating ?? 0) > ($1.rating ?? 0) }
        case .NEWEST: list = list.stableSorted { ($0.year ?? 0) > ($1.year ?? 0) }
        case .OLDEST: list = list.stableSorted { ($0.year ?? .max) < ($1.year ?? .max) }
        case .MATCH:
            let profile = s.tasteProfile()
            list = list.stableSorted { Recommender.matchPercent($0, profile) > Recommender.matchPercent($1, profile) }
        }
        return list
    }

    private func setupCatalogs() {
        // The preferred provider (Settings → Metadata) wins; otherwise Cinemeta, then any addon with catalogs of this type.
        let preferred = s.settings.metaProvider
        let usable: (Addon) -> Bool = { a in a.manifest.catalogs.contains { $0.type == self.type && $0.requiredExtras.isEmpty } }
        let pick = s.addons.addons.first { $0.manifest.id == preferred && usable($0) } ?? s.addons.cinemeta ?? s.addons.addons.first(where: usable)
        if let pick, pick.manifest.id != AddonRepository.cinemetaId {
            addon = pick
            let defs = pick.manifest.catalogs.filter { $0.type == type && $0.requiredExtras.isEmpty }
            catalogs = defs.map { BrowseCatalog(id: $0.id, label: $0.name ?? $0.id, paged: $0.supportsExtra("skip"), genres: $0.supportsExtra("genre")) }
            genres = defs.first { $0.supportsExtra("genre") }?.optionsFor("genre") ?? []
            filters.catalog = catalogs.first?.id ?? ""
            return
        }
        addon = s.addons.cinemeta
        let defs = s.addons.cinemeta?.manifest.catalogs.filter { $0.type == type } ?? []
        catalogs = [
            defs.first { $0.id == "top" }.map { _ in BrowseCatalog(id: "top", label: "Popular") },
            defs.first { $0.id == "imdbRating" }.map { _ in BrowseCatalog(id: "imdbRating", label: "Top Rated") },
        ].compactMap { $0 }
        genres = defs.first { $0.id == "top" }?.optionsFor("genre") ?? []
        filters.catalog = catalogs.first?.id ?? ""
    }

    private func setupAnime() async {
        guard let kitsu = await s.addons.ensureKitsu() else {
            error = "Couldn't install the Anime Kitsu addon. Check your connection, or install it from Addons."
            return
        }
        addon = kitsu
        let defs = kitsu.manifest.catalogs.filter { $0.requiredExtras.isEmpty }
        let labels = ["kitsu-anime-trending": "Trending", "kitsu-anime-airing": "Airing Now", "kitsu-anime-popular": "Most Popular", "kitsu-anime-rating": "Top Rated"]
        catalogs = defs.map { d in
            BrowseCatalog(id: d.id, label: labels[d.id] ?? (d.name?.removingPrefix("Kitsu ") ?? d.id), paged: d.supportsExtra("skip"), genres: d.supportsExtra("genre"))
        }
        genres = defs.first { $0.supportsExtra("genre") }?.optionsFor("genre") ?? []
        filters.catalog = defaultAnimeCatalog(filters.section)
    }

    /** Trending isn't paged and holds few movies, so movies start on Most Popular. */
    private func defaultAnimeCatalog(_ section: AnimeSection) -> String {
        let ids = catalogs.map(\.id)
        return section == .MOVIES ? (ids.first { $0.contains("popular") } ?? ids.first ?? "") : (ids.first ?? "")
    }

    func setSection(_ section: AnimeSection) {
        setFilters { $0.section = section; $0.catalog = self.defaultAnimeCatalog(section) }
    }

    func setFilters(_ transform: (inout BrowseFilters) -> Void) {
        let old = filters
        var next = old
        transform(&next)
        // Catalogs without genre support (Kitsu Trending) can't filter by genre.
        if catalogs.first(where: { $0.id == next.catalog })?.genres == false { next.genre = nil }
        filters = next
        if old.catalog != next.catalog || old.genre != next.genre { reload() }
    }

    private func reload() {
        job?.cancel()
        raw = []
        pages = 0
        endReached = false
        error = nil
        loadMore(force: true)
    }

    func loadMore(force: Bool = false) {
        if !force && (loading || endReached) { return }
        guard let source = addon else {
            if !isAnime { error = "No catalog provider is installed. Add Cinemeta or another metadata addon in Addons." }
            loading = false
            return
        }
        let f = filters
        guard let cat = catalogs.first(where: { $0.id == f.catalog }) else { loading = false; return }
        if !force && !cat.paged { return }
        let catalogType = isAnime ? "anime" : type
        job = Task {
            loading = true
            var extra: [String: String] = [:]
            if cat.genres, let g = f.genre { extra["genre"] = g }
            // Kitsu pages are addressed in steps of 50 (it rounds other values), Cinemeta by item count.
            let skip = isAnime ? pages * 50 : raw.count
            if skip > 0 { extra["skip"] = String(skip) }
            do {
                let items = try await s.addons.catalog(source, type: catalogType, id: cat.id, extra: extra)
                if Task.isCancelled { return }
                let known = Set(raw.map(\.id))
                let fresh = items.filter { !known.contains($0.id) }
                raw += fresh
                pages += 1
                if fresh.isEmpty || !cat.paged || pages >= Self.maxPages { endReached = true }
            } catch {
                if !Task.isCancelled { self.error = "Couldn't load: \(error.localizedDescription)" }
            }
            loading = false
            // Anime movies are sparse in mixed catalogs, so keep paging until the grid has enough.
            if !endReached && error == nil && items.count < 24 && !raw.isEmpty { loadMore() }
        }
    }
}

private let ratingOptions: [Double?] = [nil, 6.0, 7.0, 7.5, 8.0]
private let decadeOptions: [Int?] = [nil, 2020, 2010, 2000, 1990, 1980, 1970, -1]
private func decadeLabel(_ d: Int?) -> String { d == nil ? "Any" : d == -1 ? "Before 1970" : "\(d!)s" }
private func ratingLabel(_ r: Double?) -> String { r.map { ($0.truncatingRemainder(dividingBy: 1) == 0 ? String(Int($0)) : String($0)) + "+" } ?? "Any" }

/** Movies, Series and Anime pages: hero for the hovered title, filter chips, then a poster grid. */
struct BrowseView: View {
    let type: String
    var app = AppModel.shared
    @State private var hero: Meta?
    @State private var hovered: Meta?

    var body: some View {
        let vm = app.session.browseModel(type)
        let items = vm.items
        let f = vm.filters
        let settings = app.settings
        let title = type == "series" ? "Series" : type == "anime" ? "Anime" : "Movies"
        let genreAllowed = vm.catalogs.first { $0.id == f.catalog }?.genres != false
        let newEpisodes = app.session.newEpisodes.items.filter { type == "series" ? !$0.meta.isAnime : type == "anime" ? $0.meta.isAnime : false }

        GeometryReader { geo in
        let heroH = geo.size.height < 560 ? 0 : min(300, geo.size.height * 0.34)
        ZStack(alignment: .top) {
            P.background
            Backdrop(meta: hero, trailerAfter: nil)
                .frame(height: heroH + 220)
            VStack(alignment: .leading, spacing: 0) {
                if heroH > 0 {
                    HeroInfo(meta: hero, matchPercent: hero.map(app.session.matchPercent), compact: heroH < 250 || geo.size.width < 700)
                        .frame(height: heroH, alignment: .bottom)
                } else {
                    Spacer().frame(height: 36)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Text(title).font(.system(size: 22, weight: .black)).padding(.trailing, 6)
                        if vm.isAnime {
                            ForEach(AnimeSection.allCases, id: \.self) { s in Chip(title: s.label, selected: f.section == s) { vm.setSection(s) } }
                            MenuChip(title: vm.catalogs.first { $0.id == f.catalog }?.label ?? "Catalog", heading: "Catalog") {
                                choiceItems(vm.catalogs.map { ($0.id, $0.label) }, current: f.catalog) { id in vm.setFilters { $0.catalog = id } }
                            }
                        } else {
                            ForEach(vm.catalogs, id: \.id) { c in Chip(title: c.label, selected: f.catalog == c.id) { vm.setFilters { $0.catalog = c.id } } }
                        }
                        if genreAllowed && !vm.genres.isEmpty {
                            MenuChip(title: "Genre: \(f.genre ?? "All")", selected: f.genre != nil, heading: "Genre") {
                                choiceItems([(String?.none, "All genres")] + vm.genres.map { (Optional($0), $0) }, current: f.genre) { g in vm.setFilters { $0.genre = g } }
                            }
                        }
                        MenuChip(title: "Rating: \(ratingLabel(f.minRating))", selected: f.minRating != nil, heading: "Minimum rating") {
                            choiceItems(ratingOptions.map { ($0, ratingLabel($0)) }, current: f.minRating) { r in vm.setFilters { $0.minRating = r } }
                        }
                        MenuChip(title: "Decade: \(decadeLabel(f.decade))", selected: f.decade != nil, heading: "Decade") {
                            choiceItems(decadeOptions.map { ($0, decadeLabel($0)) }, current: f.decade) { d in vm.setFilters { $0.decade = d } }
                        }
                        MenuChip(title: "Sort: \(f.sort.label)", selected: f.sort != .DEFAULT, heading: "Sort") {
                            choiceItems(BrowseSort.allCases.map { ($0, $0.label) }, current: f.sort) { o in vm.setFilters { $0.sort = o } }
                        }
                        Text(vm.loading ? "loading…" : "\(items.count) titles").font(.system(size: 12)).foregroundStyle(Palette.textMuted).padding(.leading, 6)
                    }
                    .padding(.horizontal, 48).padding(.vertical, 12)
                }
                if let e = vm.error, items.isEmpty {
                    CenteredMessage("Couldn't load titles", e)
                } else if items.isEmpty && !vm.loading && vm.endReached {
                    CenteredMessage("Nothing matches", "No titles match these filters. Try widening them.")
                } else if items.isEmpty {
                    CenteredMessage("Loading…")
                } else {
                    PosterGrid(items: items, onNearEnd: { vm.loadMore() }, onHover: { hovered = $0 }) {
                        if !newEpisodes.isEmpty {
                            MediaRow(title: "New Episodes", items: newEpisodes.map(\.meta)) { m in
                                PosterCard(meta: m, badge: newEpisodes.first { $0.meta.id == m.id }?.badge, onHover: { hovered = $0 })
                            }
                            .padding(.horizontal, -48)
                            .padding(.horizontal, 48)
                        }
                    }
                }
            }
        }
        }
        .onChange(of: items.first?.id) { _, _ in if hovered == nil { hero = items.first } }
        .onAppear { if hero == nil { hero = items.first } }
        .task(id: hovered?.id) {
            guard let h = hovered else { return }
            try? await Task.sleep(nanoseconds: 260_000_000)
            if !Task.isCancelled { hero = h }
        }
    }
}
