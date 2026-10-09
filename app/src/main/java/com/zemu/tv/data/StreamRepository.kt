package com.zemu.tv.data

import com.zemu.tv.streams.Languages
import com.zemu.tv.streams.ParsedStream
import com.zemu.tv.streams.StreamParser
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withTimeoutOrNull
import java.util.concurrent.ConcurrentHashMap

data class StreamLoadResult(
    /** Only debrid-cached, directly playable streams. Uncached ones never leave this repository. */
    val cached: List<ParsedStream>,
    val totalFound: Int,
    /** Streams dropped because they weren't cached (torrents, "download" links). */
    val hiddenUncached: Int,
    val failedAddons: List<String>,
    val noStreamAddons: Boolean,
)

class StreamRepository(
    private val addons: AddonRepository,
    private val client: AddonClient,
    private val store: UserStore,
) {
    private val cache = ConcurrentHashMap<String, Pair<Long, StreamLoadResult>>()
    private val subsCache = ConcurrentHashMap<String, List<SubtitleTrack>>()

    suspend fun load(type: String, videoId: String, force: Boolean = false): StreamLoadResult {
        val key = "$type/$videoId"
        val now = System.currentTimeMillis()
        if (!force) cache[key]?.let { (at, r) -> if (now - at < CACHE_TTL_MS) return r }

        val targets = addons.addonsFor("stream", type, videoId)
        if (targets.isEmpty()) return StreamLoadResult(emptyList(), 0, 0, emptyList(), noStreamAddons = true)

        val trustDirect = store.settings.value.trustDirectLinks
        val responses = coroutineScope {
            targets.map { addon ->
                async {
                    addon to runCatching {
                        withTimeoutOrNull(TIMEOUT_MS) { client.streams(addon.baseUrl, type, videoId) }
                            ?: error("timed out")
                    }
                }
            }.awaitAll()
        }
        val parsed = responses.flatMap { (addon, r) ->
            r.getOrNull().orEmpty().map { StreamParser.parse(it, addon.manifest.name, trustDirect) }
        }
        val result = StreamLoadResult(
            cached = parsed.filter { it.isCached }.distinctBy { it.key },
            totalFound = parsed.size,
            hiddenUncached = parsed.count { !it.isCached },
            failedAddons = responses.filter { it.second.isFailure }.map { it.first.manifest.name },
            noStreamAddons = false,
        )
        // Don't cache total failures so a retry actually retries.
        if (result.failedAddons.size < targets.size) cache[key] = now to result
        return result
    }

    suspend fun hasCached(type: String, videoId: String): Boolean =
        runCatching { load(type, videoId).cached.isNotEmpty() }.getOrDefault(false)

    /**
     * Subtitles from installed addons. If those have nothing in a preferred language, well-known
     * free subtitle addons are asked directly (without installing them) so something turns up.
     */
    suspend fun subtitles(type: String, videoId: String): List<SubtitleTrack> {
        val key = "$type/$videoId"
        subsCache[key]?.let { return it }
        val installed = addons.addonsFor("subtitles", type, videoId)
        suspend fun fetch(bases: List<String>): List<SubtitleTrack> = coroutineScope {
            bases.map { base ->
                async {
                    runCatching { withTimeoutOrNull(TIMEOUT_MS) { client.subtitles(base, type, videoId) } }
                        .getOrNull().orEmpty()
                }
            }.awaitAll().flatten()
        }
        var subs = fetch(installed.map { it.baseUrl }).filter { it.url.isNotBlank() }
        val preferred = store.settings.value.subtitleLanguages.ifEmpty { listOf("en") }
        fun covered() = subs.any { s -> Languages.normalize(s.lang) in preferred }
        if (!covered() && videoId.startsWith("tt")) {
            val installedBases = installed.map { it.baseUrl }.toSet()
            val fallback = (listOf(OPENSUBTITLES) + preferred.flatMap { LANGUAGE_FALLBACKS[it].orEmpty() })
                .distinct().filter { it !in installedBases }
            subs = subs + fetch(fallback).filter { it.url.isNotBlank() }
        }
        subs = subs.distinctBy { it.url }
        subsCache[key] = subs
        return subs
    }

    fun invalidate() = cache.clear()

    companion object {
        private const val CACHE_TTL_MS = 15 * 60 * 1000L
        private const val TIMEOUT_MS = 20_000L

        private const val OPENSUBTITLES = "https://opensubtitles-v3.strem.io"

        /** Free, no-setup subtitle addons for languages OpenSubtitles covers poorly. */
        private val LANGUAGE_FALLBACKS = mapOf(
            "es" to listOf("https://stremio.fly.dev", "https://58196d6c26cf-stremio-tusubtitulo.baby-beamup.club"),
            "he" to listOf("https://4b139a4b7f94-wizdom-stremio-v2.baby-beamup.club", "https://4b139a4b7f94-ktuvit-stremio.baby-beamup.club"),
            "pl" to listOf("https://napisy24-stremio.top"),
        )
    }
}
