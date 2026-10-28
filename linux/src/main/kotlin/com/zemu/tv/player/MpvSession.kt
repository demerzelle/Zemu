package com.zemu.tv.player

import android.os.SystemClock
import android.widget.Toast
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.unit.IntSize
import com.zemu.tv.AppContainer
import com.zemu.tv.data.Meta
import com.zemu.tv.data.Segment
import com.zemu.tv.data.SegmentType
import com.zemu.tv.data.SubtitleTrack
import com.zemu.tv.data.Video
import com.zemu.tv.data.WatchEntry
import com.zemu.tv.data.slim
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
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.io.File
import java.net.StandardProtocolFamily
import java.net.UnixDomainSocketAddress
import java.nio.ByteBuffer
import java.nio.channels.Channels
import java.nio.channels.SocketChannel
import java.util.Locale
import java.util.concurrent.Executors
import kotlin.math.max
import kotlin.math.min

/** The shared Android player screen ([PlayerScreen]) drives this desktop player through the same API. */
typealias PlayerActivity = MpvSession

/**
 * Picture sizes. [zoom] > 1 enlarges the picture past the screen edges (useful on a 16:9 TV, where
 * Fit/Fill/Stretch all look the same for 16:9 video).
 */
enum class AspectMode(val label: String, val zoom: Float = 1f) {
    FIT("Fit"),
    ZOOM("Fill screen"),
    ZOOM_115("Zoom 115%", 1.15f),
    ZOOM_133("Zoom 133%", 1.33f),
    STRETCH("Stretch"),
    CENTER("Original size"),
}

/** An audio or subtitle track. [group] is null only for "Off"; otherwise it's mpv's track id. */
data class TrackOption(val key: String, val label: String, val selected: Boolean, val group: Any?, val index: Int, val lang: String? = null)

/** Sleep timer choices, cycled from the player's menu. */
enum class SleepTimer(val label: String, val minutes: Int?) {
    OFF("Off", null), M15("15 min", 15), M30("30 min", 30), M60("1 hour", 60), M90("90 min", 90), END_OF_EPISODE("End of episode", null)
}

/**
 * Plays a title with mpv (hardware decoding when the GPU has it, cheap scaling, a modest cache),
 * drawn inside Zemu's window, with Zemu's own player screen on top. Zemu drives mpv over its
 * JSON IPC socket: resume position, saving progress, tracks, speed, picture size, falling back to
 * the next cached stream, skip intro / recap, the next episode and "Are you still watching?".
 * State is Compose state, read by [PlayerScreen]; mpv events arrive on the session's own thread.
 */
