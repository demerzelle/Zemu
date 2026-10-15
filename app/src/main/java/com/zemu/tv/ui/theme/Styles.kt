package com.zemu.tv.ui.theme

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextGeometricTransform
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.TextUnitType
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import kotlin.math.sin

/** Beat clock for the Cat Rave, ticked by its effect layer; read only while drawing. */
object RaveClock {
    var t by mutableFloatStateOf(0f)
}

/** Pixelify Sans (SIL Open Font License; see assets/licenses): every word in the console themes. */
val PixelFont = FontFamily(androidx.compose.ui.text.font.Font(com.zemu.tv.R.font.pixelify_sans))

private fun sp(v: Float) = TextUnit(v, TextUnitType.Sp)

/** Each whole-app style's lettering. */
fun styleTextStyle(style: UiStyle, variant: String): TextStyle = when (style) {
    UiStyle.PS2 -> TextStyle(shadow = Shadow(Color(0x996FB4FF), Offset.Zero, 10f), letterSpacing = sp(0.5f))
    UiStyle.ACID -> TextStyle(fontFamily = FontFamily.Monospace, letterSpacing = sp(0.6f))
    // Airy serif with a faint halo.
    UiStyle.ETHEREAL -> TextStyle(fontFamily = FontFamily.Serif, letterSpacing = sp(0.8f), shadow = Shadow(Color(0x80E9E4FF), Offset.Zero, 14f))
    // Old desktops: a terminal face; Kawaii goes handwritten.
    UiStyle.RETRO -> if (variant == "KAWAII") TextStyle(fontFamily = FontFamily.Cursive) else TextStyle(fontFamily = if (variant == "XP") FontFamily.SansSerif else FontFamily.Monospace)
    // Slanted, heavy, with a hard drop shadow.
    UiStyle.GRAFFITI -> TextStyle(
        fontFamily = FontFamily(android.graphics.Typeface.create("sans-serif-condensed", android.graphics.Typeface.BOLD)),
        textGeometricTransform = TextGeometricTransform(skewX = -0.18f),
        shadow = Shadow(Color(0xCC000000), Offset(3f, 3f), 0f),
    )
    UiStyle.LIQUID -> TextStyle(letterSpacing = sp(-0.2f))
    UiStyle.CATRAVE -> TextStyle(fontFamily = FontFamily.Cursive, shadow = Shadow(Color(0xCCFF00E6), Offset(2f, 2f), 4f))
    // Space: wide lettering with a starlight glow; Ocean: soft, with a watery shimmer.
    UiStyle.SPACE -> TextStyle(letterSpacing = sp(0.8f), shadow = Shadow(Color(0x668AB4FF), Offset.Zero, 12f))
    UiStyle.OCEAN -> TextStyle(letterSpacing = sp(0.3f), shadow = Shadow(Color(0x554FE3C1), Offset.Zero, 10f))
    // Consoles: chunky monospace, like bitmap fonts; 16-bit text gets a hard drop shadow.
    UiStyle.POCKET -> TextStyle(fontFamily = PixelFont, letterSpacing = sp(0.4f))
    UiStyle.SIXTEEN -> TextStyle(fontFamily = PixelFont, shadow = Shadow(Color(0xFF181028), Offset(2f, 2f), 0f))
    UiStyle.NORMAL -> TextStyle.Default
}

/** Fonts you can pick in Appearance → Text (key to label); "" keeps the theme's own. */
val FONT_CHOICES = listOf(
    "" to "Theme's own", "SANS" to "Sans serif", "SERIF" to "Serif", "MONO" to "Monospace",
    "CONDENSED" to "Condensed", "CURSIVE" to "Handwritten", "PIXEL" to "Pixel",
)

fun fontFamilyOf(key: String): FontFamily? = when (key) {
    "SANS" -> FontFamily.SansSerif
    "SERIF" -> FontFamily.Serif
    "MONO" -> FontFamily.Monospace
    "CONDENSED" -> FontFamily(android.graphics.Typeface.create("sans-serif-condensed", android.graphics.Typeface.NORMAL))
    "CURSIVE" -> FontFamily.Cursive
    "PIXEL" -> PixelFont
    else -> null
}

/** A style's lettering with your chosen font (if any) in place of its own. */
fun styleTextStyle(style: UiStyle, variant: String, font: String): TextStyle =
    fontFamilyOf(font)?.let { styleTextStyle(style, variant).merge(TextStyle(fontFamily = it)) } ?: styleTextStyle(style, variant)

