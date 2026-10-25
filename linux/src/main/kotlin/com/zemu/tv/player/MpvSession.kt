package com.zemu.tv.player

import android.widget.Toast
import com.zemu.tv.AppContainer
import com.zemu.tv.data.Meta
import com.zemu.tv.data.Segment
import com.zemu.tv.data.SegmentType
import com.zemu.tv.data.SubtitleTrack
import com.zemu.tv.data.Video
import com.zemu.tv.data.WatchEntry
import com.zemu.tv.data.title
import com.zemu.tv.player.Playback.toCandidate
import com.zemu.tv.streams.FilterState
import com.zemu.tv.streams.Languages
import com.zemu.tv.streams.StreamFilter
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonPrimitive
import java.io.File
import java.net.StandardProtocolFamily
import java.net.UnixDomainSocketAddress
import java.nio.ByteBuffer
import java.nio.channels.Channels
import java.nio.channels.SocketChannel
import java.util.Locale
import java.util.concurrent.Executors

/**
 * Plays a title in mpv, a separate full-screen window that's light on slow PCs (hardware decoding
 * when the GPU has it, cheap scaling, a modest cache). Zemu drives it over mpv's JSON IPC socket:
 * resume position, saving progress, falling back to the next cached stream, Skip intro (Enter),
 * the next episode (N, or by itself at the end) and "Are you still watching?".
 * mpv's own keys work as usual (Space, arrows, F, J subtitles, # audio, Q to close).
 */
