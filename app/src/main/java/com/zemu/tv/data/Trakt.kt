package com.zemu.tv.data

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonObject
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

/** A title friends recommended on Trakt, and who (display names). */
data class FriendRec(val meta: Meta, val from: List<String>)

/** What Trakt shows to link a TV: go to [url] and enter [userCode]. */
data class TraktLink(val deviceCode: String, val userCode: String, val url: String, val intervalSec: Int, val expiresAt: Long)

/**
 * Trakt (trakt.tv): your watchlist mirrors My List both ways, watched movies come in from Trakt,
 * and what you play is scrobbled (Trakt marks it watched once you're past 80%). Uses your own
 * Trakt API app (free): its Client ID and secret go in Settings.
 */
class Trakt(private val http: OkHttpClient, private val json: Json, private val store: UserStore, private val scope: CoroutineScope) {
    private val base = "https://api.trakt.tv"
    private val settings get() = store.settings.value

    val configured: Boolean get() = settings.traktClientId.isNotBlank() && settings.traktClientSecret.isNotBlank()
    val connected: Boolean get() = configured && settings.traktAccessToken.isNotBlank()

    /** True once Trakt says you have at least one friend; the friend features stay hidden otherwise. */
    val hasFriends = kotlinx.coroutines.flow.MutableStateFlow(false)
    /** Titles on your friends' lists, newest first. */
    val friendRecs = kotlinx.coroutines.flow.MutableStateFlow<List<FriendRec>>(emptyList())
    /** Ids (imdb) of what you've recommended. */
    val myRecs = kotlinx.coroutines.flow.MutableStateFlow<Set<String>>(emptySet())

    private val recsSlug = "zemu-recommendations"

    init {
        // Push My List changes to the Trakt watchlist as they happen.
        scope.launch {
            var before = store.myListNow().map { it.id to it.type }.toSet()
            // Wait for the flow to catch up with what's saved, so its empty start isn't taken as "all removed".
            kotlinx.coroutines.withTimeoutOrNull(10_000) { store.myList.first { l -> l.map { it.id to it.type }.toSet() == before } }
            store.myList.collect { list ->
                val now = list.map { it.id to it.type }.toSet()
                if (connected) runCatching {
                    (now - before).takeIf { it.isNotEmpty() }?.let { post("/sync/watchlist", idsBody(it)) }
                    (before - now).takeIf { it.isNotEmpty() }?.let { post("/sync/watchlist/remove", idsBody(it)) }
                }
                before = now
            }
        }
        scope.launch {
            store.settings.first { it.traktAccessToken.isNotBlank() }
            if (connected) runCatching { sync() }
            if (connected) runCatching { refreshFriends() }
        }
    }

    private fun idsBody(items: Set<Pair<String, String>>): JsonObject = buildJsonObject {
        fun list(type: String) = buildJsonArray {
            items.filter { it.second == type && it.first.startsWith("tt") }.forEach { (id, _) ->
                add(buildJsonObject { putJsonObject("ids") { put("imdb", id.substringBefore(':')) } })
            }
        }
        put("movies", list("movie"))
        put("shows", list("series"))
    }

    // ---- Linking (device code) ----

    suspend fun startLink(): TraktLink {
        val o = call("/oauth/device/code", buildJsonObject { put("client_id", settings.traktClientId.trim()) }, auth = false).jsonObject
        return TraktLink(
            o.str("device_code"), o.str("user_code"), o.str("verification_url").ifEmpty { "https://trakt.tv/activate" },
            o["interval"]?.jsonPrimitive?.intOrNull ?: 5, System.currentTimeMillis() + (o["expires_in"]?.jsonPrimitive?.longOrNull ?: 600) * 1000,
        )
    }

