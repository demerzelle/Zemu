package com.zemu.tv.ui.onboarding

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.animateOffsetAsState
import androidx.compose.animation.core.animateSizeAsState
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.focusGroup
import androidx.compose.foundation.gestures.detectTapGestures
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusProperties
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInWindow
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.tv.material3.Icon
import androidx.tv.material3.Text
import com.zemu.tv.ui.components.AppIcons
import com.zemu.tv.ui.components.TvButton
import com.zemu.tv.ui.theme.Palette
import com.zemu.tv.ui.theme.glassPanel

/** Where the tour's stops point: elements tag themselves with [tourTarget]. Bounds are in the window. */
val LocalTourTargets = staticCompositionLocalOf<MutableMap<String, Rect>?> { null }

fun tourTarget(key: String): Modifier = Modifier.composed {
    val map = LocalTourTargets.current ?: return@composed Modifier
    Modifier.onGloballyPositioned { map[key] = it.boundsInWindow() }
}

@Composable
fun rememberTourTargets(): MutableMap<String, Rect> = remember { mutableStateMapOf() }

/** One stop: a spotlight on [target] (or a picture of the screen it's about, [mock]) and a caption. */
private class Stop(val target: String?, val title: String, val text: String, val openMenu: Boolean = false, val mock: (@Composable () -> Unit)? = null)

private val stops = listOf(
    Stop("menu", "Everything lives here", "Search, Home, Movies, Series and Anime, your list and your addons. Surprise me plays something picked for you.", openMenu = true),
    Stop("card", "Hold OK for options", "On any title: add it to My List or Watch Later, watch the trailer, or mark it watched. Press OK to open it."),
    Stop(null, "The best stream, picked for you", "Each title's streams are ranked by quality, what this device plays well and your languages. The best one is marked, and Play starts it.", mock = { StreamMock() }),
    Stop(null, "Your languages, automatically", "The player switches to your audio and subtitles, skips intros and plays the next episode. Change them once and the rest of the show follows.", mock = { PlayerMock() }),
    Stop("sounds", "Sounds", "Turn the clicks up, down or off, or pick another sound pack.", openMenu = true),
    Stop("dest:SETTINGS", "Settings", "Change any of this later. Updates & storage can replay this tour or run setup again.", openMenu = true),
)

/**
 * The first-run tour over the real app: a welcome card, then a spotlight on one thing at a time with a
 * short caption. Skippable from any stop. [setMenuOpen] opens the side menu for the stops that point
 * into it. [newUser] only changes the welcome's words.
 */
@OptIn(androidx.compose.ui.ExperimentalComposeUiApi::class)
@Composable
fun Tour(targets: Map<String, Rect>, newUser: Boolean, setMenuOpen: (Boolean) -> Unit, onDone: () -> Unit) {
    // -1 = the welcome card.
    var at by remember { mutableStateOf(-1) }
    val stop = stops.getOrNull(at)
    LaunchedEffect(at) { setMenuOpen(stop?.openMenu == true) }
    fun finish() { setMenuOpen(false); onDone() }
    var origin by remember { mutableStateOf(Offset.Zero) }
    val primary = remember { FocusRequester() }
    val density = LocalDensity.current

    BoxWithConstraints(
        Modifier
            .fillMaxSize()
            .onGloballyPositioned { origin = it.positionInWindow() }
            // Taps and the remote stay with the tour.
            .pointerInput(Unit) { detectTapGestures { } }
            .focusProperties { exit = { FocusRequester.Cancel } }
            .focusGroup(),
    ) {
        val hole = stop?.target?.let { targets[it] }?.translate(-origin)?.inflate(with(density) { 8.dp.toPx() })
        // The spotlight glides from stop to stop.
        val holeAt by animateOffsetAsState(hole?.topLeft ?: Offset(constraints.maxWidth / 2f, constraints.maxHeight / 2f), label = "holeAt")
        val holeSize by animateSizeAsState(hole?.size ?: Size.Zero, label = "holeSize")
        val dim by animateFloatAsState(if (stop?.mock != null || at < 0) 0.82f else 0.7f, label = "dim")
        Canvas(Modifier.fillMaxSize().graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }) {
            drawRect(Color.Black.copy(alpha = dim))
            if (holeSize.width > 1f) {
                val r = CornerRadius(14.dp.toPx())
                drawRoundRect(Color.Transparent, holeAt, holeSize, r, blendMode = BlendMode.Clear)
                drawRoundRect(Palette.Accent, holeAt, holeSize, r, style = Stroke(3.dp.toPx()))
            }
        }

        // The caption never covers the spotlight: beside it where there's room, else under it, else above.
        val w = 420.dp
        val captionH = 230.dp
        val (x, y) = with(density) {
            when {
                hole == null -> ((maxWidth - w) / 2) to (maxHeight * 0.18f)
                hole.right.toDp() + 28.dp + w < maxWidth -> (hole.right.toDp() + 28.dp) to (hole.center.y.toDp() - captionH / 2).coerceIn(24.dp, maxHeight - captionH)
                hole.bottom.toDp() + 20.dp + captionH < maxHeight -> hole.left.toDp().coerceIn(24.dp, maxWidth - w - 24.dp) to (hole.bottom.toDp() + 20.dp)
                else -> hole.left.toDp().coerceIn(24.dp, maxWidth - w - 24.dp) to (hole.top.toDp() - captionH - 20.dp).coerceAtLeast(24.dp)
            }
        }
        Column(
            Modifier
                .offset(x = x, y = y)
                .width(w)
                .glassPanel(com.zemu.tv.ui.theme.boxy(RoundedCornerShape(16.dp)))
                .padding(24.dp),
        ) {
            if (stop == null) {
                Text(if (newUser) "Welcome to Zemu" else "What's new in Zemu 1.1", fontSize = 26.sp, fontWeight = FontWeight.Bold)
                Text(
                    if (newUser) "A quick look around, then a few choices so everything plays the way you like."
                    else "Zemu now plays your languages automatically, with separate choices for anime. Take a quick look around, then confirm your subtitles and look.",
                    color = Palette.TextSecondary, fontSize = 15.sp, modifier = Modifier.padding(top = 8.dp, bottom = 18.dp),
                )
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    TvButton("Take the tour", onClick = { at = 0 }, primary = true, modifier = Modifier.focusRequester(primary))
                    TvButton("Skip the tour", onClick = ::finish)
                }
            } else {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    stops.indices.forEach { i ->
                        Box(Modifier.padding(end = 6.dp).size(if (i == at) 9.dp else 6.dp).background(if (i <= at) Palette.Accent else Palette.TextSecondary.copy(alpha = 0.35f), CircleShape))
                    }
                }
                Text(stop.title, fontSize = 22.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 12.dp))
                Text(stop.text, color = Palette.TextSecondary, fontSize = 15.sp, modifier = Modifier.padding(top = 6.dp))
                stop.mock?.let { Spacer(Modifier.height(16.dp)); it() }
                Row(Modifier.fillMaxWidth().padding(top = 20.dp), horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                    TvButton("Skip", onClick = ::finish)
                    Spacer(Modifier.weight(1f))
                    if (at > 0) TvButton("Back", onClick = { at-- })
                    TvButton(if (at < stops.lastIndex) "Next" else "Done", onClick = { if (at < stops.lastIndex) at++ else finish() }, primary = true, modifier = Modifier.focusRequester(primary))
                }
            }
        }
        LaunchedEffect(at) { runCatching { primary.requestFocus() } }
    }
}

