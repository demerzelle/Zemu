package com.zemu.tv.streams

/**
 * Picks the audio and subtitle tracks to play from the viewer's languages instead of trusting the
 * file's defaults. Tracks are often untagged or only named in their title ("English", "JPN 5.1"), so
 * titles count too. Shared by the Android and Linux players, which map their tracks to [Track].
 */
object TrackPicker {
    data class Track(
        val lang: String?,
        val label: String?,
        val forced: Boolean = false,
        val isDefault: Boolean = false,
        val sdh: Boolean = false,
        val external: Boolean = false,
        /** Audio description for the blind. */
        val describesVideo: Boolean = false,
    )

    private val partial = Regex("sign|song|s&s|forced|karaoke", RegexOption.IGNORE_CASE)
    private val extra = Regex("comment|director|descri|narrat|\\bAD\\b", RegexOption.IGNORE_CASE)

    /** [t]'s language: its tag, else a language named in its title. */
    fun languageOf(t: Track): String? =
        t.lang?.let { Languages.normalize(it) }?.takeIf { it !in setOf("und", "mul", "zxx", "mis") }
            ?: t.label?.let(::fromLabel)

    /** "English", "ENG 5.1", "Japanese (Dub)" → a 2-letter code. Short words only as known release tokens. */
    fun fromLabel(label: String): String? = Regex("[A-Za-z]+").findAll(label).firstNotNullOfOrNull { w ->
        Languages.audioTokens[w.value.uppercase()] ?: if (w.value.length > 3) Languages.normalize(w.value) else null
    }

    private fun isExtra(t: Track) = t.describesVideo || t.label?.let { extra.containsMatchIn(it) } == true
    private fun isPartial(t: Track) = t.forced || t.label?.let { partial.containsMatchIn(it) } == true

    /** Index of the audio track to play, or null to leave the player's own pick ([current]). */
    fun audio(tracks: List<Track>, prefs: List<String>, current: Int?): Int? {
        for (lang in prefs) {
            val match = tracks.indices.filter { !isExtra(tracks[it]) && languageOf(tracks[it]) == lang }
            if (match.isNotEmpty()) return match.firstOrNull { it == current } ?: match.firstOrNull { tracks[it].isDefault } ?: match.first()
        }
        return null
    }

    /**
     * Index of the subtitle track to show, or -1 for none. [mode] is "off", "auto" or "always"; in "auto",
     * full subtitles show when [audioLang] isn't one of [prefs], and otherwise only forced ones (signs and
     * foreign-language lines). Untagged audio counts as yours, except in anime ([anime]), where it's
     * usually Japanese.
     */
    fun subtitle(tracks: List<Track>, prefs: List<String>, mode: String, audioLang: String?, anime: Boolean, preferSdh: Boolean): Int {
        if (mode == "off") return -1
        val understood = if (audioLang == null) !anime else audioLang in prefs
        val full = mode == "always" || !understood
        for (lang in prefs) {
            val ofLang = tracks.indices.filter { languageOf(tracks[it]) == lang && !isExtra(tracks[it]) }
            val pick = if (full) {
                // Full subtitles, never "Signs & Songs": embedded before side-loaded, the SDH preference, then the file's default.
                ofLang.filter { !isPartial(tracks[it]) }
                    .sortedWith(compareBy({ tracks[it].sdh != preferSdh }, { tracks[it].external }, { !tracks[it].isDefault }))
                    .firstOrNull()
            } else ofLang.firstOrNull { isPartial(tracks[it]) && !tracks[it].external }
            if (pick != null) return pick
        }
        return -1
    }

    /** Remembered per-show choice ("audio|subtitle", "off" = none) put first in line, or [prefs] as they are. */
    fun withShowChoice(audioPrefs: List<String>, subPrefs: List<String>, mode: String, remembered: String?): Triple<List<String>, List<String>, String> {
        val (a, s) = remembered?.split('|')?.let { it.getOrNull(0).orEmpty() to it.getOrNull(1).orEmpty() } ?: return Triple(audioPrefs, subPrefs, mode)
        val audio = if (a.isNotEmpty()) (listOf(a) + audioPrefs).distinct() else audioPrefs
        return when {
            s == "off" -> Triple(audio, subPrefs, "off")
            s.isNotEmpty() -> Triple(audio, (listOf(s) + subPrefs).distinct(), "always")
            else -> Triple(audio, subPrefs, mode)
        }
    }
}
