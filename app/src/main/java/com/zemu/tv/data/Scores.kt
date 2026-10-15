package com.zemu.tv.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request
import java.util.concurrent.ConcurrentHashMap

/** Critic scores and the US rating of a title. */
data class TitleScores(
    /** "PG-13", "TV-14", … (null when unrated). */
    val rated: String? = null,
    /** Rotten Tomatoes Tomatometer, 0–100. */
    val rottenTomatoes: Int? = null,
    /** Metascore, 0–100. */
    val metacritic: Int? = null,
)

/**
 * Scores from OMDb (omdbapi.com; a free key, 1,000 lookups a day). Without a key nothing is
 * fetched. Remembered for the session.
 */
class Scores(private val http: OkHttpClient, private val json: Json, private val key: () -> String) {
    private val cache = ConcurrentHashMap<String, TitleScores>()

    val enabled: Boolean get() = key().isNotBlank()

    suspend fun of(imdbId: String): TitleScores? {
        if (!enabled || !imdbId.startsWith("tt")) return null
        cache[imdbId]?.let { return it }
        val url = "https://www.omdbapi.com/".toHttpUrl().newBuilder().addQueryParameter("i", imdbId).addQueryParameter("apikey", key().trim()).build()
        val body = withContext(Dispatchers.IO) {
            http.newCall(Request.Builder().url(url).build()).execute().use { if (it.isSuccessful) it.body?.string() else null }
        } ?: return null
        val o = json.parseToJsonElement(body).jsonObject
        if (o["Response"]?.jsonPrimitive?.contentOrNull == "False") return null
        val ratings = o["Ratings"]?.jsonArray.orEmpty().associate {
            it.jsonObject["Source"]?.jsonPrimitive?.contentOrNull.orEmpty() to it.jsonObject["Value"]?.jsonPrimitive?.contentOrNull.orEmpty()
        }
        return TitleScores(
            rated = o["Rated"]?.jsonPrimitive?.contentOrNull?.takeIf { Ratings.isRating(it) },
            rottenTomatoes = ratings["Rotten Tomatoes"]?.removeSuffix("%")?.toIntOrNull(),
            metacritic = ratings["Metacritic"]?.substringBefore('/')?.toIntOrNull()
                ?: o["Metascore"]?.jsonPrimitive?.contentOrNull?.toIntOrNull(),
        ).also { cache[imdbId] = it }
    }
}
