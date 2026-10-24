package com.zemu.tv.ui.components

import android.content.Context

/** PCs don't vibrate. */
object Haptics {
    enum class Kind { TICK, START }
    @Suppress("UNUSED_PARAMETER") fun buzz(context: Context, kind: Kind = Kind.TICK) {}
}
