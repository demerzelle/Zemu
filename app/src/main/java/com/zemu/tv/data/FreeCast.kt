package com.zemu.tv.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request
import java.net.URLEncoder
import java.util.concurrent.ConcurrentHashMap

/** A cast member from any source. [personKey] opens the person page ("tmdb:123", "imdb:nm123"). */
data class CastPerson(val name: String, val role: String?, val photo: String?, val personKey: String?)

/** Person page data from the free sources. */
data class FreePerson(
    val name: String,
    val photo: String?,
    val description: String?,
    val born: String?,
    val credits: List<Meta>,
)

/**
 * Cast and filmographies without any API key:
 *  - TVmaze (series cast with photos and characters)
 *  - Wikidata (movie cast lists and actor filmographies, by IMDb ids)
 *  - IMDb's public search suggestions (head shots)
 */
class FreeCast(private val http: OkHttpClient, private val json: Json) {
    private val castCache = ConcurrentHashMap<String, List<CastPerson>>()
    private val photoCache = ConcurrentHashMap<String, String>()
    private val personCache = ConcurrentHashMap<String, FreePerson>()

    private suspend fun get(url: String): JsonElement? = withContext(Dispatchers.IO) {
        runCatching {
            val req = Request.Builder().url(url).header("User-Agent", "Zemu/1.0 (Android TV media app)").header("Accept", "application/json").build()
            http.newCall(req).execute().use { r -> if (!r.isSuccessful) null else r.body?.string()?.let { json.parseToJsonElement(it) } }
        }.getOrNull()
    }

    private fun JsonElement?.str(vararg path: String): String? {
        var e: JsonElement? = this
        for (p in path) e = (e as? JsonObject)?.get(p)
        return (e as? JsonPrimitive)?.contentOrNull
    }

    private suspend fun sparql(query: String): List<JsonObject> {
        val url = "https://query.wikidata.org/sparql".toHttpUrl().newBuilder()
            .addQueryParameter("query", query).addQueryParameter("format", "json").build().toString()
        return (get(url)?.jsonObject?.get("results")?.jsonObject?.get("bindings") as? JsonArray)?.map { it.jsonObject }.orEmpty()
    }

    private fun commonsThumb(url: String?) = url?.replace("http://", "https://")?.let { "$it?width=300" }

    /** IMDb head shot for a name (also returns the IMDb person id). */
    suspend fun imdbPerson(name: String): Pair<String?, String?> {
        val enc = URLEncoder.encode(name.lowercase(), "UTF-8").replace("+", "%20")
        val first = name.lowercase().firstOrNull { it.isLetterOrDigit() } ?: 'x'
        val d = (get("https://v3.sg.media-imdb.com/suggestion/$first/$enc.json")?.jsonObject?.get("d") as? JsonArray)
            ?.map { it.jsonObject }?.firstOrNull { it.str("id")?.startsWith("nm") == true } ?: return null to null
        val img = d.str("i", "imageUrl")?.replace("._V1_.jpg", "._V1_UX300_.jpg")
        return d.str("id") to img
    }

    suspend fun photoFor(name: String): String? {
        photoCache[name]?.let { return it.ifEmpty { null } }
        val photo = imdbPerson(name).second
        photoCache[name] = photo.orEmpty()
        return photo
    }

    suspend fun cast(meta: Meta): List<CastPerson> {
        castCache[meta.id]?.let { return it }
        val imdb = meta.imdbId.takeIf { it.startsWith("tt") }
        val list = when {
            imdb != null && meta.type == "series" -> tvmaze(imdb).ifEmpty { wikidataCast(imdb, meta) }
            imdb != null -> wikidataCast(imdb, meta)
            else -> emptyList()
        }.ifEmpty { meta.cast.map { CastPerson(it, null, null, null) } }
        castCache[meta.id] = list
        return list
    }

    private suspend fun tvmaze(imdb: String): List<CastPerson> {
        val show = get("https://api.tvmaze.com/lookup/shows?imdb=$imdb") ?: return emptyList()
        val id = show.str("id") ?: return emptyList()
        val cast = get("https://api.tvmaze.com/shows/$id/cast") as? JsonArray ?: return emptyList()
        return cast.map { it.jsonObject }.mapNotNull { c ->
            val name = c.str("person", "name") ?: return@mapNotNull null
            CastPerson(
                name = name,
                role = c.str("character", "name"),
                photo = c.str("person", "image", "medium") ?: c.str("character", "image", "medium"),
                personKey = "name:$name",
            )
        }.distinctBy { it.name }
    }

