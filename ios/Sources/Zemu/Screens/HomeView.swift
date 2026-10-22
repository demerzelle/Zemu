import SwiftUI
import ZemuCore

enum RowStyle { case poster, landscape }

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
    var id: String { key }
}

@MainActor @Observable
final class HomeModel {
    @ObservationIgnored private unowned let s: Session
    private var catalogRows: [HomeRow] = []
    private var dailyRows: [HomeRow] = []
    private(set) var loading = true
    private(set) var error: String?
    @ObservationIgnored private var loadedFor: [String]?
    @ObservationIgnored private var dailyKey = ""
    @ObservationIgnored private var trackers: [AnyObject] = []

    init(_ s: Session) {
        self.s = s
        Task { await load() }
        // Reload catalogs when addons are installed or removed.
        trackers.append(Tracker({ [weak s] in s?.addons.addons.map(\.transportUrl) ?? [] }) { [weak self] urls in
            guard let self, self.s.addons.ready, let loaded = self.loadedFor, loaded != urls else { return }
            Task { await self.load() }
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
        out += dailyRows
        out += catalogRows
        return out.stableSortedByPriority()
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
    /** Each row's leftmost title (as scrolled), and the row at the top of the list. */
    @State private var leads: [String: Meta] = [:]
    @State private var topRow: String?

    var body: some View {
        let model = app.session.home
        let rows = model.rows
        GeometryReader { geo in
        // Portrait: the hero stays put and only the rows scroll under it.
        let pinned = geo.size.height > geo.size.width
        let heroH = pinned ? min(360, max(150, geo.size.height * 0.38)) : min(360, max(150, geo.size.height * 0.42))
        ZStack(alignment: .top) {
            P.background
            // No autoplaying hero trailers on iOS: YouTube's mobile embed keeps its pause overlay over the hero.
            Backdrop(meta: hero, trailerAfter: nil)
                .frame(height: heroH + 260)
            if pinned {
                VStack(alignment: .leading, spacing: 0) {
                    heroInfo(heroH, wide: geo.size.width >= 700).padding(.bottom, 8)
                    ScrollView { rowList(model, rows).padding(.top, 6) }
                        .scrollPosition(id: $topRow, anchor: .top)
                        // Posters fade out under the hero instead of being cut off.
                        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.035)], startPoint: .top, endPoint: .bottom))
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        heroInfo(heroH, wide: geo.size.width >= 700).padding(.bottom, 8)
                        rowList(model, rows)
                    }
                }
                .scrollPosition(id: $topRow, anchor: .top)
            }
        }
        }
        .onChange(of: rows.first?.items.first?.id) { _, _ in if hero == nil { hero = rows.first?.items.first } }
        .onAppear { if hero == nil { hero = rows.first?.items.first } }
        // Scrolling down: the hero shows the title at the left of the row now on top.
        .onChange(of: topRow) { _, id in
            if let id, let row = rows.first(where: { $0.id == id }) { hovered = leads[id] ?? row.items.first }
        }
        .task(id: hovered?.id) {
            // Debounce so a fast swipe across a row doesn't thrash the backdrop.
            guard let h = hovered else { return }
            try? await Task.sleep(nanoseconds: 260_000_000)
            if !Task.isCancelled { hero = h }
        }
    }

    private func heroInfo(_ heroH: CGFloat, wide: Bool) -> some View {
        HeroInfo(meta: hero, matchPercent: hero.map(app.session.matchPercent), compact: heroH < 280 || !wide)
            .frame(minHeight: heroH, alignment: .bottom) // grows instead of pushing the logo off the top (short landscape screens)
    }

    private func rowList(_ model: HomeModel, _ rows: [HomeRow]) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            if model.noStreamAddons {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.cached)
                    Text("No stream addon installed yet. Link your debrid account or add a debrid-enabled addon (AIOStreams, Torrentio, Comet, MediaFusion…) to watch.")
                        .foregroundStyle(Palette.cached).font(.system(size: 13))
                    ZButton(title: "Set up", small: true) { app.go(.addons) }
                }
                .padding(.horizontal, pagePad)
            }
            if rows.isEmpty && model.loading {
                Text("Loading catalogs…").foregroundStyle(Palette.textSecondary).padding(.horizontal, pagePad)
            } else if rows.isEmpty, let e = model.error {
                CenteredMessage(title: "Nothing to show", message: e) { ZButton(title: "Retry", primary: true) { model.retry() } }
            }
            ForEach(rows) { row in
                MediaRow(title: row.title, items: row.items, spacing: row.style == .landscape ? 16 : 14, onLead: { m in
                    leads[row.id] = m
                    hovered = m
                }) { m in
                    switch row.style {
                    case .landscape:
                        LandscapeCard(meta: m, subtitle: row.subtitles[m.id], progress: row.progress[m.id], onHover: hover, resume: row.resume[m.id])
                    case .poster:
                        PosterCard(meta: m, badge: row.badges[m.id] ?? row.match[m.id].map { "\($0)%" }, onHover: hover)
                    }
                }
            }
        }
        .scrollTargetLayout()
        .padding(.bottom, 48)
    }

    private func hover(_ m: Meta) { hovered = m }
}
