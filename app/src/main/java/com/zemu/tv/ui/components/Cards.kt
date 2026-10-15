package com.zemu.tv.ui.components

import androidx.compose.runtime.remember

import androidx.compose.runtime.setValue

import androidx.compose.runtime.getValue

import androidx.compose.runtime.mutableStateOf

import androidx.compose.foundation.focusable

import androidx.compose.ui.input.key.type

import androidx.compose.ui.input.key.key

import androidx.compose.ui.input.key.KeyEventType

import androidx.compose.ui.input.key.Key

import androidx.compose.ui.input.key.onKeyEvent

import androidx.compose.ui.focus.focusProperties

import androidx.compose.foundation.layout.size
import androidx.tv.material3.Icon
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.focusRestorer
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.isSpecified
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.tv.material3.Border
import androidx.tv.material3.ClickableSurfaceDefaults
import androidx.tv.material3.MaterialTheme
import androidx.tv.material3.Surface
import androidx.tv.material3.Text
import coil.compose.AsyncImage
import coil.request.ImageRequest
import com.zemu.tv.data.Meta
import com.zemu.tv.data.backdropUrl
import com.zemu.tv.data.posterUrl
import com.zemu.tv.data.title
import com.zemu.tv.ui.theme.Palette
import com.zemu.tv.ui.theme.styleDecor

@Composable
fun RemoteImage(url: String?, modifier: Modifier = Modifier, contentScale: ContentScale = ContentScale.Crop, alignment: Alignment = Alignment.Center) {
    if (url == null) return
    AsyncImage(
        model = ImageRequest.Builder(LocalContext.current).data(url).crossfade(true).build(),
        contentDescription = null,
        contentScale = contentScale,
        alignment = alignment,
        modifier = modifier,
    )
}

@Composable
fun PosterImage(meta: Meta, modifier: Modifier = Modifier) {
    androidx.compose.foundation.layout.Box(modifier.background(Palette.SurfaceHigh, com.zemu.tv.ui.theme.boxy(RoundedCornerShape(8.dp)))) {
        RemoteImage(meta.posterUrl(), Modifier.fillMaxSize())
    }
}

