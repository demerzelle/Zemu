package com.zemu.tv.desktop

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.awt.SwingPanel
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEvent
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.type
import com.zemu.tv.desktop.Gamepad.Button
import com.zemu.tv.player.MpvSession
import java.awt.Canvas
import java.awt.Component
import java.awt.EventQueue

/** The video playing inside Zemu's window, if any. */
object PlayerHost {
    var session by mutableStateOf<MpvSession?>(null)

    fun install() {
        MpvSession.host = { s -> EventQueue.invokeLater { session = s } }
        MpvSession.onClosed = { s -> EventQueue.invokeLater { if (session === s) session = null } }
    }

    /**
     * Keys while a video plays: Space pauses, Enter pauses or skips the intro / starts the next
     * episode when offered, arrows seek (left/right) or change the volume (up/down), Esc /
     * Backspace / Q close, N next episode, J/S subtitles, A/# audio track, M mute.
     * F and F11 are handled by the window (full screen). Returns true when the key was used.
     */
    fun key(e: KeyEvent): Boolean {
        if (session == null) return false
        if (e.type != KeyEventType.KeyDown) return true
        when (e.key) {
            Key.Spacebar -> MpvSession.command("cycle", "pause")
            Key.Enter, Key.NumPadEnter -> MpvSession.gamepad(Button.A)
            Key.DirectionLeft -> MpvSession.gamepad(Button.LEFT)
            Key.DirectionRight -> MpvSession.gamepad(Button.RIGHT)
            Key.DirectionUp -> MpvSession.command("add", "volume", 5)
            Key.DirectionDown -> MpvSession.command("add", "volume", -5)
            Key.Escape, Key.Backspace, Key.Q -> MpvSession.gamepad(Button.B)
            Key.N -> MpvSession.gamepad(Button.MENU)
            Key.J, Key.S -> MpvSession.gamepad(Button.X)
            Key.A -> MpvSession.gamepad(Button.Y)
            Key.M -> MpvSession.command("cycle", "mute")
            else -> return false
        }
        return true
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

/** Fills the window with the playing video: a native canvas that mpv draws into. */
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
                    // Keys stay with Zemu, which forwards them to mpv.
                    isFocusable = false
                }
            },
        )
    }
}
