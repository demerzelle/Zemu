package com.zemu.tv.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
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

/** Rows of choices for subtitle size, color, background, edge and position. Changes apply live. */
@Composable
fun SubtitleStyleEditor(settings: AppSettings, update: ((AppSettings) -> AppSettings) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        ChoiceRow("Size", SubtitleStyleOptions.sizes, settings.subtitleScale) { v -> update { it.copy(subtitleScale = v) } }
        ChoiceRow("Color", SubtitleStyleOptions.colors, settings.subtitleColor) { v -> update { it.copy(subtitleColor = v) } }
        ChoiceRow("Background", SubtitleStyleOptions.backgrounds, settings.subtitleBackground) { v -> update { it.copy(subtitleBackground = v) } }
        ChoiceRow("Edge", SubtitleStyleOptions.edges, settings.subtitleEdge) { v -> update { it.copy(subtitleEdge = v) } }
        ChoiceRow("Position", SubtitleStyleOptions.positions, settings.subtitleBottom) { v -> update { it.copy(subtitleBottom = v) } }
    }
}

@Composable
private fun <T> ChoiceRow(label: String, options: List<Pair<T, String>>, current: T, onPick: (T) -> Unit) {
    LazyRow(
        contentPadding = PaddingValues(vertical = 3.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = androidx.compose.ui.Alignment.CenterVertically,
    ) {
        item { Text(label, color = Palette.TextSecondary, fontSize = 15.sp, modifier = Modifier.width(110.dp).padding(end = 6.dp)) }
        items(options, key = { it.second }) { (value, name) ->
            TvChip(name, selected = value == current, onClick = { onPick(value) })
        }
    }
}
