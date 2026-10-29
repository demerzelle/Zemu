import SwiftUI
import Observation
import ZemuCore

enum Section: String, CaseIterable, Identifiable {
    case search, home, movies, series, anime, mylist, downloads, addons, settings
    var id: String { rawValue }

    var label: String {
        switch self {
        case .search: "Search"; case .home: "Home"; case .movies: "Movies"; case .series: "Series"; case .anime: "Anime"
        case .mylist: "My List"; case .downloads: "Downloads"; case .addons: "Addons"; case .settings: "Settings"
        }
    }

    var icon: String {
        switch self {
        case .search: "magnifyingglass"; case .home: "house.fill"; case .movies: "film"; case .series: "tv"
        case .anime: "sparkles.tv"; case .mylist: "heart.fill"; case .downloads: "arrow.down.circle.fill"; case .addons: "puzzlepiece.extension.fill"; case .settings: "gearshape.fill"
        }
    }

    /** ⌘1…⌘9 */
    var shortcut: KeyEquivalent {
        KeyEquivalent(Character(String((Section.allCases.firstIndex(of: self) ?? 0) + 1)))
    }
}

enum Route: Hashable {
    /** [seed] shows something (poster, name) while the full meta loads. */
    case details(type: String, id: String, section: String, play: Bool, seed: Meta?)
    case person(key: String)
    /** Everything on a streaming service ([service] provider ids) or from a studio. */
    case discover(type: String, service: String?, label: String?, studio: String?)
    /** Every streaming service in your region. */
    case services(type: String)
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
    /** All of the title's official trailers; playback continues through them. */
    var queue: [TrailerRef] = []
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
    /** The video is in the Picture in Picture window. */
    var pip = false
    /** Entered PiP because the user switched apps; leave it again when they come back. */
    @ObservationIgnored var autoEnteredPiP = false
    /** Backdrop art of the title you're looking at, for the Liquid Glass background. */
    var ambient: String?
    /** Zemu is the frontmost app. Trailers only play while it is. */
    var appActive = true
    /** Paused the video because Zemu lost focus ("Pause when Zemu isn't focused"); resume on return. */
    @ObservationIgnored var pausedForFocus = false
    /** In-app menu (dropdowns and options for keyboard and gamepad). */
    var actionMenu: ActionMenuRequest?
    /** On-screen keyboard for gamepad text entry. */
    var osk: OSKRequest?
    /** "Who's watching?" Leaving a kid profile needs the parent code. */
    var picking = false {
        didSet {
            guard picking, !oldValue, profiles.kidsOn, !parentApproved else { parentApproved = false; return }
            picking = false
            whenParent("Leave this kid profile?") { [weak self] in self?.parentApproved = true; self?.picking = true }
        }
    }
    @ObservationIgnored private var parentApproved = false
    /** The parent code pad (kid profiles). */
    var parentPrompt: ParentPrompt?
    /** Settings and Addons were unlocked with the parent code (until another page opens). */
    @ObservationIgnored private var parentUnlocked = false
    /** Bumped to move keyboard focus to the search field. */
    var focusSearch = 0

    private init() {
        session = Session(profileId: profiles.activeId)
        picking = profiles.profiles.count > 1 && !profiles.skipPicker && !profiles.kidsOn
        applyTheme()
        Tracker({ [weak self] in self?.themeKey ?? "" }) { [weak self] _ in self?.applyTheme() }.keepAlive()
        // Appearance "System" follows macOS switching between light and dark.
        DistributedNotificationCenter.default().addObserver(forName: .init("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { AppModel.shared.applyTheme() }
        }
    }

    var settings: AppSettings { session.settings }

    // MARK: Theme

    private var themeKey: String {
        let s = session.settings
        return "\(s.theme)|\(s.customAccent)|\(s.customBackground)|\(s.dynamicTheme)|\(s.uiStyle)|\(s.appearance)|\(s.uiZoom)|\(s.fontSize)|\(s.font)|\(s.colorOverrides)|\(s.themeVariants)"
    }

    /** macOS is in Dark Mode (for appearance "SYSTEM"). */
    static var systemIsDark: Bool { NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) != .aqua }