private val typographies = HashMap<String, androidx.tv.material3.Typography>()

/** The Material typography with a style's lettering merged in (cached per style). */
fun styleTypography(style: UiStyle, variant: String, font: String = ""): androidx.tv.material3.Typography = typographies.getOrPut("$style/$variant/$font") {
    val t = androidx.tv.material3.Typography()
    if (style == UiStyle.NORMAL && font.isEmpty()) return@getOrPut t
    val extra = styleTextStyle(style, variant, font)
    fun TextStyle.x() = merge(extra)
    t.copy(
        displayLarge = t.displayLarge.x(), displayMedium = t.displayMedium.x(), displaySmall = t.displaySmall.x(),
        headlineLarge = t.headlineLarge.x(), headlineMedium = t.headlineMedium.x(), headlineSmall = t.headlineSmall.x(),
        titleLarge = t.titleLarge.x(), titleMedium = t.titleMedium.x(), titleSmall = t.titleSmall.x(),
        bodyLarge = t.bodyLarge.x(), bodyMedium = t.bodyMedium.x(), bodySmall = t.bodySmall.x(),
        labelLarge = t.labelLarge.x(), labelMedium = t.labelMedium.x(), labelSmall = t.labelSmall.x(),
    )
}

/** Button shapes per style (round buttons stay round). */
fun styledShape(shape: Shape): Shape {
    // Old PCs and consoles: everything is square, round buttons included.
    val square = Palette.Style in setOf(UiStyle.POCKET, UiStyle.SIXTEEN, UiStyle.RETRO)
    if (shape == CircleShape && !square) return shape
    return when (Palette.Style) {
        UiStyle.POCKET -> androidx.compose.ui.graphics.RectangleShape
        UiStyle.SIXTEEN -> androidx.compose.ui.graphics.RectangleShape
        UiStyle.ACID -> AcidShape
        UiStyle.ETHEREAL -> RoundedCornerShape(20.dp)
        UiStyle.LIQUID, UiStyle.CATRAVE -> RoundedCornerShape(50)
        UiStyle.RETRO -> androidx.compose.ui.graphics.RectangleShape
        UiStyle.GRAFFITI -> RoundedCornerShape(3.dp)
        UiStyle.SPACE -> RoundedCornerShape(16.dp)
        UiStyle.OCEAN -> RoundedCornerShape(24.dp)
        else -> shape
    }
}

/** Panels and dialogs for the newer whole-app styles; null = the regular look. */
fun Modifier.stylePanel(shape: Shape, solid: Color): Modifier? = when (Palette.Style) {
    UiStyle.ETHEREAL -> {
        val s = RoundedCornerShape(28.dp)
        background(Brush.verticalGradient(listOf(Color.White.copy(alpha = if (Palette.Light) 0.75f else 0.12f), Color.White.copy(alpha = if (Palette.Light) 0.55f else 0.05f))), s)
            .background(solid.copy(alpha = 0.55f), s)
            .border(1.dp, Color.White.copy(alpha = 0.25f), s)
    }
    UiStyle.LIQUID -> liquidGlass(RoundedCornerShape(28.dp), strong = true)
    UiStyle.RETRO -> retroWindow(solid)
    UiStyle.POCKET -> background(solid, androidx.compose.ui.graphics.RectangleShape).border(3.dp, Color(0xFF0F380F), androidx.compose.ui.graphics.RectangleShape)
    UiStyle.SIXTEEN -> androidx.compose.ui.graphics.RectangleShape.let { s ->
        background(SixteenWindowBrush, s).border(3.dp, Color.White, s).padding(3.dp).border(1.dp, Color(0xFF9090B0), s)
    }
    UiStyle.GRAFFITI -> background(solid, androidx.compose.ui.graphics.RectangleShape)
        .border(3.dp, Palette.Accent, androidx.compose.ui.graphics.RectangleShape)
    // Space: a ship's console panel with a nebula-edged frame; Ocean: a rounded bubble of sea glass.
    UiStyle.SPACE -> RoundedCornerShape(16.dp).let { s ->
        background(solid.copy(alpha = 0.9f), s).border(1.5.dp, Brush.linearGradient(listOf(Color(0xFF8AB4FF), Color(0xFFB57BFF), Color(0xFFFF7AC6))), s)
    }
    UiStyle.OCEAN -> RoundedCornerShape(24.dp).let { s ->
        background(solid.copy(alpha = 0.85f), s).border(2.dp, Brush.verticalGradient(listOf(Color(0xFFB8FFF0), Color(0xFF4FE3C1))), s)
    }
    UiStyle.CATRAVE -> {
        val s = RoundedCornerShape(22.dp)
        background(solid, s).border(3.dp, Brush.sweepGradient((0..6).map { Color.hsv(it * 60f % 360f, 1f, 1f) }), s)
    }
    else -> null
}

