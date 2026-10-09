package com.zemu.tv.ui.components

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.gestures.BringIntoViewSpec
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp
import kotlin.math.abs

/**
 * When focus moves, lists scroll so the focused item keeps a margin from the edge instead of
 * touching it. Without this, focused cards scale up past the viewport edge and get clipped.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun FocusScrollMargins(content: @Composable () -> Unit) {
    val marginPx = with(LocalDensity.current) { 56.dp.toPx() }
    val spec = object : BringIntoViewSpec {
        override fun calculateScrollDistance(offset: Float, size: Float, containerSize: Float): Float {
            val margin = minOf(marginPx, ((containerSize - size) / 2f).coerceAtLeast(0f))
            val leading = offset - margin
            val trailing = offset + size + margin - containerSize
            return when {
                leading < 0 && trailing > 0 -> if (abs(leading) < abs(trailing)) leading else trailing
                leading < 0 -> leading
                trailing > 0 -> trailing
                else -> 0f
            }
        }
    }
    CompositionLocalProvider(androidx.compose.foundation.gestures.LocalBringIntoViewSpec provides spec, content = content)
}
