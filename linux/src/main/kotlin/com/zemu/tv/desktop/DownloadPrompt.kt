package com.zemu.tv.desktop

import android.widget.Toast
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.tv.material3.Text
import com.zemu.tv.AppContainer
import com.zemu.tv.ZemuApp
import com.zemu.tv.data.Meta
import com.zemu.tv.data.Video
import com.zemu.tv.data.title
import com.zemu.tv.streams.FilterState
import com.zemu.tv.streams.ParsedStream
import com.zemu.tv.streams.StreamFilter
import com.zemu.tv.ui.components.TvButton
import com.zemu.tv.ui.theme.Palette
import com.zemu.tv.ui.theme.glassPanel
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import java.io.File

/**
 * "Download for offline", "Download season" and "Download all seasons" all open this prompt: what
 * will be saved, how big it is and where it goes, with Change folder before anything starts.
 */
object DownloadPrompt {
    sealed class Request(val meta: Meta) {
        /** One stream the user picked for one movie or episode. */
        class Single(meta: Meta, val videoId: String, val label: String?, val stream: ParsedStream) : Request(meta)
        /** Several episodes; a stream is chosen for each when the prompt opens. */
        class Episodes(meta: Meta, val heading: String, val episodes: List<Video>) : Request(meta)
    }

    var request by mutableStateOf<Request?>(null)

    fun single(meta: Meta, videoId: String, label: String?, stream: ParsedStream) {
        request = Request.Single(meta, videoId, label, stream)
    }

    /** Released episodes of [season] (or every season but the specials when null), in order. */
    fun episodes(meta: Meta, season: Int?): List<Video> {
        val today = java.time.LocalDate.now().toString()
        return meta.videos
            .filter { v -> if (season == null) (v.season ?: 0) != 0 else v.season == season }
            .filter { v -> v.released?.take(10)?.let { it <= today } != false }
            .sortedWith(compareBy({ it.season ?: 0 }, { it.episodeNumber }))
    }

    fun season(meta: Meta, season: Int) {
        request = Request.Episodes(meta, if (season == 0) "Download the specials" else "Download season $season", episodes(meta, season))
    }

    fun allSeasons(meta: Meta) {
        request = Request.Episodes(meta, "Download all seasons", episodes(meta, null))
    }

    fun label(v: Video) = if (v.season != null) "S${v.season} E${v.episodeNumber} · ${v.displayTitle}" else v.displayTitle
}

/** The stream picked for one episode (null: nothing cached for it yet). */
private class Planned(val video: Video, val stream: ParsedStream?)

/**
 * Picks a cached stream for every episode, the best-ranked one for the first and then the same
 * release (season pack) for the rest whenever it's cached, so quality and audio match.
 */
private suspend fun plan(c: AppContainer, meta: Meta, episodes: List<Video>, progress: (Int) -> Unit): List<Planned> {
    val settings = c.userStore.settings.value
    suspend fun ranked(v: Video): List<ParsedStream> {
        val all = runCatching { c.streams.load(meta.type, v.id).cached }.getOrDefault(emptyList())
        return StreamFilter.apply(all, c.streamFilter.value, c.capabilities, settings, emptySet())
            .ifEmpty { StreamFilter.apply(all, FilterState(), c.capabilities, settings, emptySet()) }
            .map { it.stream }.filter { it.raw.url?.startsWith("http") == true }
    }
    var done = 0
    val first = episodes.firstOrNull() ?: return emptyList()
    val firstPick = ranked(first).firstOrNull()
    progress(++done)
    val group = firstPick?.raw?.behaviorHints?.bingeGroup
    val gate = Semaphore(4)
    val rest = kotlinx.coroutines.coroutineScope {
        episodes.drop(1).map { v ->
            async {
                gate.withPermit {
                    val list = ranked(v)
                    Planned(v, list.firstOrNull { group != null && it.raw.behaviorHints?.bingeGroup == group } ?: list.firstOrNull())
                        .also { synchronized(episodes) { progress(++done) } }
                }
            }
        }.awaitAll()
    }
    return listOf(Planned(first, firstPick)) + rest
}

private fun gb(bytes: Long) = "%.1f GB".format(bytes / 1e9)

