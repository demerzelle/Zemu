package com.zemu.tv.ui.home

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

@Composable
fun HomeScreen(onOpen: (Meta) -> Unit, onOpenSettings: () -> Unit) {
    val context = LocalContext.current
    val c = context.container
    val vm: HomeViewModel = viewModel { HomeViewModel(c) }
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
        focused?.let { hero = it }
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
            LazyColumn(
                Modifier.fillMaxSize(),
                contentPadding = PaddingValues(bottom = 48.dp),
            ) {
                if (state.noStreamAddons) {
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
                items(state.rows, key = { it.key }) { row ->
                    val requesters = buildMap {
                        savedFocus?.takeIf { it.startsWith("${row.key}|") }?.let { put(it.substringAfter('|'), restoreRequester) }
                        if (row === firstRow) row.items.firstOrNull()?.let { put(it.id, firstRequester) }
                    }
                    val onFocus: (Meta) -> Unit = { m ->
                        focused = m
                        savedFocus = "${row.key}|${m.id}"
                    }
                    MediaRow(
                        title = row.title,
                        items = row.items,
                        key = { it.id },
                        requesters = requesters,
                    ) { _, m, mod ->
                        when (row.style) {
                            RowStyle.LANDSCAPE -> ContinueCard(m, row.subtitles[m.id], row.progress[m.id] ?: 0f, onClick = { onOpen(m) }, modifier = mod, onFocused = onFocus)
                            RowStyle.POSTER -> PosterCard(m, onClick = { onOpen(m) }, modifier = mod, onFocused = onFocus, badge = row.badges[m.id] ?: row.match[m.id]?.let { "$it%" })
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun StatusLine(text: String) {
    Box(Modifier.fillMaxWidth().padding(horizontal = 48.dp, vertical = 16.dp), contentAlignment = Alignment.CenterStart) {
        Text(text, color = Palette.TextSecondary, fontSize = 15.sp)
    }
}
