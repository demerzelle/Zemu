import Observation
import Foundation

/** What Trakt shows to link this Mac: go to [url] and enter [userCode]. */
public struct TraktLink: Sendable, Equatable {
    public let deviceCode: String
    public let userCode: String
    public let url: String
    public let intervalSec: Int
    public let expiresAt: Int64
}

/** A title your Trakt friends recommend. */
public struct FriendRec: Sendable, Equatable {
    public var meta: Meta
    public var from: [String]
}

public struct TraktError: LocalizedError {
    public let message: String
    public var errorDescription: String? { message }
}

/**
 * Trakt (trakt.tv): your watchlist mirrors My List both ways, watched movies come in from Trakt,
 * and what you play is scrobbled (Trakt marks it watched once you're past 80%). Uses your own
 * Trakt API app (free): its Client ID and secret go in Settings.
 */
@MainActor @Observable
public final class Trakt {
    @ObservationIgnored private let base = "https://api.trakt.tv"
    @ObservationIgnored private let store: UserStore
    @ObservationIgnored private let recsSlug = "zemu-recommendations"
    public private(set) var hasFriends = false
    public private(set) var friendRecs: [FriendRec] = []
    public private(set) var myRecs: Set<String> = []
    private var settings: AppSettings { store.settings }

    public init(store: UserStore) { self.store = store }

    public var configured: Bool { !settings.traktClientId.trimmed.isEmpty && !settings.traktClientSecret.trimmed.isEmpty }
    public var connected: Bool { configured && !settings.traktAccessToken.isEmpty }

    /** Pushes My List changes to the Trakt watchlist. Ids are "id|type". */
    public func myListChanged(from before: Set<String>, to now: Set<String>) {
        guard connected else { return }
        let added = now.subtracting(before), removed = before.subtracting(now)
        Task {
            if !added.isEmpty { _ = try? await post("/sync/watchlist", idsBody(added)) }
            if !removed.isEmpty { _ = try? await post("/sync/watchlist/remove", idsBody(removed)) }
        }
    }

    private func idsBody(_ items: Set<String>) -> [String: Any] {
        func list(_ type: String) -> [[String: Any]] {
            items.compactMap { item in
                let p = item.split(separator: "|", maxSplits: 1).map(String.init)
                guard p.count == 2, p[1] == type, p[0].hasPrefix("tt") else { return nil }
                return ["ids": ["imdb": p[0].split(separator: ":").first.map(String.init) ?? p[0]]]
            }
        }
        return ["movies": list("movie"), "shows": list("series")]
    }

    // MARK: Linking (device code)

    public func startLink() async throws -> TraktLink {
        let o = try await call("/oauth/device/code", ["client_id": settings.traktClientId.trimmed], auth: false)
        return TraktLink(
            deviceCode: o["device_code"]?.string ?? "", userCode: o["user_code"]?.string ?? "",
            url: o["verification_url"]?.string ?? "https://trakt.tv/activate",
            intervalSec: o["interval"]?.int ?? 5, expiresAt: nowMs() + Int64(o["expires_in"]?.int ?? 600) * 1000
        )
    }

    /** One poll: true once linked, false while waiting; throws when declined or expired. */
    public func pollLink(_ link: TraktLink) async throws -> Bool {
        let body: [String: Any] = ["code": link.deviceCode, "client_id": settings.traktClientId.trimmed, "client_secret": settings.traktClientSecret.trimmed]
        let (code, data) = try await raw("POST", "/oauth/device/token", body, auth: false)
        switch code {
        case 200:
            saveTokens(JSONValue.parse(data) ?? .object([:]))
            Task { _ = try? await sync() }
            return true
        case 400, 429: return false
        default: throw TraktError(message: code == 418 ? "Linking was declined on Trakt." : "The code expired. Try again.")
        }
    }

    public func disconnect() {
        hasFriends = false; friendRecs = []; myRecs = []
        store.updateSettings { $0.traktAccessToken = ""; $0.traktRefreshToken = ""; $0.traktExpiresAt = 0 }
    }

    private func saveTokens(_ o: JSONValue) {
        store.updateSettings {
            $0.traktAccessToken = o["access_token"]?.string ?? ""
            $0.traktRefreshToken = o["refresh_token"]?.string ?? ""
            $0.traktExpiresAt = nowMs() + Int64(o["expires_in"]?.int ?? 0) * 1000
        }
    }

    private func refreshIfNeeded() async throws {
        guard settings.traktExpiresAt - nowMs() <= 24 * 3_600_000 else { return }
        let body: [String: Any] = [
            "refresh_token": settings.traktRefreshToken, "client_id": settings.traktClientId.trimmed,
            "client_secret": settings.traktClientSecret.trimmed, "redirect_uri": "urn:ietf:wg:oauth:2.0:oob", "grant_type": "refresh_token",
        ]
        saveTokens(try await call("/oauth/token", body, auth: false))
    }

    // MARK: Sync

    /** Brings in the Trakt watchlist (added to My List) and watched movies. Returns what was added. */
    @discardableResult
    public func sync() async throws -> String {
        try await refreshIfNeeded()
        let mine = Set(store.myList.map(\.id))
        var wanted: [Meta] = []
        for (path, type) in [("movies", "movie"), ("shows", "series")] {
            for e in try await get("/sync/watchlist/\(path)").array ?? [] {
                let item = e[type == "movie" ? "movie" : "show"]
                guard let imdb = item?["ids"]?["imdb"]?.string, !mine.contains(imdb) else { continue }
                wanted.append(Meta(id: imdb, type: type, name: item?["title"]?.string, releaseInfo: item?["year"]?.text))
            }
        }
        for m in wanted.distinct(by: \.id) { store.toggleMyList(m) }
        let watched = (try await get("/sync/watched/movies").array ?? []).compactMap { $0["movie"]?["ids"]?["imdb"]?.string }
        let fresh = store.addWatched(watched)
        return "Added \(wanted.count) from your watchlist and \(fresh) watched movies."
    }

