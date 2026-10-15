package com.zemu.tv.data

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.sync.withPermit
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File

/** A title's screensaver art: landscape backdrops and its title logo (transparent PNG). */
@Serializable
data class ScreensaverArt(val backdrops: List<String> = emptyList(), val logo: String? = null)

/** One screensaver slide: a title, one of its backdrops and its logo. */
data class ScreensaverSlide(val meta: Meta, val image: String, val logo: String?)

/**
 * Backdrops and logos for the screensaver: fanart.tv first, then TMDB `/images`. What's found is
 * kept in a small file so later runs start immediately; the images themselves are kept by the
 * app's image disk cache once shown or prefetched.
 */
class ScreensaverImages(
    context: Context,
    private val http: OkHttpClient,
    private val json: Json,
    private val tmdb: Tmdb,
    private val fanartKey: () -> String,
) {
    private val file = File(context.filesDir, "screensaver_art.json")
    private val ser = MapSerializer(String.serializer(), ScreensaverArt.serializer())
    private val lock = Mutex()
    private var cache: MutableMap<String, ScreensaverArt>? = null

    init {
        // Superseded by screensaver_art.json (backdrops only, no logos).
        File(context.filesDir, "screensaver_images.json").delete()
    }

    private suspend fun loaded(): MutableMap<String, ScreensaverArt> = lock.withLock {
        cache ?: withContext(Dispatchers.IO) {
            runCatching { json.decodeFromString(ser, file.readText()) }.getOrDefault(emptyMap()).toMutableMap()
        }.also { cache = it }
    }

    /** One slide per title with known art (a random backdrop each time), without network calls. */
    suspend fun slides(titles: List<Meta>): List<ScreensaverSlide> {
        val c = loaded()
        return titles.mapNotNull { m ->
            val art = c[m.id] ?: return@mapNotNull null
            val image = art.backdrops.randomOrNull() ?: return@mapNotNull null
            ScreensaverSlide(m, image, art.logo ?: m.logo)
        }
    }

    /** Looks up titles not seen before (a few at a time) and saves what was found. */
    suspend fun refresh(titles: List<Meta>) = coroutineScope {
        val c = loaded()
        val gate = Semaphore(4)
        val found = titles.filter { it.id !in c }.take(40).map { m ->
            async { gate.withPermit { m.id to runCatching { lookup(m) }.getOrDefault(ScreensaverArt()) } }
        }.awaitAll()
        if (found.isEmpty()) return@coroutineScope
        lock.withLock {
            found.forEach { (id, art) -> c[id] = art }
            // Suggestions change daily; keep the file from growing forever.
            while (c.size > 600) c.remove(c.keys.first())
            withContext(Dispatchers.IO) { runCatching { file.writeText(json.encodeToString(ser, c)) } }
        }
    }

    private suspend fun lookup(m: Meta): ScreensaverArt {
        val fan = runCatching { fanart(m) }.getOrNull()
        if (fan != null && fan.backdrops.isNotEmpty() && fan.logo != null) return fan
        val (backdrops, logo) = runCatching { tmdb.art(m) }.getOrDefault(emptyList<String>() to null)
        return ScreensaverArt(fan?.backdrops?.ifEmpty { null } ?: backdrops, fan?.logo ?: logo)
    }

    /** fanart.tv: movies by IMDb/TMDB id, shows by TheTVDB id (found through TMDB). */
    private suspend fun fanart(m: Meta): ScreensaverArt? {
        val key = fanartKey().trim().takeIf { it.isNotEmpty() } ?: return null
        val series = m.type == "series"
        val path = if (series) {
            val tvdb = runCatching { tmdb.tvdbId(m) }.getOrNull() ?: return null
            "tv/$tvdb"
        } else {
            val id = m.imdbId.takeIf { it.startsWith("tt") } ?: m.tmdbId ?: return null
            "movies/$id"
        }
        val body = withContext(Dispatchers.IO) {
            http.newCall(Request.Builder().url("https://webservice.fanart.tv/v3/$path?api_key=$key").build()).execute().use { r ->
                if (!r.isSuccessful) null else r.body?.string()
            }
        } ?: return null
        val o = runCatching { json.parseToJsonElement(body).jsonObject }.getOrNull() ?: return null
        fun images(field: String) = (o[field] as? JsonArray).orEmpty().mapNotNull { it as? JsonObject }
        fun url(e: JsonObject) = e["url"]?.jsonPrimitive?.contentOrNull
        val backdrops = images(if (series) "showbackground" else "moviebackground").mapNotNull(::url).take(6)
        val logos = images(if (series) "hdtvlogo" else "hdmovielogo")
        val logo = (logos.firstOrNull { it["lang"]?.jsonPrimitive?.contentOrNull == "en" } ?: logos.firstOrNull())?.let(::url)
        return ScreensaverArt(backdrops, logo)
    }
}
