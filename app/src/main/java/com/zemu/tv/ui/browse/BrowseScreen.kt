package com.zemu.tv.ui.browse

import kotlinx.coroutines.launch
import com.zemu.tv.ui.components.SheetAction
import com.zemu.tv.ui.components.ActionSheet
import com.zemu.tv.ui.components.heroTrailerTap
import com.zemu.tv.ui.components.PosterCard
import com.zemu.tv.ui.components.MediaRow
import androidx.compose.ui.layout.layout
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.tv.material3.Text
import com.zemu.tv.container
import com.zemu.tv.data.Meta
import com.zemu.tv.ui.components.heroTrailerKeys
import com.zemu.tv.ui.components.Backdrop
import com.zemu.tv.ui.components.CenteredMessage
import com.zemu.tv.ui.components.ChoiceDialog
import com.zemu.tv.ui.components.ChoiceOption
import com.zemu.tv.ui.components.HeroInfo
import com.zemu.tv.ui.components.PosterGrid
import com.zemu.tv.ui.components.TvChip
import com.zemu.tv.ui.theme.Palette
import kotlinx.coroutines.delay

private enum class BrowseDialog { CATALOG, GENRE, RATING, DECADE, SORT, SERVICE, STUDIO }

private val ratingOptions = listOf(null, 6.0, 7.0, 7.5, 8.0)
private val decadeOptions = listOf(null, 2020, 2010, 2000, 1990, 1980, 1970, -1)
private const val COLUMNS = 7

private fun decadeLabel(d: Int?) = when (d) { null -> "Any"; -1 -> "Before 1970"; else -> "${d}s" }
private fun ratingLabel(r: Double?) = if (r == null) "Any" else "${if (r % 1.0 == 0.0) r.toInt().toString() else r.toString()}+"

