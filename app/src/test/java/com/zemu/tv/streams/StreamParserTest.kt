package com.zemu.tv.streams

import com.zemu.tv.data.Stream
import com.zemu.tv.data.StreamBehaviorHints
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class StreamParserTest {
    private fun parse(name: String, desc: String, url: String? = "https://cdn.example/file.mkv", filename: String? = null) =
        StreamParser.parse(Stream(name = name, description = desc, url = url, behaviorHints = StreamBehaviorHints(filename = filename)), "Test")

    @Test fun torrentioCachedStreamIsFullyParsed() {
        val s = parse(
            "[RD+] Torrentio\n4k DV | HDR",
            "Dune.Part.Two.2024.2160p.WEB-DL.DDP5.1.Atmos.DV.HDR.H.265-FLUX\n👤 120 💾 18.5 GB ⚙️ TorrentGalaxy\nMulti Audio / 🇬🇧 / 🇮🇹",
        )
        assertTrue(s.isCached)
        assertEquals(2160, s.resolution)
        assertEquals(Source.WEB_DL, s.source)
        assertTrue(HdrFormat.DOLBY_VISION in s.hdr && HdrFormat.HDR10 in s.hdr)
        assertEquals(VideoCodec.HEVC, s.codec)
        assertTrue(AudioCodec.DDP in s.audio && AudioCodec.ATMOS in s.audio)
        assertEquals("5.1", s.channels)
        assertEquals(18.5, s.sizeBytes!! / 1_073_741_824.0, 0.01)
        assertEquals(120, s.seeders)
        assertEquals("FLUX", s.releaseGroup)
        assertEquals(setOf("en", "it"), s.audioLanguages)
        assertTrue(s.multiAudio)
        assertEquals("RD", s.debridService)
    }

    @Test fun uncachedDebridDownloadIsRejected() {
        assertFalse(parse("[RD download] Torrentio\n1080p", "Movie.2023.1080p.WEBRip.x264").isCached)
        assertFalse(parse("[RD⬇️] Comet", "Movie.2023.1080p").isCached)
        assertFalse(parse("MediaFusion ⏳ RD", "Movie.2023.1080p").isCached)
    }

    @Test fun rawTorrentIsNeverCached() {
        val s = StreamParser.parse(Stream(name = "[RD+] Torrentio", infoHash = "abc", fileIdx = 0), "Test")
        assertFalse(s.isCached)
    }

    @Test fun cometAndOtherCachedMarkers() {
        assertTrue(parse("[RD⚡] Comet 4K", "Movie.2023.2160p.BluRay.REMUX").isCached)
        assertTrue(parse("[TB+] Torrentio", "Movie.2023.1080p").isCached)
        assertTrue(parse("AIOStreams", "⚡ Cached · Movie.2023.1080p").isCached)
    }

    @Test fun plainDirectLinkNeedsOptIn() {
        val stream = Stream(name = "My Server", description = "Movie 1080p", url = "https://example.com/a.mp4")
        assertFalse(StreamParser.parse(stream, "x").isCached)
        assertTrue(StreamParser.parse(stream, "x", trustDirectLinks = true).isCached)
    }

    @Test fun sizeIsNotMistakenForChannels() {
        val s = parse("[RD+] Torrentio\n1080p", "Movie.2020.1080p.BluRay.x264\n💾 5.1 GB")
        assertNull(s.channels)
        assertEquals(5.1, s.sizeBytes!! / 1_073_741_824.0, 0.01)
    }

    @Test fun subtitleAndLanguageTokens() {
        val s = parse("[RD+] Torrentio", "Movie.2020.1080p.BluRay.x264.ITA.ENG.ESub-GRP")
        assertEquals(setOf("it", "en"), s.audioLanguages)
        assertTrue("en" in s.subtitleLanguages)

        val subsOnly = parse("[RD+] Torrentio", "Movie.2020.1080p.WEB.ENG.SUBS-GRP")
        assertTrue("en" in subsOnly.subtitleLanguages)
        assertFalse("en" in subsOnly.audioLanguages)
    }

    @Test fun titleWordsBeforeTheYearAreNotLanguages() {
        val s = parse("[RD+] Torrentio", "Ben-Hur.1959.1080p.BluRay.x264-GRP")
        assertTrue(s.audioLanguages.isEmpty())
        val spanish = parse("[RD+] Torrentio", "Spanish.Affair.2014.1080p.WEB-DL")
        assertFalse("es" in spanish.audioLanguages)
    }

    @Test fun remuxTrueHdIsDetected() {
        val s = parse("[AD+] Torrentio\n4k", "Movie.2019.UHD.BluRay.2160p.REMUX.TrueHD.Atmos.7.1.HEVC-GRP\n💾 62.3 GB")
        assertEquals(Source.REMUX, s.source)
        assertTrue(AudioCodec.TRUEHD in s.audio)
        assertEquals("7.1", s.channels)
        assertEquals("AD", s.debridService)
    }

    @Test fun camIsDetected() {
        assertEquals(Source.CAM, parse("[RD+] Torrentio", "New.Movie.2025.HDCAM.x264").source)
    }
}
