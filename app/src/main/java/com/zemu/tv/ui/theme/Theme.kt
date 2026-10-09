package com.zemu.tv.ui.theme

import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.graphics.toArgb
import androidx.tv.material3.LocalContentColor
import androidx.tv.material3.MaterialTheme
import androidx.tv.material3.darkColorScheme
import com.zemu.tv.data.AppSettings

/** The colors a theme controls; everything else (text, ratings, badges) stays fixed for legibility. */
data class ThemeColors(val accent: Color, val background: Color) {
    val surface: Color = lerp(background, Color.White, 0.07f)
    val surfaceHigh: Color = lerp(background, Color.White, 0.14f)
}

enum class ThemePreset(val label: String, val accent: Long, val background: Long) {
    CLASSIC("Zemu Neon", 0xFF39FF14, 0xFF07090A),
    CRIMSON("Crimson", 0xFFE50914, 0xFF0A0A0E),
    OLED("OLED Black", 0xFFE50914, 0xFF000000),
    OCEAN("Ocean Blue", 0xFF2F80ED, 0xFF070B14),
    ARCTIC("Arctic", 0xFF22D3EE, 0xFF0A1218),
    EMERALD("Emerald", 0xFF10B981, 0xFF06100C),
    PURPLE("Royal Purple", 0xFF8B5CF6, 0xFF0C0814),
    ROSE("Rose", 0xFFEC4899, 0xFF12070D),
    SUNSET("Sunset", 0xFFF97316, 0xFF120A06),
    GOLD("Gold", 0xFFEAB308, 0xFF0E0C05),
    SLATE("Slate", 0xFF94A3B8, 0xFF0F1115);

    val colors: ThemeColors get() = ThemeColors(Color(accent.toInt()), Color(background.toInt()))

    companion object {
        const val CUSTOM = "CUSTOM"
    }
}

fun AppSettings.themeColors(): ThemeColors =
    if (theme == ThemePreset.CUSTOM) ThemeColors(Color(customAccent.toInt()), Color(customBackground.toInt()))
    else (ThemePreset.entries.firstOrNull { it.name == theme } ?: ThemePreset.CLASSIC).colors

fun Color.toArgbLong(): Long = toArgb().toLong() and 0xFFFFFFFFL

/**
 * App colors. Reads go through snapshot state, so changing the theme recomposes every screen
 * without threading colors through each composable.
 */
object Palette {
    var colors by mutableStateOf(ThemePreset.CLASSIC.colors)

    val Background: Color get() = colors.background
    val Surface: Color get() = colors.surface
    val SurfaceHigh: Color get() = colors.surfaceHigh
    val Accent: Color get() = colors.accent
    /** Text/icon color on top of [Accent]: black on bright accents (like neon green), white otherwise. */
    val OnAccent: Color get() = if (colors.accent.luminance() > 0.45f) Color(0xFF07130A) else Color.White

    val TextSecondary = Color(0xFFB8B8C2)
    val TextMuted = Color(0xFF80808C)
    val Imdb = Color(0xFFF5C518)
    val Match = Color(0xFF46D369)
    val Cached = Color(0xFFFFC94D)
    val Info = Color(0xFF5AA9FF)
}

@Composable
fun ZemuTheme(colors: ThemeColors, content: @Composable () -> Unit) {
    Palette.colors = colors
    MaterialTheme(
        colorScheme = darkColorScheme(
            primary = colors.accent,
            onPrimary = if (colors.accent.luminance() > 0.45f) Color.Black else Color.White,
            background = colors.background,
            onBackground = Color.White,
            surface = colors.background,
            onSurface = Color.White,
            surfaceVariant = colors.surface,
            onSurfaceVariant = Palette.TextSecondary,
        ),
    ) {
        CompositionLocalProvider(LocalContentColor provides Color.White, content = content)
    }
}
