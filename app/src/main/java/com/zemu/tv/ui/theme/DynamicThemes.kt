package com.zemu.tv.ui.theme

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.rotate
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.sin
import kotlin.random.Random

/**
 * Animated themes. Some bring their own colors (Cyberpunk, Halloween, ...); the rest keep the
 * chosen color theme and only add the effect. Effects are drawn above the UI with low opacity
 * and never take focus or input.
 */
enum class DynamicTheme(val label: String, val accent: Long? = null, val background: Long? = null) {
    NONE("Off"),
    RGB("RGB"),
    SNOWFALL("Snowfall"),
    RAIN("Rain"),
    LIGHTNING("Lightning storm", 0xFF8AB4FF, 0xFF06080F),
    CYBERPUNK("Cyberpunk", 0xFFFF2A6D, 0xFF0B0518),
    HALLOWEEN("Halloween", 0xFFFF7518, 0xFF0F0710),
    CHRISTMAS("Christmas", 0xFFD42426, 0xFF06120B),
    AURORA("Aurora", 0xFF34D399, 0xFF050B14),
    FIREFLIES("Fireflies", 0xFFFACC15, 0xFF070A06),
    MATRIX("Matrix", 0xFF22C55E, 0xFF000500),
    SAKURA("Sakura", 0xFFF472B6, 0xFF120810),
    /** Restyles the whole app: chrome buttons, PS2-style backdrop, chromatic aberration. */
    Y2K("Y2K", 0xFF7FD4FF, 0xFF040818),
    ;

    companion object {
        fun of(name: String) = entries.firstOrNull { it.name == name } ?: NONE
    }
}

/** Colors after applying a dynamic theme's own palette (if it has one). */
fun DynamicTheme.applyTo(base: ThemeColors): ThemeColors =
    if (accent != null && background != null) base.copy(accent = Color(accent.toInt()), background = Color(background.toInt())) else base

private class Particle(var x: Float, var y: Float, var speed: Float, var size: Float, var drift: Float, var phase: Float, var kind: Int = 0)

/**
 * Draws [theme]'s animation. For RGB it instead calls [onAccent] with a slowly cycling hue, so
 * the whole UI's accent color shifts.
 */
