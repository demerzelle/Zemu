package com.zemu.tv.player

import android.app.AlertDialog
import android.content.Context
import android.net.Uri
import android.os.Bundle
import android.os.SystemClock
import android.view.KeyEvent
import android.view.WindowManager
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.annotation.OptIn
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.unit.IntSize
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.lifecycleScope
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.Tracks
import androidx.media3.common.VideoSize
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.audio.AudioCapabilities
import androidx.media3.exoplayer.audio.AudioSink
import androidx.media3.exoplayer.audio.DefaultAudioSink
import androidx.media3.exoplayer.ExoPlaybackException
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.CaptionStyleCompat
import androidx.media3.ui.PlayerView
import androidx.media3.ui.SubtitleView
import com.zemu.tv.container
import com.zemu.tv.data.AppSettings
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
import com.zemu.tv.ui.theme.ZemuTheme
import com.zemu.tv.ui.theme.themeColors
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.serialization.builtins.ListSerializer
import kotlin.math.max
import kotlin.math.min

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

data class TrackOption(val key: String, val label: String, val selected: Boolean, val group: Tracks.Group?, val index: Int, val lang: String? = null)

/**
 * Built-in player. Owns ExoPlayer and exposes Compose state for [PlayerScreen].
 *
 * Decoding failures escalate automatically: Dolby Vision → HDR10 base layer, then software
 * video decoders, then FFmpeg audio, then the next-best cached stream, then an external player.
 */
@OptIn(UnstableApi::class)
class PlayerActivity : ComponentActivity() {
    private val c by lazy { container }
    private var player: ExoPlayer? = null
    var playerView: PlayerView? = null
        private set

    var meta: Meta? = null
        private set
    private var videoId = ""
    private var candidates: List<PlayCandidate> = emptyList()
    private var subs: List<SubtitleTrack> = emptyList()
    private var index = 0
    private var mode = DecoderMode()
    private var startMode = DecoderMode()
    private var reachedReady = false
    private var resumeMs = 0L

    // ---- Compose state ----
    var label by mutableStateOf<String?>(null)
    var streamLabel by mutableStateOf("")
    var isPlaying by mutableStateOf(false)
    var buffering by mutableStateOf(true)
    var positionMs by mutableLongStateOf(0L)
    var durationMs by mutableLongStateOf(0L)
    var bufferedMs by mutableLongStateOf(0L)
    var videoSize by mutableStateOf<IntSize?>(null)
    var speed by mutableFloatStateOf(1f)
        private set
    var tracksVersion by mutableIntStateOf(0)

    /** Where a pending scrub will seek to; null when not scrubbing. */
    var scrubTargetMs by mutableStateOf<Long?>(null)
    var scrubShownUntil by mutableLongStateOf(0L)

    var nextUp by mutableStateOf<Video?>(null)
    /** Recommended title to play when there's no next episode. */
    var nextTitle by mutableStateOf<Meta?>(null)
    private var recommendationRequested = false

    /** What the countdown card plays: the next episode, or the first episode/movie of [nextTitle]. */
    val upNext: Video? get() = nextUp ?: nextTitle?.let { videoFor(it) }

    private fun videoFor(t: Meta) = Video(
        id = when {
            t.type != "series" -> t.id
            t.id.startsWith("kitsu:") -> "${t.id}:1"
            else -> "${t.id}:1:1"
        },
        title = t.name,
    )
    /** Seconds left on the "Next episode" countdown, or null when the card isn't showing. */
    var countdown by mutableStateOf<Int?>(null)
    var stillWatchingPrompt by mutableStateOf(false)

    private var episodes: List<Video> = emptyList()
    private var countdownCancelled = false
    private var countdownJob: Job? = null
    private var autoAdvances = 0
    private var scrubJob: Job? = null
    private var scrubStreak = 0
    private var lastScrubAt = 0L
    private var lastScrubDir = 0

    val title: String get() = meta?.title.orEmpty()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        val json = c.json
        meta = intent.getStringExtra(Playback.EXTRA_META)?.let { runCatching { json.decodeFromString(Meta.serializer(), it) }.getOrNull() }
        videoId = intent.getStringExtra(Playback.EXTRA_VIDEO_ID).orEmpty()
        label = intent.getStringExtra(Playback.EXTRA_LABEL)
        candidates = intent.getStringExtra(Playback.EXTRA_CANDIDATES)?.let {
            runCatching { json.decodeFromString(ListSerializer(PlayCandidate.serializer()), it) }.getOrNull()
        }.orEmpty()
        subs = intent.getStringExtra(Playback.EXTRA_SUBS)?.let {
            runCatching { json.decodeFromString(ListSerializer(SubtitleTrack.serializer()), it) }.getOrNull()
        }.orEmpty()
        resumeMs = intent.getLongExtra(Playback.EXTRA_START_MS, 0L)
        if (candidates.isEmpty()) return finish()

