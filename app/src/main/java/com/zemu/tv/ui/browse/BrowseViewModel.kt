package com.zemu.tv.ui.browse

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.zemu.tv.AppContainer
import com.zemu.tv.data.Addon
import com.zemu.tv.data.Meta
import com.zemu.tv.data.rating
import com.zemu.tv.data.year
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/** A catalog the page can show, e.g. Cinemeta "top" or Kitsu "kitsu-anime-airing". */
data class BrowseCatalog(val id: String, val label: String, val paged: Boolean = true, val genres: Boolean = true)

enum class BrowseSort(val label: String) { DEFAULT("Default"), RATING("Highest rated"), MOST_FAVORITED("Most favorited"), NEWEST("Newest"), OLDEST("Oldest"), MATCH("Best match for you") }

/** Anime pages split one mixed catalog into series and movies. */
enum class AnimeSection(val label: String, val metaType: String) { SERIES("Anime Series", "series"), MOVIES("Anime Movies", "movie") }

data class BrowseFilters(
    val catalog: String = "",
    val section: AnimeSection = AnimeSection.SERIES,
    val genre: String? = null,
    val minRating: Double? = null,
    /** Decade start year, e.g. 1990. -1 = before 1970. */
    val decade: Int? = null,
    val sort: BrowseSort = BrowseSort.DEFAULT,
    /** A [com.zemu.tv.data.StreamingService] name: list what's on that service (TMDB). */
    val service: String? = null,
    /** A [com.zemu.tv.data.Studio] key: list that studio's / network's titles (TMDB). */
    val studio: String? = null,
    /** Movies or series, when browsing a service. */
    val tmdbType: String = "movie",
) {
    val tmdbMode: Boolean get() = service != null || studio != null
}

data class BrowseUi(
    val items: List<Meta> = emptyList(),
    val filters: BrowseFilters = BrowseFilters(),
    val catalogs: List<BrowseCatalog> = emptyList(),
    val genres: List<String> = emptyList(),
    val loading: Boolean = false,
    val endReached: Boolean = false,
    val error: String? = null,
    /** Titles fetched so far, before section/rating/decade filters. */
    val fetched: Int = 0,
)

