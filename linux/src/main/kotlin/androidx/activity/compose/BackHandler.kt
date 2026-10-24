package androidx.activity.compose

import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.remember

/** Esc / Backspace / mouse back button: the newest enabled handler wins, else navigation goes back. */
object BackDispatcher {
    class Entry(var enabled: Boolean, var onBack: () -> Unit)
    val entries = mutableStateListOf<Entry>()

    /** Returns true when a screen handled Back itself. */
    fun dispatch(): Boolean {
        val e = entries.lastOrNull { it.enabled } ?: return false
        e.onBack()
        return true
    }
}

@Composable
fun BackHandler(enabled: Boolean = true, onBack: () -> Unit) {
    val entry = remember { BackDispatcher.Entry(enabled, onBack) }
    SideEffect { entry.enabled = enabled; entry.onBack = onBack }
    DisposableEffect(entry) {
        BackDispatcher.entries.add(entry)
        onDispose { BackDispatcher.entries.remove(entry) }
    }
}
