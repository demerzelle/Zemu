package com.zemu.tv.ui.details

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.zemu.tv.AppContainer
import com.zemu.tv.data.Meta
import com.zemu.tv.data.StreamLoadResult
import com.zemu.tv.data.SubtitleTrack
import com.zemu.tv.data.Video
import com.zemu.tv.recommend.Scored
import com.zemu.tv.streams.FacetKind
import com.zemu.tv.streams.FacetOption
import com.zemu.tv.streams.FilterState
import com.zemu.tv.streams.Languages
import com.zemu.tv.streams.RankedStream
import com.zemu.tv.streams.StreamFilter
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class StreamsUi(
    val loading: Boolean = false,
    val result: StreamLoadResult? = null,
    val streams: List<RankedStream> = emptyList(),
    val facets: Map<FacetKind, List<FacetOption>> = emptyMap(),
    val externalSubs: List<SubtitleTrack> = emptyList(),
    val externalSubLangs: Set<String> = emptySet(),
)

class DetailsViewModel(private val c: AppContainer, val type: String, val id: String, autoPlay: Boolean = false) : ViewModel() {
    val meta = MutableStateFlow<Meta?>(null)
    val metaLoading = MutableStateFlow(true)
    val similar = MutableStateFlow<List<Scored>>(emptyList())
    val genreFavorites = MutableStateFlow<Pair<String, List<Scored>>?>(null)
    val extras = MutableStateFlow<com.zemu.tv.data.TitleExtras?>(null)
    /** Cast with photos: TMDB when a key is set, otherwise TVmaze / Wikidata / IMDb. */
    val cast = MutableStateFlow<List<com.zemu.tv.data.CastPerson>>(emptyList())
    val selectedSeason = MutableStateFlow<Int?>(null)
    val selectedVideo = MutableStateFlow<Video?>(null)

    private val streamResult = MutableStateFlow<StreamLoadResult?>(null)
    private val streamsLoading = MutableStateFlow(false)
    private val externalSubs = MutableStateFlow<List<SubtitleTrack>>(emptyList())
    private var streamJob: Job? = null

    /** Instant play: start the chosen stream as soon as streams for the current video load. */
    private var autoPlayPending = autoPlay
    /** The stream to start right away; the screen plays it and calls [consumeAutoPlay]. */
    val autoPlay = MutableStateFlow<RankedStream?>(null)
    /** Set when instant play found nothing to play. */
    val autoPlayFailed = MutableStateFlow(false)

    fun consumeAutoPlay() { autoPlay.value = null }

    /**
     * The stream to play: the one used last time for this title if it's still cached (same release,
     * or for series the same release group), else the recommended one.
     */
    fun preferred(ranked: List<RankedStream>): RankedStream? {
        val last = c.userStore.lastStreams.value[id]
        return last?.let { l -> ranked.firstOrNull { it.stream.key == l.key } }
            ?: last?.bingeGroup?.let { g -> ranked.firstOrNull { it.stream.raw.behaviorHints?.bingeGroup == g } }
            ?: ranked.firstOrNull { it.recommended }
            ?: ranked.firstOrNull()
    }

    val filter: StateFlow<FilterState> = c.streamFilter
    val capabilities get() = c.capabilities

    val streams: StateFlow<StreamsUi> = combine(streamResult, streamsLoading, c.streamFilter, externalSubs, c.userStore.settings) { r, loading, f, subs, settings ->
        val ext = subs.mapNotNull { Languages.normalize(it.lang) }.toSet()
        val all = r?.cached.orEmpty()
        StreamsUi(
            loading = loading,
            result = r,
            streams = StreamFilter.apply(all, f, c.capabilities, settings, ext),
            facets = StreamFilter.facets(all, f, c.capabilities, settings, ext),
            externalSubs = subs,
            externalSubLangs = ext,
        )
    }.stateIn(viewModelScope, SharingStarted.Eagerly, StreamsUi(loading = true))

    val inMyList: StateFlow<Boolean> = c.userStore.myList.map { l -> l.any { it.id == id } }
        .stateIn(viewModelScope, SharingStarted.Eagerly, false)

    val inWatchLater: StateFlow<Boolean> = c.userStore.watchLater.map { l -> l.any { it.id == id } }
        .stateIn(viewModelScope, SharingStarted.Eagerly, false)

    val seasons: List<Int>
        get() = meta.value?.videos.orEmpty().mapNotNull { it.season }.distinct().sortedWith(compareBy { if (it == 0) Int.MAX_VALUE else it })

