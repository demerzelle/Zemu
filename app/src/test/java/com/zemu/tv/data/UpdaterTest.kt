package com.zemu.tv.data

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class UpdaterTest {
    @Test
    fun comparesVersionsNumerically() {
        assertTrue(Updater.isNewer("1.0.2", "1.0.1"))
        assertTrue(Updater.isNewer("1.0.10", "1.0.9"))
        assertTrue(Updater.isNewer("1.1", "1.0.9"))
        assertFalse(Updater.isNewer("1.0.1", "1.0.1"))
        assertFalse(Updater.isNewer("1.0", "1.0.0"))
        assertFalse(Updater.isNewer("1.0.0", "1.0.1"))
    }
}
