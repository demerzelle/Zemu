package com.zemu.tv.ui.components

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.border
import androidx.compose.foundation.focusable
import androidx.compose.foundation.gestures.animateScrollBy
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.tv.material3.Text
import com.zemu.tv.ui.theme.Palette
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * Text clipped to [maxHeight] that scrolls itself (teleprompter-style) when it doesn't fit,
 * so long summaries can be read in full. With [focusable], Up/Down on the remote scroll it
 * manually and auto-scroll pauses while it has focus.
 */
@Composable
fun ScrollingText(
    text: String,
    maxHeight: Dp,
    modifier: Modifier = Modifier,
    color: Color = Palette.TextSecondary,
    fontSize: TextUnit = 15.sp,
    lineHeight: TextUnit = 21.sp,
    focusable: Boolean = false,
    autoScroll: Boolean = true,
) {
    val scroll = rememberScrollState()
    val scope = rememberCoroutineScope()
    var focused by remember { mutableStateOf(false) }
    val overflows = scroll.maxValue > 0

    LaunchedEffect(text, scroll.maxValue, focused, autoScroll) {
        if (focused) return@LaunchedEffect
        scroll.scrollTo(0)
        if (!autoScroll || scroll.maxValue == 0) return@LaunchedEffect
        while (true) {
            delay(4_000)
            val duration = (scroll.maxValue * 40).coerceIn(3_000, 40_000)
            scroll.animateScrollTo(scroll.maxValue, tween(duration, easing = LinearEasing))
            delay(3_500)
            scroll.animateScrollTo(0, tween(700))
        }
    }

    Box(
        modifier
            .then(
                if (focusable && overflows) {
                    Modifier
                        .onFocusChanged { focused = it.isFocused }
                        .onPreviewKeyEvent { e ->
                            if (e.type != KeyEventType.KeyDown) return@onPreviewKeyEvent false
                            when (e.key) {
                                // Consume only while there's more text that way; otherwise let focus move on.
                                Key.DirectionDown -> (scroll.value < scroll.maxValue).also { if (it) scope.launch { scroll.animateScrollBy(90f) } }
                                Key.DirectionUp -> (scroll.value > 0).also { if (it) scope.launch { scroll.animateScrollBy(-90f) } }
                                else -> false
                            }
                        }
                        .focusable()
                        .border(2.dp, if (focused) Palette.FocusBorder.copy(alpha = 0.7f) else Color.Transparent, com.zemu.tv.ui.theme.boxy(RoundedCornerShape(6.dp)))
                        .padding(horizontal = 6.dp, vertical = 2.dp)
                } else Modifier,
            )
            .heightIn(max = maxHeight)
            .verticalScroll(scroll, enabled = false),
    ) {
        Text(text, color = color, fontSize = fontSize, lineHeight = lineHeight)
    }
    if (focusable && overflows && focused) {
        Box(Modifier.padding(top = 2.dp), contentAlignment = Alignment.CenterStart) {
            Text("▲▼ to scroll", color = Palette.TextMuted, fontSize = 11.sp)
        }
    }
}
