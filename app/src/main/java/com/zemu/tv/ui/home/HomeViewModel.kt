package com.zemu.tv.ui.home

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.zemu.tv.AppContainer
import com.zemu.tv.data.AddonRepository
import com.zemu.tv.data.DiscoverParams
import com.zemu.tv.data.Meta
import com.zemu.tv.data.RowPrefs
import com.zemu.tv.data.RowSnapshot
import com.zemu.tv.data.RowSpec
import com.zemu.tv.data.StreamingService
import com.zemu.tv.data.Categories
import com.zemu.tv.data.slim
import kotlinx.coroutines.sync.withPermit
import com.zemu.tv.recommend.SuggestionRow
import com.zemu.tv.recommend.TasteProfile
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

enum class RowStyle { POSTER, LANDSCAPE, /** Streaming service logos. */ SERVICES, /** Studio / network logos. */ STUDIOS }

data class HomeRow(
    val key: String,
    val title: String,
    val items: List<Meta>,
    val priority: Int = 50,
    val style: RowStyle = RowStyle.POSTER,
    val subtitles: Map<String, String> = emptyMap(),
    val progress: Map<String, Float> = emptyMap(),
    val match: Map<String, Int> = emptyMap(),
    /** Per-title poster badge text, e.g. "3 NEW"; shown instead of the match percent. */
    val badges: Map<String, String> = emptyMap(),
    /** Pinned to the top by the user (heart). */
    val favorite: Boolean = false,
    /** "See more" opens the grid for this streaming service or studio. */
    val service: String? = null,
    val serviceLabel: String? = null,
    val studio: String? = null,
)

/**
 * Applies the user's arrangement: rows they've placed keep their saved order (in the slots those
 * rows occupy by default, so new rows still show up where they normally would); favorites go first.
 */
fun arrangeRows(rows: List<HomeRow>, prefs: com.zemu.tv.data.RowPrefs): List<HomeRow> {
    val byKey = rows.filterNot { it.key in prefs.hidden }.associateBy { it.key }
    @Suppress("NAME_SHADOWING") val rows = rows.filter { it.key in byKey }
    val keys = rows.map { it.key }.toMutableList()
    val saved = prefs.order.filter { it in byKey }
    if (saved.isNotEmpty()) {
        val savedSet = saved.toSet()
        keys.indices.filter { keys[it] in savedSet }.forEachIndexed { i, slot -> keys[slot] = saved[i] }
    }
    val favs = keys.filter { it in prefs.favorites }
    return (favs + keys.filterNot { it in prefs.favorites }).map { k -> byKey.getValue(k).let { if (k in prefs.favorites) it.copy(favorite = true) else it } }
}

/** Marks In Progress shows whose next episode is up (the last one was finished). */
const val NEXT_BADGE = "NEXT"

/** "Next · S2 E5" from an episode id like "tt123:2:4" (or "kitsu:1:4"). */
fun nextEpisodeLabel(videoId: String): String? {
    val parts = videoId.split(':')
    val ep = parts.lastOrNull()?.toIntOrNull() ?: return null
    // Kitsu ids are "kitsu:<show>:<episode>": no season part.
    val season = parts.getOrNull(parts.size - 2)?.toIntOrNull()?.takeIf { parts.size >= 3 && !videoId.startsWith("kitsu:") }
    return if (season != null) "Next · S$season E${ep + 1}" else "Next · Episode ${ep + 1}"
}

/** Titles from Home's suggestion rows ([recommended]) and catalog rows. */
data class DiscoveryPool(val recommended: List<Meta> = emptyList(), val catalogs: List<Meta> = emptyList())

data class HomeUi(
    val rows: List<HomeRow> = emptyList(),
    val loading: Boolean = true,
    val error: String? = null,
    val noStreamAddons: Boolean = false,
)

private data class Status(val loading: Boolean = true, val error: String? = null)