    private suspend fun wikidataCast(imdb: String, meta: Meta): List<CastPerson> {
        val rows = sparql(
            """SELECT ?actorLabel ?img ?nm WHERE { ?film wdt:P345 "$imdb". ?film wdt:P161 ?actor.
              OPTIONAL { ?actor wdt:P18 ?img } OPTIONAL { ?actor wdt:P345 ?nm }
              SERVICE wikibase:label { bd:serviceParam wikibase:language "en". } } LIMIT 40""",
        )
        val people = rows.mapNotNull { r ->
            val name = r.str("actorLabel", "value")?.takeIf { !it.startsWith("Q") } ?: return@mapNotNull null
            val nm = r.str("nm", "value")
            CastPerson(name, null, commonsThumb(r.str("img", "value")), nm?.let { "imdb:$it" } ?: "name:$name")
        }.distinctBy { it.name }
        // Wikidata has no billing order: put the stars Cinemeta lists first.
        val top = meta.cast.map { it.lowercase() }
        return people.sortedBy { p -> top.indexOf(p.name.lowercase()).let { if (it < 0) Int.MAX_VALUE else it } }
    }

    /** Photo and name only, available almost immediately, for the top of the person page. */
    suspend fun personHeader(key: String): Pair<String, String?>? {
        val name0 = key.substringAfter("name:", "")
        if (name0.isNotEmpty()) return name0 to photoFor(name0)
        val nm = key.substringAfter("imdb:", "").ifEmpty { return null }
        val row = sparql("""SELECT ?aLabel WHERE { ?a wdt:P345 "$nm". SERVICE wikibase:label { bd:serviceParam wikibase:language "en". } } LIMIT 1""").firstOrNull()
        val name = row?.str("aLabel", "value") ?: return null
        return name to photoFor(name)
    }

    /** [key] is "imdb:nm…" or "name:Full Name". */
    suspend fun person(key: String): FreePerson? {
        personCache[key]?.let { return it }
        val name0 = key.substringAfter("name:", "")
        var nm = key.substringAfter("imdb:", "").ifEmpty { null }
        var imdbPhoto: String? = null
        if (nm == null && name0.isNotEmpty()) imdbPerson(name0).let { (id, img) -> nm = id; imdbPhoto = img }
        val id = nm ?: return null
        val info = sparql(
            """SELECT ?aLabel ?aDescription ?img ?born WHERE { ?a wdt:P345 "$id".
              OPTIONAL { ?a wdt:P18 ?img } OPTIONAL { ?a wdt:P569 ?born }
              SERVICE wikibase:label { bd:serviceParam wikibase:language "en". } } LIMIT 1""",
        ).firstOrNull()
        val films = sparql(
            """SELECT ?film ?filmLabel ?tt ?date ?inst WHERE { ?a wdt:P345 "$id". { ?film wdt:P161 ?a } UNION { ?film wdt:P57 ?a }
              ?film wdt:P345 ?tt. FILTER(STRSTARTS(?tt, "tt"))
              OPTIONAL { ?film wdt:P577 ?date } OPTIONAL { ?film wdt:P31 ?inst }
              SERVICE wikibase:label { bd:serviceParam wikibase:language "en". } } LIMIT 300""",
        )
        val tvTypes = setOf("Q5398426", "Q117467246", "Q526877", "Q1259759", "Q581714", "Q63952888")
        val credits = films.groupBy { it.str("tt", "value") }.mapNotNull { (tt, rows) ->
            tt ?: return@mapNotNull null
            val isTv = rows.any { it.str("inst", "value")?.substringAfterLast('/') in tvTypes }
            val year = rows.mapNotNull { it.str("date", "value")?.take(4) }.minOrNull()
            Meta(id = tt, type = if (isTv) "series" else "movie", name = rows.first().str("filmLabel", "value"), releaseInfo = year)
        }.filter { it.name?.startsWith("Q") == false }.sortedByDescending { it.releaseInfo ?: "" }
        val name = info?.str("aLabel", "value") ?: name0.ifEmpty { id }
        val photo = imdbPhoto ?: photoFor(name) ?: commonsThumb(info?.str("img", "value"))
        val p = FreePerson(name, photo, info?.str("aDescription", "value"), info?.str("born", "value")?.take(10), credits)
        personCache[key] = p
        return p
    }
}
