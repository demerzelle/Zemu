package com.zemu.tv.ui.home

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.foundation.hoverable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsHoveredAsState
import com.zemu.tv.ui.theme.Palette
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.zIndex
import androidx.tv.material3.Text
import com.zemu.tv.AppContainer
import com.zemu.tv.data.Meta
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow

/**
 * "Top 10 Today" rows. Movies and series: TMDB's trending today, or without a TMDB key Cinemeta's
 * popular list. Anime: Kitsu's trending anime. Home gets movies and series, each page its own kind.
 */
object Top10 {
    private val kinds = mapOf("home" to listOf("movie", "series"), "movie" to listOf("movie"), "series" to listOf("series"), "anime" to listOf("anime"))
    private val titles = mapOf("movie" to "Movies", "series" to "Series", "anime" to "Anime")

    private suspend fun load(c: AppContainer, kind: String): List<Meta> = when {
        kind == "anime" -> c.client.catalog("https://anime-kitsu.strem.fun", "anime", "kitsu-anime-trending")
        c.tmdb.enabled -> c.tmdb.trendingToday(kind)
        else -> c.client.catalog("https://v3-cinemeta.strem.io", kind, "top")
    }

    fun rows(c: AppContainer, page: String): Flow<List<HomeRow>> = flow {
        emit(emptyList())
        emit(kinds[page].orEmpty().mapNotNull { kind ->
            val items = runCatching { load(c, kind) }.onFailure { System.err.println("Zemu: Top 10 $kind: ${it.message}") }.getOrDefault(emptyList())
            items.take(10).takeIf { it.isNotEmpty() }?.let { HomeRow("top10-$kind", "Top 10 ${titles[kind]} Today", it, priority = 0) }
        })
    }
}

/**
 * A poster with its rank, big, above its top-left corner and just overlapping it; in the accent
 * color while the poster is highlighted. Ranked posters sit a little further apart to make room.
 * No rank: just the poster.
 */
@Composable
fun Ranked(rank: Int?, poster: @Composable () -> Unit) {
    if (rank == null) return poster()
    var focused by remember { mutableStateOf(false) }
    val hover = remember { MutableInteractionSource() }
    val hovered by hover.collectIsHoveredAsState()
    Box(
        Modifier
            .padding(start = 10.dp, end = 6.dp)
            .onFocusChanged { focused = it.hasFocus }
            .hoverable(hover),
    ) {
        Box(Modifier.padding(top = 46.dp)) { poster() }
        Text(
            "$rank",
            modifier = Modifier.align(Alignment.TopStart).offset(x = (-8).dp).zIndex(1f),
            style = TextStyle(
                color = if (focused || hovered) Palette.Accent else Color.White,
                fontSize = 60.sp, lineHeight = 60.sp, fontWeight = FontWeight.Black,
                shadow = Shadow(Color.Black.copy(alpha = 0.85f), Offset(0f, 3f), blurRadius = 10f),
            ),
        )
    }
}
