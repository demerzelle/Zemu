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
import com.zemu.tv.ui.theme.ColorRole
import com.zemu.tv.ui.theme.SavedPalette
import com.zemu.tv.ui.theme.glassPanel
import androidx.compose.ui.focus.focusRequester

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

/**
 * The palettes and Custom, each swatch drawn in its exact colors for the current mode. With an
 * animated theme that has its own colors on, a palette recolors that theme (menus and scene)
 * instead, and the theme's own colors come first to go back to.
 */
@Composable
fun ThemePicker(settings: AppSettings, update: ((AppSettings) -> AppSettings) -> Unit) {
    val scopeName = settings.colorScope().substringBefore('/')
    val animated = scopeName != settings.theme
    val recolored = animated && settings.colorOverrides.keys.any { it.startsWith("$scopeName/") }
    LazyRow(
        contentPadding = PaddingValues(vertical = 10.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        if (animated) item(key = "own") {
            val own = settings.copy(colorOverrides = settings.colorOverrides.filterKeys { !it.startsWith("$scopeName/") }).resolvedColors()
            ThemeSwatch("Original", own, selected = !recolored) {
                update { s -> s.copy(colorOverrides = s.colorOverrides.filterKeys { !it.startsWith("$scopeName/") }) }
            }
        }
        items(ThemePreset.entries.toList(), key = { it.name }) { p ->
            ThemeSwatch(p.label, p.colors(settings.lightMode, settings.glassStyle), selected = settings.theme == p.name && (!animated || recolored)) {
                update { s -> if (animated) s.copy(theme = p.name).recolor { light -> p.colors(light) } else s.copy(theme = p.name) }
            }
        }
        item(key = "custom") {
            val mine = settings.copy(theme = ThemePreset.CUSTOM, dynamicTheme = "NONE").resolvedColors()
            ThemeSwatch("Custom", mine, selected = settings.theme == ThemePreset.CUSTOM && (!animated || recolored)) {
                update { s ->
                    if (!animated) seedCustom(s)
                    else seedCustom(s).let { c -> c.recolor { light -> c.copy(dynamicTheme = "NONE", glassStyle = false).resolvedColors(light) } }
                }
            }
        }
    }
}

/** A color scope's display name: "Cybercore Xp", "Acidwave", "Crimson", … */
private fun themeLabel(scopeName: String): String =
    if (scopeName.startsWith("RETRO-")) com.zemu.tv.ui.theme.DynamicTheme.RETRO.variants.firstOrNull { it.first == scopeName.removePrefix("RETRO-") }?.let { "Cybercore " + it.second } ?: "Cybercore"
    else com.zemu.tv.ui.theme.DynamicTheme.entries.firstOrNull { it.name == scopeName }?.label
        ?: ThemePreset.entries.firstOrNull { it.name == scopeName }?.label ?: "Custom"

/** Every color role's value in [c], by role key; the scene takes the accent. */
private fun rolesOf(c: ThemeColors): Map<String, Long> = mapOf(
    ColorRole.ACCENT to c.accent, ColorRole.BACKGROUND to c.base, ColorRole.PANEL to c.surface, ColorRole.BUTTON to c.surfaceHigh,
    ColorRole.TEXT to (c.customText ?: if (c.light) Color(0xFF121216) else Color.White), ColorRole.SCENE to c.accent,
).entries.associate { it.key.key to it.value.toArgbLong() }

/** Writes [palette]'s colors (both modes) over the active animated theme's own. */
private fun AppSettings.recolor(palette: (light: Boolean) -> ThemeColors): AppSettings =
    withColors(rolesOf(palette(false)), light = false).withColors(rolesOf(palette(true)), light = true)

/**
 * Sets colors (role key to ARGB) for the theme showing now in one mode. Editing a preset palette
 * turns it into Custom first, so presets themselves never change.
 */
fun AppSettings.withColors(colors: Map<String, Long>, light: Boolean = lightMode): AppSettings {
    val s = if (colorScope().substringBefore('/') == theme && theme != ThemePreset.CUSTOM) seedCustom(this) else this
    val scope = s.colorScope(light)
    return s.copy(colorOverrides = s.colorOverrides + colors.mapKeys { "$scope/${it.key}" })
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
            ColorRole.ACCENT to c.accent, ColorRole.BACKGROUND to c.base,
            ColorRole.PANEL to c.surface, ColorRole.BUTTON to c.surfaceHigh,
            ColorRole.TEXT to (c.customText ?: Color.White),
        ).forEach { (r, col) -> o = o + ("CUSTOM/$mode/${r.key}" to col.toArgbLong()) }
    }
    return s.copy(theme = ThemePreset.CUSTOM, customAccent = preset.accent, colorOverrides = o)
}

