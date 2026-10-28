import com.zemu.tv.desktop.CursorAutoHide
import com.zemu.tv.desktop.FullScreen
import java.awt.EventQueue
import java.awt.Frame
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Full screen covers the whole display (top bar and dock included) and the window manager knows
 * it's full screen; there the pointer hides after 5 s still. Only on Linux with a display.
 */
class FullScreenTest {
    @Test
    fun coversDisplayAndHidesPointer() {
        if (!System.getProperty("os.name").startsWith("Linux") || System.getenv("DISPLAY") == null) return
        val frame = Frame("Zemu full screen test")
        EventQueue.invokeAndWait { frame.setSize(800, 500); frame.isVisible = true }
        Thread.sleep(800)
        FullScreen.window = frame
        CursorAutoHide.install()
        FullScreen.set(true)
        Thread.sleep(1_500)
        val screen = frame.graphicsConfiguration.bounds
        assertTrue(FullScreen.on, "not full screen")
        assertEquals(screen, frame.bounds, "should cover the whole display")
        val id = com.zemu.tv.desktop.x11WindowId(frame)?.let { java.lang.Long.toHexString(it) }
        val state = ProcessBuilder("xprop", "-id", "0x$id", "_NET_WM_STATE").start().inputStream.bufferedReader().readText()
        assertTrue("FULLSCREEN" in state, "window manager doesn't see it as full screen: $state")
        // Still for 6 s: the pointer goes blank.
        Thread.sleep(6_500)
        assertEquals("blank", frame.cursor.name, "pointer still showing after 5 s")
        FullScreen.set(false)
        Thread.sleep(1_000)
        assertTrue(!FullScreen.on && frame.bounds != screen, "didn't leave full screen")
        assertTrue(frame.cursor.name != "blank", "pointer stays hidden after leaving full screen")
        EventQueue.invokeAndWait { frame.dispose() }
    }
}
