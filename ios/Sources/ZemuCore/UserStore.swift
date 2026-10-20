import Foundation
import Observation

/** A past search and the posters it found, so Search can show them again instantly. */
public struct SearchHistoryEntry: Codable, Hashable, Sendable {
    public var query: String
    public var at: Int64
    public var results: [Meta]
}

/** A category row pinned on one page. Its titles are kept as they were when it was pinned. */
public struct PinnedRow: Codable, Hashable, Sendable {
    public var page: String
    public var key: String
    public var title: String
    public var landscape: Bool
    public var items: [Meta]

    public init(page: String, key: String, title: String, landscape: Bool, items: [Meta]) {
        self.page = page; self.key = key; self.title = title; self.landscape = landscape; self.items = items
    }
}

/** Everything one profile stores, saved as a single JSON file. */
struct UserData: Codable {
    /** nil until the first save, so first launch can install default addons. */
    var addons: [InstalledAddon]?
    var settings = AppSettings()
    var myList: [Meta] = []
    var history: [WatchEntry] = []
    /** Titles marked watched (by meta id), newest first. */
    var watched: [String] = []
    /** Thumbs up (1) / down (-1) per meta id; feeds recommendations. */
    var ratings: [String: Int] = [:]
    /** Genres of rated titles, so ratings keep working after history is cleared. */
    var ratedMetas: [Meta] = []
    var debrid: DebridAccount?
    /** The stream last played for each title (newest first), so it can be picked again while it's still cached. */
    var lastStreams: [String: LastStream] = [:]
    var lastStreamOrder: [String] = []
    /** Episodes already announced in a notification, so each is announced once. */
    var notifiedEpisodes: [String] = []
    /** Newest first. */
    var searchHistory: [SearchHistoryEntry] = []
    /** Titles opened from search results, newest first. */
    var searchPicks: [Meta] = []
    /** When each My List title was added (ms). */
    var myListAdded: [String: Int64] = [:]
    /** Row keys in the order the user arranged them, per page ("home", "movie", "series", "anime"). */
    var rowOrder: [String: [String]] = [:]
    /** Category rows the user pinned to keep for later. */
    var pinnedRows: [PinnedRow] = []
    /** Rows removed from a page (Settings → Rows can bring them back). */
    var hiddenRows: [String: [String]] = [:]
    /** Rows the user added to a page themselves. */
    var addedRows: [String: [RowSpec]] = [:]

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        addons = c.lenient(.addons, [InstalledAddon].self)
        settings = c.lenient(.settings, AppSettings.self) ?? AppSettings()
        myList = c.lenient(.myList, [Meta].self) ?? []
        history = c.lenient(.history, [WatchEntry].self) ?? []
        watched = c.lenient(.watched, [String].self) ?? []
        ratings = c.lenient(.ratings, [String: Int].self) ?? [:]
        ratedMetas = c.lenient(.ratedMetas, [Meta].self) ?? []
        debrid = c.lenient(.debrid, DebridAccount.self)
        lastStreams = c.lenient(.lastStreams, [String: LastStream].self) ?? [:]
        lastStreamOrder = c.lenient(.lastStreamOrder, [String].self) ?? []
        notifiedEpisodes = c.lenient(.notifiedEpisodes, [String].self) ?? []
        searchHistory = c.lenient(.searchHistory, [SearchHistoryEntry].self) ?? []
        searchPicks = c.lenient(.searchPicks, [Meta].self) ?? []
        myListAdded = c.lenient(.myListAdded, [String: Int64].self) ?? [:]
        rowOrder = c.lenient(.rowOrder, [String: [String]].self) ?? [:]
        pinnedRows = c.lenient(.pinnedRows, [PinnedRow].self) ?? []
        hiddenRows = c.lenient(.hiddenRows, [String: [String]].self) ?? [:]
        addedRows = c.lenient(.addedRows, [String: [RowSpec]].self) ?? [:]
    }
}

/** Summary numbers for Settings → Data & Backup, computed from this profile's history. */
public struct WatchStats: Equatable, Sendable {
    public var titlesWatched = 0
    public var myList = 0
    public var movies = 0
    public var series = 0
    /** Each title's last position added up. A lower bound: rewatches and skipped parts aren't counted. */
    public var approxHours: Double = 0
    public var topGenres: [String] = []
}

/**
 * Per-profile data (addons, settings, history, My List, likes, ...). Changes are observable and
 * written to disk shortly after they happen.
 */
@MainActor @Observable
public final class UserStore {
    public let profileId: String
    private let file: URL
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    var data: UserData { didSet { scheduleSave() } }

    public init(profileId: String) {
        self.profileId = profileId
        file = ProfileStore.dataFile(for: profileId)
        if let d = try? Data(contentsOf: file), let decoded = try? JSONDecoder().decode(UserData.self, from: d) {
            data = decoded
        } else {
            data = UserData()
        }
    }

