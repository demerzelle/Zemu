import SwiftUI
import Observation
import ZemuCore

enum Section: String, CaseIterable, Identifiable {
    case search, home, movies, series, anime, mylist, addons, settings
    var id: String { rawValue }

    var label: String {
        switch self {
        case .search: "Search"; case .home: "Home"; case .movies: "Movies"; case .series: "Series"; case .anime: "Anime"
        case .mylist: "My List"; case .addons: "Addons"; case .settings: "Settings"
        }
    }

    var icon: String {
        switch self {
        case .search: "magnifyingglass"; case .home: "house.fill"; case .movies: "film"; case .series: "tv"
        case .anime: "sparkles.tv"; case .mylist: "heart.fill"; case .addons: "puzzlepiece.extension.fill"; case .settings: "gearshape.fill"
        }
    }

}

enum Route: Hashable {
    /** [seed] shows something (poster, name) while the full meta loads. */
    case details(type: String, id: String, section: String, play: Bool, seed: Meta?)
    case person(key: String)
}

struct Toast: Identifiable, Equatable {
    let id = UUID()
    let text: String
}

/** A request to play a YouTube trailer full screen. */
struct TrailerRequest: Identifiable, Equatable {
    let id = UUID()
    let youtubeId: String
    let start: Int
}

/** An addon's configure page to open in the in-app browser. */
struct ConfigureRequest: Identifiable, Equatable {
    let id = UUID()
    let url: String
    let name: String
}

@MainActor @Observable
final class AppModel {
    static let shared = AppModel()

    let profiles = ProfileStore()
    private(set) var session: Session

    var section: Section = .home
    var stack: [Route] = []
    var player: PlayerModel?
    var trailer: TrailerRequest?
    var configure: ConfigureRequest?
    var toasts: [Toast] = []
    /** In-app menu (dropdowns and options). */
    var actionMenu: ActionMenuRequest?
    /** "Who's watching?" */
    var picking = false
    /** Bumped to move keyboard focus to the search field. */
    var focusSearch = 0

    private init() {
        session = Session(profileId: profiles.activeId)
        picking = profiles.profiles.count > 1 && !profiles.skipPicker
        applyTheme()
        Tracker({ [weak self] in self?.themeKey ?? "" }) { [weak self] _ in self?.applyTheme() }.keepAlive()
    }

    var settings: AppSettings { session.settings }

    // MARK: Theme

    private var themeKey: String {
        let s = session.settings
        return "\(s.theme)|\(s.customAccent)|\(s.customBackground)|\(s.dynamicTheme)"
    }

    private func applyTheme() {
        let s = session.settings
        let colors = DynamicTheme.of(s.dynamicTheme).apply(to: s.themeColors)
        if P.colors != colors { P.colors = colors }
        let style = s.theme == ThemePreset.custom ? .solid : (ThemePreset(rawValue: s.theme) ?? .CLASSIC).style
        if P.style != style { P.style = style }
    }

    // MARK: Profiles

    /** Swaps every per-profile object (settings, addons, history, ...) for the given profile's. */
    func switchProfile(_ id: String) {
        picking = false
        guard id != session.profileId else { return }
        player?.close()
        profiles.setActive(id)
        session.close()
        session = Session(profileId: id)
        section = .home
        stack = []
        applyTheme()
    }

    /** Recreates the current profile's session (after importing a backup). */
    func reloadSession() {
        player?.close()
        let id = session.profileId
        session.close()
        session = Session(profileId: id)
        stack = []
        applyTheme()
    }

    // MARK: Navigation

    var route: Route? { stack.last }

    func go(_ s: Section) {
        section = s
        stack = []
        if s == .search { focusSearch += 1 }
    }

    func back() {
        if !stack.isEmpty { stack.removeLast() }
    }

    func push(_ r: Route) {
        if stack.last != r { stack.append(r) }
    }

    /** Selecting a title: its page, or straight to playback with Instant play on. */
    func open(_ m: Meta) { openDetails(m, play: settings.instantPlay) }

    func openDetails(_ m: Meta, section: String = "", play: Bool = false) {
        push(.details(type: m.type, id: m.id, section: section, play: play, seed: m))
    }

    func openDetails(type: String, id: String) {
        push(.details(type: type, id: id, section: "", play: false, seed: nil))
    }

    func openPerson(_ key: String) { push(.person(key: key)) }

    // MARK: Messages

