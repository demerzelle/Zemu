package com.zemu.tv.desktop

import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.input.pointer.PointerEventType
import androidx.compose.ui.input.pointer.onPointerEvent
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.path
import androidx.compose.ui.unit.dp
import java.awt.AWTEvent
import java.awt.Component
import java.awt.Container
import java.awt.Cursor
import java.awt.EventQueue
import java.awt.Point
import java.awt.Toolkit
import java.awt.Window
import java.awt.image.BufferedImage

/**
 * True full screen: the window manager is asked for a full-screen window (_NET_WM_STATE_FULLSCREEN
 * on X11), which covers the top bar and dock, not just a maximized window. F11 / F, Alt+Enter and
 * the player's Full screen button toggle it.
 */
object FullScreen {
    @Volatile var window: Window? = null
    var on by mutableStateOf(false)
        private set

    fun toggle() = set(!on)

    fun set(value: Boolean) = EventQueue.invokeLater {
        val w = window ?: return@invokeLater
        val device = w.graphicsConfiguration?.device ?: return@invokeLater
        device.fullScreenWindow = if (value) w else null
        on = device.fullScreenWindow === w
        if (!on) CursorAutoHide.show()
    }

    /** Four corner brackets. */
    val icon: ImageVector = ImageVector.Builder("FullScreen", 24.dp, 24.dp, 24f, 24f).apply {
        path(stroke = SolidColor(Color.White), strokeLineWidth = 2.2f, strokeLineCap = StrokeCap.Round) {
            moveTo(4f, 9f); lineTo(4f, 4f); lineTo(9f, 4f)
            moveTo(15f, 4f); lineTo(20f, 4f); lineTo(20f, 9f)
            moveTo(20f, 15f); lineTo(20f, 20f); lineTo(15f, 20f)
            moveTo(9f, 20f); lineTo(4f, 20f); lineTo(4f, 15f)
        }
    }.build()
}

/**
 * In full screen and over a playing video, the mouse pointer disappears after 5 seconds without moving; anywhere, it
 * disappears as soon as the arrow keys or a controller are used, and stops hovering what it was on. It comes back on any
 * mouse move.
 */
object CursorAutoHide {
    private const val IDLE_MS = 5_000L
    private val blank: Cursor = Toolkit.getDefaultToolkit().createCustomCursor(BufferedImage(1, 1, BufferedImage.TYPE_INT_ARGB), Point(0, 0), "blank")
    @Volatile private var lastMove = System.currentTimeMillis()
    @Volatile private var hidden = false

    fun install() {
        Toolkit.getDefaultToolkit().addAWTEventListener(
            { e ->
                // Enter/exit aren't the mouse moving (hide() sends an exit of its own).
                if (e.id != java.awt.event.MouseEvent.MOUSE_EXITED && e.id != java.awt.event.MouseEvent.MOUSE_ENTERED) {
                    lastMove = System.currentTimeMillis(); if (hidden) show()
                }
            },
            AWTEvent.MOUSE_MOTION_EVENT_MASK or AWTEvent.MOUSE_EVENT_MASK or AWTEvent.MOUSE_WHEEL_EVENT_MASK,
        )
        // Arrow keys (and the controller, which sends them too) mean the mouse isn't in use.
        Toolkit.getDefaultToolkit().addAWTEventListener(
            { e -> if (e.id == java.awt.event.KeyEvent.KEY_PRESSED && (e as java.awt.event.KeyEvent).keyCode in arrows) hide() },
            AWTEvent.KEY_EVENT_MASK,
        )
        javax.swing.Timer(1_000) {
            if ((FullScreen.on || PlayerHost.session != null) && System.currentTimeMillis() - lastMove >= IDLE_MS) hide()
        }.start()
    }

    private val arrows = setOf(java.awt.event.KeyEvent.VK_UP, java.awt.event.KeyEvent.VK_DOWN, java.awt.event.KeyEvent.VK_LEFT, java.awt.event.KeyEvent.VK_RIGHT)

    fun hide() = EventQueue.invokeLater {
        if (hidden) return@invokeLater
        hidden = true
        Window.getWindows().filter { it.isShowing }.forEach { setDeep(it, blank); leave(it) }
    }

    fun show() = EventQueue.invokeLater {
        if (!hidden) return@invokeLater
        hidden = false
        Window.getWindows().filter { it.isShowing }.forEach { setDeep(it, null) }
    }

    // As if the pointer had left the window: whatever it rested on stops being hovered, and posters
    // scrolling under the hidden pointer don't light up. The next real move brings hover back.
    private fun leave(c: Component) {
        c.dispatchEvent(java.awt.event.MouseEvent(c, java.awt.event.MouseEvent.MOUSE_EXITED, System.currentTimeMillis(), 0, -1, -1, 0, false))
        if (c is Container) c.components.forEach(::leave)
    }

    // Compose sets the pointer on its inner components, so every level gets it.
    private fun setDeep(c: Component, cursor: Cursor?) {
        c.cursor = cursor
        if (c is Container) c.components.forEach { setDeep(it, cursor) }
    }
}

/**
 * Keeps the screen on and the computer awake while a video plays (mpv alone can't under GNOME on
 * Wayland). The inhibitor wraps `cat` on a pipe from Zemu, so it ends with Zemu even after a crash.
 */
object KeepAwake {
    private var process: Process? = null
    private val commands = listOf(
        listOf("gnome-session-inhibit", "--inhibit=idle", "--inhibit=suspend", "--app-id=zemu", "--reason=Playing video", "cat"),
        listOf("systemd-inhibit", "--what=idle:sleep", "--who=Zemu", "--why=Playing video", "cat"),
    )

    init { Runtime.getRuntime().addShutdownHook(Thread { set(false) }) }

    @Synchronized fun set(on: Boolean) {
        if (on == (process?.isAlive == true)) return
        if (!on) { process?.destroy(); process = null; return }
        process = commands.firstNotNullOfOrNull { runCatching { ProcessBuilder(it).redirectOutput(ProcessBuilder.Redirect.DISCARD).redirectError(ProcessBuilder.Redirect.DISCARD).start() }.getOrNull() }
    }
}

/**
 * Calls [action] once the mouse has rested on this for 3 seconds: cards then show their title in
 * the hero, as when moved to with the arrows, without moving focus (which would scroll the rows).
 */
@OptIn(androidx.compose.ui.ExperimentalComposeUiApi::class)
fun hoverHold(action: () -> Unit): Modifier = Modifier.composed {
    val latest by rememberUpdatedState(action)
    val scope = rememberCoroutineScope()
    val job = remember { arrayOfNulls<Job>(1) }
    onPointerEvent(PointerEventType.Enter) { job[0]?.cancel(); job[0] = scope.launch { delay(3_000); latest() } }
        .onPointerEvent(PointerEventType.Exit) { job[0]?.cancel() }
}
