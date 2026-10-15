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
import kotlinx.serialization.Transient
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.ConcurrentHashMap

/**
 * Parental controls, shared by every profile. Kids Mode is on while a kid profile ([Profile.kids])
 * is being used ([on]); then only kids' titles with an [allowed] rating show, Settings and
 * profile switching need the parent code.
 */
@Serializable
data class KidsSettings(
    /** Shows the kid-profile option and these settings at all. */
    val enabled: Boolean = false,
    /** Ratings a kid may watch; [Ratings.UNRATED] lets through kids' shows nobody has rated. */
    val allowed: Set<String> = Ratings.DEFAULT_ALLOWED,
    /** Salted SHA-256 of the parent code; empty until one is set. */
    val pinHash: String = "",
    /** A kid profile is in use right now (not saved; worked out from the active profile). */
    @Transient val on: Boolean = false,
)

/** US movie and TV ratings. */
object Ratings {
    const val UNRATED = "NR"
    val MOVIE = listOf("G", "PG", "PG-13", "R")
    val TV = listOf("TV-Y", "TV-Y7", "TV-G", "TV-PG", "TV-14")
    val DEFAULT_ALLOWED = setOf("G", "PG", "TV-Y", "TV-Y7", "TV-G", UNRATED)

    /** "tv-y7 " → "TV-Y7"; Kitsu's anime ratings map onto the movie ones. */
    fun normalize(cert: String): String = when (val c = cert.trim().uppercase()) {
        "TV-Y7-FV" -> "TV-Y7"
        "R18" -> "NC-17"
        else -> c
    }

    /** Kids' content only: family or kids genres (Animation alone isn't enough: think adult cartoons). */
    fun isKidsGenre(genres: List<String>) = genres.any { it.equals("Family", true) || it.equals("Kids", true) || it.equals("Children", true) }

    fun allows(allowed: Set<String>, cert: String, kidsGenre: Boolean): Boolean =
        kidsGenre && if (cert.isEmpty()) UNRATED in allowed else normalize(cert) in allowed

    /** A US movie or TV rating ("PG-13", "TV-MA"), as opposed to "N/A", "Not Rated", "Unrated". */
    fun isRating(cert: String) = normalize(cert) in MOVIE + TV + listOf("NC-17", "TV-MA")

    fun hash(pin: String): String =
        MessageDigest.getInstance("SHA-256").digest("zemu-kids:$pin".toByteArray()).joinToString("") { "%02x".format(it) }
}

/**
 * Works out and remembers each title's rating and whether it's a kids' title. Movie ratings come
 * from Wikidata (no key needed), or TMDB when there's a key; TV ratings need TMDB; anime uses
 * Kitsu. Genres come with the title or from Cinemeta.
 */
class KidsGate(context: Context, private val http: OkHttpClient, private val json: Json, private val tmdb: Tmdb, private val scores: Scores, val settings: StateFlow<KidsSettings>) {
    private val file = File(context.filesDir, "kid_ratings.json")
    private val ser = MapSerializer(String.serializer(), String.serializer())
    /** Title id to "<rating>|<1 if a kids' title>"; the rating is "" when none was found. */
    private val known = ConcurrentHashMap<String, String>(runCatching { json.decodeFromString(ser, file.readText()) }.getOrDefault(emptyMap()))
    private val limit = Semaphore(6)

    val active: Boolean get() = settings.value.on

    /** Service, studio and "see more" cards aren't titles and always pass. */
    private fun isTitle(id: String) = id.startsWith("tt") || id.startsWith("tmdb:") || id.startsWith("kitsu:")

    private fun verdict(entry: String): Boolean =
        Ratings.allows(settings.value.allowed, entry.substringBefore('|'), entry.endsWith("|1"))

    /** Allowed right now from what's already known (null = not looked up yet). */
    fun knownAllowed(m: Meta): Boolean? {
        if (!active || !isTitle(m.id)) return true
        return known[m.id]?.let(::verdict)
    }

    /** The title's US rating for a badge ("PG-13"), looked up if needed; null when unrated or unknown. */
    suspend fun certification(m: Meta): String? {
        if (!m.id.startsWith("tt") && !m.id.startsWith("tmdb:") && !m.id.startsWith("kitsu:")) return null
        val entry = known[m.id] ?: runCatching { lookup(m) }.getOrNull()?.also { known[m.id] = it } ?: return null
        return entry.substringBefore('|').takeIf { Ratings.isRating(it) }
    }

