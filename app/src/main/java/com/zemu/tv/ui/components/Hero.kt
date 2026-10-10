package com.zemu.tv.ui.components

import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import com.zemu.tv.data.officialTrailers
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import com.zemu.tv.player.TrailerActivity
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.tv.material3.MaterialTheme
import androidx.tv.material3.Text
import coil.compose.AsyncImage
import coil.request.ImageRequest
import com.zemu.tv.data.Meta
import com.zemu.tv.data.backdropUrl
import com.zemu.tv.data.logoUrl
import com.zemu.tv.data.runtimeLabel
import com.zemu.tv.data.title
import com.zemu.tv.data.trailerId
import com.zemu.tv.player.YouTubeEmbed
import com.zemu.tv.ui.theme.Palette
import kotlinx.coroutines.delay

/** Which hero trailer is playing and how far in, so ⏯ can continue it fullscreen. */
object HeroTrailerState {
    var playingId by mutableStateOf<String?>(null)
    var seconds = 0f
    /** All official trailers of the title playing, for the fullscreen selector. */
    var playlist: List<com.zemu.tv.data.TrailerRef> = emptyList()

    fun openFullscreen(context: android.content.Context) {
        val id = playingId ?: return
        TrailerActivity.start(context, playlist.ifEmpty { listOf(com.zemu.tv.data.TrailerRef(id, "Trailer")) }, startId = id, startSeconds = seconds.toInt())
    }
}

/**
 * Opens the playing hero trailer fullscreen (with sound) when ⏯ is pressed. Put it on a screen's
 * root so it sees the key whatever has focus.
 */
@Composable
fun Modifier.heroTrailerKeys(): Modifier {
    val context = LocalContext.current
    return onPreviewKeyEvent { e ->
        val id = HeroTrailerState.playingId
        if (id == null || e.type != KeyEventType.KeyDown) return@onPreviewKeyEvent false
        when (e.key) {
            Key.MediaPlayPause, Key.MediaPlay -> {
                HeroTrailerState.openFullscreen(context)
                true
            }
            else -> false
        }
    }
}

/**
 * Touch: tapping the hero area while its trailer is playing continues the trailer fullscreen.
 * Taps on buttons inside it still go to the buttons.
 */
@Composable
fun Modifier.heroTrailerTap(): Modifier {
    val context = LocalContext.current
    return pointerInput(Unit) {
        detectTapGestures {
            HeroTrailerState.openFullscreen(context)
        }
    }
}

/** Muted, cropped YouTube trailer that fades in once it actually starts playing. */
@Composable
fun HeroTrailer(videoId: String, sound: Boolean, modifier: Modifier = Modifier, onFinished: () -> Unit = {}) {
    var playing by remember(videoId) { mutableStateOf(false) }
    DisposableEffect(videoId) {
        onDispose { if (HeroTrailerState.playingId == videoId) HeroTrailerState.playingId = null }
    }
    val alpha by animateFloatAsState(if (playing) 1f else 0f, tween(900), label = "trailer")
    AndroidView(
        factory = { ctx ->
            YouTubeEmbed.create(ctx, focusable = false, listener = object : YouTubeEmbed.Listener {
                override fun onPlaying() {
                    playing = true
                    HeroTrailerState.playingId = videoId
                }
                override fun onEnded() { playing = false; HeroTrailerState.playingId = null; onFinished() }
                override fun onError(code: Int) { playing = false; HeroTrailerState.playingId = null; onFinished() }
                override fun onTime(seconds: Float) { HeroTrailerState.seconds = seconds }
            }).also { YouTubeEmbed.load(it, videoId, muted = !sound, controls = false, cover = true) }
        },
        onRelease = { it.destroy() },
        modifier = modifier.alpha(alpha),
    )
}

/**
 * Full-bleed backdrop with left/bottom fade, as used behind Home and Details. When
 * [trailerAfterMs] is set, the title's trailer replaces the image after that delay.
 */
