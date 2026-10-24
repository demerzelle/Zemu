package android.widget

import android.content.Context
import androidx.compose.runtime.mutableStateOf

/** Toasts show as a short message at the bottom of the window (drawn by the desktop shell). */
class Toast private constructor(private val text: String, private val long: Boolean) {
    fun show() { current.value = Shown(text, System.nanoTime(), if (long) 3500L else 2000L) }

    data class Shown(val text: String, val id: Long, val durationMs: Long)

    companion object {
        const val LENGTH_SHORT = 0
        const val LENGTH_LONG = 1
        val current = mutableStateOf<Shown?>(null)
        fun makeText(context: Context?, text: CharSequence, duration: Int) = Toast(text.toString(), duration == LENGTH_LONG)
    }
}
