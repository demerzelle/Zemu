package com.zemu.tv.recommend

import com.zemu.tv.data.AddonRepository
import com.zemu.tv.data.Meta
import com.zemu.tv.data.WatchEntry
import com.zemu.tv.data.rating
import com.zemu.tv.data.releasedDate
import com.zemu.tv.data.title
import com.zemu.tv.data.year
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.ConcurrentHashMap
import kotlin.math.abs
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.roundToInt
import kotlin.random.Random

data class Scored(val meta: Meta, val score: Double) {
    val matchPercent: Int get() = (55 + score * 44).roundToInt().coerceIn(50, 99)
}

/** Genre affinity learned from watch history and My List. */
data class TasteProfile(val genreWeights: Map<String, Double>, val seen: Set<String>) {
    val isEmpty: Boolean get() = genreWeights.isEmpty()

    fun affinity(m: Meta): Double {
        if (isEmpty || m.genres.isEmpty()) return 0.0
        val max = genreWeights.values.max()
        val top = m.genres.take(3)
        return (top.sumOf { genreWeights[it] ?: 0.0 } / (max * top.size)).coerceIn(0.0, 1.0)
    }

    fun topGenres(n: Int): List<String> = genreWeights.entries.sortedByDescending { it.value }.take(n).map { it.key }

    companion object {
        fun from(
            history: List<WatchEntry>,
            myList: List<Meta>,
            rated: List<Meta> = emptyList(),
            ratings: Map<String, Int> = emptyMap(),
        ): TasteProfile {
            val w = mutableMapOf<String, Double>()
            history.forEachIndexed { i, e ->
                // A thumbs-down title shouldn't pull its genres up just because it was watched.
                if ((ratings[e.meta.id] ?: 0) < 0) return@forEachIndexed
                val weight = 0.92.pow(i) * (0.5 + e.progress.coerceIn(0f, 1f))
                e.meta.genres.forEach { g -> w[g] = (w[g] ?: 0.0) + weight }
            }
            myList.forEach { m -> m.genres.forEach { g -> w[g] = (w[g] ?: 0.0) + 0.6 } }
            rated.forEach { m ->
                val r = ratings[m.id] ?: return@forEach
                m.genres.forEach { g -> w[g] = (w[g] ?: 0.0) + if (r > 0) 1.5 else -1.0 }
            }
            val positive = w.filterValues { it > 0 }
            val disliked = ratings.filterValues { it < 0 }.keys
            return TasteProfile(positive, history.map { it.meta.id }.toSet() + disliked)
        }
    }
}

/** A recommendation row for Home. */
data class SuggestionRow(
    val key: String,
    val title: String,
    val items: List<Meta>,
    /** Lower comes first on Home. */
    val priority: Int,
    val match: Map<String, Int> = emptyMap(),
    val subtitles: Map<String, String> = emptyMap(),
    val landscape: Boolean = false,
)

class Recommender(private val addons: AddonRepository) {
    private val cache = ConcurrentHashMap<String, List<Meta>>()

    /** Local calendar day number; changes at midnight so daily rows rotate. */
    fun daySeed(): Long {
        val now = System.currentTimeMillis()
        return (now + TimeZone.getDefault().getOffset(now)) / 86_400_000L
    }

