package com.zemu.tv.streams


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

    /** Each format by its stable key ([KEYS]) to whether it's supported. */
    fun supports(key: String): Boolean = when (key) {
        "hevc" -> hevc
        "av1" -> av1
        "hdr10" -> hdr10
        "hdr10plus" -> hdr10Plus
        "dv" -> dolbyVision
        else -> AudioCodec.entries.firstOrNull { it.name == key }?.let(::canPlay) ?: false
    }

    /** The user's choices in Settings → This TV, on top of what was detected. */
    fun withOverrides(o: Map<String, Boolean>, maxRes: Int): DeviceCapabilities {
        if (o.isEmpty() && maxRes == 0) return this
        fun pick(key: String) = o[key] ?: supports(key)
        return DeviceCapabilities(
            maxResolution = maxRes.takeIf { it > 0 } ?: maxResolution,
            hevc = pick("hevc"),
            av1 = pick("av1"),
            dolbyVision = pick("dv"),
            hdr10 = pick("hdr10"),
            hdr10Plus = pick("hdr10plus"),
            playableAudio = AudioCodec.entries.filter { pick(it.name) }.toSet(),
        )
    }

    companion object {
        /** Settings → This TV: key to label, in display order. */
        val KEYS: List<Pair<String, String>> = listOf(
            "hevc" to "HEVC / H.265",
            "av1" to "AV1",
            "hdr10" to "HDR10",
            "hdr10plus" to "HDR10+",
            "dv" to "Dolby Vision",
            AudioCodec.DD.name to "Dolby Digital",
            AudioCodec.DDP.name to "Dolby Digital+ / Atmos",
            AudioCodec.TRUEHD.name to "Dolby TrueHD",
            AudioCodec.DTS.name to "DTS",
            AudioCodec.DTS_HD.name to "DTS-HD",
        )

        /**
         * mpv decodes every common codec in software and passes nothing through by default, so the
         * limits that matter on a slow PC are the screen size and whether the GPU can decode HEVC/AV1.
         * Settings → This TV can override any of these.
         */
        fun detect(): DeviceCapabilities {
            val screen = runCatching {
                java.awt.GraphicsEnvironment.getLocalGraphicsEnvironment().screenDevices.maxOf { it.displayMode.height }
            }.getOrDefault(1080)
            val vaapi = runCatching {
                val p = ProcessBuilder("vainfo").redirectErrorStream(true).start()
                p.inputStream.bufferedReader().readText().also { p.waitFor() }
            }.getOrDefault("")
            return DeviceCapabilities(
                maxResolution = when {
                    screen >= 2000 -> 2160
                    screen >= 1400 -> 1440
                    screen >= 1000 -> 1080
                    else -> 720
                },
                // Without hardware decoding, HEVC/AV1 at 1080p+ stutter on older CPUs; rank them lower.
                hevc = "VAProfileHEVC" in vaapi,
                av1 = "VAProfileAV1" in vaapi,
                dolbyVision = false,
                hdr10 = false,
                hdr10Plus = false,
                playableAudio = AudioCodec.entries.toSet(),
            )
        }
    }
}
