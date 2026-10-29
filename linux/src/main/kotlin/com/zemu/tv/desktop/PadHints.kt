package com.zemu.tv.desktop

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.tv.material3.Text
import com.zemu.tv.desktop.Gamepad.Button

/** Which controller button triggers each control in the player's menu bar. */
private val playerButtons = mapOf(
    "play" to Button.A,
    "back10" to Button.LB,
    "fwd10" to Button.RB,
    "next" to Button.MENU,
    "audio" to Button.Y,
    "subs" to Button.X,
)

/** The controller button for a player control, drawn under it; nothing when no controller is connected. */
@Composable
fun PadHint(controlKey: String) {
    if (!Gamepad.connected) return
    val b = playerButtons[controlKey] ?: return
    PadGlyph(b, Modifier.padding(top = 3.dp))
}

/** The track panel hint, mentioning the controller only while one is connected. */
fun trackPanelHint(): String =
    if (Gamepad.connected) "Right-click, hold Enter or hold the A button on Audio or Subtitles to see every track, subtitle position and style"
    else "Right-click or hold Enter on Audio or Subtitles to see every track, subtitle position and style"

/**
 * An Xbox-style button: face buttons are dark discs with the letter in its color (A green, B red,
 * X blue, Y yellow); bumpers are rounded tabs; View and Menu are small discs with their symbol.
 */
@Composable
fun PadGlyph(b: Button, modifier: Modifier = Modifier, size: Dp = 16.dp) {
    val dark = Color(0xFF26262B)
    when (b) {
        Button.A, Button.B, Button.X, Button.Y -> {
            val color = when (b) {
                Button.A -> Color(0xFF6CC24A)
                Button.B -> Color(0xFFE5484D)
                Button.X -> Color(0xFF3B8EEA)
                else -> Color(0xFFF2C230)
            }
            Box(modifier.size(size).background(dark, CircleShape).border(1.dp, color.copy(alpha = 0.7f), CircleShape), contentAlignment = Alignment.Center) {
                Text(b.name, color = color, fontSize = (size.value * 0.62f).sp, fontWeight = FontWeight.Black, lineHeight = (size.value * 0.7f).sp)
            }
        }
        Button.LB, Button.RB -> Box(
            modifier.height(size).width(size * 1.7f).background(dark, RoundedCornerShape(topStart = size / 2, topEnd = size / 2, bottomStart = 3.dp, bottomEnd = 3.dp))
                .border(1.dp, Color.White.copy(alpha = 0.35f), RoundedCornerShape(topStart = size / 2, topEnd = size / 2, bottomStart = 3.dp, bottomEnd = 3.dp)),
            contentAlignment = Alignment.Center,
        ) {
            Text(b.name, color = Color.White, fontSize = (size.value * 0.5f).sp, fontWeight = FontWeight.Bold, lineHeight = (size.value * 0.6f).sp)
        }
        Button.MENU -> Box(modifier.size(size).background(dark, CircleShape).border(1.dp, Color.White.copy(alpha = 0.35f), CircleShape), contentAlignment = Alignment.Center) {
            Column(Modifier.width(size * 0.45f)) {
                repeat(3) { i ->
                    Box(Modifier.padding(top = if (i == 0) 0.dp else (size.value * 0.08f).dp).height((size.value * 0.08f).dp.coerceAtLeast(1.dp)).width(size * 0.45f).background(Color.White))
                }
            }
        }
        else -> {}
    }
}