        val settings = c.userStore.settings.value
        startMode = DecoderMode(avoidDolbyVision = settings.avoidDolbyVision, softwareVideo = settings.preferSoftwareDecoders)
        mode = startMode

        setContent {
            val s by c.userStore.settings.collectAsStateWithLifecycle()
            // The player is always dark, whatever the app's light/dark setting.
            ZemuTheme(s.themeColors().copy(light = false)) { PlayerScreen(this) }
        }
        start(resumeMs)
        loadEpisodes()

        lifecycleScope.launch {
            var ticks = 0
            while (isActive) {
                delay(500)
                pollPosition()
                if (++ticks % 30 == 0) saveProgress()
                checkSleepTimer()
            }
        }
        lifecycleScope.launch {
            c.userStore.settings.collect { applyCaptionStyle(it) }
        }
    }

    /** Created once by the UI; each new ExoPlayer is attached to it. */
    fun createPlayerView(context: Context): PlayerView = PlayerView(context).apply {
        useController = false
        setShowBuffering(PlayerView.SHOW_BUFFERING_NEVER)
        keepScreenOn = true
        isFocusable = false
        player = this@PlayerActivity.player
        playerView = this
        applyCaptionStyle(c.userStore.settings.value)
    }

    fun setAspect(mode: AspectMode) {
        playerView?.resizeMode = when (mode) {
            AspectMode.FIT, AspectMode.CENTER, AspectMode.ZOOM_115, AspectMode.ZOOM_133 -> AspectRatioFrameLayout.RESIZE_MODE_FIT
            AspectMode.ZOOM -> AspectRatioFrameLayout.RESIZE_MODE_ZOOM
            AspectMode.STRETCH -> AspectRatioFrameLayout.RESIZE_MODE_FILL
        }
    }

    private fun applyCaptionStyle(s: AppSettings) {
        val view = playerView?.subtitleView ?: return
        val bg = when (s.subtitleBackground) { 1 -> 0x99000000.toInt(); 2 -> 0xFF000000.toInt(); else -> 0 }
        val edge = when (s.subtitleEdge) {
            1 -> CaptionStyleCompat.EDGE_TYPE_OUTLINE
            2 -> CaptionStyleCompat.EDGE_TYPE_DROP_SHADOW
            else -> CaptionStyleCompat.EDGE_TYPE_NONE
        }
        view.setStyle(CaptionStyleCompat(s.subtitleColor.toInt(), bg, 0, edge, 0xFF000000.toInt(), null))
        view.setApplyEmbeddedStyles(false)
        view.setFractionalTextSize(SubtitleView.DEFAULT_TEXT_SIZE_FRACTION * s.subtitleScale)
        view.setBottomPaddingFraction(s.subtitleBottom)
    }

    // ---- Playback ----

    private fun start(positionMs: Long) {
        player?.release()
        reachedReady = false
        // Nothing queued for the previous stream may touch the new one.
        scrubJob?.cancel()
        scrubTargetMs = null
        countdownJob?.cancel()
        countdown = null
        val candidate = candidates[index]
        streamLabel = candidate.label
        val settings = c.userStore.settings.value

        val http = DefaultHttpDataSource.Factory()
            .setUserAgent("Zemu/1.0 (Android TV)")
            .setAllowCrossProtocolRedirects(true)
            .setConnectTimeoutMs(15_000)
            .setReadTimeoutMs(30_000)
            .setDefaultRequestProperties(candidate.headers)
        val pcmOnly = forcePcm
        val renderers = object : DefaultRenderersFactory(this) {
            // Bitstreamed Dolby/DTS audio (HDMI passthrough) can't change speed, so when the speed
            // isn't 1x, audio is decoded to PCM here instead and time-stretched.
            override fun buildAudioSink(context: Context, enableFloatOutput: Boolean, enableAudioTrackPlaybackParams: Boolean): AudioSink? =
                if (!pcmOnly) super.buildAudioSink(context, enableFloatOutput, enableAudioTrackPlaybackParams)
                else DefaultAudioSink.Builder(context)
                    .setAudioCapabilities(AudioCapabilities.DEFAULT_AUDIO_CAPABILITIES)
                    .setEnableFloatOutput(enableFloatOutput)
                    .build()
        }
            .setEnableDecoderFallback(true)
            .setMediaCodecSelector(FallbackCodecSelector(mode))
            .setExtensionRendererMode(
                if (mode.ffmpegAudio) DefaultRenderersFactory.EXTENSION_RENDERER_MODE_PREFER
                else DefaultRenderersFactory.EXTENSION_RENDERER_MODE_ON,
            )
        val exo = ExoPlayer.Builder(this, renderers)
            .setMediaSourceFactory(DefaultMediaSourceFactory(this).setDataSourceFactory(DefaultDataSource.Factory(this, http)))
            .setSeekBackIncrementMs(10_000)
            .setSeekForwardIncrementMs(10_000)
            .build()
        exo.trackSelectionParameters = exo.trackSelectionParameters.buildUpon()
            .setPreferredAudioLanguages(*settings.audioLanguages.toTypedArray())
            .apply { if (settings.autoSubtitles) setPreferredTextLanguages(*settings.subtitleLanguages.toTypedArray()) }
            .setSelectUndeterminedTextLanguage(false)
            .build()

        val subtitleConfigs = subs.mapNotNull { s ->
            val lang = Languages.normalize(s.lang) ?: s.lang
            runCatching {
                MediaItem.SubtitleConfiguration.Builder(Uri.parse(s.url))
                    .setMimeType(subtitleMime(s.url))
                    .setLanguage(lang)
                    .setLabel("${Languages.displayName(lang)} (external)")
                    .setSelectionFlags(0)
                    .build()
            }.getOrNull()
        }
        exo.setMediaItem(MediaItem.Builder().setUri(candidate.url).setSubtitleConfigurations(subtitleConfigs).build())
        if (positionMs > 0) exo.seekTo(positionMs)
        exo.playbackParameters = PlaybackParameters(speed)
        exo.addListener(object : Player.Listener {
            override fun onPlaybackStateChanged(state: Int) {
                buffering = state == Player.STATE_BUFFERING || state == Player.STATE_IDLE
                if (state == Player.STATE_READY && !reachedReady) {
                    reachedReady = true
                    rememberWorkingMode()
                    loadSegments()
                }
                if (state == Player.STATE_ENDED) onEnded()
            }

            override fun onIsPlayingChanged(playing: Boolean) {
                isPlaying = playing
            }

            override fun onVideoSizeChanged(size: VideoSize) {
                if (size.width > 0 && size.height > 0) {
                    videoSize = IntSize((size.width * size.pixelWidthHeightRatio).toInt(), size.height)
                }
            }

            override fun onTracksChanged(tracks: Tracks) {
                tracksVersion++
            }

            override fun onPlayerError(error: PlaybackException) = handleError(error)
        })
        exo.prepare()
        exo.playWhenReady = true
        player = exo
        playerView?.player = exo
    }

    private fun pollPosition() {
        val p = player ?: return
        positionMs = p.currentPosition.coerceAtLeast(0)
        durationMs = p.duration.takeIf { it != C.TIME_UNSET && it > 0 } ?: 0
        bufferedMs = p.bufferedPosition
        updateActiveSegment()
        maybeShowNextUp()
    }

    // ---- Sleep timer ----

    var sleep by mutableStateOf(SleepTimer.OFF)
        private set
    /** When a timed sleep option pauses playback (uptime millis), or 0. */
    var sleepAt by mutableLongStateOf(0L)
        private set

    fun cycleSleepTimer() {
        sleep = SleepTimer.entries[(sleep.ordinal + 1) % SleepTimer.entries.size]
        sleepAt = sleep.minutes?.let { android.os.SystemClock.uptimeMillis() + it * 60_000L } ?: 0L
    }

    /** "Sleep: 30 min (27 left)" etc., for the menu. */
    fun sleepLabel(): String = when {
        sleep == SleepTimer.OFF -> "Sleep timer: Off"
        sleep == SleepTimer.END_OF_EPISODE -> "Sleep timer: end of this ${if (meta?.type == "series") "episode" else "video"}"
        else -> "Sleep timer: ${sleep.label} (${((sleepAt - android.os.SystemClock.uptimeMillis()) / 60_000 + 1).coerceAtLeast(1)} min left)"
    }

    private fun checkSleepTimer() {
        if (sleepAt == 0L || android.os.SystemClock.uptimeMillis() < sleepAt) return
        sleep = SleepTimer.OFF
        sleepAt = 0L
        player?.pause()
        saveProgress()
        Toast.makeText(this, "Sleep timer: paused", Toast.LENGTH_LONG).show()
    }

    // ---- Skip intro / recap / credits ----

    /** Segments for the current video (from TheIntroDB / AniSkip). */
    private var segments: List<Segment> = emptyList()
    private var segmentsFor: String? = null
    /** The skippable part playing right now, if any. */
    var activeSegment by mutableStateOf<Segment?>(null)
        private set
    private var dismissedSegment: Segment? = null

    private fun loadSegments() {
        val m = meta ?: return
        if (segmentsFor == videoId || !c.userStore.settings.value.skipIntroButton) return
        segmentsFor = videoId
        val forVideo = videoId
        val parts = videoId.split(':')
        val season = parts.getOrNull(1)?.toIntOrNull()
        val episode = parts.getOrNull(2)?.toIntOrNull()
        lifecycleScope.launch {
            val found = runCatching { c.skipSegments.find(m, forVideo, season, episode, durationMs) }.getOrDefault(emptyList())
            if (videoId == forVideo) segments = found
        }
    }

    private fun updateActiveSegment() {
        val pos = positionMs
        val seg = segments.firstOrNull { s ->
            val end = s.endMs ?: durationMs
            pos >= s.startMs && pos < end - 1_000 &&
                // Credits with a next episode get the "Next episode" card instead.
                !(s.type == SegmentType.CREDITS && nextUp != null && c.userStore.settings.value.autoplayNext)
        }
        activeSegment = seg?.takeIf { it != dismissedSegment }
    }

    fun skipSegment() {
        val seg = activeSegment ?: return
        val end = seg.endMs
        if (end == null || (durationMs > 0 && end >= durationMs - 2_000)) {
            // Credits run to the end: move on rather than sitting on a black screen.
            if (nextUp != null) playNextNow() else {
                player?.seekTo(max(durationMs - 500, 0))
            }
        } else {
            player?.seekTo(end)
            positionMs = end
        }
        dismissedSegment = seg
        activeSegment = null
    }

    fun dismissSegment() {
        dismissedSegment = activeSegment
        activeSegment = null
    }

    fun togglePlay() {
        val p = player ?: return
        if (p.isPlaying) p.pause() else {
            if (p.playbackState == Player.STATE_ENDED) p.seekTo(0)
            p.play()
        }
    }

    fun seekBy(deltaMs: Long) {
        val p = player ?: return
        p.seekTo((p.currentPosition + deltaMs).coerceIn(0, max(durationMs, 0)))
        positionMs = p.currentPosition
    }

    /**
     * Left/Right scrubbing. The step grows from 15 s to 60 s the longer the button is held or the
     * faster it's pressed, and the seek happens once you stop, so the player doesn't rebuffer on
     * every press.
     */
    fun scrub(direction: Int, repeatCount: Int) {
        val p = player ?: return
        val now = SystemClock.uptimeMillis()
        scrubStreak = if (direction == lastScrubDir && now - lastScrubAt < 700) scrubStreak + 1 else 0
        lastScrubAt = now
        lastScrubDir = direction
        val level = max(scrubStreak / 2, repeatCount / 4)
        val stepSec = SCRUB_STEPS[min(level, SCRUB_STEPS.lastIndex)]
        val base = scrubTargetMs ?: p.currentPosition
        val limit = if (durationMs > 0) durationMs - 1_000 else Long.MAX_VALUE
        val target = (base + direction * stepSec * 1_000L).coerceIn(0, max(limit, 0))
        scrubTargetMs = target
        scrubShownUntil = now + 2_500
        scrubJob?.cancel()
        scrubJob = lifecycleScope.launch {
            delay(700)
            player?.seekTo(target)
            positionMs = target
            scrubTargetMs = null
            scrubShownUntil = SystemClock.uptimeMillis() + 1_500
        }
    }

    /** True while audio must be decoded on the device (needed for speeds other than 1x). */
    private var forcePcm = false

    fun changeSpeed(value: Float) {
        speed = value
        val p = player ?: return
        if (value != 1f && !forcePcm && isBitstreamingAudio()) {
            // Restart the stream with decoded audio so the new speed actually applies.
            forcePcm = true
            val pos = p.currentPosition
            val playing = p.playWhenReady
            start(pos)
            player?.playWhenReady = playing
            return
        }
        p.playbackParameters = PlaybackParameters(value)
    }

    /** Whether the current audio track is sent undecoded to the TV/receiver (AC3, E-AC3, DTS, TrueHD). */
    private fun isBitstreamingAudio(): Boolean {
        val format = player?.audioFormat ?: return false
        val mime = format.sampleMimeType ?: return false
        val encoded = mime in setOf(MimeTypes.AUDIO_AC3, MimeTypes.AUDIO_E_AC3, MimeTypes.AUDIO_E_AC3_JOC, MimeTypes.AUDIO_DTS, MimeTypes.AUDIO_DTS_HD, MimeTypes.AUDIO_TRUEHD)
        if (!encoded) return false
        val caps = AudioCapabilities.getCapabilities(this, androidx.media3.common.AudioAttributes.DEFAULT, null)
        return caps.isPassthroughPlaybackSupported(format, androidx.media3.common.AudioAttributes.DEFAULT)
    }

    // ---- Tracks ----

    fun audioOptions(): List<TrackOption> = trackOptions(C.TRACK_TYPE_AUDIO)

    fun subtitleOptions(): List<TrackOption> {
        val p = player ?: return emptyList()
        val tracks = trackOptions(C.TRACK_TYPE_TEXT)
        val off = p.trackSelectionParameters.disabledTrackTypes.contains(C.TRACK_TYPE_TEXT) || tracks.none { it.selected }
        return listOf(TrackOption("off", "Off", off, null, -1)) + tracks.map { if (off) it.copy(selected = false) else it }
    }

    private fun trackOptions(type: Int): List<TrackOption> {
        val p = player ?: return emptyList()
        val out = mutableListOf<TrackOption>()
        p.currentTracks.groups.filter { it.type == type }.forEachIndexed { gi, g ->
            for (i in 0 until g.length) {
                if (!g.isTrackSupported(i)) continue
                val f = g.getTrackFormat(i)
                val lang = f.language?.let { Languages.normalize(it) }?.let { Languages.displayName(it) }
                val extra = buildList {
                    if (type == C.TRACK_TYPE_AUDIO) {
                        audioCodecName(f.sampleMimeType)?.let(::add)
                        if (f.channelCount > 0) add(channelLabel(f.channelCount))
                    }
                    if ((f.selectionFlags and C.SELECTION_FLAG_FORCED) != 0) add("Forced")
                }
                val name = listOfNotNull(f.label?.takeIf { it.isNotBlank() } ?: lang ?: "Track ${out.size + 1}")
                    .plus(extra).joinToString(" · ")
                out += TrackOption("$gi:$i", name, g.isTrackSelected(i), g, i, f.language?.let { Languages.normalize(it) } ?: "und:$gi")
            }
        }
        // "English (external)" twice is ambiguous; number repeats.
        val counts = out.groupingBy { it.label }.eachCount()
        val seen = mutableMapOf<String, Int>()
        return out.map { o ->
            if ((counts[o.label] ?: 0) < 2) o
            else o.copy(label = "${o.label} ${seen.merge(o.label, 1, Int::plus)}")
        }
    }

    /** Selects the next audio track (wrapping) and returns its name. */
    fun cycleAudio(): String {
        val options = audioOptions()
        if (options.isEmpty()) return "No audio tracks"
        if (options.size == 1) return options[0].label
        val next = options[(options.indexOfFirst { it.selected } + 1).mod(options.size)]
        selectTrack(next, C.TRACK_TYPE_AUDIO)
        return next.label
    }

    /** Off → each subtitle language in turn → Off. Returns what's now showing. */
    fun cycleSubtitles(): String {
        val options = subtitleOptions()
        val tracks = options.filter { it.group != null }
        if (tracks.isEmpty()) return "No subtitles found"
        val languages = tracks.map { it.lang }.distinct()
        val current = tracks.firstOrNull { it.selected }?.lang
        val nextLang = if (current == null) languages.first() else languages.getOrNull(languages.indexOf(current) + 1)
        if (nextLang == null) {
            selectTrack(options.first(), C.TRACK_TYPE_TEXT)
            return "Off"
        }
        val track = tracks.first { it.lang == nextLang }
        selectTrack(track, C.TRACK_TYPE_TEXT)
        return track.label.replace(Regex(" \\d+$"), "")
    }

    fun currentAudioLabel(): String = audioOptions().firstOrNull { it.selected }?.label ?: "Default"

    fun currentSubtitleLabel(): String =
        subtitleOptions().firstOrNull { it.selected && it.group != null }?.label?.replace(Regex(" \\d+$"), "") ?: "Off"

    fun selectTrack(option: TrackOption, type: Int) {
        val p = player ?: return
        val builder = p.trackSelectionParameters.buildUpon()
        if (option.group == null) {
            builder.setTrackTypeDisabled(type, true)
        } else {
            builder.setTrackTypeDisabled(type, false)
                .setOverrideForType(TrackSelectionOverride(option.group.mediaTrackGroup, option.index))
        }
        p.trackSelectionParameters = builder.build()
        // Side-loaded subtitle files only deliver lines after a seek once switched on mid-playback.
        if (type == C.TRACK_TYPE_TEXT && option.group != null) p.seekTo(p.currentPosition)
        tracksVersion++
    }

    private fun audioCodecName(mime: String?): String? = when (mime) {
        MimeTypes.AUDIO_AC3 -> "Dolby Digital"
        MimeTypes.AUDIO_E_AC3, MimeTypes.AUDIO_E_AC3_JOC -> "Dolby Digital+"
        MimeTypes.AUDIO_TRUEHD -> "TrueHD"
        MimeTypes.AUDIO_DTS -> "DTS"
        MimeTypes.AUDIO_DTS_HD -> "DTS-HD"
        MimeTypes.AUDIO_AAC -> "AAC"
        MimeTypes.AUDIO_OPUS -> "Opus"
        MimeTypes.AUDIO_FLAC -> "FLAC"
        else -> null
    }

    private fun channelLabel(n: Int) = when (n) { 1 -> "Mono"; 2 -> "Stereo"; 6 -> "5.1"; 8 -> "7.1"; else -> "$n ch" }

    // ---- Next episode / autoplay ----

    private fun loadEpisodes() {
        val m = meta ?: return
        if (m.type != "series") return
        lifecycleScope.launch {
            val full = c.addons.meta("series", m.id) ?: return@launch
            episodes = full.videos
            nextUp = findNext()
        }
    }

    private fun findNext(): Video? {
        val current = episodes.firstOrNull { it.id == videoId } ?: return null
        val sameKind = episodes.filter { ((it.season ?: 0) == 0) == ((current.season ?: 0) == 0) }
        val sorted = sameKind.sortedWith(compareBy({ it.season ?: 0 }, { it.episodeNumber }))
        val today = java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.US).format(java.util.Date())
        return sorted.getOrNull(sorted.indexOfFirst { it.id == videoId } + 1)
            ?.takeIf { v -> v.released?.take(10)?.let { it <= today } != false }
    }

    /** Near the end of a movie or a series' last episode, pick a similar unwatched title. */
    private fun requestRecommendation() {
        val m = meta ?: return
        if (recommendationRequested || nextUp != null || !c.userStore.settings.value.autoplaySimilar) return
        if (durationMs <= 0 || durationMs - positionMs > 4 * 60_000L) return
        if (m.type == "series" && episodes.isEmpty()) return // still loading, or a next episode may exist
        recommendationRequested = true
        lifecycleScope.launch {
            val seen = c.userStore.watched.value + c.userStore.history.value.map { it.meta.id } + m.id
            val disliked = c.userStore.ratings.value.filterValues { it < 0 }.keys
            val recs = runCatching { c.recommender.moreLikeThis(m, exclude = seen + disliked, limit = 10) }.getOrDefault(emptyList())
            nextTitle = recs.firstOrNull { it.meta.id.startsWith("tt") || it.meta.id.startsWith("kitsu:") }?.meta
        }
    }

    private fun maybeShowNextUp() {
        requestRecommendation()
        val next = upNext ?: return
        val settings = c.userStore.settings.value
        if (!settings.autoplayNext || countdownCancelled || countdown != null || stillWatchingPrompt) return
        if (durationMs <= 0) return
        // Start at the credits when we know where they are, otherwise shortly before the end.
        val creditsAt = segments.firstOrNull { it.type == SegmentType.CREDITS && it.startMs > durationMs / 2 }?.startMs
        if (creditsAt != null) {
            if (positionMs < creditsAt) return
        } else if (durationMs - positionMs > NEXT_UP_LEAD_MS) return
        startCountdown(next, settings.autoplayCountdownSec)
    }

    private fun startCountdown(next: Video, seconds: Int) {
        countdownJob?.cancel()
        countdown = seconds
        countdownJob = lifecycleScope.launch {
            while (countdown != null && countdown!! > 0) {
                delay(1_000)
                if (player?.isPlaying == true || player?.playbackState == Player.STATE_ENDED) countdown = (countdown ?: 0) - 1
            }
            if (countdown != null) advance(next, automatic = true)
        }
    }

    fun cancelCountdown() {
        countdownJob?.cancel()
        countdown = null
        countdownCancelled = true
    }

    fun playNextNow() {
        val next = upNext ?: return
        countdownJob?.cancel()
        advance(next, automatic = false)
    }

    private fun onEnded() {
        saveProgress()
        if (sleep == SleepTimer.END_OF_EPISODE) {
            // Sleep timer: stop here instead of rolling into the next episode.
            sleep = SleepTimer.OFF
            finish()
            return
        }
        val next = upNext
        if (next != null && c.userStore.settings.value.autoplayNext && !countdownCancelled) {
            if (countdown == null) startCountdown(next, 0)
        } else {
            finish()
        }
    }

    private fun advance(next: Video, automatic: Boolean) {
        countdown = null
        val settings = c.userStore.settings.value
        if (automatic && settings.stillWatchingPrompt && autoAdvances + 1 > settings.stillWatchingEpisodes) {
            player?.pause()
            stillWatchingPrompt = true
            return
        }
        if (automatic) autoAdvances++ else autoAdvances = 0
        loadEpisode(next)
    }

    fun answerStillWatching(keepWatching: Boolean, dontAskAgain: Boolean = false) {
        stillWatchingPrompt = false
        autoAdvances = 0
        if (dontAskAgain) lifecycleScope.launch { c.userStore.updateSettings { it.copy(stillWatchingPrompt = false) } }
        val next = upNext
        if (!keepWatching || next == null) {
            finish()
            return
        }
        loadEpisode(next)
    }

    private fun loadEpisode(next: Video) {
        saveProgress()
        val switching = nextUp == null && nextTitle != null
        lifecycleScope.launch {
            if (switching) {
                // Moving on to a recommended title: load its full details (episodes for series).
                val t = nextTitle!!
                meta = c.addons.meta(t.type, t.id) ?: t
                episodes = meta?.videos.orEmpty()
                nextTitle = null
                recommendationRequested = false
            }
            val m = meta ?: return@launch
            Toast.makeText(this@PlayerActivity, "Loading ${episodeLabel(next)}…", Toast.LENGTH_SHORT).show()
            com.zemu.tv.ui.components.Haptics.buzz(this@PlayerActivity, com.zemu.tv.ui.components.Haptics.Kind.START)
            val result = c.streams.load(m.type, next.id)
            val settings = c.userStore.settings.value
            val filtered = StreamFilter.apply(result.cached, c.streamFilter.value, c.capabilities, settings, emptySet())
                .ifEmpty { StreamFilter.apply(result.cached, FilterState(), c.capabilities, settings, emptySet()) }
                .map { it.stream }
            if (filtered.isEmpty()) {
                Toast.makeText(this@PlayerActivity, "No cached streams for ${episodeLabel(next)} yet", Toast.LENGTH_LONG).show()
                finish()
                return@launch
            }
            // Same release group first, so quality and audio don't jump between episodes.
            val group = candidates.getOrNull(index)?.bingeGroup
            val ordered = if (group == null) filtered else filtered.sortedByDescending { it.raw.behaviorHints?.bingeGroup == group }
            candidates = ordered.take(5).map { it.toCandidate() }
            subs = Playback.pickSubtitles(c.streams.subtitles(m.type, next.id), settings.subtitleLanguages)
            videoId = next.id
            segments = emptyList()
            segmentsFor = null
            activeSegment = null
            dismissedSegment = null
            val ep = episodes.firstOrNull { it.id == next.id } ?: next
            label = if (switching && m.type != "series") null else episodeLabel(ep)
            index = 0
            mode = startMode
            countdownCancelled = false
            positionMs = 0
            durationMs = 0
            start(0)
            nextUp = findNext()
        }
    }

    private fun episodeLabel(v: Video) = if (v.season != null) "S${v.season} E${v.episodeNumber} · ${v.displayTitle}" else v.displayTitle

    // ---- Errors / decoder fallback ----

    private fun handleError(error: PlaybackException) {
        val position = player?.currentPosition?.takeIf { it > 0 } ?: resumeMs
        val next = escalate(error)
        if (next != null) {
            mode = next
            Toast.makeText(this, "Couldn't decode (${error.errorCodeName}). Retrying with ${next.describe()}…", Toast.LENGTH_SHORT).show()
            start(position)
            return
        }
        if (index + 1 < candidates.size) {
            index++
            mode = startMode
            Toast.makeText(this, "Stream failed, trying the next one: ${candidates[index].label}", Toast.LENGTH_LONG).show()
            start(position)
            return
        }
        showFailure(error, position)
    }

    private fun escalate(error: PlaybackException): DecoderMode? {
        val isDecoderError = error.errorCode in PlaybackException.ERROR_CODE_DECODER_INIT_FAILED..PlaybackException.ERROR_CODE_DECODING_FORMAT_UNSUPPORTED ||
            (error as? ExoPlaybackException)?.type == ExoPlaybackException.TYPE_RENDERER
        if (!isDecoderError) return null
        val mime = (error as? ExoPlaybackException)?.rendererFormat?.sampleMimeType
        val isAudio = mime != null && MimeTypes.isAudio(mime)
        return when {
            isAudio && !mode.ffmpegAudio -> mode.copy(ffmpegAudio = true)
            isAudio -> null
            !mode.avoidDolbyVision -> mode.copy(avoidDolbyVision = true)
            !mode.softwareVideo -> mode.copy(softwareVideo = true)
            !mode.ffmpegAudio -> mode.copy(ffmpegAudio = true)
            else -> null
        }
    }

    private fun rememberWorkingMode() {
        if (mode == startMode) return
        val learnDv = mode.avoidDolbyVision && !startMode.avoidDolbyVision
        val learnSw = mode.softwareVideo && !startMode.softwareVideo
        if (!learnDv && !learnSw) return
        c.appScope.launch {
            c.userStore.updateSettings {
                it.copy(avoidDolbyVision = it.avoidDolbyVision || learnDv, preferSoftwareDecoders = it.preferSoftwareDecoders || learnSw)
            }
        }
        startMode = mode
        val what = listOfNotNull("play Dolby Vision as HDR10".takeIf { learnDv }, "prefer software decoders".takeIf { learnSw }).joinToString(" and ")
        Toast.makeText(this, "Playing. This TV will now $what (change in Settings).", Toast.LENGTH_LONG).show()
    }

    private fun showFailure(error: PlaybackException, position: Long) {
        player?.pause()
        val format = (error as? ExoPlaybackException)?.rendererFormat
        val detail = buildString {
            append(error.errorCodeName)
            format?.let { f ->
                append("\n").append(listOfNotNull(f.sampleMimeType, f.codecs, if (f.height > 0) "${f.width}x${f.height}" else null).joinToString(" · "))
            }
            error.cause?.message?.takeIf { it.isNotBlank() }?.let { append("\n").append(it.take(200)) }
        }
        AlertDialog.Builder(this, android.R.style.Theme_DeviceDefault_Dialog_Alert)
            .setTitle("This video can't be played here")
            .setMessage("Tried ${candidates.size} stream(s) with every decoder fallback.\n\n$detail")
            .setPositiveButton("External player") { _, _ ->
                if (!Playback.openExternal(this, candidates[index].url, title, position)) {
                    Toast.makeText(this, "Install VLC or Just Player to use an external player", Toast.LENGTH_LONG).show()
                }
                finish()
            }
            .setNeutralButton("Retry") { _, _ ->
                index = 0
                mode = startMode
                start(position)
            }
            .setNegativeButton("Back") { _, _ -> finish() }
            .setOnCancelListener { finish() }
            .show()
    }

    private fun subtitleMime(url: String): String {
        val path = url.substringBefore('?').lowercase()
        return when {
            path.endsWith(".vtt") -> MimeTypes.TEXT_VTT
            path.endsWith(".ass") || path.endsWith(".ssa") -> MimeTypes.TEXT_SSA
            else -> MimeTypes.APPLICATION_SUBRIP
        }
    }

    // ---- Like / My List ----

    fun rate(value: Int) {
        val m = meta ?: return
        lifecycleScope.launch { c.userStore.rate(m, value) }
    }

    fun toggleMyList() {
        val m = meta ?: return
        lifecycleScope.launch { c.userStore.toggleMyList(m) }
    }

    private fun saveProgress() {
        val p = player ?: return
        val m = meta ?: return
        val duration = p.duration.takeIf { it != C.TIME_UNSET && it > 0 } ?: return
        val entry = WatchEntry(m, videoId, label, p.currentPosition, duration, System.currentTimeMillis())
        c.appScope.launch { c.userStore.recordProgress(entry) }
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        // Any remote input means someone is watching.
        if (event.action == KeyEvent.ACTION_DOWN) autoAdvances = 0
        return super.dispatchKeyEvent(event)
    }

    override fun onPause() {
        super.onPause()
        saveProgress()
        player?.pause()
    }

    override fun onResume() {
        super.onResume()
        if (!stillWatchingPrompt) player?.play()
    }

    override fun onDestroy() {
        saveProgress()
        player?.release()
        player = null
        super.onDestroy()
    }

    companion object {
        private val SCRUB_STEPS = intArrayOf(15, 15, 30, 30, 45, 60)
        /** Show the "Next episode" card this long before the end (roughly where credits start). */
        private const val NEXT_UP_LEAD_MS = 40_000L
    }
}

/** Sleep timer choices, cycled from the player's More menu. */
enum class SleepTimer(val label: String, val minutes: Int?) {
    OFF("Off", null), M15("15 min", 15), M30("30 min", 30), M60("1 hour", 60), M90("90 min", 90), END_OF_EPISODE("End of episode", null)
}
