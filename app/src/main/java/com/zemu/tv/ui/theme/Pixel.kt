package com.zemu.tv.ui.theme

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import kotlin.math.abs
import kotlin.math.sin

/**
 * Pixel art from text: each character is one pixel, looked up in a palette ('.' is see-through).
 * Rows may be ragged; short ones are padded.
 */
class Sprite(rows: List<String>) {
    val w = rows.maxOf { it.length }
    val h = rows.size
    private val px = rows.map { it.padEnd(w, '.') }

    fun draw(d: DrawScope, at: Offset, pixel: Float, colors: Map<Char, Color>, flip: Boolean = false) = with(d) {
        for (y in 0 until h) for (x in 0 until w) {
            val c = colors[px[y][if (flip) w - 1 - x else x]] ?: continue
            drawRect(c, Offset(at.x + x * pixel, at.y + y * pixel), Size(pixel + 0.5f, pixel + 0.5f))
        }
    }
}

private fun sprite(vararg rows: String) = Sprite(rows.toList())

// ---- Menu icons (12×12) for the vintage-PC and console themes ----

private val ICONS = mapOf(
    "SEARCH" to sprite(
        "..kkkk......", ".k....k.....", "k.wwww.k....", "k.wbbw.k....", "k.wbbw.k....", "k.wwww.k....",
        ".k....k.....", "..kkkkkk....", ".......kk...", "........kk..", ".........kk.", "..........k.",
    ),
    "HOME" to sprite(
        ".....kk.....", "....krrk....", "...krrrrk...", "..krrrrrrk..", ".krrrrrrrrk.", "kkkkkkkkkkkk",
        ".kyyyyyyyyk.", ".kyykkyywwk.", ".kyykbkywwk.", ".kyykbkyyyk.", ".kyykbkyyyk.", ".kkkkkkkkkk.",
    ),
    "MOVIES" to sprite(
        "kkkkkkkkkkkk", "kwwkkwwkkwwk", "kkkkkkkkkkkk", "kggggggggggk", "kgwwwwwwwwgk", "kgwbbbbbbwgk",
        "kgwbbbbbbwgk", "kgwbbbbbbwgk", "kgwwwwwwwwgk", "kggggggggggk", "kkkkkkkkkkkk",
    ),
    "SERIES" to sprite(
        "kkkkkkkkkkkk", "kggggggggggk", "kgbbbbbbbbgk", "kgbccbbbbbgk", "kgbcbbbbbbgk", "kgbbbbbbbbgk",
        "kgbbbbbbbbgk", "kggggggggggk", "kkkkkkkkkkkk", "....kggk....", "..kkkkkkkk..",
    ),
    "ANIME" to sprite(
        ".....kk.....", "....kyyk....", "....kyyk....", "kkkkkyykkkkk", "kyyyyyyyyyyk", ".kyyyyyyyyk.",
        "..kyyyyyyk..", "..kyyyyyyk..", ".kyyykkyyyk.", ".kyyk..kyyk.", "kyyk....kyyk", "kkk......kkk",
    ),
    "MY_LIST" to sprite(
        "............", ".kkk...kkk..", "krrrk.krrrk.", "krwrrkrrrrk.", "krrrrrrrrrk.", "krrrrrrrrrk.",
        ".krrrrrrrk..", "..krrrrrk...", "...krrrk....", "....krk.....", ".....k......",
    ),
    "SETTINGS" to sprite(
        "....kkkk....", "..k.kggk.k..", ".kgkkggkkgk.", "..kggggggk..", "kkgggkkgggkk", "kgggk..kgggk",
        "kgggk..kgggk", "kkgggkkgggkk", "..kggggggk..", ".kgkkggkkgk.", "..k.kggk.k..", "....kkkk....",
    ),
    "PROFILES" to sprite(
        "....kkkk....", "...kyyyyk...", "...kyyyyk...", "...kyyyyk...", "....kkkk....", "...kbbbbk...",
        "..kbbbbbbk..", ".kbbbbbbbbk.", ".kbbbbbbbbk.", ".kbbbbbbbbk.", ".kkkkkkkkkk.",
    ),
    "THEME" to sprite(
        "...kkkkkk...", "..kwwwwwwk..", ".kwrrwwbbwk.", "kwwrrwwbbwwk", "kwwwwwwwwwwk", "kwggwwkkwwwk",
        "kwggwk..kwwk", ".kwwwk..kwk.", "..kwwwkkkk..", "...kkkk.....",
    ),
    "LOCK" to sprite(
        "...kkkkkk...", "..k......k..", "..k......k..", "..k......k..", "kkkkkkkkkkkk", "kyyyyyyyyyyk",
        "kyyyykkyyyyk", "kyyyykkyyyyk", "kyyyyykyyyyk", "kyyyyyyyyyyk", "kkkkkkkkkkkk",
    ),
)