    // MARK: Friends
    // Friends are mutual follows on Trakt. Each person's recommendations are a friends-only Trakt
    // list named "Zemu Recommendations"; Home shows what your friends put on theirs.

    public func refreshFriends() async throws {
        guard connected else { return }
        try await refreshIfNeeded()
        let friends = (try await get("/users/me/friends").array ?? []).compactMap { $0["user"] }
        hasFriends = !friends.isEmpty
        myRecs = Set(try await listItems("me").map(\.id))
        var seen: [FriendRec] = []
        for u in friends.prefix(50) {
            guard let slug = u["ids"]?["slug"]?.string else { continue }
            let full = u["name"]?.string ?? ""
            let name = (full.isEmpty ? u["username"]?.string ?? "" : full).split(separator: " ").first.map(String.init) ?? ""
            for m in (try? await listItems(slug)) ?? [] {
                if let i = seen.firstIndex(where: { $0.meta.id == m.id }) { seen[i].from.append(name) }
                else { seen.append(FriendRec(meta: m, from: [name])) }
            }
        }
        friendRecs = seen.filter { !myRecs.contains($0.meta.id) }
    }

    /** Adds [meta] to (or takes it off) your recommendations list, creating the list the first time. */
    public func recommend(_ meta: Meta, on: Bool) async throws {
        try await refreshIfNeeded()
        let ids = idsBody(["\(meta.imdbId)|\(meta.type)"])
        if on {
            if try await raw("GET", "/users/me/lists/\(recsSlug)", nil).0 == 404 {
                _ = try await post("/users/me/lists", ["name": "Zemu Recommendations", "privacy": "friends",
                                                       "description": "Titles I recommend. Friends who use Zemu see them on Home."])
            }
            _ = try await post("/users/me/lists/\(recsSlug)/items", ids)
            myRecs.insert(meta.imdbId)
        } else {
            _ = try await post("/users/me/lists/\(recsSlug)/items/remove", ids)
            myRecs.remove(meta.imdbId)
        }
    }

    /** A user's recommendations list, newest first; empty when they haven't made one. */
    private func listItems(_ user: String) async throws -> [Meta] {
        let r = try await raw("GET", "/users/\(user)/lists/\(recsSlug)/items?sort_by=added&sort_how=desc", nil)
        if r.0 == 404 { return [] }
        return (JSONValue.parse(try check(r))?.array ?? []).compactMap { e in
            let type = e["type"]?.string == "show" ? "series" : "movie"
            let item = e[type == "movie" ? "movie" : "show"]
            guard let imdb = item?["ids"]?["imdb"]?.string else { return nil }
            return Meta(id: imdb, type: type, name: item?["title"]?.string, releaseInfo: item?["year"]?.text)
        }
    }

    // MARK: Scrobbling

    /** [action]: "start", "pause" or "stop"; [videoId] is "tt…" for a movie or "tt…:season:episode". */
    public func scrobble(_ action: String, meta: Meta, videoId: String, progress: Double) {
        guard connected, meta.imdbId.hasPrefix("tt") else { return }
        let parts = videoId.split(separator: ":")
        var body: [String: Any] = ["progress": min(100, max(0, progress * 100))]
        if meta.type == "series", parts.count >= 3 {
            body["show"] = ["ids": ["imdb": meta.imdbId]]
            body["episode"] = ["season": Int(parts[1]) ?? 1, "number": Int(parts[2]) ?? 1]
        } else {
            body["movie"] = ["ids": ["imdb": meta.imdbId]]
        }
        Task { try? await refreshIfNeeded(); _ = try? await post("/scrobble/\(action)", body) }
    }

    // MARK: HTTP

    private func get(_ path: String) async throws -> JSONValue { JSONValue.parse(try check(await raw("GET", path, nil))) ?? .null }
    private func post(_ path: String, _ body: [String: Any]) async throws -> JSONValue { try await call(path, body) }
    private func call(_ path: String, _ body: [String: Any], auth: Bool = true) async throws -> JSONValue {
        JSONValue.parse(try check(await raw("POST", path, body, auth: auth))) ?? .object([:])
    }

    private func check(_ r: (Int, Data)) throws -> Data {
        guard (200..<300).contains(r.0) else { throw TraktError(message: "Trakt HTTP \(r.0)") }
        return r.1
    }

    private func raw(_ method: String, _ path: String, _ body: [String: Any]?, auth: Bool = true) async throws -> (Int, Data) {
        guard let url = URL(string: base + path) else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("2", forHTTPHeaderField: "trakt-api-version")
        req.setValue(settings.traktClientId.trimmed, forHTTPHeaderField: "trakt-api-key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if auth { req.setValue("Bearer \(settings.traktAccessToken)", forHTTPHeaderField: "Authorization") }
        if let body { req.httpBody = try JSONSerialization.data(withJSONObject: body) }
        req.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, resp) = try await HTTP.session.data(for: req)
        return ((resp as? HTTPURLResponse)?.statusCode ?? 0, data)
    }
}
