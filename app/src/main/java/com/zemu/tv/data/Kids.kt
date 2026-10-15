package com.zemu.tv.data

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.ConcurrentHashMap

/**
 * Kids Mode, for the whole app (every profile): only titles rated up to [maxLevel] show or play,
 * Settings and profiles are locked, and leaving needs the parent code. [theme] is the kids theme.
 */
@Serializable
data class KidsSettings(
    val on: Boolean = false,
    val maxLevel: Int = 1,
    /** Salted SHA-256 of the parent code; empty until one is set. */
    val pinHash: String = "",
    val theme: String = "GRADE_SCHOOL",
)

/** US movie and TV ratings, grouped into levels a parent picks from. */
object Ratings {
    val LEVELS = listOf("G", "PG", "PG-13", "R")
    /** The TV ratings each level allows. */
    val TV = listOf("TV-Y, TV-G", "TV-Y7, TV-PG", "TV-14", "TV-MA")

    fun level(cert: String): Int? = when (cert.trim().uppercase()) {
        "G", "TV-Y", "TV-G" -> 0
        "PG", "TV-Y7", "TV-Y7-FV", "TV-PG" -> 1
        "PG-13", "TV-14" -> 2
        "R", "TV-MA" -> 3
        "NC-17" -> 4
        else -> null
    }

    /** Kitsu (anime) age ratings. */
    fun kitsuLevel(age: String): Int? = when (age.trim().uppercase()) {
        "G" -> 0
        "PG" -> 1
        "R" -> 3
        "R18" -> 4
        else -> null
    }

    /** The movie certification at a level, for TMDB's `certification.lte`. */
    fun movieCert(level: Int) = listOf("G", "PG", "PG-13", "R").getOrElse(level) { "R" }

    fun hash(pin: String): String =
        MessageDigest.getInstance("SHA-256").digest("zemu-kids:$pin".toByteArray()).joinToString("") { "%02x".format(it) }
}

/**
 * Looks up and remembers each title's rating. Titles with no rating found are treated as not
 * allowed, so nothing slips through. Ratings come from TMDB (needs the TMDB key) and Kitsu.
 */
class KidsGate(context: Context, private val http: OkHttpClient, private val json: Json, private val tmdb: Tmdb, val settings: StateFlow<KidsSettings>) {
    private val file = File(context.filesDir, "ratings.json")
    private val ser = MapSerializer(String.serializer(), Int.serializer())
    /** Title id to rating level; -1 = no rating found. */
    private val levels = ConcurrentHashMap<String, Int>(runCatching { json.decodeFromString(ser, file.readText()) }.getOrDefault(emptyMap()))
    private val limit = Semaphore(6)

    val active: Boolean get() = settings.value.on

    /** Service, studio and "see more" cards aren't titles and always pass. */
    private fun isTitle(id: String) = id.startsWith("tt") || id.startsWith("tmdb:") || id.startsWith("kitsu:")

    /** Allowed right now from what's already known (null = not looked up yet). */
    fun knownAllowed(m: Meta): Boolean? {
        if (!active || !isTitle(m.id)) return true
        val l = levels[m.id] ?: return null
        return l in 0..settings.value.maxLevel
    }

    suspend fun allowed(m: Meta): Boolean {
        knownAllowed(m)?.let { return it }
        val l = runCatching { lookup(m) }.getOrNull()
        // Network errors aren't remembered, so they're retried next time.
        if (l != null) levels[m.id] = l
        return l != null && l in 0..settings.value.maxLevel
    }

    suspend fun <T> filter(items: List<T>, meta: (T) -> Meta): List<T> {
        if (!active) return items
        val before = levels.size
        val ok = coroutineScope { items.map { async { limit.withPermit { allowed(meta(it)) } } }.awaitAll() }
        if (levels.size != before) save()
        return items.filterIndexed { i, _ -> ok[i] }
    }

    private suspend fun save() = withContext(Dispatchers.IO) {
        runCatching { file.writeText(json.encodeToString(ser, HashMap(levels))) }
    }

    /** The title's rating level, or -1 when it has none. */
    private suspend fun lookup(m: Meta): Int = withContext(Dispatchers.IO) {
        if (m.id.startsWith("kitsu:")) {
            val id = m.id.split(':')[1]
            val body = http.newCall(Request.Builder().url("https://kitsu.io/api/edge/anime/$id").build()).execute().use { it.body?.string().orEmpty() }
            val age = json.parseToJsonElement(body).jsonObject["data"]?.jsonObject?.get("attributes")?.jsonObject?.get("ageRating")?.jsonPrimitive?.contentOrNull
            return@withContext age?.let { Ratings.kitsuLevel(it) } ?: -1
        }
        val cert = tmdb.usCertification(m) ?: throw IllegalStateException("No TMDB key")
        Ratings.level(cert) ?: -1
    }
}
