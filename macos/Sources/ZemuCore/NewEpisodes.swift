import Foundation
import Observation

/** A show you've been watching that has [count] episodes out since you last watched it. */
public struct NewEpisodesItem: Hashable, Sendable {
    public var meta: Meta
    public var count: Int
    public var latestRelease: Int64
    /** The newest released episode, for notifications. */
    public var latest: Video
    public var badge: String { "\(count) NEW" }
}

/**
 * Finds shows in your history with episodes released after your last watch: past the episode you
 * were on, and already out. Rechecked when your history changes and every few hours.
 */
@MainActor @Observable
public final class NewEpisodes {
    public private(set) var items: [NewEpisodesItem] = []

    @ObservationIgnored private let addons: AddonRepository
    @ObservationIgnored private let store: UserStore
    @ObservationIgnored private var lastKey: [String] = []
    @ObservationIgnored private var loop: Task<Void, Never>?
    /** Called with shows that gained episodes since the previous check (for notifications). */
    @ObservationIgnored public var onFresh: (([NewEpisodesItem]) -> Void)?

    public init(addons: AddonRepository, store: UserStore) {
        self.addons = addons
        self.store = store
    }

    /** Re-checks when the set of shows (or where you are in them) changed, then every 6 hours. */
    public func historyChanged() {
        let key = store.history.filter { $0.meta.type == "series" }.map { "\($0.meta.id)|\($0.videoId)" }
        if key == lastKey && loop != nil { return }
        lastKey = key
        loop?.cancel()
        loop = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            while !Task.isCancelled {
                guard let self else { return }
                await self.addons.waitReady()
                let fresh = await self.check()
                if Task.isCancelled { return }
                self.items = fresh
                self.onFresh?(fresh)
                try? await Task.sleep(nanoseconds: 6 * 3600 * 1_000_000_000)
            }
        }
    }

    public func stop() { loop?.cancel() }

    private func check() async -> [NewEpisodesItem] {
        let now = nowMs()
        let entries = Array(store.history.filter { $0.meta.type == "series" }.distinct(by: \.meta.id).prefix(40))
        let results = await concurrentMap(entries) { entry -> NewEpisodesItem? in
            guard let meta = await self.addons.meta(type: "series", id: entry.meta.id) else { return nil }
            let ordered = meta.videos.filter { ($0.season ?? 1) > 0 }.sorted { ($0.season ?? 0, $0.episodeNumber) < ($1.season ?? 0, $1.episodeNumber) }
            guard let at = ordered.firstIndex(where: { $0.id == entry.videoId }) else { return nil }
            let fresh = ordered.dropFirst(at + 1).compactMap { v -> (Video, Int64)? in
                guard let t = Self.releasedAt(v), t > entry.updatedAt, t <= now else { return nil }
                return (v, t)
            }
            guard let newest = fresh.max(by: { $0.1 < $1.1 }) else { return nil }
            return NewEpisodesItem(meta: meta.slim(), count: fresh.count, latestRelease: newest.1, latest: newest.0)
        }
        return results.compactMap { $0 }.sorted { $0.latestRelease > $1.latestRelease }
    }

    nonisolated static func releasedAt(_ v: Video) -> Int64? {
        guard let r = v.released?.nilIfBlank else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: r) { return Int64(d.timeIntervalSince1970 * 1000) }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: r) { return Int64(d.timeIntervalSince1970 * 1000) }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: String(r.prefix(10))).map { Int64($0.timeIntervalSince1970 * 1000) }
    }
}
