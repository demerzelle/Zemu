import SwiftUI
import ZemuCore

enum RowStyle {
    case poster, landscape
    /** Streaming service logos. */
    case services
    /** Studio / network logos. */
    case studios
}

struct HomeRow: Identifiable {
    let key: String
    let title: String
    let items: [Meta]
    var priority = 50
    var style = RowStyle.poster
    var subtitles: [String: String] = [:]
    var progress: [String: Double] = [:]
    var match: [String: Int] = [:]
    /** Per-title poster badge text, e.g. "3 NEW"; shown instead of the match percent. */
    var badges: [String: String] = [:]
    var resume: [String: WatchEntry] = [:]
    /** "See all" opens the grid for this streaming service (provider ids) or studio. */
    var service: String?
    var serviceLabel: String?
    var studio: String?
    var id: String { key }

    func with(items: [Meta]) -> HomeRow {
        var r = HomeRow(key: key, title: title, items: items, priority: priority, style: style, subtitles: subtitles, progress: progress,
                        match: match, badges: badges, resume: resume)
        r.service = service; r.serviceLabel = serviceLabel; r.studio = studio
        return r
    }
}

@MainActor @Observable
final class HomeModel {
    @ObservationIgnored private unowned let s: Session
    private var catalogRows: [HomeRow] = []
    private var dailyRows: [HomeRow] = []
    /** Streaming service, studio and user-added rows, per page ("home" here; Movies/Series pages use Browse). */
    private var discoverRows: [String: [HomeRow]] = [:]
    @ObservationIgnored private var discoverLoaded: Set<String> = []
    private(set) var providers: [Provider] = []
    private var studioLogos: [String: String] = [:]

    /**
     * A fresh mix of suggestions for each screensaver run: mostly personal recommendations, the
     * rest from catalogs, minus anything already watched. Falls back to My List before Home loads.
     */
    func screensaverTitles(count: Int = 30) -> [Meta] {
        let daily = dailyRows.flatMap(\.items).filter { !s.store.isWatched($0.id) }.distinct(by: \.id).shuffled()
        let catalogs = catalogRows.flatMap(\.items).filter { !s.store.isWatched($0.id) }.distinct(by: \.id).shuffled()
        let picked = Array((Array(daily.prefix(count * 2 / 3)) + catalogs).distinct(by: \.id).prefix(count))
        return picked.isEmpty ? Array(s.store.myList.shuffled().prefix(count)) : picked
    }
    private(set) var loading = true
    private(set) var error: String?
    @ObservationIgnored private var loadedFor: [String]?
    @ObservationIgnored private var dailyKey = ""
    @ObservationIgnored private var trackers: [AnyObject] = []

    init(_ s: Session) {
        self.s = s
        Task { await load() }
        loadDiscover("home")
        // Reload catalogs when addons are installed or removed.
        trackers.append(Tracker({ [weak s] in s?.addons.addons.map(\.transportUrl) ?? [] }) { [weak self] urls in
            guard let self, self.s.addons.ready, let loaded = self.loadedFor, loaded != urls else { return }
            Task { await self.load() }
            let pages = self.discoverLoaded
            self.discoverLoaded = []
            for p in pages { self.loadDiscover(p) }
        })
        // Daily rows follow history, My List, likes and the date.
        trackers.append(Tracker({ [weak s] in
            guard let s else { return "" }
            return "\(s.store.history.map(\.meta.id).prefix(30))|\(s.store.myList.map(\.id))|\(s.store.ratings.count)|\(Recommender.daySeed())"
        }) { [weak self] key in
            guard let self else { return }
            self.dailyKey = key
            Task {
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard self.dailyKey == key else { return }
                await self.loadDaily()
            }
        })
    }

    var noStreamAddons: Bool { s.addons.ready && !s.addons.hasStreamAddons }