    private fun dateString(daysAgo: Int): String =
        SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date(System.currentTimeMillis() - daysAgo * 86_400_000L))

    /** Several pages of a Cinemeta catalog, cached for the session. */
    private suspend fun pages(type: String, catalog: String, extra: Map<String, String>, count: Int, startSkip: Int = 0): List<Meta> {
        val key = "$type/$catalog/$extra/$count/$startSkip"
        cache[key]?.let { return it }
        val cinemeta = addons.cinemeta ?: return emptyList()
        val out = mutableListOf<Meta>()
        var skip = startSkip
        repeat(count) {
            val page = runCatching {
                addons.catalog(cinemeta, type, catalog, if (skip > 0) extra + ("skip" to skip.toString()) else extra)
            }.getOrDefault(emptyList())
            if (page.isEmpty()) return@repeat
            out += page
            skip += page.size
        }
        val result = out.distinctBy { it.id }
        if (result.isNotEmpty()) cache[key] = result
        return result
    }

    /** Popular + top-rated titles for a genre: up to ~200 candidates. */
    suspend fun pool(type: String, genre: String?, pageCount: Int = 2): List<Meta> = coroutineScope {
        val extra = if (genre != null) mapOf("genre" to genre) else emptyMap()
        listOf("top", "imdbRating").map { cat -> async { pages(type, cat, extra, pageCount) } }
            .awaitAll().flatten().distinctBy { it.id }
    }

    fun similarity(a: Meta, b: Meta): Double {
        val ga = a.genres.toSet()
        val gb = b.genres.toSet()
        val jaccard = if (ga.isEmpty() || gb.isEmpty()) 0.0 else (ga intersect gb).size.toDouble() / (ga union gb).size
        val rating = (b.rating ?: 6.0) / 10.0
        val ya = a.year
        val yb = b.year
        val yearSim = if (ya == null || yb == null) 0.5 else (1.0 - abs(ya - yb) / 30.0).coerceIn(0.0, 1.0)
        val people = ((a.cast.take(6) + a.director).toSet() intersect (b.cast.take(6) + b.director).toSet()).size
        return (0.5 * jaccard + 0.25 * rating + 0.15 * yearSim + min(people, 2) * 0.05).coerceIn(0.0, 1.0)
    }

    /** Kitsu (anime) titles for a genre, from the popular and top-rated catalogs. */
    private suspend fun animePool(genre: String?): List<Meta> {
        val kitsu = addons.kitsu ?: return emptyList()
        val supported = kitsu.manifest.catalogs.firstOrNull { it.id == "kitsu-anime-popular" }?.optionsFor("genre").orEmpty()
        val extra = if (genre != null && genre in supported) mapOf("genre" to genre) else emptyMap()
        val key = "kitsu/${extra.values.joinToString()}"
        cache[key]?.let { return it }
        val result = coroutineScope {
            listOf("kitsu-anime-popular", "kitsu-anime-rating").map { cat ->
                async { runCatching { addons.catalog(kitsu, "anime", cat, extra) }.getOrDefault(emptyList()) }
            }.awaitAll().flatten().distinctBy { it.id }
        }
        if (result.isNotEmpty()) cache[key] = result
        return result
    }

    suspend fun moreLikeThis(meta: Meta, exclude: Set<String> = emptySet(), limit: Int = 50): List<Scored> {
        val genres: List<String?> = meta.genres.take(3).ifEmpty { listOf(null) }
        val anime = meta.id.startsWith("kitsu:")
        val candidates = coroutineScope {
            genres.map { g -> async { if (anime) animePool(g) else pool(meta.type, g) } }.awaitAll().flatten().distinctBy { it.id }
        }
        return candidates
            .filter { it.id != meta.id && it.id !in exclude }
            .map { Scored(it, similarity(meta, it)) }
            .sortedByDescending { it.score }
            .take(limit)
    }

    /** Highly rated titles in the same genres that aren't already in [exclude] — a second row for Details. */
    suspend fun genreFavorites(meta: Meta, exclude: Set<String>, limit: Int = 40): Pair<String, List<Scored>>? {
        val genre = meta.genres.firstOrNull() ?: return null
        if (meta.id.startsWith("kitsu:")) return null
        val items = pool(meta.type, genre, pageCount = 3)
            .filter { it.id != meta.id && it.id !in exclude && (it.rating ?: 0.0) >= 6.5 }
            .sortedByDescending { it.rating ?: 0.0 }
            .take(limit)
            .map { Scored(it, similarity(meta, it)) }
        return if (items.isEmpty()) null else genre to items
    }

    /** Best matches, with the long tail reshuffled every day so the row feels fresh. */
    suspend fun topPicks(profile: TasteProfile, limit: Int = 40, seed: Long = daySeed()): List<Scored> {
        if (profile.isEmpty) return emptyList()
        val genres = profile.topGenres(4)
        val candidates = coroutineScope {
            listOf("movie", "series").flatMap { type -> genres.map { g -> async { pool(type, g) } } }
                .awaitAll().flatten().distinctBy { it.id }
        }
        val ranked = candidates
            .filter { it.id !in profile.seen }
            .map { Scored(it, 0.6 * profile.affinity(it) + 0.4 * ((it.rating ?: 6.0) / 10.0)) }
            .sortedByDescending { it.score }
        val head = ranked.take(8)
        val tail = ranked.drop(8).take(140).shuffled(Random(seed)).take(limit - head.size)
        return head + tail
    }

    /** Netflix-style "% Match" for any title. */
    fun matchPercent(m: Meta, profile: TasteProfile): Int {
        val r = (m.rating ?: 6.5) / 10.0
        val x = if (profile.isEmpty) r else 0.55 * profile.affinity(m) + 0.45 * r
        return (50 + x * 49).roundToInt().coerceIn(50, 99)
    }

    /**
     * Home rows that change day by day: personal picks, "because you watched", a genre
     * spotlight, hidden gems, a "best of" year, new releases and new episodes of your shows.
     */
    suspend fun dailyRows(profile: TasteProfile, history: List<WatchEntry>, myList: List<Meta>): List<SuggestionRow> = coroutineScope {
        val seed = daySeed()
        val rnd = Random(seed)
        val cinemeta = addons.cinemeta ?: return@coroutineScope emptyList()
        val movieGenres = cinemeta.manifest.catalogs.firstOrNull { it.type == "movie" && it.id == "top" }?.optionsFor("genre").orEmpty()
        val yearOptions = cinemeta.manifest.catalogs.firstOrNull { it.type == "movie" && it.id == "year" }?.optionsFor("genre").orEmpty()
        val seen = profile.seen
        fun scoredRow(key: String, title: String, priority: Int, items: List<Scored>) =
            SuggestionRow(key, title, items.map { it.meta }, priority, match = items.associate { it.meta.id to it.matchPercent })
        fun plainRow(key: String, title: String, priority: Int, items: List<Meta>) =
            SuggestionRow(key, title, items, priority, match = items.associate { it.id to matchPercent(it, profile) })

        val jobs = mutableListOf<kotlinx.coroutines.Deferred<SuggestionRow?>>()

        // Picked for you today
        jobs += async {
            topPicks(profile, seed = seed).takeIf { it.isNotEmpty() }?.let { scoredRow("picks", "Picked for You Today", 2, it) }
        }

        // Because you watched … (two recent titles, rotating daily)
        val recent = history.map { it.meta }.distinctBy { it.id }.take(12)
        val becauseOf = recent.shuffled(Random(seed)).take(2)
        becauseOf.forEachIndexed { i, src ->
            jobs += async {
                moreLikeThis(src, exclude = seen, limit = 40).takeIf { it.isNotEmpty() }
                    ?.let { scoredRow("because-${src.id}", "Because you watched ${src.title}", if (i == 0) 5 else 9, it) }
            }
        }

        // Because you added … to My List
        myList.filter { m -> becauseOf.none { it.id == m.id } }.shuffled(Random(seed + 1)).firstOrNull()?.let { src ->
            jobs += async {
                moreLikeThis(src, exclude = seen + myList.map { it.id }, limit = 40).takeIf { it.isNotEmpty() }
                    ?.let { scoredRow("mylist-${src.id}", "Because you saved ${src.title}", 10, it) }
            }
        }

        // Today's genre spotlight, weighted toward your taste
        val spotlightChoices = (profile.topGenres(6) + DEFAULT_SPOTLIGHT).distinct()
            .filter { movieGenres.isEmpty() || it in movieGenres }
        val spotlight = spotlightChoices.getOrNull(rnd.nextInt(spotlightChoices.size.coerceAtLeast(1)))
        if (spotlight != null) {
            jobs += async {
                val items = (pool("movie", spotlight) + pool("series", spotlight)).distinctBy { it.id }
                    .filter { it.id !in seen }
                    .map { Scored(it, 0.5 * ((it.rating ?: 6.0) / 10.0) + 0.3 * profile.affinity(it) + 0.2 * Random(seed + it.id.hashCode()).nextDouble()) }
                    .sortedByDescending { it.score }
                    .take(40)
                items.takeIf { it.isNotEmpty() }?.let { scoredRow("spotlight", "Today's Spotlight: $spotlight", 6, it) }
            }
        }

        // Hidden gems: well rated but outside the most popular titles
        val gemGenre = profile.topGenres(3).ifEmpty { DEFAULT_SPOTLIGHT }.let { it[rnd.nextInt(it.size)] }
            .takeIf { movieGenres.isEmpty() || it in movieGenres }
        if (gemGenre != null) {
            jobs += async {
                val popular = pages("movie", "top", mapOf("genre" to gemGenre), 2).map { it.id }.toSet()
                val gems = pages("movie", "imdbRating", mapOf("genre" to gemGenre), 3, startSkip = 48)
                    .filter { it.id !in popular && it.id !in seen && (it.rating ?: 0.0) >= 7.2 }
                    .shuffled(Random(seed + 2))
                    .take(30)
                gems.takeIf { it.isNotEmpty() }?.let { plainRow("gems", "Hidden Gems: $gemGenre", 12, it) }
            }
        }

        // Best of a different year every day
        val thisYear = dateString(0).take(4).toInt()
        val years = yearOptions.mapNotNull { it.toIntOrNull() }.filter { it in 1975..(thisYear - 2) }
        if (years.isNotEmpty()) {
            val year = years[rnd.nextInt(years.size)]
            jobs += async {
                val best = pages("movie", "year", mapOf("genre" to year.toString()), 2)
                    .filter { (it.rating ?: 0.0) >= 6.3 }
                    .sortedByDescending { it.rating ?: 0.0 }
                    .take(30)
                best.takeIf { it.isNotEmpty() }?.let { plainRow("year", "Best of $year", 14, it) }
            }
        }

        // New this month (movies and series released in the last ~6 weeks)
        jobs += async {
            val cutoff = dateString(45)
            val today = dateString(0)
            val fresh = listOf("movie", "series").map { type ->
                async { pages(type, "year", mapOf("genre" to thisYear.toString()), 3) }
            }.awaitAll().flatten()
                .filter { m -> m.releasedDate?.let { it in cutoff..today } == true }
                .sortedByDescending { it.releasedDate }
                .take(40)
            fresh.takeIf { it.isNotEmpty() }?.let { plainRow("fresh", "New This Month", 8, it) }
        }

        // New episodes of series you've watched
        val seriesIds = history.filter { it.meta.type == "series" && it.meta.id.startsWith("tt") }
            .map { it.meta.id }.distinct().take(25)
        if (seriesIds.isNotEmpty()) {
            jobs += async {
                val recentCutoff = dateString(21)
                val today = dateString(0)
                val watchedVideos = history.map { it.videoId }.toSet()
                val metas = runCatching {
                    addons.catalogDetailed(cinemeta, "series", "last-videos", mapOf("lastVideosIds" to seriesIds.joinToString(",")))
                }.getOrDefault(emptyList())
                val entries = metas.mapNotNull { m ->
                    val latest = m.videos.filter { v -> v.released?.take(10)?.let { it <= today } == true }
                        .maxByOrNull { it.released.orEmpty() } ?: return@mapNotNull null
                    if (latest.released.orEmpty().take(10) < recentCutoff || latest.id in watchedVideos) return@mapNotNull null
                    m.copy(background = latest.thumbnail ?: m.background, videos = emptyList()) to
                        "New · S${latest.season} E${latest.episodeNumber}"
                }
                entries.takeIf { it.isNotEmpty() }?.let {
                    SuggestionRow(
                        "new-episodes", "New Episodes for You", it.map { e -> e.first }, 1,
                        subtitles = it.associate { e -> e.first.id to e.second },
                        landscape = true,
                    )
                }
            }
        }

        jobs.awaitAll().filterNotNull().map { row -> row.copy(items = row.items.distinctBy { it.id }) }.filter { it.items.isNotEmpty() }
    }

    companion object {
        private val DEFAULT_SPOTLIGHT = listOf(
            "Action", "Comedy", "Drama", "Thriller", "Sci-Fi", "Animation", "Horror",
            "Romance", "Crime", "Adventure", "Fantasy", "Mystery", "Documentary", "Family",
        )
    }
}