    /** Applies the look: size and font, light/dark, colors with your edits, the animated scene and its sounds. */
    func applyTheme() {
        let s = session.settings
        let zoom = CGFloat(min(160, max(70, s.uiZoom))) / 100, text = CGFloat(min(160, max(70, s.fontSize))) / 100
        if P.zoom != zoom { P.zoom = zoom }
        if P.textScale != text { P.textScale = text }
        if P.fontFamily != s.font { P.fontFamily = s.font }
        var light = !s.alwaysDark && (s.appearance == "LIGHT" || (s.appearance == "SYSTEM" && !Self.systemIsDark))
        var colors = s.resolvedColors(light: light)
        if let forced = colors.forcedLight, forced != light {
            light = forced
            colors = s.resolvedColors(light: light)
        }
        if P.lightMode != light { P.lightMode = light }
        let glass = s.uiStyle == "GLASS"
        if P.glass != glass { P.glass = glass }
        if P.colors != colors { P.colors = colors }
        let d = DynamicTheme.of(s.dynamicTheme)
        let variant = d.resolveVariant(s.variant(of: d))
        if P.scene != d.style { P.scene = d.style }
        if P.sceneVariant != variant { P.sceneVariant = variant }
        SoundFx.set = s.soundPack == "theme" ? d.style.soundSet : "pack-\(s.soundPack)"
    }

    // MARK: Command palette (⌘K) and shortcuts (⌘/)

    var showPalette = false { didSet { if !showPalette { paletteQuery = ""; paletteSelection = 0 } } }
    var showShortcuts = false
    var paletteQuery = ""
    var paletteSelection = 0

    /** Every command, filtered by what's typed (each word must match). */
    var paletteItems: [ActionItem] {
        var all: [ActionItem] = Section.allCases.map { s in ActionItem(label: "Go to \(s.label)", icon: s.icon) { [weak self] in self?.go(s) } }
        all.append(ActionItem(label: "Surprise Me", icon: "dice") { [weak self] in self?.surprise() })
        all.append(ActionItem(label: "Switch Profile…", icon: "person.2") { [weak self] in self?.picking = true })
        all.append(ActionItem(label: P.light ? "Dark Mode" : "Light Mode", icon: P.light ? "moon" : "sun.max") { [weak self] in self?.toggleLight() })
        all.append(ActionItem(label: P.glass ? "Classic Look" : "Liquid Glass Look", icon: "drop") { [weak self] in self?.toggleGlass() })
        all.append(ActionItem(label: "Keyboard Shortcuts", icon: "keyboard") { [weak self] in self?.showShortcuts = true })
        all.append(ActionItem(label: "Settings", icon: "gearshape") { [weak self] in self?.go(.settings) })
        let words = paletteQuery.lowercased().split(separator: " ")
        return words.isEmpty ? all : all.filter { item in words.allSatisfy { item.label.lowercased().contains($0) } }
    }

    func paletteMove(_ by: Int) {
        let n = paletteItems.count
        guard n > 0 else { return }
        paletteSelection = (paletteSelection + by + n) % n
    }

    func paletteRun() {
        let items = paletteItems
        guard items.indices.contains(paletteSelection) else { return }
        let item = items[paletteSelection]
        showPalette = false
        item.action()
    }

    /** ⌘⇧L: light ⇄ dark (System counts as whatever macOS shows now). */
    func toggleLight() { updateLook { $0.appearance = P.light ? "DARK" : "LIGHT" } }

    /** ⌘⇧G: the experimental Liquid Glass look on or off. */
    func toggleGlass() { updateLook { $0.uiStyle = $0.uiStyle == "GLASS" ? "CLASSIC" : "GLASS" } }

    // MARK: Keep changes?

    /** The look before a theme change that's waiting on "Keep changes?"; [lookChanges] restarts its countdown. */
    var pendingLook: AppSettings?
    var lookChanges = 0

    /** A theme change from Settings: applies now, then asks "Keep changes?" and reverts unless kept in time. */
    func updateLook(_ transform: (inout AppSettings) -> Void) {
        if pendingLook == nil { pendingLook = settings }
        lookChanges += 1
        session.store.updateSettings(transform)
    }

    func keepLook() { pendingLook = nil }

    func revertLook() {
        guard let b = pendingLook else { return }
        pendingLook = nil
        session.store.updateSettings {
            $0.theme = b.theme; $0.customAccent = b.customAccent; $0.customBackground = b.customBackground; $0.dynamicTheme = b.dynamicTheme
            $0.themeVariants = b.themeVariants; $0.colorOverrides = b.colorOverrides; $0.appearance = b.appearance; $0.uiStyle = b.uiStyle
        }
    }

    // MARK: Profiles

    /** Swaps every per-profile object (settings, addons, history, ...) for the given profile's. */
    func switchProfile(_ id: String) {
        guard id != session.profileId else { picking = false; return }
        if profiles.kidsOn && !picking {
            whenParent("Leave this kid profile?") { [weak self] in self?.picking = false; self?.doSwitchProfile(id) }
            return
        }
        picking = false
        doSwitchProfile(id)
    }

