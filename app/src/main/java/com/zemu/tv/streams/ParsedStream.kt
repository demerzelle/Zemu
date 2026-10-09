package com.zemu.tv.streams

import com.zemu.tv.data.Stream

enum class Source(val label: String, val rank: Int) {
    REMUX("Remux", 6), BLURAY("BluRay", 5), WEB_DL("WEB-DL", 4), WEBRIP("WEBRip", 3),
    HDTV("HDTV", 2), DVD("DVD", 1), CAM("CAM", -10), UNKNOWN("Unknown", 0),
}

enum class HdrFormat(val label: String) {
    DOLBY_VISION("Dolby Vision"), HDR10_PLUS("HDR10+"), HDR10("HDR10"), HLG("HLG"),
}

enum class VideoCodec(val label: String) { AV1("AV1"), HEVC("HEVC"), AVC("H.264"), UNKNOWN("Unknown") }

enum class AudioCodec(val label: String, val rank: Int) {
    ATMOS("Atmos", 6), TRUEHD("TrueHD", 5), DTS_HD("DTS-HD", 5), DTS("DTS", 3),
    DDP("DD+", 3), DD("DD", 2), FLAC("FLAC", 3), AAC("AAC", 1), OPUS("Opus", 1),
}

data class ParsedStream(
    val raw: Stream,
    val addonName: String,
    val key: String,
    /** Best human-readable release name. */
    val title: String,
    /** 2160, 1440, 1080, 720, 480, or 0 when unknown. */
    val resolution: Int,
    val source: Source,
    val hdr: Set<HdrFormat>,
    val codec: VideoCodec,
    val tenBit: Boolean,
    val audio: Set<AudioCodec>,
    val channels: String?,
    val audioLanguages: Set<String>,
    val multiAudio: Boolean,
    val subtitleLanguages: Set<String>,
    val multiSubs: Boolean,
    val sizeBytes: Long?,
    val seeders: Int?,
    val releaseGroup: String?,
    /** Short debrid tag, e.g. "RD", or null for direct links. */
    val debridService: String?,
    val isCached: Boolean,
) {
    val resolutionLabel: String
        get() = when (resolution) {
            2160 -> "4K"; 1440 -> "1440p"; 1080 -> "1080p"; 720 -> "720p"; 480 -> "SD"; else -> "Unknown"
        }

    val sizeLabel: String? get() = sizeBytes?.let { formatSize(it) }

    companion object {
        fun formatSize(bytes: Long): String {
            val gb = bytes / 1_073_741_824.0
            return if (gb >= 1) String.format("%.1f GB", gb) else String.format("%.0f MB", bytes / 1_048_576.0)
        }
    }
}
