package com.zemu.tv.player

import android.os.SystemClock
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.wrapContentSize
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.animation.core.animateFloat
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEvent
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.tv.material3.Icon
import androidx.tv.material3.Text
import com.zemu.tv.container
import com.zemu.tv.ui.components.AppIcons
import com.zemu.tv.ui.components.FocusSurface
import com.zemu.tv.ui.components.SubtitleStyleEditor
import com.zemu.tv.ui.components.TvButton
import com.zemu.tv.ui.theme.Palette
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

private enum class PlayerDialog { SUBTITLE_STYLE, AUDIO, SUBTITLES }

/** Track panel opened from Audio (left column focused) or Subtitles (right column). */

private const val STYLE_OPTION = "__style"

private val SPEEDS = listOf(0.5f, 0.75f, 1f, 1.25f, 1.5f, 2f)

fun formatTime(ms: Long): String {
    val total = (ms / 1000).coerceAtLeast(0)
    val h = total / 3600
    val m = (total % 3600) / 60
    val s = total % 60
    return if (h > 0) "%d:%02d:%02d".format(h, m, s) else "%d:%02d".format(m, s)
}

/**
 * Player UI. With the menu hidden: OK pauses and opens the menu, Left/Right scrub, Up/Down open
 * the menu, Back exits. With the menu open: Back (or Up from the seek bar) closes it.
 */