@Composable
private fun ThemeSwatch(label: String, colors: ThemeColors, selected: Boolean, onClick: () -> Unit) {
    FocusSurface(
        onClick = onClick,
        shape = com.zemu.tv.ui.theme.boxy(RoundedCornerShape(12.dp)),
        // Exactly the palette's colors, focused or not (focus shows as the outline).
        containerColor = colors.base,
        contentColor = colors.customText ?: Palette.Text,
        focusedContainerColor = colors.base,
        focusedContentColor = colors.customText ?: Palette.Text,
        focusedBorder = Palette.FocusBorder,
        focusedScale = 1.06f,
        bevel = false,
    ) {
        Column(
            Modifier
                .width(132.dp)
                .border(2.dp, if (selected) colors.accent else Color.White.copy(alpha = 0.12f), com.zemu.tv.ui.theme.boxy(RoundedCornerShape(12.dp)))
                .padding(12.dp),
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Box(Modifier.size(22.dp).background(colors.accent, com.zemu.tv.ui.theme.boxy(CircleShape)))
                Box(Modifier.size(22.dp).background(colors.surfaceHigh, com.zemu.tv.ui.theme.boxy(CircleShape)))
                Box(Modifier.size(22.dp).background(colors.surface, com.zemu.tv.ui.theme.boxy(CircleShape)))
            }
            Spacer(Modifier.height(10.dp))
            Box(Modifier.fillMaxWidth().height(6.dp).background(colors.accent, com.zemu.tv.ui.theme.boxy(RoundedCornerShape(3.dp))))
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
            .background(if (focused) Palette.SurfaceHigh else Palette.Surface, com.zemu.tv.ui.theme.boxy(RoundedCornerShape(10.dp)))
            .border(2.dp, if (focused) Palette.Accent else Color.Transparent, com.zemu.tv.ui.theme.boxy(RoundedCornerShape(10.dp)))
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
                .background(track, com.zemu.tv.ui.theme.boxy(RoundedCornerShape(7.dp))),
            contentAlignment = Alignment.CenterStart,
        ) {
            val knobX = with(density) { (widthPx * value.coerceIn(0f, 1f)).toDp() } - 9.dp
            Box(
                Modifier
                    .offset(x = knobX)
                    .size(18.dp)
                    .background(Color.White, com.zemu.tv.ui.theme.boxy(CircleShape))
                    .border(2.dp, Color.Black.copy(alpha = 0.5f), com.zemu.tv.ui.theme.boxy(CircleShape)),
            )
        }
        Text(valueText ?: "${(value * 100).toInt()}%", fontSize = 13.sp, color = Palette.TextSecondary, modifier = Modifier.width(64.dp).padding(start = 12.dp))
    }
}

/**
 * Appearance → Customize colors: every color the theme showing now uses, as a palette of swatches;
 * pick one and change it. Separate for light and dark mode, and for animated themes with their own
 * palette (PS2, Acidwave, each Cybercore desktop, …). Palettes can be saved, named and deleted.
 */
