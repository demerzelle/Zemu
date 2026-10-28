package com.zemu.tv.player

import java.awt.KeyboardFocusManager
import java.awt.event.KeyEvent
import java.util.WeakHashMap

/**
 * Android key events count auto-repeats (a held key); AWT's don't. This counts consecutive presses
 * of the same key without a release, so the shared screens can tell a hold from a tap.
 */
object KeyRepeat {
    private val counts = HashMap<Int, Int>()
    private val perEvent = WeakHashMap<KeyEvent, Int>()

    fun install() = KeyboardFocusManager.getCurrentKeyboardFocusManager().addKeyEventDispatcher { e ->
        when (e.id) {
            KeyEvent.KEY_PRESSED -> {
                val n = counts[e.keyCode]?.plus(1) ?: 0
                counts[e.keyCode] = n
                perEvent[e] = n
            }
            KeyEvent.KEY_RELEASED -> counts.remove(e.keyCode)
        }
        false
    }

    fun of(e: Any?): Int = (e as? KeyEvent)?.let { perEvent[it] } ?: 0
}

/** Android's KeyEvent.repeatCount, for the shared player screen. */
val Any.repeatCount: Int get() = KeyRepeat.of(this)
