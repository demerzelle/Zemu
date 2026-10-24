import com.zemu.tv.data.DownloadItem
import com.zemu.tv.data.Downloads
import com.zemu.tv.data.Meta
import com.sun.net.httpserver.HttpServer
import kotlinx.serialization.json.Json
import java.io.File
import java.net.InetSocketAddress
import kotlin.random.Random
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Downloads a file from a local server that drops the first connection halfway, so resume is exercised. */
class DownloadsTest {
    @Test
    fun downloadsAndResumes() {
        val data = Random(1).nextBytes(3_000_000)
        var requests = 0
        val ranges = mutableListOf<String?>()
        val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0).apply {
            createContext("/video.mkv") { ex ->
                requests++
                val range = ex.requestHeaders.getFirst("Range").also { ranges += it }
                val start = range?.removePrefix("bytes=")?.substringBefore('-')?.toInt() ?: 0
                if (start > 0) ex.responseHeaders.add("Content-Range", "bytes $start-${data.size - 1}/${data.size}")
                ex.sendResponseHeaders(if (start > 0) 206 else 200, (data.size - start).toLong())
                ex.responseBody.use { out ->
                    // First request: send half, then cut the connection.
                    val end = if (requests == 1) data.size / 2 else data.size
                    out.write(data, start, end - start)
                    if (requests == 1) { out.flush(); ex.close(); return@createContext }
                }
            }
            start()
        }
        val home = java.nio.file.Files.createTempDirectory("zemu-dl").toFile()
        System.setProperty("user.home", home.path)
        val ctx = object : android.content.Context() {}
        val downloads = Downloads(ctx, Json { ignoreUnknownKeys = true })
        val url = "http://127.0.0.1:${server.address.port}/video.mkv"
        assertNull(downloads.start(Meta(id = "tt1", type = "movie", name = "Test"), "tt1", null, url, mapOf("X-Test" to "1"), "video.mkv", data.size.toLong()))
        val item: DownloadItem = downloads.items.value.single()
        val deadline = System.currentTimeMillis() + 30_000
        while (!downloads.state(item).done && System.currentTimeMillis() < deadline) {
            check(!downloads.state(item).failed) { "failed: ${downloads.state(item).error}" }
            Thread.sleep(100)
        }
        server.stop(0)
        assertTrue(downloads.state(item).done, "download did not finish")
        assertContentEquals(data, File(item.path).readBytes())
        assertTrue(ranges.drop(1).any { it != null && it != "bytes=0-" }, "second request should resume with a Range: $ranges")
        downloads.remove(item)
        assertTrue(!File(item.path).exists())
    }
}
