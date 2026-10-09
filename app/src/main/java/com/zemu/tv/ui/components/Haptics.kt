package com.zemu.tv.ui.components

import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import com.zemu.tv.container

/** Short vibrations for page changes and starting a video. No-op on TVs and when turned off in Settings. */
object Haptics {
    enum class Kind { TICK, START }

    fun buzz(context: Context, kind: Kind = Kind.TICK) {
        val on = runCatching { context.container.userStore.settings.value.vibration }.getOrDefault(true)
        if (!on) return
        val vibrator = vibrator(context) ?: return
        if (!vibrator.hasVibrator()) return
        runCatching {
            when {
                Build.VERSION.SDK_INT >= 29 -> vibrator.vibrate(
                    VibrationEffect.createPredefined(if (kind == Kind.TICK) VibrationEffect.EFFECT_TICK else VibrationEffect.EFFECT_CLICK),
                )
                Build.VERSION.SDK_INT >= 26 -> vibrator.vibrate(VibrationEffect.createOneShot(if (kind == Kind.TICK) 15L else 35L, VibrationEffect.DEFAULT_AMPLITUDE))
                else -> @Suppress("DEPRECATION") vibrator.vibrate(if (kind == Kind.TICK) 15L else 35L)
            }
        }
    }

    private fun vibrator(context: Context): Vibrator? =
        if (Build.VERSION.SDK_INT >= 31) (context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager)?.defaultVibrator
        else @Suppress("DEPRECATION") (context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator)
}
