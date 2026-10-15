package com.zemu.tv.ui.home

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class NextEpisodeLabelTest {
    @Test fun imdbEpisode() = assertEquals("Next · S2 E5", nextEpisodeLabel("tt0944947:2:4"))
    @Test fun kitsuEpisode() = assertEquals("Next · Episode 13", nextEpisodeLabel("kitsu:1376:12"))
    @Test fun movieId() = assertNull(nextEpisodeLabel("tt0111161"))
}