/**
 * Liquid glass: a see-through fill, a bright sheen across the top, and a rim that catches light
 * on the upper edge and fades along the sides, like Apple's glass.
 */
fun Modifier.liquidGlass(shape: Shape, strong: Boolean = false): Modifier {
    val light = Palette.Light
    return background(Color.White.copy(alpha = if (light) (if (strong) 0.55f else 0.38f) else (if (strong) 0.16f else 0.10f)), shape)
        .background(Brush.verticalGradient(0f to Color.White.copy(alpha = if (light) 0.5f else 0.22f), 0.45f to Color.Transparent, 1f to Color.White.copy(alpha = 0.06f)), shape)
        .border(1.2.dp, Brush.verticalGradient(listOf(Color.White.copy(alpha = 0.85f), Color.White.copy(alpha = 0.12f), Color.White.copy(alpha = 0.35f))), shape)
}

/**
 * A vintage window, true to each desktop: Windows 98's gray box with a navy title bar and square
 * caption buttons; XP's beige body in a blue frame with a glossy rounded title bar and a red close
 * button; Kawaii's pastel window with heart buttons. Content starts below the title bar.
 */
private fun Modifier.retroWindow(solid: Color): Modifier {
    val v = Palette.colors.variant
    val barDp = when (v) { "XP" -> 26.dp; "KAWAII" -> 22.dp; else -> 20.dp }
    return drawWithContent {
        val bar = barDp.toPx()
        val u = 1.dp.toPx()
        when (v) {
            "XP" -> {
                val r = CornerRadius.Zero
                drawRoundRect(Color(0xFF0831D9), cornerRadius = r)
                drawRect(solid, Offset(3 * u, bar), Size(size.width - 6 * u, size.height - bar - 3 * u))
                drawRoundRect(Brush.verticalGradient(listOf(Color(0xFF3C8DF8), Color(0xFF0058EE), Color(0xFF0054E3), Color(0xFF0A5FF0)), endY = bar), size = Size(size.width, bar + 8 * u), cornerRadius = r)
                drawRect(solid, Offset(3 * u, bar), Size(size.width - 6 * u, 8 * u))
                // Minimize, maximize (blue) and close (red), each a rounded square with a white edge.
                val b = bar - 8 * u
                listOf(Color(0xFF2663E0), Color(0xFF2663E0), Color(0xFFE0502A)).forEachIndexed { i, c ->
                    val o = Offset(size.width - (3 - i) * (b + 3 * u) - 5 * u, 4 * u)
                    drawRect(c, o, Size(b, b))
                    drawRect(Color.White, o, Size(b, b), style = Stroke(u))
                    val m = o + Offset(b / 2, b / 2); val g = b * 0.25f
                    when (i) {
                        0 -> drawLine(Color.White, Offset(m.x - g, m.y + g), Offset(m.x + g * 0.3f, m.y + g), 2 * u)
                        1 -> drawRect(Color.White, Offset(m.x - g, m.y - g), Size(g * 2, g * 2), style = Stroke(1.5f * u))
                        else -> { drawLine(Color.White, m - Offset(g, g), m + Offset(g, g), 2 * u); drawLine(Color.White, m + Offset(-g, g), m + Offset(g, -g), 2 * u) }
                    }
                }
            }
            "KAWAII" -> {
                val r = CornerRadius.Zero
                drawRoundRect(solid, cornerRadius = r)
                drawRoundRect(Brush.horizontalGradient(listOf(Color(0xFFFF9AD5), Color(0xFFC9A8FF))), size = Size(size.width, bar), cornerRadius = r)
                drawRect(Brush.horizontalGradient(listOf(Color(0xFFFF9AD5), Color(0xFFC9A8FF))), Offset(0f, bar / 2), Size(size.width, bar / 2))
                drawRoundRect(Color(0xFFFF7CC8), cornerRadius = r, style = Stroke(2 * u))
                listOf(Color(0xFFFFE066), Color(0xFF9AF0C8), Color(0xFFFF5FA2)).forEachIndexed { i, c ->
                    val m = Offset(size.width - (3 - i) * 18 * u - 4 * u, bar / 2)
                    drawCircle(c, 5.5f * u, m - Offset(3 * u, 1.5f * u)); drawCircle(c, 5.5f * u, m + Offset(3 * u, -1.5f * u))
                    drawPath(Path().apply { moveTo(m.x - 8 * u, m.y); lineTo(m.x, m.y + 8 * u); lineTo(m.x + 8 * u, m.y); close() }, c)
                }
            }
            else -> {
                drawRect(solid)
                win98Bevel(this, raised = true)
                drawRect(Brush.horizontalGradient(listOf(Color(0xFF000080), Color(0xFF1084D0))), Offset(3 * u, 3 * u), Size(size.width - 6 * u, bar - 3 * u))
                // Caption buttons: minimize, maximize, close.
                val bw = 16 * u; val bh = bar - 7 * u
                listOf("_", "□", "x").forEachIndexed { i, g ->
                    val o = Offset(size.width - 5 * u - (3 - i) * (bw + 2 * u) + (if (i == 2) 2 * u else 0f), 5 * u)
                    drawRect(Color(0xFFC0C0C0), o, Size(bw, bh))
                    drawRect(Color.White, o, Size(bw, u)); drawRect(Color.White, o, Size(u, bh))
                    drawRect(Color.Black, o + Offset(0f, bh - u), Size(bw, u)); drawRect(Color.Black, o + Offset(bw - u, 0f), Size(u, bh))
                    val m = o + Offset(bw / 2, bh / 2); val gg = bh * 0.25f
                    when (g) {
                        "_" -> drawRect(Color.Black, Offset(m.x - gg, m.y + gg - u), Size(gg * 1.6f, 2 * u))
                        "□" -> { drawRect(Color.Black, Offset(m.x - gg, m.y - gg), Size(gg * 2, gg * 2), style = Stroke(u)); drawRect(Color.Black, Offset(m.x - gg, m.y - gg), Size(gg * 2, 2 * u)) }
                        else -> { drawLine(Color.Black, m - Offset(gg, gg), m + Offset(gg, gg), 2 * u); drawLine(Color.Black, m + Offset(-gg, gg), m + Offset(gg, -gg), 2 * u) }
                    }
                }
            }
        }
        drawContent()
    }.padding(top = barDp - 8.dp)
}

