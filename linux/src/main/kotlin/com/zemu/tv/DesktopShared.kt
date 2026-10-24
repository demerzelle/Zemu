package com.zemu.tv

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf

// Shared with the Android app's MainActivity.kt (not compiled here).

/** Opens the "Who's watching?" screen (from Settings). */
val LocalSwitchProfile = staticCompositionLocalOf<() -> Unit> { {} }

/** A title to open from elsewhere (the screensaver): type to id. Consumed by the app shell. */
object PendingOpen {
    var target by mutableStateOf<Pair<String, String>?>(null)
    /** Start playing [target] right away (the screensaver's "Watch now"). */
    var play = false

    /** Set when "Are you still watching?" went unanswered: start the slideshow right away. */
    var screensaverNow = false

    /** Set when a movie finishes: the app returns to Home. */
    var goHome by mutableStateOf(false)
}
