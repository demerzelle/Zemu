package com.zemu.tv.ui.home

import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.draw.clip
import com.zemu.tv.ui.theme.glassPanel
import com.zemu.tv.ui.components.AppIcons
import androidx.compose.runtime.CompositionLocalProvider
import com.zemu.tv.ui.components.LocalRowOptions
import com.zemu.tv.ui.components.PinnedRows
import kotlinx.coroutines.launch
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.activity.compose.BackHandler
import com.zemu.tv.ui.components.heroTrailerTap
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.tv.material3.Text
import com.zemu.tv.container
import com.zemu.tv.data.Meta
import com.zemu.tv.ui.components.heroTrailerKeys
import com.zemu.tv.ui.components.Backdrop
import com.zemu.tv.ui.components.CenteredMessage
import com.zemu.tv.ui.components.ContinueCard
import com.zemu.tv.ui.components.HeroInfo
import com.zemu.tv.ui.components.MediaRow
import com.zemu.tv.ui.components.PosterCard
import com.zemu.tv.ui.components.TvButton
import com.zemu.tv.ui.theme.Palette
import kotlinx.coroutines.delay

/**
 * Home, and the Movies / Series / Anime pages ([page] "movie", "series", "anime"), which add a bar
 * to browse everything or one streaming service or studio. [onBrowse] opens that grid.
 */
