package com.zemu.tv.ui.search

import com.zemu.tv.ui.components.TvChip
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.foundation.layout.Row
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import com.zemu.tv.ui.components.AppIcons
import com.zemu.tv.ui.components.TvIconButton
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.tv.material3.Text
import com.zemu.tv.AppContainer
import com.zemu.tv.container
import com.zemu.tv.data.Meta
import com.zemu.tv.ui.components.MediaRow
import com.zemu.tv.ui.components.PosterCard
import com.zemu.tv.ui.components.TvTextField
import com.zemu.tv.ui.theme.Palette
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

data class SearchUi(
    val query: String = "",
    val rows: List<Pair<String, List<Meta>>> = emptyList(),
    val loading: Boolean = false,
    val searched: Boolean = false,
)

class SearchViewModel(private val c: AppContainer) : ViewModel() {
    private val query = MutableStateFlow("")
    private val results = MutableStateFlow<List<Pair<String, List<Meta>>>>(emptyList())
    private val loading = MutableStateFlow(false)
    private var job: Job? = null

    val state = combine(query, results, loading) { q, rows, l ->
        SearchUi(query = q, rows = rows, loading = l, searched = q.length >= 2 && !l)
    }.stateIn(viewModelScope, SharingStarted.Eagerly, SearchUi())

    val recent = c.userStore.recentSearches

    fun remember(q: String) = viewModelScope.launch { c.userStore.addRecentSearch(q) }
    fun clearRecent() = viewModelScope.launch { c.userStore.clearRecentSearches() }

    fun setQuery(q: String) {
        query.value = q
        job?.cancel()
        job = viewModelScope.launch {
            delay(450)
            if (q.trim().length < 2) {
                results.value = emptyList()
                return@launch
            }
            loading.value = true
            val searchable = c.addons.addons.value.flatMap { a ->
                a.manifest.catalogs.filter { it.supportsExtra("search") }.map { a to it }
            }
            val rows = searchable.map { (addon, cat) ->
                async {
                    val items = runCatching { c.addons.catalog(addon, cat.type, cat.id, mapOf("search" to q.trim())) }.getOrDefault(emptyList())
                    val title = when (cat.type) { "movie" -> "Movies"; "series" -> "Series"; else -> cat.type.replaceFirstChar { it.uppercase() } }
                    title to items
                }
            }.awaitAll()
                .groupBy({ it.first }, { it.second })
                .map { (title, lists) -> title to lists.flatten().distinctBy { it.id } }
                .filter { it.second.isNotEmpty() }
            results.value = rows
            loading.value = false
        }
    }
}

@Composable
fun SearchScreen(onOpen: (Meta) -> Unit) {
    val c = LocalContext.current.container
    val vm: SearchViewModel = viewModel { SearchViewModel(c) }
    val ui by vm.state.collectAsStateWithLifecycle()
    val fieldRequester = remember { FocusRequester() }
    LaunchedEffect(Unit) { runCatching { fieldRequester.requestFocus() } }

    Column(Modifier.fillMaxSize()) {
        // Only devices with a speech recognizer (a mic remote, Google Assistant, ...) get the button.
        val voice = rememberVoiceSearch(vm::setQuery)
        Row(
            Modifier.padding(start = 48.dp, end = 48.dp, top = 36.dp).fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            voice.start?.let { start ->
                TvIconButton(AppIcons.Mic, "Voice search", modifier = Modifier.padding(end = 14.dp), active = voice.listening, onClick = start)
            }
            TvTextField(
                value = ui.query,
                onValueChange = vm::setQuery,
                placeholder = "Search movies and series",
                imeAction = ImeAction.Search,
                modifier = Modifier.weight(1f).focusRequester(fieldRequester),
            )
        }
        val status = when {
            voice.message != null -> voice.message
            ui.loading -> "Searching…"
            ui.searched && ui.rows.isEmpty() -> "No results."
            else -> null
        }
        // Recent searches while the box is empty.
        val recent by vm.recent.collectAsStateWithLifecycle()
        if (ui.query.isBlank() && recent.isNotEmpty()) {
            Text("Recent searches", color = Palette.TextSecondary, fontSize = 14.sp, modifier = Modifier.padding(start = 48.dp, top = 18.dp))
            LazyRow(contentPadding = PaddingValues(horizontal = 48.dp, vertical = 10.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                items(recent, key = { it }) { q -> TvChip(q, selected = false, onClick = { vm.setQuery(q) }) }
                item { TvChip("Clear", selected = false, onClick = { vm.clearRecent() }) }
            }
        }
        if (status != null) Text(status, color = Palette.TextSecondary, fontSize = 15.sp, modifier = Modifier.padding(horizontal = 48.dp, vertical = 14.dp))
        // Nothing typed: the titles you opened lately and Watch Later, one press away.
        val viewed = com.zemu.tv.ui.kids.kidsSafe(c.userStore.recentlyViewed.collectAsStateWithLifecycle().value) { it }
        val later = com.zemu.tv.ui.kids.kidsSafe(c.userStore.watchLater.collectAsStateWithLifecycle().value) { it }
        if (ui.query.isBlank()) {
            com.zemu.tv.ui.components.SectionedPosterGrid(
                listOf("Recently viewed" to viewed, "Watch Later" to later), onOpen, Modifier.fillMaxSize(),
                contentPadding = PaddingValues(start = 48.dp, end = 48.dp, top = 8.dp, bottom = 48.dp),
            )
            return@Column
        }
        LazyColumn(contentPadding = PaddingValues(top = 12.dp, bottom = 48.dp)) {
            items(ui.rows, key = { it.first }) { (title, items) ->
                val shown = com.zemu.tv.ui.kids.kidsSafe(items) { it }
                if (shown.isNotEmpty()) MediaRow(title = title, items = shown, key = { it.id }) { _, m, mod ->
                    PosterCard(m, onClick = { vm.remember(ui.query); onOpen(m) }, modifier = mod)
                }
            }
        }
    }
}