@Composable
fun PosterCard(
    meta: Meta,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    width: Dp = 132.dp,
    onFocused: (Meta) -> Unit = {},
    badge: String? = null,
    onLongClick: (() -> Unit)? = null,
) {
    val shape = com.zemu.tv.ui.theme.boxy(RoundedCornerShape(6.dp))
    val cardMenu = LocalCardMenu.current
    val rowOptions = LocalRowOptions.current
    val menu: (Meta) -> Unit = { cardMenu(it, rowOptions) }
    val watched = meta.id in LocalWatched.current
    // Cybercore: the selected poster opens in a desktop window titled with its name.
    var focused by remember { mutableStateOf(false) }
    val windowed = focused && Palette.Style == com.zemu.tv.ui.theme.UiStyle.RETRO
    Surface(
        onClick = onClick,
        onLongClick = onLongClick ?: { menu(meta) },
        modifier = modifier
            .touchClick(onClick, onLongClick ?: { menu(meta) })
            .then(if (width.isSpecified) Modifier.width(width) else Modifier.fillMaxWidth())
            .aspectRatio(2f / 3f)
            .onFocusChanged { focused = it.isFocused; if (it.isFocused) onFocused(meta) }
            .styleDecor(seed = meta.id.hashCode(), bevel = false),
        shape = ClickableSurfaceDefaults.shape(shape = shape),
        scale = ClickableSurfaceDefaults.scale(focusedScale = if (Palette.Style == com.zemu.tv.ui.theme.UiStyle.RETRO) 1f else 1.1f),
        border = ClickableSurfaceDefaults.border(focusedBorder = if (Palette.Style == com.zemu.tv.ui.theme.UiStyle.RETRO) Border.None else Border(BorderStroke(3.dp, Palette.FocusBorder), shape = shape)),
        colors = ClickableSurfaceDefaults.colors(containerColor = Palette.Surface, focusedContainerColor = Palette.Surface),
    ) {
        val poster: @Composable () -> Unit = {
            Box(Modifier.fillMaxSize()) {
                Text(
                    meta.title,
                    modifier = Modifier.align(Alignment.Center).padding(8.dp),
                    textAlign = TextAlign.Center,
                    color = Palette.TextSecondary,
                    fontSize = 13.sp,
                    maxLines = 4,
                )
                RemoteImage(meta.posterUrl(), Modifier.fillMaxSize())
            }
        }
        if (windowed) com.zemu.tv.ui.theme.RetroWindow(meta.title, Modifier.fillMaxSize(), poster) else poster()
        val rating = meta.imdbRating?.toDoubleOrNull()?.takeIf { it > 0 }
        if (rating != null) {
            Box(
                Modifier
                    .align(Alignment.BottomStart)
                    .padding(6.dp)
                    .background(Color.Black.copy(alpha = 0.75f), com.zemu.tv.ui.theme.boxy(RoundedCornerShape(4.dp)))
                    .padding(horizontal = 5.dp, vertical = 1.dp),
            ) {
                Text("★ ${"%.1f".format(rating)}", color = Palette.Imdb, fontSize = 11.sp, fontWeight = FontWeight.Bold)
            }
        }
        if (watched) {
            Box(
                Modifier
                    .align(Alignment.TopStart)
                    .padding(6.dp)
                    .padding(top = if (windowed) com.zemu.tv.ui.theme.retroBarHeight() else 0.dp)
                    .background(Palette.Accent, com.zemu.tv.ui.theme.boxy(RoundedCornerShape(4.dp)))
                    .padding(horizontal = 5.dp, vertical = 1.dp),
            ) {
                Text("✓ Watched", color = Palette.OnAccent, fontSize = 10.sp, fontWeight = FontWeight.Bold)
            }
        }
        if (badge != null) {
            Box(
                Modifier
                    .align(Alignment.TopEnd)
                    .padding(6.dp)
                    .padding(top = if (windowed) com.zemu.tv.ui.theme.retroBarHeight() else 0.dp)
                    .background(Color.Black.copy(alpha = 0.75f), com.zemu.tv.ui.theme.boxy(RoundedCornerShape(4.dp)))
                    .padding(horizontal = 5.dp, vertical = 1.dp),
            ) {
                // The tag is always black, so its text stays bright whatever the theme.
                Text(badge, color = Color(0xFF46D369), fontSize = 11.sp, fontWeight = FontWeight.Bold)
            }
        }
    }
}

