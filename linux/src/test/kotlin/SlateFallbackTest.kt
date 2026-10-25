import com.sun.net.httpserver.HttpServer
import com.zemu.tv.ZemuApp
import com.zemu.tv.data.Meta
import com.zemu.tv.player.MpvSession
import com.zemu.tv.player.PlayCandidate
import java.io.File
import java.net.InetSocketAddress
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/** A seconds-long "video" from an addon link is an error slate: the player must move on to the next stream. */
class SlateFallbackTest {
    @Test
    fun skipsSlateVideos() {
        if (MpvSession.mpvPath() == null) return
        val clip = File(System.getProperty("zemu.testClip"))
        val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0).apply {
            createContext("/slate.mp4") { ex ->
                val bytes = clip.readBytes()
                ex.sendResponseHeaders(200, bytes.size.toLong())
                ex.responseBody.use { it.write(bytes) }
            }
            start()
        }
        var closed = false
        MpvSession.host = null
        MpvSession.onClosed = { closed = true }
        val c = ZemuApp.container
        val meta = Meta(id = "tt0000003", type = "movie", name = "Slate test")
        val slate = PlayCandidate("http://127.0.0.1:${server.address.port}/slate.mp4", "Expired link")
        MpvSession.start(c, meta, "tt0000003", null, listOf(slate, PlayCandidate(clip.path, "Real file")), emptyList(), 0)
        val deadline = System.currentTimeMillis() + 40_000
        while (!closed && System.currentTimeMillis() < deadline) Thread.sleep(200)
        server.stop(0)
        assertTrue(closed, "mpv didn't finish")
        Thread.sleep(1_000)
        assertEquals(clip.path, c.userStore.lastStreams.value[meta.id]?.url, "should have moved on to the real file")
    }
}
