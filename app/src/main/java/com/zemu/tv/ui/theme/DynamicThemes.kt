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
 * Animated themes. Some bring their own colors; the rest keep your palette and only add an effect.
 * Several restyle the whole app ([style]). [variants] are sub-themes (key to label), e.g. the
 * kinds of weather or the holidays. Effects are drawn above the UI and never take focus or input.
 */
enum class DynamicTheme(
    val label: String,
    val accent: Long? = null,
    val background: Long? = null,
    val style: UiStyle = UiStyle.NORMAL,
    val variants: List<Pair<String, String>> = emptyList(),
    /** Only listed once unlocked (the Cat Rave). */
    val hidden: Boolean = false,
    /** Kids Mode's own themes, picked when Kids Mode starts. */
    val kids: Boolean = false,
) {
    NONE("Off"),
    RGB("RGB"),
    WEATHER("Weather", variants = listOf("SNOW" to "Snow", "RAIN" to "Rain", "STORM" to "Thunderstorm", "FOG" to "Fog", "SUNNY" to "Sunny")),
    HOLIDAYS("Holidays", variants = listOf("AUTO" to "Auto (today's holiday)") + Holiday.entries.map { it.name to it.label }),
    CYBERPUNK("Cyberpunk", 0xFFFF2A6D, 0xFF0B0518),
    FIREFLIES("Fireflies", 0xFFFACC15, 0xFF070A06),
    MATRIX("Matrix", 0xFF22C55E, 0xFF000500),
    SAKURA("Sakura", 0xFFF472B6, 0xFF120810),
    /** Dreamy aurora ribbons, soft glows, rounded floating panels. Restyles the app. */
    ETHEREAL("Ethereal · Aurora", 0xFFC4B5FD, 0xFF0A0918, UiStyle.ETHEREAL),
    /** PS / PS2 system menus: lo-fi glowing towers, controller-button legend, scanlines. Restyles the app. */
    Y2K("PS2 · Y2K", 0xFF6FB4FF, 0xFF00020A, UiStyle.PS2),
    /** Acid-green technical interface (in the spirit of Marathon): clipped corners, grids, readouts. */
    ACIDWAVE("Acidwave", 0xFFC8FF00, 0xFF0A0A0B, UiStyle.ACID),
    /** Vintage PC desktop: beveled windows and a mouse pointer on what's selected. */
    RETRO("Cybercore", style = UiStyle.RETRO, variants = listOf("CLASSIC" to "Classic", "KAWAII" to "Kawaii", "XP" to "XP")),
    /** Subway walls and tags; OK sprays paint that drips. */
    GRAFFITI("Graffiti", 0xFFFF2E88, 0xFF161616, UiStyle.GRAFFITI),
    /** Translucent liquid glass over a vivid wallpaper. */
    LIQUID("Liquid Glass", 0xFF0A84FF, 0xFF0B1226, UiStyle.LIQUID),
    /** Shh. */
    CATRAVE("Cat Rave", 0xFFFF00E6, 0xFF07000F, UiStyle.CATRAVE, hidden = true),
    /** Kids Mode: sky, hills and rising balloons; big bubbly buttons. */
    TODDLER("Toddler", 0xFFFF7A1A, 0xFFCDEBFF, UiStyle.TODDLER, kids = true),
    /** Kids Mode: notebook paper, doodles and paper airplanes. */
    GRADE_SCHOOL("Grade School", 0xFF2F6FED, 0xFFFFFBEA, UiStyle.GRADE, kids = true),
    /** Kids Mode: a night gradient with drifting glow orbs and sparkles. */
    YOUNG_ADULT("Young Adult", 0xFF7CFFCB, 0xFF0E0B1F, UiStyle.TEEN, kids = true),
    ;

    /** This theme's own accent and background for [variant], or null to keep your palette. */
    fun colorsFor(variant: String): Pair<Long, Long>? = when (this) {
        WEATHER -> if (variant == "STORM") 0xFF8AB4FF to 0xFF06080F else null
        HOLIDAYS -> Holiday.of(resolveVariant(variant)).let { it.accent to it.background }
        RETRO -> null
        else -> if (accent != null && background != null) accent to background else null
    }

    /** "AUTO" holidays become today's (or the next) holiday. */
    fun resolveVariant(variant: String): String =
        if (this == HOLIDAYS && (variant == "AUTO" || variant.isEmpty())) Holiday.today().name else variant

    companion object {
        /** Removed themes map to where their effect lives now. */
        private val RENAMED = mapOf(
            "SNOWFALL" to "WEATHER", "RAIN" to "WEATHER", "LIGHTNING" to "WEATHER",
            "HALLOWEEN" to "HOLIDAYS", "CHRISTMAS" to "HOLIDAYS", "AURORA" to "ETHEREAL",
        )

        fun of(name: String) = entries.firstOrNull { it.name == (RENAMED[name] ?: name) } ?: NONE
    }
}