    suspend fun allowed(m: Meta): Boolean {
        knownAllowed(m)?.let { return it }
        // Network errors aren't remembered, so they're retried next time.
        val entry = runCatching { lookup(m) }.getOrNull() ?: return false
        known[m.id] = entry
        return verdict(entry)
    }

    suspend fun <T> filter(items: List<T>, meta: (T) -> Meta): List<T> {
        if (!active) return items
        val before = known.size
        runCatching { prefetchWikidata(items.map(meta)) }
        val ok = coroutineScope { items.map { async { limit.withPermit { allowed(meta(it)) } } }.awaitAll() }
        if (known.size != before) save()
        return items.filterIndexed { i, _ -> ok[i] }
    }

    private suspend fun save() = withContext(Dispatchers.IO) {
        runCatching { file.writeText(json.encodeToString(ser, HashMap(known))) }
    }

    /** Movie ratings found on Wikidata ahead of time, many titles per request (IMDb id → rating). */
    private val wikidata = ConcurrentHashMap<String, String>()

    private suspend fun prefetchWikidata(metas: List<Meta>) {
        if (tmdb.enabled || scores.enabled) return
        val ids = metas.filter { it.type == "movie" && it.id.startsWith("tt") && !known.containsKey(it.id) }
            .map { it.id.substringBefore(':') }.filter { !wikidata.containsKey(it) }.distinct()
        if (ids.isEmpty()) return
        val query = "SELECT ?id ?l WHERE { VALUES ?id { ${ids.joinToString(" ") { "\"$it\"" }} } ?i wdt:P345 ?id . ?i wdt:P1657 ?r . ?r rdfs:label ?l FILTER(lang(?l)=\"en\") }"
        val body = get("https://query.wikidata.org/sparql".toHttpUrl().newBuilder().addQueryParameter("query", query).addQueryParameter("format", "json").build().toString())
        val rows = json.parseToJsonElement(body).jsonObject["results"]?.jsonObject?.get("bindings")?.jsonArray.orEmpty()
        ids.forEach { wikidata[it] = "" }
        rows.forEach { r ->
            val o = r.jsonObject
            val id = o["id"]?.jsonObject?.get("value")?.jsonPrimitive?.contentOrNull ?: return@forEach
            o["l"]?.jsonObject?.get("value")?.jsonPrimitive?.contentOrNull?.let { wikidata[id] = it }
        }
    }

    private suspend fun get(url: String): String = withContext(Dispatchers.IO) {
        // Wikidata asks for an identifying User-Agent.
        http.newCall(Request.Builder().url(url).header("User-Agent", "Zemu/1.0 (Android TV app)").build()).execute().use {
            if (!it.isSuccessful) throw java.io.IOException("HTTP ${it.code}")
            it.body?.string().orEmpty()
        }
    }

    /** "<rating>|<kids flag>" for a title. */
    private suspend fun lookup(m: Meta): String {
        if (m.id.startsWith("kitsu:")) {
            val id = m.id.split(':')[1]
            val attrs = json.parseToJsonElement(get("https://kitsu.io/api/edge/anime/$id")).jsonObject["data"]?.jsonObject?.get("attributes")?.jsonObject
            val age = attrs?.get("ageRating")?.jsonPrimitive?.contentOrNull.orEmpty()
            // Anime: only all-ages (G) counts as a kids' title.
            return "${Ratings.normalize(age)}|${if (age.equals("G", true)) 1 else 0}"
        }
        val genres = m.genres.ifEmpty {
            if (m.id.startsWith("tt")) runCatching {
                json.parseToJsonElement(get("https://v3-cinemeta.strem.io/meta/${m.type}/${m.id.substringBefore(':')}.json"))
                    .jsonObject["meta"]?.jsonObject?.get("genres")?.jsonArray?.mapNotNull { it.jsonPrimitive.contentOrNull }
            }.getOrNull().orEmpty() else emptyList()
        }
        val omdb = if (m.id.startsWith("tt")) scores.of(m.id.substringBefore(':'))?.rated else null
        val cert = when {
            omdb != null -> omdb
            tmdb.enabled -> tmdb.usCertification(m).orEmpty()
            m.type == "movie" && m.id.startsWith("tt") -> {
                prefetchWikidata(listOf(m))
                wikidata[m.id.substringBefore(':')].orEmpty()
            }
            else -> ""
        }
        return "${Ratings.normalize(cert)}|${if (Ratings.isKidsGenre(genres)) 1 else 0}"
    }
}