    // MARK: Reads

    public var settings: AppSettings { data.settings }
    public var installedAddons: [InstalledAddon]? { data.addons }
    public var myList: [Meta] { data.myList }
    public var history: [WatchEntry] { data.history }
    public var watched: Set<String> { Set(data.watched) }
    /** Non-allocating check; use this in list cells instead of building `watched` for every card. */
    public func isWatched(_ id: String) -> Bool { data.watched.contains(id) }
    public var ratings: [String: Int] { data.ratings }
    public var ratedMetas: [Meta] { data.ratedMetas }
    public var debrid: DebridAccount? { data.debrid }
    public var lastStreams: [String: LastStream] { data.lastStreams }

    public func isInMyList(_ id: String) -> Bool { data.myList.contains { $0.id == id } }
    public var searchHistory: [SearchHistoryEntry] { data.searchHistory }
    public var searchPicks: [Meta] { data.searchPicks }

    // MARK: Page rows

    /** Saved row order for a page (top first). Rows not listed keep their default place after these. */
    public func rowOrder(page: String) -> [String] { data.rowOrder[page] ?? [] }

    public func setRowOrder(_ keys: [String], page: String) {
        var d = data
        d.rowOrder[page] = keys
        data = d
    }

    public func pinnedRows(page: String) -> [PinnedRow] { data.pinnedRows.filter { $0.page == page } }

    public func pin(_ row: PinnedRow) {
        var d = data
        d.pinnedRows.removeAll { $0.page == row.page && $0.key == row.key }
        d.pinnedRows.insert(row, at: 0)
        data = d
    }

    public func unpin(key: String, page: String) {
        var d = data
        d.pinnedRows.removeAll { $0.page == page && $0.key == key }
        data = d
    }

    public func hiddenRows(page: String) -> [String] { data.hiddenRows[page] ?? [] }
    public func addedRows(page: String) -> [RowSpec] { data.addedRows[page] ?? [] }

    /** A row you added is simply taken off again; anything else is hidden and can be restored. */
    public func hideRow(_ key: String, page: String) {
        var d = data
        if d.addedRows[page]?.contains(where: { $0.key == key }) == true {
            d.addedRows[page]?.removeAll { $0.key == key }
        } else {
            d.hiddenRows[page] = ((d.hiddenRows[page] ?? []) + [key]).distinct()
        }
        d.pinnedRows.removeAll { $0.page == page && $0.key == key }
        data = d
    }

    public func showRow(_ key: String, page: String) { data.hiddenRows[page]?.removeAll { $0 == key } }

    public func addRow(_ spec: RowSpec, page: String) {
        var d = data
        guard d.addedRows[page]?.contains(where: { $0.key == spec.key }) != true else { return }
        d.addedRows[page, default: []].append(spec)
        d.hiddenRows[page]?.removeAll { $0 == spec.key }
        data = d
    }

    public var watchStats: WatchStats {
        var s = WatchStats()
        var seen = Set<String>()
        let recent = data.history.filter { seen.insert($0.meta.id).inserted }
        s.titlesWatched = data.watched.count
        s.myList = data.myList.count
        s.movies = recent.filter { $0.meta.type == "movie" }.count
        s.series = recent.filter { $0.meta.type == "series" }.count
        s.approxHours = Double(recent.reduce(Int64(0)) { $0 + $1.positionMs }) / 3_600_000
        var counts: [String: Int] = [:]
        for e in recent { for g in e.meta.genres { counts[g, default: 0] += 1 } }
        s.topGenres = counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(3).map(\.key)
        return s
    }

    /**
     * When a title was added to My List. Titles saved before dates were kept get an estimate that
     * keeps the list's order (newest first, a minute apart).
     */
    public func myListAddedAt(_ id: String) -> Int64 {
        if let t = data.myListAdded[id] { return t }
        let i = data.myList.firstIndex { $0.id == id } ?? 0
        let oldest = data.myListAdded.values.min() ?? nowMs()
        return oldest - Int64(i + 1) * 60_000
    }

    // MARK: Writes

    public func updateSettings(_ transform: (inout AppSettings) -> Void) {
        var s = data.settings
        transform(&s)
        if s != data.settings { data.settings = s }
    }

    public func saveAddons(_ list: [InstalledAddon]) { data.addons = list }

    public func saveDebrid(_ account: DebridAccount?) { data.debrid = account }

    public func setWatched(_ meta: Meta, _ watched: Bool) {
        var cur = data.watched.filter { $0 != meta.id }
        if watched { cur.insert(meta.id, at: 0) }
        data.watched = Array(cur.prefix(2000))
    }

