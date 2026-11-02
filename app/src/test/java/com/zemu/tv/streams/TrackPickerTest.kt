package com.zemu.tv.streams

import com.zemu.tv.streams.TrackPicker.Track
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class TrackPickerTest {
    private val en = listOf("en")

    @Test fun audioPrefersTaggedLanguageOverDefault() {
        val tracks = listOf(Track("ja", "Japanese", isDefault = true), Track("en", "English"))
        assertEquals(1, TrackPicker.audio(tracks, en, current = 0))
    }

    @Test fun audioReadsUntaggedTitles() {
        val tracks = listOf(Track("und", "JPN 2.0"), Track(null, "ENG 5.1"))
        assertEquals(1, TrackPicker.audio(tracks, en, current = 0))
        assertEquals(0, TrackPicker.audio(tracks, listOf("ja"), current = 1))
    }

    @Test fun audioSkipsCommentaryAndLeavesUnknownAlone() {
        val tracks = listOf(Track("en", "Director's Commentary"), Track("en", "English"))
        assertEquals(1, TrackPicker.audio(tracks, en, current = 0))
        assertNull(TrackPicker.audio(listOf(Track("fr", "French")), en, current = 0))
    }

    @Test fun animeAlwaysGetsFullSubsNotSignsAndSongs() {
        val subs = listOf(Track("en", "Signs & Songs"), Track("en", "Full Subtitles"))
        assertEquals(1, TrackPicker.subtitle(subs, en, "always", "ja", anime = true, preferSdh = false))
    }

    @Test fun autoModeOnlyShowsSubsWhenAudioIsForeign() {
        val subs = listOf(Track("en", "English"), Track("en", "English (Forced)", forced = true))
        assertEquals(0, TrackPicker.subtitle(subs, en, "auto", "ja", anime = false, preferSdh = false))
        assertEquals(1, TrackPicker.subtitle(subs, en, "auto", "en", anime = false, preferSdh = false))
        assertEquals(-1, TrackPicker.subtitle(subs.take(1), en, "auto", "en", anime = false, preferSdh = false))
    }

    @Test fun untaggedAudioCountsAsYoursExceptInAnime() {
        val subs = listOf(Track("en", "English"))
        assertEquals(-1, TrackPicker.subtitle(subs, en, "auto", null, anime = false, preferSdh = false))
        assertEquals(0, TrackPicker.subtitle(subs, en, "auto", null, anime = true, preferSdh = false))
    }

    @Test fun offIsOffAndSdhPreferenceCounts() {
        val subs = listOf(Track("en", "English"), Track("en", "English SDH", sdh = true))
        assertEquals(-1, TrackPicker.subtitle(subs, en, "off", "ja", anime = false, preferSdh = false))
        assertEquals(1, TrackPicker.subtitle(subs, en, "always", "en", anime = false, preferSdh = true))
    }

    @Test fun showChoiceGoesFirst() {
        assertEquals(Triple(listOf("ja", "en"), en, "off"), TrackPicker.withShowChoice(en, en, "auto", "ja|off"))
        assertEquals(Triple(en, listOf("es", "en"), "always"), TrackPicker.withShowChoice(en, en, "auto", "|es"))
        assertEquals(Triple(en, en, "auto"), TrackPicker.withShowChoice(en, en, "auto", null))
    }
}
