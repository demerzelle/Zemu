package com.zemu.tv.player

import android.content.Context
import com.zemu.tv.data.TrailerRef

/** Trailers play in mpv (YouTube through yt-dlp); without mpv they open in the browser. */
object TrailerActivity {
    fun start(context: Context, trailers: List<TrailerRef>, startId: String? = null, startSeconds: Int = 0) {
        if (trailers.isEmpty()) return
        val ordered = trailers.sortedByDescending { it.id == startId }
        val urls = ordered.map { "https://www.youtube.com/watch?v=${it.id}" }
        val mpv = listOf(MpvSession.mpvPath() ?: "mpv", "--fullscreen", "--ytdl-format=bestvideo[height<=?1080]+bestaudio/best", "--start=$startSeconds") + urls
        if (MpvSession.mpvPath() == null || runCatching { ProcessBuilder(mpv).start() }.isFailure) {
            runCatching { ProcessBuilder("xdg-open", urls.first()).start() }
        }
    }

    fun start(context: Context, youtubeId: String, startSeconds: Int = 0) =
        start(context, listOf(TrailerRef(youtubeId, "Trailer")), youtubeId, startSeconds)
}

/** No embedded web player on desktop: hero trailers report an error at once and the backdrop stays. */
object YouTubeEmbed {
    interface Listener {
        fun onPlaying() {}
        fun onEnded() {}
        fun onError(code: Int) {}
        fun onTime(seconds: Float) {}
    }

    class View(val listener: Listener) { fun destroy() {} }

    @Suppress("UNUSED_PARAMETER")
    fun create(context: Context, focusable: Boolean, listener: Listener) = View(listener)

    @Suppress("UNUSED_PARAMETER")
    fun load(view: View, videoId: String, muted: Boolean, controls: Boolean, cover: Boolean) = view.listener.onError(0)
}

fun formatTime(ms: Long): String {
    val total = (ms / 1000).coerceAtLeast(0)
    val h = total / 3600
    val m = (total % 3600) / 60
    val s = total % 60
    return if (h > 0) "%d:%02d:%02d".format(h, m, s) else "%d:%02d".format(m, s)
}