/**
 * Rows for Home and for the Movies, Series and Anime pages ([page] = "home", "movie", "series" or
 * "anime"). Each page mixes personal rows, streaming service and studio rows, and catalog rows; the
 * rotating ones change every launch. The last session's rows show instantly while they refresh.
 */
class HomeViewModel(private val c: AppContainer, val page: String = "home") : ViewModel() {
    private val isHome = page == "home"
    private val specRows = MutableStateFlow<List<HomeRow>>(emptyList())
    private val dailyRows = MutableStateFlow<List<HomeRow>>(emptyList())
    private val providers = MutableStateFlow<List<com.zemu.tv.data.Provider>>(emptyList())
    private val studioLogos = MutableStateFlow<Map<String, String>>(emptyMap())
    private val status = MutableStateFlow(Status())

    /** Movies/series pages only show their own kind; anime pages show Kitsu titles. */
    private fun Meta.onPage(): Boolean = when (page) {
        "home" -> true
        "anime" -> id.startsWith("kitsu:")
        else -> type == page && !id.startsWith("kitsu:")
    }

    private data class Extras(val daily: List<HomeRow>, val fresh: List<com.zemu.tv.data.NewEpisodesItem>, val providers: List<com.zemu.tv.data.Provider>, val studioLogos: Map<String, String>, val settings: com.zemu.tv.data.AppSettings)

    private val extraRows = combine(dailyRows, c.newEpisodes.items, providers, studioLogos, c.userStore.settings) { d, n, p, l, st -> Extras(d, n, p, l, st) }

    private val baseRows = combine(specRows, extraRows, c.userStore.history, c.userStore.myList, c.userStore.watched) { specs, ex, history, myList, watched ->
        val freshAll = ex.fresh
        // Optionally keep watched titles out of suggestion and category rows.
        val hide: (HomeRow) -> HomeRow = { r -> if (ex.settings.hideWatchedInRows) r.copy(items = r.items.filterNot { it.id in watched }) else r }
        val catalogs = specs.map(hide).filter { it.items.isNotEmpty() }
        val daily = ex.daily.map(hide).filter { it.items.isNotEmpty() }
        buildList {
            val fresh = freshAll.filter { it.meta.onPage() }
            if (fresh.isNotEmpty() && page != "movie") add(
                HomeRow("new-episodes", "New Episodes", fresh.map { it.meta }, priority = -1, badges = fresh.associate { it.meta.id to it.badge }),
            )
            // A show whose last episode was finished stays here, pointing at the next episode.
            fun finishedEpisode(e: com.zemu.tv.data.WatchEntry) = e.meta.type == "series" && e.durationMs > 0 && e.progress > 0.9f
            val inProgress = history.filter { (it.progress in 0.01f..0.95f || it.durationMs == 0L || finishedEpisode(it)) && it.meta.id !in watched && it.meta.onPage() }.distinctBy { it.meta.id }
            if (inProgress.isNotEmpty()) add(
                HomeRow(
                    key = "continue",
                    title = "In Progress",
                    items = inProgress.map { it.meta },
                    priority = 0,
                    style = RowStyle.LANDSCAPE,
                    subtitles = inProgress.mapNotNull { e -> (if (finishedEpisode(e)) nextEpisodeLabel(e.videoId) else e.label)?.let { e.meta.id to it } }.toMap(),
                    progress = inProgress.associate { it.meta.id to if (finishedEpisode(it)) 0f else it.progress },
                    badges = inProgress.filter(::finishedEpisode).associate { it.meta.id to NEXT_BADGE },
                ),
            )
            if (page != "anime" && c.tmdb.enabled) {
                // Your services first, then the most popular; "View more" lists all of them.
                val mine = ex.settings.myServices.map { (id, name) -> com.zemu.tv.data.Provider(id, name, ex.providers.firstOrNull { it.ids == id }?.logo) }
                val all = ex.providers.ifEmpty { StreamingService.entries.map { it.provider } }
                add(
                    HomeRow(
                        "services", "Streaming Services",
                        (mine + all).distinctBy { it.ids }.take(24).map { p -> Meta(id = "service:${p.ids}", name = p.label, poster = p.logo) },
                        priority = 1, style = RowStyle.SERVICES,
                    ),
                )
            }
            if ((page == "movie" || page == "series") && c.tmdb.enabled) add(
                HomeRow(
                    "studios", if (page == "series") "Networks" else "Studios",
                    com.zemu.tv.data.Studio.forType(page).map { st -> Meta(id = "studio:${st.key}", name = st.label, poster = ex.studioLogos[st.key]) },
                    priority = 2, style = RowStyle.STUDIOS,
                ),
            )
            if (isHome) {
                if (myList.isNotEmpty()) add(HomeRow("mylist", "My List", myList, priority = 7))
                val recent = history.sortedByDescending { it.updatedAt }.distinctBy { it.meta.id }
                // Only movies watched through to the credits; partly watched ones are In Progress.
                recent.filter { it.meta.type == "movie" && it.meta.id in watched }.map { it.meta }.take(30).takeIf { it.isNotEmpty() }
                    ?.let { add(HomeRow("recent-movies", "Recently Watched Movies", it, priority = 6)) }
                recent.filter { it.meta.type == "series" }.take(30).takeIf { it.isNotEmpty() }?.let { list ->
                    add(
                        HomeRow(
                            "recent-series", "Recently Watched Series", list.map { it.meta }, priority = 6,
                            style = RowStyle.LANDSCAPE,
                            subtitles = list.mapNotNull { e -> e.label?.let { e.meta.id to it } }.toMap(),
                        ),
                    )
                }
            }
            addAll(daily)
            addAll(catalogs)
        }.sortedBy { it.priority }
    }

