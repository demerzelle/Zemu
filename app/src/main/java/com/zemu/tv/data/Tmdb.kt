package com.zemu.tv.data

import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.IOException
import java.util.concurrent.ConcurrentHashMap

@Serializable
data class TmdbPerson(
    val id: Long = 0,
    val name: String = "",
    val character: String? = null,
    val job: String? = null,
    @SerialName("profile_path") val profilePath: String? = null,
    val roles: List<TmdbRole> = emptyList(),
) {
    val photo: String? get() = profilePath?.let { "https://image.tmdb.org/t/p/w185$it" }
    val role: String? get() = character?.takeIf { it.isNotBlank() } ?: roles.firstOrNull()?.character
}

@Serializable data class TmdbRole(val character: String? = null)

@Serializable data class TmdbCompany(val name: String = "")

@Serializable
data class TmdbCredits(
    val cast: List<TmdbPerson> = emptyList(),
    val crew: List<TmdbPerson> = emptyList(),
)

@Serializable
private data class TmdbTitle(
    val id: Long = 0,
    @SerialName("production_companies") val companies: List<TmdbCompany> = emptyList(),
    val networks: List<TmdbCompany> = emptyList(),
    @SerialName("created_by") val createdBy: List<TmdbPerson> = emptyList(),
    val credits: TmdbCredits? = null,
    @SerialName("aggregate_credits") val aggregateCredits: TmdbCredits? = null,
)

@Serializable
private data class TmdbFind(
    @SerialName("movie_results") val movies: List<TmdbIdOnly> = emptyList(),
    @SerialName("tv_results") val tv: List<TmdbIdOnly> = emptyList(),
)

@Serializable private data class TmdbIdOnly(val id: Long = 0)

@Serializable private data class TmdbExternalIds(@SerialName("imdb_id") val imdbId: String? = null)

@Serializable
data class TmdbCredit(
    val id: Long = 0,
    @SerialName("media_type") val mediaType: String = "movie",
    val title: String? = null,
    val name: String? = null,
    val character: String? = null,
    val job: String? = null,
    @SerialName("poster_path") val posterPath: String? = null,
    @SerialName("release_date") val releaseDate: String? = null,
    @SerialName("first_air_date") val firstAirDate: String? = null,
    @SerialName("vote_average") val vote: Double = 0.0,
    @SerialName("vote_count") val voteCount: Int = 0,
    val popularity: Double = 0.0,
    @SerialName("genre_ids") val genreIds: List<Int> = emptyList(),
) {
    val displayTitle: String get() = title ?: name ?: ""
    val year: String? get() = (releaseDate ?: firstAirDate)?.take(4)?.takeIf { it.length == 4 }
    val poster: String? get() = posterPath?.let { "https://image.tmdb.org/t/p/w342$it" }
    val isSeries: Boolean get() = mediaType == "tv"
}

@Serializable
data class TmdbCombinedCredits(val cast: List<TmdbCredit> = emptyList(), val crew: List<TmdbCredit> = emptyList())

@Serializable
data class TmdbPersonDetails(
    val id: Long = 0,
    val name: String = "",
    val biography: String? = null,
    val birthday: String? = null,
    val deathday: String? = null,
    @SerialName("place_of_birth") val placeOfBirth: String? = null,
    @SerialName("known_for_department") val department: String? = null,
    @SerialName("profile_path") val profilePath: String? = null,
    @SerialName("combined_credits") private val combined: TmdbCombinedCredits? = null,
) {
    val photo: String? get() = profilePath?.let { "https://image.tmdb.org/t/p/h632$it" }

    /** Acting (or directing, for directors) credits, best known first, without talk shows and cameos as "Self". */
    val credits: List<TmdbCredit>
        get() {
            val acting = combined?.cast.orEmpty().filter { c ->
                val ch = c.character.orEmpty()
                !ch.contains("Self", ignoreCase = true) && !ch.contains("Himself") && !ch.contains("Herself") &&
                    10767 !in c.genreIds && 10763 !in c.genreIds // talk, news
            }
            val directing = combined?.crew.orEmpty().filter { it.job == "Director" || it.job == "Creator" }
            val all = if (department == "Directing" || acting.isEmpty()) directing + acting else acting + directing
            return all.distinctBy { "${it.mediaType}/${it.id}" }
                .sortedByDescending { it.voteCount * 0.7 + it.popularity * 10 }
        }
}