@Composable
fun PlayerScreen(a: PlayerActivity) {
    val c = a.container
    val scope = androidx.compose.runtime.rememberCoroutineScope()
    val settings by c.userStore.settings.collectAsStateWithLifecycle()
    val myList by c.userStore.myList.collectAsStateWithLifecycle()
    val ratings by c.userStore.ratings.collectAsStateWithLifecycle()
    val meta = a.meta
    val inMyList = meta != null && myList.any { it.id == meta.id }
    val rating = meta?.let { ratings[it.id] } ?: 0

    var menu by remember { mutableStateOf(false) }
    var focusTarget by remember { mutableStateOf("play") }
    var dialog by remember { mutableStateOf<PlayerDialog?>(null) }
    var lastInteraction by remember { mutableLongStateOf(0L) }
    var swallowCenterUp by remember { mutableStateOf(false) }
    val rootFocus = remember { FocusRequester() }
    val playFocus = remember { FocusRequester() }
    val seekFocus = remember { FocusRequester() }
    val nextFocus = remember { FocusRequester() }
    val skipFocus = remember { FocusRequester() }
    val aspect = runCatching { AspectMode.valueOf(settings.aspectMode) }.getOrDefault(AspectMode.FIT)
    val cardVisible = a.countdown != null
    // "Skip credits" bubble: takes focus while it's up, so Left/Right move between its buttons
    // instead of seeking.
    val skipVisible = a.activeSegment != null && !menu && !cardVisible && dialog == null && !a.stillWatchingPrompt
    val hidden = !menu && dialog == null && !cardVisible && !a.stillWatchingPrompt && !skipVisible

    fun openMenu(target: String) {
        focusTarget = target
        menu = true
        lastInteraction = SystemClock.uptimeMillis()
    }

    LaunchedEffect(menu, focusTarget, cardVisible, skipVisible) {
        delay(60)
        runCatching {
            when {
                cardVisible && !menu -> nextFocus.requestFocus()
                skipVisible -> skipFocus.requestFocus()
                menu -> (if (focusTarget == "seek") seekFocus else playFocus).requestFocus()
                else -> rootFocus.requestFocus()
            }
        }
    }
    // Hide the menu after a few idle seconds while playing.
    LaunchedEffect(menu, lastInteraction, a.isPlaying, dialog) {
        if (menu && a.isPlaying && dialog == null) {
            delay(4_000)
            menu = false
        }
    }
    LaunchedEffect(aspect, a.playerView) { a.setAspect(aspect) }
    // Paused and untouched for 10 minutes: dim to the title's artwork, like a screensaver.
    var pauseSaver by remember { mutableStateOf(false) }
    LaunchedEffect(a.isPlaying, a.buffering, lastInteraction) {
        pauseSaver = false
        if (!a.isPlaying && !a.buffering) { delay(10 * 60_000L); pauseSaver = true }
    }


    Box(
        Modifier
            .fillMaxSize()
            .background(Color.Black)
            .onPreviewKeyEvent { e ->
                lastInteraction = SystemClock.uptimeMillis()
                // The first button press only wakes the paused screen.
                if (pauseSaver) return@onPreviewKeyEvent true
                // Compose would otherwise use Back to move focus out of the menu instead of closing it.
                if (e.key == Key.Back && dialog == null && (menu || cardVisible || skipVisible)) {
                    if (e.type == KeyEventType.KeyUp) {
                        when {
                            menu -> menu = false
                            cardVisible -> a.cancelCountdown()
                            else -> a.dismissSegment()
                        }
                    }
                    return@onPreviewKeyEvent true
                }
                handleMediaKeys(a, e) ?: if (hidden) handleHiddenKeys(a, e, ::openMenu, { swallowCenterUp = it }, swallowCenterUp) else false
            }
            .focusRequester(rootFocus)
            .focusable()
            // Touch: tap the video to show the controls, tap again (outside a button) to hide them.
            .pointerInput(Unit) {
                detectTapGestures(onTap = {
                    lastInteraction = SystemClock.uptimeMillis()
                    if (menu) menu = false else if (dialog == null && !a.stillWatchingPrompt) {
                        focusTarget = "play"
                        menu = true
                    }
                })
            },
    ) {
        VideoSurface(a, aspect)

        if (a.buffering && !menu) {
            Text("Loading…", color = Color.White.copy(alpha = 0.8f), fontSize = 16.sp, modifier = Modifier.align(Alignment.Center))
        }

        // Scrub preview when the menu is hidden.
        val now = SystemClock.uptimeMillis()
        AnimatedVisibility(
            visible = !menu && (a.scrubTargetMs != null || now < a.scrubShownUntil),
            enter = fadeIn(), exit = fadeOut(),
            modifier = Modifier.align(Alignment.BottomCenter),
        ) {
            Column(
                Modifier
                    .fillMaxWidth()
                    .background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.85f))))
                    .padding(horizontal = 48.dp, vertical = 28.dp),
            ) {
                SeekBar(a, focused = false)
            }
        }
        // Keep the scrub bar's visibility timer ticking.
        LaunchedEffect(a.scrubShownUntil) {
            while (SystemClock.uptimeMillis() < a.scrubShownUntil) delay(250)
            lastInteraction = SystemClock.uptimeMillis()
        }

        AnimatedVisibility(visible = menu, enter = fadeIn(), exit = fadeOut(), modifier = Modifier.fillMaxSize()) {
            Box(Modifier.fillMaxSize()) {
                // Top: title
                Row(
                    Modifier
                        .fillMaxWidth()
                        .background(Brush.verticalGradient(listOf(Color.Black.copy(alpha = 0.8f), Color.Transparent)))
                        .padding(horizontal = 48.dp, vertical = 28.dp),
                ) {
                    Column(Modifier.weight(1f)) {
                        Text(a.title, fontSize = 26.sp, fontWeight = FontWeight.Black, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        a.label?.let { Text(it, fontSize = 16.sp, color = Palette.TextSecondary, maxLines = 1) }
                        Text(a.streamLabel, fontSize = 13.sp, color = Palette.TextMuted, maxLines = 1)
                    }
                    // Clock and when this ends at the current speed.
                    Column(horizontalAlignment = Alignment.End) {
                        val context = androidx.compose.ui.platform.LocalContext.current
                        val fmt = remember { android.text.format.DateFormat.getTimeFormat(context) }
                        val now = System.currentTimeMillis()
                        Text(fmt.format(java.util.Date(now)), fontSize = 22.sp, fontWeight = FontWeight.Bold)
                        if (a.durationMs > 0) {
                            val left = ((a.durationMs - a.positionMs) / a.speed).toLong()
                            Text("Ends at ${fmt.format(java.util.Date(now + left))}", fontSize = 14.sp, color = Palette.TextSecondary)
                        }
                    }
                }
                // Bottom: seek bar + menu bar
                Column(
                    Modifier
                        .align(Alignment.BottomCenter)
                        .fillMaxWidth()
                        .background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.9f))))
                        .padding(start = 48.dp, end = 48.dp, top = 60.dp, bottom = 28.dp),
                ) {
                    var seekFocused by remember { mutableStateOf(false) }
                    Box(
                        Modifier
                            .focusRequester(seekFocus)
                            .onFocusChanged { seekFocused = it.isFocused }
                            .onPreviewKeyEvent { e ->
                                if (e.type != KeyEventType.KeyDown) return@onPreviewKeyEvent false
                                when (e.key) {
                                    Key.DirectionLeft -> { a.scrub(-1, e.nativeKeyEvent.repeatCount); true }
                                    Key.DirectionRight -> { a.scrub(1, e.nativeKeyEvent.repeatCount); true }
                                    Key.DirectionUp -> { menu = false; true }
                                    Key.DirectionCenter, Key.Enter -> { a.togglePlay(); true }
                                    else -> false
                                }
                            }
                            .focusable(),
                    ) {
                        SeekBar(a, focused = seekFocused)
                    }
                    Spacer(Modifier.height(18.dp))
                    MenuBar(
                        a = a,
                        playFocus = playFocus,
                        inMyList = inMyList,
                        rating = rating,
                        speedLabel = a.speed.let { if (it == 1f) "1x" else "${it}x" },
                        aspect = aspect,
                        onDialog = { dialog = it },
                        onToggleMyList = { a.toggleMyList() },
                    )
                }
            }
        }

        a.upNext?.takeIf { cardVisible }?.let { next ->
            val recommended = a.nextUp == null
            NextUpCard(
                heading = if (recommended) "Up next · recommended for you" else "Next episode",
                title = if (recommended) next.displayTitle else "S${next.season ?: 0} E${next.episodeNumber} · ${next.displayTitle}",
                seconds = a.countdown ?: 0,
                focus = nextFocus,
                onPlay = { a.playNextNow() },
                onCancel = { a.cancelCountdown() },
                modifier = Modifier.align(Alignment.BottomEnd).padding(40.dp),
            )
        }

        a.activeSegment?.takeIf { skipVisible }?.let { seg ->
            SkipBubble(
                label = seg.type.skipLabel,
                focus = skipFocus,
                onSkip = { a.skipSegment() },
                onCancel = { a.dismissSegment() },
                onMenu = { openMenu("seek") },
                modifier = Modifier.align(Alignment.BottomEnd).padding(end = 40.dp, bottom = 48.dp),
            )
        }

        if (a.stillWatchingPrompt) StillWatchingDialog(a)

        androidx.compose.animation.AnimatedVisibility(pauseSaver, enter = fadeIn(androidx.compose.animation.core.tween(1500)), exit = fadeOut(), modifier = Modifier.fillMaxSize()) {
            PausedSaver(a)
        }
    }

    when (dialog) {
        PlayerDialog.SUBTITLE_STYLE -> SubtitleStyleDialog(settings, update = { t -> scope.launch { c.userStore.updateSettings(t) } }) { dialog = null }
        PlayerDialog.AUDIO, PlayerDialog.SUBTITLES -> TrackPanel(
            a,
            focusSubtitles = dialog == PlayerDialog.SUBTITLES,
            onStyle = { dialog = PlayerDialog.SUBTITLE_STYLE },
            onDismiss = { dialog = null },
        )
        null -> {}
    }
}