    fun episodes(season: Int?): List<Video> =
        meta.value?.videos.orEmpty().filter { it.season == season }.sortedBy { it.episodeNumber }

    init {
        loadMeta()
    }

    private fun loadMeta() = viewModelScope.launch {
        metaLoading.value = true
        val m = c.addons.meta(type, id)
        meta.value = m
        metaLoading.value = false
        if (m == null) return@launch
        launch { c.userStore.addRecentlyViewed(m) }

        if (type == "series" && m.videos.isNotEmpty()) {
            selectEpisode(resumeEpisode(m), autoPlay = autoPlayPending)
        } else {
            loadStreams(id)
        }
        launch {
            val ex = runCatching { c.tmdb.extras(m) }.getOrNull()
            extras.value = ex
            cast.value = ex?.cast?.takeIf { it.isNotEmpty() }?.map { com.zemu.tv.data.CastPerson(it.name, it.role, it.photo, "tmdb:${it.id}") }
                ?: runCatching { c.freeCast.cast(m) }.getOrDefault(m.cast.map { com.zemu.tv.data.CastPerson(it, null, null, "name:$it") })
        }
        launch {
            val seen = c.userStore.history.value.map { it.meta.id }.toSet()
            val like = runCatching { c.recommender.moreLikeThis(m, exclude = seen) }.getOrDefault(emptyList())
            similar.value = like
            genreFavorites.value = runCatching {
                c.recommender.genreFavorites(m, exclude = seen + like.map { it.meta.id })
            }.getOrNull()
        }
    }

    /** Where to pick a show back up: the last episode watched, or the one after it if that was finished. */
    fun resumeEpisode(m: Meta): Video {
        val ordered = m.videos.filter { (it.season ?: 0) > 0 }.sortedWith(compareBy({ it.season }, { it.episodeNumber }))
            .ifEmpty { m.videos }
        val last = c.userStore.history.value.firstOrNull { it.meta.id == id }
        val i = ordered.indexOfFirst { it.id == last?.videoId }
        if (i < 0 || last == null) return ordered.first()
        val finished = last.durationMs > 0 && last.progress > 0.9f
        return if (finished) ordered.getOrNull(i + 1) ?: ordered[i] else ordered[i]
    }

    fun retryMeta() = loadMeta()

    fun currentVideoId(): String = if (type == "series") selectedVideo.value?.id ?: id else id

    fun episodeLabel(): String? = selectedVideo.value?.let { v ->
        if (v.season != null) "S${v.season} E${v.episodeNumber} · ${v.displayTitle}" else v.displayTitle
    }

    fun selectSeason(season: Int) {
        selectedSeason.value = season
    }

    fun selectEpisode(video: Video, autoPlay: Boolean = false) {
        selectedVideo.value = video
        selectedSeason.value = video.season
        autoPlayPending = autoPlay
        loadStreams(video.id)
    }

    fun reloadStreams() = loadStreams(currentVideoId(), force = true)

    private fun loadStreams(videoId: String, force: Boolean = false) {
        streamJob?.cancel()
        streamJob = viewModelScope.launch {
            streamsLoading.value = true
            streamResult.value = null
            externalSubs.value = emptyList()
            launch { externalSubs.value = c.streams.subtitles(type, videoId) }
            val result = c.streams.load(type, videoId, force)
            streamResult.value = result
            streamsLoading.value = false
            if (autoPlayPending) {
                autoPlayPending = false
                val ranked = StreamFilter.apply(result.cached, c.streamFilter.value, c.capabilities, c.userStore.settings.value, emptySet())
                val pick = preferred(ranked)
                if (pick != null) autoPlay.value = pick else autoPlayFailed.value = true
            }
        }
    }

    fun updateFilter(transform: (FilterState) -> FilterState) = c.streamFilter.update(transform)

    fun matchPercent(m: Meta): Int = c.recommender.matchPercent(m, c.tasteProfile())

    fun rate(value: Int) {
        val m = meta.value ?: return
        viewModelScope.launch { c.userStore.rate(m, value) }
    }

    fun toggleMyList() {
        val m = meta.value ?: return
        viewModelScope.launch { c.userStore.toggleMyList(m) }
    }

    fun toggleWatchLater() {
        val m = meta.value ?: return
        viewModelScope.launch { c.userStore.toggleWatchLater(m) }
    }
}
