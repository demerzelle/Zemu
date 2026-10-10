package com.zemu.tv.data

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

// Shapes follow the Stremio addon protocol (github.com/Stremio/stremio-addon-sdk/tree/master/docs/api).

@Serializable
data class Meta(
    val id: String = "",
    val type: String = "movie",
    /** TMDB id (Cinemeta) — used for cast data and skip-intro lookups. */
    @SerialName("moviedb_id") @Serializable(with = LenientStringSerializer::class) val tmdbId: String? = null,
    /** IMDb id when [id] is another scheme (e.g. Kitsu metas). */
    @SerialName("imdb_id") @Serializable(with = LenientStringSerializer::class) val imdbIdField: String? = null,
    @Serializable(with = LenientStringSerializer::class) val name: String? = null,
    @Serializable(with = LenientStringSerializer::class) val poster: String? = null,
    @Serializable(with = LenientStringSerializer::class) val background: String? = null,
    @Serializable(with = LenientStringSerializer::class) val logo: String? = null,
    @Serializable(with = LenientStringSerializer::class) val description: String? = null,
    @Serializable(with = LenientStringSerializer::class) val releaseInfo: String? = null,
    @Serializable(with = LenientStringSerializer::class) val imdbRating: String? = null,
    @Serializable(with = LenientStringListSerializer::class) val genres: List<String> = emptyList(),
    @Serializable(with = LenientStringSerializer::class) val runtime: String? = null,
    @Serializable(with = LenientStringListSerializer::class) val cast: List<String> = emptyList(),
    @Serializable(with = LenientStringListSerializer::class) val director: List<String> = emptyList(),
    @Serializable(with = LenientStringSerializer::class) val released: String? = null,
    val videos: List<Video> = emptyList(),
    val trailers: List<Trailer> = emptyList(),
    val trailerStreams: List<TrailerStream> = emptyList(),
)

@Serializable
data class TrailerStream(
    @Serializable(with = LenientStringSerializer::class) val title: String? = null,
    @Serializable(with = LenientStringSerializer::class) val ytId: String? = null,
)

@Serializable
data class Video(
    val id: String = "",
    @Serializable(with = LenientStringSerializer::class) val title: String? = null,
    @Serializable(with = LenientStringSerializer::class) val name: String? = null,
    @Serializable(with = LenientIntSerializer::class) val season: Int? = null,
    @Serializable(with = LenientIntSerializer::class) val episode: Int? = null,
    @Serializable(with = LenientIntSerializer::class) val number: Int? = null,
    @Serializable(with = LenientStringSerializer::class) val released: String? = null,
    @Serializable(with = LenientStringSerializer::class) val thumbnail: String? = null,
    @Serializable(with = LenientStringSerializer::class) val overview: String? = null,
    @Serializable(with = LenientStringSerializer::class) val description: String? = null,
) {
    val episodeNumber: Int get() = episode ?: number ?: 0
    val displayTitle: String get() = title ?: name ?: "Episode $episodeNumber"
    val synopsis: String? get() = overview ?: description
}

@Serializable
data class Trailer(
    @Serializable(with = LenientStringSerializer::class) val source: String? = null,
    @Serializable(with = LenientStringSerializer::class) val type: String? = null,
)

@Serializable
data class Stream(
    @Serializable(with = LenientStringSerializer::class) val name: String? = null,
    @Serializable(with = LenientStringSerializer::class) val title: String? = null,
    @Serializable(with = LenientStringSerializer::class) val description: String? = null,
    val url: String? = null,
    val infoHash: String? = null,
    @Serializable(with = LenientIntSerializer::class) val fileIdx: Int? = null,
    val externalUrl: String? = null,
    val ytId: String? = null,
    val behaviorHints: StreamBehaviorHints? = null,
    val subtitles: List<SubtitleTrack> = emptyList(),
)

@Serializable
data class StreamBehaviorHints(
    val bingeGroup: String? = null,
    @Serializable(with = LenientLongSerializer::class) val videoSize: Long? = null,
    @Serializable(with = LenientStringSerializer::class) val filename: String? = null,
    val proxyHeaders: ProxyHeaders? = null,
)

@Serializable
data class ProxyHeaders(val request: Map<String, String> = emptyMap())

