import Foundation
import Observation

@MainActor @Observable
public final class AddonRepository {
    public static let cinemetaId = "com.linvo.cinemeta"
    public static let kitsuId = "community.anime.kitsu"
    public static let kitsuUrl = "https://anime-kitsu.strem.fun/manifest.json"
    public static let defaultAddons = [
        "https://v3-cinemeta.strem.io/manifest.json",
        "https://opensubtitles-v3.strem.io/manifest.json",
    ]

    public private(set) var addons: [Addon] = []
    public private(set) var ready = false

    @ObservationIgnored private let store: UserStore
    @ObservationIgnored private var installingDefaults: Task<Void, Never>?

    public init(store: UserStore) {
        self.store = store
        if let saved = store.installedAddons {
            addons = saved.compactMap { a in (try? AddonManifest.parse(a.manifestJson)).map { Addon(transportUrl: a.transportUrl, manifest: $0) } }
            ready = true
        } else {
            Task { await installDefaults(); ready = true }
        }
    }

    /** Waits until saved addons are loaded (or defaults installed on first launch). */
    public func waitReady() async {
        while !ready { try? await Task.sleep(nanoseconds: 50_000_000) }
    }

    /** Installs the defaults if nothing is installed yet (e.g. first launch was offline). */
    public func ensureDefaults() async {
        if addons.isEmpty { await installDefaults() }
    }

    private func installDefaults() async {
        if let t = installingDefaults { return await t.value }
        let t = Task {
            var installed: [(InstalledAddon, Addon)] = []
            await withTaskGroup(of: (Int, InstalledAddon, Addon)?.self) { group in
                for (i, url) in Self.defaultAddons.enumerated() {
                    group.addTask {
                        guard let (raw, m) = try? await AddonClient.fetchManifest(url) else { return nil }
                        return (i, InstalledAddon(transportUrl: url, manifestJson: raw), Addon(transportUrl: url, manifest: m))
                    }
                }
                var results: [(Int, InstalledAddon, Addon)] = []
                for await r in group { if let r { results.append(r) } }
                installed = results.sorted { $0.0 < $1.0 }.map { ($0.1, $0.2) }
            }
            if !installed.isEmpty {
                store.saveAddons(installed.map(\.0))
                addons = installed.map(\.1)
            }
        }
        installingDefaults = t
        await t.value
        installingDefaults = nil
    }

    public var kitsu: Addon? { addons.first { $0.manifest.id == Self.kitsuId } }
    public var cinemeta: Addon? { addons.first { $0.manifest.id == Self.cinemetaId } }
    public var hasStreamAddons: Bool { addons.contains { $0.manifest.hasResource("stream") } }

    /** Installs the Kitsu addon the first time the Anime page is opened. */
    public func ensureKitsu() async -> Addon? {
        if let k = kitsu { return k }
        return try? await install(Self.kitsuUrl)
    }

    @discardableResult
    public func install(_ input: String) async throws -> Addon {
        let url = AddonClient.normalizeTransportUrl(input)
        let (raw, manifest) = try await AddonClient.fetchManifest(url)
        let addon = Addon(transportUrl: url, manifest: manifest)
        // Replace an existing install of the same addon id (e.g. re-configured Torrentio).
        let next = addons.filter { $0.manifest.id != manifest.id && $0.transportUrl != url } + [addon]
        persist(next, extra: (url, raw))
        addons = next
        return addon
    }

    public func remove(_ transportUrl: String) {
        let next = addons.filter { $0.transportUrl != transportUrl }
        persist(next)
        addons = next
    }

    /** Moves an addon in the list; earlier addons are asked first and win ties for details. */
    public func move(from: IndexSet, to: Int) {
        let moving = from.map { addons[$0] }
        var next = addons.enumerated().filter { !from.contains($0.offset) }.map(\.element)
        next.insert(contentsOf: moving, at: min(to - from.filter { $0 < to }.count, next.count))
        persist(next)
        addons = next
    }