@Composable
fun DynamicThemeLayer(theme: DynamicTheme, onAccent: (Color?) -> Unit, modifier: Modifier = Modifier) {
    if (theme == DynamicTheme.NONE) {
        LaunchedEffect(Unit) { onAccent(null) }
        return
    }
    var time by remember { mutableFloatStateOf(0f) }
    var flash by remember { mutableFloatStateOf(0f) }
    var lastHue by remember { mutableLongStateOf(0L) }
    val rnd = remember(theme) { Random(42) }
    val particles = remember(theme) {
        val n = when (theme) {
            DynamicTheme.SNOWFALL, DynamicTheme.CHRISTMAS -> 90
            DynamicTheme.RAIN, DynamicTheme.LIGHTNING -> 110
            DynamicTheme.FIREFLIES -> 36
            DynamicTheme.HALLOWEEN -> 14
            DynamicTheme.MATRIX -> 48
            DynamicTheme.SAKURA -> 40
            DynamicTheme.Y2K -> 14
            else -> 0
        }
        List(n) {
            Particle(rnd.nextFloat(), rnd.nextFloat(), 0.4f + rnd.nextFloat(), 0.5f + rnd.nextFloat(), rnd.nextFloat() * 2 - 1, rnd.nextFloat() * 6.28f, rnd.nextInt(3))
        }
    }

    LaunchedEffect(theme) {
        if (theme != DynamicTheme.RGB) onAccent(null)
        var last = 0L
        var nextBolt = 2f + rnd.nextFloat() * 5f
        while (true) {
            withFrameNanos { now ->
                val dt = if (last == 0L) 0f else ((now - last) / 1e9f).coerceAtMost(0.1f)
                last = now
                time += dt
                when (theme) {
                    DynamicTheme.RGB -> {
                        // ~12 updates/s is smooth enough for a hue cycle and keeps recomposition cheap.
                        if (now - lastHue > 80_000_000L) {
                            lastHue = now
                            onAccent(Color.hsv((time * 24f) % 360f, 0.85f, 1f))
                        }
                    }
                    DynamicTheme.LIGHTNING -> {
                        flash = (flash - dt * 2.6f).coerceAtLeast(0f)
                        if (time > nextBolt) {
                            flash = 1f
                            nextBolt = time + 3f + rnd.nextFloat() * 7f
                        }
                    }
                    else -> {}
                }
                particles.forEach { p ->
                    when (theme) {
                        DynamicTheme.SNOWFALL, DynamicTheme.CHRISTMAS -> {
                            p.y += dt * 0.05f * p.speed
                            p.x += dt * 0.015f * sin(time + p.phase)
                        }
                        DynamicTheme.RAIN, DynamicTheme.LIGHTNING -> {
                            p.y += dt * 1.1f * p.speed
                            p.x += dt * 0.12f
                        }
                        DynamicTheme.FIREFLIES -> {
                            p.x += dt * 0.02f * sin(time * 0.7f + p.phase)
                            p.y += dt * 0.02f * sin(time * 0.5f + p.phase * 1.3f)
                        }
                        DynamicTheme.HALLOWEEN -> {
                            p.x += dt * 0.05f * p.speed
                            p.y += dt * 0.02f * sin(time * 2 + p.phase)
                        }
                        DynamicTheme.MATRIX -> p.y += dt * 0.25f * p.speed
                        DynamicTheme.Y2K -> p.phase += dt * (0.6f + p.speed)
                        DynamicTheme.SAKURA -> {
                            p.y += dt * 0.04f * p.speed
                            p.x += dt * 0.03f * (1 + sin(time + p.phase))
                        }
                        else -> {}
                    }
                    if (p.y > 1.05f) { p.y = -0.05f; p.x = rnd.nextFloat() }
                    if (p.x > 1.05f) p.x = -0.05f
                    if (p.x < -0.05f) p.x = 1.05f
                }
            }
        }
    }

    Canvas(modifier.fillMaxSize()) {
        val t = time
        when (theme) {
            DynamicTheme.SNOWFALL -> snow(particles)
            DynamicTheme.CHRISTMAS -> {
                snow(particles)
                christmasLights(t)
            }
            DynamicTheme.RAIN -> rain(particles, Color(0x55B0C4DE))
            DynamicTheme.LIGHTNING -> {
                rain(particles, Color(0x448AB4FF))
                if (flash > 0f) {
                    drawRect(Color.White.copy(alpha = 0.22f * flash))
                    if (flash > 0.75f) bolt(t)
                }
            }
            DynamicTheme.CYBERPUNK -> cyberpunk(t)
            DynamicTheme.HALLOWEEN -> halloween(particles, t)
            DynamicTheme.AURORA -> aurora(t)
            DynamicTheme.FIREFLIES -> fireflies(particles, t)
            DynamicTheme.MATRIX -> matrix(particles)
            DynamicTheme.SAKURA -> sakura(particles, t)
            DynamicTheme.RGB -> rgbEdge(t)
            DynamicTheme.Y2K -> y2kOverlay(particles, t)
            DynamicTheme.NONE -> {}
        }
    }
}

private fun DrawScope.snow(ps: List<Particle>) {
    ps.forEach { p ->
        drawCircle(Color.White.copy(alpha = 0.35f + 0.35f * p.size / 1.5f), radius = 1.5f + p.size * 2.6f, center = Offset(p.x * size.width, p.y * size.height))
    }
}

private fun DrawScope.rain(ps: List<Particle>, color: Color) {
    ps.forEach { p ->
        val x = p.x * size.width
        val y = p.y * size.height
        drawLine(color, Offset(x, y), Offset(x - 6f, y + 22f + p.size * 18f), strokeWidth = 1.6f, cap = StrokeCap.Round)
    }
}

private fun DrawScope.bolt(t: Float) {
    val r = Random((t * 10).toInt())
    var x = size.width * (0.3f + r.nextFloat() * 0.5f)
    var y = 0f
    val path = Path().apply { moveTo(x, y) }
    while (y < size.height * 0.6f) {
        x += (r.nextFloat() - 0.5f) * 90f
        y += 40f + r.nextFloat() * 50f
        path.lineTo(x, y)
    }
    drawPath(path, Color.White.copy(alpha = 0.85f), style = androidx.compose.ui.graphics.drawscope.Stroke(width = 4f))
}

