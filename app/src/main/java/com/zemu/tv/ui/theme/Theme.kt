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
            customBase = get(ColorRole.BACKGROUND),
            customPanel = get(ColorRole.PANEL),
            customButton = get(ColorRole.BUTTON),
            customText = get(ColorRole.TEXT),
        )
    }
}

/** Whole-app looks that go beyond colors: shapes, type, panels and a backdrop scene. */
enum class UiStyle { NORMAL, PS2, ACID }

/** Colors the user can set per theme and per light/dark mode. */
enum class ColorRole(val key: String, val label: String) {
    ACCENT("accent", "Accent (focused button)"),
    BACKGROUND("background", "Background"),
    PANEL("panel", "Panels & rows"),
    BUTTON("button", "Buttons"),
    TEXT("text", "Text"),
}

enum class ThemePreset(val label: String, val accent: Long, val background: Long) {
    CLASSIC("Zemu Neon", 0xFF39FF14, 0xFF07090A),
    CRIMSON("Crimson", 0xFFE50914, 0xFF0A0A0E),
    OCEAN("Ocean Blue", 0xFF2F80ED, 0xFF070B14),
    EMERALD("Emerald", 0xFF10B981, 0xFF06100C),
    PURPLE("Royal Purple", 0xFF8B5CF6, 0xFF0C0814),
    ROSE("Rose", 0xFFEC4899, 0xFF12070D),
    SUNSET("Sunset", 0xFFF97316, 0xFF120A06),
    GOLD("Gold", 0xFFEAB308, 0xFF0E0C05),
    SLATE("Slate", 0xFF94A3B8, 0xFF0F1115);

    val colors: ThemeColors get() = ThemeColors(Color(accent.toInt()), Color(background.toInt()))

    companion object {
        /** Older "Custom" theme: still honored, but colors are now set with Customize colors. */
        const val CUSTOM = "CUSTOM"
        /** Removed presets map to their nearest one. */
        private val RENAMED = mapOf("OLED" to "CRIMSON", "ARCTIC" to "OCEAN")

        fun of(name: String) = entries.firstOrNull { it.name == (RENAMED[name] ?: name) } ?: CLASSIC
    }
}

fun AppSettings.themeColors(): ThemeColors =
    (if (theme == ThemePreset.CUSTOM) ThemeColors(Color(customAccent.toInt()), Color(customBackground.toInt()))
    else ThemePreset.of(theme).colors)
        .copy(light = lightMode, glass = glassStyle)

/** Which theme's custom colors apply: an animated theme with its own palette, else the color theme. */
fun AppSettings.colorScope(light: Boolean = lightMode): String {
    val d = DynamicTheme.of(dynamicTheme)
    val name = if (d.accent != null) d.name else theme
    return "$name/${if (light) "light" else "dark"}"
}

/** Everything applied: color theme, animated theme, light/dark and the user's custom colors. */
fun AppSettings.resolvedColors(light: Boolean = lightMode): ThemeColors {
    val d = DynamicTheme.of(dynamicTheme)
    val style = when (d) { DynamicTheme.Y2K -> UiStyle.PS2; DynamicTheme.ACIDWAVE -> UiStyle.ACID; else -> UiStyle.NORMAL }
    return d.applyTo(themeColors().copy(light = light)).copy(style = style)
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
    val TextSecondary: Color get() = colors.customText?.copy(alpha = 0.75f) ?: if (Light) Color(0xFF4A4A55) else Color(0xFFB8B8C2)
    val TextMuted: Color get() = colors.customText?.copy(alpha = 0.55f) ?: if (Light) Color(0xFF74747E) else Color(0xFF80808C)
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
        typography = when (colors.style) { UiStyle.PS2 -> ps2Typography; UiStyle.ACID -> acidTypography; else -> androidx.tv.material3.Typography() },
    ) {
        CompositionLocalProvider(
            LocalContentColor provides Palette.Text,
            androidx.tv.material3.LocalTextStyle provides when (colors.style) {
                UiStyle.PS2 -> PS2_TEXT
                UiStyle.ACID -> ACID_TEXT
                else -> androidx.compose.ui.text.TextStyle.Default
            },
            content = content,
        )
    }
}

/** PS2: the soft blue glow of the PS2 system menus, slightly spaced. */
private val PS2_TEXT = androidx.compose.ui.text.TextStyle(
    shadow = androidx.compose.ui.graphics.Shadow(Color(0x996FB4FF), androidx.compose.ui.geometry.Offset.Zero, 10f),
    letterSpacing = androidx.compose.ui.unit.TextUnit(0.5f, androidx.compose.ui.unit.TextUnitType.Sp),
)

/** Acidwave: technical monospace, wide tracking, like an interface readout. */
private val ACID_TEXT = androidx.compose.ui.text.TextStyle(
    fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace,
    letterSpacing = androidx.compose.ui.unit.TextUnit(0.6f, androidx.compose.ui.unit.TextUnitType.Sp),
)

private fun styled(extra: androidx.compose.ui.text.TextStyle): androidx.tv.material3.Typography {
    val t = androidx.tv.material3.Typography()
    fun androidx.compose.ui.text.TextStyle.x() = merge(extra)
    return t.copy(
        displayLarge = t.displayLarge.x(), displayMedium = t.displayMedium.x(), displaySmall = t.displaySmall.x(),
        headlineLarge = t.headlineLarge.x(), headlineMedium = t.headlineMedium.x(), headlineSmall = t.headlineSmall.x(),
        titleLarge = t.titleLarge.x(), titleMedium = t.titleMedium.x(), titleSmall = t.titleSmall.x(),
        bodyLarge = t.bodyLarge.x(), bodyMedium = t.bodyMedium.x(), bodySmall = t.bodySmall.x(),
        labelLarge = t.labelLarge.x(), labelMedium = t.labelMedium.x(), labelSmall = t.labelSmall.x(),
    )
}
private val ps2Typography by lazy { styled(PS2_TEXT) }
private val acidTypography by lazy { styled(ACID_TEXT) }

/** Acidwave's clipped corners (top-right and bottom-left), used for every button and panel. */
val AcidShape = androidx.compose.foundation.shape.CutCornerShape(topStart = 0.dp, topEnd = 12.dp, bottomEnd = 0.dp, bottomStart = 12.dp)

/**
 * Background for panels, dialogs and cards: solid normally; frosted glass (translucent fill, light
 * top sheen and a hairline edge) when the glass style is on.
 */
fun androidx.compose.ui.Modifier.glassPanel(shape: androidx.compose.ui.graphics.Shape, solid: Color = Palette.Surface): androidx.compose.ui.Modifier =
    if (Palette.Style == UiStyle.PS2) this.then(
        // PS2 system menu: deep translucent blue with a faint glowing rim.
        androidx.compose.ui.Modifier
            .background(
                androidx.compose.ui.graphics.Brush.verticalGradient(
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