/** Icon colors per style: Windows-era colors, the handheld's four greens, or 16-bit brights. */
private fun iconColors(): Map<Char, Color> = when (Palette.Style) {
    UiStyle.POCKET -> mapOf(
        'k' to Color(0xFF0F380F), 'w' to Color(0xFF9BBC0F), 'b' to Color(0xFF306230), 'r' to Color(0xFF306230),
        'g' to Color(0xFF8BAC0F), 'y' to Color(0xFF8BAC0F), 'c' to Color(0xFF9BBC0F),
    )
    UiStyle.SIXTEEN -> mapOf(
        'k' to Color(0xFF181028), 'w' to Color.White, 'b' to Color(0xFF4060E0), 'r' to Color(0xFFF04050),
        'g' to Color(0xFFB0B0C8), 'y' to Color(0xFFFFD040), 'c' to Color(0xFF60E8F8),
    )
    else -> mapOf(
        'k' to Color.Black, 'w' to Color.White, 'b' to Color(0xFF0000A8), 'r' to Color(0xFFE00000),
        'g' to Color(0xFFC0C0C0), 'y' to Color(0xFFFFD800), 'c' to Color(0xFF00FFFF),
    )
}

/** True when the menu should use pixel icons instead of the regular ones. */
val usePixelIcons: Boolean get() = Palette.Style in setOf(UiStyle.RETRO, UiStyle.POCKET, UiStyle.SIXTEEN)

@Composable
fun PixelIcon(name: String, size: Dp = 22.dp, modifier: Modifier = Modifier) {
    val s = ICONS[name] ?: return
    val colors = iconColors()
    Canvas(modifier.size(size)) { s.draw(this, Offset.Zero, this.size.width / s.w, colors) }
}

// ---- Sprites for the console scenes (original, generic characters) ----

/** A little adventurer in a cap; two walking frames. */
private val HERO = listOf(
    sprite("...kkkk.", "..kcccck", ".kcccccck", ".kksssk.", ".ksksksk", ".kssssk.", "..kksk..", ".kcccck.", "kscccsk.", "kscccsk.", ".kpppk..", ".kp.pk..", "kk...kk."),
    sprite("...kkkk.", "..kcccck", ".kcccccck", ".kksssk.", ".ksksksk", ".kssssk.", "..kksk..", ".kcccck.", "kscccsk.", "kscccsk.", ".kpppk..", "..kpk...", "..kkk..."),
)
private val SLIME = sprite("...kkkk...", "..kggggk..", ".kgwggggk.", "kgwwggkgk.", "kggggggggk", "kgkggggkgk", ".kkkkkkkk.")
private val COIN = listOf(
    sprite(".kkk.", "kyyyk", "kywyk", "kyyyk", "kywyk", "kyyyk", ".kkk."),
    sprite(".k.", "kyk", "kwk", "kyk", "kwk", "kyk", ".k."),
)
private val STAR_BLOCK = sprite("kkkkkkkkkk", "kyyyyyyyyk", "kyyykyyyyk", "kyykwkyyyk", "kykwwwkyyk", "kyykwkyyyk", "kyyykyyyyk", "kyyyyyyyyk", "kkkkkkkkkk")
private val CLOUD = sprite("....wwww......", "..wwwwwwww.ww.", ".wwwwwwwwwwwww", "wwwwwwwwwwwwww", ".wwwwwwwwwwww.")