@Serializable
data class SubtitleTrack(
    @Serializable(with = LenientStringSerializer::class) val id: String? = null,
    val url: String = "",
    @Serializable(with = LenientStringSerializer::class) val lang: String = "",
)

@Serializable data class CatalogResponse(val metas: List<Meta> = emptyList())
@Serializable data class CatalogDetailedResponse(val metasDetailed: List<Meta> = emptyList())
@Serializable data class MetaResponse(val meta: Meta? = null)
@Serializable data class StreamResponse(val streams: List<Stream> = emptyList())
@Serializable data class SubtitlesResponse(val subtitles: List<SubtitleTrack> = emptyList())

// ---- Persisted user data ----

@Serializable
data class InstalledAddon(val transportUrl: String, val manifestJson: String)

@Serializable
data class AppSettings(
    val audioLanguages: List<String> = listOf("en"),
    val subtitleLanguages: List<String> = listOf("en"),
    val autoSubtitles: Boolean = false,
    /** Count plain HTTP streams with no debrid markers as cached (off = strict). */
    val trustDirectLinks: Boolean = false,
    /** 0 = no limit. */
    val maxSizeGb: Int = 0,
    val useExternalPlayer: Boolean = false,
    /** TMDB v3 API key or v4 read token; enables cast photos, studios and filmographies. */
    val tmdbApiKey: String = "",
    val skipIntroButton: Boolean = true,
    /** Muted trailer replaces the hero backdrop after a title stays focused. */
    val heroTrailers: Boolean = true,
    val heroTrailerSound: Boolean = false,
    /** Decode Dolby Vision as its HDR10/HEVC base layer. Turned on automatically if DV fails to decode. */
    val avoidDolbyVision: Boolean = false,
    val preferSoftwareDecoders: Boolean = false,
    /** A [com.zemu.tv.ui.theme.ThemePreset] name, or "CUSTOM". */
    val theme: String = "CLASSIC",
    val customAccent: Long = 0xFFE50914,
    val customBackground: Long = 0xFF0A0A0E,
    /** A [com.zemu.tv.ui.theme.DynamicTheme] name. */
    val dynamicTheme: String = "NONE",
    /** Light background with dark text. */
    val lightMode: Boolean = false,
    /** Translucent "frosted glass" panels and buttons. */
    val glassStyle: Boolean = false,
    /** Manifest id of the addon preferred for title details and the Movies/Series pages ("" = automatic). */
    val metaProvider: String = "",
    // Player
    /** "FIT", "ZOOM", "STRETCH" or "CENTER". */
    val aspectMode: String = "FIT",
    /** Short vibrations on phones when changing pages and starting a video. */
    val vibration: Boolean = true,
    /** Selecting a title or an episode starts playing right away instead of opening its page. */
    val instantPlay: Boolean = false,
    val autoplayNext: Boolean = true,
    /** When a movie (or a series' last episode) ends, count down to a similar title. */
    val autoplaySimilar: Boolean = true,
    val autoplayCountdownSec: Int = 10,
    val stillWatchingPrompt: Boolean = true,
    /** Ask after this many episodes autoplay in a row without touching the remote. */
    val stillWatchingEpisodes: Int = 3,
    // Subtitle appearance
    val subtitleScale: Float = 1f,
    val subtitleColor: Long = 0xFFFFFFFF,
    /** 0 = none, 1 = translucent box, 2 = solid box. */
    val subtitleBackground: Int = 0,
    /** 0 = none, 1 = outline, 2 = drop shadow. */
    val subtitleEdge: Int = 1,
    /** Distance from the bottom, as a fraction of the screen height. */
    val subtitleBottom: Float = 0.08f,
)

/** A screen's row arrangement: [order] is the row keys as last arranged; [favorites] are pinned to the top. */
@Serializable
data class RowPrefs(val order: List<String> = emptyList(), val favorites: List<String> = emptyList())

/** Identifies a played stream: [key] matches the exact release, [bingeGroup] the release group across episodes. */
@Serializable
data class LastStream(val key: String, val bingeGroup: String? = null)

@Serializable
data class WatchEntry(
    val meta: Meta,
    val videoId: String,
    val label: String? = null,
    val positionMs: Long = 0,
    val durationMs: Long = 0,
    val updatedAt: Long = 0,
) {
    val progress: Float get() = if (durationMs > 0) positionMs.toFloat() / durationMs else 0f
}