/** Holidays for the Holidays theme, each with its own colors and effect. */
enum class Holiday(val label: String, val accent: Long, val background: Long) {
    NEWYEAR("New Year", 0xFFFFD166, 0xFF07060F),
    LUNAR("Lunar New Year", 0xFFFF3B30, 0xFF140405),
    VALENTINE("Valentine's Day", 0xFFFF4D8D, 0xFF14060C),
    STPATRICK("St. Patrick's Day", 0xFF2ECC71, 0xFF04120A),
    EASTER("Easter", 0xFFB39DFF, 0xFF0E0B16),
    JULY4("Fourth of July", 0xFF3B82F6, 0xFF070A16),
    HALLOWEEN("Halloween", 0xFFFF7518, 0xFF0F0710),
    DIWALI("Diwali", 0xFFFFA62B, 0xFF120802),
    THANKSGIVING("Thanksgiving", 0xFFD97706, 0xFF120A04),
    HANUKKAH("Hanukkah", 0xFF5DA9FF, 0xFF050A18),
    CHRISTMAS("Christmas", 0xFFD42426, 0xFF06120B),
    ;

    companion object {
        fun of(name: String) = entries.firstOrNull { it.name == name } ?: CHRISTMAS

        /** The holiday around [date] (a few days either side), else the next one coming up. */
        fun today(date: java.time.LocalDate = java.time.LocalDate.now()): Holiday {
            val windows = windows(date.year) + windows(date.year + 1)
            return windows.firstOrNull { (_, r) -> date in r }?.first
                ?: windows.filter { (_, r) -> r.start > date }.minByOrNull { (_, r) -> r.start }!!.first
        }

        private fun windows(y: Int): List<Pair<Holiday, ClosedRange<java.time.LocalDate>>> {
            fun d(m: Int, day: Int) = java.time.LocalDate.of(y, m, day)
            fun around(x: java.time.LocalDate, before: Long, after: Long) = x.minusDays(before)..x.plusDays(after)
            val easter = easter(y)
            val thanksgiving = d(11, 1).with(java.time.temporal.TemporalAdjusters.dayOfWeekInMonth(4, java.time.DayOfWeek.THURSDAY))
            // Diwali and Hanukkah follow lunar calendars; known dates, else a typical one.
            val diwali = DIWALI_DATES[y]?.let { java.time.LocalDate.parse(it) } ?: d(11, 1)
            val hanukkah = HANUKKAH_DATES[y]?.let { java.time.LocalDate.parse(it) } ?: d(12, 10)
            val lunar = LUNAR_DATES[y]?.let { java.time.LocalDate.parse(it) } ?: d(2, 1)
            // More specific holidays first, so they win where windows overlap.
            return listOf(
                DIWALI to around(diwali, 3, 3),
                HANUKKAH to around(hanukkah, 0, 7),
                VALENTINE to around(d(2, 14), 7, 0),
                LUNAR to around(lunar, 7, 10),
                STPATRICK to around(d(3, 17), 7, 0),
                EASTER to around(easter, 7, 1),
                JULY4 to around(d(7, 4), 6, 0),
                THANKSGIVING to around(thanksgiving, 10, 2),
                HALLOWEEN to d(10, 1)..d(10, 31),
                CHRISTMAS to d(12, 1)..d(12, 26),
                NEWYEAR to d(12, 27)..d(12, 31),
                NEWYEAR to d(1, 1)..d(1, 7),
            )
        }

        /** Gregorian Easter Sunday (anonymous algorithm). */
        fun easter(y: Int): java.time.LocalDate {
            val a = y % 19; val b = y / 100; val c = y % 100; val d = b / 4; val e = b % 4
            val f = (b + 8) / 25; val g = (b - f + 1) / 3; val h = (19 * a + b - d - g + 15) % 30
            val i = c / 4; val k = c % 4; val l = (32 + 2 * e + 2 * i - h - k) % 7; val m = (a + 11 * h + 22 * l) / 451
            val month = (h + l - 7 * m + 114) / 31; val day = (h + l - 7 * m + 114) % 31 + 1
            return java.time.LocalDate.of(y, month, day)
        }

        private val DIWALI_DATES = mapOf(2025 to "2025-10-20", 2026 to "2026-11-08", 2027 to "2027-10-29", 2028 to "2028-10-17", 2029 to "2029-11-05", 2030 to "2030-10-26")
        private val HANUKKAH_DATES = mapOf(2025 to "2025-12-14", 2026 to "2026-12-04", 2027 to "2027-12-24", 2028 to "2028-12-12", 2029 to "2029-12-01", 2030 to "2030-12-20")
        private val LUNAR_DATES = mapOf(2025 to "2025-01-29", 2026 to "2026-02-17", 2027 to "2027-02-06", 2028 to "2028-01-26", 2029 to "2029-02-13", 2030 to "2030-02-03")
    }
}