/** Handheld LCD: a pale green screen, dot grid, drifting clouds, a walking hero, a slime, coins and falling blocks. */
@Composable
fun PocketBackdrop(modifier: Modifier = Modifier) {
    val clock = sceneClock(8)
    val c0 = Color(0xFF0F380F); val c1 = Color(0xFF306230); val c2 = Color(0xFF8BAC0F); val c3 = Color(0xFF9BBC0F)
    val pal = mapOf('k' to c0, 'c' to c1, 's' to c2, 'p' to c1, 'g' to c2, 'w' to c3, 'y' to c2)
    val cloudPal = mapOf('w' to c2)
    Canvas(modifier.fillMaxSize()) {
        val t = clock.floatValue
        val px = 3.dp.toPx()
        drawRect(c3)
        // LCD dot grid.
        var gx = 0f
        while (gx < size.width) { drawLine(c2.copy(alpha = 0.35f), Offset(gx, 0f), Offset(gx, size.height), 1f); gx += px * 2 }
        repeat(3) { i ->
            val x = ((t * 10f * (i + 1) + i * 300f) % (size.width + 200f)) - 100f
            CLOUD.draw(this, Offset(x, size.height * (0.08f + i * 0.1f)), px, cloudPal)
        }
        // The ground is its own strip below ([PocketFloor]); characters stand on its top edge.
        val groundY = size.height
        // Hero walks across; slime bounces; coins spin.
        val heroX = ((t * 30f) % (size.width + 100f)) - 50f
        HERO[(t * 4).toInt() % 2].draw(this, Offset(heroX, groundY - HERO[0].h * px), px, pal)
        val slimeX = size.width * 0.7f
        val hop = abs(sin(t * 3f)) * px * 10
        SLIME.draw(this, Offset(slimeX, groundY - SLIME.h * px - hop), px, pal)
        repeat(5) { i ->
            COIN[((t * 3).toInt() + i) % 2].draw(this, Offset(size.width * (0.25f + i * 0.08f), groundY - px * 18), px, pal)
        }
        // Falling blocks down the right edge.
        val well = size.width - px * 30
        repeat(3) { i ->
            val y = ((t * 40f + i * 220f) % (size.height + 100f)) - 50f
            val shape = listOf(listOf(0 to 0, 1 to 0, 2 to 0, 1 to 1), listOf(0 to 0, 1 to 0, 0 to 1, 1 to 1), listOf(0 to 0, 0 to 1, 0 to 2, 1 to 2))[i]
            shape.forEach { (cx, cy) ->
                val o = Offset(well + i * px * 8 + cx * px * 4, y + cy * px * 4)
                drawRect(c0, o, Size(px * 4, px * 4)); drawRect(c2, o + Offset(px, px), Size(px * 2, px * 2))
            }
        }
    }
}

/** 16-bit side-scroller: banded sky, parallax hills, star blocks, spinning coins and a running hero. */
@Composable
fun SixteenBackdrop(modifier: Modifier = Modifier) {
    val clock = sceneClock(15)
    val pal = mapOf(
        'k' to Color(0xFF181028), 'c' to Color(0xFFE04040), 's' to Color(0xFFFFC890), 'p' to Color(0xFF3050C8),
        'g' to Color(0xFF50D060), 'w' to Color.White, 'y' to Color(0xFFFFD040),
    )
    Canvas(modifier.fillMaxSize()) {
        val t = clock.floatValue
        val px = 4.dp.toPx()
        // Sky in flat bands, like a 16-bit gradient.
        val bands = listOf(0xFF2848B8, 0xFF3860D0, 0xFF4878E0, 0xFF6090E8, 0xFF80A8F0, 0xFFA0C0F8).map { Color(it.toInt()) }
        val bh = size.height * 0.7f / bands.size
        bands.forEachIndexed { i, c -> drawRect(c, Offset(0f, i * bh), Size(size.width, bh + 1f)) }
        repeat(4) { i ->
            val x = ((t * (8f + i * 4f) + i * 380f) % (size.width + 300f)) - 150f
            CLOUD.draw(this, Offset(x, size.height * (0.06f + i * 0.08f)), px, mapOf('w' to Color.White))
        }
        // Far hills, then near hills (they scroll at different speeds).
        fun hills(color: Color, base: Float, amp: Float, speed: Float, period: Float) {
            val shift = (t * speed) % period
            var x = -period
            while (x < size.width + period) {
                val cx = x - shift
                drawOval(color, Offset(cx, base - amp), Size(period, amp * 2))
                x += period * 0.8f
            }
            drawRect(color, Offset(0f, base), Size(size.width, size.height - base))
        }
        hills(Color(0xFF3A9A80), size.height * 0.62f, size.height * 0.12f, 6f, size.width * 0.35f)
        hills(Color(0xFF48B848), size.height * 0.74f, size.height * 0.07f, 16f, size.width * 0.22f)
        // The ground is its own strip below ([SixteenFloor]); characters stand on its top edge.
        val groundY = size.height
        // Floating star blocks and coins.
        repeat(4) { i ->
            val x = size.width * (0.3f + i * 0.13f)
            STAR_BLOCK.draw(this, Offset(x, size.height * 0.48f), px, pal)
            COIN[((t * 6).toInt() + i) % 2].draw(this, Offset(x + px * 2, size.height * 0.4f + sin(t * 3f + i) * px * 2), px, pal)
        }
        // The hero runs and hops now and then; a slime patrols.
        val heroX = ((t * 70f) % (size.width + 120f)) - 60f
        val jump = ((t % 3f) / 0.6f).let { if (it < 1f) sin(it * Math.PI.toFloat()) * px * 18 else 0f }
        HERO[(t * 8).toInt() % 2].draw(this, Offset(heroX, groundY - HERO[0].h * px - jump), px, pal)
        val slimeX = size.width * 0.15f + sin(t * 0.8f) * size.width * 0.08f
        SLIME.draw(this, Offset(slimeX, groundY - SLIME.h * px), px, pal, flip = kotlin.math.cos(t * 0.8f) < 0)
    }
}

