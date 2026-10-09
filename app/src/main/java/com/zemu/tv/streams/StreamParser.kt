package com.zemu.tv.streams

import com.zemu.tv.data.Stream

/**
 * Extracts quality, language and cache information from a Stremio stream object.
 *
 * Debrid addons (Torrentio, Comet, MediaFusion, AIOStreams, TorBox, ...) don't share a schema for
 * this, so it's inferred from the `name`, `description`/`title` and `behaviorHints.filename` text,
 * the same text users read in Stremio.
 */
object StreamParser {
    private val I = RegexOption.IGNORE_CASE
    private const val B = "(?<![a-z0-9])"
    private const val E = "(?![a-z0-9])"
    /** Audio tags are often glued to channel counts ("DDP5.1"), so only letters end them. */
    private const val EA = "(?![a-z])"
    private fun rx(p: String, end: String = E) = Regex("$B(?:$p)$end", I)

    private val res2160 = rx("2160p|4k|uhd")
    private val res1440 = rx("1440p|2k")
    private val res1080 = rx("1080[pi]|fhd")
    private val res720 = rx("720p")
    private val resSd = rx("576p|480p|360p|sd")

    private val cam = rx("cam|camrip|hdcam|hd-?ts|telesync|telecine|hd-?tc|dvdscr|screener")
    private val remux = rx("remux|bdremux")
    private val bluray = rx("blu-?ray|bdrip|brrip|bd25|bd50|bdmv")
    private val webrip = rx("web-?rip")
    private val webdl = rx("web-?dl|web")
    private val hdtv = rx("hdtv|pdtv|dsr|tvrip")
    private val dvd = rx("dvd-?rip|dvd|dvd5|dvd9")

    private val dv = rx("dv|dovi|dolby[ .-]?vision")
    private val hdr10p = Regex("$B(?:hdr10\\+|hdr10plus|hdr10p)(?![a-z0-9])", I)
    private val hdr = Regex("$B(?:hdr(?:10)?)(?![a-z0-9+])", I)
    private val hlg = rx("hlg")

    private val av1 = rx("av1")
    private val hevc = rx("x265|h\\.?265|hevc")
    private val avc = rx("x264|h\\.?264|avc")
    private val tenBit = rx("10-?bit|hi10p")

    private val atmos = rx("atmos", EA)
    private val truehd = rx("true-?hd", EA)
    private val dtsHd = rx("dts-?hd(?:[ .-]?ma)?|dts-?x|dts-?ma", EA)
    private val dts = rx("dts", EA)
    private val ddp = rx("ddp|dd\\+|e-?ac-?3|dolby[ .]?digital[ .]?plus", EA)
    private val dd = rx("dd|ac-?3|dolby[ .]?digital", EA)
    private val aac = rx("aac", EA)
    private val flac = rx("flac", EA)
    private val opus = rx("opus", EA)
    private val channelsRx = Regex("(?<![0-9])([2578])[ .]([01])(?![0-9])(?!\\s*[gmkt]i?b)", I)

    private val sizeRx = Regex("([0-9]+(?:[.,][0-9]+)?)\\s*(tb|tib|gb|gib|mb|mib)(?![a-z])", I)
    private val seedersRx = Regex("👤\\s*([0-9]+)|seed(?:er)?s?\\s*:?\\s*([0-9]+)", I)
    private val groupRx = Regex("-([A-Za-z0-9]{2,15})(?:\\.[A-Za-z0-9]{2,4})?\\s*$")

    // Case-sensitive on purpose: "[RD+]", "[AD download]", "[TB⚡]".
    private val serviceTagRx = Regex("(?<![A-Za-z])(RD|AD|PM|DL|TB|OC|ED|PKP|EN)(?=\\s*(?:\\+|⚡|⏳|⬇|download|\\]|☁))")
    private val serviceNames = listOf(
        "real-?debrid" to "RD", "alldebrid" to "AD", "premiumize" to "PM", "debrid-?link" to "DL",
        "torbox" to "TB", "offcloud" to "OC", "easydebrid" to "ED", "pikpak" to "PKP", "easynews" to "EN",
    ).map { Regex(it.first, I) to it.second }