class MpvSession private constructor(
    private val c: AppContainer,
    meta: Meta,
    private var videoId: String,
    label: String?,
    private var candidates: List<PlayCandidate>,
    private var subs: List<SubtitleTrack>,
    private val startMs: Long,
) : android.content.Context() {
    private val thread = Executors.newSingleThreadExecutor { Thread(it, "mpv-session").apply { isDaemon = true } }
    private val scope = CoroutineScope(SupervisorJob() + thread.asCoroutineDispatcher())
    private val dir = File(c.appContext.cacheDir, "mpv").apply { mkdirs() }
    private val socketFile = File(dir, "ipc-${ProcessHandle.current().pid()}.sock")
    private var process: Process? = null
    private var channel: SocketChannel? = null

    // ---- State for the player screen ----

    var meta by mutableStateOf(meta)
        private set
    var label by mutableStateOf(label)
        private set
    var streamLabel by mutableStateOf("")
        private set
    val title: String get() = meta.title
    var isPlaying by mutableStateOf(false)
        private set
    var buffering by mutableStateOf(true)
        private set
    var positionMs by mutableLongStateOf(0L)
        private set
    var durationMs by mutableLongStateOf(0L)
        private set
    var bufferedMs by mutableLongStateOf(0L)
        private set
    var speed by mutableFloatStateOf(1f)
        private set
    var videoSize by mutableStateOf<IntSize?>(null)
        private set
    var tracksVersion by mutableIntStateOf(0)
        private set
    var scrubTargetMs by mutableStateOf<Long?>(null)
        private set
    var scrubShownUntil by mutableLongStateOf(0L)
        private set
    var nextUp by mutableStateOf<Video?>(null)
        private set
    /** A recommended title to play when there's no next episode. */
    var nextTitle by mutableStateOf<Meta?>(null)
        private set
    /** Seconds left on the "Next episode" card, or null when it isn't showing. */
    var countdown by mutableStateOf<Int?>(null)
        private set
    var stillWatchingPrompt by mutableStateOf(false)
        private set
    /** The skippable part playing right now (intro, recap, credits), if any. */
    var activeSegment by mutableStateOf<Segment?>(null)
        private set
    var sleep by mutableStateOf(SleepTimer.OFF)
        private set
    private var sleepAt = 0L

    /** Skippable parts of this video, marked on the seek bar. */
    val markers: List<Segment> get() = segments

    /** What the countdown card plays: the next episode, or the first episode/movie of [nextTitle]. */
    val upNext: Video? get() = nextUp ?: nextTitle?.let { videoFor(it) }

    /** Android draws video into a view; here mpv draws into Zemu's window, so these are placeholders. */
    val playerView: Any? = null
    fun createPlayerView(@Suppress("UNUSED_PARAMETER") context: android.content.Context): Any = Unit

    // ---- Internal ----

    private var index = 0
    private var paused = false
    private var resumeMs = startMs
    private var loaded = false
    private var refetched = false
    private var slateChecked: String? = null
    private var tracks: List<JsonObject> = emptyList()

    private var episodes: List<Video> = emptyList()
    private var countdownJob: Job? = null
    private var countdownCancelled = false
    private var autoAdvances = 0
    private var recommendationRequested = false
    private var stillWatchingTimeout: Job? = null

    private var segments: List<Segment> = emptyList()
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
            // Zemu draws the controls and handles every key, mouse click and controller button.
            "--osc=no", "--osd-level=0", "--input-default-bindings=no", "--input-vo-keyboard=no",
            "--cursor-autohide=5000",
            "--user-agent=Zemu/1.0 (Linux)",
            // Light on slow machines: GPU decoding when it works, cheap scalers, a bounded cache.
            // Settings → "Prefer software video decoders" for streams the GPU decodes with glitches.
            if (settings.preferSoftwareDecoders) "--hwdec=no" else "--hwdec=auto-safe",
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
        cmd += subtitleStyle(settings)
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
                checkSleepTimer()
            }
        }
        // Subtitle style changes in Settings / the player apply right away.
        scope.launch { c.userStore.settings.collect { s -> subtitleStyle(s).forEach { send("set_property", it.substringBefore('=').removePrefix("--"), it.substringAfter('=')) } } }
        loadEpisodes()
        c.trakt.scrobble("start", meta, videoId, 0f)
    }

    private fun subtitleStyle(s: com.zemu.tv.data.AppSettings): List<String> {
        if (s.subtitleOriginalStyle) return listOf("--sub-ass-override=no")
        return listOf(
            "--sub-ass-override=force",
            "--sub-font-size=${(55 * s.subtitleScale).toInt()}",
            "--sub-color=${String.format("#%08X", s.subtitleColor and 0xFFFFFFFFL)}",
            "--sub-margin-y=${(s.subtitleBottom * 720).toInt()}",
            "--sub-back-color=" + when (s.subtitleBackground) { 1 -> "#99000000"; 2 -> "#FF000000"; else -> "#00000000" },
            "--sub-border-size=${if (s.subtitleEdge == 1) 3 else 0}",
            "--sub-shadow-offset=${if (s.subtitleEdge == 2) 2 else 0}",
        )
    }

    // ---- IPC ----

    private val observed = listOf("time-pos", "duration", "pause", "paused-for-cache", "demuxer-cache-time", "speed", "track-list", "video-params")

    private fun readLoop() {
        val ch = connect() ?: return scope.launch { finish() }.let { }
        channel = ch
        scope.launch {
            observed.forEachIndexed { i, p -> send("observe_property", i + 1, p) }
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

    private fun notice(text: String, long: Boolean = false) = Toast.makeText(null, text, if (long) Toast.LENGTH_LONG else Toast.LENGTH_SHORT).show()

    // ---- Loading ----

    private fun loadCurrent(position: Long) {
        val cand = candidates.getOrNull(index) ?: return
        loaded = false
        buffering = true
        streamLabel = cand.label
        val headers = cand.headers.map { (k, v) -> "$k: $v" }
        send("set_property", "http-header-fields", headers.joinToString(","))
        send("set_property", "start", if (position > 0) "+${position / 1000.0}" else "none")
        send("set_property", "force-media-title", listOfNotNull(meta.title, label).joinToString(" · "))
        send("loadfile", cand.url, "replace")
    }

    private fun onEvent(o: JsonObject) {
        when (o.str("event")) {
            "property-change" -> {
                val data = o["data"]
                when (o.str("name")) {
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
                    "pause" -> { paused = (data as? JsonPrimitive)?.booleanOrNull ?: false; isPlaying = loaded && !paused }
                    "paused-for-cache" -> buffering = !loaded || (data as? JsonPrimitive)?.booleanOrNull == true
                    "demuxer-cache-time" -> o.num("data")?.let { bufferedMs = (it * 1000).toLong() }
                    "speed" -> o.num("data")?.let { speed = it.toFloat() }
                    "track-list" -> { tracks = (data as? JsonArray)?.mapNotNull { it as? JsonObject }.orEmpty(); tracksVersion++ }
                    "video-params" -> (data as? JsonObject)?.let { p ->
                        val w = p["w"]?.jsonPrimitive?.intOrNull
                        val h = p["h"]?.jsonPrimitive?.intOrNull
                        videoSize = if (w != null && h != null) IntSize(w, h) else null
                    }
                }
            }
            "file-loaded" -> {
                loaded = true
                buffering = false
                isPlaying = !paused
                send("set_property", "start", "none")
                subs.forEach { s -> send("sub-add", s.url, "auto", s.lang, Languages.normalize(s.lang) ?: s.lang) }
                rememberPlayingFile()
            }
            "end-file" -> when (o.str("reason")) {
                "error" -> onError(o.str("file_error").ifBlank { "can't open" })
                "eof" -> onEnded()
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
        if (positionMs >= durationMs - 400 && countdownJob == null && !stillWatchingPrompt) onEnded()
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
        val entry = WatchEntry(meta.slim(), videoId, label, positionMs, durationMs, System.currentTimeMillis())
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

    // ---- Controls (called from the player screen, on the UI thread) ----

    fun togglePlay() = on { send("cycle", "pause") }

    fun seekBy(deltaMs: Long) = on {
        val target = (positionMs + deltaMs).coerceIn(0, max(durationMs - 1_000, 0))
        send("seek", target / 1000.0, "absolute")
        positionMs = target
    }

    fun changeSpeed(value: Float) = on { send("set_property", "speed", value) }

    fun setAspect(mode: AspectMode) = on {
        send("set_property", "keepaspect", mode != AspectMode.STRETCH)
        send("set_property", "panscan", if (mode == AspectMode.ZOOM) 1.0 else 0.0)
        send("set_property", "video-zoom", if (mode.zoom > 1f) kotlin.math.ln(mode.zoom.toDouble()) / kotlin.math.ln(2.0) else 0.0)
        send("set_property", "video-unscaled", if (mode == AspectMode.CENTER) "downscale-big" else "no")
    }

    fun rate(value: Int) { c.appScope.launch { c.userStore.rate(meta, value) } }

    fun toggleMyList() { c.appScope.launch { c.userStore.toggleMyList(meta) } }

    private fun on(block: () -> Unit) { scope.launch { block() } }

    // ---- Scrubbing ----

    private var scrubJob: Job? = null
    private var holdJob: Job? = null
    private var scrubStreak = 0
    private var lastScrubAt = 0L
    private var lastScrubDir = 0

    /**
     * Left/Right scrubbing. The step grows from 15 s to 60 s the faster it's pressed (or the longer
     * a key is held), and the seek happens once you stop, so mpv doesn't rebuffer on every press.
     */
    fun scrub(direction: Int, repeatCount: Int) {
        val now = SystemClock.uptimeMillis()
        scrubStreak = if (direction == lastScrubDir && now - lastScrubAt < 700) scrubStreak + 1 else 0
        lastScrubAt = now
        lastScrubDir = direction
        val level = max(scrubStreak / 2, repeatCount / 4)
        val stepSec = SCRUB_STEPS[min(level, SCRUB_STEPS.lastIndex)]
        val base = scrubTargetMs ?: positionMs
        val limit = if (durationMs > 0) durationMs - 1_000 else Long.MAX_VALUE
        val target = (base + direction * stepSec * 1_000L).coerceIn(0, max(limit, 0))
        scrubTargetMs = target
        scrubShownUntil = now + 2_500
        scrubJob?.cancel()
        scrubJob = scope.launch {
            delay(700)
            send("seek", target / 1000.0, "absolute")
            positionMs = target
            scrubTargetMs = null
            scrubShownUntil = SystemClock.uptimeMillis() + 1_500
        }
    }

    /** Held down: the preview moves faster the longer it's held (10 s → 5 min per second). Seeks on release. */
    fun startHoldScrub(direction: Int) {
        if (holdJob?.isActive == true) return
        scrubJob?.cancel()
        holdJob = scope.launch {
            val started = SystemClock.uptimeMillis()
            var last = started
            var target = (scrubTargetMs ?: positionMs).toDouble()
            val limit = if (durationMs > 0) durationMs - 1_000.0 else Double.MAX_VALUE
            while (isActive) {
                val now = SystemClock.uptimeMillis()
                val rate = (10.0 * Math.pow(1.75, (now - started) / 1000.0)).coerceAtMost(300.0)
                target = (target + direction * rate * (now - last)).coerceIn(0.0, max(limit, 0.0))
                last = now
                scrubTargetMs = target.toLong()
                scrubShownUntil = now + 2_500
                delay(33)
            }
        }
    }

    fun stopHoldScrub() {
        holdJob?.cancel() ?: return
        holdJob = null
        val target = scrubTargetMs ?: return
        on { send("seek", target / 1000.0, "absolute"); positionMs = target }
        scrubTargetMs = null
        scrubShownUntil = SystemClock.uptimeMillis() + 1_500
    }

    // ---- Tracks ----

    private fun trackOptions(type: String): List<TrackOption> {
        val out = tracks.filter { it.str("type") == type }.map { t ->
            val id = t["id"]?.jsonPrimitive?.intOrNull ?: 0
            val lang = t.str("lang").takeIf { it.isNotBlank() }?.let { Languages.normalize(it) }
            val title = t.str("title").takeIf { it.isNotBlank() }
            val extra = buildList {
                if (type == "audio") {
                    t.str("codec").takeIf { it.isNotBlank() }?.let { add(codecName(it)) }
                    (t["demux-channel-count"]?.jsonPrimitive?.intOrNull)?.let { add(channelLabel(it)) }
                }
                if (t["forced"]?.jsonPrimitive?.booleanOrNull == true) add("Forced")
                if (type == "sub" && title?.contains("SDH", ignoreCase = true) == true) add("SDH")
            }
            val name = (listOf(title ?: lang?.let { Languages.displayName(it) } ?: "Track $id") + extra).distinct().joinToString(" · ")
            TrackOption("$type:$id", name, t["selected"]?.jsonPrimitive?.booleanOrNull == true, id, id, lang ?: "und:$id")
        }
        // "English" twice is ambiguous; number repeats.
        val counts = out.groupingBy { it.label }.eachCount()
        val seen = mutableMapOf<String, Int>()
        return out.map { o -> if ((counts[o.label] ?: 0) < 2) o else o.copy(label = "${o.label} ${seen.merge(o.label, 1, Int::plus)}") }
    }

    fun audioOptions(): List<TrackOption> = trackOptions("audio")

    fun subtitleOptions(): List<TrackOption> {
        val list = trackOptions("sub")
        val off = list.none { it.selected }
        return listOf(TrackOption("off", "Off", off, null, -1)) + list
    }

    fun selectTrack(option: TrackOption, type: Int) = on {
        if (type == androidx.media3.common.C.TRACK_TYPE_AUDIO) send("set_property", "aid", option.index)
        else send("set_property", "sid", if (option.group == null) "no" else option.index)
    }

    /** Selects the next audio track (wrapping) and returns its name. */
    fun cycleAudio(): String {
        val options = audioOptions()
        if (options.isEmpty()) return "No audio tracks"
        if (options.size == 1) return options[0].label
        val next = options[(options.indexOfFirst { it.selected } + 1).mod(options.size)]
        selectTrack(next, androidx.media3.common.C.TRACK_TYPE_AUDIO)
        return next.label
    }

    /** Off → each subtitle language in turn → Off. Returns what's now showing. */
    fun cycleSubtitles(): String {
        val options = subtitleOptions()
        val list = options.filter { it.group != null }
        if (list.isEmpty()) return "No subtitles found"
        val languages = list.map { it.lang }.distinct()
        val current = list.firstOrNull { it.selected }?.lang
        val nextLang = if (current == null) languages.first() else languages.getOrNull(languages.indexOf(current) + 1)
        if (nextLang == null) {
            selectTrack(options.first(), androidx.media3.common.C.TRACK_TYPE_TEXT)
            return "Off"
        }
        val sdh = c.userStore.settings.value.preferSdh
        val track = list.filter { it.lang == nextLang }.let { same -> same.firstOrNull { it.label.contains("SDH") == sdh } ?: same.first() }
        selectTrack(track, androidx.media3.common.C.TRACK_TYPE_TEXT)
        return track.label.replace(Regex(" \\d+$"), "")
    }

    fun currentAudioLabel(): String = audioOptions().firstOrNull { it.selected }?.label ?: "Default"

    fun currentSubtitleLabel(): String =
        subtitleOptions().firstOrNull { it.selected && it.group != null }?.label?.replace(Regex(" \\d+$"), "") ?: "Off"

    private fun codecName(codec: String) = when (codec.lowercase()) {
        "eac3" -> "Dolby Digital+"
        "ac3" -> "Dolby Digital"
        "truehd" -> "TrueHD"
        "dts" -> "DTS"
        "aac" -> "AAC"
        "opus" -> "Opus"
        "flac" -> "FLAC"
        "mp3" -> "MP3"
        else -> codec.uppercase()
    }

    private fun channelLabel(n: Int) = when (n) { 1 -> "Mono"; 2 -> "Stereo"; 6 -> "5.1"; 8 -> "7.1"; else -> "$n ch" }

    // ---- Sleep timer ----

    fun cycleSleepTimer() {
        sleep = SleepTimer.entries[(sleep.ordinal + 1) % SleepTimer.entries.size]
        sleepAt = sleep.minutes?.let { SystemClock.uptimeMillis() + it * 60_000L } ?: 0L
    }

    fun sleepShort(): String = when {
        sleep == SleepTimer.OFF -> "Off"
        sleep == SleepTimer.END_OF_EPISODE -> "At end"
        else -> "${((sleepAt - SystemClock.uptimeMillis()) / 60_000 + 1).coerceAtLeast(1)} min"
    }

    private fun checkSleepTimer() {
        if (sleepAt == 0L || SystemClock.uptimeMillis() < sleepAt) return
        sleep = SleepTimer.OFF
        sleepAt = 0L
        send("set_property", "pause", true)
        saveProgress()
        notice("Sleep timer: paused", long = true)
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
        activeSegment = segments.firstOrNull { s ->
            val end = s.endMs ?: durationMs
            positionMs >= s.startMs && positionMs < end - 1_000 &&
                !(s.type == SegmentType.CREDITS && nextUp != null && c.userStore.settings.value.autoplayNext)
        }?.takeIf { it != dismissedSegment }
    }

    fun skipSegment() = on {
        val seg = activeSegment ?: return@on
        val end = seg.endMs
        if (end == null || end >= durationMs - 2_000) {
            if (upNext != null) playNextNowInternal() else send("seek", ((durationMs - 500) / 1000.0).coerceAtLeast(0.0), "absolute")
        } else {
            send("seek", end / 1000.0, "absolute")
            positionMs = end
        }
        dismissedSegment = seg
        activeSegment = null
    }

    fun dismissSegment() = on {
        dismissedSegment = activeSegment
        activeSegment = null
    }

    // ---- Next episode / autoplay ----

    private fun videoFor(t: Meta) = Video(
        id = when {
            t.type != "series" -> t.id
            t.id.startsWith("kitsu:") -> "${t.id}:1"
            else -> "${t.id}:1:1"
        },
        name = t.name,
    )

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

    /** Near the end of a series' last episode, pick a similar unwatched title. */
    private fun requestRecommendation() {
        if (meta.type != "series") return
        if (recommendationRequested || nextUp != null || !c.userStore.settings.value.autoplaySimilar) return
        if (durationMs <= 0 || durationMs - positionMs > 4 * 60_000L || episodes.isEmpty()) return
        recommendationRequested = true
        val m = meta
        scope.launch {
            val seen = c.userStore.watched.value + c.userStore.history.value.map { it.meta.id } + m.id
            val disliked = c.userStore.ratings.value.filterValues { it < 0 }.keys
            val recs = runCatching { c.recommender.moreLikeThis(m, exclude = seen + disliked, limit = 10) }.getOrDefault(emptyList())
            nextTitle = recs.firstOrNull { it.meta.id.startsWith("tt") || it.meta.id.startsWith("kitsu:") }?.meta
        }
    }

    private fun maybeShowNextUp() {
        val creditsAt = segments.firstOrNull { it.type == SegmentType.CREDITS && it.startMs > durationMs / 2 }?.startMs
        if (meta.type != "series") {
            // A movie is over once its credits start: save it as watched and go back to Zemu.
            if (creditsAt != null && positionMs >= creditsAt && !paused && !finishedMovie) {
                finishedMovie = true
                saveProgress(reachedEnd = true)
                com.zemu.tv.PendingOpen.goHome = true
                send("quit")
            }
            return
        }
        requestRecommendation()
        val next = upNext ?: return
        val settings = c.userStore.settings.value
        if (!settings.autoplayNext || countdownCancelled || countdownJob != null || stillWatchingPrompt) return
        if (creditsAt != null) { if (positionMs < creditsAt) return } else if (durationMs - positionMs > 40_000L) return
        startCountdown(next, settings.autoplayCountdownSec)
    }

    private fun startCountdown(next: Video, seconds: Int) {
        countdownJob?.cancel()
        countdown = seconds
        countdownJob = scope.launch {
            while ((countdown ?: 0) > 0) {
                delay(1_000)
                if (!paused || ended) countdown = (countdown ?: 0) - 1
            }
            if (countdown != null) advance(next, automatic = true)
        }
    }

    fun cancelCountdown() = on {
        countdownJob?.cancel()
        countdownJob = null
        countdown = null
        countdownCancelled = true
    }

    fun playNextNow() = on { playNextNowInternal() }

    private fun playNextNowInternal() {
        val next = upNext ?: return
        countdownJob?.cancel()
        countdownJob = null
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
        if (sleep == SleepTimer.END_OF_EPISODE) {
            sleep = SleepTimer.OFF
            send("quit")
            return
        }
        val next = upNext
        if (next != null && c.userStore.settings.value.autoplayNext && !countdownCancelled) {
            if (countdownJob == null) startCountdown(next, 0)
        } else {
            send("quit")
        }
    }

    private fun advance(next: Video, automatic: Boolean) {
        countdown = null
        countdownJob = null
        val settings = c.userStore.settings.value
        if (automatic && settings.stillWatchingPrompt && autoAdvances + 1 > settings.stillWatchingEpisodes) {
            send("set_property", "pause", true)
            stillWatchingPrompt = true
            // Nobody answered: leave the player and let the library slideshow take over.
            stillWatchingTimeout?.cancel()
            stillWatchingTimeout = scope.launch {
                delay(5 * 60_000L)
                if (!stillWatchingPrompt) return@launch
                stillWatchingPrompt = false
                com.zemu.tv.PendingOpen.screensaverNow = true
                send("quit")
            }
            return
        }
        if (automatic) autoAdvances++ else autoAdvances = 0
        loadEpisode(next)
    }

    fun answerStillWatching(keepWatching: Boolean, dontAskAgain: Boolean = false) = on {
        stillWatchingPrompt = false
        stillWatchingTimeout?.cancel()
        autoAdvances = if (keepWatching) 1 else 0
        if (dontAskAgain) c.appScope.launch { c.userStore.updateSettings { it.copy(stillWatchingPrompt = false) } }
        val next = upNext
        if (!keepWatching || next == null) send("quit") else loadEpisode(next)
    }

    private fun loadEpisode(next: Video) {
        saveProgress()
        loaded = false
        buffering = true
        val switching = nextUp == null && nextTitle != null
        scope.launch {
            if (switching) {
                // Moving on to a recommended title: load its full details (episodes for series).
                val t = nextTitle!!
                meta = runCatching { c.addons.meta(t.type, t.id) }.getOrNull() ?: t
                episodes = meta.videos
                nextTitle = null
                recommendationRequested = false
            }
            notice("Loading ${episodeLabel(next)}…")
            val result = runCatching { c.streams.load(meta.type, next.id) }.getOrNull()
            val settings = c.userStore.settings.value
            val filtered = result?.cached.orEmpty().let { all ->
                StreamFilter.apply(all, c.streamFilter.value, c.capabilities, settings, emptySet())
                    .ifEmpty { StreamFilter.apply(all, FilterState(), c.capabilities, settings, emptySet()) }
            }.map { it.stream }
            if (filtered.isEmpty()) {
                notice("No cached streams for ${episodeLabel(next)} yet", long = true)
                delay(3_000)
                send("quit")
                return@launch
            }
            // Same release group first, so quality and audio don't jump between episodes.
            val group = candidates.getOrNull(index)?.bingeGroup
            val ordered = if (group == null) filtered else filtered.sortedByDescending { it.raw.behaviorHints?.bingeGroup == group }
            candidates = ordered.take(5).map { it.toCandidate() }
            subs = Playback.pickSubtitles(runCatching { c.streams.subtitles(meta.type, next.id) }.getOrDefault(emptyList()), settings.subtitleLanguages)
            videoId = next.id
            label = if (switching && meta.type != "series") null else episodeLabel(episodes.firstOrNull { it.id == next.id } ?: next)
            segments = emptyList(); activeSegment = null; dismissedSegment = null
            index = 0; positionMs = 0; durationMs = 0; refetched = false; ended = false; finishedMovie = false
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
            notice("Stream failed ($why), trying the next one: ${candidates[index].label}")
            loadCurrent(position)
            return
        }
        if (!refetched) {
            refetched = true
            notice("That file isn't available anymore. Finding it again…")
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
        notice("None of the streams would open ($why). If this keeps happening, check your debrid account and your stream addon's setup.", long = true)
        scope.launch { delay(4_000); send("quit") }
    }

    // ---- Controller shortcuts (buttons with no key equivalent) ----

    /** X: subtitles, Y: audio track, LB/RB: -/+10 s, Menu: next episode. */
    private fun onPad(b: com.zemu.tv.desktop.Gamepad.Button): Boolean {
        when (b) {
            com.zemu.tv.desktop.Gamepad.Button.X -> notice("Subtitles: ${cycleSubtitles()}")
            com.zemu.tv.desktop.Gamepad.Button.Y -> notice("Audio: ${cycleAudio()}")
            com.zemu.tv.desktop.Gamepad.Button.LB -> seekBy(-10_000)
            com.zemu.tv.desktop.Gamepad.Button.RB -> seekBy(10_000)
            com.zemu.tv.desktop.Gamepad.Button.MENU -> if (upNext != null) playNextNow() else return false
            else -> return false
        }
        return true
    }

    /** Closes the player (Back, Esc, B). */
    fun stop() = on { send("quit") }

    /** Mute toggle (M). */
    fun toggleMute() = on { send("cycle", "mute") }

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
        private val SCRUB_STEPS = intArrayOf(15, 15, 30, 30, 45, 60)

        @Volatile private var active: MpvSession? = null

        /** Called when a session's mpv closes; the desktop shell hides its video area. */
        var onClosed: (MpvSession) -> Unit = {}

        /**
         * Set by the desktop shell: shows a video area in Zemu's window and calls [launch] with its
         * X11 window id. Without it (tests), mpv opens its own window.
         */
        var host: ((MpvSession) -> Unit)? = null

        /** Controller buttons that act on the playing video directly; false when not handled. */
        fun gamepad(b: com.zemu.tv.desktop.Gamepad.Button): Boolean {
            val s = active?.takeIf { !it.finished } ?: return false
            return s.onPad(b)
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