    private func persist(_ list: [Addon], extra: (String, String)? = nil) {
        let saved = Dictionary((store.installedAddons ?? []).map { ($0.transportUrl, $0) }, uniquingKeysWith: { a, _ in a })
        store.saveAddons(list.compactMap { a in
            if let extra, a.transportUrl == extra.0 { return InstalledAddon(transportUrl: a.transportUrl, manifestJson: extra.1) }
            return saved[a.transportUrl]
        })
    }

    public func addonsFor(_ resource: String, type: String, id: String?) -> [Addon] {
        addons.filter { $0.manifest.supports(resource, type: type, id: id) }
    }

    /** Every season seen so far, by [AnimeSeasons.groupKey], for the seasons row on a title's page. */
    @ObservationIgnored private var animeSeasons: [String: [Meta]] = [:]

    /** Kitsu catalogs show one card per anime, with its other seasons kept for its page. */
    public func catalog(_ addon: Addon, type: String, id: String, extra: [String: String] = [:]) async throws -> [Meta] {
        let items = try await AddonClient.catalog(addon.baseUrl, type: type, id: id, extra: extra)
        guard addon.manifest.id == Self.kitsuId else { return items }
        for m in items where m.isAnime {
            let key = AnimeSeasons.groupKey(m)
            var list = animeSeasons[key] ?? []
            if !list.contains(where: { $0.id == m.id }) { list.append(m) }
            animeSeasons[key] = list
        }
        return AnimeSeasons.collapse(items)
    }

    /** All seasons of the show a title belongs to, in order. Empty when the show has only one. */
    public func seasons(of meta: Meta) -> [Meta] {
        guard meta.isAnime, let list = animeSeasons[AnimeSeasons.groupKey(meta)], list.count > 1 else { return [] }
        return AnimeSeasons.sorted(list)
    }

    public func catalogDetailed(_ addon: Addon, type: String, id: String, extra: [String: String]) async throws -> [Meta] {
        try await AddonClient.catalogDetailed(addon.baseUrl, type: type, id: id, extra: extra)
    }

    public func isInstalled(_ manifestId: String) -> Bool { addons.contains { $0.manifest.id == manifestId } }

    /** Addon catalogs to browse: those published by installed addons (Cinemeta: Official, Community) plus stremio-addons.net. */
    public func addonCatalogSources() -> [AddonCatalogSource] {
        let fromInstalled = addons.flatMap { a in
            a.manifest.addonCatalogs.filter { $0.type == "all" }.map { c in
                let n = c.name ?? c.id
                return AddonCatalogSource(key: "\(a.manifest.id)/\(c.id)", name: n.prefix(1).uppercased() + n.dropFirst(), base: a.baseUrl, type: c.type, id: c.id)
            }
        }
        let extra = AddonCatalogSource(key: "stremio-addons.net", name: "stremio-addons.net", base: "https://stremio-addons.net/api", type: "all", id: "stremio-addons.net")
        return (fromInstalled + [extra]).distinct(by: \.key)
    }

    public func browse(_ source: AddonCatalogSource) async throws -> [CatalogAddon] {
        try await AddonClient.addonCatalog(source.base, type: source.type, id: source.id)
    }

    /** Addons that can provide catalogs or details, in preference order. */
    public func metaProviders() -> [Addon] {
        let preferred = store.settings.metaProvider
        return addons.filter { $0.manifest.hasResource("meta") || !$0.manifest.catalogs.isEmpty }
            .stableSorted { ($0.manifest.id == preferred ? 1 : 0) > ($1.manifest.id == preferred ? 1 : 0) }
    }

    /** True when something besides [excludingId] still provides catalogs. */
    public func hasOtherCatalogProvider(excluding id: String) -> Bool {
        addons.contains { a in a.manifest.id != id && a.manifest.catalogs.contains { ["movie", "series"].contains($0.type) && $0.requiredExtras.isEmpty } }
    }

    public func meta(type: String, id: String) async -> Meta? {
        let preferred = store.settings.metaProvider
        let candidates = addonsFor("meta", type: type, id: id).stableSorted { ($0.manifest.id == preferred ? 1 : 0) > ($1.manifest.id == preferred ? 1 : 0) }
        for addon in candidates {
            if let m = try? await AddonClient.meta(addon.baseUrl, type: type, id: id), !m.id.isEmpty { return m }
        }
        return nil
    }
}