private fun DrawScope.christmasLights(t: Float) {
    val colors = listOf(Color(0xFFFF3B30), Color(0xFF34C759), Color(0xFFFFCC00), Color(0xFF0A84FF))
    val n = 26
    val sag = 18f
    for (i in 0 until n) {
        val fx = (i + 0.5f) / n
        val x = fx * size.width
        val y = 10f + sag * sin(fx * PI.toFloat() * 6).let { abs(it) }
        val on = ((t * 2).toInt() + i) % 3 != 0
        val c = colors[i % colors.size]
        drawCircle(c.copy(alpha = if (on) 0.9f else 0.25f), radius = 6f, center = Offset(x, y))
        if (on) drawCircle(c.copy(alpha = 0.18f), radius = 16f, center = Offset(x, y))
    }
}

private fun DrawScope.cyberpunk(t: Float) {
    // Neon horizon grid at the bottom plus faint scanlines.
    val pink = Color(0xFFFF2A6D)
    val cyan = Color(0xFF05D9E8)
    val top = size.height * 0.78f
    drawRect(Brush.verticalGradient(listOf(Color.Transparent, pink.copy(alpha = 0.10f)), startY = top, endY = size.height), topLeft = Offset(0f, top), size = Size(size.width, size.height - top))
    val offset = (t * 40f) % 40f
    var y = top + offset
    while (y < size.height) {
        drawLine(cyan.copy(alpha = 0.18f), Offset(0f, y), Offset(size.width, y), strokeWidth = 1.2f)
        y += 40f
    }
    val cx = size.width / 2
    for (i in -12..12) {
        drawLine(pink.copy(alpha = 0.16f), Offset(cx + i * 30f, top), Offset(cx + i * 180f, size.height), strokeWidth = 1.2f)
    }
    var s = 0f
    while (s < size.height) {
        drawLine(Color.White.copy(alpha = 0.025f), Offset(0f, s), Offset(size.width, s), strokeWidth = 1f)
        s += 4f
    }
}

private fun DrawScope.halloween(ps: List<Particle>, t: Float) {
    drawRect(Brush.verticalGradient(listOf(Color(0x22FF7518), Color.Transparent), endY = size.height * 0.3f))
    // Harvest moon in the top-right corner.
    val moon = Offset(size.width * 0.88f, size.height * 0.14f)
    drawCircle(Brush.radialGradient(listOf(Color(0x40FFB347), Color.Transparent), center = moon, radius = 180f), radius = 180f, center = moon)
    drawCircle(Color(0x66FFC069), radius = 46f, center = moon)
    ps.forEach { p ->
        val x = p.x * size.width
        val y = p.y * size.height * 0.6f
        val w = 14f + p.size * 10f
        val flap = sin(t * 9 + p.phase) * 0.6f
        val bat = Path().apply {
            moveTo(x, y)
            quadraticTo(x - w * 0.5f, y - w * (0.4f + flap), x - w, y + w * 0.1f)
            quadraticTo(x - w * 0.5f, y + w * 0.05f, x, y + w * 0.25f)
            quadraticTo(x + w * 0.5f, y + w * 0.05f, x + w, y + w * 0.1f)
            quadraticTo(x + w * 0.5f, y - w * (0.4f + flap), x, y)
            close()
        }
        drawPath(bat, Color(0x99FF8C2E))
    }
}

private fun DrawScope.aurora(t: Float) {
    val bands = listOf(Color(0xFF34D399), Color(0xFF22D3EE), Color(0xFFA78BFA))
    bands.forEachIndexed { i, c ->
        val path = Path()
        val base = size.height * (0.12f + i * 0.07f)
        path.moveTo(0f, base)
        var x = 0f
        while (x <= size.width) {
            val y = base + sin(x / size.width * 6f + t * (0.3f + i * 0.1f) + i) * 40f
            path.lineTo(x, y)
            x += 24f
        }
        path.lineTo(size.width, 0f)
        path.lineTo(0f, 0f)
        path.close()
        drawPath(path, Brush.verticalGradient(listOf(c.copy(alpha = 0f), c.copy(alpha = 0.10f)), startY = 0f, endY = base + 60f))
    }
}