/** A few stream rows as the title page shows them, the best one marked. */
@Composable
private fun StreamMock() {
    val rows = listOf(Triple("4K · HDR · Dolby Atmos", "English · 18.2 GB", true), Triple("1080p · 5.1", "English, Japanese · 4.1 GB", false), Triple("720p", "Japanese · 1.2 GB", false))
    Column(Modifier.fillMaxWidth().background(Palette.Surface, RoundedCornerShape(10.dp)).padding(10.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        rows.forEach { (name, info, best) ->
            Row(
                Modifier.fillMaxWidth().then(if (best) Modifier.border(2.dp, Palette.Accent, RoundedCornerShape(8.dp)) else Modifier).padding(horizontal = 10.dp, vertical = 7.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column(Modifier.weight(1f)) {
                    Text(name, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                    Text(info, fontSize = 11.sp, color = Palette.TextSecondary)
                }
                if (best) Text("BEST", fontSize = 11.sp, fontWeight = FontWeight.Black, color = Palette.Accent)
            }
        }
    }
}

/** The player's bottom bar with the language buttons, over a dark frame. */
@Composable
private fun PlayerMock() {
    Column(Modifier.fillMaxWidth().height(130.dp).background(Color(0xFF15151C), RoundedCornerShape(10.dp)).padding(12.dp), verticalArrangement = Arrangement.Bottom) {
        Text("Skip intro", fontSize = 11.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.align(Alignment.End).background(Color.White.copy(alpha = 0.15f), RoundedCornerShape(6.dp)).padding(horizontal = 8.dp, vertical = 4.dp))
        Spacer(Modifier.weight(1f))
        Box(Modifier.fillMaxWidth().height(3.dp).background(Color.White.copy(alpha = 0.25f))) {
            Box(Modifier.fillMaxWidth(0.4f).height(3.dp).background(Palette.Accent))
        }
        Row(Modifier.padding(top = 10.dp), horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(AppIcons.Pause, contentDescription = null, tint = Color.White, modifier = Modifier.size(18.dp))
            Spacer(Modifier.weight(1f))
            Icon(AppIcons.Audio, contentDescription = null, tint = Palette.Accent, modifier = Modifier.size(16.dp))
            Text("Japanese", fontSize = 11.sp, color = Color.White)
            Icon(AppIcons.Subtitles, contentDescription = null, tint = Palette.Accent, modifier = Modifier.size(16.dp))
            Text("English", fontSize = 11.sp, color = Color.White)
            Icon(AppIcons.Next, contentDescription = null, tint = Color.White, modifier = Modifier.size(16.dp))
        }
    }
}