    private func doSwitchProfile(_ id: String) {
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
        if profiles.kidsOn && (s == .settings || s == .addons) && !parentUnlocked {
            whenParent("Grown-ups only") { [weak self] in self?.parentUnlocked = true; self?.go(s) }
            return
        }
        if s != .settings && s != .addons { parentUnlocked = false }
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
        // Streaming service and studio rows list TMDB titles; they open as their IMDb title.
        if m.id.hasPrefix("tmdb:") {
            Task {
                guard let imdb = try? await session.tmdb.imdbFor(m.id) else { toast("Couldn't find \(m.title) in the catalog"); return }
                var seed = m
                seed.id = imdb
                push(.details(type: m.type, id: imdb, section: section, play: play, seed: seed))
            }
            return
        }
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

    // MARK: Picture in Picture

    func enterPiP(auto: Bool = false) {
        guard let p = player, !pip else { return }
        if PlayerWindow.isFullScreen && PlayerWindow.enteredFullScreen { PlayerWindow.leavePlayback() }
        pip = true
        autoEnteredPiP = auto
        PiPController.shared.show(p)
    }

    func exitPiP() {
        guard pip else { return }
        pip = false
        autoEnteredPiP = false
        PiPController.shared.close()
        NSApp.activate(ignoringOtherApps: true)
        PlayerWindow.host?.makeKeyAndOrderFront(nil)
    }

    // MARK: Card actions

    func toggleMyList(_ m: Meta) { session.store.toggleMyList(m) }
    func setWatched(_ m: Meta, _ w: Bool) { session.store.setWatched(m, w) }
    func removeFromHistory(_ m: Meta) { session.store.removeFromHistory(m.id) }

    func playTrailer(_ youtubeId: String, start: Int = 0, queue: [TrailerRef] = []) {
        trailer = TrailerRequest(youtubeId: youtubeId, start: start, queue: queue)
    }

    func openConfigure(_ url: String, name: String) {
        configure = ConfigureRequest(url: url, name: name)
    }

    // MARK: Playback

    /** Starts [stream], falling back through [alternatives] (ranked) if it can't be played. */
    func play(meta: Meta, videoId: String, episodeLabel: String?, stream: ParsedStream, externalSubs: [SubtitleTrack], alternatives: [ParsedStream] = []) {
        let s = session
        guard let url = stream.raw.url else { return }
        let resume = s.store.history.first { $0.meta.id == meta.id && $0.videoId == videoId }
            .flatMap { ($0.progress >= 0.02 && $0.progress <= 0.95) ? $0.positionMs : nil } ?? 0
        let title = [meta.title, episodeLabel].compactMap { $0 }.joined(separator: " · ")

        if settings.useExternalPlayer {
            if ExternalPlayer.open(url: url, title: title, preferred: settings.externalPlayer) {
                s.store.recordProgress(WatchEntry(meta: meta.slim(), videoId: videoId, label: episodeLabel, positionMs: resume, durationMs: 0, updatedAt: nowMs()))
                return
            }
            toast("No external player found (install IINA or VLC). Using the built-in player.")
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
    func resume(_ entry: WatchEntry, fromStart: Bool = false) {
        if resumeSaved(entry, fromStart: fromStart) { return }
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

    /**
     * Continue Watching: replays the exact file that last played, from where it stopped. False when
     * no saved file is known. If the file is gone, the player looks up cached streams itself.
     */
    @discardableResult
    func resumeSaved(_ entry: WatchEntry, fromStart: Bool = false) -> Bool {
        let s = session
        guard !settings.useExternalPlayer, let saved = s.store.lastStreams[entry.meta.id], saved.videoId == entry.videoId,
              let c = PlayCandidate(saved: saved) else { return false }
        let start = fromStart || !(0.01...0.97).contains(entry.progress) ? 0 : entry.positionMs
        Task {
            // Subtitles are usually cached from the last play; don't hold the start up for long.
            let subs = (try? await withTimeout(3) { await s.streams.subtitles(type: entry.meta.type, videoId: entry.videoId) }) ?? []
            player?.close()
            player = PlayerModel(session: s, meta: entry.meta, videoId: entry.videoId, label: entry.label, candidates: [c],
                                 subtitles: PlayerModel.pickSubtitles(subs, preferred: settings.subtitleLanguages), startMs: start, savedFile: true)
        }
        return true
    }

    /** "Surprise me": plays a random unwatched title from your best matches. */
    func surprise() {
        guard let m = session.home.surprise() else {
            go(.home)
            toast("Still loading suggestions…")
            return
        }
        openDetails(m, play: true)
    }

    // MARK: Links

    /** stremio:// addon links and zemu://details/{type}/{id}. */
    func handleURL(_ url: URL) {
        let s = url.absoluteString
        if url.scheme == "zemu" {
            let parts = url.pathComponents.filter { $0 != "/" }
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