/** Backs the Movies, Series and Anime pages. [type] is "movie", "series" or "anime". */
class BrowseViewModel(
    private val c: AppContainer,
    val type: String,
    initialService: String? = null,
    initialStudio: String? = null,
) : ViewModel() {
    val isAnime = type == "anime"

    private val raw = MutableStateFlow<List<Meta>>(emptyList())
    private val filters = MutableStateFlow(
        BrowseFilters(
            service = initialService,
            studio = initialStudio,
            tmdbType = com.zemu.tv.data.Studio.of(initialStudio)?.type ?: if (type == "series") "series" else "movie",
        ),
    )
    private val loading = MutableStateFlow(false)
    private val endReached = MutableStateFlow(false)
    private val error = MutableStateFlow<String?>(null)
    private val catalogs = MutableStateFlow<List<BrowseCatalog>>(emptyList())
    private val genres = MutableStateFlow<List<String>>(emptyList())
    private var addon: Addon? = null
    private var job: Job? = null
    private var pages = 0

    private data class Status(val loading: Boolean, val end: Boolean, val error: String?, val catalogs: List<BrowseCatalog>, val genres: List<String>)

    private val status = combine(loading, endReached, error, catalogs, genres) { l, e, err, cats, g -> Status(l, e, err, cats, g) }

    val state: StateFlow<BrowseUi> = combine(raw, filters, status) { items, f, s ->
        val profile = c.tasteProfile()
        if (f.tmdbMode) {
            val l = if (f.sort == BrowseSort.MATCH) items.sortedByDescending { c.recommender.matchPercent(it, profile) } else items
            return@combine BrowseUi(l, f, s.catalogs, (if (f.tmdbType == "series") com.zemu.tv.data.Tmdb.TV_GENRES else com.zemu.tv.data.Tmdb.MOVIE_GENRES).values.sorted(), s.loading, s.end, s.error, items.size)
        }
        var list = items
            .filter { !isAnime || it.type == f.section.metaType }
            .filter { x -> f.minRating == null || (x.rating ?: 0.0) >= f.minRating }
            .filter { x ->
                val y = x.year
                when (val d = f.decade) {
                    null -> true
                    -1 -> y != null && y < 1970
                    else -> y != null && y in d until d + 10
                }
            }
        list = when (f.sort) {
            BrowseSort.DEFAULT -> list
            BrowseSort.RATING, BrowseSort.MOST_FAVORITED -> list.sortedByDescending { it.rating ?: 0.0 }
            BrowseSort.NEWEST -> list.sortedByDescending { it.year ?: 0 }
            BrowseSort.OLDEST -> list.sortedBy { it.year ?: Int.MAX_VALUE }
            BrowseSort.MATCH -> list.sortedByDescending { c.recommender.matchPercent(it, profile) }
        }
        val genreNames = if (f.tmdbMode) (if (f.tmdbType == "series") com.zemu.tv.data.Tmdb.TV_GENRES else com.zemu.tv.data.Tmdb.MOVIE_GENRES).values.sorted() else s.genres
        BrowseUi(list, f, s.catalogs, genreNames, s.loading, s.end, s.error, items.size)
    }.stateIn(viewModelScope, SharingStarted.Eagerly, BrowseUi(loading = true))

    init {
        viewModelScope.launch {
            loading.value = true
            c.addons.ready.first { it }
            if (isAnime) setupAnime() else setupCinemeta()
            reload()
        }
    }

    private fun setupCinemeta() {
        // The preferred provider (Settings → Metadata) wins; otherwise Cinemeta, then any addon with catalogs of this type.
        val preferred = c.userStore.settings.value.metaProvider
        val usable: (com.zemu.tv.data.Addon) -> Boolean = { a -> a.manifest.catalogs.any { it.type == type && it.requiredExtras.isEmpty() } }
        val pick = c.addons.addons.value.firstOrNull { it.manifest.id == preferred && usable(it) }
            ?: c.addons.cinemeta
            ?: c.addons.addons.value.firstOrNull(usable)
        if (pick != null && pick.manifest.id != com.zemu.tv.data.AddonRepository.CINEMETA_ID) {
            addon = pick
            val defs = pick.manifest.catalogs.filter { it.type == type && it.requiredExtras.isEmpty() }
            catalogs.value = defs.map { d -> BrowseCatalog(d.id, d.name ?: d.id, paged = d.supportsExtra("skip"), genres = d.supportsExtra("genre")) }
            genres.value = defs.firstOrNull { it.supportsExtra("genre") }?.optionsFor("genre").orEmpty()
            filters.update { it.copy(catalog = catalogs.value.firstOrNull()?.id.orEmpty()) }
            return
        }
        val cinemeta = c.addons.cinemeta
        addon = cinemeta
        val defs = cinemeta?.manifest?.catalogs.orEmpty().filter { it.type == type }
        catalogs.value = listOfNotNull(
            defs.firstOrNull { it.id == "top" }?.let { BrowseCatalog("top", "Popular") },
            defs.firstOrNull { it.id == "imdbRating" }?.let { BrowseCatalog("imdbRating", "Top Rated") },
        )
        genres.value = defs.firstOrNull { it.id == "top" }?.optionsFor("genre").orEmpty()
        filters.update { it.copy(catalog = catalogs.value.firstOrNull()?.id.orEmpty()) }
    }

    private suspend fun setupAnime() {
        val kitsu = c.addons.ensureKitsu()
        addon = kitsu
        if (kitsu == null) {
            error.value = "Couldn't install the Anime Kitsu addon. Check your connection, or install it from Addons."
            return
        }
        val defs = kitsu.manifest.catalogs.filter { it.requiredExtras.isEmpty() }
        val labels = mapOf(
            "kitsu-anime-trending" to "Trending",
            "kitsu-anime-airing" to "Airing Now",
            "kitsu-anime-popular" to "Most Popular",
            "kitsu-anime-rating" to "Top Rated",
        )
        catalogs.value = defs.map { d ->
            BrowseCatalog(
                id = d.id,
                label = labels[d.id] ?: d.name?.removePrefix("Kitsu ") ?: d.id,
                paged = d.supportsExtra("skip"),
                genres = d.supportsExtra("genre"),
            )
        }
        genres.value = defs.firstOrNull { it.supportsExtra("genre") }?.optionsFor("genre").orEmpty()
        filters.update { it.copy(catalog = defaultAnimeCatalog(it.section)) }
    }

    /** Trending isn't paged and holds few movies, so movies start on Most Popular. */
    private fun defaultAnimeCatalog(section: AnimeSection): String {
        val ids = catalogs.value.map { it.id }
        return if (section == AnimeSection.MOVIES) ids.firstOrNull { it.contains("popular") } ?: ids.firstOrNull().orEmpty()
        else ids.firstOrNull().orEmpty()
    }

    fun setSection(section: AnimeSection) = setFilters { it.copy(section = section, catalog = defaultAnimeCatalog(section)) }

    fun setFilters(transform: (BrowseFilters) -> BrowseFilters) {
        val old = filters.value
        var next = transform(old)
        // Catalogs without genre support (Kitsu Trending) can't filter by genre.
        if (!next.tmdbMode && catalogs.value.firstOrNull { it.id == next.catalog }?.genres == false) next = next.copy(genre = null)
        // Switching between a service/studio list and the addon catalog: genre names differ.
        if (old.tmdbMode != next.tmdbMode || old.tmdbType != next.tmdbType) next = next.copy(genre = null)
        filters.value = next
        val serverSide = next.tmdbMode && (old.sort != next.sort || old.minRating != next.minRating || old.decade != next.decade)
        if (old.catalog != next.catalog || old.genre != next.genre || old.service != next.service || old.studio != next.studio || old.tmdbType != next.tmdbType || serverSide) reload()
    }

    private fun reload() {
        job?.cancel()
        raw.value = emptyList()
        pages = 0
        endReached.value = false
        error.value = null
        loadMore(force = true)
    }

    fun loadMore(force: Boolean = false) {
        if (!force && (loading.value || endReached.value)) return
        if (filters.value.tmdbMode) return loadTmdb()
        val source = addon ?: run {
            if (!isAnime) error.value = "No catalog provider is installed. Add Cinemeta or another metadata addon in Addons."
            loading.value = false
            return
        }
        val f = filters.value
        val cat = catalogs.value.firstOrNull { it.id == f.catalog } ?: run { loading.value = false; return }
        if (!force && !cat.paged) return
        job = viewModelScope.launch {
            loading.value = true
            val extra = buildMap {
                if (cat.genres) f.genre?.let { put("genre", it) }
                // Kitsu pages are addressed in steps of 50 (it rounds other values), Cinemeta by item count.
                val skip = if (isAnime) pages * 50 else raw.value.size
                if (skip > 0) put("skip", skip.toString())
            }
            val catalogType = if (isAnime) "anime" else type
            runCatching { c.addons.catalog(source, catalogType, cat.id, extra) }
                .onSuccess { items ->
                    val fresh = items.filter { n -> raw.value.none { it.id == n.id } }
                    raw.value = raw.value + fresh
                    pages++
                    if (fresh.isEmpty() || !cat.paged || pages >= MAX_PAGES) endReached.value = true
                }
                .onFailure { e -> error.value = "Couldn't load: ${e.message}" }
            loading.value = false
        }
    }

    /** A page of a streaming service's or studio's titles from TMDB, filtered and sorted there. */
    private fun loadTmdb() {
        val f = filters.value
        val t = f.tmdbType
        val params = buildMap {
            com.zemu.tv.data.StreamingService.of(f.service)?.let { putAll(com.zemu.tv.data.DiscoverParams.service(it)) }
            com.zemu.tv.data.Studio.of(f.studio)?.let { put(it.param.first, it.param.second) }
            putAll(
                when (f.sort) {
                    BrowseSort.RATING -> com.zemu.tv.data.DiscoverParams.topRated(200)
                    BrowseSort.NEWEST -> com.zemu.tv.data.DiscoverParams.newest(t)
                    BrowseSort.OLDEST -> mapOf("sort_by" to "${com.zemu.tv.data.DiscoverParams.dateField(t)}.asc", "vote_count.gte" to "20")
                    BrowseSort.MOST_FAVORITED -> com.zemu.tv.data.DiscoverParams.mostFavorited()
                    else -> com.zemu.tv.data.DiscoverParams.popular()
                },
            )
            f.genre?.let { g -> com.zemu.tv.data.Tmdb.genreId(t, g)?.let { put("with_genres", it.toString()) } }
            f.minRating?.let { put("vote_average.gte", it.toString()); put("vote_count.gte", "50") }
            val df = com.zemu.tv.data.DiscoverParams.dateField(t)
            when (val d = f.decade) {
                null -> {}
                -1 -> put("$df.lte", "1969-12-31")
                else -> { put("$df.gte", "$d-01-01"); put("$df.lte", "${d + 9}-12-31") }
            }
        }
        job = viewModelScope.launch {
            loading.value = true
            runCatching { c.tmdb.discover(t, params, page = pages + 1) }
                .onSuccess { items ->
                    val fresh = items.filter { n -> raw.value.none { it.id == n.id } }
                    raw.value = raw.value + fresh
                    pages++
                    if (fresh.isEmpty() || pages >= 25) endReached.value = true
                }
                .onFailure { e -> error.value = if (!c.tmdb.enabled) "Add a TMDB key in Settings → Addons to browse streaming services and studios." else "Couldn't load: ${e.message}" }
            loading.value = false
        }
    }

    /** Anime movies are sparse in mixed catalogs, so keep paging until the grid has enough. */
    fun shouldAutoLoad(ui: BrowseUi): Boolean =
        !ui.loading && !ui.endReached && ui.error == null && ui.items.size < 24 && raw.value.isNotEmpty()

    companion object {
        private const val MAX_PAGES = 12
    }
}