/** Play/pause and seek keys work in every state. Returns null when the key isn't one of them. */
private fun handleMediaKeys(a: PlayerActivity, e: KeyEvent): Boolean? {
    val down = e.type == KeyEventType.KeyDown
    return when (e.key) {
        Key.MediaPlayPause, Key.MediaPlay, Key.MediaPause -> { if (down) a.togglePlay(); true }
        Key.MediaFastForward, Key.ButtonR1 -> { holdScrub(a, e, 1); true }
        Key.MediaRewind, Key.ButtonL1 -> { holdScrub(a, e, -1); true }
        else -> null
    }
}

/** A tap jumps one step; holding scrubs smoothly, faster the longer it's held, until released. */
private fun holdScrub(a: PlayerActivity, e: KeyEvent, direction: Int) {
    when {
        e.type == KeyEventType.KeyUp -> a.stopHoldScrub()
        e.type != KeyEventType.KeyDown -> {}
        e.nativeKeyEvent.repeatCount == 0 -> a.scrub(direction, 0)
        else -> a.startHoldScrub(direction)
    }
}

private fun handleHiddenKeys(
    a: PlayerActivity,
    e: KeyEvent,
    openMenu: (String) -> Unit,
    setSwallow: (Boolean) -> Unit,
    swallow: Boolean,
): Boolean {
    val center = e.key == Key.DirectionCenter || e.key == Key.Enter || e.key == Key.NumPadEnter
    if (e.type == KeyEventType.KeyUp) {
        if (center && swallow) { setSwallow(false); return true }
        return false
    }
    return when {
        center -> {
            // OK pauses (or resumes) and shows the menu. Its key-up must not click the focused button.
            if (e.nativeKeyEvent.repeatCount == 0) {
                a.togglePlay()
                setSwallow(true)
                openMenu("play")
            }
            true
        }
        e.key == Key.DirectionLeft -> { a.scrub(-1, e.nativeKeyEvent.repeatCount); true }
        e.key == Key.DirectionRight -> { a.scrub(1, e.nativeKeyEvent.repeatCount); true }
        e.key == Key.DirectionUp || e.key == Key.DirectionDown -> { openMenu("seek"); true }
        else -> false
    }
}

