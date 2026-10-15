package com.zemu.tv.ui.components

import androidx.tv.material3.LocalContentColor

import androidx.compose.ui.text.font.FontWeight

import androidx.compose.ui.input.key.onPreviewKeyEvent

import androidx.compose.ui.input.key.type

import androidx.compose.ui.input.key.key

import androidx.compose.ui.input.key.KeyEventType

import androidx.compose.ui.input.key.Key

import androidx.compose.ui.Alignment

import androidx.compose.foundation.shape.RoundedCornerShape

import androidx.compose.foundation.layout.fillMaxWidth

import androidx.compose.foundation.layout.Row

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.tv.material3.Text
import com.zemu.tv.data.AppSettings
import com.zemu.tv.ui.theme.Palette

object SubtitleStyleOptions {
    val sizes = listOf(0.75f to "Small", 1f to "Normal", 1.3f to "Large", 1.6f to "Extra large", 2f to "Huge")
    val colors = listOf(
        0xFFFFFFFF to "White", 0xFFFFEB3B to "Yellow", 0xFF80DEEA to "Cyan",
        0xFFA5D6A7 to "Green", 0xFFF48FB1 to "Pink", 0xFFBDBDBD to "Grey",
    )
    val backgrounds = listOf(0 to "None", 1 to "Translucent box", 2 to "Solid box")
    val edges = listOf(0 to "None", 1 to "Outline", 2 to "Drop shadow")
    val positions = listOf(0.03f to "Bottom", 0.08f to "Normal", 0.15f to "Raised", 0.25f to "High")
}

/**
 * Subtitle style: one switch for custom vs. the file's own style, then (when custom) one compact
 * line per setting. OK or Right picks the next choice, Left the previous; changes apply live.
 */
@Composable
fun SubtitleStyleEditor(settings: AppSettings, update: ((AppSettings) -> AppSettings) -> Unit) {
    val custom = !settings.subtitleOriginalStyle
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        CycleRow("Custom style", if (custom) "On" else "Off · using the file's original style", listOf(true, false), custom) { v ->
            update { it.copy(subtitleOriginalStyle = !v) }
        }
        if (custom) {
            CycleRow("Size", SubtitleStyleOptions.sizes, settings.subtitleScale) { v -> update { it.copy(subtitleScale = v) } }
            CycleRow("Color", SubtitleStyleOptions.colors, settings.subtitleColor) { v -> update { it.copy(subtitleColor = v) } }
            CycleRow("Background", SubtitleStyleOptions.backgrounds, settings.subtitleBackground) { v -> update { it.copy(subtitleBackground = v) } }
            CycleRow("Edge", SubtitleStyleOptions.edges, settings.subtitleEdge) { v -> update { it.copy(subtitleEdge = v) } }
            CycleRow("Position", SubtitleStyleOptions.positions, settings.subtitleBottom) { v -> update { it.copy(subtitleBottom = v) } }
        }
    }
}

@Composable
private fun <T> CycleRow(label: String, options: List<Pair<T, String>>, current: T, onPick: (T) -> Unit) =
    CycleRow(label, options.firstOrNull { it.first == current }?.second ?: options.first().second, options.map { it.first }, current, onPick)

/** A one-line setting: name on the left, value on the right with ◀ ▶; OK/Right = next, Left = previous. */
@Composable
private fun <T> CycleRow(label: String, value: String, values: List<T>, current: T, onPick: (T) -> Unit) {
    val i = values.indexOf(current).coerceAtLeast(0)
    fun step(d: Int) = onPick(values[(i + d).mod(values.size)])
    FocusSurface(
        onClick = { step(1) },
        modifier = Modifier.fillMaxWidth().onPreviewKeyEvent { e ->
            if (e.type != KeyEventType.KeyDown) return@onPreviewKeyEvent false
            when (e.key) {
                Key.DirectionLeft -> { step(-1); true }
                Key.DirectionRight -> { step(1); true }
                else -> false
            }
        },
        shape = RoundedCornerShape(10.dp),
        containerColor = Palette.Surface,
        focusedScale = 1.01f,
    ) {
        Row(Modifier.padding(horizontal = 16.dp, vertical = 9.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(label, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
            Text("◀  $value  ▶", fontSize = 14.sp, color = LocalContentColor.current.copy(alpha = 0.8f))
        }
    }
}
