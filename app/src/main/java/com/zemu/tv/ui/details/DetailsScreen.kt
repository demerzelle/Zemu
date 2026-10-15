package com.zemu.tv.ui.details

import com.zemu.tv.ui.theme.retroScrollbar
import com.zemu.tv.data.officialTrailers
import com.zemu.tv.ui.components.SheetAction
import com.zemu.tv.ui.components.ActionSheet
import com.zemu.tv.data.title
import com.zemu.tv.ui.components.heroTrailerTap
import android.content.Intent
import android.net.Uri
import android.widget.Toast
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.tv.material3.Border
import androidx.tv.material3.ClickableSurfaceDefaults
import androidx.tv.material3.Surface
import androidx.tv.material3.Text
import com.zemu.tv.container
import com.zemu.tv.data.Meta
import com.zemu.tv.data.Video
import com.zemu.tv.data.trailerId
import com.zemu.tv.player.Playback
import com.zemu.tv.player.TrailerActivity
import com.zemu.tv.ui.components.heroTrailerKeys
import com.zemu.tv.ui.components.ScrollingText
import com.zemu.tv.streams.FacetKind
import com.zemu.tv.streams.FilterState
import com.zemu.tv.streams.RankedStream
import com.zemu.tv.streams.SortOption
import com.zemu.tv.ui.components.AppIcons
import com.zemu.tv.ui.components.Backdrop
import com.zemu.tv.ui.components.CastMember
import com.zemu.tv.ui.components.CastRow
import com.zemu.tv.ui.components.CenteredMessage
import com.zemu.tv.ui.components.ChoiceDialog
import com.zemu.tv.ui.components.ChoiceOption
import com.zemu.tv.ui.components.MediaRow
import com.zemu.tv.ui.components.MetaLine
import com.zemu.tv.ui.components.PosterCard
import com.zemu.tv.ui.components.RemoteImage
import com.zemu.tv.ui.components.SectionTitle
import com.zemu.tv.ui.components.TitleLogo
import com.zemu.tv.ui.components.TvButton
import com.zemu.tv.ui.components.touchClick
import com.zemu.tv.ui.components.TvIconButton
import com.zemu.tv.ui.components.TvChip
import com.zemu.tv.ui.theme.Palette
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