@Composable
fun HomeScreen(
    onOpen: (Meta) -> Unit,
    onOpenSettings: () -> Unit,
    onPlay: (Meta) -> Unit = onOpen,
    page: String = "home",
    onBrowse: (type: String, service: String?, studio: String?) -> Unit = { _, _, _ -> },
) {
    val context = LocalContext.current
    val c = context.container
    val vm: HomeViewModel = viewModel(key = "rows-$page") { HomeViewModel(c, page) }
    var pageDialog by remember { mutableStateOf<String?>(null) }
    val state by vm.state.collectAsStateWithLifecycle()
    val settings by c.userStore.settings.collectAsStateWithLifecycle()

    var focused by remember { mutableStateOf<Meta?>(null) }
    var hero by remember { mutableStateOf<Meta?>(null) }
    var savedFocus by rememberSaveable { mutableStateOf<String?>(null) }
    val restoreRequester = remember { FocusRequester() }
    val firstRequester = remember { FocusRequester() }

    val firstRow = state.rows.firstOrNull()
    val firstKey = firstRow?.items?.firstOrNull()?.let { "${firstRow.key}|${it.id}" }

    // Debounce so fast scrolling doesn't thrash the backdrop.
    LaunchedEffect(focused) {
        delay(220)
        // Service logos and "See more" tiles aren't titles; keep the last title in the hero.
        focused?.takeIf { !it.id.startsWith("service:") && !it.id.startsWith("seemore:") }?.let { hero = it }
    }
    LaunchedEffect(firstKey) {
        if (hero == null) hero = firstRow?.items?.firstOrNull()
    }
    LaunchedEffect(firstKey != null) {
        if (firstKey == null) return@LaunchedEffect
        delay(80)
        val ok = savedFocus != null && runCatching { restoreRequester.requestFocus() }.isSuccess
        if (!ok) runCatching { firstRequester.requestFocus() }
    }

    // Back: first jump to the top of Home, then ask before leaving the app.
    val listState = rememberLazyListState()
    val scope = rememberCoroutineScope()
    var lastBack by remember { mutableLongStateOf(0L) }
    // Row being moved or favorited (popup with heart / up / down).
    var editingRow by remember { mutableStateOf<String?>(null) }
    val scrolled by remember { androidx.compose.runtime.derivedStateOf { listState.firstVisibleItemIndex > 0 || listState.firstVisibleItemScrollOffset > 0 } }
    // Other pages: Back at the top goes back as usual.
    BackHandler(enabled = page == "home" || scrolled) {
        val now = System.currentTimeMillis()
        when {
            listState.firstVisibleItemIndex > 0 || listState.firstVisibleItemScrollOffset > 0 -> scope.launch {
                listState.animateScrollToItem(0)
                runCatching { firstRequester.requestFocus() }
            }
            now - lastBack < 2_000 -> (context as? android.app.Activity)?.finish()
            else -> {
                lastBack = now
                android.widget.Toast.makeText(context, "Press Back again to exit Zemu", android.widget.Toast.LENGTH_SHORT).show()
            }
        }
    }

    Box(Modifier.fillMaxSize().heroTrailerKeys()) {
        Backdrop(
            hero,
            Modifier.fillMaxWidth().fillMaxHeight(0.62f),
            trailerAfterMs = if (settings.heroTrailers) 3_500L else null,
            trailerSound = settings.heroTrailerSound,
        )
        Column(Modifier.fillMaxSize()) {
            HeroInfo(hero, hero?.let { vm.match(it) }, Modifier.fillMaxWidth().fillMaxHeight(0.40f).heroTrailerTap())
            when {
                state.rows.isEmpty() && state.loading ->
                    StatusLine("Loading catalogs…")
                state.rows.isEmpty() && state.error != null ->
                    CenteredMessage("Nothing to show", state.error, action = { TvButton("Retry", onClick = vm::retry, primary = true) })
            }
            PinnedRows(anchor = 52.dp) { pinRow ->
            LazyColumn(
                Modifier.fillMaxSize(),
                state = listState,
                // Room below the last row so it can settle at the same spot as the others.
                contentPadding = PaddingValues(bottom = 420.dp),
            ) {
                if (state.noStreamAddons && page == "home") {
                    item(key = "no-streams") {
                        Column(Modifier.padding(horizontal = 48.dp, vertical = 8.dp)) {
                            Text(
                                "No stream addon installed yet. Add a debrid-enabled addon (AIOStreams, Torrentio, Comet, MediaFusion, …) in Addons to watch.",
                                color = Palette.Cached,
                                fontSize = 14.sp,
                            )
                            Spacer(Modifier.size(8.dp))
                            TvButton("Add addon", onClick = onOpenSettings)
                        }
                    }
                }
                if (page != "home") item(key = "page-bar") {
                    PageBar(page, onBrowse = { onBrowse(if (page == "anime") "anime" else page, null, null) }, onPick = { pageDialog = it }, tmdb = c.tmdb.enabled)
                }
                items(state.rows, key = { it.key }) { row ->
                    val requesters = buildMap {
                        savedFocus?.takeIf { it.startsWith("${row.key}|") }?.let { put(it.substringAfter('|'), restoreRequester) }
                        if (row === firstRow) row.items.firstOrNull()?.let { put(it.id, firstRequester) }
                    }
                    val onFocus: (Meta) -> Unit = { m ->
                        focused = m
                        savedFocus = "${row.key}|${m.id}"
                    }
                    pinRow {
                    CompositionLocalProvider(LocalRowOptions provides { editingRow = row.key }) {
                    val rowType = row.items.firstOrNull()?.type?.takeIf { page == "home" } ?: if (page == "series") "series" else "movie"
                    val more = row.service != null || row.studio != null
                    MediaRow(
                        title = row.title,
                        items = if (more) row.items + Meta(id = "seemore:${row.key}", name = "See more") else row.items,
                        key = { it.id },
                        requesters = requesters,
                        favorite = row.favorite,
                        onTitleLongPress = { editingRow = row.key },
                    ) { _, m, mod ->
                        when (row.style) {
                            RowStyle.LANDSCAPE -> ContinueCard(m, row.subtitles[m.id], row.progress[m.id] ?: 0f, onClick = {
                                // In Progress replays the same file from where it stopped.
                                if (row.key != "continue" || !com.zemu.tv.player.Playback.resumeSaved(context, m)) {
                                    if (row.key == "continue") onPlay(m) else onOpen(m)
                                }
                            }, modifier = mod, onFocused = onFocus)
                            RowStyle.SERVICES -> ServiceCard(m, modifier = mod, onFocused = onFocus) {
                                onBrowse(if (page == "series") "series" else "movie", m.id.removePrefix("service:"), null)
                            }
                            RowStyle.POSTER -> if (m.id.startsWith("seemore:")) SeeMoreCard(row.title, mod, onFocus = { onFocus(m) }) { onBrowse(rowType, row.service, row.studio) }
                            else PosterCard(m, onClick = { onOpen(m) }, modifier = mod, onFocused = onFocus, badge = row.badges[m.id] ?: row.match[m.id]?.let { "$it%" })
                        }
                    }
                    }
                    }
                }
            }
            }
        }
    }
    pageDialog?.let { which ->
        val type = if (page == "series") "series" else "movie"
        val options = if (which == "service") com.zemu.tv.data.StreamingService.entries.map { com.zemu.tv.ui.components.ChoiceOption(it.name, it.label) }
        else com.zemu.tv.data.Studio.forType(type).map { com.zemu.tv.ui.components.ChoiceOption(it.key, it.label) }
        com.zemu.tv.ui.components.ChoiceDialog(
            title = if (which == "service") "Streaming service" else if (type == "series") "Network" else "Studio",
            options = options,
            selected = emptySet(),
            multiSelect = false,
            onToggle = { v -> if (which == "service") onBrowse(type, v, null) else onBrowse(type, null, v) },
            onDismiss = { pageDialog = null },
        )
    }
    editingRow?.let { key ->
        val row = state.rows.firstOrNull { it.key == key }
        if (row == null) editingRow = null
        else RowEditor(
            favorite = row.favorite,
            onFavorite = { vm.toggleFavoriteRow(key) },
            onUp = { vm.moveRow(key, -1) },
            onDown = { vm.moveRow(key, 1) },
            onDismiss = { editingRow = null },
        )
    }
}

