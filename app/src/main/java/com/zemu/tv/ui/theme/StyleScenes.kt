package com.zemu.tv.ui.theme

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.CanvasDrawScope
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.tv.material3.Text
import kotlin.math.sin
import kotlin.random.Random

// ---------------------------------------------------------------------------------------------
// PS / PS2 (the "PS2 · Y2K" theme)
// ---------------------------------------------------------------------------------------------

/** The four controller face buttons, in their classic colors. */
private val PS_GREEN = Color(0xFF40E0A0)   // triangle
private val PS_RED = Color(0xFFFF6B6B)     // circle
private val PS_BLUE = Color(0xFF7CB2EE)    // cross
private val PS_PINK = Color(0xFFF58AE6)    // square
private val PS2_GLOW = Color(0xFF6FB4FF)

/**
 * Seconds since the scene started, ticking at [fps] (lo-fi: deliberately choppy and cheap). Read it
 * while drawing, so only the drawing repeats, not composition.
 */
@Composable
private fun sceneClock(fps: Int): androidx.compose.runtime.FloatState {
    val t = remember { mutableFloatStateOf(0f) }
    LaunchedEffect(fps) {
        var start = 0L
        var last = 0L
        val step = 1_000_000_000L / fps
        while (true) withFrameNanos { now ->
            if (start == 0L) start = now
            if (now - last >= step) { last = now; t.floatValue = (now - start) / 1e9f }
        }
    }
    return t
}

/**
 * Behind the UI: the PS2 boot scene. Glowing translucent towers rise and fall out of a blue fog,
 * specks of light drift up, and faint PlayStation button shapes float by. Rendered at a fifth of the
 * screen's resolution and scaled up without smoothing, at 15 fps, for that chunky lo-fi look.
 */
@Composable
fun Ps2Backdrop(modifier: Modifier = Modifier) {
    val clock = sceneClock(15)
    val light = Palette.Light
    Spacer(
        modifier.fillMaxSize().drawWithCache {
            val w = (size.width / 5).toInt().coerceAtLeast(1)
            val h = (size.height / 5).toInt().coerceAtLeast(1)
            val bitmap = ImageBitmap(w, h)
            val canvas = androidx.compose.ui.graphics.Canvas(bitmap)
            val scope = CanvasDrawScope()
            onDrawBehind {
                val t = clock.floatValue
                scope.draw(this, layoutDirection, canvas, Size(w.toFloat(), h.toFloat())) { ps2Scene(t, light) }
                drawImage(bitmap, dstSize = IntSize(size.width.toInt(), size.height.toInt()), dstOffset = IntOffset.Zero, filterQuality = FilterQuality.None)
            }
        },
    )
}

private fun DrawScope.ps2Scene(t: Float, light: Boolean) {
    val sky = if (light) listOf(Color(0xFFDCE6FA), Color(0xFFB4C8F0)) else listOf(Color(0xFF000106), Color(0xFF02092A))
    drawRect(Brush.verticalGradient(sky))
    val horizon = size.height * 0.66f
    // Fog band the towers rise out of.
    drawRect(
        Brush.verticalGradient(listOf(Color.Transparent, PS2_GLOW.copy(alpha = if (light) 0.25f else 0.18f), Color.Transparent), startY = horizon - size.height * 0.2f, endY = size.height),
        topLeft = Offset(0f, horizon - size.height * 0.2f), size = Size(size.width, size.height),
    )
    // Towers: rows at three depths, each slowly breathing up and down.
    for (row in 0..2) {
        val depth = 1f - row * 0.28f
        val n = 7 + row * 5
        val w = size.width / n * 0.36f * depth
        for (i in 0 until n) {
            val seed = ((i * 53 + row * 97) % 89) / 89f
            val x = (i + 0.5f) / n * size.width + (seed - 0.5f) * w * 2
            val grow = 0.7f + 0.3f * sin(t * (0.18f + seed * 0.25f) + seed * 6.28f)
            val h = size.height * (0.12f + 0.38f * seed) * depth * grow
            val base = horizon + row * 3f
            val a = (0.14f + 0.22f * depth)
            drawRect(
                Brush.verticalGradient(listOf(Color.White.copy(alpha = a * 1.4f), PS2_GLOW.copy(alpha = a), PS2_GLOW.copy(alpha = 0f)), startY = base - h, endY = base + 4f),
                topLeft = Offset(x - w / 2, base - h), size = Size(w, h + 4f),
            )
        }
    }
    // Specks of light drifting upward.
    for (k in 0 until 26) {
        val r = Random(k * 31)
        val speed = 0.02f + r.nextFloat() * 0.04f
        val y = (1f - ((t * speed + r.nextFloat()) % 1f)) * size.height
        val x = r.nextFloat() * size.width + sin(t * 0.5f + k) * 3f
        drawRect(Color.White.copy(alpha = 0.35f + 0.4f * r.nextFloat()), topLeft = Offset(x, y), size = Size(1f, 1f))
    }
    // The four button shapes, drifting and turning slowly, very faint.
    val shapes = listOf(PS_GREEN, PS_RED, PS_BLUE, PS_PINK)
    shapes.forEachIndexed { i, c ->
        val x = ((i * 0.27f + 0.08f + t * 0.006f) % 1.1f - 0.05f) * size.width
        val y = size.height * (0.16f + 0.1f * i) + sin(t * 0.3f + i * 1.7f) * 4f
        val r = size.height * 0.045f
        rotate(t * 8f * (if (i % 2 == 0) 1 else -1), Offset(x, y)) { psGlyph(i, Offset(x, y), r, c.copy(alpha = 0.35f), stroke = 1.5f) }
    }
}

