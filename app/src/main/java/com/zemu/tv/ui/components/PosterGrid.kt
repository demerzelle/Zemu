package com.zemu.tv.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.layout.padding
import com.zemu.tv.data.Meta

@Composable
fun PosterGrid(
    items: List<Meta>,
    onOpen: (Meta) -> Unit,
    modifier: Modifier = Modifier,
    columns: Int = 6,
    onNearEnd: () -> Unit = {},
    badge: (Meta) -> String? = { null },
    onFocused: (index: Int, meta: Meta) -> Unit = { _, _ -> },
    contentPadding: PaddingValues = PaddingValues(start = 48.dp, end = 48.dp, top = 16.dp, bottom = 48.dp),
    /** Full-width content above the grid that scrolls with it (e.g. a "New Episodes" row). */
    header: (@Composable () -> Unit)? = null,
    state: androidx.compose.foundation.lazy.grid.LazyGridState = rememberLazyGridState(),
) {
    val shown = com.zemu.tv.ui.kids.kidsSafe(items) { it }
    val nearEnd by remember {
        derivedStateOf {
            val last = state.layoutInfo.visibleItemsInfo.lastOrNull()?.index ?: 0
            last >= state.layoutInfo.totalItemsCount - columns * 2
        }
    }
    LaunchedEffect(nearEnd, shown.size) { if (nearEnd) onNearEnd() }

    LazyVerticalGrid(
        columns = GridCells.Fixed(columns),
        state = state,
        modifier = modifier,
        contentPadding = contentPadding,
        horizontalArrangement = Arrangement.spacedBy(18.dp),
        verticalArrangement = Arrangement.spacedBy(22.dp),
    ) {
        if (header != null) item(key = "grid-header", span = { androidx.compose.foundation.lazy.grid.GridItemSpan(maxLineSpan) }) { header() }
        itemsIndexed(shown, key = { _, m -> m.id }) { i, m ->
            PosterCard(m, onClick = { onOpen(m) }, width = androidx.compose.ui.unit.Dp.Unspecified, badge = badge(m), onFocused = { onFocused(i, it) })
        }
    }
}

/** A grid of posters with titled sections that scroll as one (My List, Search's saved titles). */
@Composable
fun SectionedPosterGrid(
    sections: List<Pair<String?, List<Meta>>>,
    onOpen: (Meta) -> Unit,
    modifier: Modifier = Modifier,
    contentPadding: PaddingValues = PaddingValues(start = 48.dp, end = 48.dp, top = 16.dp, bottom = 48.dp),
) {
    LazyVerticalGrid(
        columns = GridCells.Fixed(6),
        modifier = modifier,
        contentPadding = contentPadding,
        horizontalArrangement = Arrangement.spacedBy(18.dp),
        verticalArrangement = Arrangement.spacedBy(22.dp),
    ) {
        sections.forEachIndexed { s, (title, items) ->
            if (items.isEmpty()) return@forEachIndexed
            if (title != null) item(key = "title-$s", span = { androidx.compose.foundation.lazy.grid.GridItemSpan(maxLineSpan) }) {
                androidx.tv.material3.Text(title, fontSize = 20.sp, fontWeight = androidx.compose.ui.text.font.FontWeight.Bold, modifier = Modifier.padding(top = if (s == 0) 0.dp else 14.dp))
            }
            items(items.size, key = { "$s-${items[it].id}" }) { i ->
                PosterCard(items[i], onClick = { onOpen(items[i]) }, width = androidx.compose.ui.unit.Dp.Unspecified)
            }
        }
    }
}