@Composable
fun ContinueCard(
    meta: Meta,
    subtitle: String?,
    progress: Float,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    onFocused: (Meta) -> Unit = {},
) {
    val shape = com.zemu.tv.ui.theme.boxy(RoundedCornerShape(6.dp))
    val cardMenu = LocalCardMenu.current
    val rowOptions = LocalRowOptions.current
    val menu: (Meta) -> Unit = { cardMenu(it, rowOptions) }
    Surface(
        onClick = onClick,
        onLongClick = { menu(meta) },
        modifier = modifier
            .touchClick(onClick) { menu(meta) }
            // Same height as a poster (132 × 3/2), so every row is the same height.
            .height(198.dp)
            .aspectRatio(16f / 9f)
            .onFocusChanged { if (it.isFocused) onFocused(meta) }
            .styleDecor(seed = meta.id.hashCode(), bevel = false),
        shape = ClickableSurfaceDefaults.shape(shape = shape),
        scale = ClickableSurfaceDefaults.scale(focusedScale = if (Palette.Style == com.zemu.tv.ui.theme.UiStyle.RETRO) 1f else 1.08f),
        border = ClickableSurfaceDefaults.border(focusedBorder = if (Palette.Style == com.zemu.tv.ui.theme.UiStyle.RETRO) Border.None else Border(BorderStroke(3.dp, Palette.FocusBorder), shape = shape)),
        colors = ClickableSurfaceDefaults.colors(containerColor = Palette.Surface, focusedContainerColor = Palette.Surface),
    ) {
        RemoteImage(meta.backdropUrl(), Modifier.fillMaxSize())
        Box(Modifier.fillMaxSize().background(Brush.verticalGradient(0.45f to Color.Transparent, 1f to Color.Black.copy(alpha = 0.9f))))
        Column(Modifier.align(Alignment.BottomStart).fillMaxWidth().padding(10.dp)) {
            Text(meta.title, fontWeight = FontWeight.Bold, fontSize = 14.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (subtitle != null) Text(subtitle, color = Palette.TextSecondary, fontSize = 12.sp, maxLines = 1)
            if (progress > 0f) {
                Box(Modifier.padding(top = 6.dp).fillMaxWidth().height(3.dp).background(Color.White.copy(alpha = 0.3f))) {
                    Box(Modifier.fillMaxWidth(progress.coerceIn(0f, 1f)).height(3.dp).background(Palette.Accent))
                }
            }
        }
    }
}

/**
 * Horizontal row with a title. `requesters` lets the caller attach focus requesters to specific
 * items (used to restore focus after navigating back).
 */
@OptIn(ExperimentalComposeUiApi::class)
@Composable
fun <T> MediaRow(
    title: String,
    items: List<T>,
    key: (T) -> String,
    modifier: Modifier = Modifier,
    requesters: Map<String, FocusRequester> = emptyMap(),
    contentPadding: PaddingValues = PaddingValues(horizontal = 48.dp, vertical = 18.dp),
    trailingTitle: String? = null,
    /** Favorite rows show a heart before the title. */
    favorite: Boolean = false,
    /** Touch: long-press the title (e.g. to move or favorite the row). */
    onTitleLongPress: (() -> Unit)? = null,
    itemContent: @Composable (index: Int, item: T, itemModifier: Modifier) -> Unit,
) {
    var rowFocused by remember { mutableStateOf(false) }
    var titleFocused by remember { mutableStateOf(false) }
    Column(modifier.onFocusChanged { rowFocused = it.hasFocus }) {
        val titleTouch = if (onTitleLongPress == null) Modifier else Modifier.pointerInput(onTitleLongPress) { detectTapGestures(onLongPress = { onTitleLongPress() }) }
        // Up from a row's posters lands on its name; OK (or holding OK) there opens the row editor.
        // Only focusable while the row has focus, so Up/Down between rows never stops on names.
        val titleKeys = if (onTitleLongPress == null) Modifier else Modifier
            .focusProperties { canFocus = rowFocused }
            .onFocusChanged { titleFocused = it.isFocused }
            .onKeyEvent { e ->
                val ok = e.key == Key.DirectionCenter || e.key == Key.Enter || e.key == Key.NumPadEnter
                if (ok && e.type == KeyEventType.KeyUp) { onTitleLongPress(); true } else ok
            }
            .focusable()
        Row(
            Modifier.padding(start = 48.dp).then(titleTouch).then(titleKeys)
                .background(if (titleFocused) Palette.Accent else Color.Transparent, com.zemu.tv.ui.theme.boxy(RoundedCornerShape(6.dp)))
                .padding(horizontal = if (titleFocused) 8.dp else 0.dp, vertical = 2.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            val ink = if (titleFocused) Palette.OnAccent else Palette.Text
            if (favorite) Icon(AppIcons.Heart, contentDescription = "Pinned", tint = if (titleFocused) ink else Palette.Accent, modifier = Modifier.padding(end = 8.dp).size(18.dp))
            Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold, color = ink)
            if (titleFocused) Text("   OK: pin, move or remove", color = ink.copy(alpha = 0.75f), fontSize = 13.sp)
            else if (trailingTitle != null) {
                Text("  ·  $trailingTitle", color = Palette.TextMuted, fontSize = 13.sp)
            }
        }
        LazyRow(
            state = rememberLazyListState(),
            modifier = Modifier.focusRestorer(),
            contentPadding = contentPadding,
            horizontalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            itemsIndexed(items, key = { _, it -> key(it) }) { index, item ->
                val req = requesters[key(item)]
                itemContent(index, item, if (req != null) Modifier.focusRequester(req) else Modifier)
            }
        }
    }
}

/** A streaming service: its square logo fills the whole tile. */
@Composable
fun ServiceCard(m: Meta, modifier: Modifier = Modifier, selected: Boolean = false, onLongClick: (() -> Unit)? = null, onFocused: (Meta) -> Unit = {}, onClick: () -> Unit) {
    val shape = com.zemu.tv.ui.theme.boxy(RoundedCornerShape(14.dp))
    Surface(
        onClick = onClick,
        onLongClick = onLongClick,
        modifier = modifier.touchClick(onClick, onLongClick).size(168.dp).onFocusChanged { if (it.isFocused) onFocused(m) }.styleDecor(seed = m.id.hashCode(), bevel = false),
        shape = ClickableSurfaceDefaults.shape(shape = shape),
        scale = ClickableSurfaceDefaults.scale(focusedScale = if (Palette.Style == com.zemu.tv.ui.theme.UiStyle.RETRO) 1f else 1.08f),
        border = ClickableSurfaceDefaults.border(
            border = if (selected) Border(BorderStroke(3.dp, Palette.Accent), shape = shape) else Border.None,
            focusedBorder = if (Palette.Style == com.zemu.tv.ui.theme.UiStyle.RETRO) Border.None else Border(BorderStroke(3.dp, Palette.FocusBorder), shape = shape),
        ),
        colors = ClickableSurfaceDefaults.colors(containerColor = Palette.SurfaceHigh, focusedContainerColor = Palette.SurfaceHigh),
    ) {
        Text(m.name.orEmpty(), modifier = Modifier.align(Alignment.Center).padding(10.dp), textAlign = TextAlign.Center, fontWeight = FontWeight.Bold, fontSize = 16.sp)
        RemoteImage(m.poster, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
        if (selected) Box(Modifier.align(Alignment.TopEnd).padding(6.dp).background(Palette.Accent, com.zemu.tv.ui.theme.boxy(RoundedCornerShape(4.dp))).padding(horizontal = 5.dp, vertical = 1.dp)) {
            Text("✓", color = Palette.OnAccent, fontSize = 12.sp, fontWeight = FontWeight.Black)
        }
    }
}

/** A studio or network: its wordmark fills a light tile (logos are made for light backgrounds). */
@Composable
fun StudioCard(m: Meta, modifier: Modifier = Modifier, onFocused: (Meta) -> Unit = {}, onClick: () -> Unit) {
    val shape = com.zemu.tv.ui.theme.boxy(RoundedCornerShape(14.dp))
    Surface(
        onClick = onClick,
        modifier = modifier.touchClick(onClick, null).size(width = 260.dp, height = 146.dp).onFocusChanged { if (it.isFocused) onFocused(m) }.styleDecor(seed = m.id.hashCode(), bevel = false),
        shape = ClickableSurfaceDefaults.shape(shape = shape),
        scale = ClickableSurfaceDefaults.scale(focusedScale = if (Palette.Style == com.zemu.tv.ui.theme.UiStyle.RETRO) 1f else 1.08f),
        border = ClickableSurfaceDefaults.border(focusedBorder = if (Palette.Style == com.zemu.tv.ui.theme.UiStyle.RETRO) Border.None else Border(BorderStroke(3.dp, Palette.FocusBorder), shape = shape)),
        colors = ClickableSurfaceDefaults.colors(containerColor = Color(0xFFF2F2F4), focusedContainerColor = Color.White),
    ) {
        if (m.poster == null) Text(m.name.orEmpty(), modifier = Modifier.align(Alignment.Center), color = Color(0xFF121216), fontWeight = FontWeight.Black, fontSize = 20.sp)
        RemoteImage(m.poster, Modifier.fillMaxSize().padding(horizontal = 18.dp, vertical = 16.dp), contentScale = ContentScale.Fit)
    }
}
