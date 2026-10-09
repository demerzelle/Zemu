package com.zemu.tv.streams

import com.zemu.tv.data.AppSettings
import kotlin.math.min

enum class SortOption(val label: String) {
    BEST("Best match"), RESOLUTION("Highest quality"), SIZE_DESC("Largest size"),
    SIZE_ASC("Smallest size"), SEEDERS("Most seeded"),
}

enum class SizeBucket(val label: String, val minGb: Double, val maxGb: Double) {
    UNDER_2("Under 2 GB", 0.0, 2.0),
    GB_2_5("2 – 5 GB", 2.0, 5.0),
    GB_5_10("5 – 10 GB", 5.0, 10.0),
    GB_10_20("10 – 20 GB", 10.0, 20.0),
    GB_20_40("20 – 40 GB", 20.0, 40.0),
    OVER_40("40 GB +", 40.0, Double.MAX_VALUE);

    companion object {
        fun of(bytes: Long?): SizeBucket? {
            val gb = (bytes ?: return null) / 1_073_741_824.0
            return entries.firstOrNull { gb >= it.minGb && gb < it.maxGb }
        }
    }
}

enum class FacetKind(val label: String) {
    QUALITY("Quality"), AUDIO_LANG("Audio language"), SUB_LANG("Subtitles"), SIZE("Size"),
    HDR("HDR"), CODEC("Video codec"), AUDIO("Audio format"), CHANNELS("Channels"),
    SOURCE("Source"), SERVICE("Debrid service"), ADDON("Addon"),
}

data class FilterState(
    val sort: SortOption = SortOption.BEST,
    val selected: Map<FacetKind, Set<String>> = emptyMap(),
    /** Only streams this TV can decode and display natively. */
    val deviceFriendlyOnly: Boolean = false,
    val hideCam: Boolean = true,
) {
    val activeCount: Int get() = selected.values.count { it.isNotEmpty() } + (if (deviceFriendlyOnly) 1 else 0)

    fun toggle(kind: FacetKind, value: String): FilterState {
        val cur = selected[kind].orEmpty()
        return copy(selected = selected + (kind to if (value in cur) cur - value else cur + value))
    }

    fun clear(kind: FacetKind) = copy(selected = selected - kind)
}

data class FacetOption(val value: String, val label: String, val count: Int)

data class RankedStream(
    val stream: ParsedStream,
    val score: Double,
    val recommended: Boolean,
    val deviceFriendly: Boolean,
)

object StreamFilter {
    const val MULTI = "multi"
    const val UNSPECIFIED = "und"
    const val NONE = "none"
    const val UNKNOWN = "?"

    private val qualityOrder = listOf("4K", "1440p", "1080p", "720p", "SD", "Unknown")
    private const val GB = 1_073_741_824L

    fun values(kind: FacetKind, s: ParsedStream, externalSubs: Set<String>): Set<String> = when (kind) {
        FacetKind.QUALITY -> setOf(s.resolutionLabel)
        FacetKind.AUDIO_LANG -> buildSet {
            addAll(s.audioLanguages)
            if (s.multiAudio) add(MULTI)
            if (isEmpty()) add(UNSPECIFIED)
        }
        FacetKind.SUB_LANG -> buildSet {
            addAll(s.subtitleLanguages)
            if (s.multiSubs) add(MULTI)
            addAll(externalSubs)
            if (isEmpty()) add(NONE)
        }
        FacetKind.SIZE -> setOf(SizeBucket.of(s.sizeBytes)?.name ?: UNKNOWN)
        FacetKind.HDR -> if (s.hdr.isEmpty()) setOf("SDR") else s.hdr.map { it.label }.toSet()
        FacetKind.CODEC -> setOf(s.codec.label)
        FacetKind.AUDIO -> if (s.audio.isEmpty()) setOf(UNKNOWN) else s.audio.map { it.label }.toSet()
        FacetKind.CHANNELS -> setOf(s.channels ?: UNKNOWN)
        FacetKind.SOURCE -> setOf(s.source.label)
        FacetKind.SERVICE -> setOf(s.debridService ?: "Direct")
        FacetKind.ADDON -> setOf(s.addonName)
    }

    fun label(kind: FacetKind, value: String, externalSubs: Set<String> = emptySet()): String = when {
        value == MULTI -> "Multi-language"
        value == UNSPECIFIED -> "Not specified"
        value == NONE -> "None listed"
        value == UNKNOWN -> "Unknown"
        kind == FacetKind.AUDIO_LANG -> Languages.displayName(value)
        kind == FacetKind.SUB_LANG ->
            Languages.displayName(value) + if (value in externalSubs) "  (incl. external)" else ""
        kind == FacetKind.SIZE -> runCatching { SizeBucket.valueOf(value).label }.getOrDefault(value)
        else -> value
    }

    private fun matches(s: ParsedStream, state: FilterState, ext: Set<String>, exclude: FacetKind? = null) =
        state.selected.all { (kind, sel) -> kind == exclude || sel.isEmpty() || values(kind, s, ext).any { it in sel } }

    private fun base(all: List<ParsedStream>, state: FilterState, caps: DeviceCapabilities, settings: AppSettings) =
        all.filter { s ->
            !(state.hideCam && s.source == Source.CAM) &&
                (!state.deviceFriendlyOnly || isDeviceFriendly(s, caps)) &&
                (settings.maxSizeGb <= 0 || (s.sizeBytes ?: 0) <= settings.maxSizeGb * GB)
        }