    private val prefs = if (isHome) c.userStore.homeRows else c.userStore.pageRows.map { it[page] ?: RowPrefs() }
        .stateIn(viewModelScope, SharingStarted.Eagerly, RowPrefs())

    private val arrangedRows = combine(baseRows, prefs) { rows, p -> arrangeRows(rows, p) }

    /** Every row in its arranged order, removed ones included (for Settings → Manage rows). */
    val manageRows: StateFlow<Pair<List<HomeRow>, RowPrefs>> = combine(baseRows, prefs) { rows, p -> arrangeRows(rows, p.copy(hidden = emptyList())) to p }
        .stateIn(viewModelScope, SharingStarted.Eagerly, emptyList<HomeRow>() to RowPrefs())

    fun hideRow(key: String) = viewModelScope.launch {
        val p = prefs.value
        // A row you added is simply taken off again; anything else is hidden and can be restored.
        if (p.added.any { it.key == key }) {
            c.userStore.saveRowPrefs(page, p.copy(added = p.added.filterNot { it.key == key }, favorites = p.favorites - key))
            specRows.value = specRows.value.filterNot { it.key == key }
        } else c.userStore.saveRowPrefs(page, p.copy(hidden = (p.hidden + key).distinct(), favorites = p.favorites - key))
    }

    fun showRow(key: String) = viewModelScope.launch {
        val p = prefs.value
        c.userStore.saveRowPrefs(page, p.copy(hidden = p.hidden - key))
    }

    /** Adds a row of your own choosing; it stays on this page, loads now, and can be removed again. */
    fun addRow(spec: RowSpec) = viewModelScope.launch {
        val p = prefs.value
        if (p.added.any { it.key == spec.key }) return@launch
        c.userStore.saveRowPrefs(page, p.copy(added = p.added + spec, hidden = p.hidden - spec.key))
        val items = runCatching { fetch(spec) }.getOrDefault(emptyList())
        if (items.isNotEmpty()) specRows.value = (specRows.value.filterNot { it.key == spec.key } + spec.toRow(items)).sortedBy { it.priority }
    }

