package com.zemu.tv.player

import android.content.Context
import android.widget.Toast
import com.zemu.tv.container
import com.zemu.tv.data.Meta
import com.zemu.tv.data.SubtitleTrack
import com.zemu.tv.data.WatchEntry
import com.zemu.tv.data.slim
import com.zemu.tv.data.title
import com.zemu.tv.streams.Languages
import com.zemu.tv.streams.ParsedStream
import kotlinx.coroutines.launch
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer

/** One playable stream handed to the player; the player falls back through them in order. */
@Serializable
data class PlayCandidate(
    val url: String,
    val label: String,
    val headers: Map<String, String> = emptyMap(),
    /** Addon hint that streams with the same value come from the same release (used for next episode). */
    val bingeGroup: String? = null,
    /** [ParsedStream.key] of the release, when known. */
    val key: String = "",
)

object Playback {
    const val EXTRA_TITLE = "title"
    const val EXTRA_META = "meta"
    const val EXTRA_VIDEO_ID = "videoId"
    const val EXTRA_LABEL = "label"
    const val EXTRA_CANDIDATES = "candidates"
    const val EXTRA_SUBS = "subs"
    const val EXTRA_START_MS = "startMs"

    fun ParsedStream.toCandidate() = PlayCandidate(
        url = raw.url.orEmpty(),
        label = listOfNotNull(resolutionLabel, sizeLabel, addonName).joinToString(" · "),
        headers = raw.behaviorHints?.proxyHeaders?.request.orEmpty(),
        bingeGroup = raw.behaviorHints?.bingeGroup,
        key = key,
    )

    /** The link that last played [videoId] of this title, if it was saved. */
    fun savedFor(context: Context, metaId: String, videoId: String): PlayCandidate? =
        context.container.userStore.lastStreams.value[metaId]
            ?.takeIf { it.videoId == videoId && !it.url.isNullOrBlank() }
            ?.let { PlayCandidate(it.url!!, it.label ?: "Last played file", it.headers, it.bingeGroup, it.key) }

    /**
     * Continue Watching: replay the exact file that last played, from where it stopped (or from
     * the start). Returns false when no saved file is known, so the caller can look up streams.
     * If the file is gone, the player looks up cached streams itself and keeps the position.
     */
    fun resumeSaved(context: Context, meta: Meta, fromStart: Boolean = false): Boolean {
        val c = context.container
        val entry = c.userStore.history.value.firstOrNull { it.meta.id == meta.id } ?: return false
        val saved = savedFor(context, meta.id, entry.videoId) ?: return false
        if (c.userStore.settings.value.useExternalPlayer) return false
        val start = if (fromStart) 0L else entry.positionMs.takeIf { entry.progress in 0.01f..0.97f } ?: 0L
        val m = entry.meta
        c.appScope.launch(kotlinx.coroutines.Dispatchers.Main) {
            // Subtitles are usually cached from the last play; don't hold the start up for long.
            val subs = kotlinx.coroutines.withTimeoutOrNull(3_000) { runCatching { c.streams.subtitles(m.type, entry.videoId) }.getOrNull() }.orEmpty()
            launch(context, m, entry.videoId, entry.label, listOf(saved), subs, start)
        }
        return true
    }

    /** Plays a downloaded file (no network needed), from where it was left. */
    fun playDownload(context: Context, item: com.zemu.tv.data.DownloadItem) {
        val start = context.container.userStore.history.value
            .firstOrNull { it.meta.id == item.meta.id && it.videoId == item.videoId }
            ?.takeIf { it.progress in 0.02f..0.95f }?.positionMs ?: 0L
        launch(context, item.meta, item.videoId, item.label, listOf(PlayCandidate(item.path, "Downloaded")), emptyList(), start)
    }

    private fun launch(context: Context, meta: Meta, videoId: String, label: String?, candidates: List<PlayCandidate>, subs: List<SubtitleTrack>, startMs: Long) {
        val c = context.container
        MpvSession.start(c, meta, videoId, label, candidates, pickSubtitles(subs, c.userStore.settings.value.subtitleLanguages), startMs)
    }

    /**
     * The player fetches every side-loaded subtitle before starting, and one dead link fails the
     * whole playback, so only pass a couple per preferred language.
     */
    fun pickSubtitles(all: List<SubtitleTrack>, preferred: List<String>): List<SubtitleTrack> {
        val langs = preferred.ifEmpty { listOf("en") }
        val picked = langs.flatMap { lang -> all.filter { Languages.normalize(it.lang) == lang }.take(2) }.take(8)
        if (picked.isNotEmpty()) return picked
        // Nothing in a preferred language: offer English plus a few others rather than nothing.
        val byLang = all.groupBy { Languages.normalize(it.lang) ?: it.lang }
        val order = (listOf("en") + byLang.keys).distinct().filter { it in byLang }
        return order.take(4).map { byLang.getValue(it).first() }
    }

    /**
     * @param alternatives other cached streams in ranked order; used automatically if [stream] can't be decoded.
     */
    fun play(
        context: Context,
        meta: Meta,
        videoId: String,
        episodeLabel: String?,
        stream: ParsedStream,
        externalSubs: List<SubtitleTrack>,
        alternatives: List<ParsedStream> = emptyList(),
        /** Ignore saved progress and play from the beginning. */
        fromStart: Boolean = false,
        /** Play the file that last played this video first (false when a stream was picked by hand). */
        preferSaved: Boolean = true,
    ) {
        val c = context.container
        val url = stream.raw.url ?: return
        val settings = c.userStore.settings.value
        // A movie watched through the credits starts over.
        val finished = meta.type != "series" && meta.id in c.userStore.watched.value
        val resume = if (fromStart || finished) 0L else c.userStore.history.value
            .firstOrNull { it.meta.id == meta.id && it.videoId == videoId }
            ?.takeIf { it.progress in 0.02f..0.95f }?.positionMs ?: 0L
        val displayTitle = listOfNotNull(meta.title, episodeLabel).joinToString(" · ")

        if (settings.useExternalPlayer) {
            if (openExternal(context, url, displayTitle, resume)) {
                com.zemu.tv.ui.components.Haptics.buzz(context, com.zemu.tv.ui.components.Haptics.Kind.START)
                c.appScope.launch {
                    c.userStore.rememberStream(meta.id, com.zemu.tv.data.LastStream(stream.key, stream.raw.behaviorHints?.bingeGroup))
                    c.userStore.recordProgress(WatchEntry(meta.slim(), videoId, episodeLabel, resume, 0, System.currentTimeMillis()))
                }
                return
            }
            Toast.makeText(context, "No external player found (install VLC), using mpv", Toast.LENGTH_LONG).show()
        }

        if (url.isBlank()) return
        val fresh = (listOf(stream) + alternatives.filter { it.key != stream.key && it.raw.url != null }).map { it.toCandidate() }
        val saved = if (preferSaved) savedFor(context, meta.id, videoId) else null
        val candidates = (listOfNotNull(saved) + fresh.filter { it.url != saved?.url }).take(MAX_CANDIDATES)
        launch(context, meta, videoId, episodeLabel, candidates, externalSubs, resume)
    }

    /** Hands the link to VLC (or whatever opens videos) with Zemu out of the way. */
    fun openExternal(context: Context, url: String, title: String, positionMs: Long = 0): Boolean {
        val vlc = listOf("vlc", "--fullscreen", "--start-time=${positionMs / 1000}", "--meta-title=$title", url)
        return listOf(vlc, listOf("xdg-open", url)).any { cmd -> runCatching { ProcessBuilder(cmd).start() }.isSuccess }
    }

    private const val MAX_CANDIDATES = 5
}