private fun DrawScope.fireflies(ps: List<Particle>, t: Float) {
    ps.forEach { p ->
        val a = (0.5f + 0.5f * sin(t * 2 + p.phase)).coerceIn(0f, 1f)
        val c = Offset(p.x * size.width, p.y * size.height)
        drawCircle(Color(0xFFFACC15).copy(alpha = 0.12f * a), radius = 18f, center = c)
        drawCircle(Color(0xFFFDE68A).copy(alpha = 0.8f * a), radius = 3f, center = c)
    }
}

private fun DrawScope.matrix(ps: List<Particle>) {
    ps.forEachIndexed { i, p ->
        val x = (i + 0.5f) / ps.size * size.width
        val head = p.y * size.height
        for (k in 0 until 14) {
            val y = head - k * 22f
            if (y < 0) break
            drawRect(Color(0xFF22C55E).copy(alpha = (0.35f - k * 0.025f).coerceAtLeast(0f)), topLeft = Offset(x, y), size = Size(8f, 14f))
        }
    }
}

private fun DrawScope.sakura(ps: List<Particle>, t: Float) {
    ps.forEach { p ->
        val c = Offset(p.x * size.width, p.y * size.height)
        rotate((t * 60f + p.phase * 57f) % 360f, c) {
            drawOval(Color(0xFFF9A8D4).copy(alpha = 0.55f), topLeft = Offset(c.x - 6f * p.size, c.y - 3.5f * p.size), size = Size(12f * p.size, 7f * p.size))
        }
    }
}

private fun DrawScope.rgbEdge(t: Float) {
    val colors = (0..6).map { Color.hsv(((t * 40f) + it * 60f) % 360f, 0.9f, 1f).copy(alpha = 0.55f) }
    drawRect(Brush.horizontalGradient(colors), size = Size(size.width, 3f))
    drawRect(Brush.horizontalGradient(colors.reversed()), topLeft = Offset(0f, size.height - 3f), size = Size(size.width, 3f))
}

/**
 * Y2K, above the UI: chromatic aberration at the screen edges (red and cyan fringes), faint CRT
 * scanlines and a few four-point chrome sparkles that twinkle in and out.
 */
private fun DrawScope.y2kOverlay(ps: List<Particle>, t: Float) {
    val edge = size.width * 0.06f
    drawRect(Brush.horizontalGradient(listOf(Color(0x30FF1E56), Color.Transparent), endX = edge), size = Size(edge, size.height))
    drawRect(Brush.horizontalGradient(listOf(Color.Transparent, Color(0x3000E5FF)), startX = size.width - edge, endX = size.width), topLeft = Offset(size.width - edge, 0f), size = Size(edge, size.height))
    drawRect(Brush.verticalGradient(listOf(Color(0x2200E5FF), Color.Transparent), endY = edge * 0.6f), size = Size(size.width, edge * 0.6f))
    drawRect(Brush.verticalGradient(listOf(Color.Transparent, Color(0x22FF1E56)), startY = size.height - edge * 0.6f, endY = size.height), topLeft = Offset(0f, size.height - edge * 0.6f), size = Size(size.width, edge * 0.6f))
    var y = 0f
    while (y < size.height) {
        drawLine(Color.Black.copy(alpha = 0.06f), Offset(0f, y), Offset(size.width, y), strokeWidth = 1f)
        y += 3f
    }
    ps.forEach { p ->
        val a = sin(p.phase).coerceAtLeast(0f)
        if (a < 0.05f) return@forEach
        val c = Offset(p.x * size.width, p.y * size.height)
        val r = (10f + p.size * 14f) * a
        val glint = Color.White.copy(alpha = 0.75f * a)
        drawLine(glint, Offset(c.x - r, c.y), Offset(c.x + r, c.y), strokeWidth = 2f, cap = StrokeCap.Round)
        drawLine(glint, Offset(c.x, c.y - r), Offset(c.x, c.y + r), strokeWidth = 2f, cap = StrokeCap.Round)
        drawCircle(Color(0xFF7FD4FF).copy(alpha = 0.35f * a), radius = r * 0.35f, center = c)
    }
}

