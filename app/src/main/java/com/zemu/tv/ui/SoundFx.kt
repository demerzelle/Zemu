package com.zemu.tv.ui

import android.content.Context
import android.media.AudioAttributes
import android.media.SoundPool
import com.zemu.tv.ui.theme.UiStyle

/**
 * UI sound effects: move, select, hold, back. Files live in assets/sounds/<set>/<event>.<ext>
 * (see the README there); themes that restyle the app have their own set, falling back to
 * "default". Your own .ogg/.mp3/.m4a beat the .wav placeholders.
 */
object SoundFx {
    enum class Event { MOVE, SELECT, HOLD, BACK }

    private var pool: SoundPool? = null
    private var loadedSet: String? = null
    private val ids = HashMap<Event, Int>()
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
        UiStyle.TODDLER -> "toddler"
        UiStyle.GRADE -> "gradeschool"
        UiStyle.TEEN -> "youngadult"
        UiStyle.NORMAL -> "default"
    }

    /** Loads [set]'s sounds (once per change of theme). */
    fun use(context: Context, set: String) {
        if (set == loadedSet) return
        loadedSet = set
        pool?.release()
        val p = SoundPool.Builder().setMaxStreams(4)
            .setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION).setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build())
            .build()
        pool = p
        ids.clear()
        val assets = context.assets
        fun find(folder: String, name: String): String? {
            val files = runCatching { assets.list("sounds/$folder")?.toList() }.getOrNull().orEmpty()
            return listOf("ogg", "mp3", "m4a", "wav").map { "$name.$it" }.firstOrNull { it in files }?.let { "sounds/$folder/$it" }
        }
        Event.entries.forEach { e ->
            val name = e.name.lowercase()
            val path = find(set, name) ?: find("default", name) ?: return@forEach
            runCatching { assets.openFd(path).use { fd -> ids[e] = p.load(fd, 1) } }
        }
    }

    fun play(e: Event) {
        if (!enabled) return
        val p = pool ?: return
        val id = ids[e] ?: return
        if (e == Event.MOVE) {
            // Holding an arrow repeats fast; keep it a gentle patter.
            val now = android.os.SystemClock.uptimeMillis()
            if (now - lastMove < 70) return
            lastMove = now
        }
        val vol = if (e == Event.MOVE) 0.45f else 0.7f
        p.play(id, vol, vol, 1, 0, 1f)
    }
}
