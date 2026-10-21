package com.zemu.tv.ui.person

import com.zemu.tv.ui.components.ZemuLoader

import android.widget.Toast
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.tv.material3.MaterialTheme
import androidx.tv.material3.Text
import com.zemu.tv.AppContainer
import com.zemu.tv.container
import com.zemu.tv.data.Meta
import com.zemu.tv.data.TmdbCredit
import com.zemu.tv.ui.components.CenteredMessage
import com.zemu.tv.ui.components.MediaRow
import com.zemu.tv.ui.components.PosterCard
import com.zemu.tv.ui.components.RemoteImage
import com.zemu.tv.ui.components.ScrollingText
import com.zemu.tv.ui.theme.Palette
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch

/** Unified person data for the page, from TMDB or the free sources. */
data class PersonPage(
    val name: String,
    val photo: String?,
    val facts: List<String>,
    val bio: String?,
    val movies: List<Meta>,
    val series: List<Meta>,
    /** TMDB credits need resolving to IMDb ids before opening. */
    val tmdbCredits: Map<String, TmdbCredit> = emptyMap(),
)

class PersonViewModel(private val c: AppContainer, val key: String) : ViewModel() {
    val page = MutableStateFlow<PersonPage?>(null)
    val error = MutableStateFlow<String?>(null)

    init {
        // Show the name and photo right away; the full filmography (Wikidata) can take a while.
        if (!key.startsWith("tmdb:") || !c.tmdb.enabled) viewModelScope.launch {
            runCatching { c.freeCast.personHeader(key) }.getOrNull()?.let { (name, photo) ->
                if (page.value == null) page.value = PersonPage(name, photo, listOf("Loading filmography…"), null, emptyList(), emptyList())
            }
        }
        viewModelScope.launch {
            runCatching { load() }
                .onSuccess {
                    if (it != null) page.value = it
                    else if (page.value == null) error.value = "No details found for this person"
                    else page.value = page.value?.copy(facts = listOf("No filmography found"))
                }
                .onFailure { error.value = it.message ?: "Couldn't load this person" }
        }
    }

    private suspend fun load(): PersonPage? {
        val tmdbId = key.substringAfter("tmdb:", "").toLongOrNull()
        if (tmdbId != null && c.tmdb.enabled) {
            val p = c.tmdb.person(tmdbId)
            val credits = p.credits
            val movies = credits.filter { !it.isSeries }.take(40)
            val series = credits.filter { it.isSeries }.take(40)
            return PersonPage(
                name = p.name,
                photo = p.photo,
                facts = listOfNotNull(p.department, p.birthday?.let { b -> "Born $b" + (p.placeOfBirth?.let { " · $it" } ?: "") }, p.deathday?.let { "Died $it" }),
                bio = p.biography,
                movies = movies.map { it.asMeta() },
                series = series.map { it.asMeta() },
                tmdbCredits = (movies + series).associateBy { it.asMeta().id },
            )
        }
        val p = c.freeCast.person(key) ?: return null
        return PersonPage(
            name = p.name,
            photo = p.photo,
            facts = listOfNotNull(p.description?.replaceFirstChar { it.uppercase() }, p.born?.let { "Born $it" }),
            bio = null,
            movies = p.credits.filter { it.type == "movie" }.take(60),
            series = p.credits.filter { it.type == "series" }.take(60),
        )
    }

    /** IMDb-based metas open directly; TMDB credits are translated first. */
    suspend fun resolve(meta: Meta): Meta? {
        if (meta.id.startsWith("tt")) return meta
        val credit = page.value?.tmdbCredits?.get(meta.id) ?: return null
        val imdb = runCatching { c.tmdb.imdbIdFor(credit) }.getOrNull() ?: return null
        return Meta(id = imdb, type = meta.type, name = meta.name)
    }
}

private fun TmdbCredit.asMeta() = Meta(
    id = "tmdb:$mediaType:$id",
    type = if (isSeries) "series" else "movie",
    name = displayTitle,
    poster = poster,
    releaseInfo = year,
    imdbRating = vote.takeIf { voteCount > 20 }?.let { "%.1f".format(it) },
)

@Composable
fun PersonScreen(key: String, onOpen: (Meta) -> Unit) {
    val context = LocalContext.current
    val c = context.container
    val vm: PersonViewModel = viewModel(key = "person-$key") { PersonViewModel(c, key) }
    val page by vm.page.collectAsStateWithLifecycle()
    val error by vm.error.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()
    val firstFocus = remember { FocusRequester() }

    val p = page
    if (p == null) {
        Box(Modifier.fillMaxSize()) {
            if (error != null) CenteredMessage("Couldn't load this person", error) else ZemuLoader()
        }
        return
    }
    LaunchedEffect(p.name) { runCatching { firstFocus.requestFocus() } }

    val open: (Meta) -> Unit = { meta ->
        scope.launch {
            val resolved = vm.resolve(meta)
            if (resolved != null) onOpen(resolved)
            else Toast.makeText(context, "\"${meta.name}\" isn't in the catalog yet", Toast.LENGTH_SHORT).show()
        }
    }

    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(top = 36.dp, bottom = 48.dp)) {
        item(key = "header") {
            Row(Modifier.padding(horizontal = 48.dp)) {
                Box(Modifier.width(150.dp).height(225.dp).clip(com.zemu.tv.ui.theme.boxy(RoundedCornerShape(12.dp))).background(Palette.SurfaceHigh)) {
                    RemoteImage(p.photo, Modifier.fillMaxSize())
                }
                Spacer(Modifier.width(28.dp))
                Column(Modifier.fillMaxWidth(0.8f)) {
                    Text(p.name, style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Black)
                    Text(p.facts.joinToString("   ·   "), color = Palette.TextSecondary, fontSize = 14.sp, modifier = Modifier.padding(vertical = 6.dp))
                    if (!p.bio.isNullOrBlank()) ScrollingText(p.bio, maxHeight = 150.dp, focusable = true)
                    Text("${p.movies.size} movies · ${p.series.size} series", color = Palette.TextMuted, fontSize = 13.sp, modifier = Modifier.padding(top = 8.dp))
                }
            }
            Spacer(Modifier.size(20.dp))
        }
        if (p.movies.isNotEmpty()) item(key = "movies") {
            MediaRow(title = "Movies", items = com.zemu.tv.ui.kids.kidsSafe(p.movies) { it }, key = { "m${it.id}" }, requesters = mapOf("m${p.movies.first().id}" to firstFocus)) { _, m, mod ->
                PosterCard(m, onClick = { open(m) }, modifier = mod, onLongClick = { open(m) })
            }
        }
        if (p.series.isNotEmpty()) item(key = "series") {
            MediaRow(title = "Series", items = com.zemu.tv.ui.kids.kidsSafe(p.series) { it }, key = { "s${it.id}" }, requesters = if (p.movies.isEmpty()) mapOf("s${p.series.first().id}" to firstFocus) else emptyMap()) { _, m, mod ->
                PosterCard(m, onClick = { open(m) }, modifier = mod, onLongClick = { open(m) })
            }
        }
    }
}