    var rows: [HomeRow] {
        var out: [HomeRow] = []
        let fresh = s.newEpisodes.items
        if !fresh.isEmpty {
            out.append(HomeRow(key: "new-episodes", title: "New Episodes", items: fresh.map(\.meta), priority: -1,
                               badges: Dictionary(fresh.map { ($0.meta.id, $0.badge) }, uniquingKeysWith: { a, _ in a })))
        }
        // Calendar: the next episode of each show you follow, soonest first, with its day.
        let upcoming = s.newEpisodes.upcoming
        if !upcoming.isEmpty {
            out.append(HomeRow(key: "coming-up", title: "Coming Up", items: upcoming.map(\.meta), priority: -1,
                               badges: Dictionary(upcoming.map { ($0.meta.id, $0.badge) }, uniquingKeysWith: { a, _ in a })))
        }
        let inProgress = s.inProgress
        if !inProgress.isEmpty {
            out.append(HomeRow(
                key: "continue", title: "Continue Watching", items: inProgress.map(\.meta), priority: 0, style: .landscape,
                subtitles: Dictionary(inProgress.compactMap { e in e.label.map { (e.meta.id, $0) } }, uniquingKeysWith: { a, _ in a }),
                progress: Dictionary(inProgress.map { ($0.meta.id, $0.progress) }, uniquingKeysWith: { a, _ in a }),
                resume: Dictionary(inProgress.map { ($0.meta.id, $0) }, uniquingKeysWith: { a, _ in a })
            ))
        }
        let myList = s.store.myList
        if !myList.isEmpty { out.append(HomeRow(key: "mylist", title: "My List", items: myList, priority: 7)) }
        let recent = s.store.history.sorted { $0.updatedAt > $1.updatedAt }.distinct(by: \.meta.id)
        let movies = recent.filter { $0.meta.type == "movie" }.map(\.meta).prefix(30)
        if !movies.isEmpty { out.append(HomeRow(key: "recent-movies", title: "Recently Watched Movies", items: Array(movies), priority: 6)) }
        let series = recent.filter { $0.meta.type == "series" }.prefix(30)
        if !series.isEmpty {
            out.append(HomeRow(key: "recent-series", title: "Recently Watched Series", items: series.map(\.meta), priority: 6, style: .landscape,
                               subtitles: Dictionary(series.compactMap { e in e.label.map { (e.meta.id, $0) } }, uniquingKeysWith: { a, _ in a })))
        }
        out += hidingWatched(dailyRows + catalogRows + (discoverRows["home"] ?? []))
        out += logoRows("home")
        return out.filter { !s.store.hiddenRows(page: "home").contains($0.key) }.stableSortedByPriority()
    }

    /** Optionally keeps watched titles out of suggestion and category rows. */
    private func hidingWatched(_ rows: [HomeRow]) -> [HomeRow] {
        guard s.settings.hideWatchedInRows else { return rows }
        return rows.compactMap { r in
            let items = r.items.filter { !s.store.isWatched($0.id) }
            return items.isEmpty ? nil : r.with(items: items)
        }
    }

    /** "Surprise me": a random unwatched title from your best-matching suggestions. */
    func surprise() -> Meta? {
        let seen = Set(s.store.history.map(\.meta.id))
        let pool = (dailyRows + catalogRows).flatMap(\.items)
            .filter { !s.store.isWatched($0.id) && !seen.contains($0.id) && ["movie", "series"].contains($0.type) && s.kids.knownAllowed($0) == true }
            .distinct(by: \.id)
        let profile = s.tasteProfile()
        return pool.sorted { Recommender.matchPercent($0, profile) > Recommender.matchPercent($1, profile) }.prefix(30).randomElement()
    }

    /** "Streaming Services" (your services first) and, on Movies/Series, "Studios" / "Networks". */
    private func logoRows(_ page: String) -> [HomeRow] {
        guard page != "anime", s.tmdb.enabled else { return [] }
        var out: [HomeRow] = []
        let mine = s.settings.myServices.map { id, name in Provider(ids: id, label: name, logo: providers.first { $0.ids == id }?.logo) }
        let all = providers.isEmpty ? StreamingService.all : providers
        let list = (mine + all).distinct(by: \.ids).prefix(24)
        out.append(HomeRow(key: "services", title: "Streaming Services", items: list.map { Meta(id: "service:\($0.ids)", type: page == "series" ? "series" : "movie", name: $0.label, poster: $0.logo) },
                           priority: 1, style: .services))
        if page == "movie" || page == "series" {
            out.append(HomeRow(key: "studios", title: page == "series" ? "Networks" : "Studios",
                               items: Studio.forType(page).map { Meta(id: "studio:\($0.key)", type: page, name: $0.label, poster: studioLogos[$0.key]) },
                               priority: 2, style: .studios))
        }
        return out
    }