    /** Rows that can be added to this page: services, studios, genres, catalogs. */
    fun addableRows(): List<RowSpec> {
        val out = mutableListOf<RowSpec>()
        val types = when (page) { "home" -> listOf("movie", "series"); "anime" -> emptyList(); else -> listOf(page) }
        val noun = { t: String -> if (t == "series") "Series" else "Movies" }
        if (c.tmdb.enabled) types.forEach { t ->
            val services = (c.userStore.settings.value.myServices.map { (id, n) -> com.zemu.tv.data.Provider(id, n) } + StreamingService.entries.map { it.provider }).distinctBy { it.ids }
            services.forEach { s -> out += RowSpec("$t/added-svc-${s.ids}", "${noun(t)} on ${s.label}", 5, t, tmdb = DiscoverParams.service(s) + DiscoverParams.popular(), service = s.ids, serviceLabel = s.label) }
            com.zemu.tv.data.Studio.forType(t).forEach { st -> out += RowSpec("$t/added-studio-${st.key}", "From ${st.label}", 5, t, tmdb = mapOf(st.param) + DiscoverParams.popular(), studio = st.key) }
        }
        val cinemeta = c.addons.cinemeta
        if (cinemeta != null) types.forEach { t ->
            cinemeta.manifest.catalogs.firstOrNull { it.type == t && it.id == "top" }?.optionsFor("genre")?.forEach { g ->
                out += RowSpec("$t/added-genre-$g", "$g ${noun(t)}", 5, t, addonId = cinemeta.manifest.id, catalogType = t, catalogId = "top", extra = mapOf("genre" to g))
            }
        }
        if (page == "anime") c.addons.kitsu?.let { k ->
            k.manifest.catalogs.firstOrNull { it.id == "kitsu-anime-popular" }?.optionsFor("genre")?.forEach { g ->
                out += RowSpec("anime/added-genre-$g", "$g Anime", 5, "series", addonId = k.manifest.id, catalogType = "anime", catalogId = "kitsu-anime-popular", extra = mapOf("genre" to g))
            }
        }
        // Any catalog from any installed addon.
        c.addons.addons.value.forEach { a ->
            a.manifest.catalogs.filter { it.requiredExtras.isEmpty() && (page == "home" || it.type == page || (page == "anime" && a.manifest.id == AddonRepository.KITSU_ID)) }.forEach { cat ->
                out += RowSpec("${a.manifest.id}/added-${cat.type}/${cat.id}", "${cat.name ?: cat.id} · ${a.manifest.name}", 5, cat.type, addonId = a.manifest.id, catalogType = cat.type, catalogId = cat.id)
            }
        }
        return out.distinctBy { it.key }
    }

    init {
        // The screensaver suggests titles from Home's discovery rows (not your own history).
        if (isHome) viewModelScope.launch {
            combine(specRows, dailyRows) { cat, daily -> daily to cat }.collect { (daily, cat) ->
                c.discovery.value = DiscoveryPool(daily.flatMap { it.items }, cat.flatMap { it.items })
            }
        }
    }

    val state: StateFlow<HomeUi> = combine(arrangedRows, c.addons.ready, c.addons.addons, status) { rows, ready, _, st ->
        if (!ready && rows.isEmpty()) return@combine HomeUi(loading = true)
        HomeUi(rows = rows, loading = st.loading, error = st.error, noStreamAddons = ready && !c.addons.hasStreamAddons)
    }.stateIn(viewModelScope, SharingStarted.Eagerly, HomeUi())

    /** Emits the local day number, re-checked every 30 minutes so rows rotate after midnight. */
    private val day = flow {
        while (true) {
            emit(c.recommender.daySeed())
            delay(30 * 60 * 1000L)
        }
    }.distinctUntilChanged()

    private val snapshotFile = java.io.File(c.appContext.filesDir, "rows_${c.profileId}_$page.json")

