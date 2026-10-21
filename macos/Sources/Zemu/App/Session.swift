import SwiftUI
import Observation
import ZemuCore

/** Calls [onChange] with [value] now and whenever what it reads changes (Observation, outside SwiftUI). Keep the result alive. */
@MainActor
final class Tracker<T: Equatable> {
    private let value: @MainActor () -> T
    private let onChange: @MainActor (T) -> Void
    private var last: T?
    private var stopped = false

    init(_ value: @escaping @MainActor () -> T, _ onChange: @escaping @MainActor (T) -> Void) {
        self.value = value
        self.onChange = onChange
        observe()
    }

    private func observe() {
        guard !stopped else { return }
        let v = withObservationTracking { value() } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
        if v != last {
            last = v
            onChange(v)
        }
    }

    func stop() { stopped = true }
}

/**
 * Everything that belongs to one profile: its addons, history, settings and the services built on
 * them. Switching profile swaps the whole session (like the Android app's AppContainer).
 */
@MainActor @Observable
final class Session {
    let profileId: String
    let store: UserStore
    let addons: AddonRepository
    let streams: StreamRepository
    let recommender: Recommender
    let tmdb: Tmdb
    let freeCast = FreeCast()
    let skipSegments = SkipSegments()
    let newEpisodes: NewEpisodes
    let capabilities: DeviceCapabilities
    let scores: Scores
    let artwork: Artwork
    let trakt: Trakt
    let kids: KidsGate

    /** Stream filters persist across titles for the session, like a "sticky" preference. */
    var streamFilter = FilterState()

    // Screen models kept alive while switching pages, so coming back is instant.
    @ObservationIgnored lazy var home = HomeModel(self)
    @ObservationIgnored lazy var search = SearchModel(self)
    @ObservationIgnored lazy var addonsBrowser = AddonsModel(self)
    @ObservationIgnored private var browse: [String: BrowseModel] = [:]
    func browseModel(_ type: String) -> BrowseModel {
        if let b = browse[type] { return b }
        let b = BrowseModel(self, type: type)
        browse[type] = b
        return b
    }

    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var alive = true
    @ObservationIgnored private var trackers: [Tracker<[String]>] = []

    init(profileId: String) {
        self.profileId = profileId
        let store = UserStore(profileId: profileId)
        self.store = store
        let addons = AddonRepository(store: store)
        self.addons = addons
        streams = StreamRepository(addons: addons, store: store)
        recommender = Recommender(addons: addons)
        tmdb = Tmdb(key: { store.settings.tmdbApiKey })
        newEpisodes = NewEpisodes(addons: addons, store: store)
        capabilities = DeviceCaps.detect()
        scores = Scores(key: { store.settings.omdbApiKey })
        artwork = Artwork(tmdb: tmdb, fanartKey: { store.settings.fanartApiKey })
        trakt = Trakt(store: store)
        // Called later, never during AppModel's own init.
        kids = KidsGate(tmdb: tmdb, scores: scores, settings: { AppModel.shared.profiles.kids }, on: { AppModel.shared.profiles.kidsOn })

        newEpisodes.onFresh = { [weak self] items in self?.announce(items) }
        trackers.append(Tracker({ [weak self] in
            (self?.store.history.filter { $0.meta.type == "series" }.map { "\($0.meta.id)|\($0.videoId)" } ?? [])
                + (self?.store.myList.filter { $0.type == "series" }.map(\.id) ?? [])
        }) { [weak self] _ in
            guard let self, self.alive else { return }
            self.newEpisodes.historyChanged()
        })
        // Mirror My List to the Trakt watchlist, and sync from Trakt once per session.
        var listBefore: Set<String>?
        trackers.append(Tracker({ [weak self] in self?.store.myList.map { "\($0.id)|\($0.type)" } ?? [] }) { [weak self] ids in
            let now = Set(ids)
            if let before = listBefore, before != now { self?.trakt.myListChanged(from: before, to: now) }
            listBefore = now
        })
        tasks.append(Task { [weak self] in
            guard let self, self.trakt.connected else { return }
            _ = try? await self.trakt.sync()
        })
        tasks.append(Task { [weak self] in await self?.keepDebridFresh() })
        Integrations.shared.sessionStarted(self)
    }