/** Movies, Series and Anime pages: hero for the focused title, filter chips, then a poster grid. */
@Composable
fun BrowseScreen(type: String, onOpen: (Meta) -> Unit, service: String? = null, studio: String? = null, serviceLabel: String? = null) {
    val c = LocalContext.current.container
    val vm: BrowseViewModel = viewModel(key = "browse-$type-$service-$studio") { BrowseViewModel(c, type, service, studio, serviceLabel) }
    val ui by vm.state.collectAsStateWithLifecycle()
    val settings by c.userStore.settings.collectAsStateWithLifecycle()
    var dialog by remember { mutableStateOf<BrowseDialog?>(null) }
    var filtersOpen by remember { mutableStateOf(false) }
    val f = ui.filters
    val topFocus = remember { FocusRequester() }
    // Back from deep in the grid jumps to the top first.
    val gridState = androidx.compose.foundation.lazy.grid.rememberLazyGridState()
    val scope = androidx.compose.runtime.rememberCoroutineScope()
    val scrolled by androidx.compose.runtime.remember { androidx.compose.runtime.derivedStateOf { gridState.firstVisibleItemIndex > 0 } }
    androidx.activity.compose.BackHandler(enabled = scrolled) {
        scope.launch {
            gridState.scrollToItem(0)
            runCatching { topFocus.requestFocus() }
        }
    }

    var focused by remember { mutableStateOf<Meta?>(null) }
    var hero by remember { mutableStateOf<Meta?>(null) }
    var focusedIndex by remember { mutableIntStateOf(-1) }
    // Collapse the hero once you're past the first grid row so more posters fit.
    val heroHeight = 180.dp

    LaunchedEffect(type) {
        delay(120)
        runCatching { topFocus.requestFocus() }
    }
    LaunchedEffect(focused) {
        delay(220)
        focused?.let { hero = it }
    }
    LaunchedEffect(ui.items.firstOrNull()?.id) {
        if (focused == null) hero = ui.items.firstOrNull()
    }
    LaunchedEffect(ui.items.size, ui.fetched, ui.loading, ui.endReached) {
        if (vm.shouldAutoLoad(ui)) vm.loadMore()
    }

    // Series: shows from regular catalogs; Anime: Kitsu shows. Movies have no episodes.
    val allNew by c.newEpisodes.items.collectAsStateWithLifecycle()
    val newEpisodes = when (type) {
        "series" -> allNew.filter { !it.meta.id.startsWith("kitsu:") }
        "anime" -> allNew.filter { it.meta.id.startsWith("kitsu:") }
        else -> emptyList()
    }

    val svc = f.service?.let { com.zemu.tv.data.Provider(it, f.serviceLabel ?: com.zemu.tv.data.StreamingService.entries.firstOrNull { s -> s.ids == it }?.label ?: "Service") }
    val std = com.zemu.tv.data.Studio.of(f.studio)
    val title = listOfNotNull(svc?.label ?: std?.label, when (if (f.tmdbMode) f.tmdbType else type) { "series" -> "Series"; "anime" -> "Anime"; else -> "Movies" }).joinToString(" · ")
    val catalogLabel = ui.catalogs.firstOrNull { it.id == f.catalog }?.label ?: ""
    val genreAllowed = ui.catalogs.firstOrNull { it.id == f.catalog }?.genres != false

    Box(Modifier.fillMaxSize().heroTrailerKeys()) {
        Backdrop(
            hero,
            Modifier.fillMaxWidth().fillMaxHeight(0.62f),
            trailerAfterMs = if (settings.heroTrailers) 6_000L else null,
            trailerSound = settings.heroTrailerSound,
        )
        Column(Modifier.fillMaxSize()) {
            HeroInfo(hero, hero?.let { c.recommender.matchPercent(it, c.tasteProfile()) }, Modifier.fillMaxWidth().height(heroHeight).heroTrailerTap())
            LazyRow(
                contentPadding = PaddingValues(horizontal = 48.dp, vertical = 10.dp),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.onFocusChanged { if (it.hasFocus) focusedIndex = -1 },
            ) {
                item { Text(title, fontWeight = FontWeight.Black, fontSize = 22.sp, modifier = Modifier.padding(end = 6.dp)) }
                if (vm.isAnime) {
                    AnimeSection.entries.forEach { s ->
                        item {
                            TvChip(
                                s.label,
                                selected = f.section == s,
                                onClick = { vm.setSection(s) },
                                modifier = if (s == AnimeSection.SERIES) Modifier.focusRequester(topFocus) else Modifier,
                            )
                        }
                    }
                    item { TvChip("$catalogLabel ▾", selected = false, onClick = { dialog = BrowseDialog.CATALOG }) }
                } else if (f.tmdbMode) {
                    // A service lists both movies and series; a studio or network has one kind.
                    if (svc != null) listOf("movie" to "Movies", "series" to "Series").forEachIndexed { i, (t, label) ->
                        item {
                            TvChip(label, selected = f.tmdbType == t, onClick = { vm.setFilters { it.copy(tmdbType = t) } },
                                modifier = if (i == 0) Modifier.focusRequester(topFocus) else Modifier)
                        }
                    }
                    item {
                        TvChip("${svc?.label ?: std?.label} ✕", selected = false, onClick = { vm.setFilters { it.copy(service = null, studio = null) } },
                            modifier = if (svc == null) Modifier.focusRequester(topFocus) else Modifier)
                    }
                } else {
                    item { TvChip("$catalogLabel ▾", selected = false, onClick = { dialog = BrowseDialog.CATALOG }, modifier = Modifier.focusRequester(topFocus)) }
                }
                // Genre, rating, decade and sort live behind one button.
                val active = listOf(f.genre != null && genreAllowed, f.minRating != null, f.decade != null, f.sort != BrowseSort.DEFAULT).count { it }
                item { TvChip(if (active > 0) "Filters · $active ▾" else "Filters ▾", selected = active > 0, onClick = { filtersOpen = true }) }
                item { Text(if (ui.loading) "loading…" else "${ui.items.size} titles", color = Palette.TextMuted, fontSize = 13.sp) }
            }
            when {
                ui.error != null && ui.items.isEmpty() -> CenteredMessage("Couldn't load titles", ui.error)
                ui.items.isEmpty() && !ui.loading && ui.endReached ->
                    CenteredMessage("Nothing matches", "No titles match these filters. Try widening them.")
                ui.items.isEmpty() -> CenteredMessage("Loading…")
                else -> PosterGrid(
                    ui.items,
                    onOpen,
                    Modifier.fillMaxSize(),
                    columns = COLUMNS,
                    onNearEnd = { vm.loadMore() },
                    onFocused = { i, m ->
                        focusedIndex = i
                        focused = m
                    },
                    contentPadding = PaddingValues(start = 48.dp, end = 48.dp, top = 6.dp, bottom = 48.dp),
                    state = gridState,
                    header = newEpisodes.takeIf { it.isNotEmpty() }?.let { list ->
                        {
                            // Shows you watch with episodes out since you last watched; the row bleeds past the grid padding.
                            MediaRow(
                                title = "New Episodes",
                                items = list,
                                key = { it.meta.id },
                                modifier = Modifier.padding(bottom = 4.dp).layout { measurable, constraints ->
                                    val extra = 96.dp.roundToPx()
                                    val p = measurable.measure(constraints.copy(maxWidth = constraints.maxWidth + extra))
                                    layout(constraints.maxWidth, p.height) { p.place(-extra / 2, 0) }
                                },
                            ) { _, item, mod ->
                                PosterCard(item.meta, onClick = { onOpen(item.meta) }, modifier = mod, badge = item.badge, onFocused = { focused = it })
                            }
                        }
                    },
                )
            }
        }
    }

    if (filtersOpen) {
        ActionSheet(
            title = "Filters",
            onDismiss = { filtersOpen = false },
            actions = buildList {
                if (!vm.isAnime && c.tmdb.enabled) {
                    add(SheetAction("Streaming service", svc?.label ?: "Any") { dialog = BrowseDialog.SERVICE })
                    add(SheetAction(if (type == "series") "Network" else "Studio", std?.label ?: "Any") { dialog = BrowseDialog.STUDIO })
                }
                if ((genreAllowed || f.tmdbMode) && ui.genres.isNotEmpty()) add(SheetAction("Genre", f.genre ?: "All") { dialog = BrowseDialog.GENRE })
                add(SheetAction("Rating", ratingLabel(f.minRating)) { dialog = BrowseDialog.RATING })
                add(SheetAction("Decade", decadeLabel(f.decade)) { dialog = BrowseDialog.DECADE })
                add(SheetAction("Sort", f.sort.label) { dialog = BrowseDialog.SORT })
                if (f.genre != null || f.minRating != null || f.decade != null || f.sort != BrowseSort.DEFAULT) {
                    add(SheetAction("Clear filters") { vm.setFilters { it.copy(genre = null, minRating = null, decade = null, sort = BrowseSort.DEFAULT) } })
                }
            },
        )
    }

    when (dialog) {
        BrowseDialog.CATALOG -> ChoiceDialog(
            title = "Catalog",
            options = ui.catalogs.map { ChoiceOption(it.id, it.label) },
            selected = setOf(f.catalog),
            multiSelect = false,
            onToggle = { id -> vm.setFilters { it.copy(catalog = id) } },
            onDismiss = { dialog = null },
        )
        BrowseDialog.GENRE -> ChoiceDialog(
            title = "Genre",
            options = listOf(ChoiceOption("", "All genres")) + ui.genres.map { ChoiceOption(it, it) },
            selected = setOf(f.genre.orEmpty()),
            multiSelect = false,
            onToggle = { g -> vm.setFilters { it.copy(genre = g.ifEmpty { null }) } },
            onDismiss = { dialog = null },
        )
        BrowseDialog.RATING -> ChoiceDialog(
            title = "Minimum rating",
            options = ratingOptions.map { ChoiceOption(it?.toString() ?: "", ratingLabel(it)) },
            selected = setOf(f.minRating?.toString() ?: ""),
            multiSelect = false,
            onToggle = { v -> vm.setFilters { it.copy(minRating = v.toDoubleOrNull()) } },
            onDismiss = { dialog = null },
        )
        BrowseDialog.DECADE -> ChoiceDialog(
            title = "Decade",
            options = decadeOptions.map { ChoiceOption(it?.toString() ?: "", decadeLabel(it)) },
            selected = setOf(f.decade?.toString() ?: ""),
            multiSelect = false,
            onToggle = { v -> vm.setFilters { it.copy(decade = v.toIntOrNull()) } },
            onDismiss = { dialog = null },
        )
        BrowseDialog.SORT -> ChoiceDialog(
            title = "Sort",
            options = BrowseSort.entries.map { ChoiceOption(it.name, it.label) },
            selected = setOf(f.sort.name),
            multiSelect = false,
            onToggle = { v -> vm.setFilters { it.copy(sort = BrowseSort.valueOf(v)) } },
            onDismiss = { dialog = null },
        )
        BrowseDialog.SERVICE -> ChoiceDialog(
            title = "Streaming service",
            // Your services first, then the big ones.
            options = listOf(ChoiceOption("", "Any")) + (settings.myServices.map { (id, name) -> ChoiceOption(id, name) } +
                com.zemu.tv.data.StreamingService.entries.map { ChoiceOption(it.ids, it.label) }).distinctBy { it.value },
            selected = setOf(f.service.orEmpty()),
            multiSelect = false,
            onToggle = { v ->
                val label = settings.myServices[v] ?: com.zemu.tv.data.StreamingService.entries.firstOrNull { it.ids == v }?.label
                vm.setFilters { it.copy(service = v.ifEmpty { null }, serviceLabel = label, studio = null, tmdbType = if (type == "series") "series" else "movie") }
            },
            onDismiss = { dialog = null },
        )
        BrowseDialog.STUDIO -> ChoiceDialog(
            title = if (type == "series") "Network" else "Studio",
            options = listOf(ChoiceOption("", "Any")) + com.zemu.tv.data.Studio.forType(if (type == "series") "series" else "movie").map { ChoiceOption(it.key, it.label) },
            selected = setOf(f.studio.orEmpty()),
            multiSelect = false,
            onToggle = { v -> vm.setFilters { it.copy(studio = v.ifEmpty { null }, service = null, tmdbType = if (type == "series") "series" else "movie") } },
            onDismiss = { dialog = null },
        )
        null -> {}
    }
}