    /**
     * Loads a page's rotating streaming service, studio and genre rows (a new mix each launch) and
     * the rows the user added there. Each row appears as soon as it loads.
     */
    func loadDiscover(_ page: String, force: Bool = false) {
        guard force || !discoverLoaded.contains(page) else { return }
        discoverLoaded.insert(page)
        Task {
            await s.addons.waitReady()
            if providers.isEmpty { providers = await s.tmdb.allProviders(region: DiscoverParams.region) }
            if page == "movie" || page == "series" {
                for st in Studio.forType(page) where studioLogos[st.key] == nil {
                    if let l = await s.tmdb.studioLogo(st) { studioLogos[st.key] = l }
                }
            }
        }
        Task {
            await s.addons.waitReady()
            let mine = s.settings.myServices.map { Provider(ids: $0.key, label: $0.value) }
            let specs = (s.tmdb.enabled ? Categories.tmdbRows(page: page, seed: Int64.random(in: .min ... .max), taste: s.tasteProfile().topGenres(4), mine: mine) : [])
                + s.store.addedRows(page: page)
            discoverRows[page] = []
            await withTaskGroup(of: Void.self) { g in
                for (kind, label) in Top10.kinds(page) {
                    g.addTask { @MainActor in
                        let items = await Top10.load(kind)
                        guard !items.isEmpty else { return }
                        let key = "top10-\(kind)"
                        self.discoverRows[page, default: []].removeAll { $0.key == key }
                        self.discoverRows[page, default: []].append(HomeRow(key: key, title: "Top 10 \(label) Today", items: items, priority: 0))
                    }
                }
                for spec in specs.distinct(by: \.key) {
                    g.addTask { @MainActor in
                        let items = await self.fetch(spec)
                        guard !items.isEmpty else { return }
                        self.discoverRows[page, default: []].removeAll { $0.key == spec.key }
                        self.discoverRows[page, default: []].append(self.row(spec, items))
                    }
                }
            }
        }
    }

    /** Adds a row of your own choosing; it stays on this page and loads now. */
    func addRow(_ spec: RowSpec, page: String) {
        s.store.addRow(spec, page: page)
        Task {
            let items = await fetch(spec)
            guard !items.isEmpty else { return }
            discoverRows[page, default: []].removeAll { $0.key == spec.key }
            discoverRows[page, default: []].append(row(spec, items))
        }
    }

    private func row(_ spec: RowSpec, _ items: [Meta]) -> HomeRow {
        var r = HomeRow(key: spec.key, title: spec.title, items: items, priority: spec.priority)
        r.service = spec.service; r.serviceLabel = spec.serviceLabel; r.studio = spec.studio
        return r
    }

    private func fetch(_ spec: RowSpec) async -> [Meta] {
        if let t = spec.tmdb { return Array(((try? await s.tmdb.discover(type: spec.type, params: t)) ?? []).prefix(spec.limit)) }
        guard let id = spec.addonId, let cat = spec.catalogId, let addon = s.addons.addons.first(where: { $0.manifest.id == id }) else { return [] }
        return Array(((try? await s.addons.catalog(addon, type: spec.catalogType ?? spec.type, id: cat, extra: spec.extra)) ?? []).prefix(spec.limit))
    }

    /** Rows that can be added to a page: services, studios, genres and any addon catalog. */
    func addableRows(_ page: String) -> [RowSpec] {
        var out: [RowSpec] = []
        let types = page == "home" ? ["movie", "series"] : page == "anime" ? [] : [page]
        let noun = { (t: String) in t == "series" ? "Series" : "Movies" }
        if s.tmdb.enabled {
            for t in types {
                let services = (s.settings.myServices.map { Provider(ids: $0.key, label: $0.value) } + StreamingService.all).distinct(by: \.ids)
                for sv in services {
                    out.append(RowSpec(key: "\(t)/added-svc-\(sv.ids)", title: "\(noun(t)) on \(sv.label)", priority: 5, type: t,
                                       tmdb: DiscoverParams.service(sv.ids).merging(DiscoverParams.popular()) { a, _ in a }, service: sv.ids, serviceLabel: sv.label))
                }
                for st in Studio.forType(t) {
                    out.append(RowSpec(key: "\(t)/added-studio-\(st.key)", title: "From \(st.label)", priority: 5, type: t,
                                       tmdb: [st.param.0: st.param.1].merging(DiscoverParams.popular()) { a, _ in a }, studio: st.key))
                }
            }
        }
        if let cinemeta = s.addons.cinemeta {
            for t in types {
                for g in cinemeta.manifest.catalogs.first(where: { $0.type == t && $0.id == "top" })?.optionsFor("genre") ?? [] {
                    out.append(RowSpec(key: "\(t)/added-genre-\(g)", title: "\(g) \(noun(t))", priority: 5, type: t, addonId: cinemeta.manifest.id,
                                       catalogType: t, catalogId: "top", extra: ["genre": g]))
                }
            }
        }
        for a in s.addons.addons {
            for c in a.manifest.catalogs where c.requiredExtras.isEmpty && (page == "home" || c.type == page || (page == "anime" && a.manifest.id == AddonRepository.kitsuId)) {
                out.append(RowSpec(key: "\(a.manifest.id)/added-\(c.type)/\(c.id)", title: "\(c.name ?? c.id) · \(a.manifest.name)", priority: 5,
                                   type: c.type == "anime" ? "series" : c.type, addonId: a.manifest.id, catalogType: c.type, catalogId: c.id))
            }
        }
        return out.distinct(by: \.key)
    }