    /** Marks titles watched (Trakt sync); returns how many weren't already. */
    @discardableResult
    public func addWatched(_ ids: [String]) -> Int {
        let fresh = ids.filter { !data.watched.contains($0) }.distinct()
        if !fresh.isEmpty { data.watched = Array((fresh + data.watched).prefix(2000)) }
        return fresh.count
    }

    public func rate(_ meta: Meta, _ value: Int) {
        var d = data
        if value == 0 { d.ratings[meta.id] = nil } else { d.ratings[meta.id] = value }
        let metas = d.ratedMetas.filter { $0.id != meta.id }
        d.ratedMetas = value == 0 ? metas : Array(([meta.slim()] + metas).prefix(300))
        data = d
    }

    public func toggleMyList(_ meta: Meta) {
        var d = data
        if isInMyList(meta.id) {
            d.myList.removeAll { $0.id == meta.id }
            d.myListAdded[meta.id] = nil
        } else {
            d.myList.insert(meta.slim(), at: 0)
            d.myListAdded[meta.id] = nowMs()
        }
        data = d
    }

    // MARK: Search history

    /** Remembers a search with (a few of) its results; repeating a search moves it to the top. */
    public func recordSearch(_ query: String, results: [Meta]) {
        let q = query.trimmed
        guard q.count >= 2 else { return }
        var d = data
        d.searchHistory.removeAll { $0.query.lowercased() == q.lowercased() }
        d.searchHistory.insert(SearchHistoryEntry(query: q, at: nowMs(), results: results.prefix(18).map { $0.slim() }), at: 0)
        d.searchHistory = Array(d.searchHistory.prefix(15))
        data = d
    }

    public func removeSearch(_ query: String) { data.searchHistory.removeAll { $0.query == query } }

    public func clearSearchHistory() {
        var d = data
        d.searchHistory = []
        d.searchPicks = []
        data = d
    }

    /** A title opened from search results. */
    public func recordSearchPick(_ meta: Meta) {
        var d = data
        d.searchPicks = Array(([meta.slim()] + d.searchPicks.filter { $0.id != meta.id }).prefix(30))
        data = d
    }

    public func removeFromHistory(_ metaId: String) { data.history.removeAll { $0.meta.id == metaId } }

    public func clearHistory() { data.history = [] }

    public func recordProgress(_ entry: WatchEntry) {
        var d = data
        var e = entry
        e.meta = entry.meta.slim()
        d.history = Array(([e] + d.history.filter { $0.meta.id != entry.meta.id }).prefix(150))
        let done = entry.durationMs > 0 && entry.progress > 0.92 && entry.meta.type != "series"
        if done || (0.01...0.9).contains(entry.progress) {
            var w = d.watched.filter { $0 != entry.meta.id }
            if done { w.insert(entry.meta.id, at: 0) }
            d.watched = w
        }
        data = d
    }

    public func rememberStream(_ metaId: String, _ stream: LastStream) {
        var d = data
        d.lastStreams[metaId] = stream
        d.lastStreamOrder = [metaId] + d.lastStreamOrder.filter { $0 != metaId }
        if d.lastStreamOrder.count > 200 {
            for id in d.lastStreamOrder.dropFirst(200) { d.lastStreams[id] = nil }
            d.lastStreamOrder = Array(d.lastStreamOrder.prefix(200))
        }
        data = d
    }

    /** Returns the keys not yet announced and records them. */
    public func markNotified(_ keys: [String]) -> [String] {
        let fresh = keys.filter { !data.notifiedEpisodes.contains($0) }
        if !fresh.isEmpty { data.notifiedEpisodes = Array((fresh + data.notifiedEpisodes).prefix(500)) }
        return fresh
    }

    // MARK: Backup

    /** The whole profile as JSON (Settings → Export). */
    public func exportData() throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try enc.encode(data)
    }

    public func importData(_ raw: Data) throws {
        data = try JSONDecoder().decode(UserData.self, from: raw)
    }

    // MARK: Persistence

    /** One serial queue for all profile writes, so an older snapshot can never overwrite a newer one. */
    private static let writer = DispatchQueue(label: "zemu.userstore.write", qos: .utility)

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            self?.persist(blocking: false)
        }
    }

    /** Writes the profile now (on quit and profile switches). */
    public func saveNow() {
        persist(blocking: true)
    }

    /**
     * Encoding a large profile (history, My List, search results) is real work, so debounced saves
     * encode and write on a background queue. The snapshot is a value copy, so later edits don't race it.
     */
    private func persist(blocking: Bool) {
        let snapshot = data
        let file = self.file
        let job = {
            guard let encoded = try? JSONEncoder().encode(snapshot) else { return }
            try? encoded.write(to: file, options: [.atomic])
            // The file holds debrid tokens and API keys.
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        }
        if blocking { Self.writer.sync(execute: job) } else { Self.writer.async(execute: job) }
    }
}
