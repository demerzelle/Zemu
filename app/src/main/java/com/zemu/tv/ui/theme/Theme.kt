package com.zemu.tv.ui.theme

import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
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
 * panels and buttons translucent "frosted glass" over a soft colored backdrop; [style] switches the
 * whole look (PS2, Acidwave).
 * The nullable colors are the user's own picks from Appearance → Customize colors.
 */
data class ThemeColors(
    val accent: Color,
    val background: Color,
    val light: Boolean = false,
    val glass: Boolean = false,
    val style: UiStyle = UiStyle.NORMAL,
    val customBase: Color? = null,
    val customPanel: Color? = null,
    val customButton: Color? = null,
    val customText: Color? = null,
    /** Sub-style of [style] (e.g. Cybercore's "CLASSIC", "KAWAII", "XP"). */
    val variant: String = "",
    /** Accessibility: pure black and white, full-strength text and a bold outline on what's focused. */
    val highContrast: Boolean = false,
) {
    /** In light mode the theme's dark background becomes a pale tint of its accent. */
    val base: Color = customBase ?: if (light) lerp(Color(0xFFF4F4F7), accent, 0.05f) else background
    val surface: Color = customPanel ?: when {
        glass && light -> Color.White.copy(alpha = 0.55f)
        glass -> Color.White.copy(alpha = 0.09f)
        light -> if (customBase != null) lerp(base, Color.White, 0.6f) else Color.White
        else -> lerp(base, Color.White, 0.07f)
    }
    /** Buttons and raised rows (unfocused). */
    val surfaceHigh: Color = customButton ?: when {
        glass && light -> Color.White.copy(alpha = 0.8f)
        glass -> Color.White.copy(alpha = 0.17f)
        light -> if (customBase != null) lerp(base, Color.Black, 0.07f) else lerp(Color.White, Color.Black, 0.07f)
        else -> lerp(base, Color.White, 0.14f)
    }

    /** Applies saved overrides for [scope] ("<theme>/<dark|light>"); see [ColorRole]. */
    fun withOverrides(all: Map<String, Long>, scope: String): ThemeColors {
        fun get(r: ColorRole) = all["$scope/${r.key}"]?.let { Color(it.toInt()) }
        return copy(
            accent = get(ColorRole.ACCENT) ?: accent,
            customBase = get(ColorRole.BACKGROUND) ?: customBase,
            customPanel = get(ColorRole.PANEL) ?: customPanel,
            customButton = get(ColorRole.BUTTON) ?: customButton,
            customText = get(ColorRole.TEXT) ?: customText,
        )
    }
}

/** Whole-app looks that go beyond colors: shapes, type, panels and a backdrop scene. */
enum class UiStyle { NORMAL, PS2, ACID, ETHEREAL, RETRO, GRAFFITI, LIQUID, CATRAVE, TODDLER, GRADE, TEEN }

/** Colors the user can set per theme and per light/dark mode. */
enum class ColorRole(val key: String, val label: String) {
    ACCENT("accent", "Accent (focused button)"),
    BACKGROUND("background", "Background"),
    PANEL("panel", "Panels & rows"),
    BUTTON("button", "Buttons"),
    TEXT("text", "Text"),
}

/**
 * The five color palettes. Every color is spelled out for dark and light mode, so what the swatch
 * shows is exactly what the app uses; nothing is tinted or derived.
 */
