import SwiftUI
import ZemuCore

@MainActor @Observable
final class DetailsModel {
    let type: String
    let id: String
    @ObservationIgnored private unowned let s: Session

    private(set) var meta: Meta?
    private(set) var metaLoading = true
    private(set) var similar: [Scored] = []
    private(set) var genreFavorites: (String, [Scored])?
    private(set) var extras: TitleExtras?
    /** Cast with photos: TMDB when a key is set, otherwise TVmaze / Wikidata / IMDb. */
    private(set) var cast: [CastPerson] = []
    var selectedSeason: Int?
    private(set) var selectedVideo: Video?

    private(set) var streamResult: StreamLoadResult?
    private(set) var streamsLoading = false
    private(set) var externalSubs: [SubtitleTrack] = []
    @ObservationIgnored private var streamJob: Task<Void, Never>?

    /** Instant play: start the chosen stream as soon as streams for the current video load. */
    @ObservationIgnored private var autoPlayPending: Bool
    /** Set once an instant start happened (the page then closes itself if it was opened for that). */
    private(set) var autoPlayed = 0
    private(set) var autoPlayFailed = 0

    init(_ s: Session, type: String, id: String, seed: Meta?, autoPlay: Bool) {
        self.s = s
        self.type = type
        self.id = id
        self.autoPlayPending = autoPlay
        if let seed, seed.id == id { meta = seed }
        Task { await loadMeta() }
    }

    var filter: FilterState { s.streamFilter }
    func updateFilter(_ t: (inout FilterState) -> Void) { t(&s.streamFilter) }

    var externalSubLangs: Set<String> { Set(externalSubs.compactMap { Languages.normalize($0.lang) }) }

    var streams: [RankedStream] {
        StreamFilter.apply(streamResult?.cached ?? [], s.streamFilter, s.capabilities, s.settings, externalSubLangs)
    }

    var facets: [FacetKind: [FacetOption]] {
        StreamFilter.facets(streamResult?.cached ?? [], s.streamFilter, s.capabilities, s.settings, externalSubLangs)
    }

    /**
     * The stream to play: the one used last time for this title if it's still cached (same release,
     * or for series the same release group), else the recommended one.
     */
    func preferred(_ ranked: [RankedStream]) -> RankedStream? {
        let last = s.store.lastStreams[id]
        return last.flatMap { l in ranked.first { $0.stream.key == l.key } }
            ?? last?.bingeGroup.flatMap { g in ranked.first { $0.stream.raw.behaviorHints?.bingeGroup == g } }
            ?? ranked.first { $0.recommended }
            ?? ranked.first
    }

    var seasons: [Int] {
        (meta?.videos ?? []).compactMap(\.season).distinct().sorted { ($0 == 0 ? Int.max : $0) < ($1 == 0 ? Int.max : $1) }
    }

    func episodes(_ season: Int?) -> [Video] {
        (meta?.videos ?? []).filter { $0.season == season }.sorted { $0.episodeNumber < $1.episodeNumber }
    }

    func loadMeta() async {
        metaLoading = true
        let m = await s.addons.meta(type: type, id: id)
        if let m { meta = m }
        metaLoading = false
        guard let m else { return }

        if type == "series" && !m.videos.isEmpty {
            selectEpisode(resumeEpisode(m), autoPlay: autoPlayPending)
        } else {
            loadStreams(id)
        }
        Task {
            let ex = try? await s.tmdb.extras(m)
            extras = ex
            if let ex, !ex.cast.isEmpty {
                cast = ex.cast.map { CastPerson(name: $0.name, role: $0.role, photo: $0.photo, personKey: "tmdb:\($0.id)") }
            } else {
                cast = await s.freeCast.cast(m)
            }
        }
        Task {
            let seen = Set(s.store.history.map(\.meta.id))
            let like = await s.recommender.moreLikeThis(m, exclude: seen)
            similar = like
            genreFavorites = await s.recommender.genreFavorites(m, exclude: seen.union(like.map(\.meta.id)))
        }
    }

    /** Where to pick a show back up: the last episode watched, or the one after it if that was finished. */
    private func resumeEpisode(_ m: Meta) -> Video {
        let ordered = m.orderedEpisodes
        guard let last = s.store.history.first(where: { $0.meta.id == id }),
              let i = ordered.firstIndex(where: { $0.id == last.videoId }) else { return ordered.first! }
        let finished = last.durationMs > 0 && last.progress > 0.9
        return finished ? (i + 1 < ordered.count ? ordered[i + 1] : ordered[i]) : ordered[i]
    }

    /** Progress of an episode (0…1) from history, for the episode cards. */
    func progress(of v: Video) -> Double? {
        guard let e = s.store.history.first(where: { $0.meta.id == id && $0.videoId == v.id }) else { return nil }
        return e.progress
    }

    func currentVideoId() -> String { type == "series" ? (selectedVideo?.id ?? id) : id }

    func episodeLabel() -> String? { selectedVideo?.label }

    func selectEpisode(_ v: Video, autoPlay: Bool = false) {
        selectedVideo = v
        selectedSeason = v.season
        autoPlayPending = autoPlay
        loadStreams(v.id)
    }

    func reloadStreams() { loadStreams(currentVideoId(), force: true) }

    private func loadStreams(_ videoId: String, force: Bool = false) {
        streamJob?.cancel()
        streamJob = Task {
            streamsLoading = true
            streamResult = nil
            externalSubs = []
            async let subs = s.streams.subtitles(type: type, videoId: videoId)
            let result = await s.streams.load(type: type, videoId: videoId, force: force)
            if Task.isCancelled { return }
            streamResult = result
            streamsLoading = false
            externalSubs = await subs
            if autoPlayPending {
                autoPlayPending = false
                let ranked = StreamFilter.apply(result.cached, s.streamFilter, s.capabilities, s.settings, [])
                if let pick = preferred(ranked) {
                    play(pick)
                    autoPlayed += 1
                } else {
                    autoPlayFailed += 1
                }
            }
        }
    }

    func play(_ r: RankedStream) {
        guard let m = meta else { return }
        let ranked = streams.isEmpty ? StreamFilter.apply(streamResult?.cached ?? [], s.streamFilter, s.capabilities, s.settings, []) : streams
        AppModel.shared.play(meta: m, videoId: currentVideoId(), episodeLabel: episodeLabel(), stream: r.stream,
                             externalSubs: externalSubs, alternatives: ranked.map(\.stream))
    }

    func download(_ r: RankedStream) {
        guard let m = meta else { return }
        let err = Downloads.shared.start(meta: m, videoId: currentVideoId(), label: episodeLabel(), stream: r.stream)
        AppModel.shared.toast(err ?? "Downloading. Find it in Downloads.")
    }

    func matchPercent(_ m: Meta) -> Int { s.matchPercent(m) }
    var rating: Int { s.store.ratings[id] ?? 0 }
    func rate(_ v: Int) { if let m = meta { s.store.rate(m, v) } }
    var inMyList: Bool { s.store.isInMyList(id) }
    func toggleMyList() { if let m = meta { s.store.toggleMyList(m) } }
    var capabilities: DeviceCapabilities { s.capabilities }
}
