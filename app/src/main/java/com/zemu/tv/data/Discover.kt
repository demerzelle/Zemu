package com.zemu.tv.data

import kotlinx.serialization.Serializable
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.random.Random

/** A streaming service; [ids] are TMDB watch-provider ids ("|" = any, for renamed services). */
enum class StreamingService(val label: String, val ids: String) {
    NETFLIX("Netflix", "8"),
    HULU("Hulu", "15"),
    DISNEY("Disney+", "337"),
    MAX("HBO Max", "1899|384"),
    PRIME("Prime Video", "9|119"),
    APPLE("Apple TV", "350"),
    PARAMOUNT("Paramount+", "2303|2616|531"),
    PEACOCK("Peacock", "386|387"),
    AMC("AMC+", "526"),
    SHUDDER("Shudder", "99"),
    CRUNCHYROLL("Crunchyroll", "283"),
    ;

    val logoId: Int get() = ids.substringBefore('|').toInt()
    val provider: Provider get() = Provider(ids, label)

    companion object {
        fun of(name: String?) = entries.firstOrNull { it.name == name }

        /** A row's service: older saved rows stored the enum name, newer ones the provider ids. */
        fun providerFor(service: String?, label: String?): Provider? =
            of(service)?.provider ?: service?.let { Provider(it, label ?: "this service") }
    }
}

/** Any streaming service: TMDB provider [ids] ("|" = any of them), its name and logo. */
data class Provider(val ids: String, val label: String, val logo: String? = null)

/** A studio (movies, TMDB company id) or a network (series, TMDB network id). */
data class Studio(val key: String, val label: String, val type: String, val id: Int) {
    /** The TMDB discover parameter for this studio. */
    val param: Pair<String, String> get() = (if (type == "series") "with_networks" else "with_companies") to id.toString()

    companion object {
        val ALL = listOf(
            Studio("a24", "A24", "movie", 41077),
            Studio("pixar", "Pixar", "movie", 3),
            Studio("wb", "Warner Bros.", "movie", 174),
            Studio("marvel", "Marvel Studios", "movie", 420),
            Studio("disney", "Walt Disney Pictures", "movie", 2),
            Studio("universal", "Universal", "movie", 33),
            Studio("paramount", "Paramount", "movie", 4),
            Studio("lucasfilm", "Lucasfilm", "movie", 1),
            Studio("ghibli", "Studio Ghibli", "movie", 10342),
            Studio("blumhouse", "Blumhouse", "movie", 3172),
            Studio("neon", "Neon", "movie", 90733),
            Studio("dreamworks", "DreamWorks Animation", "movie", 521),
            Studio("legendary", "Legendary", "movie", 923),
            Studio("searchlight", "Searchlight", "movie", 43),
            Studio("lionsgate", "Lionsgate", "movie", 1632),
            Studio("columbia", "Columbia", "movie", 5),
            Studio("newline", "New Line", "movie", 12),
            Studio("focus", "Focus Features", "movie", 10146),
            Studio("illumination", "Illumination", "movie", 6704),
            Studio("hbo", "HBO", "series", 49),
            Studio("amc", "AMC", "series", 174),
            Studio("fx", "FX", "series", 88),
            Studio("netflix-tv", "Netflix", "series", 213),
            Studio("bbc", "BBC One", "series", 4),
            Studio("showtime", "Showtime", "series", 67),
            Studio("adultswim", "Adult Swim", "series", 80),
            Studio("appletv", "Apple TV", "series", 2552),
            Studio("disneyplus", "Disney+", "series", 2739),
            Studio("hulu-tv", "Hulu", "series", 453),
            Studio("prime-tv", "Prime Video", "series", 1024),
            Studio("paramountplus", "Paramount+", "series", 4330),
            Studio("peacock-tv", "Peacock", "series", 3353),
            Studio("max-tv", "HBO Max", "series", 3186),
            Studio("cartoon", "Cartoon Network", "series", 56),
            Studio("comedy", "Comedy Central", "series", 47),
            Studio("nbc", "NBC", "series", 6),
            Studio("abc", "ABC", "series", 2),
            Studio("cbs", "CBS", "series", 16),
            Studio("fox", "FOX", "series", 19),
        )

        fun of(key: String?) = ALL.firstOrNull { it.key == key }
        fun forType(type: String) = ALL.filter { it.type == type }
    }
}