enum class ThemePreset(
    val label: String,
    val accent: Long,
    val dark: List<Long>,
    val light: List<Long>,
    /** Stays dark in light mode (a white OLED theme makes no sense). */
    val alwaysDark: Boolean = false,
) {
    // Colors: background, panels & rows, buttons, text.
    CLASSIC("Zemu Neon", 0xFF39FF14, listOf(0xFF07090A, 0xFF121516, 0xFF1D2122, 0xFFFFFFFF), listOf(0xFFF3F6F2, 0xFFFFFFFF, 0xFFE4E9E3, 0xFF101410)),
    CRIMSON("Crimson", 0xFFE50914, listOf(0xFF0A0A0E, 0xFF16161B, 0xFF222229, 0xFFFFFFFF), listOf(0xFFF7F3F3, 0xFFFFFFFF, 0xFFEBE4E4, 0xFF161012)),
    OCEAN("Ocean Blue", 0xFF2F80ED, listOf(0xFF070B14, 0xFF111827, 0xFF1C2537, 0xFFFFFFFF), listOf(0xFFF1F5FB, 0xFFFFFFFF, 0xFFE1E8F3, 0xFF0D1422)),
    PURPLE("Royal Purple", 0xFF8B5CF6, listOf(0xFF0C0814, 0xFF171222, 0xFF231C31, 0xFFFFFFFF), listOf(0xFFF5F2FB, 0xFFFFFFFF, 0xFFE8E2F4, 0xFF15101F)),
    SUNSET("Sunset", 0xFFF97316, listOf(0xFF120A06, 0xFF1E140E, 0xFF2B1E15, 0xFFFFFFFF), listOf(0xFFFBF5F0, 0xFFFFFFFF, 0xFFF1E6DC, 0xFF1C120C)),
    /** Pure black: OLED pixels switch off, so it's the darkest and most power-saving look. */
    OLED("OLED Black", 0xFFE6E6E6, listOf(0xFF000000, 0xFF000000, 0xFF121212, 0xFFFFFFFF), listOf(0xFF000000, 0xFF000000, 0xFF121212, 0xFFFFFFFF), alwaysDark = true),
    /** Accessibility: black and white with a bright yellow focus. */
    HIGH_CONTRAST("High Contrast", 0xFFFFE600, listOf(0xFF000000, 0xFF000000, 0xFF1F1F1F, 0xFFFFFFFF), listOf(0xFF000000, 0xFF000000, 0xFF1F1F1F, 0xFFFFFFFF), alwaysDark = true),
    ;

    /** The exact colors; with [glass], panels and buttons stay see-through instead. */
    fun colors(light: Boolean = false, glass: Boolean = false): ThemeColors {
        val light = light && !alwaysDark
        // High contrast never goes see-through.
        val glass = glass && this != HIGH_CONTRAST
        val c = (if (light) this.light else dark).map { Color(it.toInt()) }
        return ThemeColors(
            accent = Color(accent.toInt()), background = Color(dark[0].toInt()), light = light, glass = glass, highContrast = this == HIGH_CONTRAST,
            customBase = c[0], customPanel = c[1].takeUnless { glass }, customButton = c[2].takeUnless { glass }, customText = c[3],
        )
    }

    val colors: ThemeColors get() = colors()

    companion object {
        /** Your own palette: starts from the one you were using, every color editable. */
        const val CUSTOM = "CUSTOM"
        /** Removed palettes map to their nearest one. */
        private val RENAMED = mapOf("ARCTIC" to "OCEAN", "EMERALD" to "CLASSIC", "ROSE" to "PURPLE", "GOLD" to "SUNSET", "SLATE" to "OCEAN")

        fun of(name: String) = entries.firstOrNull { it.name == (RENAMED[name] ?: name) } ?: CLASSIC
    }
}

/** The palette's own colors (Custom: Zemu Neon's, plus your saved picks applied later). */
fun AppSettings.themeColors(light: Boolean = lightMode): ThemeColors =
    if (theme == ThemePreset.CUSTOM) ThemePreset.CLASSIC.colors(light, glassStyle).copy(accent = Color(customAccent.toInt()))
    else ThemePreset.of(theme).colors(light, glassStyle)

/** Which colors your edits change: an animated theme with its own palette, else your palette. */
fun AppSettings.colorScope(light: Boolean = lightMode): String {
    val d = DynamicTheme.of(dynamicTheme)
    val name = when {
        // Each Cybercore desktop keeps its own colors.
        d == DynamicTheme.RETRO -> "RETRO-${variantOf(d)}"
        d.colorsFor(variantOf(d)) != null -> d.name
        else -> theme
    }
    return "$name/${if (light) "light" else "dark"}"
}

/** The chosen sub-theme of [d] (weather kind, holiday, Cybercore style). */
fun AppSettings.variantOf(d: DynamicTheme): String = themeVariants[d.name] ?: d.variants.firstOrNull()?.first.orEmpty()