@Composable
fun ColorCustomizer(settings: AppSettings, updateLook: ((AppSettings) -> AppSettings) -> Unit, update: ((AppSettings) -> AppSettings) -> Unit) {
    var role by remember { mutableStateOf(ColorRole.ACCENT) }
    var naming by remember { mutableStateOf(false) }
    var deleting by remember { mutableStateOf(false) }
    val scope = settings.colorScope()
    val scopeName = scope.substringBefore('/')
    val colors = settings.resolvedColors()
    val own = settings.copy(colorOverrides = settings.colorOverrides.filterKeys { !it.startsWith("$scope/") }).resolvedColors()
    // The scene swatch only means something with an animated theme on.
    val roles = ColorRole.entries.filter { it != ColorRole.SCENE || settings.dynamicTheme != "NONE" }
    fun valueOf(r: ColorRole): Color = when (r) {
        ColorRole.ACCENT -> colors.accent
        ColorRole.BACKGROUND -> colors.base
        ColorRole.PANEL -> colors.surface
        ColorRole.BUTTON -> colors.surfaceHigh
        ColorRole.TEXT -> colors.customText ?: Palette.Text
        ColorRole.SCENE -> colors.sceneTint ?: own.accent
    }
    val current = valueOf(role)
    val key = "$scope/${role.key}"
    val themeName = themeLabel(scopeName)
    val mode = if (settings.lightMode) "light" else "dark"
    Text("Editing $themeName · $mode mode. Switch light mode or the theme to edit theirs.", color = Palette.TextSecondary, fontSize = 13.sp)
    LazyRow(contentPadding = PaddingValues(vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        items(roles, key = { it.name }) { r ->
            PaletteSwatch(r.label.substringBefore(" ("), valueOf(r), selected = r == role, edited = "$scope/${r.key}" in settings.colorOverrides) { role = r }
        }
    }
    val hsv = Hsv.of(current)
    // Exact: what you pick is stored and used as-is.
    fun set(h: Hsv) = update { it.withColors(mapOf(role.key to h.color().toArgbLong())) }
    Text("%s  #%06X".format(role.label, current.toArgbLong() and 0xFFFFFF), fontSize = 14.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(bottom = 4.dp))
    val hueBrush = Brush.horizontalGradient((0..6).map { Color.hsv(it * 60f % 360f, 1f, 1f) })
    TvSlider("Hue", hsv.h / 360f, 1f / 72, hueBrush) { set(hsv.copy(h = it * 360f, s = hsv.s.coerceAtLeast(0.05f))) }
    TvSlider("Saturation", hsv.s, 0.05f, Brush.horizontalGradient(listOf(hsv.copy(s = 0f).color(), hsv.copy(s = 1f).color()))) { set(hsv.copy(s = it)) }
    TvSlider("Brightness", hsv.v, 0.05f, Brush.horizontalGradient(listOf(Color.Black, hsv.copy(v = 1f).color()))) { set(hsv.copy(v = it)) }
    Row(Modifier.padding(top = 6.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        com.zemu.tv.ui.components.TvButton("Reset ${role.label.substringBefore(" (")}", onClick = { update { it.copy(colorOverrides = it.colorOverrides - key) } })
        com.zemu.tv.ui.components.TvButton("Reset all colors for $themeName ($mode)", onClick = {
            updateLook { s -> s.copy(colorOverrides = s.colorOverrides.filterKeys { !it.startsWith("$scope/") }) }
        })
    }

    // Saved palettes: for every theme, or only for this one.
    val saved = settings.savedPalettes.filter { it.theme.isEmpty() || it.theme == scopeName }
    Text("Saved palettes", fontSize = 15.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(top = 14.dp))
    LazyRow(contentPadding = PaddingValues(vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
        items(saved, key = { it.theme + "|" + it.name }) { p ->
            SavedPaletteSwatch(p, if (p.theme.isEmpty()) "Any theme" else "Only $themeName") { updateLook { it.withColors(p.colors) } }
        }
        item(key = "save") { com.zemu.tv.ui.components.TvButton("Save these colors…", onClick = { naming = true }) }
        if (saved.isNotEmpty()) item(key = "delete") { com.zemu.tv.ui.components.TvButton("Delete…", onClick = { deleting = true }) }
    }
    if (naming) SavePaletteDialog(themeName, onDismiss = { naming = false }) { name, onlyHere ->
        naming = false
        val p = SavedPalette(name, roles.associate { it.key to valueOf(it).toArgbLong() }, if (onlyHere) scopeName else "")
        update { s -> s.copy(savedPalettes = s.savedPalettes.filterNot { it.name == p.name && it.theme == p.theme } + p) }
    }
    if (deleting) com.zemu.tv.ui.components.ChoiceDialog(
        title = "Delete palettes",
        options = saved.map { com.zemu.tv.ui.components.ChoiceOption(it.theme + "|" + it.name, it.name, if (it.theme.isEmpty()) "Any theme" else themeLabel(it.theme)) },
        selected = emptySet(),
        onToggle = { id -> update { s -> s.copy(savedPalettes = s.savedPalettes.filterNot { it.theme + "|" + it.name == id }) } },
        onDismiss = { deleting = false },
    )
}

/** One color of the palette: its swatch, name and hex. */
@Composable
private fun PaletteSwatch(label: String, color: Color, selected: Boolean, edited: Boolean, onClick: () -> Unit) {
    FocusSurface(onClick = onClick, shape = com.zemu.tv.ui.theme.boxy(RoundedCornerShape(10.dp)), focusedScale = 1.05f, bevel = false) {
        Column(
            Modifier
                .width(118.dp)
                .border(2.dp, if (selected) Palette.Accent else Color.Transparent, com.zemu.tv.ui.theme.boxy(RoundedCornerShape(10.dp)))
                .padding(8.dp),
        ) {
            Box(Modifier.fillMaxWidth().height(44.dp).background(color, com.zemu.tv.ui.theme.boxy(RoundedCornerShape(6.dp))).border(1.dp, Palette.TextMuted, com.zemu.tv.ui.theme.boxy(RoundedCornerShape(6.dp))))
            Text(label + if (edited) " •" else "", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, modifier = Modifier.padding(top = 6.dp))
            Text("#%06X".format(color.toArgbLong() and 0xFFFFFF), fontSize = 11.sp, color = Palette.TextSecondary)
        }
    }
}

@Composable
private fun SavedPaletteSwatch(p: SavedPalette, where: String, onClick: () -> Unit) {
    FocusSurface(onClick = onClick, shape = com.zemu.tv.ui.theme.boxy(RoundedCornerShape(10.dp)), focusedScale = 1.05f, bevel = false) {
        Column(Modifier.width(150.dp).padding(8.dp)) {
            Row(Modifier.fillMaxWidth().height(30.dp)) {
                ColorRole.entries.mapNotNull { p.colors[it.key] }.forEach { Box(Modifier.weight(1f).height(30.dp).background(Color(it.toInt()))) }
            }
            Text(p.name, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, modifier = Modifier.padding(top = 6.dp))
            Text(where, fontSize = 11.sp, color = Palette.TextSecondary, maxLines = 1)
        }
    }
}

@Composable
private fun SavePaletteDialog(themeName: String, onDismiss: () -> Unit, onSave: (name: String, onlyHere: Boolean) -> Unit) {
    var name by remember { mutableStateOf("") }
    val field = remember { androidx.compose.ui.focus.FocusRequester() }
    androidx.compose.ui.window.Dialog(onDismissRequest = onDismiss) {
        com.zemu.tv.ui.theme.DialogBackdropBlur()
        Column(Modifier.width(720.dp).glassPanel(com.zemu.tv.ui.theme.boxy(RoundedCornerShape(14.dp))).padding(24.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text("Save palette", fontSize = 22.sp, fontWeight = FontWeight.Bold)
            com.zemu.tv.ui.components.TvTextField(name, { name = it.take(30) }, "Name", Modifier.fillMaxWidth().focusRequester(field))
            val n = name.trim().ifEmpty { "My palette" }
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                com.zemu.tv.ui.components.TvButton("For every theme", onClick = { onSave(n, false) })
                com.zemu.tv.ui.components.TvButton("Only for $themeName", onClick = { onSave(n, true) })
                com.zemu.tv.ui.components.TvButton("Cancel", onClick = onDismiss)
            }
        }
        androidx.compose.runtime.LaunchedEffect(Unit) { kotlinx.coroutines.delay(100); runCatching { field.requestFocus() } }
    }
}

/** After a theme change: keep it, or it goes back on its own when the countdown runs out. */
@Composable
fun KeepChangesDialog(changes: Int, onKeep: () -> Unit, onRevert: () -> Unit) {
    var left by remember { mutableStateOf(15) }
    androidx.compose.runtime.LaunchedEffect(changes) {
        left = 15
        while (left > 0) { kotlinx.coroutines.delay(1000); left-- }
        onRevert()
    }
    val ok = remember { androidx.compose.ui.focus.FocusRequester() }
    androidx.compose.ui.window.Dialog(onDismissRequest = onRevert) {
        com.zemu.tv.ui.theme.DialogBackdropBlur()
        Column(Modifier.width(520.dp).glassPanel(com.zemu.tv.ui.theme.boxy(RoundedCornerShape(14.dp))).padding(24.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text("Keep changes?", fontSize = 22.sp, fontWeight = FontWeight.Bold)
            Text("Going back to your previous theme in ${left}s.", color = Palette.TextSecondary, fontSize = 15.sp)
            Row(Modifier.padding(top = 6.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                com.zemu.tv.ui.components.TvButton("OK", onClick = onKeep, modifier = Modifier.focusRequester(ok))
                com.zemu.tv.ui.components.TvButton("Cancel", onClick = onRevert)
            }
        }
        androidx.compose.runtime.LaunchedEffect(Unit) { kotlinx.coroutines.delay(100); runCatching { ok.requestFocus() } }
    }
}