    private val positiveRx = Regex("\\+\\]|⚡|✅|(?<![a-z])(?:cached|instant)(?![a-z])", I)
    private val negativeNameRx = Regex("download|⏳|⬇|uncached|not[ _-]?cached", I)
    private val negativeDescRx = Regex("⏳|⬇|uncached|not[ _-]?cached", I)

    private val anchorRx = Regex("^(?:(?:19|20)\\d{2}|S\\d{1,2}(?:E\\d{1,3})?|\\d{3,4}P|4K)$")
    private val tokenSplit = Regex("[^A-Za-z0-9+]+")
    private val multiAudioRx = Regex("multi[ ._-]?audio|dual[ ._-]?audio", I)
    private val multiSubRx = Regex("multi[ ._-]?subs?", I)

    fun parse(stream: Stream, addonName: String, trustDirectLinks: Boolean = false): ParsedStream {
        val name = stream.name.orEmpty()
        val desc = (stream.description ?: stream.title).orEmpty()
        val filename = stream.behaviorHints?.filename.orEmpty()
        val all = "$name\n$desc\n$filename"
        val descLines = desc.lines().map { it.trim() }.filter { it.isNotEmpty() }

        val title = filename.ifBlank { descLines.firstOrNull().orEmpty() }.ifBlank { name.replace('\n', ' ') }

        val resolution = detectResolution(name) ?: detectResolution(all) ?: 0
        val source = when {
            cam.containsMatchIn(all) -> Source.CAM
            remux.containsMatchIn(all) -> Source.REMUX
            bluray.containsMatchIn(all) -> Source.BLURAY
            webrip.containsMatchIn(all) -> Source.WEBRIP
            webdl.containsMatchIn(all) -> Source.WEB_DL
            hdtv.containsMatchIn(all) -> Source.HDTV
            dvd.containsMatchIn(all) -> Source.DVD
            else -> Source.UNKNOWN
        }
        val hdrSet = buildSet {
            if (dv.containsMatchIn(all)) add(HdrFormat.DOLBY_VISION)
            if (hdr10p.containsMatchIn(all)) add(HdrFormat.HDR10_PLUS)
            if (hdr.containsMatchIn(all)) add(HdrFormat.HDR10)
            if (hlg.containsMatchIn(all)) add(HdrFormat.HLG)
        }
        val codec = when {
            av1.containsMatchIn(all) -> VideoCodec.AV1
            hevc.containsMatchIn(all) -> VideoCodec.HEVC
            avc.containsMatchIn(all) -> VideoCodec.AVC
            else -> VideoCodec.UNKNOWN
        }
        val audio = buildSet {
            if (atmos.containsMatchIn(all)) add(AudioCodec.ATMOS)
            if (truehd.containsMatchIn(all)) add(AudioCodec.TRUEHD)
            val hasDtsHd = dtsHd.containsMatchIn(all)
            if (hasDtsHd) add(AudioCodec.DTS_HD) else if (dts.containsMatchIn(all)) add(AudioCodec.DTS)
            val hasDdp = ddp.containsMatchIn(all)
            if (hasDdp) add(AudioCodec.DDP) else if (dd.containsMatchIn(all)) add(AudioCodec.DD)
            if (aac.containsMatchIn(all)) add(AudioCodec.AAC)
            if (flac.containsMatchIn(all)) add(AudioCodec.FLAC)
            if (opus.containsMatchIn(all)) add(AudioCodec.OPUS)
        }
        val channels = channelsRx.findAll("$desc\n$filename")
            .map { "${it.groupValues[1]}.${it.groupValues[2]}" }
            .maxByOrNull { it.replace(".", "").toInt() }

        val langs = detectLanguages(name, descLines, filename)
        val subsFromField = stream.subtitles.mapNotNull { Languages.normalize(it.lang) }

        val service = serviceTagRx.find(name)?.groupValues?.get(1)
            ?: serviceNames.firstOrNull { it.first.containsMatchIn("$name\n$desc") }?.second

        return ParsedStream(
            raw = stream,
            addonName = addonName,
            key = stream.url ?: stream.infoHash?.let { "$it:${stream.fileIdx ?: 0}" } ?: "$addonName|$name|$desc",
            title = title,
            resolution = resolution,
            source = source,
            hdr = hdrSet,
            codec = codec,
            tenBit = tenBit.containsMatchIn(all),
            audio = audio,
            channels = channels,
            audioLanguages = langs.audio,
            multiAudio = langs.multiAudio,
            subtitleLanguages = langs.subs + subsFromField,
            multiSubs = langs.multiSubs,
            sizeBytes = stream.behaviorHints?.videoSize?.takeIf { it > 0 } ?: parseSize("$desc\n$name"),
            seeders = seedersRx.find(desc)?.let { m -> (m.groupValues[1].ifEmpty { m.groupValues[2] }).toIntOrNull() },
            releaseGroup = groupRx.find(title)?.groupValues?.get(1),
            debridService = service,
            isCached = isCached(stream, name, desc, trustDirectLinks),
        )
    }

