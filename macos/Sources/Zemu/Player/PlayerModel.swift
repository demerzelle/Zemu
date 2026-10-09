import AppKit
import Observation
import ZemuCore

/** One playable stream handed to the player; the player falls back through them in order. */
struct PlayCandidate: Hashable {
    let url: String
    let label: String
    let headers: [String: String]
    /** Addon hint that streams with the same value come from the same release (used for next episode). */
    let bingeGroup: String?

    init(_ s: ParsedStream) {
        url = s.raw.url ?? ""
        label = [s.resolutionLabel, s.sizeLabel, s.addonName].compactMap { $0 }.joined(separator: " · ")
        headers = s.raw.behaviorHints?.proxyHeaders?.request ?? [:]
        bingeGroup = s.raw.behaviorHints?.bingeGroup
    }
}

/** Shown when every stream and fallback failed. */
struct PlaybackFailure: Equatable {
    let detail: String
    let positionMs: Int64
}

/**
 * The built-in player's state and logic (port of the Android PlayerActivity): stream fallback,
 * resume, skip intro/credits, next-episode countdown, "still watching?", tracks and progress.
 */
@MainActor @Observable
final class PlayerModel {
    static let maxCandidates = 5
    private static let scrubSteps = [10, 10, 15, 30, 45, 60]
    /** Show the "Next episode" card this long before the end (roughly where credits start). */
    private static let nextUpLeadMs: Int64 = 40_000
    /** A stream that hasn't started after this long is treated as dead. */
    private static let loadTimeout: Double = 45

    @ObservationIgnored let session: Session
    private(set) var meta: Meta
    private(set) var videoId: String
    private(set) var label: String?
    @ObservationIgnored private var candidates: [PlayCandidate]
    @ObservationIgnored private var subs: [SubtitleTrack]
    @ObservationIgnored private var index = 0
    @ObservationIgnored private var resumeMs: Int64

    private(set) var engine: PlaybackEngine
    private(set) var streamLabel = ""
    private(set) var isPlaying = false
    private(set) var buffering = true
    private(set) var positionMs: Int64 = 0
    private(set) var durationMs: Int64 = 0
    private(set) var bufferedMs: Int64 = 0
    private(set) var videoSize: CGSize?
    private(set) var speed: Double = 1
    private(set) var volume: Double
    private(set) var muted = false
    private(set) var tracksVersion = 0
    /** Where a pending scrub will seek to; nil when not scrubbing. */
    private(set) var scrubTargetMs: Int64?

    private(set) var nextUp: Video?
    /** Recommended title to play when there's no next episode. */
    private(set) var nextTitle: Meta?
    /** Seconds left on the "Next episode" countdown, or nil when the card isn't showing. */
    private(set) var countdown: Int?
    private(set) var stillWatchingPrompt = false
    private(set) var activeSegment: Segment?
    private(set) var failure: PlaybackFailure?
    /** One-line notices shown over the video ("Trying the next stream…"). */
    private(set) var notice: String?
    /** On-screen controls; they hide after a few idle seconds while playing. */
    private(set) var controlsVisible = true
    var subtitleStyleOpen = false
    @ObservationIgnored private var hideTask: Task<Void, Never>?

    @ObservationIgnored private var episodes: [Video] = []
    @ObservationIgnored private var softwareDecoding: Bool
    @ObservationIgnored private var reachedReady = false
    @ObservationIgnored private var countdownCancelled = false
    @ObservationIgnored private var countdownTask: Task<Void, Never>?
    @ObservationIgnored private var scrubTask: Task<Void, Never>?
    @ObservationIgnored private var loadTimer: Task<Void, Never>?
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private var noticeTask: Task<Void, Never>?
    @ObservationIgnored private var autoAdvances = 0
    @ObservationIgnored private var scrubStreak = 0
    @ObservationIgnored private var lastScrubAt = Date.distantPast
    @ObservationIgnored private var lastScrubDir = 0
    @ObservationIgnored private var segments: [Segment] = []
    @ObservationIgnored private var segmentsFor: String?
    @ObservationIgnored private var dismissedSegment: Segment?
    @ObservationIgnored private var recommendationRequested = false
    @ObservationIgnored private var closed = false
    @ObservationIgnored private var lastSave = Date()

