package com.zemu.tv.desktop

import android.widget.Toast
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.awt.ComposeWindow
import androidx.compose.ui.awt.SwingPanel
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEvent
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.isAltPressed
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.type
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Window
import androidx.compose.ui.window.WindowPosition
import androidx.compose.ui.window.rememberWindowState
import com.zemu.tv.ZemuApp
import com.zemu.tv.player.MpvSession
import com.zemu.tv.player.PlayerScreen
import com.zemu.tv.ui.theme.ZemuTheme
import com.zemu.tv.ui.theme.resolvedColors
import java.awt.Canvas
import java.awt.Component
import java.awt.EventQueue
import java.awt.event.ComponentAdapter
import java.awt.event.ComponentEvent
import java.awt.event.WindowAdapter
import java.awt.event.WindowEvent

/** The video playing inside Zemu's window, if any. */
object PlayerHost {
    var session by mutableStateOf<MpvSession?>(null)

    fun install() {
        MpvSession.host = { s -> EventQueue.invokeLater { session = s } }
        MpvSession.onClosed = { s -> EventQueue.invokeLater { if (session === s) session = null } }
    }
}

/**
 * An X11 window's id for an AWT component (the jar's manifest opens these JDK internals). Null
 * when not on X11, and mpv then plays in its own window.
 */
internal fun x11WindowId(c: Component): Long? = runCatching {
    val accessor = Class.forName("sun.awt.AWTAccessor").getMethod("getComponentAccessor").invoke(null)
    // Through the interface: the accessor's own class is private to java.awt.
    val peer = Class.forName("sun.awt.AWTAccessor\$ComponentAccessor").getMethod("getPeer", Component::class.java).invoke(accessor, c)
    Class.forName("sun.awt.X11.XBaseWindow").getMethod("getWindow").apply { isAccessible = true }.invoke(peer) as Long
}.getOrNull()?.takeIf { it != 0L }

/** Fills the main window with the playing video: a native canvas that mpv draws into. */
@Composable
fun PlayerSurface() {
    val s = PlayerHost.session ?: return
    key(s) {
        SwingPanel(
            background = Color.Black,
            modifier = Modifier.fillMaxSize(),
            factory = {
                object : Canvas() {
                    // Once the canvas has its native window, start mpv inside it.
                    override fun addNotify() {
                        super.addNotify()
                        EventQueue.invokeLater { s.launch(x11WindowId(this)) }
                    }
                }.apply {
                    background = java.awt.Color.BLACK
                    // Keys stay with Zemu's player screen.
                    isFocusable = false
                }
            },
        )
    }
}

/**
 * Keys for the player that the shared (TV) player screen doesn't have: Space pauses, F / F11 /
 * Alt+Enter full screen, M mute, N next episode, J or S subtitles, A audio track.
 */
private fun desktopPlayerKeys(s: MpvSession, e: KeyEvent): Boolean {
    if (e.type != KeyEventType.KeyDown) return false
    when {
        e.key == Key.Spacebar -> s.togglePlay()
        e.key == Key.F || e.key == Key.F11 || (e.key == Key.Enter && e.isAltPressed) -> FullScreen.toggle()
        e.key == Key.M -> s.toggleMute()
        e.key == Key.N && s.upNext != null -> s.playNextNow()
        e.key == Key.J || e.key == Key.S -> Toast.makeText(null, "Subtitles: ${s.cycleSubtitles()}", Toast.LENGTH_SHORT).show()
        e.key == Key.A -> Toast.makeText(null, "Audio: ${s.cycleAudio()}", Toast.LENGTH_SHORT).show()
        else -> return false
    }
    return true
}

/**
 * Zemu's own player screen (the same one as on Android TV) in a transparent window laid exactly
 * over the main window, where mpv draws the video: native video can't have Compose drawn on top of
 * it inside one window, but a second, see-through window can. It isn't owned by the main window:
 * GNOME won't make an owned window full screen, and any other window stays out from under the top
 * bar and dock, cutting the player's edges off.
 */
