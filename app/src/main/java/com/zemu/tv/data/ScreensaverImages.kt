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
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File

/**
 * Landscape backdrops for the library screensaver: fanart.tv first, then TMDB `/images` backdrops.
 * Found URLs are kept in a small file so later runs start immediately; the images themselves are
 * kept by the app's image disk cache once shown or prefetched.
 */
class ScreensaverImages(
    context: Context,
    private val http: OkHttpClient,
    private val json: Json,
    private val tmdb: Tmdb,
    private val fanartKey: () -> String,
) {
    private val file = File(context.filesDir, "screensaver_images.json")
    private val ser = MapSerializer(String.serializer(), ListSerializer(String.serializer()))
    private val lock = Mutex()
    private var cache: MutableMap<String, List<String>>? = null

    private suspend fun loaded(): MutableMap<String, List<String>> = lock.withLock {
        cache ?: withContext(Dispatchers.IO) {
            runCatching { json.decodeFromString(ser, file.readText()) }.getOrDefault(emptyMap()).toMutableMap()
        }.also { cache = it }
    }

    /** Images already known for these titles, without any network calls. */
    suspend fun cached(titles: List<Meta>): List<String> {
        val c = loaded()
        return titles.flatMap { c[it.id].orEmpty() }
    }

    /** Looks up titles not seen before (a few at a time) and saves what was found. */
    suspend fun refresh(titles: List<Meta>) = coroutineScope {
        val c = loaded()
        val gate = Semaphore(4)
        val found = titles.filter { it.id !in c }.take(40).map { m ->
            async { gate.withPermit { m.id to runCatching { lookup(m) }.getOrDefault(emptyList()) } }
        }.awaitAll()
        if (found.isEmpty()) return@coroutineScope
        lock.withLock {
            found.forEach { (id, urls) -> c[id] = urls }
            withContext(Dispatchers.IO) { runCatching { file.writeText(json.encodeToString(ser, c)) } }
        }
    }

    private suspend fun lookup(m: Meta): List<String> {
        fanart(m).takeIf { it.isNotEmpty() }?.let { return it }
        return tmdb.backdrops(m)
    }

    /** fanart.tv: movies by IMDb/TMDB id, shows by TheTVDB id (found through TMDB). */
    private suspend fun fanart(m: Meta): List<String> {
        val key = fanartKey().trim().takeIf { it.isNotEmpty() } ?: return emptyList()
        val path = if (m.type == "series") {
            val tvdb = runCatching { tmdb.tvdbId(m) }.getOrNull() ?: return emptyList()
            "tv/$tvdb"
        } else {
            val id = m.imdbId.takeIf { it.startsWith("tt") } ?: m.tmdbId ?: return emptyList()
            "movies/$id"
        }
        val body = withContext(Dispatchers.IO) {
            http.newCall(Request.Builder().url("https://webservice.fanart.tv/v3/$path?api_key=$key").build()).execute().use { r ->
                if (!r.isSuccessful) null else r.body?.string()
            }
        } ?: return emptyList()
        val o = runCatching { json.parseToJsonElement(body).jsonObject }.getOrNull() ?: return emptyList()
        val field = if (m.type == "series") "showbackground" else "moviebackground"
        return (o[field] as? kotlinx.serialization.json.JsonArray).orEmpty()
            .mapNotNull { (it as? JsonObject)?.get("url")?.jsonPrimitive?.contentOrNull }
            .take(6)
    }
}