    /** One poll: true once linked, false while waiting; throws when denied or expired. */
    suspend fun pollLink(link: TraktLink): Boolean {
        val body = buildJsonObject {
            put("code", link.deviceCode); put("client_id", settings.traktClientId.trim()); put("client_secret", settings.traktClientSecret.trim())
        }
        val (code, text) = raw("POST", "/oauth/device/token", body.toString(), auth = false)
        return when (code) {
            200 -> { saveTokens(json.parseToJsonElement(text).jsonObject); scope.launch { runCatching { sync() }; runCatching { refreshFriends() } }; true }
            400, 429 -> false
            else -> throw IllegalStateException(if (code == 418) "Linking was declined on Trakt." else "The code expired. Try again.")
        }
    }

    suspend fun disconnect() {
        store.updateSettings { it.copy(traktAccessToken = "", traktRefreshToken = "", traktExpiresAt = 0) }
        hasFriends.value = false; friendRecs.value = emptyList(); myRecs.value = emptySet()
    }

    private suspend fun saveTokens(o: JsonObject) = store.updateSettings {
        it.copy(
            traktAccessToken = o.str("access_token"), traktRefreshToken = o.str("refresh_token"),
            traktExpiresAt = System.currentTimeMillis() + (o["expires_in"]?.jsonPrimitive?.longOrNull ?: 0) * 1000,
        )
    }

    private suspend fun refreshIfNeeded() {
        if (settings.traktExpiresAt - System.currentTimeMillis() > 24 * 3600_000L) return
        val body = buildJsonObject {
            put("refresh_token", settings.traktRefreshToken); put("client_id", settings.traktClientId.trim())
            put("client_secret", settings.traktClientSecret.trim()); put("redirect_uri", "urn:ietf:wg:oauth:2.0:oob"); put("grant_type", "refresh_token")
        }
        saveTokens(call("/oauth/token", body, auth = false).jsonObject)
    }

    // ---- Sync ----

    /** Brings in the Trakt watchlist (added to My List) and watched movies. Returns what was added. */
    suspend fun sync(): String {
        refreshIfNeeded()
        val mine = store.myList.value.map { it.id }.toSet()
        val wanted = listOf("movies" to "movie", "shows" to "series").flatMap { (path, type) ->
            get("/sync/watchlist/$path").jsonArray.mapNotNull { e ->
                val item = e.jsonObject[if (type == "movie") "movie" else "show"]?.jsonObject ?: return@mapNotNull null
                val imdb = item["ids"]?.jsonObject?.get("imdb")?.jsonPrimitive?.contentOrNull ?: return@mapNotNull null
                Meta(id = imdb, type = type, name = item.str("title"), releaseInfo = item["year"]?.jsonPrimitive?.contentOrNull)
            }
        }.filter { it.id !in mine }
        wanted.forEach { store.toggleMyList(it) }
        val watched = get("/sync/watched/movies").jsonArray.mapNotNull {
            it.jsonObject["movie"]?.jsonObject?.get("ids")?.jsonObject?.get("imdb")?.jsonPrimitive?.contentOrNull
        }
        val newWatched = store.addWatched(watched)
        return "Added ${wanted.size} from your watchlist and $newWatched watched movies."
    }

    // ---- Friends ----
    // Friends are mutual follows on Trakt. Each person's recommendations are a friends-only Trakt
    // list named "Zemu Recommendations"; Home shows what your friends put on theirs.

    suspend fun refreshFriends() {
        if (!connected) return
        refreshIfNeeded()
        val friends = get("/users/me/friends").jsonArray.mapNotNull { it.jsonObject["user"]?.jsonObject }
        hasFriends.value = friends.isNotEmpty()
        myRecs.value = listItems("me").map { it.id }.toSet()
        val seen = LinkedHashMap<String, FriendRec>()
        for (u in friends.take(50)) {
            val slug = u["ids"]?.jsonObject?.get("slug")?.jsonPrimitive?.contentOrNull ?: continue
            val name = u.str("name").ifBlank { u.str("username") }.substringBefore(' ')
            for (m in runCatching { listItems(slug) }.getOrDefault(emptyList())) {
                val cur = seen[m.id]
                seen[m.id] = cur?.copy(from = cur.from + name) ?: FriendRec(m, listOf(name))
            }
        }
        friendRecs.value = seen.values.filter { it.meta.id !in myRecs.value }.toList()
    }

