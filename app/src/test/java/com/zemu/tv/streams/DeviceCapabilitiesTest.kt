package com.zemu.tv.streams

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

class DeviceCapabilitiesTest {
    private val detected = DeviceCapabilities(
        maxResolution = 1080, hevc = true, av1 = false, dolbyVision = false, hdr10 = true, hdr10Plus = false,
        playableAudio = setOf(AudioCodec.AAC, AudioCodec.DD, AudioCodec.DDP),
    )

    @Test fun noOverridesKeepsDetected() = assertSame(detected, detected.withOverrides(emptyMap(), 0))

    @Test fun overridesApplyPerFormat() {
        val c = detected.withOverrides(mapOf("dv" to true, "hevc" to false, AudioCodec.DTS.name to true, AudioCodec.DDP.name to false), 2160)
        assertEquals(2160, c.maxResolution)
        assertTrue(c.dolbyVision)
        assertFalse(c.hevc)
        assertTrue(c.hdr10) // untouched keeps detected
        assertTrue(c.canPlay(AudioCodec.DTS))
        assertFalse(c.canPlay(AudioCodec.DDP))
        assertTrue(c.canPlay(AudioCodec.AAC))
    }
}
