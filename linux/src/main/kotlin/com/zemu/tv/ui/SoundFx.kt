package com.zemu.tv.ui

import android.content.Context
import com.zemu.tv.ui.theme.UiStyle
import javax.sound.sampled.AudioSystem
import javax.sound.sampled.Clip

/**
 * UI sound effects: move, select, hold, back, from resources sounds/<set>/<event>.wav (themes that
 * restyle the app have their own set, falling back to "default"). Clips are decoded once per set.
 */
object SoundFx {
    enum class Event { MOVE, SELECT, HOLD, BACK }

    private var loadedSet: String? = null
    private val clips = HashMap<Event, Clip>()
    private var lastMove = 0L
    var enabled = true

    fun setFor(style: UiStyle): String = when (style) {
        UiStyle.PS2 -> "ps2"
        UiStyle.ACID -> "acidwave"
        UiStyle.RETRO -> "cybercore"
        UiStyle.GRAFFITI -> "graffiti"
        UiStyle.LIQUID -> "liquid"
        UiStyle.ETHEREAL -> "ethereal"
        UiStyle.CATRAVE -> "catrave"
        UiStyle.SPACE -> "space"
        UiStyle.OCEAN -> "ocean"
        UiStyle.NIGHT -> "ethereal"
        UiStyle.ALIEN -> "space"
        UiStyle.POCKET -> "pocket"
        UiStyle.SIXTEEN -> "sixteen"
        UiStyle.NORMAL -> "default"
    }

    @Suppress("UNUSED_PARAMETER")
    fun use(context: Context, set: String) {
        if (set == loadedSet || !enabled) return
        loadedSet = set
        clips.values.forEach { it.close() }
        clips.clear()
        // Off the UI thread: opening the sound device can take a moment (or fail on headless boxes).
        Thread {
            Event.entries.forEach { e ->
                val name = e.name.lowercase()
                val res = SoundFx::class.java.classLoader.getResource("sounds/$set/$name.wav")
                    ?: SoundFx::class.java.classLoader.getResource("sounds/default/$name.wav") ?: return@forEach
                runCatching {
                    val clip = AudioSystem.getClip()
                    AudioSystem.getAudioInputStream(res).use { clip.open(it) }
                    synchronized(clips) { clips[e] = clip }
                }
            }
        }.apply { isDaemon = true }.start()
    }

    fun play(e: Event) {
        if (!enabled) return
        val clip = synchronized(clips) { clips[e] } ?: return
        if (e == Event.MOVE) {
            // Holding an arrow repeats fast; keep it a gentle patter.
            val now = System.nanoTime() / 1_000_000
            if (now - lastMove < 70) return
            lastMove = now
        }
        clip.stop()
        clip.framePosition = 0
        clip.start()
    }
}