class MpvSession private constructor(
    private val c: AppContainer,
    private var meta: Meta,
    private var videoId: String,
    private var label: String?,
    private var candidates: List<PlayCandidate>,
    private var subs: List<SubtitleTrack>,
    private val startMs: Long,
) {
    private val thread = Executors.newSingleThreadExecutor { Thread(it, "mpv-session").apply { isDaemon = true } }
    private val scope = CoroutineScope(SupervisorJob() + thread.asCoroutineDispatcher())
    private val dir = File(c.appContext.cacheDir, "mpv").apply { mkdirs() }
    private val socketFile = File(dir, "ipc-${ProcessHandle.current().pid()}.sock")
    private var process: Process? = null
    private var channel: SocketChannel? = null

    private var index = 0
    private var positionMs = 0L
    private var durationMs = 0L
    private var paused = false
    private var resumeMs = startMs
    private var loaded = false
    private var refetched = false
    private var slateChecked: String? = null

    private var episodes: List<Video> = emptyList()
    private var nextUp: Video? = null
    private var countdownJob: Job? = null
    private var countdownCancelled = false
    private var autoAdvances = 0
    private var stillWatching = false

    private var segments: List<Segment> = emptyList()
    private var activeSegment: Segment? = null
    private var dismissedSegment: Segment? = null
    private var finishedMovie = false

    private var launched = false

    /**
     * Starts mpv. [wid]: an X11 window inside Zemu to draw the video in; null opens mpv's own
     * full-screen window (no X11, e.g. macOS during development).
     */
    fun launch(wid: Long?) {
        if (launched) return
        launched = true
        val settings = c.userStore.settings.value
        socketFile.delete()
        val inputConf = File(dir, "input.conf").apply {
            writeText(
                """
                ENTER script-message zemu-skip
                KP_ENTER script-message zemu-skip
                n script-message zemu-next
                N script-message zemu-next
                ESC quit
                BS quit
                MBTN_BACK quit
                """.trimIndent() + "\n",
            )
        }
        val langs = settings.subtitleLanguages.ifEmpty { listOf("en") }.flatMap(::langCodes)
        val audio = settings.audioLanguages.flatMap(::langCodes)
        val cmd = mutableListOf(
            mpvPath()!!,
            // Warnings and errors go to mpv.log (in the cache folder); no status line.
            "--msg-level=all=warn", "--term-osd=no", "--input-terminal=no", "--term-status-msg=",
            "--input-ipc-server=${socketFile.path}",
            "--idle=yes",
            "--keep-open=yes",
            "--force-window=immediate",
            if (wid != null) "--wid=$wid" else "--fullscreen",
            "--title=${listOfNotNull(meta.title, label).joinToString(" · ")}",
            // Mouse-friendly control bar along the bottom, like the rest of Zemu.
            "--script-opts=osc-layout=bottombar,osc-seekbarstyle=bar,osc-hidetimeout=1500",
            "--input-conf=${inputConf.path}",
            "--user-agent=Zemu/1.0 (Linux)",
            // Light on slow machines: GPU decoding when it works, cheap scalers, a bounded cache.
            "--hwdec=auto-safe",
            "--scale=bilinear", "--dscale=bilinear", "--cscale=bilinear",
            "--dither-depth=no", "--correct-downscaling=no", "--linear-downscaling=no", "--sigmoid-upscaling=no",
            "--hdr-compute-peak=no",
            "--cache=yes", "--demuxer-max-bytes=200MiB", "--demuxer-max-back-bytes=30MiB", "--demuxer-readahead-secs=60",
            // After running dry, wait for 10 s of video before resuming: on a slow connection that's
            // one pause now and then instead of stopping every second.
            "--cache-pause-initial=yes", "--cache-pause-wait=10",
            "--network-timeout=30",
            // Streams are direct links; asking yt-dlp about each failed one only adds seconds.
            "--ytdl=no",
            "--slang=${langs.joinToString(",")}",
            "--alang=${audio.joinToString(",")}",
            "--sub-auto=fuzzy",
        )
        // OpenGL: old Intel GPUs (Ivy Bridge and earlier) only have incomplete Vulkan drivers.
        // (Linux mpv always has OpenGL; macOS builds don't, and mpv refuses to start then.)
        if (System.getProperty("os.name").startsWith("Linux")) cmd += "--gpu-api=opengl"
        if (settings.autoSubtitles) cmd += "--sid=auto" else cmd += "--sid=no"
        if (!settings.subtitleOriginalStyle) {
            val color = String.format("#%08X", settings.subtitleColor and 0xFFFFFFFFL)
            cmd += listOf(
                "--sub-ass-override=force",
                "--sub-font-size=${(55 * settings.subtitleScale).toInt()}",
                "--sub-color=$color",
                "--sub-margin-y=${(settings.subtitleBottom * 720).toInt()}",
                when (settings.subtitleBackground) {
                    1 -> "--sub-back-color=#99000000"
                    2 -> "--sub-back-color=#FF000000"
                    else -> "--sub-back-color=#00000000"
                },
                "--sub-border-size=${if (settings.subtitleEdge == 1) 3 else 0}",
                "--sub-shadow-offset=${if (settings.subtitleEdge == 2) 2 else 0}",
            )
        }
        val builder = ProcessBuilder(cmd).redirectErrorStream(true).redirectOutput(File(dir, "mpv.log"))
        // Embedding needs X11: on a Wayland desktop mpv would open its own window instead, so it
        // runs through XWayland like Zemu does.
        if (wid != null) builder.environment().remove("WAYLAND_DISPLAY")
        process = runCatching { builder.start() }.getOrElse {
            Toast.makeText(null, "Couldn't start mpv: ${it.message}", Toast.LENGTH_LONG).show()
            onClosed(this)
            return
        }
        active = this
        Thread(::readLoop, "mpv-ipc").apply { isDaemon = true }.start()
        scope.launch {
            var ticks = 0
            while (true) {
                delay(1_000)
                if (++ticks % 15 == 0) saveProgress()
            }
        }
        loadEpisodes()
        c.trakt.scrobble("start", meta, videoId, 0f)
    }

    // ---- IPC ----

    private fun readLoop() {
        val ch = connect() ?: return scope.launch { finish() }.let { }
        channel = ch
        scope.launch {
            listOf("time-pos", "duration", "pause").forEachIndexed { i, p -> send("observe_property", i + 1, p) }
            loadCurrent(resumeMs)
        }
        runCatching {
            Channels.newInputStream(ch).bufferedReader().useLines { lines ->
                lines.forEach { line ->
                    val o = runCatching { c.json.parseToJsonElement(line) as? JsonObject }.getOrNull() ?: return@forEach
                    scope.launch { onEvent(o) }
                }
            }
        }
        // The socket closes when mpv quits.
        scope.launch { finish() }
    }

    private fun connect(): SocketChannel? {
        repeat(100) {
            if (process?.isAlive == false) return null
            runCatching {
                return SocketChannel.open(StandardProtocolFamily.UNIX).apply { connect(UnixDomainSocketAddress.of(socketFile.toPath())) }
            }
            Thread.sleep(100)
        }
        return null
    }

    private fun send(vararg args: Any?) {
        val ch = channel ?: return
        val arr = JsonArray(args.map { a ->
            when (a) {
                null -> kotlinx.serialization.json.JsonNull
                is Number -> JsonPrimitive(a)
                is Boolean -> JsonPrimitive(a)
                else -> JsonPrimitive(a.toString())
            }
        })
        val line = JsonObject(mapOf("command" to arr)).toString() + "\n"
        runCatching { synchronized(ch) { ch.write(ByteBuffer.wrap(line.toByteArray())) } }
    }

    private fun osd(text: String, ms: Int = 3000) = send("show-text", text, ms)

    // ---- Loading ----

    private fun loadCurrent(position: Long) {
        val cand = candidates.getOrNull(index) ?: return
        loaded = false
        val headers = cand.headers.map { (k, v) -> "$k: $v" }
        send("set_property", "http-header-fields", headers.joinToString(","))
        send("set_property", "start", if (position > 0) "+${position / 1000.0}" else "none")
        send("set_property", "force-media-title", listOfNotNull(meta.title, label).joinToString(" · "))
        send("loadfile", cand.url, "replace")
    }

    private fun onEvent(o: JsonObject) {
        when (o.str("event")) {
            "property-change" -> when (o.str("name")) {
                "time-pos" -> o.num("data")?.let { positionMs = (it * 1000).toLong(); onTick() }
                "duration" -> o.num("data")?.let {
                    durationMs = (it * 1000).toLong()
                    // A 2-minute "video" from an addon is an error slate (AIOStreams shows one when a
                    // link was opened from another IP or expired), not the title: try a fresh link.
                    // shortcut: assumes no episode is under 2.5 min; skip shows tagged as shorts if that changes.
                    val cand = candidates.getOrNull(index)
                    if (durationMs in 1..150_000 && cand != null && cand.url.startsWith("http") && slateChecked != cand.url) {
                        slateChecked = cand.url
                        onError("that link stopped working")
                    } else loadSegments()
                }
                "pause" -> paused = (o["data"] as? JsonPrimitive)?.booleanOrNull ?: false
            }
            "file-loaded" -> {
                loaded = true
                send("set_property", "start", "none")
                subs.forEach { s -> send("sub-add", s.url, "auto", s.lang, Languages.normalize(s.lang) ?: s.lang) }
                rememberPlayingFile()
            }
            "end-file" -> when (o.str("reason")) {
                "error" -> onError(o.str("file_error").ifBlank { "can't open" })
                "eof" -> onEnded()
            }
            "client-message" -> when ((o["args"] as? JsonArray)?.firstOrNull()?.jsonPrimitive?.contentOrNull) {
                "zemu-skip" -> skipSegment()
                "zemu-next" -> playNextNow()
            }
        }
    }

    // ---- Progress ----

    private fun onTick() {
        if (durationMs <= 0 || !loaded) return
        autoAdvancesTouched()
        updateActiveSegment()
        maybeShowNextUp()
        // keep-open leaves the last frame up; treat reaching it as the end.
        if (positionMs >= durationMs - 400 && countdownJob == null && !stillWatching) onEnded()
    }

    private var lastPos = 0L

    /** Seeking or pausing means someone is there: reset the "still watching?" count. */
    private fun autoAdvancesTouched() {
        if (paused || kotlin.math.abs(positionMs - lastPos) > 5_000) autoAdvances = 0
        lastPos = positionMs
    }

    /** This video played to its end; later saves (on close) mustn't undo "watched". */
    private var ended = false

    private fun saveProgress(reachedEnd: Boolean = false) {
        if (reachedEnd) ended = true
        if (!loaded || durationMs <= 0) return
        val entry = WatchEntry(meta, videoId, label, positionMs, durationMs, System.currentTimeMillis())
        val creditsAt = segments.firstOrNull { it.type == SegmentType.CREDITS && it.startMs > durationMs / 2 }?.startMs
        val finished = ended || if (creditsAt != null) positionMs >= creditsAt - 2_000 else positionMs >= durationMs * 0.95
        // In order: an older save landing last would undo "watched".
        val prev = lastSave
        lastSave = c.appScope.launch { prev?.join(); c.userStore.recordProgress(entry, finished) }
    }

    private var lastSave: Job? = null

    private fun rememberPlayingFile() {
        val cand = candidates.getOrNull(index) ?: return
        val entry = com.zemu.tv.data.LastStream(cand.key.ifEmpty { cand.url }, cand.bingeGroup, cand.url, cand.headers, videoId, cand.label)
        c.appScope.launch { c.userStore.rememberStream(meta.id, entry) }
    }

    // ---- Skip intro / recap / credits ----

    private fun loadSegments() {
        if (segments.isNotEmpty() || !c.userStore.settings.value.skipIntroButton || durationMs <= 0) return
        val forVideo = videoId
        val parts = videoId.split(':')
        scope.launch {
            val found = runCatching { c.skipSegments.find(meta, forVideo, parts.getOrNull(1)?.toIntOrNull(), parts.getOrNull(2)?.toIntOrNull(), durationMs) }.getOrDefault(emptyList())
            if (videoId == forVideo) segments = found
        }
    }

    private fun updateActiveSegment() {
        val seg = segments.firstOrNull { s ->
            val end = s.endMs ?: durationMs
            positionMs >= s.startMs && positionMs < end - 1_000 &&
                !(s.type == SegmentType.CREDITS && nextUp != null && c.userStore.settings.value.autoplayNext)
        }?.takeIf { it != dismissedSegment }
        if (seg != null && seg != activeSegment) osd("Press Enter (A) to skip ${seg.type.name.lowercase()}", 6000)
        activeSegment = seg
    }

    private fun skipSegment() {
        val seg = activeSegment ?: return
        val end = seg.endMs
        if (end == null || end >= durationMs - 2_000) {
            if (nextUp != null) playNextNow() else send("seek", ((durationMs - 500) / 1000.0).coerceAtLeast(0.0), "absolute")
        } else {
            send("seek", end / 1000.0, "absolute")
        }
        dismissedSegment = seg
        activeSegment = null
    }

    // ---- Next episode ----

    private fun loadEpisodes() {
        if (meta.type != "series") return
        scope.launch {
            val full = runCatching { c.addons.meta("series", meta.id) }.getOrNull() ?: return@launch
            episodes = full.videos
            nextUp = findNext()
        }
    }

    private fun findNext(): Video? {
        val current = episodes.firstOrNull { it.id == videoId } ?: return null
        val sameKind = episodes.filter { ((it.season ?: 0) == 0) == ((current.season ?: 0) == 0) }
        val sorted = sameKind.sortedWith(compareBy({ it.season ?: 0 }, { it.episodeNumber }))
        val today = java.text.SimpleDateFormat("yyyy-MM-dd", Locale.US).format(java.util.Date())
        return sorted.getOrNull(sorted.indexOfFirst { it.id == videoId } + 1)
            ?.takeIf { v -> v.released?.take(10)?.let { it <= today } != false }
    }

    private fun maybeShowNextUp() {
        val creditsAt = segments.firstOrNull { it.type == SegmentType.CREDITS && it.startMs > durationMs / 2 }?.startMs
        if (meta.type != "series") {
            // A movie is over once its credits start: save it as watched and go back to Zemu.
            if (creditsAt != null && positionMs >= creditsAt && !paused && !finishedMovie) {
                finishedMovie = true
                saveProgress()
                com.zemu.tv.PendingOpen.goHome = true
                send("quit")
            }
            return
        }
        val next = nextUp ?: return
        val settings = c.userStore.settings.value
        if (!settings.autoplayNext || countdownCancelled || countdownJob != null || stillWatching) return
        if (creditsAt != null) { if (positionMs < creditsAt) return } else if (durationMs - positionMs > 40_000L) return
        startCountdown(next, settings.autoplayCountdownSec)
    }

    private fun startCountdown(next: Video, seconds: Int) {
        countdownJob?.cancel()
        countdownJob = scope.launch {
            var left = seconds
            while (left > 0) {
                osd("Next: ${episodeLabel(next)} in $left s · N (A) to play now", 1100)
                delay(1_000)
                if (!paused) left--
            }
            advance(next, automatic = true)
        }
    }

    private fun playNextNow() {
        val next = nextUp ?: return
        countdownJob?.cancel()
        countdownJob = null
        if (stillWatching) { stillWatching = false; autoAdvances = 0 }
        advance(next, automatic = false)
    }

    private fun onEnded() {
        if (meta.type != "series") {
            saveProgress(reachedEnd = true)
            com.zemu.tv.PendingOpen.goHome = true
            send("quit")
            return
        }
        saveProgress(reachedEnd = true)
        val next = nextUp
        if (next != null && c.userStore.settings.value.autoplayNext && !countdownCancelled) {
            if (countdownJob == null) startCountdown(next, 0)
        } else {
            send("quit")
        }
    }

    private fun advance(next: Video, automatic: Boolean) {
        countdownJob = null
        val settings = c.userStore.settings.value
        if (automatic && settings.stillWatchingPrompt && autoAdvances + 1 > settings.stillWatchingEpisodes) {
            stillWatching = true
            send("set_property", "pause", true)
            osd("Are you still watching? Press N (A) to play ${episodeLabel(next)}, Q (B) to stop.", 600_000)
            return
        }
        if (automatic) autoAdvances++ else autoAdvances = 0
        loadEpisode(next)
    }

    private fun loadEpisode(next: Video) {
        saveProgress()
        loaded = false
        scope.launch {
            osd("Loading ${episodeLabel(next)}…", 10_000)
            val result = runCatching { c.streams.load(meta.type, next.id) }.getOrNull()
            val settings = c.userStore.settings.value
            val filtered = result?.cached.orEmpty().let { all ->
                StreamFilter.apply(all, c.streamFilter.value, c.capabilities, settings, emptySet())
                    .ifEmpty { StreamFilter.apply(all, FilterState(), c.capabilities, settings, emptySet()) }
            }.map { it.stream }
            if (filtered.isEmpty()) {
                osd("No cached streams for ${episodeLabel(next)} yet", 4000)
                delay(4000)
                send("quit")
                return@launch
            }
            val group = candidates.getOrNull(index)?.bingeGroup
            val ordered = if (group == null) filtered else filtered.sortedByDescending { it.raw.behaviorHints?.bingeGroup == group }
            candidates = ordered.take(5).map { it.toCandidate() }
            subs = Playback.pickSubtitles(runCatching { c.streams.subtitles(meta.type, next.id) }.getOrDefault(emptyList()), settings.subtitleLanguages)
            videoId = next.id
            label = episodeLabel(episodes.firstOrNull { it.id == next.id } ?: next)
            segments = emptyList(); activeSegment = null; dismissedSegment = null
            index = 0; positionMs = 0; durationMs = 0; refetched = false; ended = false
            countdownCancelled = false
            loadCurrent(0)
            nextUp = findNext()
        }
    }

    private fun episodeLabel(v: Video) = if (v.season != null) "S${v.season} E${v.episodeNumber} · ${v.displayTitle}" else v.displayTitle

    // ---- Errors: next stream, then look the title up again ----

    private fun onError(why: String) {
        val position = positionMs.takeIf { it > 0 } ?: resumeMs
        if (index + 1 < candidates.size) {
            index++
            osd("Stream failed ($why), trying the next one: ${candidates[index].label}", 4000)
            loadCurrent(position)
            return
        }
        if (!refetched) {
            refetched = true
            osd("That file isn't available anymore. Finding it again…", 6000)
            val tried = candidates.map { it.url }.toSet()
            val key = candidates.getOrNull(index)?.key
            scope.launch {
                val result = runCatching { c.streams.load(meta.type, videoId, force = true) }.getOrNull()
                val settings = c.userStore.settings.value
                val fresh = result?.cached.orEmpty().let { all ->
                    StreamFilter.apply(all, c.streamFilter.value, c.capabilities, settings, emptySet())
                        .ifEmpty { StreamFilter.apply(all, FilterState(), c.capabilities, settings, emptySet()) }
                }.map { it.stream }.filter { it.raw.url != null && it.raw.url !in tried }.sortedByDescending { it.key == key }
                if (fresh.isEmpty()) return@launch fail(why)
                candidates = fresh.take(5).map { it.toCandidate() }
                index = 0
                loadCurrent(position)
            }
            return
        }
        fail(why)
    }

    private fun fail(why: String) {
        // Every link (and a fresh lookup) failed to open: almost always the addon or debrid side.
        osd("None of the streams would open ($why).\nIf this keeps happening, check your debrid account and your stream addon's setup.", 8000)
        scope.launch { delay(8000); send("quit") }
    }

    // ---- Controller ----

    /**
     * A: pause (or skip the intro / play the next episode when offered), B / View: close,
     * D-pad or stick left/right: -/+10 s, LB/RB: -/+30 s, X: subtitles, Y: audio track,
     * up/down: show the progress bar, Menu: next episode.
     */
    private fun onPad(b: com.zemu.tv.desktop.Gamepad.Button) = scope.launch {
        if (!stillWatching) autoAdvances = 0
        when (b) {
            com.zemu.tv.desktop.Gamepad.Button.A -> when {
                stillWatching || countdownJob != null -> playNextNow()
                activeSegment != null -> skipSegment()
                else -> send("cycle", "pause")
            }
            com.zemu.tv.desktop.Gamepad.Button.B, com.zemu.tv.desktop.Gamepad.Button.VIEW -> send("quit")
            com.zemu.tv.desktop.Gamepad.Button.X -> send("cycle", "sub")
            com.zemu.tv.desktop.Gamepad.Button.Y -> send("cycle", "audio")
            com.zemu.tv.desktop.Gamepad.Button.LEFT -> send("seek", -10, "relative")
            com.zemu.tv.desktop.Gamepad.Button.RIGHT -> send("seek", 10, "relative")
            com.zemu.tv.desktop.Gamepad.Button.LB -> send("seek", -30, "relative")
            com.zemu.tv.desktop.Gamepad.Button.RB -> send("seek", 30, "relative")
            com.zemu.tv.desktop.Gamepad.Button.UP, com.zemu.tv.desktop.Gamepad.Button.DOWN -> send("show-progress")
            com.zemu.tv.desktop.Gamepad.Button.MENU -> playNextNow()
        }
    }

    // ---- End ----

    private var finished = false

    private fun finish() {
        if (finished) return
        finished = true
        saveProgress()
        c.trakt.scrobble("stop", meta, videoId, if (durationMs > 0) positionMs.toFloat() / durationMs else 0f)
        runCatching { channel?.close() }
        process?.destroy()
        socketFile.delete()
        if (active === this) active = null
        onClosed(this)
        scope.cancel()
        thread.shutdown()
    }

    private fun JsonObject.str(k: String) = (this[k] as? JsonPrimitive)?.contentOrNull.orEmpty()
    private fun JsonObject.num(k: String) = (this[k] as? JsonPrimitive)?.doubleOrNull

    companion object {
        @Volatile private var active: MpvSession? = null

        /** Called when a session's mpv closes; the desktop shell hides its video area. */
        var onClosed: (MpvSession) -> Unit = {}

        /**
         * Set by the desktop shell: shows a video area in Zemu's window and calls [launch] with its
         * X11 window id. Without it (tests), mpv opens its own window.
         */
        var host: ((MpvSession) -> Unit)? = null

        /** Sends a controller button to the playing video; false when nothing is playing. */
        fun gamepad(b: com.zemu.tv.desktop.Gamepad.Button): Boolean {
            val s = active?.takeIf { !it.finished } ?: return false
            s.onPad(b)
            return true
        }

        /** Sends an mpv command (keyboard shortcuts) to the playing video; false when nothing is playing. */
        fun command(vararg args: Any?): Boolean {
            val s = active?.takeIf { !it.finished } ?: return false
            s.scope.launch { s.send(*args) }
            return true
        }

        fun mpvPath(): String? = System.getenv("PATH").orEmpty().split(':')
            .map { File(it, "mpv") }.firstOrNull { it.canExecute() }?.path

        fun start(c: AppContainer, meta: Meta, videoId: String, label: String?, candidates: List<PlayCandidate>, subs: List<SubtitleTrack>, startMs: Long) {
            if (candidates.isEmpty()) return
            if (mpvPath() == null) {
                Toast.makeText(null, "Zemu plays videos with mpv. Install it (e.g. sudo apt install mpv) and try again.", Toast.LENGTH_LONG).show()
                return
            }
            // One player at a time: a new title replaces whatever is playing.
            active?.send("quit")
            val s = MpvSession(c, meta, videoId, label, candidates, subs, startMs)
            active = s
            host?.invoke(s) ?: s.launch(null)
        }

        /** "en" → ["en", "eng"], so mpv matches files tagged either way. */
        private fun langCodes(code: String): List<String> =
            listOf(code) + runCatching { Locale(code).isO3Language }.getOrNull().orEmpty().let { if (it.isNotBlank() && it != code) listOf(it) else emptyList() }
    }
}