/** Windows 98's two-step 3D edge: white and light gray on top-left, black and dark gray bottom-right (reversed when sunken). */
internal fun win98Bevel(d: DrawScope, raised: Boolean = true) = with(d) {
    val u = 1.dp.toPx()
    val (tl1, tl2, br1, br2) = if (raised) listOf(Color(0xFFDFDFDF), Color.White, Color.Black, Color(0xFF808080))
    else listOf(Color(0xFF808080), Color.Black, Color.White, Color(0xFFDFDFDF))
    drawRect(tl1, Offset.Zero, Size(size.width, u)); drawRect(tl1, Offset.Zero, Size(u, size.height))
    drawRect(br1, Offset(0f, size.height - u), Size(size.width, u)); drawRect(br1, Offset(size.width - u, 0f), Size(u, size.height))
    drawRect(tl2, Offset(u, u), Size(size.width - 2 * u, u)); drawRect(tl2, Offset(u, u), Size(u, size.height - 2 * u))
    drawRect(br2, Offset(u, size.height - 2 * u), Size(size.width - 2 * u, u)); drawRect(br2, Offset(size.width - 2 * u, u), Size(u, size.height - 2 * u))
}

/** A button's edge for each desktop, and how it shows focus (98: dotted rectangle; XP: orange glow; Kawaii: pink glow). */
private fun bevel(d: DrawScope, focused: Boolean = false) = with(d) {
    val u = 1.dp.toPx()
    when (Palette.colors.variant) {
        "KAWAII" -> {
            val r = CornerRadius.Zero
            if (focused) drawRoundRect(Color(0x66FF7CC8), Offset(-3 * u, -3 * u), Size(size.width + 6 * u, size.height + 6 * u), r, style = Stroke(4 * u))
            drawRoundRect(Color(0xFFFF7CC8), style = Stroke(2 * u), cornerRadius = r)
        }
        "XP" -> {
            val r = CornerRadius.Zero
            drawRoundRect(Brush.verticalGradient(listOf(Color.White.copy(alpha = 0.7f), Color.Transparent, Color(0x22000000))), cornerRadius = r)
            if (focused) drawRoundRect(Color(0xFFF8B636), Offset(u, u), Size(size.width - 2 * u, size.height - 2 * u), r, style = Stroke(2.5f * u))
            drawRoundRect(Color(0xFF003C74), cornerRadius = r, style = Stroke(u))
        }
        else -> {
            win98Bevel(this, raised = true)
            if (focused) drawRect(
                Color.Black, Offset(4 * u, 4 * u), Size(size.width - 8 * u, size.height - 8 * u),
                style = Stroke(u, pathEffect = androidx.compose.ui.graphics.PathEffect.dashPathEffect(floatArrayOf(u, u))),
            )
        }
    }
}