/**
 * How to load one row: a TMDB discover query ([tmdb]) or an addon catalog. Serializable so a page
 * can show the last session's rows instantly while they refresh.
 */
@Serializable
data class RowSpec(
    val key: String,
    val title: String,
    val priority: Int,
    /** "movie" or "series" (the titles' type). */
    val type: String,
    val tmdb: Map<String, String>? = null,
    val addonId: String? = null,
    val catalogType: String? = null,
    val catalogId: String? = null,
    val extra: Map<String, String> = emptyMap(),
    val limit: Int = 40,
    /** "See more" opens the grid for this service (provider ids) / studio. */
    val service: String? = null,
    val serviceLabel: String? = null,
    val studio: String? = null,
)

/** A page's rows as last loaded, for an instant start next time. */
@Serializable
data class RowSnapshot(val specs: List<RowSpec> = emptyList(), val items: Map<String, List<Meta>> = emptyMap())

/** TMDB discover parameters shared by rows and the grid. */
object DiscoverParams {
    val region: String get() = Locale.getDefault().country.takeIf { it.length == 2 } ?: "US"

    fun today(): String = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())

    fun service(s: StreamingService) = service(s.ids)
    fun service(p: Provider) = service(p.ids)

    fun service(ids: String) = mapOf(
        "with_watch_providers" to ids,
        "watch_region" to region,
        "with_watch_monetization_types" to "flatrate",
    )

    fun dateField(type: String) = if (type == "series") "first_air_date" else "primary_release_date"

    fun popular() = mapOf("sort_by" to "popularity.desc")
    fun newest(type: String) = mapOf("sort_by" to "${dateField(type)}.desc", "${dateField(type)}.lte" to today(), "vote_count.gte" to "10")
    fun mostFavorited() = mapOf("sort_by" to "vote_count.desc")
    fun topRated(minVotes: Int = 300) = mapOf("sort_by" to "vote_average.desc", "vote_count.gte" to minVotes.toString())
}

/**
 * Rotating categories for a page: streaming services, studios, genres and decades. A different
 * mix each time ([seed]); [hasTmdb] gates everything that needs TMDB.
 */
object Categories {
    private val MOVIE_GENRES = listOf("Action", "Comedy", "Horror", "Sci-Fi", "Thriller", "Animation", "Romance", "Drama", "Crime", "Fantasy", "Mystery", "Documentary", "Family", "Adventure")
    private val SERIES_GENRES = listOf("Drama", "Comedy", "Crime", "Sci-Fi", "Animation", "Mystery", "Documentary", "Reality", "Action")