/** Colors after applying an animated theme's own palette (if it has one). */
fun DynamicTheme.applyTo(base: ThemeColors, variant: String): ThemeColors {
    if (this == DynamicTheme.RETRO) return retroColors(variant, base)
    if (kids) return kidsColors(this)
    val own = colorsFor(variant) ?: return base
    // Its own palette replaces yours entirely (your saved edits for this theme apply afterwards).
    val c = ThemeColors(Color(own.first.toInt()), Color(own.second.toInt()), light = base.light, glass = base.glass || style == UiStyle.LIQUID)
    return if (base.light) c else c.copy(customBase = Color(own.second.toInt()))
}

/** Cybercore's desktops: Classic (teal desktop, gray windows), Kawaii (pastel), XP (blue sky, beige windows). */
private fun retroColors(variant: String, base: ThemeColors): ThemeColors {
    val (accent, desk, window, text) = when (variant) {
        "KAWAII" -> listOf(0xFFFF5FB8, 0xFFFFD6EC, 0xFFFFF4FA, 0xFF5A2346)
        "XP" -> listOf(0xFF2459D6, 0xFF3A7BD5, 0xFFECE9D8, 0xFF111111)
        else -> listOf(0xFF000080, 0xFF008080, 0xFFC0C0C0, 0xFF000000)
    }.map { Color(it.toInt()) }
    // Desktops and windows are light: dark text, like the real thing.
    return ThemeColors(accent, desk, light = true, customBase = desk, customPanel = window, customButton = window, customText = text)
}

/** Kids themes have fixed colors: Toddler and Grade School are light, Young Adult is dark. */
private fun kidsColors(theme: DynamicTheme): ThemeColors {
    val (accent, base, panel, text) = when (theme) {
        DynamicTheme.TODDLER -> listOf(0xFFFF7A1A, 0xFFCDEBFF, 0xFFFFFFFF, 0xFF23305A)
        DynamicTheme.GRADE_SCHOOL -> listOf(0xFF2F6FED, 0xFFFFFBEA, 0xFFFFFFFF, 0xFF1F2937)
        else -> listOf(0xFF7CFFCB, 0xFF0E0B1F, 0xFF1C1736, 0xFFF4F1FF)
    }.map { Color(it.toInt()) }
    return ThemeColors(accent, base, light = theme != DynamicTheme.YOUNG_ADULT, customBase = base, customPanel = panel, customButton = panel, customText = text)
}

private class Particle(var x: Float, var y: Float, var speed: Float, var size: Float, var drift: Float, var phase: Float, var kind: Int = 0)

/** The effect key for a theme and its sub-theme: "SNOW", "RAIN", "HALLOWEEN", "MATRIX", … */
private fun effectKey(theme: DynamicTheme, variant: String): String = when (theme) {
    DynamicTheme.WEATHER -> variant.ifEmpty { "SNOW" }
    DynamicTheme.HOLIDAYS -> theme.resolveVariant(variant)
    else -> theme.name
}

/**
 * Draws [theme]'s animation. RGB and the Cat Rave instead call [onAccent] with a cycling hue, so
 * the whole UI's accent color shifts.
 */