/** A title in a TMDB list (discover). */
@Serializable
data class TmdbItem(
    val id: Long = 0,
    val title: String? = null,
    val name: String? = null,
    val overview: String? = null,
    @SerialName("poster_path") val posterPath: String? = null,
    @SerialName("backdrop_path") val backdropPath: String? = null,
    @SerialName("release_date") val releaseDate: String? = null,
    @SerialName("first_air_date") val firstAirDate: String? = null,
    @SerialName("vote_average") val vote: Double = 0.0,
    @SerialName("vote_count") val voteCount: Int = 0,
    @SerialName("genre_ids") val genreIds: List<Int> = emptyList(),
)

@Serializable private data class TmdbPage(val results: List<TmdbItem> = emptyList(), @SerialName("total_pages") val totalPages: Int = 0)

@Serializable private data class TmdbProvider(@SerialName("provider_id") val id: Int = 0, @SerialName("logo_path") val logoPath: String? = null)
@Serializable private data class TmdbProviders(val results: List<TmdbProvider> = emptyList())

/** Extra details shown on the Details page. */
data class TitleExtras(
    val directors: List<TmdbPerson>,
    val creators: List<TmdbPerson>,
    val studios: List<String>,
    val cast: List<TmdbPerson>,
)

/**
 * Minimal TMDB client. Works with either a v3 API key or a v4 "API Read Access Token" — both are
 * free from themoviedb.org → Settings → API.
 */
class Tmdb(private val http: OkHttpClient, private val json: Json, private val key: () -> String) {
    private val extrasCache = ConcurrentHashMap<String, TitleExtras>()
    private val imdbCache = ConcurrentHashMap<String, String>()

    val enabled: Boolean get() = key().isNotBlank()

    private suspend fun get(path: String, query: String = ""): String = withContext(Dispatchers.IO) {
        val k = key().trim()
        val bearer = k.startsWith("eyJ")
        val sep = if ('?' in path || query.isNotEmpty()) "&" else "?"
        val url = "https://api.themoviedb.org/3$path" + (if (query.isNotEmpty()) "?$query" else "") +
            if (bearer) "" else "${sep}api_key=$k"
        val req = Request.Builder().url(url).apply { if (bearer) header("Authorization", "Bearer $k") }.build()
        http.newCall(req).execute().use { r ->
            if (r.code == 401) throw IOException("TMDB rejected the API key")
            if (!r.isSuccessful) throw IOException("TMDB HTTP ${r.code}")
            r.body?.string() ?: throw IOException("Empty TMDB response")
        }
    }

    /** Checks a key before saving it. */
    suspend fun validate(): Boolean = runCatching { get("/configuration") }.isSuccess

    private suspend fun tmdbIdFor(meta: Meta): Long? {
        meta.tmdbId?.toLongOrNull()?.let { return it }
        val imdb = meta.imdbId.takeIf { it.startsWith("tt") } ?: return null
        val found = json.decodeFromString(TmdbFind.serializer(), get("/find/$imdb", "external_source=imdb_id"))
        return (if (meta.type == "series") found.tv.firstOrNull() ?: found.movies.firstOrNull() else found.movies.firstOrNull() ?: found.tv.firstOrNull())?.id
    }