    init {
        load(useSnapshot = true)
        if (page != "anime") viewModelScope.launch {
            combine(c.userStore.history, c.userStore.myList, day, c.userStore.ratings) { h, l, d, r -> listOf(h, l, d, r) }
                .distinctUntilChanged()
                .collectLatest {
                    delay(if (isHome) 1_200 else 2_000)
                    loadDaily(c.tasteProfile(), c.userStore.history.value, c.userStore.myList.value)
                }
        }
        if (page != "anime") viewModelScope.launch {
            providers.value = runCatching { c.tmdb.allProviders(DiscoverParams.region) }.getOrDefault(emptyList())
            if (page == "movie" || page == "series") {
                val gate = kotlinx.coroutines.sync.Semaphore(4)
                com.zemu.tv.data.Studio.forType(page).map { st ->
                    async { gate.withPermit { st.key to runCatching { c.tmdb.studioLogo(st) }.getOrNull() } }
                }.awaitAll().forEach { (k, v) -> if (v != null) studioLogos.value = studioLogos.value + (k to v) }
            }
        }
        // Reload catalogs when addons are installed/removed.
        viewModelScope.launch {
            c.addons.addons.map { list -> list.map { it.transportUrl } }.distinctUntilChanged().collect {
                if (c.addons.ready.value && loadedFor != null && it != loadedFor) load(useSnapshot = false)
            }
        }
    }

    /** Moves a row one place up (-1) or down (+1) among rows of the same kind (favorites or not). */
    fun moveRow(key: String, direction: Int) = viewModelScope.launch {
        val shown = state.value.rows
        val i = shown.indexOfFirst { it.key == key }
        val j = i + direction
        if (i < 0 || j !in shown.indices || shown[i].favorite != shown[j].favorite) return@launch
        val keys = shown.map { it.key }.toMutableList()
        keys[i] = keys[j].also { keys[j] = keys[i] }
        c.userStore.saveRowPrefs(page, prefs.value.copy(order = keys))
    }

    fun toggleFavoriteRow(key: String) = viewModelScope.launch {
        val p = prefs.value
        // Un-favoriting drops the row's saved spot, so it goes back where it normally appears.
        val next = if (key in p.favorites) p.copy(favorites = p.favorites - key, order = p.order - key)
        else p.copy(favorites = p.favorites + key)
        c.userStore.saveRowPrefs(page, next)
    }

    fun match(meta: Meta): Int = c.recommender.matchPercent(meta, c.tasteProfile())

    /** "Surprise me": a random unwatched title from your best-matching suggestions. */
    fun surprise(): Meta? {
        val watched = c.userStore.watched.value
        val seen = c.userStore.history.value.map { it.meta.id }.toSet()
        val pool = (dailyRows.value.flatMap { it.items } + specRows.value.flatMap { it.items })
            .filter { it.id !in watched && it.id !in seen && it.type in setOf("movie", "series") && c.kids.knownAllowed(it) == true }
            .distinctBy { it.id }
        val profile = c.tasteProfile()
        return pool.sortedByDescending { c.recommender.matchPercent(it, profile) }.take(30).randomOrNull()
    }

    fun retry() {
        c.streams.invalidate()
        load(useSnapshot = false)
    }

    private var loadedFor: List<String>? = null
    private var loadJob: kotlinx.coroutines.Job? = null

    private fun RowSpec.toRow(items: List<Meta>) = HomeRow(key, title, items, priority, service = service, serviceLabel = serviceLabel, studio = studio)