@Composable
fun Backdrop(meta: Meta?, modifier: Modifier = Modifier, trailerAfterMs: Long? = null, trailerSound: Boolean = false) {
    var showTrailer by remember(meta?.id) { mutableStateOf(false) }
    // Several official trailers play one after another; otherwise the single one.
    val playlist = remember(meta?.id) { meta?.officialTrailers.orEmpty() }
    var index by remember(meta?.id) { mutableIntStateOf(0) }
    val trailer = playlist.getOrNull(index)?.id
    LaunchedEffect(meta?.id, trailerAfterMs) {
        showTrailer = false
        if (trailerAfterMs != null && trailer != null) {
            delay(trailerAfterMs)
            showTrailer = true
        }
    }
    Box(modifier) {
        Crossfade(targetState = meta?.backdropUrl(), label = "backdrop") { url ->
            Box(Modifier.fillMaxSize()) {
                RemoteImage(url, Modifier.fillMaxHeight().fillMaxWidth(0.78f).align(Alignment.TopEnd), alignment = Alignment.TopCenter)
            }
        }
        if (showTrailer && trailer != null) {
            HeroTrailerState.playlist = playlist
            key(trailer) {
                HeroTrailer(
                    trailer,
                    sound = trailerSound,
                    modifier = Modifier.fillMaxHeight().fillMaxWidth(0.78f).align(Alignment.TopEnd),
                    onFinished = { if (index + 1 < playlist.size) index++ else showTrailer = false },
                )
            }
        }
        Box(
            Modifier.fillMaxSize().background(
                Brush.horizontalGradient(
                    0f to Palette.Background,
                    0.3f to Palette.Background.copy(alpha = 0.92f),
                    0.6f to Palette.Background.copy(alpha = 0.35f),
                    1f to Color.Transparent,
                ),
            ),
        )
        Box(Modifier.fillMaxSize().background(Brush.verticalGradient(0.5f to Color.Transparent, 1f to Palette.Background)))
    }
}

@Composable
fun TitleLogo(meta: Meta, maxHeight: Int = 110) {
    var failed by remember(meta.id) { mutableStateOf(false) }
    val logo = meta.logoUrl()
    if (logo != null && !failed) {
        AsyncImage(
            model = ImageRequest.Builder(LocalContext.current).data(logo).crossfade(true).build(),
            contentDescription = meta.title,
            contentScale = ContentScale.Fit,
            alignment = Alignment.CenterStart,
            onError = { failed = true },
            modifier = Modifier.heightIn(max = maxHeight.dp).widthIn(max = 420.dp),
        )
    } else {
        Text(meta.title, style = MaterialTheme.typography.displaySmall, fontWeight = FontWeight.Black, maxLines = 2, overflow = TextOverflow.Ellipsis)
    }
}

@Composable
fun MetaLine(meta: Meta, matchPercent: Int?) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
        if (matchPercent != null) Text("$matchPercent% Match", color = Palette.Match, fontWeight = FontWeight.Bold, fontSize = 15.sp)
        meta.releaseInfo?.takeIf { it.isNotBlank() }?.let { Text(it, fontSize = 15.sp, color = Palette.TextSecondary) }
        meta.runtimeLabel?.let { Text(it, fontSize = 15.sp, color = Palette.TextSecondary) }
        Tag(if (meta.type == "series") "SERIES" else "MOVIE", Palette.TextSecondary)
        ImdbBadge(meta.imdbRating)
    }
}

/** Home hero: shows whatever card currently has focus. */
@Composable
fun HeroInfo(meta: Meta?, matchPercent: Int?, modifier: Modifier = Modifier) {
    Box(modifier.clipToBounds()) {
        Crossfade(targetState = meta, label = "hero") { m ->
            if (m != null) {
                Column(Modifier.padding(start = 48.dp, top = 20.dp).width(560.dp)) {
                    Box(Modifier.height(80.dp), contentAlignment = Alignment.BottomStart) { TitleLogo(m, maxHeight = 80) }
                    Spacer(Modifier.size(10.dp))
                    MetaLine(m, matchPercent)
                    Spacer(Modifier.size(6.dp))
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        if (m.genres.isNotEmpty()) Text(m.genres.take(4).joinToString("  •  "), color = Palette.TextSecondary, fontSize = 14.sp)
                        val trailerOn = m.trailerId != null && HeroTrailerState.playingId == m.trailerId
                        Text(
                            if (trailerOn) "     ⏯ Press Play/Pause for fullscreen trailer" else "     Hold OK for options",
                            color = if (trailerOn) Palette.Text else Palette.TextMuted,
                            fontSize = 12.sp,
                        )
                    }
                    Spacer(Modifier.size(8.dp))
                    ScrollingText(m.description.orEmpty(), maxHeight = 40.dp, lineHeight = 20.sp)
                }
            }
        }
    }
}
