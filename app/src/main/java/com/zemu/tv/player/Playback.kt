package com.zemu.tv.player

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
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
    )

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
    ) {
        val c = context.container
        val url = stream.raw.url ?: return
        val settings = c.userStore.settings.value
        com.zemu.tv.ui.components.Haptics.buzz(context, com.zemu.tv.ui.components.Haptics.Kind.START)
        c.appScope.launch { c.userStore.rememberStream(meta.id, com.zemu.tv.data.LastStream(stream.key, stream.raw.behaviorHints?.bingeGroup)) }
        val resume = c.userStore.history.value
            .firstOrNull { it.meta.id == meta.id && it.videoId == videoId }
            ?.takeIf { it.progress in 0.02f..0.95f }?.positionMs ?: 0L
        val displayTitle = listOfNotNull(meta.title, episodeLabel).joinToString(" · ")

        if (settings.useExternalPlayer) {
            if (openExternal(context, url, displayTitle, resume)) {
                c.appScope.launch {
                    c.userStore.recordProgress(WatchEntry(meta.slim(), videoId, episodeLabel, resume, 0, System.currentTimeMillis()))
                }
                return
            }
            Toast.makeText(context, "No external player installed, using the built-in player", Toast.LENGTH_LONG).show()
        }

        val candidates = (listOf(stream) + alternatives.filter { it.key != stream.key && it.raw.url != null })
            .take(MAX_CANDIDATES)
            .map { it.toCandidate() }
        val json = c.json
        val intent = Intent(context, PlayerActivity::class.java)
            .putExtra(EXTRA_TITLE, displayTitle)
            .putExtra(EXTRA_META, json.encodeToString(Meta.serializer(), meta.slim()))
            .putExtra(EXTRA_VIDEO_ID, videoId)
            .putExtra(EXTRA_LABEL, episodeLabel)
            .putExtra(EXTRA_CANDIDATES, json.encodeToString(ListSerializer(PlayCandidate.serializer()), candidates))
            .putExtra(EXTRA_SUBS, json.encodeToString(ListSerializer(SubtitleTrack.serializer()), pickSubtitles(externalSubs, settings.subtitleLanguages)))
            .putExtra(EXTRA_START_MS, resume)
        if (url.isNotBlank()) context.startActivity(intent)
    }

    fun openExternal(context: Context, url: String, title: String, positionMs: Long = 0): Boolean {
        val intent = Intent(Intent.ACTION_VIEW)
            .setDataAndType(Uri.parse(url), "video/*")
            .putExtra("title", title)
            .putExtra("position", positionMs.toInt())
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return try {
            context.startActivity(intent)
            true
        } catch (_: ActivityNotFoundException) {
            false
        }
    }

    private const val MAX_CANDIDATES = 5
}