    /**
     * Shows the saved rows right away (if any), then refreshes every row in parallel, each one
     * appearing as soon as it loads. Afterwards the next rotation is fetched and saved, so the
     * next launch starts instantly with new categories.
     */
    private fun load(useSnapshot: Boolean) {
        loadJob?.cancel()
        loadJob = viewModelScope.launch {
            val snapshot = if (useSnapshot) readSnapshot() else null
            if (snapshot != null && snapshot.specs.isNotEmpty()) {
                specRows.value = snapshot.specs.mapNotNull { s -> snapshot.items[s.key]?.takeIf { it.isNotEmpty() }?.let { s.toRow(it) } }
                status.value = Status(loading = false)
            } else status.value = Status(loading = true)
            c.addons.ready.first { it }
            if (isHome) c.addons.ensureDefaults()
            if (page == "anime") c.addons.ensureKitsu()
            loadedFor = c.addons.addons.value.map { it.transportUrl }
            val specs = ((snapshot?.specs?.takeIf { it.isNotEmpty() } ?: buildSpecs(kotlin.random.Random.nextLong())) + prefs.value.added).distinctBy { it.key }
            val items = fetchAll(specs) { key, list ->
                val spec = specs.first { it.key == key }
                specRows.value = (specRows.value.filterNot { it.key == key } + spec.toRow(list)).sortedBy { it.priority }
            }
            // Drop rows that came back empty this time.
            specRows.value = specRows.value.filter { r -> items[r.key]?.isNotEmpty() ?: true }
            status.value = Status(
                loading = false,
                error = if (specRows.value.isEmpty()) "Couldn't load any catalogs. Check your connection and installed addons." else null,
            )
            // Prepare the next launch's rotation once startup traffic (images, personal rows) is done.
            delay(90_000)
            val next = buildSpecs(kotlin.random.Random.nextLong())
            val nextItems = fetchAll(next) { _, _ -> }
            writeSnapshot(RowSnapshot(next, nextItems.mapValues { (_, v) -> v.map { it.slim() } }))
        }
    }

    private suspend fun fetchAll(specs: List<RowSpec>, onRow: (String, List<Meta>) -> Unit): Map<String, List<Meta>> = kotlinx.coroutines.coroutineScope {
        val gate = kotlinx.coroutines.sync.Semaphore(6)
        specs.map { spec ->
            async {
                val list = gate.withPermit { runCatching { fetch(spec) }.getOrDefault(emptyList()) }
                if (list.isNotEmpty()) onRow(spec.key, list)
                spec.key to list
            }
        }.awaitAll().toMap()
    }

    private suspend fun fetch(spec: RowSpec): List<Meta> {
        spec.tmdb?.let { return c.tmdb.discover(spec.type, it).take(spec.limit) }
        val addon = c.addons.addons.value.firstOrNull { it.manifest.id == spec.addonId } ?: return emptyList()
        return c.addons.catalog(addon, spec.catalogType ?: spec.type, spec.catalogId ?: return emptyList(), spec.extra).take(spec.limit)
    }

