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
import androidx.compose.foundation.background
import androidx.compose.ui.draw.drawBehind
import androidx.compose.foundation.border
import androidx.compose.ui.unit.dp
import androidx.tv.material3.LocalContentColor
import androidx.tv.material3.MaterialTheme
import androidx.tv.material3.darkColorScheme
import com.zemu.tv.data.AppSettings

/**
 * The colors a theme controls. [light] flips to a light background with dark text; [glass] makes
 * panels and buttons translucent "frosted glass" over a soft colored backdrop.
 */
data class ThemeColors(val accent: Color, val background: Color, val light: Boolean = false, val glass: Boolean = false) {
    /** In light mode the theme's dark background becomes a pale tint of its accent. */
    val base: Color = if (light) lerp(Color(0xFFF4F4F7), accent, 0.05f) else background
    val surface: Color = when {
        glass && light -> Color.White.copy(alpha = 0.55f)
        glass -> Color.White.copy(alpha = 0.09f)
        light -> Color.White
        else -> lerp(background, Color.White, 0.07f)
    }
    val surfaceHigh: Color = when {
        glass && light -> Color.White.copy(alpha = 0.8f)
        glass -> Color.White.copy(alpha = 0.17f)
        light -> lerp(Color.White, Color.Black, 0.07f)
        else -> lerp(background, Color.White, 0.14f)
    }
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
    (if (theme == ThemePreset.CUSTOM) ThemeColors(Color(customAccent.toInt()), Color(customBackground.toInt()))
    else (ThemePreset.entries.firstOrNull { it.name == theme } ?: ThemePreset.CLASSIC).colors)
        .copy(light = lightMode, glass = glassStyle)

fun Color.toArgbLong(): Long = toArgb().toLong() and 0xFFFFFFFFL

/**
 * App colors. Reads go through snapshot state, so changing the theme recomposes every screen
 * without threading colors through each composable.
 */
object Palette {
    var colors by mutableStateOf(ThemePreset.CLASSIC.colors)

    /** True when the device can blur behind windows (Android 12+ and supported by the device). */
    var blurSupported: Boolean = false
    val Light: Boolean get() = colors.light
    val Glass: Boolean get() = colors.glass
    val Background: Color get() = colors.base
    val Surface: Color get() = colors.surface
    val SurfaceHigh: Color get() = colors.surfaceHigh
    val Accent: Color get() = colors.accent
    /** Text/icon color on top of [Accent]: black on bright accents (like neon green), white otherwise. */
    val OnAccent: Color get() = if (colors.accent.luminance() > 0.45f) Color(0xFF07130A) else Color.White

    val Text: Color get() = if (Light) Color(0xFF121216) else Color.White
    val TextSecondary: Color get() = if (Light) Color(0xFF4A4A55) else Color(0xFFB8B8C2)
    val TextMuted: Color get() = if (Light) Color(0xFF74747E) else Color(0xFF80808C)
    /** A focused button's fill and its content: white-on-dark normally, inverted in light mode. */
    val Focus: Color get() = if (Light) Color(0xFF121216) else Color.White
    val OnFocus: Color get() = if (Light) Color.White else Color.Black
    /** Outline around a focused card or tile. */
    val FocusBorder: Color get() = if (Light) Color(0xFF121216) else Color.White
    /** Hairline edge of glass panels. */
    val Edge: Color get() = if (Light) Color.Black.copy(alpha = 0.08f) else Color.White.copy(alpha = 0.16f)
    val Imdb = Color(0xFFF5C518)
    val Match: Color get() = if (Light) Color(0xFF14853B) else Color(0xFF46D369)
    val Cached: Color get() = if (Light) Color(0xFF9A5B00) else Color(0xFFFFC94D)
    val Info: Color get() = if (Light) Color(0xFF1E62C8) else Color(0xFF5AA9FF)
}

@Composable
fun ZemuTheme(colors: ThemeColors, content: @Composable () -> Unit) {
    Palette.colors = colors
    MaterialTheme(
        colorScheme = darkColorScheme(
            primary = colors.accent,
            onPrimary = if (colors.accent.luminance() > 0.45f) Color.Black else Color.White,
            background = colors.base,
            onBackground = Palette.Text,
            surface = colors.base,
            onSurface = Palette.Text,
            surfaceVariant = colors.surface,
            onSurfaceVariant = Palette.TextSecondary,
        ),
    ) {
        CompositionLocalProvider(LocalContentColor provides Palette.Text, content = content)
    }
}


/**
 * Background for panels, dialogs and cards: solid normally; frosted glass (translucent fill, light
 * top sheen and a hairline edge) when the glass style is on.
 */
fun androidx.compose.ui.Modifier.glassPanel(shape: androidx.compose.ui.graphics.Shape, solid: Color = Palette.Surface): androidx.compose.ui.Modifier =
    if (!Palette.Glass) this.then(androidx.compose.ui.Modifier.background(solid, shape))
    else this.then(
        androidx.compose.ui.Modifier
            // Without real blur behind it, glass needs a denser fill to stay readable.
            .background(
                if (Palette.Light) Color.White.copy(alpha = if (Palette.blurSupported) 0.72f else 0.92f)
                else Color(0xFF1C1C22).copy(alpha = if (Palette.blurSupported) 0.62f else 0.9f),
                shape,
            )
            .background(
                androidx.compose.ui.graphics.Brush.verticalGradient(
                    listOf(Color.White.copy(alpha = if (Palette.Light) 0.35f else 0.10f), Color.Transparent),
                ),
                shape,
            )
            .border(1.dp, Palette.Edge, shape),
    )

/** Page background: flat normally; with glass, soft glows of the accent behind the panels. */
fun androidx.compose.ui.Modifier.appBackground(): androidx.compose.ui.Modifier =
    if (!Palette.Glass) this.then(androidx.compose.ui.Modifier.background(Palette.Background))
    else this.then(
        androidx.compose.ui.Modifier
            .background(Palette.Background)
            .drawBehind {
                val glow = Palette.Accent.copy(alpha = if (Palette.Light) 0.22f else 0.20f)
                val second = lerp(Palette.Accent, Color(0xFF6E4BFF), 0.6f).copy(alpha = if (Palette.Light) 0.16f else 0.14f)
                drawRect(androidx.compose.ui.graphics.Brush.radialGradient(listOf(glow, Color.Transparent), center = androidx.compose.ui.geometry.Offset(size.width * 0.15f, size.height * 0.1f), radius = size.maxDimension * 0.6f))
                drawRect(androidx.compose.ui.graphics.Brush.radialGradient(listOf(second, Color.Transparent), center = androidx.compose.ui.geometry.Offset(size.width * 0.9f, size.height * 0.95f), radius = size.maxDimension * 0.55f))
            },
    )

/**
 * Call first thing inside a Dialog: with the glass style on Android 12+, blurs the screen behind
 * the dialog (where the device supports cross-window blur) instead of just dimming it.
 */
@Composable
fun DialogBackdropBlur() {
    if (!Palette.Glass || android.os.Build.VERSION.SDK_INT < 31) return
    val view = androidx.compose.ui.platform.LocalView.current
    androidx.compose.runtime.SideEffect {
        val window = (view.parent as? androidx.compose.ui.window.DialogWindowProvider)?.window ?: return@SideEffect
        window.addFlags(android.view.WindowManager.LayoutParams.FLAG_BLUR_BEHIND)
        window.attributes = window.attributes.apply { blurBehindRadius = 48 }
        window.setDimAmount(0.3f)
    }
}
