package com.zemu.tv

/** The Android resource ids the shared code uses, mapped to bundled resource files. */
object R {
    object drawable {
        const val logo_mark = 1
        const val logo_mark_glow = 2
        const val logo_wordmark = 3
    }
    object font { const val pixelify_sans = 100 }

    val paths = mapOf(1 to "logo_mark.png", 2 to "logo_mark_glow.png", 3 to "logo_wordmark.png", 100 to "pixelify_sans.ttf")
}