@Composable
fun DetailsScreen(
    type: String,
    id: String,
    section: String = "",
    onOpen: (Meta) -> Unit,
    onOpenSettings: () -> Unit,
    onOpenPerson: (String) -> Unit = {},
    autoPlay: Boolean = false,
    onAutoPlayed: () -> Unit = {},
) {
    val context = LocalContext.current
    val c = context.container
    val vm: DetailsViewModel = viewModel(key = "$type/$id") { DetailsViewModel(c, type, id, autoPlay) }
    val autoPick by vm.autoPlay.collectAsStateWithLifecycle()
    val autoFailed by vm.autoPlayFailed.collectAsStateWithLifecycle()
    // Leave the page once an instant start launched from a poster, not from picking an episode here.
    var leaveAfterAutoPlay by remember { mutableStateOf(autoPlay) }
    val meta by vm.meta.collectAsStateWithLifecycle()
    val metaLoading by vm.metaLoading.collectAsStateWithLifecycle()
    val streams by vm.streams.collectAsStateWithLifecycle()
    val filter by vm.filter.collectAsStateWithLifecycle()
    val similar by vm.similar.collectAsStateWithLifecycle()
    val genreFavorites by vm.genreFavorites.collectAsStateWithLifecycle()
    val extras by vm.extras.collectAsStateWithLifecycle()
    val castPeople by vm.cast.collectAsStateWithLifecycle()
    var showCast by remember { mutableStateOf(false) }
    val castFocus = remember { FocusRequester() }
    val inMyList by vm.inMyList.collectAsStateWithLifecycle()
    val ratings by c.userStore.ratings.collectAsStateWithLifecycle()
    val rating = ratings[id] ?: 0
    val season by vm.selectedSeason.collectAsStateWithLifecycle()
    val selectedVideo by vm.selectedVideo.collectAsStateWithLifecycle()
    val settings by c.userStore.settings.collectAsStateWithLifecycle()

    val playRequester = remember { FocusRequester() }
    val listState = rememberLazyListState()
    val scope = rememberCoroutineScope()
    var openFacet by remember { mutableStateOf<FacetKind?>(null) }
    var sortOpen by remember { mutableStateOf(false) }
    var moreOpen by remember { mutableStateOf(false) }
    val history by c.userStore.history.collectAsStateWithLifecycle()
    val watchedIds by c.userStore.watched.collectAsStateWithLifecycle()

    val m = meta
    if (m == null) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            if (metaLoading) Text("Loading…", color = Palette.TextSecondary)
            else CenteredMessage("Couldn't load this title", "The metadata addon didn't respond.", action = {
                TvButton("Retry", onClick = { vm.retryMeta() }, primary = true)
            })
        }
        return
    }

    LaunchedEffect(m.id) {
        delay(80)
        runCatching { playRequester.requestFocus() }
        if (section == "episodes" && type == "series" && m.videos.isNotEmpty()) {
            delay(150)
            listState.animateScrollToItem(1)
        }
    }

    // "More like this": jump to that row once it has loaded, and onto its first title.
    val similarFocus = remember { FocusRequester() }
    var showSimilar by remember { mutableStateOf(section == "similar") }
    LaunchedEffect(showSimilar, similar.isNotEmpty(), m.id) {
        if (!showSimilar || similar.isEmpty()) return@LaunchedEffect
        // After the page's own first focus on Play (which runs when the title loads).
        delay(500)
        // The row is at the end: scrolling there brings it on screen, then focus lands on its first title.
        listState.animateScrollToItem((listState.layoutInfo.totalItemsCount - 1).coerceAtLeast(0))
        delay(150)
        if (runCatching { similarFocus.requestFocus() }.isSuccess) showSimilar = false
    }

    /** [picked]: chosen from the stream list, so play exactly that one instead of the saved file. */
    fun play(r: RankedStream, fromStart: Boolean = false, picked: Boolean = false) {
        Playback.play(context, m, vm.currentVideoId(), vm.episodeLabel(), r.stream, streams.externalSubs, alternatives = streams.streams.map { it.stream }, fromStart = fromStart, preferSaved = !picked)
    }

    LaunchedEffect(autoPick) {
        val pick = autoPick ?: return@LaunchedEffect
        vm.consumeAutoPlay()
        val rest = streams.streams.filter { it.stream.key != pick.stream.key }
        Playback.play(context, m, vm.currentVideoId(), vm.episodeLabel(), pick.stream, streams.externalSubs, alternatives = rest.map { it.stream })
        if (leaveAfterAutoPlay) { leaveAfterAutoPlay = false; delay(400); onAutoPlayed() }
    }
    LaunchedEffect(autoFailed) {
        if (autoFailed) {
            leaveAfterAutoPlay = false
            vm.autoPlayFailed.value = false
            Toast.makeText(context, "No cached streams to start right away", Toast.LENGTH_SHORT).show()
        }
    }

    val best = vm.preferred(streams.streams)

    /** Resume / start over: the saved file plays even before (or without) a fresh stream list. */
    fun playSavedOrBest(fromStart: Boolean) {
        val pick = best
        when {
            pick != null -> play(pick, fromStart)
            Playback.resumeSaved(context, m, fromStart) -> {}
            streams.result?.noStreamAddons == true -> onOpenSettings()
            !streams.loading -> Toast.makeText(context, "No cached streams for this title", Toast.LENGTH_SHORT).show()
        }
    }

    // Partly watched: "Resume from h:mm:ss" and "Start from beginning", both on the saved file.
    val resume = history.firstOrNull { it.meta.id == m.id && it.videoId == vm.currentVideoId() }
        ?.takeIf { it.durationMs > 0 && it.progress in 0.02f..0.95f && (m.type == "series" || m.id !in watchedIds) }
        ?.let { ResumeInfo(it.positionMs) }
    val hasSaved = resume != null && Playback.savedFor(context, m.id, vm.currentVideoId()) != null

    fun showCastRow() {
        showCast = !showCast
        if (showCast) scope.launch {
            delay(120)
            listState.animateScrollToItem(1)
            delay(200)
            runCatching { castFocus.requestFocus() }
        }
    }
    // Index of the "Cached streams" header inside the LazyColumn, used for "Choose stream".
    // The cast row (when shown) sits right after the header, before episodes.
    val streamsHeaderIndex = (if (type == "series" && m.videos.isNotEmpty()) 2 else 1) + (if (showCast) 1 else 0)

    Box(Modifier.fillMaxSize().heroTrailerKeys()) {
        // Only play the trailer while the header is on screen.
        val atTop by remember { derivedStateOf { listState.firstVisibleItemIndex == 0 && listState.firstVisibleItemScrollOffset < 200 } }
        Backdrop(
            m,
            Modifier.fillMaxWidth().height(520.dp),
            trailerAfterMs = if (settings.heroTrailers && atTop) 5_000L else null,
            trailerSound = settings.heroTrailerSound,
        )
        LazyColumn(state = listState, modifier = Modifier.fillMaxSize().retroScrollbar(listState), contentPadding = PaddingValues(bottom = 60.dp)) {
            item(key = "header") {
                Column(Modifier.heroTrailerTap().padding(start = 48.dp, top = 48.dp, end = 48.dp)) {
                    TitleLogo(m, maxHeight = 120)
                    Spacer(Modifier.size(14.dp))
                    MetaLine(m, vm.matchPercent(m))
                    if (m.genres.isNotEmpty()) {
                        Spacer(Modifier.size(6.dp))
                        Text(m.genres.joinToString("  •  "), color = Palette.TextSecondary, fontSize = 14.sp)
                    }
                    if (selectedVideo != null) {
                        Spacer(Modifier.size(10.dp))
                        Text(vm.episodeLabel().orEmpty(), fontWeight = FontWeight.Bold, fontSize = 16.sp)
                    }
                    Spacer(Modifier.size(10.dp))
                    ScrollingText(m.description.orEmpty(), maxHeight = 88.dp, modifier = Modifier.fillMaxWidth(0.62f), focusable = true)
                    val ex = extras
                    val directors = ex?.directors?.map { it.name }?.ifEmpty { null } ?: m.director.take(2)
                    val people = listOfNotNull(
                        directors.takeIf { it.isNotEmpty() }?.let { "Director: ${it.joinToString(", ")}" },
                        ex?.creators?.takeIf { it.isNotEmpty() }?.let { c -> "Created by: ${c.joinToString(", ") { it.name }}" },
                        ex?.studios?.takeIf { it.isNotEmpty() }?.let { "Studio: ${it.joinToString(", ")}" },
                        m.cast.take(4).takeIf { it.isNotEmpty() && ex == null }?.let { "Starring: ${it.joinToString(", ")}" },
                    )
                    people.forEach { Text(it, color = Palette.TextMuted, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis) }
                    Spacer(Modifier.size(20.dp))
                    // Four buttons; everything else lives under "More".
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                        val epTag = selectedVideo?.takeIf { it.season != null }?.let { "S${it.season} E${it.episodeNumber}" }
                        val playLabel = when {
                            resume != null && (best != null || hasSaved) ->
                                listOfNotNull("Resume", epTag).joinToString(" ") + " from ${com.zemu.tv.player.formatTime(resume.positionMs)}"
                            streams.loading -> "Finding cached streams…"
                            best == null -> "No cached streams"
                            else -> listOfNotNull("Play", epTag).joinToString(" ")
                        }
                        TvButton(
                            playLabel,
                            icon = Icons.Filled.PlayArrow,
                            primary = true,
                            modifier = Modifier.focusRequester(playRequester),
                            onClick = { playSavedOrBest(fromStart = false) },
                        )
                        if (resume != null && (best != null || hasSaved)) {
                            TvButton("Start from beginning", onClick = { playSavedOrBest(fromStart = true) })
                        }
                        m.officialTrailers.takeIf { it.isNotEmpty() && settings.trailers }?.let { list ->
                            TvButton(if (list.size > 1) "Trailers" else "Trailer", onClick = { TrailerActivity.start(context, list) })
                        }
                        TvButton("Streams", onClick = { scope.launch { listState.animateScrollToItem(streamsHeaderIndex) } })
                        TvButton(
                            if (inMyList) "In My List" else "My List",
                            icon = if (inMyList) Icons.Filled.Check else Icons.Filled.Add,
                            onClick = vm::toggleMyList,
                        )
                        TvButton("More", onClick = { moreOpen = true })
                    }
                    bestSummary(best)?.let {
                        Spacer(Modifier.size(8.dp))
                        Text("Best for this TV: $it", color = Palette.TextSecondary, fontSize = 13.sp)
                    }
                }
                Spacer(Modifier.size(24.dp))
            }

            if (showCast) {
                item(key = "cast") {
                    Spacer(Modifier.size(12.dp))
                    val people = castPeople.ifEmpty { m.cast.map { com.zemu.tv.data.CastPerson(it, null, null, "name:$it") } }
                    CastRow(
                        title = "Cast",
                        people = people.map { CastMember(it.personKey ?: "name:${it.name}", it.name, it.role, it.photo) },
                        onClick = { p -> onOpenPerson(p.key) },
                        firstFocus = castFocus,
                    )
                }
            }

            if (type == "series" && m.videos.isNotEmpty()) {
                item(key = "episodes") {
                    EpisodesSection(
                        seasons = vm.seasons,
                        season = season,
                        episodes = vm.episodes(season),
                        selected = selectedVideo,
                        nextUpId = remember(m.id, history) { vm.resumeEpisode(m).id },
                        progress = history.firstOrNull { it.meta.id == m.id }?.let { mapOf(it.videoId to it.progress) }.orEmpty(),
                        onSeason = vm::selectSeason,
                        onEpisodeFocused = {
                            // Keep the season chips, the summary and the episode row all on screen.
                            val target = if (showCast) 2 else 1
                            if (listState.firstVisibleItemIndex != target || listState.firstVisibleItemScrollOffset != 0) {
                                scope.launch { listState.animateScrollToItem(target) }
                            }
                        },
                        onEpisode = { v ->
                            if (settings.instantPlay) vm.selectEpisode(v, autoPlay = true)
                            else {
                                vm.selectEpisode(v)
                                scope.launch { listState.animateScrollToItem(streamsHeaderIndex) }
                            }
                        },
                    )
                }
            }

            item(key = "streams-header") {
                Column(Modifier.padding(top = 8.dp)) {
                    Row(Modifier.padding(horizontal = 48.dp), verticalAlignment = Alignment.CenterVertically) {
                        SectionTitle("Cached streams")
                        Spacer(Modifier.width(14.dp))
                        val r = streams.result
                        val summary = when {
                            streams.loading -> "searching your addons…"
                            r == null -> ""
                            r.noStreamAddons -> "no stream addons installed"
                            else -> "${streams.streams.size} shown · ${r.cached.size} cached · ${r.hiddenUncached} uncached hidden" +
                                if (r.failedAddons.isNotEmpty()) " · failed: ${r.failedAddons.joinToString()}" else ""
                        }
                        Text(summary, color = Palette.TextMuted, fontSize = 14.sp)
                        Spacer(Modifier.weight(1f))
                        if (!streams.loading) TvChip("↻ Refresh", selected = false, onClick = vm::reloadStreams)
                    }
                    if (streams.result?.cached?.isNotEmpty() == true) {
                        FilterBar(
                            filter = filter,
                            facets = streams.facets,
                            externalSubLangs = streams.externalSubLangs,
                            onSort = { sortOpen = true },
                            onFacet = { openFacet = it },
                            onToggleDeviceFriendly = { vm.updateFilter { it.copy(deviceFriendlyOnly = !it.deviceFriendlyOnly) } },
                            onToggleCam = { vm.updateFilter { it.copy(hideCam = !it.hideCam) } },
                            onReset = { vm.updateFilter { FilterState(sort = it.sort) } },
                        )
                    }
                    Spacer(Modifier.size(8.dp))
                }
            }

            val r = streams.result
            when {
                streams.loading -> item(key = "streams-loading") { Hint("Asking your addons for debrid-cached streams…") }
                r == null -> {}
                r.noStreamAddons -> item(key = "streams-none") {
                    Column(Modifier.padding(horizontal = 48.dp)) {
                        Hint("Install a debrid-enabled stream addon to watch. Only cached results are ever shown.", padded = false)
                        Spacer(Modifier.size(8.dp))
                        TvButton("Manage addons", onClick = onOpenSettings, primary = true)
                    }
                }
                r.cached.isEmpty() -> item(key = "streams-empty") {
                    Hint(
                        if (r.totalFound > 0) "Found ${r.totalFound} streams, but none are cached on your debrid service yet."
                        else "Your addons returned no streams for this ${if (type == "series") "episode" else "title"}.",
                    )
                }
                streams.streams.isEmpty() -> item(key = "streams-filtered") {
                    Column(Modifier.padding(horizontal = 48.dp)) {
                        Hint("No cached streams match these filters.", padded = false)
                        Spacer(Modifier.size(8.dp))
                        TvButton("Reset filters", onClick = { vm.updateFilter { FilterState(sort = it.sort) } })
                    }
                }
                else -> items(streams.streams, key = { "s-" + it.stream.key }) { rs ->
                    StreamRow(rs, streams.externalSubLangs, onClick = { play(rs, picked = true) }, modifier = Modifier.padding(vertical = 5.dp))
                }
            }

            if (similar.isNotEmpty()) {
                item(key = "similar") {
                    Spacer(Modifier.size(24.dp))
                    val shownSimilar = com.zemu.tv.ui.kids.kidsSafe(similar) { it.meta }
                    MediaRow(title = "More Like This", items = shownSimilar, key = { it.meta.id }, requesters = shownSimilar.firstOrNull()?.let { mapOf(it.meta.id to similarFocus) }.orEmpty()) { _, s, mod ->
                        PosterCard(s.meta, onClick = { onOpen(s.meta) }, modifier = mod, badge = "${s.matchPercent}%")
                    }
                }
            }
            genreFavorites?.let { (genre, items) ->
                item(key = "genre-favorites") {
                    Spacer(Modifier.size(12.dp))
                    MediaRow(title = "Top $genre Picks", items = com.zemu.tv.ui.kids.kidsSafe(items) { it.meta }, key = { it.meta.id }) { _, s, mod ->
                        PosterCard(s.meta, onClick = { onOpen(s.meta) }, modifier = mod, badge = "${s.matchPercent}%")
                    }
                }
            }
        }
    }

    if (moreOpen) {
        val watched = m.id in watchedIds
        ActionSheet(
            title = m.title,
            onDismiss = { moreOpen = false },
            actions = buildList {
                add(SheetAction(if (rating > 0) "Remove like" else "Like", if (rating > 0) "👍 Liked" else null) { vm.rate(if (rating > 0) 0 else 1) })
                add(SheetAction(if (rating < 0) "Remove dislike" else "Not for me", if (rating < 0) "👎" else null) { vm.rate(if (rating < 0) 0 else -1) })
                if (castPeople.isNotEmpty() || m.cast.isNotEmpty()) add(SheetAction(if (showCast) "Hide cast" else "View cast") { showCastRow() })
                add(SheetAction(if (watched) "Mark as unwatched" else "Mark as watched") { scope.launch { c.userStore.setWatched(m, !watched) } })
                if (similar.isNotEmpty()) add(SheetAction("More like this") { showSimilar = true })
                add(SheetAction("Refresh streams") { vm.reloadStreams() })
            },
        )
    }

    openFacet?.let { kind ->
        ChoiceDialog(
            title = kind.label,
            options = streams.facets[kind].orEmpty().map { ChoiceOption(it.value, it.label, it.count.toString()) },
            selected = filter.selected[kind].orEmpty(),
            onToggle = { v -> vm.updateFilter { it.toggle(kind, v) } },
            onClear = { vm.updateFilter { it.clear(kind) } },
            onDismiss = { openFacet = null },
        )
    }
    if (sortOpen) {
        ChoiceDialog(
            title = "Sort streams",
            options = SortOption.entries.map { ChoiceOption(it.name, it.label) },
            selected = setOf(filter.sort.name),
            multiSelect = false,
            onToggle = { v -> vm.updateFilter { it.copy(sort = SortOption.valueOf(v)) } },
            onDismiss = { sortOpen = false },
        )
    }
}