    func close() {
        alive = false
        tasks.forEach { $0.cancel() }
        trackers.forEach { $0.stop() }
        newEpisodes.stop()
        store.saveNow()
    }

    var settings: AppSettings { store.settings }

    func tasteProfile() -> TasteProfile {
        TasteProfile.from(history: store.history, myList: store.myList, rated: store.ratedMetas, ratings: store.ratings)
    }

    func matchPercent(_ m: Meta) -> Int { Recommender.matchPercent(m, tasteProfile()) }

    /** Titles in progress, for Continue Watching (Home, Dock menu, menu bar). */
    var inProgress: [WatchEntry] {
        let w = store.watched
        return store.history.filter { ($0.progress >= 0.01 && $0.progress <= 0.95 || $0.durationMs == 0) && !w.contains($0.meta.id) }.distinct(by: \.meta.id)
    }

    // MARK: Debrid

    /** Saves the account and installs Torrentio set up with it (replacing any other Torrentio). */
    func linkDebrid(_ account: DebridAccount) async -> String {
        store.saveDebrid(account)
        do {
            try await addons.install(account.torrentioUrl)
            streams.invalidate()
            return "\(account.service.label) linked. Torrentio is set up with your account."
        } catch {
            return "\(account.service.label) linked, but Torrentio couldn't be installed: \(error.localizedDescription)"
        }
    }

    func unlinkDebrid() {
        guard let account = store.debrid else { return }
        store.saveDebrid(nil)
        for a in addons.addons where a.transportUrl.contains("\(account.service.torrentio)=\(account.token)") { addons.remove(a.transportUrl) }
        streams.invalidate()
    }

    /** Code-approved Real-Debrid logins expire; renew them shortly before and update Torrentio's URL. */
    private func keepDebridFresh() async {
        await addons.waitReady()
        while !Task.isCancelled {
            guard let a = store.debrid, a.renewable else { return }
            let wait = a.expiresAt - nowMs() - 30 * 60_000
            if wait > 0 {
                try? await Task.sleep(nanoseconds: UInt64(min(wait, 6 * 3600_000)) * 1_000_000)
                continue
            }
            guard let fresh = await DebridAuth.refresh(a) else {
                try? await Task.sleep(nanoseconds: 10 * 60 * 1_000_000_000)
                continue
            }
            let old = addons.addons.first { $0.transportUrl.contains("\(a.service.torrentio)=\(a.token)") }
            store.saveDebrid(fresh)
            if let old {
                _ = try? await addons.install(fresh.torrentioUrl)
                if addons.addons.contains(where: { $0.transportUrl == old.transportUrl }) { addons.remove(old.transportUrl) }
                streams.invalidate()
            }
        }
    }

    // MARK: Keys and pasted text

    func saveTmdbKey(_ key: String) async -> String {
        let k = key.trimmed
        if k.isEmpty {
            store.updateSettings { $0.tmdbApiKey = "" }
            return "TMDB key removed"
        }
        guard await tmdb.validate(k) else {
            return "That TMDB key didn't work. Copy the \"API Key\" or \"API Read Access Token\" from themoviedb.org → Settings → API."
        }
        store.updateSettings { $0.tmdbApiKey = k }
        return "TMDB key saved. Cast photos and filmographies are on."
    }

    /** Pasted or dropped text: an addon URL installs it, anything else is tried as a TMDB key. */
    func handlePastedText(_ text: String) async -> String {
        let t = text.trimmed
        let looksLikeUrl = t.hasPrefix("http") || t.hasPrefix("stremio://") || t.contains("manifest.json") || t.contains("/")
        if looksLikeUrl {
            do {
                let a = try await addons.install(t)
                streams.invalidate()
                return "Installed \(a.manifest.name) \(a.manifest.version)"
            } catch {
                return "Couldn't install: \(error.localizedDescription)"
            }
        }
        return await saveTmdbKey(t)
    }

    // MARK: Notifications

    private func announce(_ items: [NewEpisodesItem]) {
        guard settings.notifyNewEpisodes, !items.isEmpty else { return }
        let fresh = store.markNotified(items.map { "\($0.meta.id)|\($0.latest.id)" })
        let toAnnounce = items.filter { fresh.contains("\($0.meta.id)|\($0.latest.id)") }
        Integrations.shared.notifyNewEpisodes(toAnnounce)
    }
}
