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
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.drawscope.inset
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
internal fun sceneClock(fps: Int): androidx.compose.runtime.FloatState {
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

// ---------------------------------------------------------------------------------------------
// Ethereal · Aurora
// ---------------------------------------------------------------------------------------------

/** Deep twilight with slow aurora curtains, drifting light orbs and faint stars. */
@Composable
fun EtherealBackdrop(modifier: Modifier = Modifier) {
    val clock = sceneClock(30)
    val light = Palette.Light
    Canvas(modifier.fillMaxSize()) {
        val t = clock.floatValue
        drawRect(Brush.verticalGradient(if (light) listOf(Color(0xFFF3EEFF), Color(0xFFE2F3FF), Color(0xFFFBEFFF)) else listOf(Color(0xFF07061A), Color(0xFF1A1240), Color(0xFF0B1A2E))))
        val r = Random(3)
        repeat(80) {
            drawCircle(Color.White.copy(alpha = (0.15f + 0.4f * r.nextFloat()) * (0.6f + 0.4f * sin(t + it))), 1.2f, Offset(r.nextFloat() * size.width, r.nextFloat() * size.height * 0.6f))
        }
        val bands = listOf(Color(0xFF8B5CF6), Color(0xFF22D3EE), Color(0xFFF472B6), Color(0xFF34D399))
        bands.forEachIndexed { i, c ->
            val path = Path()
            val base = size.height * (0.15f + i * 0.09f)
            path.moveTo(0f, base)
            var x = 0f
            while (x <= size.width) {
                path.lineTo(x, base + sin(x / size.width * 5f + t * (0.15f + i * 0.05f) + i) * 60f)
                x += 24f
            }
            path.lineTo(size.width, 0f); path.lineTo(0f, 0f); path.close()
            drawPath(path, Brush.verticalGradient(listOf(c.copy(alpha = 0f), c.copy(alpha = if (light) 0.14f else 0.22f)), startY = 0f, endY = base + 80f))
        }
        repeat(6) { i ->
            val c = Offset(size.width * (0.1f + ((i * 0.19f + t * 0.01f) % 1f) * 0.8f), size.height * (0.55f + 0.3f * sin(t * 0.2f + i)))
            drawCircle(Brush.radialGradient(listOf(bands[i % 4].copy(alpha = 0.18f), Color.Transparent), center = c, radius = 180f), 180f, c)
        }
    }
}

// ---------------------------------------------------------------------------------------------
// Cybercore (vintage PC)
// ---------------------------------------------------------------------------------------------

/** The desktop: Classic (teal + gray taskbar), Kawaii (pastel hearts and clouds), XP (blue sky and the green hill). */
@Composable
fun RetroBackdrop(variant: String, modifier: Modifier = Modifier) {
    val measurer = rememberTextMeasurer()
    val clock = sceneClock(4)
    Canvas(modifier.fillMaxSize()) {
        val t = clock.floatValue
        val bar = 34.dp.toPx()
        // The side menu covers the left edge, so the Start button begins just past it.
        val startX = 84.dp.toPx()
        when (variant) {
            "KAWAII" -> {
                drawRect(Brush.verticalGradient(listOf(Color(0xFFFFD6EC), Color(0xFFE9D9FF))))
                val step = 64f
                var y = 0f; var row = 0
                while (y < size.height) {
                    var x = if (row % 2 == 0) 0f else step / 2
                    while (x < size.width) {
                        if ((x / step + row).toInt() % 3 == 0) drawCircle(Color.White.copy(alpha = 0.55f), 3f, Offset(x, y))
                        else drawPath(Path().apply { moveTo(x, y + 4f); cubicTo(x - 8f, y - 2f, x - 3f, y - 7f, x, y - 2f); cubicTo(x + 3f, y - 7f, x + 8f, y - 2f, x, y + 4f) }, Color(0x66FF7CC8))
                        x += step
                    }
                    y += step / 1.6f; row++
                }
                repeat(3) { i ->
                    val cx = ((t * 6f + i * 420f) % (size.width + 300f)) - 150f
                    val cy = size.height * (0.15f + i * 0.2f)
                    listOf(0f to 0f, 30f to -14f, 60f to 0f, 30f to 10f).forEach { (dx, dy) -> drawCircle(Color.White.copy(alpha = 0.8f), 26f, Offset(cx + dx, cy + dy)) }
                }
                drawRect(Color(0xFFFFB8DE), Offset(0f, size.height - bar), Size(size.width, bar))
                drawLine(Color.White, Offset(0f, size.height - bar), Offset(size.width, size.height - bar), 2f)
                drawRoundRect(Color(0xFFFF7CC8), Offset(startX, size.height - bar + 4.dp.toPx()), Size(96.dp.toPx(), bar - 8.dp.toPx()), androidx.compose.ui.geometry.CornerRadius(bar))
                drawText(measurer.measure("♡ start", TextStyle(fontFamily = FontFamily.Cursive, fontSize = 16.sp, color = Color.White, fontWeight = FontWeight.Bold)), topLeft = Offset(startX + 16.dp.toPx(), size.height - bar + 6.dp.toPx()))
                drawRoundRect(Color(0xFFFFD6EC), Offset(size.width - 100.dp.toPx(), size.height - bar + 4.dp.toPx()), Size(96.dp.toPx(), bar - 8.dp.toPx()), androidx.compose.ui.geometry.CornerRadius(bar))
            }
            "XP" -> {
                drawRect(Brush.verticalGradient(listOf(Color(0xFF2E6FD8), Color(0xFF6FA8F0), Color(0xFFB8D8F8)), endY = size.height * 0.7f))
                repeat(4) { i ->
                    val cx = ((t * 4f + i * 500f) % (size.width + 400f)) - 200f
                    drawOval(Color.White.copy(alpha = 0.75f), Offset(cx, size.height * (0.12f + i * 0.08f)), Size(260f, 50f))
                }
                drawPath(Path().apply {
                    moveTo(0f, size.height * 0.72f)
                    cubicTo(size.width * 0.3f, size.height * 0.52f, size.width * 0.7f, size.height * 0.62f, size.width, size.height * 0.7f)
                    lineTo(size.width, size.height); lineTo(0f, size.height); close()
                }, Brush.verticalGradient(listOf(Color(0xFF6CC24A), Color(0xFF2F8A1F)), startY = size.height * 0.55f, endY = size.height))
                // Luna taskbar: glossy blue, the green Start button and the lighter blue tray.
                drawRect(Brush.verticalGradient(listOf(Color(0xFF3F8CF3), Color(0xFF245EDC), Color(0xFF1941A5)), startY = size.height - bar, endY = size.height), Offset(0f, size.height - bar), Size(size.width, bar))
                val sw = 104.dp.toPx()
                drawRoundRect(Brush.verticalGradient(listOf(Color(0xFF5EC55E), Color(0xFF3C9B3C), Color(0xFF2E7D2E)), startY = size.height - bar, endY = size.height), Offset(startX - 12.dp.toPx(), size.height - bar), Size(sw + 12.dp.toPx(), bar), androidx.compose.ui.geometry.CornerRadius(14.dp.toPx()))
                // The four-pane flag, then "start" in bold italic.
                val f = Offset(startX + 4.dp.toPx(), size.height - bar + 9.dp.toPx()); val q = 7.dp.toPx()
                listOf(Color(0xFFF65314), Color(0xFF7CBB00), Color(0xFF00A1F1), Color(0xFFFFBB00)).forEachIndexed { i, c -> drawRect(c, f + Offset((i % 2) * (q + 1f), (i / 2) * (q + 1f)), Size(q, q)) }
                drawText(measurer.measure("start", TextStyle(fontSize = 18.sp, color = Color.White, fontWeight = FontWeight.Bold, fontStyle = androidx.compose.ui.text.font.FontStyle.Italic, shadow = androidx.compose.ui.graphics.Shadow(Color(0x88000000), Offset(1f, 1f), 2f))), topLeft = Offset(startX + 24.dp.toPx(), size.height - bar + 4.dp.toPx()))
                drawRect(Brush.verticalGradient(listOf(Color(0xFF14A0F0), Color(0xFF0B77D6)), startY = size.height - bar, endY = size.height), Offset(size.width - 100.dp.toPx(), size.height - bar), Size(100.dp.toPx(), bar))
                drawLine(Color(0xFF0A3FA0), Offset(size.width - 100.dp.toPx(), size.height - bar), Offset(size.width - 100.dp.toPx(), size.height), 2f)
            }
            else -> {
                drawRect(Color(0xFF008080))
                // Windows 98 taskbar: a raised Start button with the flag, and the sunken clock tray.
                drawRect(Color(0xFFC0C0C0), Offset(0f, size.height - bar), Size(size.width, bar))
                drawLine(Color(0xFFDFDFDF), Offset(0f, size.height - bar), Offset(size.width, size.height - bar), 2f)
                drawLine(Color.White, Offset(0f, size.height - bar + 2f), Offset(size.width, size.height - bar + 2f), 2f)
                val sb = Offset(startX, size.height - bar + 4.dp.toPx())
                translate(sb.x, sb.y) {
                    val bs = Size(72.dp.toPx(), bar - 8.dp.toPx())
                    drawRect(Color(0xFFC0C0C0), size = bs)
                    inset(0f, 0f, size.width - bs.width, size.height - bs.height) { win98Bevel(this, raised = true) }
                    val q = 5.dp.toPx()
                    listOf(Color(0xFFFF0000), Color(0xFF00C000), Color(0xFF0000FF), Color(0xFFFFFF00)).forEachIndexed { i, c -> drawRect(c, Offset(5.dp.toPx() + (i % 2) * (q + 1f), 6.dp.toPx() + (i / 2) * (q + 1f)), Size(q, q)) }
                    drawText(measurer.measure("Start", TextStyle(fontSize = 14.sp, color = Color.Black, fontWeight = FontWeight.Bold)), topLeft = Offset(19.dp.toPx(), 4.dp.toPx()))
                }
                translate(size.width - 96.dp.toPx(), size.height - bar + 4.dp.toPx()) {
                    inset(0f, 0f, size.width - 92.dp.toPx(), size.height - (bar - 8.dp.toPx())) { win98Bevel(this, raised = false) }
                }
            }
        }
        val clockText = java.text.SimpleDateFormat("h:mm a", java.util.Locale.US).format(java.util.Date())
        drawText(measurer.measure(clockText, TextStyle(fontSize = 13.sp, color = if (variant == "XP") Color.White else Color.Black)), topLeft = Offset(size.width - 84.dp.toPx(), size.height - bar + 9.dp.toPx()))
    }
}

// ---------------------------------------------------------------------------------------------
// Graffiti
// ---------------------------------------------------------------------------------------------

/** A subway wall: dark bricks, layered tags with drips, a big bubble-letter piece. */
@Composable
fun GraffitiBackdrop(modifier: Modifier = Modifier) {
    val measurer = rememberTextMeasurer()
    val accent = Palette.Accent
    Canvas(modifier.fillMaxSize()) {
        drawRect(Color(0xFF1A1A1A))
        val bw = 120f; val bh = 44f
        var row = 0; var y = 0f
        while (y < size.height) {
            var x = if (row % 2 == 0) 0f else -bw / 2
            while (x < size.width) {
                val shade = 0.10f + 0.05f * ((x.toInt() * 7 + row * 13) % 5) / 5f
                drawRect(Color(0xFF7A3B2E).copy(alpha = shade + 0.12f), Offset(x + 3f, y + 3f), Size(bw - 6f, bh - 6f))
                x += bw
            }
            y += bh; row++
        }
        val r = Random(11)
        val paints = listOf(accent, Color(0xFF00E5FF), Color(0xFFFFE600), Color(0xFF39FF14), Color.White)
        repeat(9) {
            val c = paints[r.nextInt(paints.size)].copy(alpha = 0.32f)
            val x0 = r.nextFloat() * size.width; val y0 = r.nextFloat() * size.height
            val p = Path().apply {
                moveTo(x0, y0)
                repeat(4) { cubicTo(x0 + r.nextFloat() * 180f - 40f, y0 - r.nextFloat() * 80f, x0 + r.nextFloat() * 220f, y0 + r.nextFloat() * 60f, x0 + r.nextFloat() * 260f, y0 + r.nextFloat() * 30f - 15f) }
            }
            drawPath(p, c, style = Stroke(6f + r.nextFloat() * 6f, cap = androidx.compose.ui.graphics.StrokeCap.Round))
            repeat(3) { val dx = x0 + r.nextFloat() * 200f; drawLine(c, Offset(dx, y0), Offset(dx, y0 + 20f + r.nextFloat() * 70f), 3f, cap = androidx.compose.ui.graphics.StrokeCap.Round) }
        }
        val piece = measurer.measure("ZEMU", TextStyle(fontFamily = FontFamily(android.graphics.Typeface.create("sans-serif-black", android.graphics.Typeface.NORMAL)), fontSize = 190.sp, color = accent.copy(alpha = 0.18f)))
        rotate(-8f, Offset(size.width * 0.6f, size.height * 0.65f)) {
            drawText(piece, topLeft = Offset(size.width * 0.45f + 8f, size.height * 0.52f + 8f), color = Color.Black.copy(alpha = 0.35f))
            drawText(piece, topLeft = Offset(size.width * 0.45f, size.height * 0.52f))
            drawText(piece, topLeft = Offset(size.width * 0.45f, size.height * 0.52f), color = Color.White.copy(alpha = 0.2f), drawStyle = Stroke(4f))
        }
    }
}

// ---------------------------------------------------------------------------------------------
// Liquid Glass
// ---------------------------------------------------------------------------------------------

/** A vivid, slowly flowing wallpaper for the glass to sit on (big soft color blobs). */
@Composable
fun LiquidBackdrop(modifier: Modifier = Modifier) {
    val clock = sceneClock(24)
    val light = Palette.Light
    Canvas(modifier.fillMaxSize()) {
        val t = clock.floatValue
        drawRect(if (light) Color(0xFFEFF3FA) else Color(0xFF060914))
        val blobs = listOf(Color(0xFF0A84FF), Color(0xFFBF5AF2), Color(0xFFFF9F0A), Color(0xFF30D5C8), Color(0xFFFF375F))
        blobs.forEachIndexed { i, c ->
            val cx = size.width * (0.5f + 0.38f * sin(t * (0.05f + i * 0.013f) + i * 1.3f))
            val cy = size.height * (0.5f + 0.36f * sin(t * (0.04f + i * 0.011f) + i * 2.1f))
            val rad = size.maxDimension * (0.32f + 0.05f * i)
            drawCircle(Brush.radialGradient(listOf(c.copy(alpha = if (light) 0.35f else 0.55f), Color.Transparent), center = Offset(cx, cy), radius = rad), rad, Offset(cx, cy))
        }
    }
}

// ---------------------------------------------------------------------------------------------
// Cat Rave
// ---------------------------------------------------------------------------------------------

/** A dark dance floor: a spinning disco ball, sweeping spotlights and a pulsing grid. */
@Composable
fun CatRaveBackdrop(modifier: Modifier = Modifier) {
    val clock = sceneClock(30)
    Canvas(modifier.fillMaxSize()) {
        val t = clock.floatValue
        drawRect(Color(0xFF07000F))
        val beat = (t * 2.13f) % 1f
        // Pulsing floor grid.
        val horizon = size.height * 0.7f
        for (i in -14..14) drawLine(Color.hsv((t * 60f + i * 12f + 360f) % 360f, 1f, 1f).copy(alpha = 0.25f), Offset(size.width / 2 + i * 40f, horizon), Offset(size.width / 2 + i * 260f, size.height), 2f)
        var y = horizon
        var gap = 8f
        while (y < size.height) { drawLine(Color(0xFFFF00E6).copy(alpha = 0.25f * (1f - beat) + 0.08f), Offset(0f, y), Offset(size.width, y), 2f); y += gap; gap *= 1.35f }
        // Spotlights.
        for (i in 0 until 3) {
            val top = Offset(size.width * (0.25f + i * 0.25f), 0f)
            val a = sin(t * (0.8f + i * 0.3f) + i) * 0.5f
            val bottomC = Offset(top.x + a * size.width * 0.5f, size.height)
            drawPath(Path().apply { moveTo(top.x, top.y); lineTo(bottomC.x - 140f, bottomC.y); lineTo(bottomC.x + 140f, bottomC.y); close() },
                Brush.verticalGradient(listOf(Color.hsv((t * 80f + i * 120f) % 360f, 0.8f, 1f).copy(alpha = 0.22f), Color.Transparent)))
        }
        // Disco ball with spinning facets.
        val c = Offset(size.width / 2, 70f)
        drawLine(Color.Gray, Offset(c.x, 0f), Offset(c.x, c.y - 44f), 2f)
        drawCircle(Color(0xFFB0B0C8), 44f, c)
        for (row in -3..3) for (col in 0 until 10) {
            val ang = (col / 10f * 6.283f + t * 1.5f)
            val x = c.x + kotlin.math.cos(ang) * 44f * kotlin.math.cos(row * 0.4f)
            if (kotlin.math.sin(ang) < 0) continue
            drawRect(Color.hsv((col * 36f + t * 200f) % 360f, 0.3f, 1f), Offset(x - 4f, c.y + row * 11f - 4f), Size(7f, 7f))
        }
        catFace(Offset(size.width * 0.12f, size.height * 0.4f + sin(t * 4f) * 20f), 60f, Color.hsv((t * 100f) % 360f, 0.6f, 1f).copy(alpha = 0.3f))
        catFace(Offset(size.width * 0.88f, size.height * 0.4f + sin(t * 4f + 1.5f) * 20f), 60f, Color.hsv((t * 100f + 180f) % 360f, 0.6f, 1f).copy(alpha = 0.3f))
    }
}

// ---------------------------------------------------------------------------------------------
// Kids Mode
// ---------------------------------------------------------------------------------------------

/** Toddler: a bright sky with a smiling sun, drifting clouds and rolling green hills. */
@Composable
fun ToddlerBackdrop(modifier: Modifier = Modifier) {
    val clock = sceneClock(20)
    Canvas(modifier.fillMaxSize()) {
        val t = clock.floatValue
        drawRect(Brush.verticalGradient(listOf(Color(0xFF9FD8FF), Color(0xFFCDEBFF), Color(0xFFFFF6D6))))
        // Sun with slowly turning rays and a smile.
        val sun = Offset(size.width * 0.9f, size.height * 0.14f)
        rotate(t * 12f, sun) {
            repeat(12) { i ->
                rotate(i * 30f, sun) { drawLine(Color(0xFFFFC93C), Offset(sun.x, sun.y - 70f), Offset(sun.x, sun.y - 100f), strokeWidth = 10f, cap = androidx.compose.ui.graphics.StrokeCap.Round) }
            }
        }
        drawCircle(Color(0xFFFFD84D), 58f, sun)
        drawCircle(Color(0xFF6B4A00), 6f, sun + Offset(-18f, -10f))
        drawCircle(Color(0xFF6B4A00), 6f, sun + Offset(18f, -10f))
        drawArc(Color(0xFF6B4A00), 20f, 140f, false, sun + Offset(-24f, -14f), Size(48f, 40f), style = Stroke(5f, cap = androidx.compose.ui.graphics.StrokeCap.Round))
        // Clouds.
        repeat(4) { i ->
            val x = ((i * 0.31f + t * (0.006f + i * 0.002f)) % 1.3f - 0.15f) * size.width
            val y = size.height * (0.08f + i * 0.07f)
            val s = 1f + (i % 2) * 0.4f
            listOf(Offset(0f, 0f) to 40f, Offset(45f, -18f) to 52f, Offset(95f, 0f) to 40f, Offset(48f, 12f) to 44f).forEach { (o, r) ->
                drawCircle(Color.White.copy(alpha = 0.9f), r * s, Offset(x + o.x * s, y + o.y * s))
            }
        }
        // Hills.
        listOf(Color(0xFF8FD694) to 0.86f, Color(0xFF6CC570) to 0.92f).forEachIndexed { i, (c, h) ->
            val path = Path().apply {
                moveTo(0f, size.height)
                var x = 0f
                while (x <= size.width) {
                    lineTo(x, size.height * h + sin(x / size.width * 6f + i * 2f) * 30f)
                    x += 30f
                }
                lineTo(size.width, size.height); close()
            }
            drawPath(path, c)
        }
        // Little flowers bobbing on the front hill.
        repeat(9) { i ->
            val x = size.width * (0.05f + i * 0.11f)
            val y = size.height * 0.95f + sin(t * 2f + i) * 4f
            repeat(5) { k ->
                val a = k * 72f * (Math.PI / 180f).toFloat()
                drawCircle(listOf(Color(0xFFFF8AC7), Color(0xFFFFFFFF), Color(0xFFB57BFF))[i % 3], 7f, Offset(x + kotlin.math.cos(a) * 9f, y + sin(a) * 9f))
            }
            drawCircle(Color(0xFFFFC93C), 6f, Offset(x, y))
        }
    }
}

/** Grade School: lined notebook paper with a margin, doodled stars and a wobbly crayon rainbow. */
@Composable
fun GradeSchoolBackdrop(modifier: Modifier = Modifier) {
    val clock = sceneClock(12)
    Canvas(modifier.fillMaxSize()) {
        val t = clock.floatValue
        drawRect(Color(0xFFFFFBEA))
        var y = 90f
        while (y < size.height) { drawLine(Color(0x553B82F6), Offset(0f, y), Offset(size.width, y), strokeWidth = 2f); y += 44f }
        drawLine(Color(0x88EF4444), Offset(150f, 0f), Offset(150f, size.height), strokeWidth = 3f)
        // Binder holes down the left edge.
        repeat(3) { i -> drawCircle(Color(0xFFE9E3CC), 16f, Offset(60f, size.height * (0.2f + i * 0.3f))) }
        // Crayon rainbow in the corner.
        val rainbow = listOf(Color(0xFFEF4444), Color(0xFFF59E0B), Color(0xFFFACC15), Color(0xFF22C55E), Color(0xFF3B82F6), Color(0xFF8B5CF6))
        val center = Offset(size.width * 0.92f, size.height * 0.98f)
        rainbow.forEachIndexed { i, c ->
            val r = 260f - i * 22f
            drawArc(c.copy(alpha = 0.55f), 180f, 180f * (0.85f + 0.15f * sin(t * 0.6f)), false, center - Offset(r, r), Size(r * 2, r * 2), style = Stroke(18f, cap = androidx.compose.ui.graphics.StrokeCap.Round))
        }
        // Doodled stars that twinkle.
        val r = Random(11)
        repeat(10) { i ->
            val c = Offset(size.width * (0.12f + r.nextFloat() * 0.85f), size.height * (0.05f + r.nextFloat() * 0.9f))
            val s = (10f + r.nextFloat() * 10f) * (0.85f + 0.15f * sin(t * 2f + i))
            val star = Path()
            repeat(10) { k ->
                val a = (k * 36f - 90f) * (Math.PI / 180f).toFloat()
                val rr = if (k % 2 == 0) s else s * 0.45f
                val p = Offset(c.x + kotlin.math.cos(a) * rr, c.y + sin(a) * rr)
                if (k == 0) star.moveTo(p.x, p.y) else star.lineTo(p.x, p.y)
            }
            star.close()
            drawPath(star, listOf(Color(0x66FACC15), Color(0x553B82F6), Color(0x55EF4444))[i % 3], style = Stroke(3f))
        }
    }
}

/** Young Adult: a deep night gradient with big soft glow orbs drifting and a faint wave grid. */
@Composable
fun YoungAdultBackdrop(modifier: Modifier = Modifier) {
    val clock = sceneClock(24)
    Canvas(modifier.fillMaxSize()) {
        val t = clock.floatValue
        drawRect(Brush.linearGradient(listOf(Color(0xFF0E0B1F), Color(0xFF1A1340), Color(0xFF0B2A33)), Offset.Zero, Offset(size.width, size.height)))
        val colors = listOf(Color(0xFF7CFFCB), Color(0xFFB57BFF), Color(0xFFFF7AC6), Color(0xFF5AB8FF))
        colors.forEachIndexed { i, c ->
            val center = Offset(
                size.width * (0.5f + 0.4f * sin(t * (0.05f + i * 0.02f) + i * 1.7f)),
                size.height * (0.5f + 0.35f * kotlin.math.cos(t * (0.04f + i * 0.015f) + i)),
            )
            val radius = size.minDimension * (0.35f + 0.08f * sin(t * 0.3f + i))
            drawCircle(Brush.radialGradient(listOf(c.copy(alpha = 0.22f), Color.Transparent), center, radius), radius, center)
        }
        // Perspective wave lines along the bottom.
        repeat(7) { i ->
            val path = Path()
            val base = size.height * (0.78f + i * 0.035f)
            var x = 0f
            path.moveTo(0f, base)
            while (x <= size.width) { path.lineTo(x, base + sin(x / 180f + t * 0.8f + i * 0.6f) * (6f + i * 2f)); x += 20f }
            drawPath(path, Color(0xFF7CFFCB).copy(alpha = 0.06f + i * 0.015f), style = Stroke(1.5f))
        }
    }
}

// Kids sub-themes: Dinosaurs, Space and Ocean (any age).

/** Dinosaurs: a jungle valley with a smoking volcano, palms and dinosaurs strolling past. */
@Composable
fun DinoBackdrop(modifier: Modifier = Modifier) {
    val clock = sceneClock(20)
    Canvas(modifier.fillMaxSize()) {
        val t = clock.floatValue
        drawRect(Brush.verticalGradient(listOf(Color(0xFFFFE3B0), Color(0xFFE6F4CF))))
        // Volcano with drifting smoke puffs.
        val vx = size.width * 0.78f
        val vy = size.height * 0.62f
        drawPath(Path().apply { moveTo(vx - 260f, vy + 120f); lineTo(vx - 50f, vy - 170f); lineTo(vx + 50f, vy - 170f); lineTo(vx + 260f, vy + 120f); close() }, Color(0xFF8A6A55))
        drawPath(Path().apply { moveTo(vx - 50f, vy - 170f); lineTo(vx + 50f, vy - 170f); lineTo(vx + 30f, vy - 140f); lineTo(vx - 30f, vy - 140f); close() }, Color(0xFFFF7A3D))
        repeat(5) { i ->
            val k = (t * 0.12f + i * 0.2f) % 1f
            drawCircle(Color(0xFF9E9E9E).copy(alpha = 0.5f * (1 - k)), 30f + k * 60f, Offset(vx + sin(k * 6f + i) * 30f, vy - 190f - k * 260f))
        }
        // Hills.
        drawPath(Path().apply {
            moveTo(0f, size.height)
            var x = 0f
            while (x <= size.width) { lineTo(x, size.height * 0.78f + sin(x / size.width * 5f) * 26f); x += 30f }
            lineTo(size.width, size.height); close()
        }, Color(0xFF7CB86A))
        // Palm trees swaying.
        listOf(0.18f, 0.55f, 0.95f).forEachIndexed { i, fx ->
            val base = Offset(size.width * fx, size.height * 0.82f)
            val sway = sin(t * 1.2f + i) * 8f
            val top = base + Offset(20f + sway, -220f)
            drawLine(Color(0xFF8B5A2B), base, top, strokeWidth = 16f, cap = androidx.compose.ui.graphics.StrokeCap.Round)
            repeat(6) { k ->
                rotate(k * 60f + sway, top) {
                    drawOval(Color(0xFF3E8E41), Offset(top.x, top.y - 14f), Size(110f, 28f))
                }
            }
        }
        // Two dinosaurs walking across (a long-neck and a little one), bobbing with each step.
        listOf(0.018f to 1.4f, 0.03f to 0.8f).forEachIndexed { i, (speed, s) ->
            val x = ((t * speed + i * 0.5f) % 1.3f - 0.15f) * size.width
            val y = size.height * (0.86f + i * 0.04f) + kotlin.math.abs(sin(t * 4f + i)) * -6f
            val c = if (i == 0) Color(0xFF4FA36B) else Color(0xFFE38B3C)
            drawOval(c, Offset(x - 70f * s, y - 50f * s), Size(140f * s, 70f * s))
            drawLine(c, Offset(x + 50f * s, y - 30f * s), Offset(x + 100f * s, y - (if (i == 0) 150f else 70f) * s), strokeWidth = 22f * s, cap = androidx.compose.ui.graphics.StrokeCap.Round)
            drawCircle(c, 20f * s, Offset(x + 105f * s, y - (if (i == 0) 155f else 75f) * s))
            drawCircle(Color.Black, 3.5f * s, Offset(x + 112f * s, y - (if (i == 0) 160f else 80f) * s))
            drawLine(c, Offset(x - 65f * s, y - 20f * s), Offset(x - 130f * s, y - 5f * s), strokeWidth = 16f * s, cap = androidx.compose.ui.graphics.StrokeCap.Round)
            val step = sin(t * 4f + i) * 10f * s
            listOf(-40f, 35f).forEach { lx -> drawLine(c, Offset(x + lx * s, y), Offset(x + lx * s + step, y + 40f * s), strokeWidth = 14f * s, cap = androidx.compose.ui.graphics.StrokeCap.Round) }
        }
    }
}

/** Space: deep blue night, a ringed planet, a moon and a rocket looping by. */
@Composable
fun SpaceBackdrop(modifier: Modifier = Modifier) {
    val clock = sceneClock(24)
    Canvas(modifier.fillMaxSize()) {
        val t = clock.floatValue
        drawRect(Brush.verticalGradient(listOf(Color(0xFF05071A), Color(0xFF0B1030), Color(0xFF1B1446))))
        val r = Random(5)
        repeat(90) { drawCircle(Color.White.copy(alpha = 0.25f + 0.4f * r.nextFloat()), 1f + r.nextFloat() * 1.4f, Offset(r.nextFloat() * size.width, r.nextFloat() * size.height)) }
        // Ringed planet.
        val p = Offset(size.width * 0.84f, size.height * 0.22f)
        drawCircle(Brush.radialGradient(listOf(Color(0xFFFFB86B), Color(0xFFE0663B)), p - Offset(30f, 30f), 140f), 95f, p)
        rotate(-18f, p) { drawOval(Color(0xFFFFE0A8).copy(alpha = 0.8f), Offset(p.x - 170f, p.y - 26f), Size(340f, 52f), style = Stroke(9f)) }
        // Moon.
        val m = Offset(size.width * 0.12f, size.height * 0.8f)
        drawCircle(Color(0xFFD9DDE8), 70f, m)
        drawCircle(Color(0xFFB8BECC), 14f, m + Offset(-20f, -15f))
        drawCircle(Color(0xFFB8BECC), 9f, m + Offset(25f, 20f))
        // Rocket on a slow loop with a flickering flame.
        val a = t * 0.15f
        val c = Offset(size.width * (0.5f + 0.32f * kotlin.math.cos(a)), size.height * (0.5f + 0.28f * sin(a)))
        val heading = Math.toDegrees(kotlin.math.atan2(0.28 * kotlin.math.cos(a), -0.32 * sin(a))).toFloat() + 90f
        rotate(heading, c) {
            drawPath(Path().apply { moveTo(c.x, c.y - 50f); lineTo(c.x + 18f, c.y + 20f); lineTo(c.x - 18f, c.y + 20f); close() }, Color(0xFFF2F2F2))
            drawCircle(Color(0xFF5AB8FF), 8f, c + Offset(0f, -12f))
            drawPath(Path().apply { moveTo(c.x - 18f, c.y + 20f); lineTo(c.x - 30f, c.y + 34f); lineTo(c.x - 12f, c.y + 20f); close() }, Color(0xFFE5484D))
            drawPath(Path().apply { moveTo(c.x + 18f, c.y + 20f); lineTo(c.x + 30f, c.y + 34f); lineTo(c.x + 12f, c.y + 20f); close() }, Color(0xFFE5484D))
            drawOval(Color(0xFFFFB13B), Offset(c.x - 9f, c.y + 22f), Size(18f, 22f + sin(t * 30f) * 6f))
        }
    }
}

/** Ocean: sunbeams through blue water, swaying seaweed and fish swimming both ways. */
@Composable
fun OceanBackdrop(modifier: Modifier = Modifier) {
    val clock = sceneClock(24)
    Canvas(modifier.fillMaxSize()) {
        val t = clock.floatValue
        drawRect(Brush.verticalGradient(listOf(Color(0xFF2A9BD1), Color(0xFF0C4A70), Color(0xFF062B45))))
        repeat(5) { i ->
            val x = size.width * (0.1f + i * 0.2f) + sin(t * 0.3f + i) * 40f
            drawPath(Path().apply { moveTo(x - 30f, 0f); lineTo(x + 30f, 0f); lineTo(x + 160f, size.height); lineTo(x + 40f, size.height); close() }, Color.White.copy(alpha = 0.05f))
        }
        // Sand and seaweed.
        drawRect(Color(0xFFD9C38C), Offset(0f, size.height * 0.93f), Size(size.width, size.height * 0.07f))
        repeat(9) { i ->
            val bx = size.width * (0.04f + i * 0.12f)
            val path = Path().apply {
                moveTo(bx, size.height * 0.94f)
                var y = size.height * 0.94f
                var k = 0
                while (y > size.height * (0.68f + (i % 3) * 0.05f)) {
                    y -= 20f; k++
                    lineTo(bx + sin(t * 1.3f + i + k * 0.5f) * 14f, y)
                }
            }
            drawPath(path, Color(0xFF2E9E6A), style = Stroke(12f, cap = androidx.compose.ui.graphics.StrokeCap.Round))
        }
        // Fish.
        val colors = listOf(Color(0xFFFFB13B), Color(0xFFFF6B9A), Color(0xFF7CFFCB), Color(0xFFFFE066))
        repeat(6) { i ->
            val dir = if (i % 2 == 0) 1f else -1f
            val k = (t * (0.025f + i * 0.006f) + i * 0.17f) % 1.3f - 0.15f
            val x = (if (dir > 0) k else 1f - k) * size.width
            val y = size.height * (0.18f + i * 0.11f) + sin(t * 1.5f + i) * 12f
            val s = 0.8f + (i % 3) * 0.3f
            val col = colors[i % colors.size]
            drawOval(col, Offset(x - 30f * s, y - 16f * s), Size(60f * s, 32f * s))
            drawPath(Path().apply { moveTo(x - dir * 26f * s, y); lineTo(x - dir * 50f * s, y - 16f * s); lineTo(x - dir * 50f * s, y + 16f * s); close() }, col)
            drawCircle(Color.Black, 3.5f * s, Offset(x + dir * 16f * s, y - 4f * s))
        }
    }
}
