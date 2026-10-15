package com.zemu.tv.ui.home

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.zemu.tv.AppContainer
import com.zemu.tv.data.Addon
import com.zemu.tv.data.AddonRepository
import com.zemu.tv.data.CatalogDef
import com.zemu.tv.data.Meta
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

enum class RowStyle { POSTER, LANDSCAPE }

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
)

/**
 * Applies the user's arrangement: rows they've placed keep their saved order (in the slots those
 * rows occupy by default, so new rows still show up where they normally would); favorites go first.
 */
fun arrangeRows(rows: List<HomeRow>, prefs: com.zemu.tv.data.RowPrefs): List<HomeRow> {
    val byKey = rows.associateBy { it.key }
    val keys = rows.map { it.key }.toMutableList()
    val saved = prefs.order.filter { it in byKey }
    if (saved.isNotEmpty()) {
        val savedSet = saved.toSet()
        keys.indices.filter { keys[it] in savedSet }.forEachIndexed { i, slot -> keys[slot] = saved[i] }
    }
    val favs = keys.filter { it in prefs.favorites }
    return (favs + keys.filterNot { it in prefs.favorites }).map { k -> byKey.getValue(k).let { if (k in prefs.favorites) it.copy(favorite = true) else it } }
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

class HomeViewModel(private val c: AppContainer) : ViewModel() {
    private val catalogRows = MutableStateFlow<List<HomeRow>>(emptyList())
    private val dailyRows = MutableStateFlow<List<HomeRow>>(emptyList())
    private val status = MutableStateFlow(Status())

    private val extraRows = combine(dailyRows, c.newEpisodes.items) { d, n -> d to n }

    private val baseRows = combine(catalogRows, extraRows, c.userStore.history, c.userStore.myList, c.userStore.watched) { catalogs, (daily, fresh), history, myList, watched ->
        buildList {
            if (fresh.isNotEmpty()) add(
                HomeRow("new-episodes", "New Episodes", fresh.map { it.meta }, priority = -1, badges = fresh.associate { it.meta.id to it.badge }),
            )
            val inProgress = history.filter { (it.progress in 0.01f..0.95f || it.durationMs == 0L) && it.meta.id !in watched }.distinctBy { it.meta.id }
            if (inProgress.isNotEmpty()) add(
                HomeRow(
                    key = "continue",
                    title = "In Progress",
                    items = inProgress.map { it.meta },
                    priority = 0,
                    style = RowStyle.LANDSCAPE,
                    subtitles = inProgress.mapNotNull { e -> e.label?.let { e.meta.id to it } }.toMap(),
                    progress = inProgress.associate { it.meta.id to it.progress },
                ),
            )
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
            addAll(daily)
            addAll(catalogs)
        }.sortedBy { it.priority }
    }

    private val arrangedRows = combine(baseRows, c.userStore.homeRows) { rows, prefs -> arrangeRows(rows, prefs) }

    init {
        // The screensaver suggests titles from the same discovery rows (not your own history).
        viewModelScope.launch {
            combine(catalogRows, dailyRows) { cat, daily -> daily to cat }.collect { (daily, cat) ->
                c.discovery.value = DiscoveryPool(daily.flatMap { it.items }, cat.flatMap { it.items })
            }
        }
    }

    val state: StateFlow<HomeUi> = combine(arrangedRows, c.addons.ready, c.addons.addons, status) { rows, ready, _, st ->
        if (!ready) return@combine HomeUi(loading = true)
        HomeUi(rows = rows, loading = st.loading, error = st.error, noStreamAddons = !c.addons.hasStreamAddons)
    }.stateIn(viewModelScope, SharingStarted.Eagerly, HomeUi())

    /** Emits the local day number, re-checked every 30 minutes so rows rotate after midnight. */
    private val day = flow {
        while (true) {
            emit(c.recommender.daySeed())
            delay(30 * 60 * 1000L)
        }
    }.distinctUntilChanged()

    init {
        load()
        viewModelScope.launch {
            combine(c.userStore.history, c.userStore.myList, day, c.userStore.ratings) { h, l, d, r -> listOf(h, l, d, r) }
                .distinctUntilChanged()
                .collectLatest {
                    delay(300)
                    val history = c.userStore.history.value
                    val myList = c.userStore.myList.value
                    loadDaily(c.tasteProfile(), history, myList)
                }
        }
        // Reload catalogs when addons are installed/removed.
        viewModelScope.launch {
            c.addons.addons.map { list -> list.map { it.transportUrl } }.distinctUntilChanged().collect {
                if (c.addons.ready.value && it != loadedFor) load()
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
        val prefs = c.userStore.homeRows.value
        c.userStore.saveHomeRows(prefs.copy(order = keys))
    }

    fun toggleFavoriteRow(key: String) = viewModelScope.launch {
        val prefs = c.userStore.homeRows.value
        // Un-favoriting drops the row's saved spot, so it goes back where it normally appears.
        val next = if (key in prefs.favorites) prefs.copy(favorites = prefs.favorites - key, order = prefs.order - key)
        else prefs.copy(favorites = prefs.favorites + key)
        c.userStore.saveHomeRows(next)
    }

    fun match(meta: Meta): Int = c.recommender.matchPercent(meta, c.tasteProfile())

    fun retry() {
        c.streams.invalidate()
        load()
    }

    private var loadedFor: List<String>? = null

    private fun load() = viewModelScope.launch {
        status.value = Status(loading = true)
        c.addons.ready.first { it }
        c.addons.ensureDefaults()
        loadedFor = c.addons.addons.value.map { it.transportUrl }
        val specs = catalogSpecs(c.addons.addons.value)
        val rows = specs.map { spec ->
            async {
                val items = runCatching { c.addons.catalog(spec.addon, spec.catalog.type, spec.catalog.id, spec.extra) }
                    .getOrDefault(emptyList())
                HomeRow(
                    key = "${spec.addon.manifest.id}/${spec.catalog.type}/${spec.catalog.id}/${spec.extra.values.joinToString()}",
                    title = spec.title,
                    items = items,
                    priority = spec.priority,
                )
            }
        }.awaitAll().filter { it.items.isNotEmpty() }
        catalogRows.value = rows
        status.value = Status(
            loading = false,
            error = if (rows.isEmpty()) "Couldn't load any catalogs. Check your connection and installed addons." else null,
        )
    }

    private suspend fun loadDaily(profile: TasteProfile, history: List<com.zemu.tv.data.WatchEntry>, myList: List<Meta>) {
        c.addons.ready.first { it }
        val rows = runCatching { c.recommender.dailyRows(profile, history, myList) }.getOrDefault(emptyList())
        dailyRows.value = rows.map { it.toHomeRow() }
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

    private data class CatalogSpec(
        val addon: Addon,
        val catalog: CatalogDef,
        val title: String,
        val priority: Int,
        val extra: Map<String, String> = emptyMap(),
    )

    private fun catalogSpecs(addons: List<Addon>): List<CatalogSpec> {
        val specs = mutableListOf<CatalogSpec>()
        val cinemeta = addons.firstOrNull { it.manifest.id == AddonRepository.CINEMETA_ID }
        if (cinemeta != null) {
            fun cat(type: String, id: String) = cinemeta.manifest.catalogs.firstOrNull { it.type == type && it.id == id }
            cat("movie", "top")?.let { specs += CatalogSpec(cinemeta, it, "Popular Movies", 3) }
            cat("series", "top")?.let { specs += CatalogSpec(cinemeta, it, "Popular Series", 4) }
            cat("movie", "year")?.let { c -> c.optionsFor("genre").firstOrNull()?.let { y -> specs += CatalogSpec(cinemeta, c, "New Movies · $y", 11, mapOf("genre" to y)) } }
            cat("movie", "imdbRating")?.let { specs += CatalogSpec(cinemeta, it, "Top Rated Movies", 13) }
            cat("series", "year")?.let { c -> c.optionsFor("genre").firstOrNull()?.let { y -> specs += CatalogSpec(cinemeta, c, "New Series · $y", 15, mapOf("genre" to y)) } }
            cat("series", "imdbRating")?.let { specs += CatalogSpec(cinemeta, it, "Top Rated Series", 16) }
            listOf("Action", "Comedy", "Sci-Fi", "Thriller", "Animation", "Horror", "Romance", "Documentary").forEachIndexed { i, g ->
                cat("movie", "top")?.takeIf { g in it.optionsFor("genre") }?.let { specs += CatalogSpec(cinemeta, it, "$g Movies", 20 + i, mapOf("genre" to g)) }
            }
            listOf("Drama", "Crime", "Comedy").forEachIndexed { i, g ->
                cat("series", "top")?.takeIf { g in it.optionsFor("genre") }?.let { specs += CatalogSpec(cinemeta, it, "$g Series", 30 + i, mapOf("genre" to g)) }
            }
        }
        // Catalogs from any other installed addon that don't need extra input.
        var p = 40
        addons.filter { it !== cinemeta }.forEach { addon ->
            addon.manifest.catalogs.filter { it.requiredExtras.isEmpty() && it.type in setOf("movie", "series") }.take(4).forEach { cat ->
                specs += CatalogSpec(addon, cat, "${cat.name ?: cat.id} · ${addon.manifest.name}", p++)
            }
        }
        return specs
    }

}
