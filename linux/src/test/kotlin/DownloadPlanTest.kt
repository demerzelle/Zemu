import com.zemu.tv.data.Downloads
import com.zemu.tv.data.Meta
import com.zemu.tv.data.Video
import com.zemu.tv.desktop.DownloadPrompt
import kotlinx.serialization.json.Json
import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals

class DownloadPlanTest {
    private val show = Meta(
        id = "tt9", type = "series", name = "Some: Show!",
        videos = listOf(
            Video(id = "tt9:2:1", season = 2, episode = 1, released = "2020-01-01"),
            Video(id = "tt9:1:2", season = 1, episode = 2, released = "2019-01-08"),
            Video(id = "tt9:1:1", season = 1, episode = 1, released = "2019-01-01"),
            Video(id = "tt9:0:1", season = 0, episode = 1, released = "2019-06-01"),
            Video(id = "tt9:2:2", season = 2, episode = 2, released = "2999-01-01"),
        ),
    )

    @Test
    fun picksReleasedEpisodesInOrder() {
        assertEquals(listOf("tt9:1:1", "tt9:1:2"), DownloadPrompt.episodes(show, 1).map { it.id })
        // All seasons: no specials, nothing unreleased.
        assertEquals(listOf("tt9:1:1", "tt9:1:2", "tt9:2:1"), DownloadPrompt.episodes(show, null).map { it.id })
        assertEquals(listOf("tt9:0:1"), DownloadPrompt.episodes(show, 0).map { it.id })
    }

    @Test
    fun filesSeriesBySeason() {
        val d = Downloads(object : android.content.Context() {}, Json)
        val root = File("/x")
        assertEquals(File("/x/Some Show/Season 2"), d.targetFor(show, "tt9:2:1", root))
        assertEquals(File("/x/Some Show/Specials"), d.targetFor(show, "tt9:0:1", root))
        assertEquals(root, d.targetFor(Meta(id = "tt1", type = "movie", name = "Film"), "tt1", root))
    }
}