@Composable
private fun VideoSurface(a: PlayerActivity, aspect: AspectMode) {
    BoxWithConstraints(Modifier.fillMaxSize().clipToBounds(), contentAlignment = Alignment.Center) {
        val density = LocalDensity.current
        val size = a.videoSize
        // Center: original pixel size, shrunk only if it doesn't fit.
        val modifier = when {
            aspect == AspectMode.CENTER && size != null -> {
                val w = with(density) { size.width.toDp() }
                val h = with(density) { size.height.toDp() }
                val scale = minOf(1f, maxWidth / w, maxHeight / h)
                Modifier.size(w * scale, h * scale)
            }
            // Lay the video out larger than the screen; the edges are cropped. Works with
            // SurfaceView, which ignores view scaling.
            aspect.zoom > 1f -> Modifier.wrapContentSize(unbounded = true).requiredSize(maxWidth * aspect.zoom, maxHeight * aspect.zoom)
            else -> Modifier.fillMaxSize()
        }
        AndroidView(factory = { ctx -> a.createPlayerView(ctx) }, modifier = modifier)
    }
}

@Composable
private fun SeekBar(a: PlayerActivity, focused: Boolean) {
    val duration = a.durationMs.coerceAtLeast(1)
    val target = a.scrubTargetMs
    val shown = target ?: a.positionMs
    Column {
        if (target != null) {
            val delta = target - a.positionMs
            Text(
                "${formatTime(target)}   (${if (delta >= 0) "+" else "−"}${formatTime(kotlin.math.abs(delta))})",
                fontSize = 18.sp, fontWeight = FontWeight.Bold,
            )
            Spacer(Modifier.height(6.dp))
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(formatTime(shown), fontSize = if (target != null) 20.sp else 14.sp, fontWeight = if (target != null) FontWeight.Bold else FontWeight.Normal, modifier = Modifier.width(96.dp))
            BoxWithConstraints(
                Modifier
                    .weight(1f)
                    .height(if (focused) 10.dp else 6.dp)
                    // Touch: tap anywhere on the bar to jump there (generous hit area).
                    .pointerInput(duration) {
                        detectTapGestures { o -> a.seekBy((o.x / size.width * duration).toLong() - a.positionMs) }
                    },
                contentAlignment = Alignment.CenterStart,
            ) {
                val w = maxWidth
                Box(Modifier.fillMaxSize().background(Color.White.copy(alpha = 0.25f), RoundedCornerShape(5.dp)))
                Box(Modifier.width(w * (a.bufferedMs.toFloat() / duration).coerceIn(0f, 1f)).fillMaxSize().background(Color.White.copy(alpha = 0.35f), RoundedCornerShape(5.dp)))
                Box(Modifier.width(w * (a.positionMs.toFloat() / duration).coerceIn(0f, 1f)).fillMaxSize().background(Palette.Accent, RoundedCornerShape(5.dp)))
                // Intro / recap / credits, so you can see where they are while scrubbing.
                a.markers.forEach { seg ->
                    val start = (seg.startMs.toFloat() / duration).coerceIn(0f, 1f)
                    val end = ((seg.endMs ?: a.durationMs).toFloat() / duration).coerceIn(start, 1f)
                    Box(Modifier.offset(x = w * start).width(w * (end - start)).fillMaxSize().background(Color(0xFFFFC94D).copy(alpha = 0.55f)))
                }
                val knob = if (focused || target != null) 18.dp else 12.dp
                Box(
                    Modifier
                        .offset(x = w * (shown.toFloat() / duration).coerceIn(0f, 1f) - knob / 2)
                        .size(knob)
                        .background(if (target != null) Color.White else Palette.Accent, CircleShape)
                        .border(2.dp, Color.White, CircleShape),
                )
            }
            Text(
                "-" + formatTime(a.durationMs - shown),
                fontSize = 14.sp,
                modifier = Modifier.width(86.dp).padding(start = 12.dp),
            )
        }
        if (focused) Text("◀ ▶ to scrub (hold to go faster)  ·  ▲ to hide", fontSize = 12.sp, color = Palette.TextMuted, modifier = Modifier.padding(top = 6.dp))
    }
}

