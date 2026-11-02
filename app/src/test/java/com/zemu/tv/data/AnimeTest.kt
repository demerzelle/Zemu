package com.zemu.tv.data

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AnimeTest {
    @Test fun asianAnimationFromAnyCatalogIsAnime() {
        assertTrue(Meta(id = "tt2560140", type = "series", genres = listOf("Animation", "Action"), country = "Japan").isAnime)
        assertTrue(Meta(id = "tt21209876", type = "series", genres = listOf("Animation"), country = "Japan, South Korea").isAnime)
        assertTrue(Meta(id = "tt0000001", type = "movie", genres = listOf("Animation"), country = "China").isAnime)
        assertTrue(Meta(id = "kitsu:1", type = "series").isAnime)
    }

    @Test fun otherAnimationAndAsianLiveActionAreNot() {
        assertFalse(Meta(id = "tt0417299", type = "series", genres = listOf("Animation"), country = "United States").isAnime)
        assertFalse(Meta(id = "tt10919420", type = "series", genres = listOf("Drama", "Thriller"), country = "South Korea").isAnime)
        assertFalse(Meta(id = "tt0903747", type = "series", genres = listOf("Crime"), country = "United States").isAnime)
        // Saved before 1.1: no country yet.
        assertFalse(Meta(id = "tt2560140", type = "series", genres = listOf("Animation")).isAnime)
    }
}