@Composable
fun PlayerOverlay(owner: ComposeWindow) {
    val s = PlayerHost.session ?: return
    key(s) {
        val state = rememberWindowState()
        var ownerShown by remember { mutableStateOf(true) }
        Window(
            onCloseRequest = { s.stop() },
            state = state,
            visible = ownerShown,
            title = "Zemu player",
            undecorated = true,
            transparent = true,
            // Resizable so it can follow the main window (it has no frame to drag anyway).
            resizable = true,
            onPreviewKeyEvent = { e -> desktopPlayerKeys(s, e) },
            // Back with nothing open on the player screen closes the player.
            onKeyEvent = { e ->
                if (e.type == KeyEventType.KeyDown && (e.key == Key.Escape || e.key == Key.Backspace)) { s.stop(); true } else false
            },
        ) {
            // Always exactly over the main window's content, also when it moves, resizes or goes full
            // screen. Through the window's Compose state, which would otherwise put it back.
            val wmFullScreen = remember { booleanArrayOf(false) }
            DisposableEffect(owner) {
                fun sync() {
                    val pane = owner.contentPane
                    if (!pane.isShowing) return
                    // By size: Java's idea of the position is off by the title bar it no longer has.
                    val full = pane.size == owner.graphicsConfiguration.bounds.size
                    if (full != wmFullScreen[0]) { wmFullScreen[0] = full; setWmFullScreen(window, full) }
                    if (full) return
                    val at = pane.locationOnScreen
                    state.position = WindowPosition(at.x.dp, at.y.dp)
                    state.size = DpSize(pane.width.dp, pane.height.dp)
                    // GNOME ignores a size set only through the state once the window is mapped.
                    EventQueue.invokeLater { window.setBounds(at.x, at.y, pane.width, pane.height) }
                }
                val follow = object : ComponentAdapter() {
                    override fun componentMoved(e: ComponentEvent) = sync()
                    override fun componentResized(e: ComponentEvent) = sync()
                }
                // Not owned, so it's kept on top of the main window by hand, and minimized with it.
                val stack = object : WindowAdapter() {
                    override fun windowActivated(e: WindowEvent) = window.toFront()
                    override fun windowIconified(e: WindowEvent) { ownerShown = false }
                    override fun windowDeiconified(e: WindowEvent) { ownerShown = true; EventQueue.invokeLater { window.toFront(); sync() } }
                }
                owner.addComponentListener(follow)
                owner.addWindowListener(stack)
                sync()
                onDispose { owner.removeComponentListener(follow); owner.removeWindowListener(stack) }
            }
            LaunchedEffect(Unit) {
                // Again once it's on screen: the window manager places a new window after the first request.
                repeat(4) {
                    kotlinx.coroutines.delay(250)
                    val pane = owner.contentPane
                    if (pane.isShowing && !wmFullScreen[0]) pane.locationOnScreen.let { at -> window.setBounds(at.x, at.y, pane.width, pane.height) }
                }
                window.toFront()
                window.requestFocus()
            }
            val settings by ZemuApp.container.userStore.settings.collectAsState()
            // The player is always dark, whatever the app's light/dark setting.
            ZemuTheme(settings.resolvedColors(light = false), settings.uiZoom, settings.font, settings.fontSize) {
                Box(Modifier.fillMaxSize()) {
                    PlayerScreen(s)
                    ToastHost()
                }
            }
        }
    }
}

/** Asks the window manager to make [w] full screen or not (JDK internals, opened by the jar's manifest). */
internal fun setWmFullScreen(w: java.awt.Window, value: Boolean) = runCatching {
    Class.forName("sun.awt.X11GraphicsDevice")
        .getDeclaredMethod(if (value) "enterFullScreenExclusive" else "exitFullScreenExclusive", java.awt.Window::class.java)
        .apply { isAccessible = true }.invoke(null, w)
}.onFailure { System.err.println("Zemu: player full screen: $it") }