private data class MenuItem(
    val key: String,
    /** Short name under the button, and the current value (second line) if any. */
    val label: String,
    val value: String? = null,
    val icon: ImageVector,
    val active: Boolean = false,
    val onLongClick: (() -> Unit)? = null,
    val onClick: () -> Unit,
)

/** Every player control in one row, each labeled with its current setting. */
@Composable
private fun MenuBar(
    a: PlayerActivity,
    playFocus: FocusRequester,
    inMyList: Boolean,
    rating: Int,
    speedLabel: String,
    aspect: AspectMode,
    onDialog: (PlayerDialog) -> Unit,
    onToggleMyList: () -> Unit,
) {
    val scope = androidx.compose.runtime.rememberCoroutineScope()
    @Suppress("UNUSED_VARIABLE") val tv = a.tracksVersion // re-read track labels when tracks change
    val sub = a.currentSubtitleLabel()
    val items = buildList {
        add(MenuItem("play", if (a.isPlaying) "Pause" else "Play", icon = if (a.isPlaying) AppIcons.Pause else AppIcons.Play) { a.togglePlay() })
        add(MenuItem("back10", "−10s", icon = AppIcons.Rewind) { a.seekBy(-10_000) })
        add(MenuItem("fwd10", "+10s", icon = AppIcons.Forward) { a.seekBy(10_000) })
        if (a.nextUp != null) add(MenuItem("next", "Next", "episode", AppIcons.Next) { a.playNextNow() })
        add(MenuItem("audio", "Audio", a.currentAudioLabel(), AppIcons.Audio, onLongClick = { onDialog(PlayerDialog.AUDIO) }) { a.cycleAudio() })
        add(MenuItem("subs", "Subtitles", sub, AppIcons.Subtitles, active = sub != "Off", onLongClick = { onDialog(PlayerDialog.SUBTITLES) }) { a.cycleSubtitles() })
        add(MenuItem("speed", "Speed", speedLabel, AppIcons.Speed, active = speedLabel != "1x") {
            val i = SPEEDS.indexOf(a.speed)
            a.changeSpeed(SPEEDS[(i + 1).mod(SPEEDS.size)])
        })
        add(MenuItem("aspect", "Picture", aspect.label, AppIcons.Aspect, active = aspect != AspectMode.FIT) {
            val next = AspectMode.entries[(aspect.ordinal + 1) % AspectMode.entries.size]
            scope.launch { a.container.userStore.updateSettings { it.copy(aspectMode = next.name) } }
        })
        add(MenuItem("sleep", "Sleep", a.sleepShort(), AppIcons.Sleep, active = a.sleep != SleepTimer.OFF) { a.cycleSleepTimer() })
        add(MenuItem("like", if (rating > 0) "Liked" else "Like", icon = AppIcons.ThumbUp, active = rating > 0) { a.rate(if (rating > 0) 0 else 1) })
        add(MenuItem("dislike", if (rating < 0) "Disliked" else "Dislike", icon = AppIcons.ThumbDown, active = rating < 0) { a.rate(if (rating < 0) 0 else -1) })
        add(MenuItem("fav", "My List", if (inMyList) "Added" else null, if (inMyList) AppIcons.Heart else AppIcons.HeartOutline, active = inMyList) { onToggleMyList() })
    }
    var focusedKey by remember { mutableStateOf<String?>(null) }
    Column {
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.Top) {
            items.forEach { item ->
                Column(Modifier.width(98.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    FocusSurface(
                        onClick = item.onClick,
                        onLongClick = item.onLongClick,
                        modifier = Modifier
                            .size(54.dp)
                            .onFocusChanged { if (it.isFocused) focusedKey = item.key }
                            .then(if (item.key == "play") Modifier.focusRequester(playFocus) else Modifier),
                        shape = CircleShape,
                        // Dark buttons; "on" shows as an accent icon, focus as the accent fill.
                        containerColor = Color(0xFF1E1E24).copy(alpha = 0.85f),
                        contentColor = if (item.active) Palette.Accent else Color.White,
                        focusedScale = 1.12f,
                    ) {
                        Icon(item.icon, contentDescription = item.label, modifier = Modifier.align(Alignment.Center).size(26.dp))
                    }
                    val focused = focusedKey == item.key
                    Text(item.label, fontSize = 12.sp, fontWeight = if (focused) FontWeight.Bold else FontWeight.Medium, maxLines = 1,
                        color = if (focused) Color.White else Color.White.copy(alpha = 0.75f), modifier = Modifier.padding(top = 6.dp))
                    item.value?.let {
                        Text(it, fontSize = 11.sp, maxLines = 1, overflow = TextOverflow.Ellipsis,
                            color = if (item.active) Palette.Accent else Color.White.copy(alpha = 0.55f))
                    }
                }
            }
        }
        Text("Hold OK on Audio or Subtitles to see every track", fontSize = 12.sp, color = Color.White.copy(alpha = 0.5f), modifier = Modifier.padding(top = 8.dp))
    }
}