/** Draws a face-button glyph: 0 triangle, 1 circle, 2 cross, 3 square. */
private fun DrawScope.psGlyph(kind: Int, c: Offset, r: Float, color: Color, stroke: Float) {
    val st = Stroke(stroke)
    when (kind) {
        0 -> drawPath(Path().apply { moveTo(c.x, c.y - r); lineTo(c.x + r * 0.9f, c.y + r * 0.65f); lineTo(c.x - r * 0.9f, c.y + r * 0.65f); close() }, color, style = st)
        1 -> drawCircle(color, r * 0.85f, c, style = st)
        2 -> { drawLine(color, Offset(c.x - r * 0.75f, c.y - r * 0.75f), Offset(c.x + r * 0.75f, c.y + r * 0.75f), stroke); drawLine(color, Offset(c.x + r * 0.75f, c.y - r * 0.75f), Offset(c.x - r * 0.75f, c.y + r * 0.75f), stroke) }
        else -> drawRect(color, Offset(c.x - r * 0.7f, c.y - r * 0.7f), Size(r * 1.4f, r * 1.4f), style = st)
    }
}

/** Above the UI: CRT scanlines and a soft vignette. */
fun DrawScope.ps2Overlay() {
    var y = 0f
    while (y < size.height) {
        drawLine(Color.Black.copy(alpha = 0.09f), Offset(0f, y), Offset(size.width, y), strokeWidth = 1f)
        y += 3f
    }
    drawRect(Brush.radialGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.35f)), center = center, radius = size.maxDimension * 0.75f))
}

/**
 * The PlayStation button legend, mapped to the remote: OK is ✕ (enter), Back is ○, holding OK is △
 * (options). Shown in the bottom corner like the PS2 system menus.
 */
@Composable
fun Ps2Legend(modifier: Modifier = Modifier) {
    Row(
        modifier.padding(end = 28.dp, bottom = 14.dp).background(Color.Black.copy(alpha = 0.45f), androidx.compose.foundation.shape.RoundedCornerShape(6.dp)).padding(horizontal = 12.dp, vertical = 5.dp),
        horizontalArrangement = Arrangement.spacedBy(14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        listOf(Triple(2, PS_BLUE, "Enter"), Triple(1, PS_RED, "Back"), Triple(0, PS_GREEN, "Hold: Options")).forEach { (kind, color, label) ->
            Row(verticalAlignment = Alignment.CenterVertically) {
                Canvas(Modifier.size(16.dp)) { psGlyph(kind, center, size.minDimension / 2, color, stroke = 2.5f) }
                Spacer(Modifier.width(6.dp))
                Text(label, fontSize = 12.sp, color = Color.White.copy(alpha = 0.85f))
            }
        }
    }
}

/**
 * Cold-start splash for the PS2 theme: a black screen, a swell of light, the name in glowing
 * letters, then it fades away (about two seconds). Rows keep loading underneath.
 */
@Composable
fun Ps2Boot(onDone: () -> Unit) {
    val fade = remember { Animatable(1f) }
    val glow = remember { Animatable(0f) }
    LaunchedEffect(Unit) {
        glow.animateTo(1f, tween(900))
        kotlinx.coroutines.delay(700)
        fade.animateTo(0f, tween(600))
        onDone()
    }
    Box(Modifier.fillMaxSize().graphicsLayer { alpha = fade.value }.background(Color.Black), contentAlignment = Alignment.Center) {
        Box(Modifier.fillMaxSize().graphicsLayer { alpha = glow.value * 0.6f }.background(Brush.radialGradient(listOf(PS2_GLOW.copy(alpha = 0.5f), Color.Transparent))))
        Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.graphicsLayer { alpha = glow.value }) {
            Text("ZEMU", fontSize = 64.sp, fontWeight = FontWeight.Light, color = Color.White, letterSpacing = 18.sp)
            Text("TV  ENTERTAINMENT  SYSTEM", fontSize = 13.sp, color = PS2_GLOW, letterSpacing = 6.sp, modifier = Modifier.padding(top = 6.dp))
        }
    }
}