@Composable
fun DynamicThemeLayer(theme: DynamicTheme, variant: String = "", onAccent: (Color?) -> Unit, modifier: Modifier = Modifier) {
    if (theme == DynamicTheme.NONE) {
        LaunchedEffect(Unit) { onAccent(null) }
        return
    }
    val effect = effectKey(theme, variant)
    var time by remember { mutableFloatStateOf(0f) }
    var flash by remember { mutableFloatStateOf(0f) }
    var lastHue by remember { mutableLongStateOf(0L) }
    val rnd = remember(effect) { Random(42) }
    val particles = remember(effect) {
        val n = when (effect) {
            "SNOW", "CHRISTMAS" -> 90
            "RAIN", "STORM" -> 110
            "FIREFLIES", "SUNNY" -> 36
            "HALLOWEEN" -> 14
            "MATRIX" -> 48
            "SAKURA", "THANKSGIVING", "STPATRICK" -> 40
            "VALENTINE", "EASTER", "HANUKKAH", "DIWALI", "LUNAR", "ETHEREAL" -> 34
            "CATRAVE" -> 80
            "TODDLER" -> 14
            "GRADE_SCHOOL" -> 5
            "YOUNG_ADULT" -> 40
            else -> 0
        }
        List(n) {
            Particle(rnd.nextFloat(), rnd.nextFloat(), 0.4f + rnd.nextFloat(), 0.5f + rnd.nextFloat(), rnd.nextFloat() * 2 - 1, rnd.nextFloat() * 6.28f, rnd.nextInt(4))
        }
    }

    LaunchedEffect(effect) {
        val cycles = theme == DynamicTheme.RGB || theme == DynamicTheme.CATRAVE
        if (!cycles) onAccent(null)
        var last = 0L
        var nextBolt = 2f + rnd.nextFloat() * 5f
        while (true) {
            withFrameNanos { now ->
                val dt = if (last == 0L) 0f else ((now - last) / 1e9f).coerceAtMost(0.1f)
                last = now
                time += dt
                if (theme == DynamicTheme.CATRAVE) RaveClock.t = time
                // ~12 hue updates/s is smooth enough and keeps recomposition cheap; the rave cycles 6x faster.
                if (cycles && now - lastHue > 80_000_000L) {
                    lastHue = now
                    onAccent(Color.hsv((time * (if (theme == DynamicTheme.CATRAVE) 150f else 24f)) % 360f, 0.85f, 1f))
                }
                if (effect == "STORM") {
                    flash = (flash - dt * 2.6f).coerceAtLeast(0f)
                    if (time > nextBolt) { flash = 1f; nextBolt = time + 3f + rnd.nextFloat() * 7f }
                }
                particles.forEach { p ->
                    when (effect) {
                        "SNOW", "CHRISTMAS" -> { p.y += dt * 0.05f * p.speed; p.x += dt * 0.015f * sin(time + p.phase) }
                        "RAIN", "STORM" -> { p.y += dt * 1.1f * p.speed; p.x += dt * 0.12f }
                        "FIREFLIES", "SUNNY" -> { p.x += dt * 0.02f * sin(time * 0.7f + p.phase); p.y += dt * 0.02f * sin(time * 0.5f + p.phase * 1.3f) }
                        "HALLOWEEN" -> { p.x += dt * 0.05f * p.speed; p.y += dt * 0.02f * sin(time * 2 + p.phase) }
                        "MATRIX" -> p.y += dt * 0.25f * p.speed
                        "SAKURA", "THANKSGIVING", "STPATRICK" -> { p.y += dt * 0.04f * p.speed; p.x += dt * 0.03f * (1 + sin(time + p.phase)) }
                        // Rising: hearts, eggs, sparks, sparkles.
                        "VALENTINE", "EASTER", "HANUKKAH", "DIWALI", "LUNAR", "ETHEREAL" -> { p.y -= dt * 0.035f * p.speed; p.x += dt * 0.01f * sin(time + p.phase) }
                        "CATRAVE" -> { p.y += dt * 0.12f * p.speed; p.x += dt * 0.04f * sin(time * 3 + p.phase) }
                        // Balloons float up and sway; paper airplanes glide across; sparkles drift up.
                        "TODDLER" -> { p.y -= dt * 0.045f * p.speed; p.x += dt * 0.012f * sin(time * 0.8f + p.phase) }
                        "GRADE_SCHOOL" -> { p.x += dt * 0.07f * p.speed; p.y += dt * 0.02f * sin(time * 1.3f + p.phase) }
                        "YOUNG_ADULT" -> { p.y -= dt * 0.02f * p.speed; p.x += dt * 0.008f * sin(time * 0.5f + p.phase) }
                        else -> {}
                    }
                    if (p.y > 1.05f) { p.y = -0.05f; p.x = rnd.nextFloat() }
                    if (p.y < -0.05f) { p.y = 1.05f; p.x = rnd.nextFloat() }
                    if (p.x > 1.05f) p.x = -0.05f
                    if (p.x < -0.05f) p.x = 1.05f
                }
            }
        }
    }

    Canvas(modifier.fillMaxSize()) {
        val t = time
        when (effect) {
            "SNOW" -> snow(particles)
            "RAIN" -> rain(particles, Color(0x55B0C4DE))
            "STORM" -> {
                rain(particles, Color(0x448AB4FF))
                if (flash > 0f) {
                    drawRect(Color.White.copy(alpha = 0.22f * flash))
                    if (flash > 0.75f) bolt(t)
                }
            }
            "FOG" -> fog(t)
            "SUNNY" -> sunny(particles, t)
            "CHRISTMAS" -> { snow(particles); christmasLights(t) }
            "HALLOWEEN" -> halloween(particles, t)
            "NEWYEAR" -> fireworks(t, listOf(Color(0xFFFFD166), Color(0xFFFFF4C2), Color(0xFFE6C3FF)))
            "JULY4" -> fireworks(t, listOf(Color(0xFFEF4444), Color.White, Color(0xFF3B82F6)))
            "VALENTINE" -> hearts(particles)
            "STPATRICK" -> clovers(particles, t)
            "EASTER" -> eggs(particles)
            "THANKSGIVING" -> leaves(particles, t)
            "HANUKKAH" -> { sparkles(particles, Color(0xFFBFDBFE)); menorah(t) }
            "DIWALI" -> { sparkles(particles, Color(0xFFFFC56B)); diyas(t) }
            "LUNAR" -> { sparkles(particles, Color(0xFFFFD166)); lanterns(t) }
            "CYBERPUNK" -> cyberpunk(t)
            "ETHEREAL" -> sparkles(particles, Color(0xFFE9E4FF))
            "FIREFLIES" -> fireflies(particles, t)
            "MATRIX" -> matrix(particles)
            "SAKURA" -> sakura(particles, t)
            "RGB" -> rgbEdge(t)
            "Y2K" -> ps2Overlay()
            "ACIDWAVE" -> acidOverlay(t)
            "CATRAVE" -> catRaveOverlay(particles, t)
            "TODDLER" -> balloons(particles, t)
            "GRADE_SCHOOL" -> paperPlanes(particles, t)
            "YOUNG_ADULT" -> sparkles(particles, Color(0xFFB9FFE6))
            else -> {}
        }
    }
    if (theme == DynamicTheme.Y2K) androidx.compose.foundation.layout.Box(modifier.fillMaxSize()) {
        Ps2Legend(Modifier.align(androidx.compose.ui.Alignment.BottomEnd))
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

internal fun DrawScope.aurora(t: Float) {
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


// ---- Weather ----

private fun DrawScope.fog(t: Float) {
    for (i in 0 until 4) {
        val y = size.height * (0.2f + i * 0.2f)
        val dx = ((t * (8f + i * 5f)) % size.width)
        listOf(dx - size.width, dx).forEach { x ->
            drawOval(
                Brush.radialGradient(listOf(Color.White.copy(alpha = 0.10f), Color.Transparent), center = Offset(x + size.width / 2, y), radius = size.width * 0.45f),
                topLeft = Offset(x, y - size.height * 0.12f), size = Size(size.width, size.height * 0.24f),
            )
        }
    }
}

private fun DrawScope.sunny(ps: List<Particle>, t: Float) {
    val origin = Offset(size.width * 0.92f, -size.height * 0.1f)
    for (i in 0 until 7) {
        val a = Math.toRadians(100.0 + i * 11 + sin(t * 0.2f + i) * 3).toFloat()
        val end = Offset(origin.x + kotlin.math.cos(a) * size.maxDimension * 1.3f, origin.y + kotlin.math.sin(a) * size.maxDimension * 1.3f)
        drawLine(Brush.linearGradient(listOf(Color(0x33FFE7A3), Color.Transparent), start = origin, end = end), origin, end, strokeWidth = 60f + i * 10f)
    }
    ps.forEach { p -> drawCircle(Color(0x66FFF3C4), radius = 1.5f + p.size, center = Offset(p.x * size.width, p.y * size.height)) }
}

// ---- Holidays ----

/** A burst every ~1.4 s at a random spot, sparks flying out and fading. */
private fun DrawScope.fireworks(t: Float, colors: List<Color>) {
    for (k in 0 until 3) {
        val period = 1.4f
        val local = t + k * 0.47f
        val n = (local / period).toInt()
        val age = (local % period) / period
        val r = Random(n * 7 + k)
        val c = Offset(size.width * (0.15f + r.nextFloat() * 0.7f), size.height * (0.1f + r.nextFloat() * 0.35f))
        val color = colors[r.nextInt(colors.size)]
        for (i in 0 until 26) {
            val a = i / 26f * 6.283f
            val d = age * size.minDimension * 0.18f
            drawCircle(color.copy(alpha = (1f - age) * 0.8f), radius = 2.5f, center = Offset(c.x + kotlin.math.cos(a) * d, c.y + kotlin.math.sin(a) * d + age * age * 40f))
        }
    }
}

private fun DrawScope.heart(c: Offset, r: Float, color: Color) {
    drawPath(Path().apply {
        moveTo(c.x, c.y + r * 0.9f)
        cubicTo(c.x - r * 1.6f, c.y - r * 0.2f, c.x - r * 0.6f, c.y - r * 1.3f, c.x, c.y - r * 0.4f)
        cubicTo(c.x + r * 0.6f, c.y - r * 1.3f, c.x + r * 1.6f, c.y - r * 0.2f, c.x, c.y + r * 0.9f)
        close()
    }, color)
}

private fun DrawScope.hearts(ps: List<Particle>) =
    ps.forEach { p -> heart(Offset(p.x * size.width, p.y * size.height), 6f + p.size * 6f, Color(if (p.kind % 2 == 0) 0x66FF4D8D else 0x55FFB3CF)) }

private fun DrawScope.clovers(ps: List<Particle>, t: Float) = ps.forEach { p ->
    val c = Offset(p.x * size.width, p.y * size.height)
    val r = 4f + p.size * 3f
    rotate(t * 30f + p.phase * 57f, c) {
        for (i in 0 until 3) {
            val a = i * 2.094f
            drawCircle(Color(0x6632C66B), r, Offset(c.x + kotlin.math.cos(a) * r, c.y + kotlin.math.sin(a) * r))
        }
        drawLine(Color(0x6632C66B), c, Offset(c.x, c.y + r * 2.4f), 2f)
    }
}

private fun DrawScope.eggs(ps: List<Particle>) {
    val pastel = listOf(Color(0x77F9A8D4), Color(0x77A7F3D0), Color(0x77BFDBFE), Color(0x77FDE68A))
    ps.forEach { p ->
        val c = Offset(p.x * size.width, p.y * size.height)
        val w = 10f + p.size * 6f
        drawOval(pastel[p.kind % 4], topLeft = Offset(c.x - w / 2, c.y - w * 0.65f), size = Size(w, w * 1.3f))
        drawLine(Color.White.copy(alpha = 0.4f), Offset(c.x - w / 2.4f, c.y), Offset(c.x + w / 2.4f, c.y), 2f)
    }
}

private fun DrawScope.leaves(ps: List<Particle>, t: Float) {
    val tones = listOf(Color(0x88D97706), Color(0x88B45309), Color(0x88EA580C), Color(0x889A3412))
    ps.forEach { p ->
        val c = Offset(p.x * size.width, p.y * size.height)
        rotate((t * 50f + p.phase * 57f) % 360f, c) {
            drawOval(tones[p.kind % 4], topLeft = Offset(c.x - 9f * p.size, c.y - 4f * p.size), size = Size(18f * p.size, 8f * p.size))
        }
    }
}

private fun DrawScope.sparkles(ps: List<Particle>, color: Color) = ps.forEach { p ->
    val c = Offset(p.x * size.width, p.y * size.height)
    val a = (0.4f + 0.6f * sin(p.phase + p.y * 20f).coerceAtLeast(0f))
    drawCircle(color.copy(alpha = 0.18f * a), 8f * p.size, c)
    drawCircle(color.copy(alpha = 0.8f * a), 1.6f * p.size, c)
}

/** A small menorah glowing at the bottom left: nine flickering candles. */
private fun DrawScope.menorah(t: Float) {
    val baseY = size.height - 30f
    val x0 = 60f
    drawLine(Color(0x88D4AF37), Offset(x0, baseY), Offset(x0 + 200f, baseY), 4f)
    for (i in 0 until 9) {
        val x = x0 + i * 25f
        val top = baseY - if (i == 4) 70f else 52f
        drawLine(Color(0x99E5E7EB), Offset(x, baseY), Offset(x, top), 6f)
        val f = 0.8f + 0.2f * sin(t * 11f + i)
        drawCircle(Color(0x55FFD166), 12f * f, Offset(x, top - 8f))
        drawOval(Color(0xCCFFC145), topLeft = Offset(x - 3f, top - 15f * f), size = Size(6f, 12f * f))
    }
}

/** A row of diya lamps along the bottom, flames flickering. */
private fun DrawScope.diyas(t: Float) {
    val n = 9
    for (i in 0 until n) {
        val x = size.width * (i + 0.5f) / n
        val y = size.height - 22f
        drawArc(Color(0x99B45309), 0f, 180f, true, topLeft = Offset(x - 18f, y - 12f), size = Size(36f, 24f))
        val f = 0.8f + 0.25f * sin(t * 9f + i * 1.7f)
        drawCircle(Color(0x44FFA62B), 22f * f, Offset(x, y - 16f))
        drawOval(Color(0xDDFFD166), topLeft = Offset(x - 4f, y - 26f * f), size = Size(8f, 16f * f))
    }
}

/** Red lanterns hanging along the top, swinging gently. */
private fun DrawScope.lanterns(t: Float) {
    for (i in 0 until 6) {
        val x = size.width * (0.08f + i * 0.17f)
        rotate(sin(t * 1.2f + i) * 6f, Offset(x, 0f)) {
            drawLine(Color(0x88FFD166), Offset(x, 0f), Offset(x, 40f), 2f)
            drawOval(Color(0xAAE11D2E), topLeft = Offset(x - 26f, 40f), size = Size(52f, 44f))
            drawRect(Color(0xAAFFD166), topLeft = Offset(x - 12f, 36f), size = Size(24f, 6f))
            drawRect(Color(0xAAFFD166), topLeft = Offset(x - 12f, 82f), size = Size(24f, 6f))
            drawLine(Color(0x88FFD166), Offset(x, 88f), Offset(x, 108f), 2f)
        }
    }
}

// ---- Cat Rave ----

/** A cat face: round head, pointy ears, eyes. */
internal fun DrawScope.catFace(c: Offset, r: Float, color: Color) {
    drawPath(Path().apply { moveTo(c.x - r * 0.9f, c.y - r * 0.3f); lineTo(c.x - r * 0.7f, c.y - r * 1.25f); lineTo(c.x - r * 0.2f, c.y - r * 0.8f); close() }, color)
    drawPath(Path().apply { moveTo(c.x + r * 0.9f, c.y - r * 0.3f); lineTo(c.x + r * 0.7f, c.y - r * 1.25f); lineTo(c.x + r * 0.2f, c.y - r * 0.8f); close() }, color)
    drawCircle(color, r, c)
    drawCircle(Color.Black.copy(alpha = 0.75f), r * 0.14f, Offset(c.x - r * 0.38f, c.y - r * 0.1f))
    drawCircle(Color.Black.copy(alpha = 0.75f), r * 0.14f, Offset(c.x + r * 0.38f, c.y - r * 0.1f))
    drawCircle(Color(0xFFFF8FB1), r * 0.1f, Offset(c.x, c.y + r * 0.2f))
    for (s in listOf(-1f, 1f)) for (k in listOf(-0.1f, 0.15f)) {
        drawLine(Color.Black.copy(alpha = 0.5f), Offset(c.x + s * r * 0.25f, c.y + r * (0.25f + k)), Offset(c.x + s * r * 1.15f, c.y + r * (0.15f + k * 2)), 1.5f)
    }
}

/** Confetti, sweeping lasers, a strobe pulse on the beat and cats bopping along the bottom. */
private fun DrawScope.catRaveOverlay(ps: List<Particle>, t: Float) {
    val beat = (t * 2.13f) % 1f // ~128 BPM
    drawRect(Color.hsv((t * 150f) % 360f, 1f, 1f).copy(alpha = 0.10f * (1f - beat)))
    for (i in 0 until 4) {
        val origin = Offset(size.width * (0.2f + i * 0.2f), size.height)
        val a = Math.toRadians(250.0 + sin(t * (1.1f + i * 0.3f)) * 35).toFloat()
        val end = Offset(origin.x + kotlin.math.cos(a) * size.height * 1.4f, origin.y + kotlin.math.sin(a) * size.height * 1.4f)
        drawLine(Color.hsv((t * 90f + i * 90f) % 360f, 1f, 1f).copy(alpha = 0.35f), origin, end, strokeWidth = 3f)
    }
    ps.forEach { p ->
        drawRect(Color.hsv((p.phase * 57f + t * 200f) % 360f, 0.9f, 1f).copy(alpha = 0.7f), topLeft = Offset(p.x * size.width, p.y * size.height), size = Size(6f * p.size, 3f * p.size))
    }
    val n = 7
    for (i in 0 until n) {
        val bob = kotlin.math.abs(sin((t * 2.13f + i * 0.5f) * 3.1416f)) * 22f
        catFace(Offset(size.width * (i + 0.5f) / n, size.height - 40f - bob), 26f, Color.hsv((t * 120f + i * 51f) % 360f, 0.7f, 1f).copy(alpha = 0.85f))
    }
}

private val BALLOON_COLORS = listOf(Color(0xFFFF5A5F), Color(0xFFFFC93C), Color(0xFF3EC1FF), Color(0xFF7BD389), Color(0xFFB57BFF), Color(0xFFFF8AC7))

/** Toddler: balloons on strings along the right edge (the menu is on the left), clear of most posters. */
private fun DrawScope.balloons(ps: List<Particle>, t: Float) {
    ps.forEachIndexed { i, p ->
        val x = (0.86f + p.x * 0.14f) * size.width
        val y = p.y * size.height
        val r = 22f + p.size * 14f
        val c = BALLOON_COLORS[i % BALLOON_COLORS.size]
        val sway = sin(t * 1.5f + p.phase) * 10f
        val string = Path().apply {
            moveTo(x, y + r * 1.2f)
            quadraticTo(x + sway, y + r * 2.2f, x - sway * 0.5f, y + r * 3.4f)
        }
        drawPath(string, Color(0x8823305A), style = androidx.compose.ui.graphics.drawscope.Stroke(width = 2f))
        drawOval(c.copy(alpha = 0.75f), Offset(x - r, y - r * 1.2f), Size(r * 2, r * 2.4f))
        drawCircle(Color.White.copy(alpha = 0.5f), r * 0.22f, Offset(x - r * 0.4f, y - r * 0.55f))
    }
}

/** Grade School: a few paper airplanes with dashed trails. */
private fun DrawScope.paperPlanes(ps: List<Particle>, t: Float) {
    ps.forEachIndexed { i, p ->
        val x = p.x * size.width
        val y = (0.08f + (i * 0.21f) % 0.9f) * size.height + p.y * 80f
        val s = 16f + p.size * 10f
        val tilt = sin(t * 1.3f + p.phase) * 8f
        rotate(tilt, Offset(x, y)) {
            var tx = x - s * 2
            while (tx > x - s * 9) {
                drawLine(Color(0x552F6FED), Offset(tx, y + sin(tx / 40f) * 6f), Offset(tx - 10f, y + sin((tx - 10f) / 40f) * 6f), strokeWidth = 2.5f, cap = StrokeCap.Round)
                tx -= 20f
            }
            val wing = Path().apply { moveTo(x + s * 2, y); lineTo(x - s * 1.4f, y - s); lineTo(x - s * 0.6f, y); close() }
            val body = Path().apply { moveTo(x + s * 2, y); lineTo(x - s * 1.4f, y + s * 0.7f); lineTo(x - s * 0.6f, y); close() }
            drawPath(wing, Color.White)
            drawPath(body, Color(0xFFDDE6F7))
            drawPath(wing, Color(0xFF1F2937), style = androidx.compose.ui.graphics.drawscope.Stroke(width = 1.8f))
            drawPath(body, Color(0xFF1F2937), style = androidx.compose.ui.graphics.drawscope.Stroke(width = 1.8f))
        }
    }
}