/**
 * Audio and subtitle tracks side by side, so both can be changed in one place. Opened by holding OK
 * on Audio or Subtitles; Back closes it.
 */
@Composable
private fun TrackPanel(a: PlayerActivity, focusSubtitles: Boolean, onStyle: () -> Unit, onDismiss: () -> Unit) {
    @Suppress("UNUSED_VARIABLE") val tv = a.tracksVersion
    val audio = a.audioOptions()
    val subs = a.subtitleOptions()
    val audioFocus = remember { FocusRequester() }
    val subsFocus = remember { FocusRequester() }
    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.CenterEnd) {
            Row(
                Modifier
                    .padding(end = 32.dp)
                    .width(760.dp)
                    .heightIn(max = 620.dp)
                    .background(Palette.Surface.copy(alpha = 0.96f), RoundedCornerShape(16.dp))
                    .padding(20.dp),
                horizontalArrangement = Arrangement.spacedBy(20.dp),
            ) {
                TrackColumn("Audio", audio, Modifier.weight(1f), audioFocus) { a.selectTrack(it, androidx.media3.common.C.TRACK_TYPE_AUDIO) }
                TrackColumn("Subtitles", subs, Modifier.weight(1f), subsFocus, footer = "Subtitle style…" to onStyle) {
                    a.selectTrack(it, androidx.media3.common.C.TRACK_TYPE_TEXT)
                }
            }
        }
    }
    LaunchedEffect(Unit) { delay(80); runCatching { (if (focusSubtitles) subsFocus else audioFocus).requestFocus() } }
}

