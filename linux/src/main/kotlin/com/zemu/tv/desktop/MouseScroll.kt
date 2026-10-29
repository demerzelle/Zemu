package com.zemu.tv.desktop

import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.animateScrollBy
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.PointerEventType
import androidx.compose.ui.input.pointer.onPointerEvent
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.unit.dp
import androidx.tv.material3.Icon
import com.zemu.tv.ZemuApp
import com.zemu.tv.ui.theme.Palette
import kotlinx.coroutines.launch

/** Hover-scroll speeds (Settings → Home & browsing), in screen widths per second. */
val EDGE_SPEEDS = listOf(1 to 0.25f, 2 to 0.45f, 3 to 0.7f, 4 to 1f, 5 to 1.5f)

/**
 * A poster row the mouse alone can scroll: while the pointer is over it, either arrow buttons at its
 * ends or hovering near an end scrolls it (the setting). Nothing shows while the keyboard or a
 * controller is in use (the pointer is hidden then).
 */
@OptIn(ExperimentalComposeUiApi::class)
@Composable
fun MouseScroll(content: @Composable (LazyListState) -> Unit) {
    val state = rememberLazyListState()
    val settings by ZemuApp.container.userStore.settings.collectAsState()
    var hovered by remember { mutableStateOf(false) }
    var width by remember { mutableStateOf(1) }
    // -1..1: how far into the left or right edge the pointer is.
    var edge by remember { mutableFloatStateOf(0f) }
    val active = hovered && !CursorAutoHide.hidden
    val edges = settings.mouseRowScroll == "edges"
    Box(
        Modifier.onSizeChanged { width = it.width.coerceAtLeast(1) }
            .onPointerEvent(PointerEventType.Enter) { hovered = true }
            .onPointerEvent(PointerEventType.Exit) { hovered = false; edge = 0f }
            .onPointerEvent(PointerEventType.Move) { e ->
                val x = e.changes.first().position.x
                val zone = width * 0.12f
                edge = when {
                    x < zone -> -(1 - x / zone)
                    x > width - zone -> 1 - (width - x) / zone
                    else -> 0f
                }
            },
    ) {
        content(state)
        if (!active) return@Box
        if (edges) {
            val speed = EDGE_SPEEDS.firstOrNull { it.first == settings.edgeScrollSpeed }?.second ?: 0.7f
            LaunchedEffect(edge != 0f) {
                var last = 0L
                while (edge != 0f) withFrameNanos { now ->
                    // Faster the closer to the end; per frame, from the time since the last one.
                    if (last != 0L) state.dispatchRawDelta(edge * speed * width * (now - last) / 1e9f)
                    last = now
                }
            }
        } else {
            val scope = rememberCoroutineScope()
            val page = width * 0.75f
            if (state.canScrollBackward) RowArrow(Icons.AutoMirrored.Filled.KeyboardArrowLeft, "Scroll left", Modifier.align(Alignment.CenterStart)) { scope.launch { state.animateScrollBy(-page) } }
            if (state.canScrollForward) RowArrow(Icons.AutoMirrored.Filled.KeyboardArrowRight, "Scroll right", Modifier.align(Alignment.CenterEnd)) { scope.launch { state.animateScrollBy(page) } }
        }
    }
}

/** Clicked only, never focused: the arrow keys keep moving between posters. */
@Composable
private fun RowArrow(icon: ImageVector, label: String, modifier: Modifier, onClick: () -> Unit) {
    Box(
        modifier.padding(horizontal = 12.dp).size(48.dp).background(Palette.Background.copy(alpha = 0.8f), CircleShape)
            .pointerInput(Unit) { detectTapGestures { onClick() } },
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, contentDescription = label, tint = Color.White, modifier = Modifier.size(32.dp))
    }
}