/** Shown over the whole app while [DownloadPrompt.request] is set. */
@Composable
fun DownloadDialog() {
    val req = DownloadPrompt.request ?: return
    val c = ZemuApp.container
    val downloads = c.downloads
    val context = androidx.compose.ui.platform.LocalContext.current
    val defaultRoot by downloads.folderState.collectAsState()
    var root by remember(req) { mutableStateOf(defaultRoot) }
    var picking by remember(req) { mutableStateOf(false) }
    var plan by remember(req) { mutableStateOf<List<Planned>?>(null) }
    var found by remember(req) { mutableStateOf(0) }
    val close = { DownloadPrompt.request = null }

    if (req is DownloadPrompt.Request.Episodes) LaunchedEffect(req) {
        plan = plan(c, req.meta, req.episodes) { found = it }
    }

    DpadDialog(onDismissRequest = { if (picking) picking = false else close() }) {
        if (picking) {
            FolderPicker(root, onPick = { root = it; picking = false }, onCancel = { picking = false })
            return@DpadDialog
        }
        val first = remember { FocusRequester() }
        LaunchedEffect(Unit) { kotlinx.coroutines.delay(80); runCatching { first.requestFocus() } }
        // Where it goes: the series folder (and season) under the chosen root.
        val target: File = when (req) {
            is DownloadPrompt.Request.Single -> downloads.targetFor(req.meta, req.videoId, root)
            is DownloadPrompt.Request.Episodes -> req.episodes.map { it.season }.distinct().singleOrNull()
                ?.let { downloads.targetFor(req.meta, req.episodes.first().id, root) }
                ?: downloads.targetFor(req.meta, req.meta.id, root)
        }
        Column(Modifier.width(640.dp).glassPanel(com.zemu.tv.ui.theme.boxy(RoundedCornerShape(16.dp))).padding(26.dp)) {
            val ready: Boolean
            when (req) {
                is DownloadPrompt.Request.Single -> {
                    ready = true
                    Text("Download", fontSize = 24.sp, fontWeight = FontWeight.Black)
                    Text(listOfNotNull(req.meta.title, req.label).joinToString(" · "), fontSize = 17.sp, modifier = Modifier.padding(top = 6.dp))
                    Text(listOfNotNull(req.stream.resolutionLabel, req.stream.sizeLabel).joinToString(" · "), color = Palette.TextSecondary, fontSize = 14.sp)
                }
                is DownloadPrompt.Request.Episodes -> {
                    val p = plan
                    ready = p != null && p.any { it.stream != null }
                    Text(req.heading, fontSize = 24.sp, fontWeight = FontWeight.Black)
                    Text(req.meta.title, fontSize = 17.sp, modifier = Modifier.padding(top = 6.dp))
                    val series = req.meta.type == "series"
                    val line = when {
                        req.episodes.isEmpty() -> "No released episodes to download."
                        p == null -> if (series) "Finding cached streams… $found of ${req.episodes.size}" else "Finding the best cached stream…"
                        !series -> p.firstOrNull()?.stream?.let { s -> listOfNotNull(s.resolutionLabel, s.sizeLabel).joinToString(" · ") }
                            ?: "No cached stream for this title yet."
                        else -> {
                            val ok = p.filter { it.stream != null }
                            val size = ok.sumOf { it.stream?.sizeBytes ?: 0L }
                            buildString {
                                append("${ok.size} episode${if (ok.size == 1) "" else "s"}")
                                if (size > 0) append(" · about ${gb(size)}")
                                val missing = p.size - ok.size
                                if (missing > 0) append("\n$missing with no cached stream yet will be skipped")
                            }
                        }
                    }
                    Text(line, color = Palette.TextSecondary, fontSize = 14.sp)
                }
            }
            Text("Saving to", color = Palette.TextMuted, fontSize = 13.sp, modifier = Modifier.padding(top = 16.dp))
            Text(target.path, fontSize = 15.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
            Text("${gb(generateSequence(target) { it.parentFile }.first { it.exists() }.usableSpace)} free", color = Palette.TextMuted, fontSize = 13.sp)
            Row(Modifier.padding(top = 20.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                TvButton(if (ready) "Download" else "Finding streams…", primary = true, modifier = Modifier.focusRequester(first), onClick = {
                    if (!ready) return@TvButton
                    val message = when (req) {
                        is DownloadPrompt.Request.Single -> downloads.start(
                            req.meta, req.videoId, req.label, req.stream.raw.url.orEmpty(),
                            req.stream.raw.behaviorHints?.proxyHeaders?.request.orEmpty(), req.stream.raw.behaviorHints?.filename,
                            req.stream.sizeBytes, downloads.targetFor(req.meta, req.videoId, root),
                        ) ?: "Downloading to ${target.path}"
                        is DownloadPrompt.Request.Episodes -> {
                            val errors = plan.orEmpty().filter { it.stream != null }.mapNotNull { (it.video to it.stream!!).let { (v, s) ->
                                downloads.start(
                                    req.meta, v.id, if (req.meta.type == "series") DownloadPrompt.label(v) else null, s.raw.url.orEmpty(), s.raw.behaviorHints?.proxyHeaders?.request.orEmpty(),
                                    s.raw.behaviorHints?.filename, s.sizeBytes, downloads.targetFor(req.meta, v.id, root),
                                )
                            } }
                            val started = plan.orEmpty().count { it.stream != null } - errors.size
                            val what = if (req.meta.type != "series") req.meta.title else "$started episode${if (started == 1) "" else "s"}"
                            if (started > 0) "Downloading $what to ${target.path}" +
                                (if (errors.isNotEmpty()) " (${errors.size} skipped: ${errors.first()})" else "")
                            else errors.firstOrNull() ?: "Nothing to download."
                        }
                    }
                    Toast.makeText(context, message, Toast.LENGTH_LONG).show()
                    close()
                })
                TvButton("Change folder", onClick = { picking = true })
                TvButton("Cancel", onClick = close)
            }
        }
    }
}

/** Settings → Downloads → Download folder: the same browser, changing the default. */
object FolderSetting {
    var open by mutableStateOf(false)
}

@Composable
fun FolderSettingDialog() {
    if (!FolderSetting.open) return
    val downloads = ZemuApp.container.downloads
    DpadDialog(onDismissRequest = { FolderSetting.open = false }) {
        FolderPicker(downloads.folder, onPick = { downloads.setFolder(it); FolderSetting.open = false }, onCancel = { FolderSetting.open = false })
    }
}
