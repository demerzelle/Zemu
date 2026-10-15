package com.zemu.tv.ui.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.tv.material3.Text
import com.zemu.tv.data.AppSettings
import com.zemu.tv.ui.components.FocusSurface
import com.zemu.tv.ui.theme.Palette
import com.zemu.tv.ui.theme.ThemeColors
import com.zemu.tv.ui.theme.ThemePreset
import com.zemu.tv.ui.theme.themeColors
import com.zemu.tv.ui.theme.colorScope
import com.zemu.tv.ui.theme.resolvedColors
import com.zemu.tv.ui.theme.toArgbLong

private data class Hsv(val h: Float, val s: Float, val v: Float) {
    fun color(): Color = Color.hsv(h.coerceIn(0f, 360f), s.coerceIn(0f, 1f), v.coerceIn(0f, 1f))

    companion object {
        fun of(c: Color): Hsv {
            val hsv = FloatArray(3)
            android.graphics.Color.colorToHSV(android.graphics.Color.argb(255, (c.red * 255).toInt(), (c.green * 255).toInt(), (c.blue * 255).toInt()), hsv)
            return Hsv(hsv[0], hsv[1], hsv[2])
        }
    }
}

/** The five palettes and Custom, each swatch drawn in its exact colors for the current mode. */
@Composable
fun ThemePicker(settings: AppSettings, update: ((AppSettings) -> AppSettings) -> Unit) {
    LazyRow(
        contentPadding = PaddingValues(vertical = 10.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        items(ThemePreset.entries.toList(), key = { it.name }) { p ->
            ThemeSwatch(p.label, p.colors(settings.lightMode, settings.glassStyle), selected = settings.theme == p.name) { update { it.copy(theme = p.name) } }
        }
        item(key = "custom") {
            val mine = settings.copy(theme = ThemePreset.CUSTOM, dynamicTheme = "NONE").resolvedColors()
            ThemeSwatch("Custom", mine, selected = settings.theme == ThemePreset.CUSTOM) { update { seedCustom(it) } }
        }
    }
}

/**
 * Switches to the Custom palette, starting it from the palette in use (both modes) unless it
 * already has colors, so nothing changes until you edit.
 */
fun seedCustom(s: AppSettings): AppSettings {
    if (s.theme == ThemePreset.CUSTOM) return s
    val preset = ThemePreset.of(s.theme)
    var o = s.colorOverrides
    for (light in listOf(false, true)) {
        val mode = if (light) "light" else "dark"
        if (o.keys.any { it.startsWith("CUSTOM/$mode/") }) continue
        val c = preset.colors(light, s.glassStyle)
        listOf(
            com.zemu.tv.ui.theme.ColorRole.ACCENT to c.accent, com.zemu.tv.ui.theme.ColorRole.BACKGROUND to c.base,
            com.zemu.tv.ui.theme.ColorRole.PANEL to c.surface, com.zemu.tv.ui.theme.ColorRole.BUTTON to c.surfaceHigh,
            com.zemu.tv.ui.theme.ColorRole.TEXT to (c.customText ?: Color.White),
        ).forEach { (r, col) -> o = o + ("CUSTOM/$mode/${r.key}" to col.toArgbLong()) }
    }
    return s.copy(theme = ThemePreset.CUSTOM, customAccent = preset.accent, colorOverrides = o)
}

@Composable
private fun ThemeSwatch(label: String, colors: ThemeColors, selected: Boolean, onClick: () -> Unit) {
    FocusSurface(
        onClick = onClick,
        shape = RoundedCornerShape(12.dp),
        // Exactly the palette's colors, focused or not (focus shows as the outline).
        containerColor = colors.base,
        contentColor = colors.customText ?: Palette.Text,
        focusedContainerColor = colors.base,
        focusedContentColor = colors.customText ?: Palette.Text,
        focusedBorder = Palette.FocusBorder,
        focusedScale = 1.06f,
    ) {
        Column(
            Modifier
                .width(132.dp)
                .border(2.dp, if (selected) colors.accent else Color.White.copy(alpha = 0.12f), RoundedCornerShape(12.dp))
                .padding(12.dp),
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Box(Modifier.size(22.dp).background(colors.accent, CircleShape))
                Box(Modifier.size(22.dp).background(colors.surfaceHigh, CircleShape))
                Box(Modifier.size(22.dp).background(colors.surface, CircleShape))
            }
            Spacer(Modifier.height(10.dp))
            Box(Modifier.fillMaxWidth().height(6.dp).background(colors.accent, RoundedCornerShape(3.dp)))
            Spacer(Modifier.height(8.dp))
            Text((if (selected) "✓ " else "") + label, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
        }
    }
}

/** A D-pad slider: focus it, then Left/Right change the value (holding repeats). */
@Composable
fun TvSlider(label: String, value: Float, step: Float, track: Brush, valueText: String? = null, onChange: (Float) -> Unit) {
    var focused by remember { mutableStateOf(false) }
    var widthPx by remember { mutableStateOf(0) }
    val density = LocalDensity.current
    Row(
        Modifier
            .fillMaxWidth()
            .padding(vertical = 4.dp)
            .onFocusChanged { focused = it.isFocused }
            .onPreviewKeyEvent { e ->
                if (e.type != KeyEventType.KeyDown) return@onPreviewKeyEvent false
                when (e.key) {
                    Key.DirectionLeft -> { onChange((value - step).coerceIn(0f, 1f)); true }
                    Key.DirectionRight -> { onChange((value + step).coerceIn(0f, 1f)); true }
                    else -> false
                }
            }
            .focusable()
            .background(if (focused) Palette.SurfaceHigh else Palette.Surface, RoundedCornerShape(10.dp))
            .border(2.dp, if (focused) Palette.Accent else Color.Transparent, RoundedCornerShape(10.dp))
            .padding(horizontal = 18.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.width(230.dp))
        Box(
            Modifier
                .weight(1f)
                .height(14.dp)
                .onSizeChanged { widthPx = it.width }
                .pointerInput(Unit) { detectTapGestures { o -> onChange((o.x / size.width).coerceIn(0f, 1f)) } }
                .background(track, RoundedCornerShape(7.dp)),
            contentAlignment = Alignment.CenterStart,
        ) {
            val knobX = with(density) { (widthPx * value.coerceIn(0f, 1f)).toDp() } - 9.dp
            Box(
                Modifier
                    .offset(x = knobX)
                    .size(18.dp)
                    .background(Color.White, CircleShape)
                    .border(2.dp, Color.Black.copy(alpha = 0.5f), CircleShape),
            )
        }
        Text(valueText ?: "${(value * 100).toInt()}%", fontSize = 13.sp, color = Palette.TextSecondary, modifier = Modifier.width(64.dp).padding(start = 12.dp))
    }
}

/**
 * Appearance → Customize colors: every color of the theme showing now, separately for light and
 * dark mode (and for animated themes with their own palette, like PS2 or Acidwave). Saved per theme and mode.
 */
@Composable
fun ColorCustomizer(settings: AppSettings, update: ((AppSettings) -> AppSettings) -> Unit) {
    var role by remember { mutableStateOf(com.zemu.tv.ui.theme.ColorRole.ACCENT) }
    val scope = settings.colorScope()
    val colors = settings.resolvedColors()
    val current = when (role) {
        com.zemu.tv.ui.theme.ColorRole.ACCENT -> colors.accent
        com.zemu.tv.ui.theme.ColorRole.BACKGROUND -> colors.base
        com.zemu.tv.ui.theme.ColorRole.PANEL -> colors.surface
        com.zemu.tv.ui.theme.ColorRole.BUTTON -> colors.surfaceHigh
        com.zemu.tv.ui.theme.ColorRole.TEXT -> Palette.Text
    }
    val key = "$scope/${role.key}"
    val themeName = scope.substringBefore('/').let { n ->
        if (n.startsWith("RETRO-")) "Cybercore " + n.removePrefix("RETRO-").lowercase().replaceFirstChar { it.uppercase() }
        else com.zemu.tv.ui.theme.DynamicTheme.entries.firstOrNull { it.name == n }?.label
            ?: ThemePreset.entries.firstOrNull { it.name == n }?.label ?: "Custom"
    }
    Text(
        "Editing $themeName · ${if (settings.lightMode) "light" else "dark"} mode. Switch light mode or the theme to edit theirs.",
        color = Palette.TextSecondary, fontSize = 13.sp,
    )
    LazyRow(contentPadding = PaddingValues(vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        items(com.zemu.tv.ui.theme.ColorRole.entries.toList(), key = { it.name }) { r ->
            val custom = "$scope/${r.key}" in settings.colorOverrides
            com.zemu.tv.ui.components.TvChip(r.label + if (custom) " •" else "", selected = r == role, onClick = { role = r })
        }
    }
    val hsv = Hsv.of(current)
    // Exact: what you pick is stored and used as-is. Editing a preset palette turns it into Custom.
    fun set(h: Hsv) = update { s0 ->
        val s = if (scope.substringBefore('/') == s0.theme && s0.theme != ThemePreset.CUSTOM) seedCustom(s0) else s0
        s.copy(colorOverrides = s.colorOverrides + ("${s.colorScope()}/${role.key}" to h.color().toArgbLong()))
    }
    Text("%s  #%06X".format(role.label, current.toArgbLong() and 0xFFFFFF), fontSize = 14.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(bottom = 4.dp))
    val hueBrush = Brush.horizontalGradient((0..6).map { Color.hsv(it * 60f % 360f, 1f, 1f) })
    TvSlider("Hue", hsv.h / 360f, 1f / 72, hueBrush) { set(hsv.copy(h = it * 360f, s = hsv.s.coerceAtLeast(0.05f))) }
    TvSlider("Saturation", hsv.s, 0.05f, Brush.horizontalGradient(listOf(hsv.copy(s = 0f).color(), hsv.copy(s = 1f).color()))) { set(hsv.copy(s = it)) }
    TvSlider("Brightness", hsv.v, 0.05f, Brush.horizontalGradient(listOf(Color.Black, hsv.copy(v = 1f).color()))) { set(hsv.copy(v = it)) }
    Row(Modifier.padding(top = 6.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        com.zemu.tv.ui.components.TvButton("Reset ${role.label.substringBefore(" (")}", onClick = { update { it.copy(colorOverrides = it.colorOverrides - key) } })
        com.zemu.tv.ui.components.TvButton("Reset all colors for $themeName (${if (settings.lightMode) "light" else "dark"})", onClick = {
            update { s -> s.copy(colorOverrides = s.colorOverrides.filterKeys { !it.startsWith("$scope/") }) }
        })
    }
}