    init(session: Session, meta: Meta, videoId: String, label: String?, candidates: [PlayCandidate], subtitles: [SubtitleTrack], startMs: Int64) {
        self.session = session
        self.meta = meta
        self.videoId = videoId
        self.label = label
        self.candidates = candidates
        self.subs = subtitles
        self.resumeMs = startMs
        let s = session.settings
        softwareDecoding = s.preferSoftwareDecoders
        volume = s.volume
        engine = MPV.available ? MPV() : AVEngine()
        start(at: startMs)
        loadEpisodes()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                self?.tick()
            }
        }
        Integrations.shared.playbackStarted(self)
    }

    var title: String { meta.title }
    var upNext: Video? { nextUp ?? nextTitle.map(videoFor) }
    var aspect: AspectMode { AspectMode(rawValue: session.settings.aspectMode) ?? .FIT }
    var engineName: String { engine.name }

    private func videoFor(_ t: Meta) -> Video {
        let id = t.type != "series" ? t.id : t.isAnime ? "\(t.id):1" : "\(t.id):1:1"
        return Video(id: id, title: t.name)
    }

    // MARK: Playback

    private func makeEngine() -> PlaybackEngine {
        engine.stop()
        return MPV.available ? MPV() : AVEngine()
    }

    private func start(at position: Int64, freshEngine: Bool = false) {
        reachedReady = false
        scrubTask?.cancel(); scrubTargetMs = nil
        countdownTask?.cancel(); countdown = nil
        failure = nil
        buffering = true
        if freshEngine { engine = makeEngine() }
        let candidate = candidates[index]
        streamLabel = candidate.label
        let s = session.settings
        engine.onEvent = { [weak self] e in self?.handle(e) }
        engine.load(url: candidate.url, startMs: position, subtitles: subs, options: EngineOptions(
            softwareDecoding: softwareDecoding, audioLanguages: s.audioLanguages, subtitleLanguages: s.subtitleLanguages,
            autoSubtitles: s.autoSubtitles, headers: candidate.headers, volume: volume, speed: speed
        ))
        engine.applySubtitleStyle(s)
        engine.setAspect(aspect)
        engine.setMuted(muted)
        loadTimer?.cancel()
        loadTimer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.loadTimeout * 1e9))
            guard let self, !Task.isCancelled, !self.reachedReady else { return }
            self.handleError("The stream didn't start within \(Int(Self.loadTimeout)) seconds", fatal: true)
        }
    }

    private func handle(_ e: EngineEvent) {
        switch e {
        case .loaded:
            break
        case let .position(ms, d, buf):
            positionMs = max(0, ms)
            if d > 0 { durationMs = d }
            bufferedMs = buf
            if ms > 0 && !reachedReady {
                reachedReady = true
                loadTimer?.cancel()
                buffering = false
                rememberWorkingMode()
                loadSegments()
            }
        case .paused(let p):
            isPlaying = !p
            if p { showControls() }
            Integrations.shared.updateNowPlaying(self)
        case .buffering(let b):
            buffering = b
        case .tracksChanged:
            tracksVersion += 1
        case .videoSize(let s):
            videoSize = s
        case .ended:
            onEnded()
        case let .failed(msg, fatal):
            handleError(msg, fatal: fatal)
        }
    }

    func togglePlay() {
        if failure != nil { return }
        engine.setPaused(isPlaying)
        noteInteraction()
    }

    func setPaused(_ p: Bool) { engine.setPaused(p) }

    func seekBy(_ deltaMs: Int64) {
        let target = max(0, min(positionMs + deltaMs, max(durationMs - 1000, 0)))
        engine.seek(toMs: target, exact: false)
        positionMs = target
        noteInteraction()
    }

    func seek(toFraction f: Double) {
        guard durationMs > 0 else { return }
        let target = Int64(Double(durationMs) * max(0, min(1, f)))
        engine.seek(toMs: target, exact: false)
        positionMs = target
        noteInteraction()
    }

    /**
     * Arrow-key scrubbing. The step grows from 10 s to 60 s the longer the key is held or the
     * faster it's pressed, and the seek happens once you stop, so the stream doesn't rebuffer on
     * every press.
     */
    func scrub(_ direction: Int, isRepeat: Bool) {
        let now = Date()
        scrubStreak = direction == lastScrubDir && now.timeIntervalSince(lastScrubAt) < 0.7 ? scrubStreak + 1 : 0
        lastScrubAt = now
        lastScrubDir = direction
        let level = scrubStreak / (isRepeat ? 4 : 2)
        let step = Self.scrubSteps[min(level, Self.scrubSteps.count - 1)]
        let base = scrubTargetMs ?? positionMs
        let limit = durationMs > 0 ? durationMs - 1000 : Int64.max
        let target = max(0, min(base + Int64(direction * step) * 1000, max(limit, 0)))
        scrubTargetMs = target
        scrubTask?.cancel()
        scrubTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard let self, !Task.isCancelled else { return }
            self.engine.seek(toMs: target, exact: false)
            self.positionMs = target
            self.scrubTargetMs = nil
        }
        noteInteraction()
    }

    func changeSpeed(_ value: Double) {
        speed = value
        engine.setSpeed(value)
    }

    func setVolume(_ v: Double) {
        volume = max(0, min(130, v))
        engine.setVolume(volume)
        if muted && volume > 0 { toggleMute() }
        session.store.updateSettings { $0.volume = min(100, self.volume) }
    }

    func toggleMute() {
        muted.toggle()
        engine.setMuted(muted)
    }

    func setAspect(_ m: AspectMode) {
        session.store.updateSettings { $0.aspectMode = m.rawValue }
        engine.setAspect(m)
    }

    func cycleAspect() {
        let all = AspectMode.allCases
        let next = all[(all.firstIndex(of: aspect)! + 1) % all.count]
        setAspect(next)
        flash("Picture: \(next.label)")
    }

    func applySubtitleStyle() { engine.applySubtitleStyle(session.settings) }

    func adjustSubtitleDelay(_ delta: Double) {
        session.store.updateSettings { $0.subtitleDelay = (($0.subtitleDelay + delta) * 10).rounded() / 10 }
        applySubtitleStyle()
        flash(String(format: "Subtitle delay: %+.1f s", session.settings.subtitleDelay))
    }

    // MARK: Tracks

    func audioTracks() -> [TrackInfo] { _ = tracksVersion; return dedupe(engine.tracks().filter { $0.kind == .audio }) }
    func subtitleTracks() -> [TrackInfo] { _ = tracksVersion; return dedupe(engine.tracks().filter { $0.kind == .sub }) }

    /** "English (external)" twice is ambiguous; number repeats. */
    private func dedupe(_ list: [TrackInfo]) -> [TrackInfo] {
        var counts: [String: Int] = [:]
        list.forEach { counts[$0.label, default: 0] += 1 }
        var seen: [String: Int] = [:]
        return list.map { t in
            guard counts[t.label]! > 1 else { return t }
            seen[t.label, default: 0] += 1
            var c = t
            c.label = "\(t.label) \(seen[t.label]!)"
            return c
        }
    }

    func select(_ t: TrackInfo?, kind: TrackKind) {
        engine.select(t, kind: kind)
        tracksVersion += 1
    }

    var currentAudioLabel: String { audioTracks().first(where: \.selected)?.label ?? "Default" }
    var currentSubtitleLabel: String { subtitleTracks().first(where: \.selected)?.label ?? "Off" }

    /** Selects the next audio track (wrapping) and says which. */
    func cycleAudio() {
        let options = audioTracks()
        guard options.count > 1 else { flash(options.first?.label ?? "No other audio tracks"); return }
        let next = options[((options.firstIndex(where: \.selected) ?? -1) + 1) % options.count]
        select(next, kind: .audio)
        flash("Audio: \(next.label)")
    }

    /** Off → each subtitle language in turn → Off. */
    func cycleSubtitles() {
        let tracks = subtitleTracks()
        guard !tracks.isEmpty else { flash("No subtitles found"); return }
        let languages = tracks.map { $0.lang ?? "und:\($0.id)" }.distinct()
        let current = tracks.first(where: \.selected).map { $0.lang ?? "und:\($0.id)" }
        let nextLang: String? = current == nil ? languages.first : languages.firstIndex(of: current!).flatMap { $0 + 1 < languages.count ? languages[$0 + 1] : nil }
        guard let nextLang, let t = tracks.first(where: { ($0.lang ?? "und:\($0.id)") == nextLang }) else {
            select(nil, kind: .sub)
            flash("Subtitles off")
            return
        }
        select(t, kind: .sub)
        flash("Subtitles: \(t.label)")
    }

    /** Loads a subtitle file from disk (drag & drop or File → Add Subtitle File…). */
    func addSubtitleFile(_ url: URL) {
        if let mpv = engine as? MPV {
            mpv.command(["sub-add", url.path, "select", url.deletingPathExtension().lastPathComponent])
            tracksVersion += 1
            flash("Subtitles: \(url.lastPathComponent)")
        } else {
            flash("Subtitle files need the mpv engine")
        }
    }

    // MARK: Screenshots

    func saveFrame() {
        let dir = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0].appendingPathComponent("Zemu", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = "\(meta.title)\(label.map { " \($0)" } ?? "") \(Self.formatTime(positionMs)).png"
            .replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: ".")
        let url = dir.appendingPathComponent(name)
        flash(engine.screenshot(to: url) ? "Saved to Pictures/Zemu" : "Couldn't save the frame")
    }

    // MARK: Notices

    func flash(_ text: String) {
        notice = text
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if !Task.isCancelled { self?.notice = nil }
        }
    }

    /** Any keyboard, mouse or gamepad input means someone is watching. */
    func noteInteraction() { autoAdvances = 0 }

    // MARK: Controls visibility

    func showControls() {
        if !controlsVisible { controlsVisible = true }
        noteInteraction()
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard let self, !Task.isCancelled, self.isPlaying, !self.subtitleStyleOpen, AppModel.shared.actionMenu == nil else { return }
            self.hideControls()
        }
    }

    func hideControls() {
        hideTask?.cancel()
        controlsVisible = false
        subtitleStyleOpen = false
        if FocusEngine.shared.focused?.scope == "player" { FocusEngine.shared.clear() }
        NSCursor.setHiddenUntilMouseMoves(true)
    }

    /** Shows the controls with keyboard/gamepad focus on Play (like OK on the TV remote). */
    func openControlsMenu() {
        showControls()
        FocusEngine.shared.focusPreferred(scope: "player")
    }

    var speedLabel: String { speed == 1 ? "Normal" : String(format: speed == speed.rounded() ? "%.0fx" : "%gx", speed) }

    // MARK: Ticking

    private func tick() {
        guard !closed else { return }
        updateActiveSegment()
        maybeShowNextUp()
        if Date().timeIntervalSince(lastSave) > 15 && isPlaying {
            lastSave = Date()
            saveProgress()
            Integrations.shared.updateNowPlaying(self)
        }
    }

    // MARK: Skip intro / recap / credits

    private func loadSegments() {
        guard segmentsFor != videoId, session.settings.skipIntroButton else { return }
        segmentsFor = videoId
        let forVideo = videoId
        let parts = videoId.components(separatedBy: ":")
        let season = parts.count > 1 ? Int(parts[1]) : nil
        let episode = parts.count > 2 ? Int(parts[2]) : nil
        let m = meta, d = durationMs
        Task {
            let found = await session.skipSegments.find(m, videoId: forVideo, season: season, episode: episode, durationMs: d)
            if videoId == forVideo { segments = found }
        }
    }

    private func updateActiveSegment() {
        let pos = positionMs
        let autoNext = session.settings.autoplayNext
        let seg = segments.first { s in
            let end = s.endMs ?? durationMs
            // Credits with a next episode get the "Next episode" card instead.
            return pos >= s.startMs && pos < end - 1000 && !(s.type == .credits && nextUp != nil && autoNext)
        }
        let shown = seg == dismissedSegment ? nil : seg
        if shown != activeSegment { activeSegment = shown }
    }

    func skipSegment() {
        guard let seg = activeSegment else { return }
        if let end = seg.endMs, !(durationMs > 0 && end >= durationMs - 2000) {
            engine.seek(toMs: end, exact: false)
            positionMs = end
        } else {
            // Credits run to the end: move on rather than sitting on a black screen.
            if nextUp != nil { playNextNow() } else { engine.seek(toMs: max(durationMs - 500, 0), exact: false) }
        }
        dismissedSegment = seg
        activeSegment = nil
    }

    func dismissSegment() {
        dismissedSegment = activeSegment
        activeSegment = nil
    }

    // MARK: Next episode / autoplay

    private func loadEpisodes() {
        guard meta.type == "series" else { return }
        let id = meta.id
        Task {
            guard let full = await session.addons.meta(type: "series", id: id), meta.id == id else { return }
            episodes = full.videos
            nextUp = findNext()
        }
    }

    private func findNext() -> Video? {
        guard let current = episodes.first(where: { $0.id == videoId }) else { return nil }
        let special = (current.season ?? 0) == 0
        let sorted = episodes.filter { (($0.season ?? 0) == 0) == special }.sorted { ($0.season ?? 0, $0.episodeNumber) < ($1.season ?? 0, $1.episodeNumber) }
        guard let i = sorted.firstIndex(where: { $0.id == videoId }), i + 1 < sorted.count else { return nil }
        let next = sorted[i + 1]
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let today = f.string(from: Date())
        if let r = next.released, r.count >= 10, String(r.prefix(10)) > today { return nil }
        return next
    }

    /** Near the end of a movie or a series' last episode, pick a similar unwatched title. */
    private func requestRecommendation() {
        guard !recommendationRequested, nextUp == nil, session.settings.autoplaySimilar, !isAdHoc else { return }
        guard durationMs > 0, durationMs - positionMs <= 4 * 60_000 else { return }
        if meta.type == "series" && episodes.isEmpty { return } // still loading, or a next episode may exist
        recommendationRequested = true
        let m = meta
        Task {
            let store = session.store
            let seen = store.watched.union(store.history.map(\.meta.id)).union([m.id]).union(store.ratings.filter { $0.value < 0 }.keys)
            let recs = await session.recommender.moreLikeThis(m, exclude: seen, limit: 10)
            nextTitle = recs.first { $0.meta.isImdb || $0.meta.isAnime }?.meta
        }
    }

    private func maybeShowNextUp() {
        requestRecommendation()
        guard let next = upNext else { return }
        let s = session.settings
        guard s.autoplayNext, !countdownCancelled, countdown == nil, !stillWatchingPrompt, durationMs > 0 else { return }
        // Start at the credits when we know where they are, otherwise shortly before the end.
        if let creditsAt = segments.first(where: { $0.type == .credits && $0.startMs > durationMs / 2 })?.startMs {
            if positionMs < creditsAt { return }
        } else if durationMs - positionMs > Self.nextUpLeadMs { return }
        startCountdown(next, seconds: s.autoplayCountdownSec)
    }

    private func startCountdown(_ next: Video, seconds: Int) {
        countdownTask?.cancel()
        countdown = seconds
        countdownTask = Task { [weak self] in
            while let self, let c = self.countdown, c > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                if self.isPlaying || self.positionMs >= self.durationMs - 1500 { self.countdown = (self.countdown ?? 0) - 1 }
            }
            guard let self, !Task.isCancelled, self.countdown != nil else { return }
            self.advance(next, automatic: true)
        }
    }

    func cancelCountdown() {
        countdownTask?.cancel()
        countdown = nil
        countdownCancelled = true
    }

    func playNextNow() {
        guard let next = upNext else { return }
        countdownTask?.cancel()
        advance(next, automatic: false)
    }

    private func onEnded() {
        saveProgress()
        if let next = upNext, session.settings.autoplayNext, !countdownCancelled {
            if countdown == nil { startCountdown(next, seconds: 0) }
        } else {
            close()
        }
    }

    private func advance(_ next: Video, automatic: Bool) {
        countdown = nil
        let s = session.settings
        if automatic && s.stillWatchingPrompt && autoAdvances + 1 > s.stillWatchingEpisodes {
            engine.setPaused(true)
            stillWatchingPrompt = true
            return
        }
        if automatic { autoAdvances += 1 } else { autoAdvances = 0 }
        loadEpisode(next)
    }

    func answerStillWatching(_ keepWatching: Bool, dontAskAgain: Bool = false) {
        stillWatchingPrompt = false
        autoAdvances = 0
        if dontAskAgain { session.store.updateSettings { $0.stillWatchingPrompt = false } }
        guard keepWatching, let next = upNext else { close(); return }
        loadEpisode(next)
    }

    private func loadEpisode(_ next: Video) {
        saveProgress()
        let switching = nextUp == nil && nextTitle != nil
        Task {
            if switching, let t = nextTitle {
                // Moving on to a recommended title: load its full details (episodes for series).
                meta = (await session.addons.meta(type: t.type, id: t.id) ?? t).slim()
                episodes = (await session.addons.meta(type: t.type, id: t.id))?.videos ?? []
                nextTitle = nil
                recommendationRequested = false
            }
            let m = meta
            flash("Loading \(next.label)…")
            let result = await session.streams.load(type: m.type, videoId: next.id)
            let s = session.settings
            var filtered = StreamFilter.apply(result.cached, session.streamFilter, session.capabilities, s, []).map(\.stream)
            if filtered.isEmpty { filtered = StreamFilter.apply(result.cached, FilterState(), session.capabilities, s, []).map(\.stream) }
            guard !filtered.isEmpty else {
                AppModel.shared.toast("No cached streams for \(next.label) yet")
                close()
                return
            }
            // Same release group first, so quality and audio don't jump between episodes.
            let group = candidates.indices.contains(index) ? candidates[index].bingeGroup : nil
            let ordered = group == nil ? filtered : filtered.stableSorted { ($0.raw.behaviorHints?.bingeGroup == group ? 1 : 0) > ($1.raw.behaviorHints?.bingeGroup == group ? 1 : 0) }
            candidates = ordered.prefix(Self.maxCandidates).map(PlayCandidate.init)
            subs = Self.pickSubtitles(await session.streams.subtitles(type: m.type, videoId: next.id), preferred: s.subtitleLanguages)
            videoId = next.id
            segments = []; segmentsFor = nil; activeSegment = nil; dismissedSegment = nil
            let ep = episodes.first { $0.id == next.id } ?? next
            label = switching && m.type != "series" ? nil : ep.label
            index = 0
            softwareDecoding = s.preferSoftwareDecoders
            countdownCancelled = false
            positionMs = 0; durationMs = 0
            session.store.rememberStream(m.id, LastStream(key: ordered.first?.key ?? "", bingeGroup: ordered.first?.raw.behaviorHints?.bingeGroup))
            start(at: 0)
            nextUp = findNext()
            Integrations.shared.updateNowPlaying(self)
        }
    }

    // MARK: Errors / fallback

    private func handleError(_ message: String, fatal: Bool) {
        guard !closed else { return }
        loadTimer?.cancel()
        let position = positionMs > 0 ? positionMs : resumeMs
        // Hardware decoding problems: retry this stream with software decoding once.
        if !fatal && !softwareDecoding && engine is MPV {
            softwareDecoding = true
            flash("Couldn't decode (\(message)). Retrying with software decoding…")
            start(at: position)
            return
        }
        if index + 1 < candidates.count {
            index += 1
            softwareDecoding = session.settings.preferSoftwareDecoders
            flash("Stream failed (\(message)). Trying the next one: \(candidates[index].label)")
            start(at: position, freshEngine: true)
            return
        }
        engine.setPaused(true)
        failure = PlaybackFailure(detail: "Tried \(candidates.count) stream(s) with \(engine.name).\n\n\(message)", positionMs: position)
    }

    func retry() {
        guard let f = failure else { return }
        index = 0
        softwareDecoding = session.settings.preferSoftwareDecoders
        start(at: f.positionMs, freshEngine: true)
    }

    func openExternally() {
        let url = candidates[index].url
        if !ExternalPlayer.open(url: url, title: title, preferred: session.settings.externalPlayer) {
            AppModel.shared.toast("Install IINA or VLC to use an external player")
            return
        }
        close()
    }

    func copyStreamURL() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(candidates[index].url, forType: .string)
        flash("Stream link copied")
    }

    private func rememberWorkingMode() {
        guard softwareDecoding && !session.settings.preferSoftwareDecoders else { return }
        session.store.updateSettings { $0.preferSoftwareDecoders = true }
        flash("Playing. Zemu will now prefer software decoding (change in Settings → Playback).")
    }

    // MARK: Likes / My List

    func rate(_ value: Int) { session.store.rate(meta, value) }
    func toggleMyList() { session.store.toggleMyList(meta) }
    var rating: Int { session.store.ratings[meta.id] ?? 0 }
    var inMyList: Bool { session.store.isInMyList(meta.id) }

    // MARK: Lifecycle

    /** A link opened with File → Open Stream URL: no history, no recommendations. */
    private var isAdHoc: Bool { meta.id.hasPrefix("url:") }

    private func saveProgress() {
        guard durationMs > 0, reachedReady, !isAdHoc else { return }
        session.store.recordProgress(WatchEntry(meta: meta, videoId: videoId, label: label, positionMs: positionMs, durationMs: durationMs, updatedAt: nowMs()))
    }

    func close() {
        guard !closed else { return }
        saveProgress()
        closed = true
        tickTask?.cancel(); countdownTask?.cancel(); scrubTask?.cancel(); loadTimer?.cancel()
        hideTask?.cancel()
        engine.stop()
        Integrations.shared.playbackStopped(self)
        if AppModel.shared.pip && AppModel.shared.player === self {
            AppModel.shared.pip = false
            PiPController.shared.close()
        }
        if AppModel.shared.player === self { AppModel.shared.player = nil }
    }

    // MARK: Helpers

    /**
     * Side-loaded subtitles are fetched by the player, so only pass a couple per preferred
     * language.
     */
    static func pickSubtitles(_ all: [SubtitleTrack], preferred: [String]) -> [SubtitleTrack] {
        let langs = preferred.isEmpty ? ["en"] : preferred
        let picked = langs.flatMap { lang in all.filter { Languages.normalize($0.lang) == lang }.prefix(2) }.prefix(8)
        if !picked.isEmpty { return Array(picked) }
        // Nothing in a preferred language: offer English plus a few others rather than nothing.
        let byLang = Dictionary(grouping: all) { Languages.normalize($0.lang) ?? $0.lang }
        let order = (["en"] + all.map { Languages.normalize($0.lang) ?? $0.lang }).distinct().filter { byLang[$0] != nil }
        return order.prefix(4).compactMap { byLang[$0]?.first }
    }

    static func formatTime(_ ms: Int64) -> String {
        let total = max(0, ms / 1000)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
