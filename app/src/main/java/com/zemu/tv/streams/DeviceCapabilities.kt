package com.zemu.tv.streams

import android.content.Context
import android.hardware.display.DisplayManager
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.media.MediaCodecList
import android.view.Display
import kotlin.math.min

/** What this TV can decode and display, used to rank streams ("Best for this TV"). */
data class DeviceCapabilities(
    val maxResolution: Int,
    val hevc: Boolean,
    val av1: Boolean,
    val dolbyVision: Boolean,
    val hdr10: Boolean,
    val hdr10Plus: Boolean,
    val playableAudio: Set<AudioCodec>,
) {
    fun canPlay(a: AudioCodec) = a in playableAudio

    fun summary(): List<Pair<String, Boolean>> = listOf(
        "4K output" to (maxResolution >= 2160),
        "HEVC / H.265" to hevc,
        "AV1" to av1,
        "HDR10" to hdr10,
        "HDR10+" to hdr10Plus,
        "Dolby Vision" to dolbyVision,
        "Dolby Digital+ / Atmos" to canPlay(AudioCodec.DDP),
        "Dolby TrueHD" to canPlay(AudioCodec.TRUEHD),
        "DTS" to canPlay(AudioCodec.DTS),
        "DTS-HD" to canPlay(AudioCodec.DTS_HD),
    )

    companion object {
        // android.view.Display.HdrCapabilities constants (inlined to avoid API-level lint noise).
        private const val HDR_TYPE_DOLBY_VISION = 1
        private const val HDR_TYPE_HDR10 = 2
        private const val HDR_TYPE_HDR10_PLUS = 4

        // android.media.AudioFormat encodings reported by HDMI sinks.
        private const val ENC_AC3 = 5
        private const val ENC_E_AC3 = 6
        private const val ENC_DTS = 7
        private const val ENC_DTS_HD = 8
        private const val ENC_DOLBY_TRUEHD = 14
        private const val ENC_E_AC3_JOC = 18

        @Suppress("DEPRECATION")
        fun detect(context: Context): DeviceCapabilities {
            val decoders = runCatching {
                MediaCodecList(MediaCodecList.ALL_CODECS).codecInfos
                    .filter { !it.isEncoder }
                    .flatMap { it.supportedTypes.map(String::lowercase) }
                    .toSet()
            }.getOrDefault(emptySet())

            val display = (context.getSystemService(Context.DISPLAY_SERVICE) as? DisplayManager)
                ?.getDisplay(Display.DEFAULT_DISPLAY)
            val maxHeight = display?.supportedModes?.maxOfOrNull { min(it.physicalWidth, it.physicalHeight) } ?: 1080
            val hdrTypes = runCatching { display?.hdrCapabilities?.supportedHdrTypes?.toSet() }.getOrNull().orEmpty()

            val passthrough = runCatching {
                (context.getSystemService(Context.AUDIO_SERVICE) as AudioManager)
                    .getDevices(AudioManager.GET_DEVICES_OUTPUTS)
                    .filter { it.type == AudioDeviceInfo.TYPE_HDMI || it.type == AudioDeviceInfo.TYPE_HDMI_ARC || it.type == 29 /* HDMI eARC */ }
                    .flatMap { it.encodings.toList() }
                    .toSet()
            }.getOrDefault(emptySet())

            val audio = buildSet {
                add(AudioCodec.AAC); add(AudioCodec.FLAC); add(AudioCodec.OPUS); add(AudioCodec.ATMOS)
                if ("audio/ac3" in decoders || ENC_AC3 in passthrough) add(AudioCodec.DD)
                if ("audio/eac3" in decoders || "audio/eac3-joc" in decoders || ENC_E_AC3 in passthrough || ENC_E_AC3_JOC in passthrough) add(AudioCodec.DDP)
                if ("audio/true-hd" in decoders || ENC_DOLBY_TRUEHD in passthrough) add(AudioCodec.TRUEHD)
                if ("audio/vnd.dts" in decoders || ENC_DTS in passthrough) add(AudioCodec.DTS)
                if ("audio/vnd.dts.hd" in decoders || ENC_DTS_HD in passthrough) add(AudioCodec.DTS_HD)
            }

            return DeviceCapabilities(
                maxResolution = when {
                    maxHeight >= 2000 -> 2160
                    maxHeight >= 1400 -> 1440
                    maxHeight >= 1000 -> 1080
                    else -> 720
                },
                hevc = "video/hevc" in decoders,
                av1 = "video/av01" in decoders,
                dolbyVision = "video/dolby-vision" in decoders && HDR_TYPE_DOLBY_VISION in hdrTypes,
                hdr10 = HDR_TYPE_HDR10 in hdrTypes,
                hdr10Plus = HDR_TYPE_HDR10_PLUS in hdrTypes,
                playableAudio = audio,
            )
        }
    }
}