@Composable
private fun Hint(text: String, padded: Boolean = true) {
    Text(
        text,
        color = Palette.TextSecondary,
        fontSize = 15.sp,
        modifier = if (padded) Modifier.padding(horizontal = 48.dp, vertical = 12.dp) else Modifier.padding(vertical = 8.dp),
    )
}

@Composable
private fun EpisodesSection(
    seasons: List<Int>,
    season: Int?,
    episodes: List<Video>,
    selected: Video?,
    nextUpId: String?,
    progress: Map<String, Float>,
    onSeason: (Int) -> Unit,
    onEpisodeFocused: () -> Unit,
    onEpisode: (Video) -> Unit,
) {
    Column {
        SectionTitle("Episodes", Modifier.padding(horizontal = 48.dp))
        LazyRow(
            contentPadding = PaddingValues(horizontal = 48.dp, vertical = 10.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            items(seasons, key = { it }) { s ->
                TvChip(if (s == 0) "Specials" else "Season $s", selected = s == season, onClick = { onSeason(s) })
            }
        }
        var highlighted by remember(episodes) { mutableStateOf<Video?>(null) }
        // The highlighted episode's own summary (or the selected one's), above the row so it's never
        // pushed below the screen. Fixed height so the row doesn't jump between episodes.
        val shown = highlighted ?: selected?.takeIf { s -> episodes.any { it.id == s.id } } ?: episodes.firstOrNull()
        Column(Modifier.padding(horizontal = 48.dp).fillMaxWidth(0.8f).height(108.dp)) {
            if (shown != null) {
                Text(
                    listOfNotNull(
                        shown.season?.let { "S$it E${shown.episodeNumber}" },
                        shown.displayTitle,
                        shown.released?.take(10),
                    ).joinToString("  ·  "),
                    fontWeight = FontWeight.Bold, fontSize = 16.sp, maxLines = 1, overflow = TextOverflow.Ellipsis,
                )
                key(shown.id) {
                    ScrollingText(shown.synopsis ?: "No summary available for this episode.", maxHeight = 80.dp, fontSize = 14.sp, lineHeight = 20.sp)
                }
            }
        }
        LazyRow(
            contentPadding = PaddingValues(horizontal = 48.dp, vertical = 12.dp),
            horizontalArrangement = Arrangement.spacedBy(14.dp),
            modifier = Modifier.onFocusChanged { if (!it.hasFocus) highlighted = null },
        ) {
            items(episodes, key = { it.id }) { v ->
                EpisodeCard(v, v.id == selected?.id, nextUp = v.id == nextUpId, progress = progress[v.id] ?: 0f, onFocused = { highlighted = v; onEpisodeFocused() }) { onEpisode(v) }
            }
        }
    }
}

@Composable
private fun EpisodeCard(video: Video, selected: Boolean, nextUp: Boolean = false, progress: Float = 0f, onFocused: () -> Unit = {}, onClick: () -> Unit) {
    val shape = RoundedCornerShape(6.dp)
    Column(Modifier.width(230.dp)) {
        Surface(
            onClick = onClick,
            modifier = Modifier.fillMaxWidth().aspectRatio(16f / 9f).onFocusChanged { if (it.isFocused) onFocused() }.touchClick(onClick),
            shape = ClickableSurfaceDefaults.shape(shape = shape),
            scale = ClickableSurfaceDefaults.scale(focusedScale = 1.07f),
            border = ClickableSurfaceDefaults.border(
                border = if (selected) Border(BorderStroke(2.dp, Palette.Accent), shape = shape) else Border.None,
                focusedBorder = Border(BorderStroke(3.dp, Palette.FocusBorder), shape = shape),
            ),
            colors = ClickableSurfaceDefaults.colors(containerColor = Palette.Surface, focusedContainerColor = Palette.Surface),
        ) {
            RemoteImage(video.thumbnail, Modifier.fillMaxSize())
            Box(Modifier.fillMaxSize().background(Brush.verticalGradient(0.5f to Color.Transparent, 1f to Color.Black.copy(alpha = 0.85f))))
            Text(
                "E${video.episodeNumber}" + if (selected) "  ▶ selected" else "",
                modifier = Modifier.align(Alignment.BottomStart).padding(start = 8.dp, bottom = 12.dp),
                fontWeight = FontWeight.Bold,
                fontSize = 13.sp,
            )
            if (nextUp) Box(Modifier.align(Alignment.TopStart).padding(6.dp).background(Palette.Accent, RoundedCornerShape(4.dp)).padding(horizontal = 6.dp, vertical = 2.dp)) {
                Text("NEXT UP", color = Palette.OnAccent, fontSize = 11.sp, fontWeight = FontWeight.Black)
            }
            // How far you got in this episode.
            if (progress in 0.01f..0.97f) Box(Modifier.align(Alignment.BottomStart).fillMaxWidth().height(4.dp).background(Color.White.copy(alpha = 0.25f))) {
                Box(Modifier.fillMaxWidth(progress).fillMaxHeight().background(Palette.Accent))
            }
        }
        Spacer(Modifier.size(6.dp))
        Text(video.displayTitle, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
        video.released?.take(10)?.let { Text(it, color = Palette.TextMuted, fontSize = 12.sp) }
    }
}

private data class ResumeInfo(val positionMs: Long)