// ---------------------------------------------------------------------------------------------
// Acidwave
// ---------------------------------------------------------------------------------------------

/**
 * Behind the UI: a technical sheet. A fine grid, registration marks, a huge stenciled word along
 * the edge, hazard stripes and a barcode, all in the accent and text colors so custom colors
 * restyle it too.
 */
@Composable
fun AcidBackdrop(modifier: Modifier = Modifier) {
    val measurer = rememberTextMeasurer()
    val accent = Palette.Accent
    val ink = Palette.Text
    val base = Palette.Background
    Canvas(modifier.fillMaxSize()) {
        drawRect(base)
        val step = 48f
        var x = 0f
        while (x < size.width) { drawLine(ink.copy(alpha = 0.045f), Offset(x, 0f), Offset(x, size.height), 1f); x += step }
        var y = 0f
        while (y < size.height) { drawLine(ink.copy(alpha = 0.045f), Offset(0f, y), Offset(size.width, y), 1f); y += step }
        // Giant stencil word up the right edge.
        val big = measurer.measure("ZEMU//SIG", TextStyle(fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Black, fontSize = 150.sp, color = accent.copy(alpha = 0.07f)))
        rotate(90f, Offset(size.width - 40f, 40f)) { drawText(big, topLeft = Offset(size.width - 40f, 40f)) }
        // Hazard stripes along the bottom-left.
        val bandY = size.height - 26f
        var sx = -40f
        while (sx < size.width * 0.38f) {
            drawPath(Path().apply { moveTo(sx, bandY + 26f); lineTo(sx + 16f, bandY); lineTo(sx + 32f, bandY); lineTo(sx + 16f, bandY + 26f); close() }, accent.copy(alpha = 0.18f))
            sx += 34f
        }
        // Barcode block and readout, bottom-right.
        val bx = size.width - 260f
        val r = Random(7)
        var px = bx
        while (px < bx + 150f) { val bw = 1f + r.nextInt(4); drawRect(ink.copy(alpha = 0.22f), Offset(px, size.height - 70f), Size(bw, 40f)); px += bw + 2f + r.nextInt(3) }
        drawText(measurer.measure("FEED 07 · ACQ ACTIVE · UPLINK OK", TextStyle(fontFamily = FontFamily.Monospace, fontSize = 10.sp, color = ink.copy(alpha = 0.35f))), topLeft = Offset(bx - 120f, size.height - 22f))
    }
}

/** Above the UI: corner registration marks and an occasional one-line glitch in the accent. */
fun DrawScope.acidOverlay(t: Float) {
    val a = Palette.Accent
    val m = 18f
    val l = 26f
    listOf(Offset(m, m) to Offset(1f, 1f), Offset(size.width - m, m) to Offset(-1f, 1f), Offset(m, size.height - m) to Offset(1f, -1f), Offset(size.width - m, size.height - m) to Offset(-1f, -1f))
        .forEach { (p, d) ->
            drawLine(a.copy(alpha = 0.7f), p, Offset(p.x + l * d.x, p.y), 2f)
            drawLine(a.copy(alpha = 0.7f), p, Offset(p.x, p.y + l * d.y), 2f)
        }
    // Every ~5 s, a thin bar flickers across for a moment.
    val cycle = t % 5f
    if (cycle < 0.12f) {
        val y = Random((t / 5f).toInt()).nextFloat() * size.height
        drawRect(a.copy(alpha = 0.35f), Offset(0f, y), Size(size.width, 3f))
        drawRect(Color(0xFFFF2BD6).copy(alpha = 0.25f), Offset(size.width * 0.2f, y + 5f), Size(size.width * 0.5f, 2f))
    }
}