    func toast(_ text: String) {
        let t = Toast(text: text)
        withAnimation(.easeOut(duration: 0.2)) { toasts.append(t) }
        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            withAnimation(.easeIn(duration: 0.3)) { toasts.removeAll { $0.id == t.id } }
        }
    }

    // MARK: Menus

    func showMenu(_ title: String, _ items: @escaping () -> [ActionItem]) {
        actionMenu = ActionMenuRequest(title: title, items: items)
    }

    func showCardMenu(_ m: Meta) { showMenu(m.title) { cardMenuItems(m) } }

    // MARK: Card actions

    func toggleMyList(_ m: Meta) { session.store.toggleMyList(m) }
    func setWatched(_ m: Meta, _ w: Bool) { session.store.setWatched(m, w) }
    func removeFromHistory(_ m: Meta) { session.store.removeFromHistory(m.id) }

    func playTrailer(_ youtubeId: String, start: Int = 0) {
        trailer = TrailerRequest(youtubeId: youtubeId, start: start)
    }

    func openConfigure(_ url: String, name: String) {
        configure = ConfigureRequest(url: url, name: name)
    }

    // MARK: Playback

    /** Starts [stream], falling back through [alternatives] (ranked) if it can't be played. */
    func play(meta: Meta, videoId: String, episodeLabel: String?, stream: ParsedStream, externalSubs: [SubtitleTrack], alternatives: [ParsedStream] = []) {
        let s = session
        guard let url = stream.raw.url else { return }
        s.store.rememberStream(meta.id, LastStream(key: stream.key, bingeGroup: stream.raw.behaviorHints?.bingeGroup))
        let resume = s.store.history.first { $0.meta.id == meta.id && $0.videoId == videoId }
            .flatMap { ($0.progress >= 0.02 && $0.progress <= 0.95) ? $0.positionMs : nil } ?? 0
        let title = [meta.title, episodeLabel].compactMap { $0 }.joined(separator: " · ")

        if settings.useExternalPlayer {
            if ExternalPlayer.open(url: url, title: title, preferred: settings.externalPlayer) {
                s.store.recordProgress(WatchEntry(meta: meta.slim(), videoId: videoId, label: episodeLabel, positionMs: resume, durationMs: 0, updatedAt: nowMs()))
                return
            }
            toast("No external player found (install VLC, Infuse or Outplayer). Using the built-in player.")
        }

        let candidates = ([stream] + alternatives.filter { $0.key != stream.key && $0.raw.url != nil })
            .prefix(PlayerModel.maxCandidates)
            .map(PlayCandidate.init)
        player?.close()
        player = PlayerModel(
            session: s, meta: meta.slim(), videoId: videoId, label: episodeLabel,
            candidates: Array(candidates),
            subtitles: PlayerModel.pickSubtitles(externalSubs, preferred: settings.subtitleLanguages),
            startMs: resume
        )
    }

    /** Plays any direct video link (File → Open Stream URL…). */
    func playURL(_ raw: String) {
        let url = raw.trimmed
        guard url.hasPrefix("http://") || url.hasPrefix("https://") || url.hasPrefix("file://") else {
            toast("That isn't a video link")
            return
        }
        let name = URL(string: url)?.lastPathComponent.removingPercentEncoding ?? url
        let stream = StreamParser.parse(Stream(name: "Link", url: url, behaviorHints: StreamBehaviorHints(filename: name)), addonName: "Link", trustDirectLinks: true)
        player?.close()
        player = PlayerModel(session: session, meta: Meta(id: "url:\(stableHash(url))", type: "movie", name: name), videoId: "url",
                             label: nil, candidates: [PlayCandidate(stream)], subtitles: [], startMs: 0)
    }

    /** Resumes a Continue Watching entry: loads streams and plays the best (or last used) one. */
    func resume(_ entry: WatchEntry) {
        Task {
            let s = session
            let meta = await s.addons.meta(type: entry.meta.type, id: entry.meta.id) ?? entry.meta
            let r = await s.streams.load(type: meta.type, videoId: entry.videoId)
            let ranked = StreamFilter.apply(r.cached, s.streamFilter, s.capabilities, s.settings, [])
            let last = s.store.lastStreams[meta.id]
            guard let pick = ranked.first(where: { $0.stream.key == last?.key })
                ?? ranked.first(where: { last?.bingeGroup != nil && $0.stream.raw.behaviorHints?.bingeGroup == last?.bingeGroup })
                ?? ranked.first else {
                openDetails(meta)
                toast("No cached streams to resume right away")
                return
            }
            let subs = await s.streams.subtitles(type: meta.type, videoId: entry.videoId)
            play(meta: meta, videoId: entry.videoId, episodeLabel: entry.label, stream: pick.stream, externalSubs: subs,
                 alternatives: ranked.map(\.stream))
        }
    }

    // MARK: Links

    /** stremio:// addon links, zemu://details/{type}/{id} and zemu://play?url=…. */
    func handleURL(_ url: URL) {
        let s = url.absoluteString
        if url.scheme == "zemu" {
            let parts = url.pathComponents.filter { $0 != "/" }
            // zemu://play?url=… plays a direct video link (the Mac's File → Open Stream URL).
            if url.host == "play", let link = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "url" })?.value {
                picking = false
                playURL(link)
                return
            }
            if url.host == "details", parts.count >= 2 {
                picking = false
                openDetails(type: parts[0], id: parts[1])
            }
            return
        }
        if url.scheme == "stremio" || s.contains("manifest.json") {
            Task {
                let msg = await session.handlePastedText(s)
                toast(msg)
                if msg.hasPrefix("Installed") { go(.addons) }
            }
        }
    }
}

extension Tracker {
    /** For app-lifetime trackers. */
    func keepAlive() { KeepAlive.objects.append(self) }
}

@MainActor enum KeepAlive { static var objects: [AnyObject] = [] }