    /**
     * A stream counts as cached only if it has a direct HTTP(S) URL (not a raw torrent) and the
     * addon marked it as cached ("[RD+]", "⚡", "cached", ...) without any "download"/"⏳" marker.
     * Uncached debrid links would start a download on the debrid service instead of playing.
     */
    fun isCached(stream: Stream, name: String, desc: String, trustDirectLinks: Boolean): Boolean {
        val url = stream.url
        if (url.isNullOrBlank() || !(url.startsWith("https://") || url.startsWith("http://"))) return false
        if (negativeNameRx.containsMatchIn(name) || negativeDescRx.containsMatchIn(desc)) return false
        return positiveRx.containsMatchIn(name) || positiveRx.containsMatchIn(desc) || trustDirectLinks
    }

    private fun detectResolution(text: String): Int? = when {
        res2160.containsMatchIn(text) -> 2160
        res1440.containsMatchIn(text) -> 1440
        res1080.containsMatchIn(text) -> 1080
        res720.containsMatchIn(text) -> 720
        resSd.containsMatchIn(text) -> 480
        else -> null
    }

    fun parseSize(text: String): Long? {
        val idx = text.indexOf("💾")
        val m = (if (idx >= 0) sizeRx.find(text, idx) else null) ?: sizeRx.find(text) ?: return null
        val n = m.groupValues[1].replace(',', '.').toDoubleOrNull() ?: return null
        val mult = when (m.groupValues[2].lowercase()) {
            "tb", "tib" -> 1_099_511_627_776.0
            "gb", "gib" -> 1_073_741_824.0
            else -> 1_048_576.0
        }
        return (n * mult).toLong()
    }

    private data class Langs(val audio: Set<String>, val subs: Set<String>, val multiAudio: Boolean, val multiSubs: Boolean)

    private fun detectLanguages(name: String, descLines: List<String>, filename: String): Langs {
        val audio = linkedSetOf<String>()
        val subs = linkedSetOf<String>()
        var multiAudio = false
        var multiSubs = false

        for (line in descLines + name.lines()) {
            val flags = Languages.fromFlags(line)
            if (flags.isEmpty()) continue
            if (line.contains("sub", ignoreCase = true)) subs += flags else audio += flags
        }

        val lines = (descLines + filename).filter { it.isNotBlank() }
        for (line in lines) {
            if (multiAudioRx.containsMatchIn(line)) multiAudio = true
            if (multiSubRx.containsMatchIn(line)) multiSubs = true

            val tokens = line.split(tokenSplit).filter { it.isNotEmpty() }.map { it.uppercase() }
            val anchor = tokens.indexOfFirst { anchorRx.matches(it) }
            // Language tokens are only trusted after the year/season/resolution, past the title.
            if (anchor < 0) continue
            for (i in anchor + 1 until tokens.size) {
                val t = tokens[i]
                val next = tokens.getOrNull(i + 1)
                when {
                    t == "MULTI" || t == "DUAL" -> if (next == "SUB" || next == "SUBS") multiSubs = true else multiAudio = true
                    t in Languages.multiSubTokens -> multiSubs = true
                    t in Languages.subtitleTokens -> subs += Languages.subtitleTokens.getValue(t)
                    t in Languages.audioTokens -> {
                        val lang = Languages.audioTokens.getValue(t)
                        if (next != null && next in Languages.genericSubTokens) subs += lang else audio += lang
                    }
                }
            }
        }
        return Langs(audio, subs, multiAudio || audio.size > 1, multiSubs)
    }
}
