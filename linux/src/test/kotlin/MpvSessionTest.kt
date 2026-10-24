import com.zemu.tv.ZemuApp
import com.zemu.tv.data.Meta
import com.zemu.tv.player.MpvSession
import com.zemu.tv.player.PlayCandidate
import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Plays a 6-second clip in the real mpv: the first stream is broken so the player must fall back,
 * then the clip runs to the end, mpv closes and Zemu has saved the progress and the working file.
 * Skipped when mpv isn't installed.
 */
class MpvSessionTest {
    @Test
    fun fallsBackPlaysAndSavesProgress() {
        if (MpvSession.mpvPath() == null) return
        val clip = File(System.getProperty("zemu.testClip"))
        val c = ZemuApp.container
        var closed = false
        MpvSession.onClosed = { closed = true }
        val meta = Meta(id = "tt0000001", type = "movie", name = "Clip")
        MpvSession.start(c, meta, "tt0000001", null, listOf(PlayCandidate("http://127.0.0.1:9/missing.mkv", "Broken"), PlayCandidate(clip.path, "Clip")), emptyList(), 2_000)
        val deadline = System.currentTimeMillis() + 40_000
        while (!closed && System.currentTimeMillis() < deadline) Thread.sleep(200)
        assertTrue(closed, "mpv didn't finish; see ${File(c.appContext.cacheDir, "mpv/mpv.log")}")
        Thread.sleep(1_000)
        val entry = c.userStore.history.value.firstOrNull { it.meta.id == meta.id }
        assertTrue(entry != null && entry.durationMs in 5_000..7_000, "no progress saved: ${c.userStore.history.value}")
        assertTrue(meta.id in c.userStore.watched.value, "not marked watched: $entry")
        assertEquals(clip.path, c.userStore.lastStreams.value[meta.id]?.url)
    }
}
