package com.zemu.tv.ui.search

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
import android.content.Intent
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
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
        val context = LocalContext.current
        val voiceIntent = remember {
            Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
                .putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                .putExtra(RecognizerIntent.EXTRA_PROMPT, "Search movies and series")
        }
        // Only devices with a speech recognizer (a mic remote, Google Assistant, ...) get the button.
        val canVoice = remember {
            SpeechRecognizer.isRecognitionAvailable(context) ||
                context.packageManager.queryIntentActivities(voiceIntent, 0).isNotEmpty()
        }
        val voice = rememberLauncherForActivityResult(ActivityResultContracts.StartActivityForResult()) { r ->
            r.data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)?.firstOrNull()?.let(vm::setQuery)
        }
        Row(
            Modifier.padding(start = 48.dp, end = 48.dp, top = 36.dp).fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (canVoice) {
                TvIconButton(AppIcons.Mic, "Voice search", modifier = Modifier.padding(end = 14.dp)) {
                    runCatching { voice.launch(voiceIntent) }
                }
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
            ui.loading -> "Searching…"
            ui.searched && ui.rows.isEmpty() -> "No results."
            else -> null
        }
        if (status != null) Text(status, color = Palette.TextSecondary, fontSize = 15.sp, modifier = Modifier.padding(horizontal = 48.dp, vertical = 14.dp))
        LazyColumn(contentPadding = PaddingValues(top = 12.dp, bottom = 48.dp)) {
            items(ui.rows, key = { it.first }) { (title, items) ->
                MediaRow(title = title, items = items, key = { it.id }) { _, m, mod ->
                    PosterCard(m, onClick = { onOpen(m) }, modifier = mod)
                }
            }
        }
    }
}