/**
 * A scroll bar on the right of a long list, drawn the way each desktop did it: 98's gray arrows
 * and beveled thumb, XP's soft blue rounded thumb, Kawaii's pink one. Other styles: nothing.
 */
fun Modifier.retroScrollbar(state: androidx.compose.foundation.lazy.LazyListState): Modifier =
    if (Palette.Style != UiStyle.RETRO) this else drawWithContent {
        drawContent()
        val info = state.layoutInfo
        val total = info.totalItemsCount
        if (total <= 1 || info.visibleItemsInfo.size >= total) return@drawWithContent
        val u = 1.dp.toPx()
        val w = 16 * u
        val x = size.width - w
        val v = Palette.colors.variant
        val arrowH = w
        val trackTop = arrowH; val trackH = size.height - arrowH * 2
        val thumbH = (trackH * info.visibleItemsInfo.size / total).coerceAtLeast(24 * u)
        val frac = state.firstVisibleItemIndex.toFloat() / (total - info.visibleItemsInfo.size).coerceAtLeast(1)
        val thumbY = trackTop + (trackH - thumbH) * frac.coerceIn(0f, 1f)
        fun arrow(y: Float, up: Boolean, color: Color) {
            val m = Offset(x + w / 2, y + arrowH / 2); val g = 3.5f * u
            drawPath(Path().apply {
                if (up) { moveTo(m.x - g, m.y + g / 2); lineTo(m.x + g, m.y + g / 2); lineTo(m.x, m.y - g / 2) }
                else { moveTo(m.x - g, m.y - g / 2); lineTo(m.x + g, m.y - g / 2); lineTo(m.x, m.y + g / 2) }
                close()
            }, color)
        }
        when (v) {
            "XP" -> {
                drawRect(Color(0xFFF7F7F2), Offset(x, 0f), Size(w, size.height))
                listOf(0f, size.height - arrowH).forEachIndexed { i, y ->
                    drawRect(Color(0xFFC3D5FD), Offset(x + u, y + u), Size(w - 2 * u, arrowH - 2 * u))
                    drawRect(Color(0xFF8EB0F5), Offset(x + u, y + u), Size(w - 2 * u, arrowH - 2 * u), style = Stroke(u))
                    arrow(y, i == 0, Color(0xFF4D6185))
                }
                drawRect(Color(0xFFC3D5FD), Offset(x + u, thumbY), Size(w - 2 * u, thumbH))
                drawRect(Color(0xFF8EB0F5), Offset(x + u, thumbY), Size(w - 2 * u, thumbH), style = Stroke(u))
                repeat(4) { k -> drawLine(Color(0xFF8EB0F5), Offset(x + 4 * u, thumbY + thumbH / 2 + (k - 1.5f) * 2 * u), Offset(x + w - 4 * u, thumbY + thumbH / 2 + (k - 1.5f) * 2 * u), u) }
            }
            "KAWAII" -> {
                drawRect(Color(0xFFFFE3F2), Offset(x, 0f), Size(w, size.height))
                drawRect(Color(0xFFFF9AD5), Offset(x + 2 * u, thumbY), Size(w - 4 * u, thumbH))
                drawRect(Color(0xFFFF7CC8), Offset(x + 2 * u, thumbY), Size(w - 4 * u, thumbH), style = Stroke(u))
            }
            else -> {
                // Dithered track, then beveled arrow buttons and thumb.
                drawRect(Color(0xFFE0E0E0), Offset(x, 0f), Size(w, size.height))
                listOf(0f, size.height - arrowH).forEachIndexed { i, y ->
                    drawRect(Color(0xFFC0C0C0), Offset(x, y), Size(w, arrowH))
                    arrow(y, i == 0, Color.Black)
                    drawRect(Color.Black, Offset(x, y + arrowH - u), Size(w, u)); drawRect(Color.White, Offset(x, y), Size(w, u))
                }
                drawRect(Color(0xFFC0C0C0), Offset(x, thumbY), Size(w, thumbH))
                drawRect(Color.White, Offset(x, thumbY), Size(w, u)); drawRect(Color.White, Offset(x, thumbY), Size(u, thumbH))
                drawRect(Color.Black, Offset(x, thumbY + thumbH - u), Size(w, u)); drawRect(Color.Black, Offset(x + w - u, thumbY), Size(u, thumbH))
            }
        }
    }