@Composable
private fun TrackColumn(
    title: String,
    options: List<TrackOption>,
    modifier: Modifier,
    focus: FocusRequester,
    footer: Pair<String, () -> Unit>? = null,
    onPick: (TrackOption) -> Unit,
) {
    Column(modifier) {
        Text(title, fontSize = 18.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(start = 8.dp, bottom = 8.dp))
        androidx.compose.foundation.lazy.LazyColumn(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            itemsIndexed(options, key = { _, o -> o.key }) { i, o ->
                val first = (options.indexOfFirst { it.selected }.takeIf { it >= 0 } ?: 0) == i
                FocusSurface(
                    onClick = { onPick(o) },
                    modifier = Modifier.fillMaxWidth().then(if (first) Modifier.focusRequester(focus) else Modifier),
                    shape = RoundedCornerShape(10.dp),
                    containerColor = if (o.selected) Palette.SurfaceHigh else Color.Transparent,
                    focusedScale = 1.02f,
                ) {
                    Text((if (o.selected) "✓  " else "     ") + o.label, fontSize = 15.sp, maxLines = 1, overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.padding(horizontal = 12.dp, vertical = 10.dp))
                }
            }
            if (footer != null) item(key = "footer") {
                FocusSurface(onClick = footer.second, modifier = Modifier.fillMaxWidth().padding(top = 8.dp), shape = RoundedCornerShape(10.dp), focusedScale = 1.02f) {
                    Text(footer.first, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(horizontal = 12.dp, vertical = 10.dp))
                }
            }
        }
    }
}

/**
 * Compact "Skip intro / credits" bubble with a Cancel button. "Skip" is focused when it appears;
 * Right moves to Cancel, Up/Down open the player menu, Back dismisses it.
 */
