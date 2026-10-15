package com.zemu.tv.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class CategoriesTest {
    @Test fun pagesAlwaysGetServiceAndStudioRows() {
        for (page in listOf("home", "movie", "series")) {
            val rows = Categories.tmdbRows(page, seed = 7, taste = listOf("Horror"))
            assertTrue(page, rows.count { it.service != null } >= 3)
            assertTrue(page, rows.any { it.studio != null })
            assertEquals(page, rows.size, rows.map { it.key }.toSet().size)
            if (page != "home") assertTrue(rows.all { it.type == page })
        }
    }

    @Test fun rotationChangesWithSeed() =
        assertNotEquals(Categories.tmdbRows("movie", 1, emptyList()).map { it.key }, Categories.tmdbRows("movie", 2, emptyList()).map { it.key })

    @Test fun genreIdsMatchCinemetaNames() {
        assertEquals(878, Tmdb.genreId("movie", "Sci-Fi"))
        assertEquals(10765, Tmdb.genreId("series", "Sci-Fi"))
        assertEquals(10759, Tmdb.genreId("series", "Action"))
    }
}