/** The pointer's look from Settings (set once per composition by the app). */
object PointerPrefs {
    var color by mutableStateOf<Color?>(null)
    var scale by mutableFloatStateOf(1f)
    /** "RIGHT", "CENTER", "LEFT" or "CORNER" (bottom right). */
    var position by mutableStateOf("RIGHT")

    fun at(size: Size): Offset = when (position) {
        "CENTER" -> Offset(size.width * 0.5f, size.height * 0.5f)
        "LEFT" -> Offset(size.width * 0.12f, size.height * 0.5f)
        "CORNER" -> Offset(size.width * 0.85f, size.height * 0.7f)
        else -> Offset(size.width * 0.72f, size.height * 0.5f)
    }
}

/** The arrow pointer drawn on whatever is selected in Cybercore (instead of a highlight). */
fun DrawScope.drawPointer(at: Offset) {
    val s = 1.6f * density / 2f * 14f * PointerPrefs.scale
    val p = Path().apply {
        moveTo(at.x, at.y); lineTo(at.x, at.y + s * 1.5f); lineTo(at.x + s * 0.38f, at.y + s * 1.12f)
        lineTo(at.x + s * 0.66f, at.y + s * 1.72f); lineTo(at.x + s * 0.86f, at.y + s * 1.62f)
        lineTo(at.x + s * 0.58f, at.y + s * 1.04f); lineTo(at.x + s * 1.06f, at.y + s * 1.04f); close()
    }
    val fill = PointerPrefs.color ?: if (Palette.colors.variant == "KAWAII") Color(0xFFFF7CC8) else Color.White
    drawPath(p, fill)
    drawPath(p, Color.Black, style = Stroke(1.5f * density))
}

/**
 * Per-style decoration of any button, card or tile: Cybercore's bevel and pointer, Graffiti's
 * paint drip on OK, the Cat Rave's endless wiggle. [onClick] is wrapped so Graffiti can spray.
 */
fun Modifier.styleDecor(seed: Int = 0, bevel: Boolean = true): Modifier = composed {
    when (Palette.Style) {
        UiStyle.RETRO -> {
            var focused by remember { mutableStateOf(false) }
            onFocusChanged { focused = it.isFocused || it.hasFocus }.drawWithContent {
                drawContent()
                if (bevel) bevel(this, focused)
                if (focused) drawPointer(PointerPrefs.at(size))
            }
        }
        // Consoles: a menu pointer (a glove, or the handheld's arrow) beside what's selected.
        UiStyle.POCKET, UiStyle.SIXTEEN -> {
            var focused by remember { mutableStateOf(false) }
            onFocusChanged { focused = it.isFocused }.drawWithContent {
                drawContent()
                if (focused) drawConsolePointer()
            }
        }
        UiStyle.CATRAVE -> graphicsLayer {
            val t = RaveClock.t
            rotationZ = sin(t * 7f + seed * 0.7f) * 3f
            val beat = (t * 2.13f) % 1f
            scaleX = 1f + 0.04f * (1f - beat); scaleY = scaleX
        }
        else -> this
    }
}

/** Graffiti: remembers a spray and draws it dripping down from the element. */
class Spray {
    val progress = Animatable(0f)
    var seed = 0
}