    /**
     * Screensaver art: 16:9 backdrops (text-free ones first) and the English (or language-free)
     * title logo, if TMDB has one.
     */
    suspend fun art(meta: Meta): Pair<List<String>, String?> {
        if (!enabled) return emptyList<String>() to null
        val id = tmdbIdFor(meta) ?: return emptyList<String>() to null
        val raw = json.parseToJsonElement(get(if (meta.type == "series") "/tv/$id/images" else "/movie/$id/images", "include_image_language=en,null")).jsonObject
        val logo = raw["logos"]?.jsonArray.orEmpty().map { it.jsonObject }
            .sortedByDescending { if (it["iso_639_1"]?.jsonPrimitive?.contentOrNull == "en") 1 else 0 }
            .firstNotNullOfOrNull { it["file_path"]?.jsonPrimitive?.contentOrNull }
            ?.let { "https://image.tmdb.org/t/p/w500${it.replace(".svg", ".png")}" }
        val list = raw["backdrops"]?.jsonArray.orEmpty().mapNotNull { e ->
            val o = e.jsonObject
            val path = o["file_path"]?.jsonPrimitive?.contentOrNull ?: return@mapNotNull null
            val lang = o["iso_639_1"]?.jsonPrimitive?.contentOrNull
            Triple(path, lang == null, o["vote_average"]?.jsonPrimitive?.doubleOrNull ?: 0.0)
        }
        return list.sortedWith(compareByDescending<Triple<String, Boolean, Double>> { it.second }.thenByDescending { it.third })
            .take(6).map { "https://image.tmdb.org/t/p/w1280${it.first}" } to logo
    }

    /** TheTVDB id of a series (fanart.tv indexes shows by it). */
    suspend fun tvdbId(meta: Meta): String? {
        if (!enabled || meta.type != "series") return null
        val id = tmdbIdFor(meta) ?: return null
        return json.parseToJsonElement(get("/tv/$id/external_ids")).jsonObject["tvdb_id"]?.jsonPrimitive?.contentOrNull
    }

    suspend fun extras(meta: Meta): TitleExtras? {
        if (!enabled) return null
        extrasCache[meta.id]?.let { return it }
        val id = tmdbIdFor(meta) ?: return null
        val tv = meta.type == "series"
        val raw = if (tv) get("/tv/$id", "append_to_response=aggregate_credits") else get("/movie/$id", "append_to_response=credits")
        val t = json.decodeFromString(TmdbTitle.serializer(), raw)
        val credits = (if (tv) t.aggregateCredits else t.credits) ?: TmdbCredits()
        val extras = TitleExtras(
            directors = credits.crew.filter { it.job == "Director" }.distinctBy { it.id }.take(3),
            creators = t.createdBy.take(3),
            studios = (t.companies.map { it.name } + t.networks.map { it.name }).distinct().take(3),
            cast = credits.cast.distinctBy { it.id }.take(20),
        )
        extrasCache[meta.id] = extras
        return extras
    }

    suspend fun person(id: Long): TmdbPersonDetails =
        json.decodeFromString(TmdbPersonDetails.serializer(), get("/person/$id", "append_to_response=combined_credits"))

    private val discoverCache = ConcurrentHashMap<String, Pair<Long, List<Meta>>>()

    /**
     * TMDB `/discover` as app titles. Ids are "tmdb:<movie|tv>:<id>" and are turned into IMDb ids
     * only when opened ([imdbFor]), so rows load with one request each. Cached for 30 minutes.
     */
    suspend fun discover(type: String, params: Map<String, String>, page: Int = 1): List<Meta> {
        if (!enabled) return emptyList()
        val media = if (type == "series") "tv" else "movie"
        val query = (params + ("page" to page.toString()) + ("include_adult" to "false")).entries
            .sortedBy { it.key }.joinToString("&") { "${it.key}=${java.net.URLEncoder.encode(it.value, "UTF-8")}" }
        val key = "$media?$query"
        val now = System.currentTimeMillis()
        discoverCache[key]?.let { (at, list) -> if (now - at < 30 * 60_000L) return list }
        val list = json.decodeFromString(TmdbPage.serializer(), get("/discover/$media", query)).results
            .filter { it.posterPath != null }
            .map { it.toMeta(type) }
        discoverCache[key] = now to list
        return list
    }

