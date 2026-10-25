import com.zemu.tv.ZemuApp
import com.zemu.tv.data.Meta
import com.zemu.tv.desktop.x11WindowId
import com.zemu.tv.player.MpvSession
import com.zemu.tv.player.PlayCandidate
import java.awt.Canvas
import java.awt.EventQueue
import java.awt.Frame
import java.io.File
import kotlin.test.Test
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

/**
 * mpv drawing inside a window of ours (as in Zemu's player area): the canvas has an X11 id, mpv
 * plays the clip in it to the end and progress is saved. Only on Linux with a display.
 */
class EmbeddedPlayerTest {
    @Test
    fun playsInsideOurWindow() {
        if (!System.getProperty("os.name").startsWith("Linux") || System.getenv("DISPLAY") == null || MpvSession.mpvPath() == null) return
        val clip = File(System.getProperty("zemu.testClip"))
        val canvas = Canvas().apply { background = java.awt.Color.BLACK }
        val frame = Frame("Zemu embed test")
        EventQueue.invokeAndWait { frame.add(canvas); frame.setSize(640, 360); frame.isVisible = true }
        Thread.sleep(500)
        val wid = x11WindowId(canvas)
        assertNotNull(wid, "no X11 window id for the canvas")
        var closed = false
        MpvSession.host = { s -> EventQueue.invokeLater { s.launch(wid) } }
        MpvSession.onClosed = { closed = true }
        val c = ZemuApp.container
        val meta = Meta(id = "tt0000002", type = "movie", name = "Embedded clip")
        MpvSession.start(c, meta, "tt0000002", null, listOf(PlayCandidate(clip.path, "Clip")), emptyList(), 0)
        // Halfway through: mpv's own window must be inside our canvas.
        Thread.sleep(3_000)
        val tree = runCatching {
            ProcessBuilder("xwininfo", "-children", "-id", wid.toString()).start().inputStream.bufferedReader().readText()
        }.getOrDefault("")
        assertTrue(Regex("""\d+ child""").containsMatchIn(tree) && "0 children" !in tree, "mpv isn't drawing inside the canvas:\n$tree")
        System.getProperty("zemu.shot")?.let { shot ->
            runCatching { ProcessBuilder("ffmpeg", "-loglevel", "error", "-y", "-f", "x11grab", "-window_id", wid.toString(), "-i", System.getenv("DISPLAY"), "-frames:v", "1", shot).start().waitFor() }
        }
        val deadline = System.currentTimeMillis() + 30_000
        while (!closed && System.currentTimeMillis() < deadline) Thread.sleep(200)
        EventQueue.invokeAndWait { frame.dispose() }
        assertTrue(closed, "mpv didn't finish; see ${File(c.appContext.cacheDir, "mpv/mpv.log")}")
        val log = File(c.appContext.cacheDir, "mpv/mpv.log").readText()
        assertTrue("--wid" !in log && "rror" !in log.lines().filter { "wid" in it }.joinToString(), log)
        Thread.sleep(1_000)
        assertTrue(meta.id in c.userStore.watched.value, "not marked watched")
    }
}
