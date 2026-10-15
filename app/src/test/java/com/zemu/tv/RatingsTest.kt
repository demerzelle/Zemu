package com.zemu.tv

import com.zemu.tv.data.Ratings
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class RatingsTest {
    private val allowed = setOf("G", "PG", "TV-Y7", Ratings.UNRATED)

    @Test fun normalizes() {
        assertEquals("TV-Y7", Ratings.normalize(" tv-y7-fv "))
        assertEquals("NC-17", Ratings.normalize("R18"))
    }

    @Test fun onlyKidsTitlesWithAllowedRatings() {
        assertTrue(Ratings.allows(allowed, "PG", kidsGenre = true))
        assertTrue(Ratings.allows(allowed, "tv-y7", kidsGenre = true))
        assertFalse(Ratings.allows(allowed, "PG-13", kidsGenre = true))
        // A G-rated documentary isn't a kids' title.
        assertFalse(Ratings.allows(allowed, "G", kidsGenre = false))
        assertTrue(Ratings.allows(allowed, "", kidsGenre = true))
        assertFalse(Ratings.allows(allowed - Ratings.UNRATED, "", kidsGenre = true))
    }

    @Test fun realRatingsOnly() {
        assertTrue(Ratings.isRating("PG-13"))
        assertTrue(Ratings.isRating("TV-MA"))
        assertFalse(Ratings.isRating("N/A"))
        assertFalse(Ratings.isRating("Not Rated"))
    }

    @Test fun kidsGenres() {
        assertTrue(Ratings.isKidsGenre(listOf("Animation", "Family")))
        assertTrue(Ratings.isKidsGenre(listOf("kids")))
        assertFalse(Ratings.isKidsGenre(listOf("Animation", "Comedy")))
    }

    @Test fun codesHashDifferently() {
        assertEquals(Ratings.hash("1234"), Ratings.hash("1234"))
        assertNotEquals(Ratings.hash("1234"), Ratings.hash("1235"))
    }
}