    private fun TmdbItem.toMeta(type: String): Meta {
        val tv = type == "series"
        val names = if (tv) TV_GENRES else MOVIE_GENRES
        return Meta(
            id = "tmdb:${if (tv) "tv" else "movie"}:$id",
            type = type,
            tmdbId = id.toString(),
            name = title ?: name,
            poster = posterPath?.let { "https://image.tmdb.org/t/p/w342$it" },
            background = backdropPath?.let { "https://image.tmdb.org/t/p/w1280$it" },
            description = overview,
            releaseInfo = (releaseDate ?: firstAirDate)?.take(4)?.takeIf { it.length == 4 },
            released = releaseDate ?: firstAirDate,
            imdbRating = vote.takeIf { voteCount >= 20 && it > 0 }?.let { "%.1f".format(java.util.Locale.US, it) },
            genres = genreIds.mapNotNull { names[it] },
        )
    }

    private var providerLogos: Map<Int, String>? = null

    /** Streaming service logos by TMDB provider id. */
    suspend fun providerLogos(region: String): Map<Int, String> {
        providerLogos?.let { return it }
        if (!enabled) return emptyMap()
        val found = runCatching {
            json.decodeFromString(TmdbProviders.serializer(), get("/watch/providers/movie", "watch_region=$region")).results
                .mapNotNull { p -> p.logoPath?.let { p.id to "https://image.tmdb.org/t/p/w154$it" } }.toMap()
        }.getOrDefault(emptyMap())
        if (found.isNotEmpty()) providerLogos = found
        return found
    }

    /** The IMDb id of a "tmdb:<movie|tv>:<id>" title. */
    suspend fun imdbFor(tmdbKey: String): String? {
        val parts = tmdbKey.split(':')
        val id = parts.getOrNull(2)?.toLongOrNull() ?: return null
        return imdbIdFor(TmdbCredit(id = id, mediaType = parts[1]))
    }

    /** IMDb id for a TMDB title, so it can open in the app's Details page. */
    suspend fun imdbIdFor(credit: TmdbCredit): String? {
        val key = "${credit.mediaType}/${credit.id}"
        imdbCache[key]?.let { return it }
        val path = if (credit.isSeries) "/tv/${credit.id}/external_ids" else "/movie/${credit.id}/external_ids"
        val imdb = json.decodeFromString(TmdbExternalIds.serializer(), get(path)).imdbId?.takeIf { it.startsWith("tt") } ?: return null
        imdbCache[key] = imdb
        return imdb
    }

    companion object {
        /** TMDB genre ids, named the way Cinemeta names them. */
        val MOVIE_GENRES = mapOf(
            28 to "Action", 12 to "Adventure", 16 to "Animation", 35 to "Comedy", 80 to "Crime", 99 to "Documentary",
            18 to "Drama", 10751 to "Family", 14 to "Fantasy", 36 to "History", 27 to "Horror", 10402 to "Music",
            9648 to "Mystery", 10749 to "Romance", 878 to "Sci-Fi", 53 to "Thriller", 10752 to "War", 37 to "Western",
        )
        val TV_GENRES = mapOf(
            10759 to "Action", 16 to "Animation", 35 to "Comedy", 80 to "Crime", 99 to "Documentary", 18 to "Drama",
            10751 to "Family", 10762 to "Kids", 9648 to "Mystery", 10764 to "Reality", 10765 to "Sci-Fi",
            10768 to "War", 37 to "Western",
        )

        /** TMDB genre id for a genre name on a "movie" or "series" page, if TMDB has it. */
        fun genreId(type: String, name: String): Int? =
            (if (type == "series") TV_GENRES else MOVIE_GENRES).entries.firstOrNull { it.value.equals(name, ignoreCase = true) }?.key
                ?: if (type == "series" && name in setOf("Fantasy", "Science Fiction")) 10765
                else if (type == "series" && name in setOf("Adventure")) 10759 else null
    }
}
