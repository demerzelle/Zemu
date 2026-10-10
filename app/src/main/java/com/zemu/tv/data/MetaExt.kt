package com.zemu.tv.data

val Meta.title: String get() = name.orEmpty()
val Meta.imdbId: String get() = if (id.startsWith("tt")) id.substringBefore(':') else imdbIdField?.takeIf { it.startsWith("tt") } ?: id.substringBefore(':')
val Meta.isImdb: Boolean get() = id.startsWith("tt")
val Meta.rating: Double? get() = imdbRating?.toDoubleOrNull()?.takeIf { it > 0 }
val Meta.year: Int? get() = releaseInfo?.let { Regex("\\d{4}").find(it)?.value?.toIntOrNull() }

val Meta.runtimeLabel: String?
    get() {
        val raw = runtime ?: return null
        if (raw.contains('h')) return raw
        val mins = Regex("\\d+").find(raw)?.value?.toIntOrNull() ?: return raw
        return if (mins >= 60) "${mins / 60}h ${mins % 60}m" else "${mins}m"
    }

fun Meta.posterUrl(): String? =
    poster ?: if (isImdb) "https://images.metahub.space/poster/medium/$imdbId/img" else null

fun Meta.backdropUrl(): String? =
    background ?: if (isImdb) "https://images.metahub.space/background/medium/$imdbId/img" else posterUrl()

fun Meta.logoUrl(): String? =
    logo ?: if (isImdb) "https://images.metahub.space/logo/medium/$imdbId/img" else null

/** Small copy for persistence (history / My List) without the episode list. */
fun Meta.slim(): Meta = copy(videos = emptyList(), trailers = trailers.take(1), trailerStreams = trailerStreams.take(1), cast = cast.take(6))

/** A YouTube trailer with a display name. */
data class TrailerRef(val id: String, val title: String)

/**
 * The title's official trailers, in the addon's order: named "trailer" (not teasers, clips or
 * featurettes) or typed as one. Falls back to whatever single trailer the addon gives.
 */
val Meta.officialTrailers: List<TrailerRef>
    get() {
        val named = trailerStreams.mapNotNull { t ->
            val id = t.ytId?.takeIf { it.isNotBlank() } ?: return@mapNotNull null
            val title = t.title.orEmpty()
            if (title.isBlank() || ("trailer" in title.lowercase() && "teaser" !in title.lowercase())) TrailerRef(id, title) else null
        }
        val typed = trailers.mapNotNull { t ->
            val id = t.source?.takeIf { it.isNotBlank() } ?: return@mapNotNull null
            if (t.type == null || t.type.equals("Trailer", ignoreCase = true)) TrailerRef(id, "") else null
        }
        val all = (named + typed).distinctBy { it.id }.ifEmpty { trailerId?.let { listOf(TrailerRef(it, "")) }.orEmpty() }
        return all.mapIndexed { i, t -> t.copy(title = t.title.ifBlank { if (all.size > 1) "Trailer ${i + 1}" else "Trailer" }) }
    }

/** YouTube id of the first trailer, if any. */
val Meta.trailerId: String?
    get() = trailers.firstOrNull { !it.source.isNullOrBlank() }?.source
        ?: trailerStreams.firstOrNull { !it.ytId.isNullOrBlank() }?.ytId

/** "yyyy-MM-dd" from the ISO release timestamp. */
val Meta.releasedDate: String? get() = released?.take(10)?.takeIf { it.length == 10 }


/** Video id to probe when checking whether a title has cached streams. */
val Meta.probeVideoId: String get() = if (type == "series" && isImdb && !id.contains(':')) "$id:1:1" else id