/**
 * Y2K, behind the UI: a PS2 boot-screen style scene. A deep blue void, a perspective floor of
 * light, and rows of translucent glowing towers that slowly rise and fall, with drifting
 * cubes. Drawn in its own layer so only it redraws each frame.
 */
@Composable
fun Y2kBackdrop(modifier: Modifier = Modifier) {
    var time by remember { mutableFloatStateOf(0f) }
    LaunchedEffect(Unit) {
        var last = 0L
        while (true) {
            withFrameNanos { now ->
                // ~30 fps is plenty for slow motion and keeps the TV's GPU cool.
                if (last == 0L || now - last > 33_000_000L) {
                    time += if (last == 0L) 0f else (now - last) / 1e9f
                    last = now
                }
            }
        }
    }
    val light = Palette.Light
    Canvas(modifier.fillMaxSize()) {
        val t = time
        val top = if (light) Color(0xFFE6EEFF) else Color(0xFF02040D)
        val mid = if (light) Color(0xFFB9CCF2) else Color(0xFF0A1440)
        drawRect(Brush.verticalGradient(listOf(top, mid, top)))
        val horizon = size.height * 0.62f
        // Floor: glow at the horizon and converging lines.
        drawRect(
            Brush.verticalGradient(listOf(Color(0x552F6BFF), Color.Transparent), startY = horizon, endY = size.height),
            topLeft = Offset(0f, horizon), size = Size(size.width, size.height - horizon),
        )
        val cx = size.width / 2
        for (i in -10..10) drawLine(Color(0x223F8CFF), Offset(cx + i * 22f, horizon), Offset(cx + i * 200f, size.height), strokeWidth = 1f)
        var fy = 0f
        while (horizon + fy < size.height) {
            drawLine(Color(0x1A3F8CFF), Offset(0f, horizon + fy), Offset(size.width, horizon + fy), strokeWidth = 1f)
            fy = fy * 1.35f + 6f
        }
        // Towers: three depth rows, farther ones smaller and dimmer.
        for (row in 0..2) {
            val depth = 1f - row * 0.3f
            val n = 9 + row * 4
            val w = size.width / n * 0.42f * depth
            for (i in 0 until n) {
                val seed = (i * 37 + row * 101) % 97 / 97f
                val x = (i + 0.5f) / n * size.width + (seed - 0.5f) * w
                val h = size.height * (0.10f + 0.28f * seed) * depth * (0.75f + 0.25f * sin(t * (0.25f + seed * 0.3f) + seed * 6.28f))
                val base = horizon + row * 10f
                val alpha = (0.10f + 0.16f * depth) * (if (light) 0.8f else 1f)
                drawRect(
                    Brush.verticalGradient(listOf(Color(0xFF7FD4FF).copy(alpha = alpha * 1.6f), Color(0xFF2F6BFF).copy(alpha = alpha * 0.4f)), startY = base - h, endY = base),
                    topLeft = Offset(x - w / 2, base - h), size = Size(w, h),
                )
                drawRect(Color.White.copy(alpha = alpha * 1.8f), topLeft = Offset(x - w / 2, base - h), size = Size(w, 2f))
            }
        }
        // Drifting wireframe cubes.
        for (k in 0 until 7) {
            val s0 = k / 7f
            val x = ((s0 * 1.7f + t * 0.012f * (1 + k % 3)) % 1.2f - 0.1f) * size.width
            val y = size.height * (0.12f + 0.4f * ((k * 53 % 11) / 11f)) + sin(t * 0.4f + k) * 14f
            val r = 10f + (k % 3) * 8f
            rotate(t * 20f * (if (k % 2 == 0) 1 else -1) + k * 30f, Offset(x, y)) {
                drawRect(Color(0x667FD4FF), topLeft = Offset(x - r, y - r), size = Size(r * 2, r * 2), style = androidx.compose.ui.graphics.drawscope.Stroke(1.5f))
                drawRect(Color(0x33FF7AD9), topLeft = Offset(x - r * 0.55f, y - r * 0.55f), size = Size(r * 1.1f, r * 1.1f), style = androidx.compose.ui.graphics.drawscope.Stroke(1f))
            }
        }
    }
}