    /**
     * @param page "home", "movie" or "series".
     * @param taste the viewer's top genres, which come up more often.
     */
    fun tmdbRows(page: String, seed: Long, taste: List<String>, mine: List<Provider> = emptyList()): List<RowSpec> {
        val rnd = Random(seed)
        val out = mutableListOf<RowSpec>()
        val types = if (page == "home") listOf("movie", "series") else listOf(page)
        // Your own services when you've picked them, else the big ones.
        val services = mine.ifEmpty { StreamingService.entries.filter { it != StreamingService.CRUNCHYROLL }.map { it.provider } }.shuffled(rnd)
        var p = 20
        fun add(type: String, key: String, title: String, params: Map<String, String>, limit: Int = 40, service: Provider? = null, studio: Studio? = null) {
            out += RowSpec("$type/$key", title, p++, type, tmdb = params, limit = limit, service = service?.ids, serviceLabel = service?.label, studio = studio?.key)
        }
        val providerRows = (if (page == "home") 3 else 4).coerceAtMost(services.size)
        services.take(providerRows).forEachIndexed { i, s ->
            val type = types[i % types.size]
            val kinds = listOf(
                Triple("top", "Top 20 on ${s.label}", DiscoverParams.popular()),
                Triple("new", "New on ${s.label}", DiscoverParams.newest(type)),
                Triple("fav", "Most Favorited on ${s.label}", DiscoverParams.mostFavorited()),
                Triple("rated", "Top Rated on ${s.label}", DiscoverParams.topRated()),
            )
            val (k, title, params) = kinds[rnd.nextInt(kinds.size)]
            add(type, "svc-${s.ids}-$k", if (page == "home") "$title · ${if (type == "series") "Series" else "Movies"}" else title, DiscoverParams.service(s) + params, if (k == "top") 20 else 40, service = s)
        }
        types.forEach { type ->
            Studio.forType(type).shuffled(rnd).take(if (page == "home") 1 else 3).forEach { st ->
                val kinds = listOf(
                    Triple("top", "Top 20 from ${st.label}", DiscoverParams.popular()),
                    Triple("new", "New from ${st.label}", DiscoverParams.newest(type)),
                    Triple("best", "Best of ${st.label}", DiscoverParams.topRated(150)),
                )
                val (k, title, params) = kinds[rnd.nextInt(kinds.size)]
                add(type, "studio-${st.key}-$k", title, mapOf(st.param) + params, if (k == "top") 20 else 40, studio = st)
            }
        }
        if (page != "home") {
            val type = page
            val genres = (taste.filter { it in (if (type == "series") SERIES_GENRES else MOVIE_GENRES) } + (if (type == "series") SERIES_GENRES else MOVIE_GENRES).shuffled(rnd)).distinct()
            // A genre on a service, e.g. "Horror on Shudder".
            val s = services[providerRows % services.size.coerceAtLeast(1)]
            genres.getOrNull(0)?.let { g -> Tmdb.genreId(type, g)?.let { id -> add(type, "svcgenre-${s.ids}-$g", "$g on ${s.label}", DiscoverParams.service(s) + DiscoverParams.popular() + ("with_genres" to id.toString()), service = s) } }
            genres.getOrNull(1)?.let { g -> Tmdb.genreId(type, g)?.let { id -> add(type, "acclaimed-$g", "Acclaimed $g", DiscoverParams.topRated(1500) + ("with_genres" to id.toString())) } }
            val decade = listOf(1970, 1980, 1990, 2000, 2010)[rnd.nextInt(5)]
            val f = DiscoverParams.dateField(type)
            add(type, "decade-$decade", "Best of the ${decade % 100}s".replace("of the 0s", "of the 2000s"), DiscoverParams.topRated(500) + mapOf("$f.gte" to "$decade-01-01", "$f.lte" to "${decade + 9}-12-31"))
        }
        return out
    }

    /** Cinemeta genre rows for a page, rotating; [count] of them. */
    fun genreRows(cinemeta: Addon, type: String, seed: Long, taste: List<String>, count: Int, priority: Int): List<RowSpec> {
        val cat = cinemeta.manifest.catalogs.firstOrNull { it.type == type && it.id == "top" } ?: return emptyList()
        val options = cat.optionsFor("genre")
        val pool = (if (type == "series") SERIES_GENRES else MOVIE_GENRES).filter { it in options }
        val picks = (taste.filter { it in pool }.take(1) + pool.shuffled(Random(seed + type.hashCode()))).distinct().take(count)
        return picks.mapIndexed { i, g ->
            RowSpec("$type/genre-$g", "$g ${if (type == "series") "Series" else "Movies"}", priority + i, type, addonId = cinemeta.manifest.id, catalogType = type, catalogId = "top", extra = mapOf("genre" to g))
        }
    }
}
