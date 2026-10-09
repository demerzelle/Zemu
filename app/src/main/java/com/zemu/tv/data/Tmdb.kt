package com.zemu.tv.data

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

    /** IMDb id for a TMDB title, so it can open in the app's Details page. */
    suspend fun imdbIdFor(credit: TmdbCredit): String? {
        val key = "${credit.mediaType}/${credit.id}"
        imdbCache[key]?.let { return it }
        val path = if (credit.isSeries) "/tv/${credit.id}/external_ids" else "/movie/${credit.id}/external_ids"
        val imdb = json.decodeFromString(TmdbExternalIds.serializer(), get(path)).imdbId?.takeIf { it.startsWith("tt") } ?: return null
        imdbCache[key] = imdb
        return imdb
    }
}