    private suspend fun readSnapshot(): RowSnapshot? = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
        runCatching { c.json.decodeFromString(RowSnapshot.serializer(), snapshotFile.readText()) }.getOrNull()
    }

    private suspend fun writeSnapshot(s: RowSnapshot) = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
        runCatching { snapshotFile.writeText(c.json.encodeToString(RowSnapshot.serializer(), s)) }
    }

    private fun buildSpecs(seed: Long): List<RowSpec> {
        val addons = c.addons.addons.value
        val taste = c.tasteProfile().topGenres(4)
        val specs = mutableListOf<RowSpec>()
        if (page == "anime") {
            val kitsu = c.addons.kitsu
            if (kitsu != null) {
                val labels = mapOf("kitsu-anime-trending" to "Trending Anime", "kitsu-anime-airing" to "Airing Now", "kitsu-anime-popular" to "Most Popular Anime", "kitsu-anime-rating" to "Top Rated Anime")
                kitsu.manifest.catalogs.filter { it.requiredExtras.isEmpty() && it.id in labels }.forEachIndexed { i, d ->
                    specs += RowSpec("anime/${d.id}", labels.getValue(d.id), 3 + i, "series", addonId = kitsu.manifest.id, catalogType = d.type, catalogId = d.id)
                }
                kitsu.manifest.catalogs.firstOrNull { it.id == "kitsu-anime-popular" }?.optionsFor("genre").orEmpty()
                    .shuffled(kotlin.random.Random(seed)).take(4).forEachIndexed { i, g ->
                        specs += RowSpec("anime/genre-$g", "Popular $g Anime", 30 + i, "series", addonId = kitsu.manifest.id, catalogType = "anime", catalogId = "kitsu-anime-popular", extra = mapOf("genre" to g))
                    }
            }
            if (c.tmdb.enabled) listOf(StreamingService.CRUNCHYROLL, StreamingService.NETFLIX, StreamingService.HULU).forEachIndexed { i, s ->
                specs += RowSpec("anime/svc-${s.name}", "Anime on ${s.label}", 20 + i, "series",
                    tmdb = DiscoverParams.service(s) + DiscoverParams.popular() + mapOf("with_genres" to "16", "with_original_language" to "ja"), service = s.ids, serviceLabel = s.label)
            }
            return specs
        }
        val cinemeta = addons.firstOrNull { it.manifest.id == AddonRepository.CINEMETA_ID }
        if (cinemeta != null) {
            fun cat(type: String, id: String) = cinemeta.manifest.catalogs.firstOrNull { it.type == type && it.id == id }
            fun spec(type: String, id: String, title: String, priority: Int, extra: Map<String, String> = emptyMap()) =
                RowSpec("$type/$id/${extra.values.joinToString()}", title, priority, type, addonId = cinemeta.manifest.id, catalogType = type, catalogId = id, extra = extra)
            val types = if (isHome) listOf("movie", "series") else listOf(page)
            types.forEach { type ->
                val noun = if (type == "series") "Series" else "Movies"
                val o = if (type == "series") 1 else 0
                cat(type, "top")?.let { specs += spec(type, "top", if (isHome) "Popular $noun" else "Popular", 3 + o) }
                cat(type, "year")?.optionsFor("genre")?.firstOrNull()?.let { y -> specs += spec(type, "year", "New $noun · $y", 11 + o * 4, mapOf("genre" to y)) }
                cat(type, "imdbRating")?.let { specs += spec(type, "imdbRating", "Top Rated $noun", 13 + o * 3) }
                specs += Categories.genreRows(cinemeta, type, seed, taste, count = if (isHome) (if (type == "movie") 2 else 1) else 3, priority = 30 + o * 5)
            }
        }
        val mine = c.userStore.settings.value.myServices.map { (id, name) -> com.zemu.tv.data.Provider(id, name) }
        if (c.tmdb.enabled) specs += Categories.tmdbRows(page, seed, taste, mine)
        // Catalogs from any other installed addon that don't need extra input.
        var p = 50
        addons.filter { it !== cinemeta && it.manifest.id != AddonRepository.KITSU_ID }.forEach { addon ->
            addon.manifest.catalogs.filter { it.requiredExtras.isEmpty() && it.type in (if (isHome) setOf("movie", "series") else setOf(page)) }.take(4).forEach { cat ->
                specs += RowSpec("${addon.manifest.id}/${cat.type}/${cat.id}", "${cat.name ?: cat.id} · ${addon.manifest.name}", p++, cat.type, addonId = addon.manifest.id, catalogType = cat.type, catalogId = cat.id)
            }
        }
        return specs
    }

    private suspend fun loadDaily(profile: TasteProfile, history: List<com.zemu.tv.data.WatchEntry>, myList: List<Meta>) {
        c.addons.ready.first { it }
        // Scoring hundreds of titles: keep it off the main thread.
        val rows = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.Default) {
            runCatching { c.recommender.dailyRows(profile, history, myList) }.getOrDefault(emptyList())
        }
        dailyRows.value = rows.map { it.toHomeRow() }
            .map { r -> if (isHome) r else r.copy(items = r.items.filter { it.onPage() }) }
            .filter { isHome || it.items.size >= 6 }
            // The New Episodes row is already built from [NewEpisodes].
            .filter { isHome || it.key != "new-episodes" }
    }

    private fun SuggestionRow.toHomeRow() = HomeRow(
        key = key,
        title = title,
        items = items,
        priority = priority,
        style = if (landscape) RowStyle.LANDSCAPE else RowStyle.POSTER,
        subtitles = subtitles,
        match = match,
    )
}