    func retry() {
        s.streams.invalidate()
        Task { await load() }
    }

    private func load() async {
        loading = true
        error = nil
        await s.addons.waitReady()
        await s.addons.ensureDefaults()
        loadedFor = s.addons.addons.map(\.transportUrl)
        let specs = catalogSpecs(s.addons.addons)
        let addons = s.addons
        let rows = await concurrentMapUI(specs) { spec -> HomeRow in
            let items = (try? await addons.catalog(spec.addon, type: spec.catalog.type, id: spec.catalog.id, extra: spec.extra)) ?? []
            return HomeRow(key: "\(spec.addon.manifest.id)/\(spec.catalog.type)/\(spec.catalog.id)/\(spec.extra.values.joined())",
                           title: spec.title, items: items, priority: spec.priority)
        }.filter { !$0.items.isEmpty }
        catalogRows = rows
        loading = false
        error = rows.isEmpty ? "Couldn't load any catalogs. Check your connection and installed addons." : nil
    }

    private func loadDaily() async {
        await s.addons.waitReady()
        let rows = await s.recommender.dailyRows(s.tasteProfile(), history: s.store.history, myList: s.store.myList)
        dailyRows = rows.map { r in
            HomeRow(key: r.key, title: r.title, items: r.items, priority: r.priority, style: r.landscape ? .landscape : .poster,
                    subtitles: r.subtitles, match: r.match)
        }
    }

    private struct CatalogSpec {
        let addon: Addon
        let catalog: CatalogDef
        let title: String
        let priority: Int
        var extra: [String: String] = [:]
    }

    private func catalogSpecs(_ addons: [Addon]) -> [CatalogSpec] {
        var specs: [CatalogSpec] = []
        let cinemeta = addons.first { $0.manifest.id == AddonRepository.cinemetaId }
        if let cinemeta {
            func cat(_ type: String, _ id: String) -> CatalogDef? { cinemeta.manifest.catalogs.first { $0.type == type && $0.id == id } }
            if let c = cat("movie", "top") { specs.append(CatalogSpec(addon: cinemeta, catalog: c, title: "Popular Movies", priority: 3)) }
            if let c = cat("series", "top") { specs.append(CatalogSpec(addon: cinemeta, catalog: c, title: "Popular Series", priority: 4)) }
            if let c = cat("movie", "year"), let y = c.optionsFor("genre").first { specs.append(CatalogSpec(addon: cinemeta, catalog: c, title: "New Movies · \(y)", priority: 11, extra: ["genre": y])) }
            if let c = cat("movie", "imdbRating") { specs.append(CatalogSpec(addon: cinemeta, catalog: c, title: "Top Rated Movies", priority: 13)) }
            if let c = cat("series", "year"), let y = c.optionsFor("genre").first { specs.append(CatalogSpec(addon: cinemeta, catalog: c, title: "New Series · \(y)", priority: 15, extra: ["genre": y])) }
            if let c = cat("series", "imdbRating") { specs.append(CatalogSpec(addon: cinemeta, catalog: c, title: "Top Rated Series", priority: 16)) }
            for (i, g) in ["Action", "Comedy", "Sci-Fi", "Thriller", "Animation", "Horror", "Romance", "Documentary"].enumerated() {
                if let c = cat("movie", "top"), c.optionsFor("genre").contains(g) { specs.append(CatalogSpec(addon: cinemeta, catalog: c, title: "\(g) Movies", priority: 20 + i, extra: ["genre": g])) }
            }
            for (i, g) in ["Drama", "Crime", "Comedy"].enumerated() {
                if let c = cat("series", "top"), c.optionsFor("genre").contains(g) { specs.append(CatalogSpec(addon: cinemeta, catalog: c, title: "\(g) Series", priority: 30 + i, extra: ["genre": g])) }
            }
        }
        // Catalogs from any other installed addon that don't need extra input.
        var p = 40
        for addon in addons where addon.manifest.id != cinemeta?.manifest.id {
            for c in addon.manifest.catalogs.filter({ $0.requiredExtras.isEmpty && ["movie", "series"].contains($0.type) }).prefix(4) {
                specs.append(CatalogSpec(addon: addon, catalog: c, title: "\(c.name ?? c.id) · \(addon.manifest.name)", priority: p))
                p += 1
            }
        }
        return specs
    }
}

