package com.zemu.tv.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.longOrNull
import okhttp3.OkHttpClient
import okhttp3.Request

enum class SegmentType(val skipLabel: String) { INTRO("Skip intro"), RECAP("Skip recap"), CREDITS("Skip credits"), PREVIEW("Skip preview") }

/** [endMs] null means "until the end". */
data class Segment(val type: SegmentType, val startMs: Long, val endMs: Long?)

/**
 * Community skip timestamps:
 *  - TheIntroDB (theintrodb.org) for TV episodes and movies, by TMDB or IMDb id.
 *  - AniSkip (aniskip.com) for anime, by MyAnimeList id (resolved from Kitsu).
 */
class SkipSegments(private val http: OkHttpClient, private val json: Json) {

    private suspend fun getJson(url: String): JsonObject? = withContext(Dispatchers.IO) {
        runCatching {
            http.newCall(Request.Builder().url(url).header("User-Agent", "Zemu/1.0").build()).execute().use { r ->
                if (!r.isSuccessful) null else r.body?.string()?.let { json.parseToJsonElement(it).jsonObject }
            }
        }.getOrNull()
    }

    suspend fun find(meta: Meta, videoId: String, season: Int?, episode: Int?, durationMs: Long): List<Segment> {
        val kitsuId = (if (videoId.startsWith("kitsu:")) videoId else meta.id).takeIf { it.startsWith("kitsu:") }
            ?.removePrefix("kitsu:")?.substringBefore(':')
        if (kitsuId != null) {
            val ep = videoId.split(':').getOrNull(2)?.toIntOrNull() ?: episode ?: 1
            return aniSkip(kitsuId, ep, durationMs)
        }
        return introDb(meta, season, episode, durationMs)
    }

    private suspend fun introDb(meta: Meta, season: Int?, episode: Int?, durationMs: Long): List<Segment> {
        val idParam = meta.tmdbId?.takeIf { it.isNotBlank() }?.let { "tmdb_id=$it" }
            ?: meta.imdbId.takeIf { it.startsWith("tt") }?.let { "imdb_id=$it" }
            ?: return emptyList()
        val ep = if (meta.type == "series" && season != null && episode != null) "&season=$season&episode=$episode" else ""
        val dur = if (durationMs > 0) "&duration_ms=$durationMs" else ""
        val o = getJson("https://api.theintrodb.org/v3/media?$idParam$ep$dur") ?: return emptyList()
        val map = mapOf("intro" to SegmentType.INTRO, "recap" to SegmentType.RECAP, "credits" to SegmentType.CREDITS, "preview" to SegmentType.PREVIEW)
        return map.flatMap { (key, type) ->
            (o[key] as? JsonArray).orEmpty().mapNotNull { el ->
                val s = el.jsonObject
                val start = (s["start_ms"] as? JsonPrimitive)?.longOrNull ?: 0L
                val end = (s["end_ms"] as? JsonPrimitive)?.longOrNull
                if (end != null && end <= start) null else Segment(type, start, end)
            }
        }.sortedBy { it.startMs }
    }

    private suspend fun aniSkip(kitsuId: String, episode: Int, durationMs: Long): List<Segment> {
        val mal = malIdFor(kitsuId) ?: return emptyList()
        val len = if (durationMs > 0) durationMs / 1000.0 else 0.0
        val o = getJson("https://api.aniskip.com/v2/skip-times/$mal/$episode?types=op&types=ed&types=recap&types=mixed-op&types=mixed-ed&episodeLength=$len")
            ?: return emptyList()
        if ((o["found"] as? JsonPrimitive)?.contentOrNull != "true") return emptyList()
        return (o["results"] as? JsonArray).orEmpty().mapNotNull { el ->
            val r = el.jsonObject
            val interval = r["interval"]?.jsonObject ?: return@mapNotNull null
            val start = ((interval["startTime"] as? JsonPrimitive)?.doubleOrNull ?: return@mapNotNull null) * 1000
            val end = ((interval["endTime"] as? JsonPrimitive)?.doubleOrNull ?: return@mapNotNull null) * 1000
            val type = when ((r["skipType"] as? JsonPrimitive)?.contentOrNull) {
                "op", "mixed-op" -> SegmentType.INTRO
                "ed", "mixed-ed" -> SegmentType.CREDITS
                "recap" -> SegmentType.RECAP
                else -> return@mapNotNull null
            }
            Segment(type, start.toLong(), end.toLong())
        }.sortedBy { it.startMs }
    }

    private val malCache = HashMap<String, String?>()

    private suspend fun malIdFor(kitsuId: String): String? {
        if (malCache.containsKey(kitsuId)) return malCache[kitsuId]
        val o = getJson("https://kitsu.io/api/edge/anime/$kitsuId/mappings?filter%5BexternalSite%5D=myanimelist/anime")
        val mal = (o?.get("data") as? JsonArray)?.firstOrNull()?.jsonObject
            ?.get("attributes")?.jsonObject?.get("externalId")?.let { (it as? JsonPrimitive)?.contentOrNull }
        malCache[kitsuId] = mal
        return mal
    }
}