/** The 16-bit menu cursor: a little white glove pointing right. */
private val GLOVE = sprite("..kkk.....", ".kwwwkkkk.", "kwwwwwwwwk", "kwwwwkkkk.", "kwwwwwk...", ".kwwwwk...", "..kkkk....")

/** Handheld menus point with a ▶ arrow. */
private val ARROW = sprite("k...", "kk..", "kkk.", "kkkk", "kkk.", "kk..", "k...")

/** Draws the console themes' menu pointer just left of a focused element. */
fun DrawScope.drawConsolePointer() {
    val px = 2.dp.toPx()
    when (Palette.Style) {
        UiStyle.SIXTEEN -> GLOVE.draw(this, Offset(-GLOVE.w * px - 2f, size.height / 2 - GLOVE.h * px / 2), px, mapOf('k' to Color(0xFF181028), 'w' to Color.White))
        UiStyle.POCKET -> ARROW.draw(this, Offset(-ARROW.w * px - 4f, size.height / 2 - ARROW.h * px / 2), px, mapOf('k' to Color(0xFF0F380F)))
        else -> {}
    }
}

/** 16-bit RPG window: a blue gradient box with a white frame. */
val SixteenWindowBrush = Brush.verticalGradient(listOf(Color(0xFF3858D8), Color(0xFF182890), Color(0xFF101870)))

/** The handheld's brick floor, a strip along the bottom of the screen above everything. */
@Composable
fun PocketFloor(modifier: Modifier = Modifier) = Canvas(modifier) {
    val px = 3.dp.toPx()
    drawRect(Color(0xFF306230))
    var bx = 0f
    while (bx < size.width) {
        drawRect(Color(0xFF0F380F), Offset(bx, 0f), Size(px, size.height))
        drawRect(Color(0xFF0F380F), Offset(bx, px * 8), Size(px * 8, px))
        bx += px * 8
    }
    drawRect(Color(0xFF0F380F), Offset.Zero, Size(size.width, px))
}

/** The 16-bit grass-on-dirt floor, scrolling with the run, above everything. */
@Composable
fun SixteenFloor(modifier: Modifier = Modifier) {
    val clock = sceneClock(15)
    Canvas(modifier) {
        val px = 4.dp.toPx()
        drawRect(Color(0xFFC07838))
        drawRect(Color(0xFF50D060), Offset.Zero, Size(size.width, px * 3))
        drawRect(Color(0xFF2E9A3C), Offset(0f, px * 3), Size(size.width, px))
        var bx = -(clock.floatValue * 40f) % (px * 12)
        while (bx < size.width) {
            drawRect(Color(0xFF8A5020), Offset(bx, px * 4), Size(px, size.height)); bx += px * 12
        }
        drawRect(Color(0xFF8A5020), Offset(0f, px * 10), Size(size.width, px))
    }
}

/** Height of a style's bottom strip (taskbar or floor); the app's pages and menu end above it. */
fun floorHeight(): androidx.compose.ui.unit.Dp = when (Palette.Style) {
    UiStyle.RETRO -> 34.dp
    UiStyle.POCKET -> 30.dp
    UiStyle.SIXTEEN -> 40.dp
    else -> 0.dp
}

/** Draws the current style's bottom strip. */
@Composable
fun StyleFloor(modifier: Modifier = Modifier) = when (Palette.Style) {
    UiStyle.RETRO -> RetroTaskbar(Palette.colors.variant, modifier)
    UiStyle.POCKET -> PocketFloor(modifier)
    UiStyle.SIXTEEN -> SixteenFloor(modifier)
    else -> {}
}