/** Heart (favorite), up and down: the only controls, per the row's long-press. Stays open for repeated moves. */
@Composable
private fun RowEditor(favorite: Boolean, onFavorite: () -> Unit, onUp: () -> Unit, onDown: () -> Unit, onDismiss: () -> Unit) {
    val first = remember { FocusRequester() }
    LaunchedEffect(Unit) { delay(60); runCatching { first.requestFocus() } }
    androidx.compose.ui.window.Dialog(onDismissRequest = onDismiss) {
        com.zemu.tv.ui.theme.DialogBackdropBlur()
        androidx.compose.foundation.layout.Row(
            Modifier.glassPanel(androidx.compose.foundation.shape.RoundedCornerShape(18.dp)).padding(12.dp),
            horizontalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(12.dp),
        ) {
            RowEditorButton(if (favorite) AppIcons.Heart else AppIcons.HeartOutline, if (favorite) "Remove from favorites" else "Add to favorites", Modifier.focusRequester(first), active = favorite, onClick = onFavorite)
            RowEditorButton(AppIcons.ArrowUp, "Move up", onClick = onUp)
            RowEditorButton(AppIcons.ArrowDown, "Move down", onClick = onDown)
        }
    }
}

@Composable
private fun RowEditorButton(icon: androidx.compose.ui.graphics.vector.ImageVector, label: String, modifier: Modifier = Modifier, active: Boolean = false, onClick: () -> Unit) {
    com.zemu.tv.ui.components.FocusSurface(
        onClick = onClick,
        modifier = modifier.size(64.dp),
        shape = androidx.compose.foundation.shape.CircleShape,
        containerColor = Palette.SurfaceHigh,
        contentColor = if (active) Palette.Accent else Palette.Text,
        focusedScale = 1.1f,
    ) {
        androidx.tv.material3.Icon(icon, contentDescription = label, modifier = Modifier.align(Alignment.Center).size(30.dp))
    }
}

@Composable
private fun StatusLine(text: String) {
    Box(Modifier.fillMaxWidth().padding(horizontal = 48.dp, vertical = 16.dp), contentAlignment = Alignment.CenterStart) {
        Text(text, color = Palette.TextSecondary, fontSize = 15.sp)
    }
}

/** Top of the Movies / Series / Anime pages: the page name and ways into the full catalog. */
@Composable
private fun PageBar(page: String, onBrowse: () -> Unit, onPick: (String) -> Unit, tmdb: Boolean) {
    androidx.compose.foundation.layout.Row(
        Modifier.padding(start = 48.dp, end = 48.dp, top = 4.dp, bottom = 4.dp),
        horizontalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        val noun = when (page) { "series" -> "Series"; "anime" -> "Anime"; else -> "Movies" }
        Text(noun, fontWeight = FontWeight.Black, fontSize = 22.sp, modifier = Modifier.padding(end = 6.dp))
        com.zemu.tv.ui.components.TvChip("All $noun ▸", selected = false, onClick = onBrowse)
        if (page != "anime" && tmdb) {
            com.zemu.tv.ui.components.TvChip("By streaming service ▾", selected = false, onClick = { onPick("service") })
            com.zemu.tv.ui.components.TvChip(if (page == "series") "By network ▾" else "By studio ▾", selected = false, onClick = { onPick("studio") })
        }
        if (!tmdb && page != "anime") Text("Add a free TMDB key in Settings → Addons for streaming services and studios.", color = Palette.TextMuted, fontSize = 13.sp)
    }
}

/** A streaming service tile: its logo (or name), opening everything on that service. */
@Composable
private fun ServiceCard(m: Meta, modifier: Modifier, onFocused: (Meta) -> Unit, onClick: () -> Unit) {
    com.zemu.tv.ui.components.FocusSurface(
        onClick = onClick,
        modifier = modifier.size(width = 168.dp, height = 96.dp).onFocusChanged { if (it.isFocused) onFocused(m) },
        shape = androidx.compose.foundation.shape.RoundedCornerShape(12.dp),
        focusedScale = 1.08f,
    ) {
        if (m.poster != null) {
            com.zemu.tv.ui.components.RemoteImage(
                m.poster, Modifier.align(Alignment.Center).padding(14.dp).fillMaxSize()
                    .clip(androidx.compose.foundation.shape.RoundedCornerShape(10.dp)),
                contentScale = androidx.compose.ui.layout.ContentScale.Fit,
            )
        } else Text(m.name.orEmpty(), fontWeight = FontWeight.Bold, fontSize = 18.sp, modifier = Modifier.align(Alignment.Center))
    }
}

/** Last tile of a service or studio row: opens the full, filterable list. */
@Composable
private fun SeeMoreCard(title: String, modifier: Modifier, onFocus: () -> Unit, onClick: () -> Unit) {
    com.zemu.tv.ui.components.FocusSurface(
        onClick = onClick,
        modifier = modifier.size(width = 132.dp, height = 198.dp).onFocusChanged { if (it.isFocused) onFocus() },
        shape = androidx.compose.foundation.shape.RoundedCornerShape(6.dp),
        focusedScale = 1.1f,
    ) {
        Column(Modifier.align(Alignment.Center).padding(10.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Text("See more", fontWeight = FontWeight.Black, fontSize = 17.sp)
            Text(title.substringAfter(" on ").substringAfter(" from ").substringAfter("Best of "), fontSize = 12.sp, maxLines = 2,
                color = androidx.tv.material3.LocalContentColor.current.copy(alpha = 0.7f), textAlign = androidx.compose.ui.text.style.TextAlign.Center)
        }
    }
}
