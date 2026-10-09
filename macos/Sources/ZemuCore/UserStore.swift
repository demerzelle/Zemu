import Foundation
import Observation

/** A past search and the posters it found, so Search can show them again instantly. */
public struct SearchHistoryEntry: Codable, Hashable, Sendable {
    public var query: String
    public var at: Int64
    public var results: [Meta]
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
    }
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
    public var ratings: [String: Int] { data.ratings }
    public var ratedMetas: [Meta] { data.ratedMetas }
    public var debrid: DebridAccount? { data.debrid }
    public var lastStreams: [String: LastStream] { data.lastStreams }

    public func isInMyList(_ id: String) -> Bool { data.myList.contains { $0.id == id } }
    public var searchHistory: [SearchHistoryEntry] { data.searchHistory }
    public var searchPicks: [Meta] { data.searchPicks }

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

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    public func saveNow() {
        guard let encoded = try? JSONEncoder().encode(data) else { return }
        let file = self.file
        try? encoded.write(to: file, options: [.atomic])
        // The file holds debrid tokens and API keys.
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}