    /** Adds [meta] to (or takes it off) your recommendations list, creating the list the first time. */
    suspend fun recommend(meta: Meta, on: Boolean) {
        refreshIfNeeded()
        val ids = setOf(meta.imdbId to meta.type)
        if (on) {
            if (raw("GET", "/users/me/lists/$recsSlug", null).first == 404) post(
                "/users/me/lists",
                buildJsonObject {
                    put("name", "Zemu Recommendations"); put("privacy", "friends")
                    put("description", "Titles I recommend. Friends who use Zemu see them on Home.")
                },
            )
            post("/users/me/lists/$recsSlug/items", idsBody(ids))
            myRecs.value = myRecs.value + meta.imdbId
        } else {
            post("/users/me/lists/$recsSlug/items/remove", idsBody(ids))
            myRecs.value = myRecs.value - meta.imdbId
        }
    }

    /** A user's recommendations list, newest first; empty when they haven't made one. */
    private suspend fun listItems(user: String): List<Meta> {
        val (code, text) = raw("GET", "/users/$user/lists/$recsSlug/items?sort_by=added&sort_how=desc", null)
        if (code == 404) return emptyList()
        return json.parseToJsonElement(check(code to text)).jsonArray.mapNotNull { e ->
            val o = e.jsonObject
            val type = if (o.str("type") == "show") "series" else "movie"
            val item = o[if (type == "movie") "movie" else "show"]?.jsonObject ?: return@mapNotNull null
            val imdb = item["ids"]?.jsonObject?.get("imdb")?.jsonPrimitive?.contentOrNull ?: return@mapNotNull null
            Meta(id = imdb, type = type, name = item.str("title"), releaseInfo = item["year"]?.jsonPrimitive?.contentOrNull)
        }
    }

    // ---- Scrobbling ----

    /** [action]: "start", "pause" or "stop"; [videoId] is "tt…" for a movie or "tt…:season:episode". */
    fun scrobble(action: String, meta: Meta, videoId: String, progress: Float) {
        if (!connected) return
        val imdb = meta.imdbId.takeIf { it.startsWith("tt") } ?: return
        val parts = videoId.split(':')
        val body = buildJsonObject {
            if (meta.type == "series" && parts.size >= 3) {
                putJsonObject("show") { putJsonObject("ids") { put("imdb", imdb) } }
                putJsonObject("episode") { put("season", parts[1].toIntOrNull() ?: 1); put("number", parts[2].toIntOrNull() ?: 1) }
            } else putJsonObject("movie") { putJsonObject("ids") { put("imdb", imdb) } }
            put("progress", (progress * 100).coerceIn(0f, 100f))
        }
        scope.launch { runCatching { refreshIfNeeded(); post("/scrobble/$action", body) } }
    }

    // ---- HTTP ----

    private suspend fun get(path: String): JsonElement = json.parseToJsonElement(check(raw("GET", path, null)))
    private suspend fun post(path: String, body: JsonObject): JsonElement = call(path, body)
    private suspend fun call(path: String, body: JsonObject, auth: Boolean = true): JsonElement =
        json.parseToJsonElement(check(raw("POST", path, body.toString(), auth)).ifEmpty { "{}" })

    private fun check(r: Pair<Int, String>): String {
        if (r.first !in 200..299) throw java.io.IOException("Trakt HTTP ${r.first}")
        return r.second
    }

    private suspend fun raw(method: String, path: String, body: String?, auth: Boolean = true): Pair<Int, String> = withContext(Dispatchers.IO) {
        val req = Request.Builder().url(base + path)
            .header("trakt-api-version", "2")
            .header("trakt-api-key", settings.traktClientId.trim())
            .apply { if (auth) header("Authorization", "Bearer ${settings.traktAccessToken}") }
            .method(method, body?.toRequestBody("application/json".toMediaType()))
            .build()
        http.newCall(req).execute().use { it.code to (it.body?.string().orEmpty()) }
    }

    private fun JsonObject.str(k: String) = this[k]?.jsonPrimitive?.contentOrNull.orEmpty()
}
