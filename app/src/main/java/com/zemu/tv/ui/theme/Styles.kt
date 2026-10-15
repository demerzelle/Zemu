package com.zemu.tv.ui.theme

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
    UiStyle.NORMAL -> TextStyle.Default
}

private val typographies = HashMap<String, androidx.tv.material3.Typography>()

/** The Material typography with a style's lettering merged in (cached per style). */
fun styleTypography(style: UiStyle, variant: String): androidx.tv.material3.Typography = typographies.getOrPut("$style/$variant") {
    val t = androidx.tv.material3.Typography()
    if (style == UiStyle.NORMAL) return@getOrPut t
    val extra = styleTextStyle(style, variant)
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
    if (shape == CircleShape) return shape
    return when (Palette.Style) {
        UiStyle.ACID -> AcidShape
        UiStyle.ETHEREAL -> RoundedCornerShape(20.dp)
        UiStyle.LIQUID, UiStyle.CATRAVE -> RoundedCornerShape(50)
        UiStyle.RETRO -> if (Palette.colors.variant == "KAWAII") RoundedCornerShape(14.dp) else if (Palette.colors.variant == "XP") RoundedCornerShape(5.dp) else androidx.compose.ui.graphics.RectangleShape
        UiStyle.GRAFFITI -> RoundedCornerShape(3.dp)
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
    UiStyle.GRAFFITI -> background(solid, androidx.compose.ui.graphics.RectangleShape)
        .border(3.dp, Palette.Accent, androidx.compose.ui.graphics.RectangleShape)
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

/** A vintage window: solid body, beveled edges and a title bar in the accent color. */
private fun Modifier.retroWindow(solid: Color): Modifier = drawWithContent {
    val v = Palette.colors.variant
    val r = if (v == "CLASSIC" || v.isEmpty()) 0f else 12f
    drawRoundRect(solid, cornerRadius = CornerRadius(r))
    val bar = if (v == "XP") Brush.verticalGradient(listOf(Color(0xFF3D86F5), Color(0xFF0A54D6))) else if (v == "KAWAII") Brush.horizontalGradient(listOf(Color(0xFFFF9AD5), Color(0xFFC9A8FF))) else Brush.horizontalGradient(listOf(Color(0xFF000080), Color(0xFF1084D0)))
    drawRoundRect(bar, size = Size(size.width, 10.dp.toPx()), cornerRadius = CornerRadius(r))
    bevel(this)
    drawContent()
}

/** Raised 3D edge: light top-left, dark bottom-right (Windows 95 buttons and windows). */
private fun bevel(d: DrawScope) = with(d) {
    if (Palette.colors.variant == "KAWAII") {
        drawRoundRect(Color(0xFFFF7CC8), style = Stroke(2.dp.toPx()), cornerRadius = CornerRadius(12.dp.toPx()))
        return@with
    }
    val w = 2.dp.toPx()
    drawLine(Color.White, Offset(0f, 0f), Offset(size.width, 0f), w)
    drawLine(Color.White, Offset(0f, 0f), Offset(0f, size.height), w)
    drawLine(Color(0xFF404040), Offset(0f, size.height), Offset(size.width, size.height), w)
    drawLine(Color(0xFF404040), Offset(size.width, 0f), Offset(size.width, size.height), w)
}

/** The arrow pointer drawn on whatever is selected in Cybercore (instead of a highlight). */
fun DrawScope.drawPointer(at: Offset) {
    val s = 1.6f * density / 2f * 14f
    val p = Path().apply {
        moveTo(at.x, at.y); lineTo(at.x, at.y + s * 1.5f); lineTo(at.x + s * 0.38f, at.y + s * 1.12f)
        lineTo(at.x + s * 0.66f, at.y + s * 1.72f); lineTo(at.x + s * 0.86f, at.y + s * 1.62f)
        lineTo(at.x + s * 0.58f, at.y + s * 1.04f); lineTo(at.x + s * 1.06f, at.y + s * 1.04f); close()
    }
    val fill = if (Palette.colors.variant == "KAWAII") Color(0xFFFF7CC8) else Color.White
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
                if (bevel) bevel(this)
                if (focused) drawPointer(Offset(size.width * 0.72f, size.height * 0.5f))
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