    fun apply(
        all: List<ParsedStream>,
        state: FilterState,
        caps: DeviceCapabilities,
        settings: AppSettings,
        externalSubs: Set<String>,
    ): List<RankedStream> {
        val ranked = base(all, state, caps, settings)
            .filter { matches(it, state, externalSubs) }
            .map { RankedStream(it, score(it, caps, settings, externalSubs), false, isDeviceFriendly(it, caps)) }
        val bestKey = ranked.maxByOrNull { it.score }?.stream?.key
        val sorted = when (state.sort) {
            SortOption.BEST -> ranked.sortedByDescending { it.score }
            SortOption.RESOLUTION -> ranked.sortedWith(compareByDescending<RankedStream> { it.stream.resolution }.thenByDescending { it.score })
            SortOption.SIZE_DESC -> ranked.sortedByDescending { it.stream.sizeBytes ?: 0L }
            SortOption.SIZE_ASC -> ranked.sortedBy { it.stream.sizeBytes ?: Long.MAX_VALUE }
            SortOption.SEEDERS -> ranked.sortedByDescending { it.stream.seeders ?: -1 }
        }
        return sorted.map { if (it.stream.key == bestKey) it.copy(recommended = true) else it }
    }

    /** Options for each facet with counts that respect every *other* active facet. */
    fun facets(
        all: List<ParsedStream>,
        state: FilterState,
        caps: DeviceCapabilities,
        settings: AppSettings,
        externalSubs: Set<String>,
    ): Map<FacetKind, List<FacetOption>> {
        val base = base(all, state, caps, settings)
        return FacetKind.entries.associateWith { kind ->
            val pool = base.filter { matches(it, state, externalSubs, exclude = kind) }
            val counts = pool.flatMap { values(kind, it, externalSubs) }.groupingBy { it }.eachCount().toMutableMap()
            state.selected[kind].orEmpty().forEach { counts.putIfAbsent(it, 0) }
            val options = counts.map { (v, n) -> FacetOption(v, label(kind, v, externalSubs), n) }
            when (kind) {
                FacetKind.QUALITY -> options.sortedBy { qualityOrder.indexOf(it.value).let { i -> if (i < 0) 99 else i } }
                FacetKind.SIZE -> options.sortedBy { runCatching { SizeBucket.valueOf(it.value).ordinal }.getOrDefault(99) }
                else -> options.sortedWith(compareByDescending<FacetOption> { it.count }.thenBy { it.label })
            }
        }
    }

    fun isDeviceFriendly(s: ParsedStream, caps: DeviceCapabilities): Boolean {
        val codecOk = when (s.codec) {
            VideoCodec.AV1 -> caps.av1
            VideoCodec.HEVC -> caps.hevc
            else -> true
        }
        val dvOnly = s.hdr == setOf(HdrFormat.DOLBY_VISION)
        val hdrOk = when {
            s.hdr.isEmpty() -> true
            dvOnly -> caps.dolbyVision
            else -> caps.hdr10 || caps.dolbyVision
        }
        val audioOk = s.audio.isEmpty() || s.audio.any { caps.canPlay(it) }
        return codecOk && hdrOk && audioOk
    }

    /** Heuristic "how good will this look and sound on this TV, in my languages" score. */
    fun score(s: ParsedStream, caps: DeviceCapabilities, settings: AppSettings, externalSubs: Set<String>): Double {
        var sc = 0.0
        val effective = min(s.resolution, caps.maxResolution)
        sc += when {
            effective >= 2160 -> 40.0
            effective >= 1440 -> 33.0
            effective >= 1080 -> 30.0
            effective >= 720 -> 18.0
            effective > 0 -> 8.0
            else -> 12.0
        }
        if (s.resolution > caps.maxResolution) sc -= 6 // bandwidth this TV can't show
        sc += s.source.rank * 4

        if (HdrFormat.DOLBY_VISION in s.hdr) {
            val dvUsable = caps.dolbyVision && !settings.avoidDolbyVision
            sc += if (dvUsable) 10 else if (s.hdr.size == 1) -18 else 0
            // Disc-based DV is usually dual-layer profile 7, which most Android TV decoders can't handle.
            if (s.source == Source.REMUX || s.source == Source.BLURAY) sc -= 8
        }
        if (HdrFormat.HDR10_PLUS in s.hdr && caps.hdr10Plus) sc += 3
        if (HdrFormat.HDR10 in s.hdr || HdrFormat.HDR10_PLUS in s.hdr) sc += if (caps.hdr10) 7 else -3

        when (s.codec) {
            VideoCodec.AV1 -> sc += if (caps.av1) 3 else -35
            VideoCodec.HEVC -> sc += if (caps.hevc) 2 else -35
            else -> {}
        }
        if (s.audio.isNotEmpty()) {
            val playable = s.audio.filter { caps.canPlay(it) }
            sc += if (playable.isEmpty()) -20.0 else playable.maxOf { it.rank } * 1.5
        }

        val prefAudio = settings.audioLanguages.toSet()
        sc += when {
            s.audioLanguages.any { it in prefAudio } -> 25.0
            s.multiAudio -> 12.0
            s.audioLanguages.isEmpty() -> 6.0 // usually the original language
            else -> -15.0
        }
        val prefSubs = settings.subtitleLanguages.toSet()
        if (prefSubs.isNotEmpty() && (s.subtitleLanguages + externalSubs).any { it in prefSubs }) sc += 4

        sc += min(s.seeders ?: 0, 100) / 25.0
        val gb = (s.sizeBytes ?: 0) / 1_073_741_824.0
        if (gb > 0 && gb < 0.4 && s.resolution >= 1080) sc -= 10 // suspiciously small
        return sc
    }
}
