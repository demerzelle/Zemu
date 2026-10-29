package com.zemu.tv.ui

import android.content.Context
import com.zemu.tv.ui.theme.UiStyle
import javax.sound.sampled.AudioFormat
import javax.sound.sampled.AudioSystem
import javax.sound.sampled.Clip

/**
 * UI sound effects: move, select, hold, back, from resources sounds/<set>/<event>.wav (themes that
 * restyle the app have their own set, falling back to "default"), or a sound pack chosen in Settings
 * ([PACKS]). Clips are decoded once per set; theme sets are made softer and lo-fi on the way in ([lofi]).
 */
object SoundFx {
    enum class Event { MOVE, SELECT, HOLD, BACK }

    private var loadedSet: String? = null
    private val clips = HashMap<Event, Clip>()
    private var lastMove = 0L
    var enabled = true
    private val player = java.util.concurrent.Executors.newSingleThreadExecutor { r -> Thread(r, "sound").apply { isDaemon = true } }

    /** Desktop sound packs (resources sounds/pack-<key>), by setting key; "lofi" is the theme's own set, softened. */
    val PACKS = listOf("lofi" to "Lo-fi", "wood" to "Wood", "bubbles" to "Bubbles", "keys" to "Soft keys", "cosmic" to "Cosmic", "retro" to "Retro")

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

    /** The set to load: the chosen pack, or the theme's own. */
    fun setFor(style: UiStyle, pack: String): String = if (pack == "lofi") setFor(style) else "pack-$pack"

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
                    AudioSystem.getAudioInputStream(res).use { src ->
                        val fmt = AudioFormat(src.format.sampleRate, 16, src.format.channels, true, false)
                        val raw = AudioSystem.getAudioInputStream(fmt, src).use { it.readAllBytes() }
                        // The packs are made soft already.
                        val pcm = if (set.startsWith("pack-")) raw else lofi(raw, fmt)
                        clip.open(fmt, pcm, 0, pcm.size)
                    }
                    synchronized(clips) { clips[e] = clip }
                }
            }
        }.apply { isDaemon = true }.start()
    }

    /**
     * Softer, lower and lo-fi: pitched down an octave and a half (played back at a third of the speed), quieter, and
     * muffled (two gentle low-pass passes around 900 Hz take the edge off the timbre), with a short
     * fade at the end so nothing clicks.
     */
    private fun lofi(input: ByteArray, fmt: AudioFormat): ByteArray {
        val ch = fmt.channels
        val inFrames = input.size / (2 * ch)
        val pitch = 0.35f
        val frames = (inFrames / pitch).toInt()
        val pcm = ByteArray(frames * 2 * ch)
        fun sample(i: Int, c: Int): Float {
            val at = (i.coerceIn(0, inFrames - 1) * ch + c) * 2
            return ((input[at + 1].toInt() shl 8) or (input[at].toInt() and 0xFF)) / 32768f
        }
        val a = 1f - kotlin.math.exp(-2f * Math.PI.toFloat() * 900f / fmt.sampleRate)
        val fade = (fmt.sampleRate * 0.03f).toInt().coerceAtMost(frames)
        for (c in 0 until ch) {
            var y1 = 0f; var y2 = 0f
            for (i in 0 until frames) {
                // Slower playback, by linear interpolation between the original samples.
                val pos = i * pitch
                val j = pos.toInt()
                val x = sample(j, c) + (sample(j + 1, c) - sample(j, c)) * (pos - j)
                y1 += a * (x - y1); y2 += a * (y1 - y2)
                var v = y2 * 0.5f
                if (i >= frames - fade) v *= (frames - i).toFloat() / fade
                val out = (v * 32767f).toInt().coerceIn(-32768, 32767)
                val at = (i * ch + c) * 2
                pcm[at] = out.toByte(); pcm[at + 1] = (out shr 8).toByte()
            }
        }
        return pcm
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
        // Off the UI thread: a stalled sound device would otherwise freeze the arrow keys with it.
        player.execute {
            clip.stop()
            clip.framePosition = 0
            clip.start()
        }
    }
}