fun Modifier.graffitiDrips(spray: Spray): Modifier = drawWithContent {
    drawContent()
    val p = spray.progress.value
    if (p <= 0f || p >= 1f) return@drawWithContent
    val r = kotlin.random.Random(spray.seed)
    val color = Palette.Accent.copy(alpha = (1f - p * 0.6f))
    // Splats where the paint hit, then drips running down past the edge.
    repeat(9) {
        val x = r.nextFloat() * size.width
        val y = r.nextFloat() * size.height * 0.6f
        drawCircle(color, (4f + r.nextFloat() * 10f) * density / 2f, Offset(x, y))
    }
    repeat(5) {
        val x = size.width * (0.1f + r.nextFloat() * 0.8f)
        val len = (size.height * 0.4f + r.nextFloat() * size.height) * p
        val w = (3f + r.nextFloat() * 4f) * density / 2f
        drawRoundRect(color, topLeft = Offset(x - w / 2, size.height * 0.5f), size = Size(w, len), cornerRadius = CornerRadius(w / 2))
        drawCircle(color, w * 0.9f, Offset(x, size.height * 0.5f + len))
    }
}

/** Starts the drip animation for a click (Graffiti only). */
fun Spray.fire(scope: kotlinx.coroutines.CoroutineScope) {
    if (Palette.Style != UiStyle.GRAFFITI) return
    seed = (System.nanoTime() % 100_000).toInt()
    scope.launch {
        progress.snapTo(0.001f)
        progress.animateTo(1f, tween(1400))
        progress.snapTo(0f)
    }
}

@androidx.compose.runtime.Composable
fun rememberSpray(): Spray = remember { Spray() }

@androidx.compose.runtime.Composable
fun rememberStyleScope() = rememberCoroutineScope()

/** Desktop and console themes have no rounded corners anywhere; other styles keep [shape]. */
fun boxy(shape: Shape): Shape =
    if (Palette.Style in setOf(UiStyle.RETRO, UiStyle.POCKET, UiStyle.SIXTEEN)) androidx.compose.ui.graphics.RectangleShape else shape

/** Text fields drawn per style: sunken 98 boxes, XP's blue-edged field, Kawaii pink, console frames. */
fun styleField(): Modifier = when (Palette.Style) {
    UiStyle.RETRO -> when (Palette.colors.variant) {
        "XP" -> Modifier.border(1.dp, Color(0xFF7F9DB9))
        "KAWAII" -> Modifier.border(2.dp, Color(0xFFFF9AD5))
        else -> Modifier.drawWithContent { drawContent(); win98Bevel(this, raised = false) }
    }
    UiStyle.POCKET -> Modifier.border(3.dp, Color(0xFF0F380F))
    UiStyle.SIXTEEN -> Modifier.border(2.dp, Color.White)
    else -> Modifier
}

/** Title-bar height of the current desktop's windows. */
fun retroBarHeight(): androidx.compose.ui.unit.Dp = when (Palette.colors.variant) { "XP" -> 26.dp; "KAWAII" -> 22.dp; else -> 20.dp }

/** A desktop window with [title] in its title bar and [content] in its body. */
@androidx.compose.runtime.Composable
fun RetroWindow(title: String, modifier: Modifier = Modifier, content: @androidx.compose.runtime.Composable () -> Unit) {
    val bar = retroBarHeight()
    val dark = Palette.colors.variant == "KAWAII"
    // The window frame pads its body to just under the title bar, so the title moves up into the bar.
    androidx.compose.foundation.layout.Box(modifier.stylePanel(androidx.compose.ui.graphics.RectangleShape, Palette.Surface) ?: modifier) {
        androidx.compose.foundation.layout.Box(Modifier.fillMaxWidth().height(bar).offset(y = -(bar - 8.dp)).padding(start = 8.dp, end = 80.dp), contentAlignment = androidx.compose.ui.Alignment.CenterStart) {
            androidx.tv.material3.Text(title, color = if (dark) Color(0xFF5A2346) else Color.White, fontSize = androidx.compose.ui.unit.TextUnit(12f, TextUnitType.Sp), fontWeight = androidx.compose.ui.text.font.FontWeight.Bold, maxLines = 1)
        }
        // The frame's padding ends 8dp inside the title bar, so the body starts a little lower.
        androidx.compose.foundation.layout.Box(Modifier.fillMaxSize().padding(start = 4.dp, end = 4.dp, top = 10.dp, bottom = 4.dp).background(Color.Black)) { content() }
    }
}
