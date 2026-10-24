package android.os

object SystemClock {
    fun uptimeMillis(): Long = System.nanoTime() / 1_000_000
    fun elapsedRealtime(): Long = uptimeMillis()
}

/** SDK_INT 0 turns off the Android 12+ paths (window blur, render effects). */
object Build { object VERSION { const val SDK_INT = 0 } }
