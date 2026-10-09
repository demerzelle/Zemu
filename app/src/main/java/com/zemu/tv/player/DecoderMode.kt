package com.zemu.tv.player

import androidx.annotation.OptIn
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.mediacodec.MediaCodecInfo
import androidx.media3.exoplayer.mediacodec.MediaCodecSelector

/** How decoders are chosen. The player escalates through these when a stream fails to decode. */
data class DecoderMode(
    /** Hide Dolby Vision decoders so DV files play their HEVC (HDR10/SDR) base layer. */
    val avoidDolbyVision: Boolean = false,
    /** Try software video decoders before hardware ones. */
    val softwareVideo: Boolean = false,
    /** Use the FFmpeg audio decoder before the platform's. */
    val ffmpegAudio: Boolean = false,
) {
    fun describe(): String = listOfNotNull(
        "Dolby Vision as HDR10".takeIf { avoidDolbyVision },
        "software video decoding".takeIf { softwareVideo },
        "FFmpeg audio".takeIf { ffmpegAudio },
    ).joinToString(", ").ifEmpty { "default decoders" }
}

@OptIn(UnstableApi::class)
class FallbackCodecSelector(private val mode: DecoderMode) : MediaCodecSelector {
    override fun getDecoderInfos(
        mimeType: String,
        requiresSecureDecoder: Boolean,
        requiresTunnelingDecoder: Boolean,
    ): List<MediaCodecInfo> {
        // Returning nothing for DV makes the video renderer use the HEVC/AVC alternative decoders.
        if (mode.avoidDolbyVision && mimeType == MimeTypes.VIDEO_DOLBY_VISION) return emptyList()
        val infos = MediaCodecSelector.DEFAULT.getDecoderInfos(mimeType, requiresSecureDecoder, requiresTunnelingDecoder)
        return if (mode.softwareVideo && MimeTypes.isVideo(mimeType)) infos.sortedByDescending { it.softwareOnly } else infos
    }
}
