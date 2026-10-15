package com.zemu.tv

import com.zemu.tv.data.Ratings
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Test

class RatingsTest {
    @Test fun moviesAndTvShareLevels() {
        assertEquals(0, Ratings.level("G"))
        assertEquals(0, Ratings.level("TV-Y"))
        assertEquals(1, Ratings.level(" tv-y7 "))
        assertEquals(1, Ratings.level("PG"))
        assertEquals(2, Ratings.level("PG-13"))
        assertEquals(2, Ratings.level("TV-14"))
        assertEquals(3, Ratings.level("TV-MA"))
        assertEquals(4, Ratings.level("NC-17"))
    }

    @Test fun unratedIsUnknown() {
        assertNull(Ratings.level(""))
        assertNull(Ratings.level("NR"))
        assertNull(Ratings.kitsuLevel(""))
        assertEquals(4, Ratings.kitsuLevel("R18"))
    }

    @Test fun codesHashDifferently() {
        assertEquals(Ratings.hash("1234"), Ratings.hash("1234"))
        assertNotEquals(Ratings.hash("1234"), Ratings.hash("1235"))
    }
}
