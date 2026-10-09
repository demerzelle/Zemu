package com.zemu.tv.ui.profiles

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.tv.material3.Text
import coil.compose.AsyncImage
import coil.request.ImageRequest
import java.io.File

/** Premade avatars: a gradient tile with an emoji. */
object AvatarPresets {
    data class Preset(val emoji: String, val from: Long, val to: Long)

    val all = listOf(
        Preset("😎", 0xFFE50914, 0xFF7F0A12), Preset("🦊", 0xFFF97316, 0xFF9A3412), Preset("🐼", 0xFF64748B, 0xFF1E293B),
        Preset("🐯", 0xFFF59E0B, 0xFFB45309), Preset("🐸", 0xFF22C55E, 0xFF15803D), Preset("🐙", 0xFFEC4899, 0xFF9D174D),
        Preset("🦄", 0xFFA855F7, 0xFF6B21A8), Preset("🐶", 0xFFD97706, 0xFF78350F), Preset("🐱", 0xFF06B6D4, 0xFF0E7490),
        Preset("👾", 0xFF6366F1, 0xFF3730A3), Preset("🤖", 0xFF94A3B8, 0xFF334155), Preset("👻", 0xFF8B5CF6, 0xFF4C1D95),
        Preset("🎮", 0xFF10B981, 0xFF065F46), Preset("🍿", 0xFFEF4444, 0xFF991B1B), Preset("🚀", 0xFF3B82F6, 0xFF1E3A8A),
        Preset("⚡", 0xFFEAB308, 0xFF854D0E), Preset("🌸", 0xFFF472B6, 0xFFBE185D), Preset("🧙", 0xFF7C3AED, 0xFF2E1065),
    )
}

@Composable
fun Avatar(avatar: String, size: Dp, modifier: Modifier = Modifier, corner: Dp = size / 6) {
    val shape = RoundedCornerShape(corner)
    if (avatar.startsWith("file:")) {
        val path = avatar.removePrefix("file:").substringBefore('?')
        AsyncImage(
            model = ImageRequest.Builder(LocalContext.current).data(File(path)).memoryCacheKey(avatar).diskCacheKey(avatar).build(),
            contentDescription = null,
            contentScale = ContentScale.Crop,
            modifier = modifier.size(size).clip(shape).background(Color.DarkGray),
        )
        return
    }
    val idx = avatar.removePrefix("preset:").toIntOrNull()?.coerceIn(0, AvatarPresets.all.lastIndex) ?: 0
    val p = AvatarPresets.all[idx]
    Box(
        modifier.size(size).clip(shape).background(Brush.linearGradient(listOf(Color(p.from.toInt()), Color(p.to.toInt())))),
        contentAlignment = Alignment.Center,
    ) {
        Text(p.emoji, fontSize = (size.value * 0.48f).sp)
    }
}