@Composable
private fun SkipBubble(label: String, focus: FocusRequester, onSkip: () -> Unit, onCancel: () -> Unit, onMenu: () -> Unit, modifier: Modifier) {
    Row(
        modifier
            .background(Color.Black.copy(alpha = 0.55f), RoundedCornerShape(12.dp))
            .padding(6.dp)
            .onPreviewKeyEvent { e ->
                if (e.type == KeyEventType.KeyDown && (e.key == Key.DirectionUp || e.key == Key.DirectionDown)) { onMenu(); true } else false
            },
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        BubbleButton(onClick = onSkip, modifier = Modifier.focusRequester(focus)) {
            Icon(AppIcons.Next, contentDescription = null, modifier = Modifier.size(18.dp), tint = androidx.tv.material3.LocalContentColor.current)
            Spacer(Modifier.width(6.dp))
            Text(label, fontSize = 15.sp, fontWeight = FontWeight.Bold)
        }
        BubbleButton(onClick = onCancel) {
            Text("Cancel", fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
        }
    }
}

@Composable
private fun BubbleButton(onClick: () -> Unit, modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    FocusSurface(
        onClick = onClick,
        modifier = modifier,
        shape = RoundedCornerShape(8.dp),
        focusedScale = 1.04f,
        containerColor = Color(0xFF1E1E24).copy(alpha = 0.85f),
        contentColor = Color.White,
    ) {
        Row(Modifier.padding(horizontal = 14.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) { content() }
    }
}

@Composable
private fun NextUpCard(heading: String, title: String, seconds: Int, focus: FocusRequester, onPlay: () -> Unit, onCancel: () -> Unit, modifier: Modifier) {
    Column(
        modifier
            .width(380.dp)
            .background(Palette.Surface.copy(alpha = 0.95f), RoundedCornerShape(14.dp))
            .padding(20.dp),
    ) {
        Text(heading, color = Palette.TextSecondary, fontSize = 13.sp)
        Text(title, fontSize = 18.sp, fontWeight = FontWeight.Bold, maxLines = 2, overflow = TextOverflow.Ellipsis)
        Text(if (seconds > 0) "Playing in ${seconds}s" else "Starting…", color = Palette.TextSecondary, fontSize = 14.sp, modifier = Modifier.padding(top = 4.dp))
        Spacer(Modifier.height(14.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            TvButton("Play now", onClick = onPlay, primary = true, modifier = Modifier.focusRequester(focus))
            TvButton("Cancel", onClick = onCancel)
        }
    }
}

@Composable
private fun StillWatchingDialog(a: PlayerActivity) {
    val first = remember { FocusRequester() }
    Dialog(onDismissRequest = { a.answerStillWatching(keepWatching = false) }, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Column(
            Modifier
                .width(520.dp)
                .background(Palette.Surface, RoundedCornerShape(16.dp))
                .padding(28.dp),
        ) {
            Text("Are you still watching?", fontSize = 26.sp, fontWeight = FontWeight.Black)
            Text(a.title, color = Palette.TextSecondary, fontSize = 15.sp, modifier = Modifier.padding(top = 4.dp, bottom = 20.dp))
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                TvButton("Continue watching", primary = true, onClick = { a.answerStillWatching(true) }, modifier = Modifier.fillMaxWidth().focusRequester(first))
                TvButton("Continue and don't ask again", onClick = { a.answerStillWatching(true, dontAskAgain = true) }, modifier = Modifier.fillMaxWidth())
                TvButton("Back to browsing", onClick = { a.answerStillWatching(false) }, modifier = Modifier.fillMaxWidth())
            }
        }
    }
    LaunchedEffect(Unit) {
        delay(80)
        runCatching { first.requestFocus() }
    }
}

@Composable
private fun SubtitleStyleDialog(
    settings: com.zemu.tv.data.AppSettings,
    update: ((com.zemu.tv.data.AppSettings) -> com.zemu.tv.data.AppSettings) -> Unit,
    onDismiss: () -> Unit,
) {
    // Dimmed only at the top so the subtitles behind stay visible as a live preview.
    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        // Pinned to the top so the subtitles at the bottom stay visible as a live preview.
        Box(Modifier.fillMaxSize().padding(top = 24.dp), contentAlignment = Alignment.TopCenter) {
            Column(
                Modifier
                    .width(820.dp)
                    .background(Palette.Surface.copy(alpha = 0.92f), RoundedCornerShape(16.dp))
                    .padding(horizontal = 24.dp, vertical = 14.dp),
            ) {
                Text("Subtitle style  ·  changes apply right away, Back to close", fontSize = 15.sp, fontWeight = FontWeight.Bold)
                SubtitleStyleEditor(settings, update)
            }
        }
    }
}

/** Shown over a video paused for a long time: its artwork drifting slowly, dimmed. */
@Composable
private fun PausedSaver(a: PlayerActivity) {
    val drift = androidx.compose.animation.core.rememberInfiniteTransition(label = "paused")
    val scale by drift.animateFloat(1f, 1.12f, androidx.compose.animation.core.infiniteRepeatable(androidx.compose.animation.core.tween(40_000), androidx.compose.animation.core.RepeatMode.Reverse), label = "zoom")
    val m = a.meta
    Box(Modifier.fillMaxSize().background(Color.Black)) {
        coil.compose.AsyncImage(
            model = m?.background ?: m?.poster,
            contentDescription = null,
            contentScale = androidx.compose.ui.layout.ContentScale.Crop,
            modifier = Modifier.fillMaxSize().graphicsLayer { scaleX = scale; scaleY = scale; alpha = 0.45f },
        )
        Column(Modifier.align(Alignment.BottomStart).padding(64.dp)) {
            Text("Paused", fontSize = 18.sp, color = Color.White.copy(alpha = 0.7f))
            Text(a.title, fontSize = 40.sp, fontWeight = FontWeight.Black, color = Color.White)
            a.label?.let { Text(it, fontSize = 18.sp, color = Color.White.copy(alpha = 0.8f)) }
            Text("Press any button", fontSize = 14.sp, color = Color.White.copy(alpha = 0.5f), modifier = Modifier.padding(top = 10.dp))
        }
    }
}