/** Everything applied: palette, animated theme, light/dark and the user's exact colors. */
fun AppSettings.resolvedColors(light: Boolean = lightMode): ThemeColors {
    val d = DynamicTheme.of(dynamicTheme)
    val variant = variantOf(d)
    return d.applyTo(themeColors(light), variant).copy(style = d.style, variant = d.resolveVariant(variant))
        .withOverrides(colorOverrides, colorScope(light))
}

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
    val Style: UiStyle get() = colors.style
    val Background: Color get() = colors.base
    val Surface: Color get() = colors.surface
    val SurfaceHigh: Color get() = colors.surfaceHigh
    val Accent: Color get() = colors.accent
    /** Text/icon color on top of [Accent]: black on bright accents (like neon green), white otherwise. */
    val OnAccent: Color get() = if (colors.accent.luminance() > 0.45f) Color(0xFF07130A) else Color.White

    val Text: Color get() = colors.customText ?: if (Light) Color(0xFF121216) else Color.White
    val TextSecondary: Color get() = if (colors.highContrast) Text else colors.customText?.copy(alpha = 0.75f) ?: if (Light) Color(0xFF4A4A55) else Color(0xFFB8B8C2)
    val TextMuted: Color get() = if (colors.highContrast) Color(0xFFDDDDDD) else colors.customText?.copy(alpha = 0.55f) ?: if (Light) Color(0xFF74747E) else Color(0xFF80808C)
    /**
     * A focused button's fill and its content. Buttons are dark with light text in dark mode and
     * light with dark text in light mode; only the focused one takes the accent color.
     */
    val Focus: Color get() = Accent
    val OnFocus: Color get() = OnAccent
    /** Outline around a focused card or tile. */
    val FocusBorder: Color get() = Accent
    /** Hairline edge of glass panels. */
    val Edge: Color get() = if (Light) Color.Black.copy(alpha = 0.08f) else Color.White.copy(alpha = 0.16f)
    val Imdb = Color(0xFFF5C518)
    // Cybercore desktops are colorful, so its labels use the text color to stay readable.
    val Match: Color get() = if (Style == UiStyle.RETRO) Text else if (Light) Color(0xFF14853B) else Color(0xFF46D369)
    val Cached: Color get() = if (Light) Color(0xFF9A5B00) else Color(0xFFFFC94D)
    val Info: Color get() = if (Light) Color(0xFF1E62C8) else Color(0xFF5AA9FF)
}

@Composable
fun ZemuTheme(colors: ThemeColors, zoom: Int = 100, content: @Composable () -> Unit) {
    Palette.colors = colors
    // UI zoom: scaling the density resizes every dp and sp, so layouts reflow instead of being stretched.
    val density = androidx.compose.ui.platform.LocalDensity.current
    val zoomed = remember(density, zoom) { androidx.compose.ui.unit.Density(density.density * zoom / 100f, density.fontScale) }
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
        typography = styleTypography(colors.style, colors.variant),
    ) {
        CompositionLocalProvider(
            androidx.compose.ui.platform.LocalDensity provides zoomed,
            LocalContentColor provides Palette.Text,
            androidx.tv.material3.LocalTextStyle provides styleTextStyle(colors.style, colors.variant),
            content = content,
        )
    }
}

/** Acidwave's clipped corners (top-right and bottom-left), used for every button and panel. */
val AcidShape = androidx.compose.foundation.shape.CutCornerShape(topStart = 0.dp, topEnd = 12.dp, bottomEnd = 0.dp, bottomStart = 12.dp)

/**
 * Background for panels, dialogs and cards: solid normally; frosted glass (translucent fill, light
 * top sheen and a hairline edge) when the glass style is on.
 */
fun androidx.compose.ui.Modifier.glassPanel(shape: androidx.compose.ui.graphics.Shape, solid: Color = Palette.Surface): androidx.compose.ui.Modifier =
    stylePanel(shape, solid) ?: if (Palette.Style == UiStyle.PS2) this.then(
        // PS2 system menu: deep translucent blue with a faint glowing rim.
        androidx.compose.ui.Modifier
            .background(
                // A custom panel color is used exactly; otherwise the PS2 blue.
                Palette.colors.customPanel?.let { androidx.compose.ui.graphics.SolidColor(it) } ?: androidx.compose.ui.graphics.Brush.verticalGradient(
                    if (Palette.Light) listOf(Color(0xF2EEF3FF), Color(0xF2D5DEF2)) else listOf(Color(0xEE0E1A3A), Color(0xEE030818)),
                ),
                shape,
            )
            .border(1.dp, Color(0xFF6FB4FF).copy(alpha = 0.55f), shape),
    )
    else if (Palette.Style == UiStyle.ACID) this.then(
        // Acidwave: a solid slab with an accent rule and clipped corners.
        androidx.compose.ui.Modifier
            .background(solid, AcidShape)
            .border(2.dp, Palette.Accent, AcidShape),
    )
    else if (!Palette.Glass) this.then(androidx.compose.ui.Modifier.background(solid, shape))
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