extension Array where Element == HomeRow {
    func stableSortedByPriority() -> [HomeRow] {
        enumerated().sorted { ($0.element.priority, $0.offset) < ($1.element.priority, $1.offset) }.map(\.element)
    }
}

/** Concurrent map on the main actor (network-bound work), keeping order. */
@MainActor
func concurrentMapUI<T, R>(_ items: [T], _ transform: @escaping @MainActor (T) async -> R) async -> [R] {
    await withTaskGroup(of: (Int, R).self) { group in
        for (i, item) in items.enumerated() { group.addTask { @MainActor in (i, await transform(item)) } }
        var out: [(Int, R)] = []
        for await r in group { out.append(r) }
        return out.sorted { $0.0 < $1.0 }.map(\.1)
    }
}

struct HomeView: View {
    var app = AppModel.shared
    @State private var hero: Meta?
    @State private var hovered: Meta?

    var body: some View {
        let model = app.session.home
        let rows = model.rows
        let settings = app.settings
        GeometryReader { geo in
        let heroH = min(360, max(150, geo.size.height * 0.42))
        ZStack(alignment: .top) {
            P.background
            Backdrop(meta: hero, trailerAfter: settings.heroTrailers ? 3.5 : nil, trailerSound: settings.heroTrailerSound)
                .frame(height: heroH + 260)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HeroInfo(meta: hero, matchPercent: hero.map(app.session.matchPercent), compact: heroH < 280 || geo.size.width < 700)
                        .frame(height: heroH, alignment: .bottom)
                        .padding(.bottom, 8)
                    if model.noStreamAddons {
                        HStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.cached)
                            Text("No stream addon installed yet. Link your debrid account or add a debrid-enabled addon (AIOStreams, Torrentio, Comet, MediaFusion…) to watch.")
                                .foregroundStyle(Palette.cached).font(.z(size: 13))
                            ZButton(title: "Set up", small: true) { app.go(.addons) }
                        }
                        .padding(.horizontal, 48)
                    }
                    if rows.isEmpty && model.loading {
                        Text("Loading catalogs…").foregroundStyle(Palette.textSecondary).padding(.horizontal, 48)
                    } else if rows.isEmpty, let e = model.error {
                        CenteredMessage(title: "Nothing to show", message: e) { ZButton(title: "Retry", primary: true) { model.retry() } }
                    }
                    ForEach(rows) { row in
                        MediaRow(title: row.title, items: row.items, spacing: row.style == .landscape ? 16 : 14) { m in
                            switch row.style {
                            case .landscape:
                                LandscapeCard(meta: m, subtitle: row.subtitles[m.id], progress: row.progress[m.id], onHover: hover, resume: row.resume[m.id])
                            case .poster:
                                PosterCard(meta: m, badge: row.badges[m.id] ?? row.match[m.id].map { "\($0)%" }, onHover: hover)
                            case .services, .studios:
                                LogoCard(meta: m)
                            }
                        }
                    }
                }
                .padding(.bottom, 48)
            }
        }
        }
        .onChange(of: rows.first?.items.first?.id) { _, _ in if hero == nil { hero = app.session.kids.safe(rows.first?.items ?? []).first } }
        .onAppear { if hero == nil { hero = app.session.kids.safe(rows.first?.items ?? []).first } }
        .task(id: hovered?.id) {
            // Debounce so sweeping the mouse across a row doesn't thrash the backdrop.
            guard let h = hovered else { return }
            try? await Task.sleep(nanoseconds: 260_000_000)
            if !Task.isCancelled { hero = h }
        }
    }

    private func hover(_ m: Meta) { hovered = m }
}
