package com.zemu.tv.ui.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.tv.material3.Text
import com.zemu.tv.container
import com.zemu.tv.ui.components.AppIcons
import com.zemu.tv.ui.components.ChoiceDialog
import com.zemu.tv.ui.components.ChoiceOption
import com.zemu.tv.ui.components.TvButton
import com.zemu.tv.ui.components.TvIconButton
import com.zemu.tv.ui.home.HomeViewModel
import com.zemu.tv.ui.theme.Palette
import com.zemu.tv.ui.theme.glassPanel
import kotlinx.coroutines.delay

/**
 * Settings → Manage rows for one page ("home", "movie", "series", "anime"): every row in order,
 * with pin, move, remove/restore, and adding rows of your own (a service, a studio, a genre, any
 * addon catalog).
 */
@Composable
fun RowsManagerScreen(page: String) {
    val c = LocalContext.current.container
    val vm: HomeViewModel = viewModel(key = "rows-manage-$page") { HomeViewModel(c, page) }
    val (rows, prefs) = vm.manageRows.collectAsStateWithLifecycle().value
    var adding by remember { mutableStateOf(false) }
    val first = remember { FocusRequester() }
    LaunchedEffect(Unit) { delay(150); runCatching { first.requestFocus() } }
    val noun = when (page) { "movie" -> "Movies"; "series" -> "Series"; "anime" -> "Anime"; else -> "Home" }
    Column(Modifier.fillMaxSize().padding(start = 48.dp, end = 48.dp, top = 32.dp)) {
        Text("$noun rows", fontSize = 26.sp, fontWeight = FontWeight.Black)
        Text("Pin rows to the top, move them, remove the ones you don't want, or add your own. On the page itself, press Up from a row to its name and OK for the same controls.",
            color = Palette.TextSecondary, fontSize = 14.sp, modifier = Modifier.padding(top = 4.dp, bottom = 12.dp))
        TvButton("＋  Add a row", onClick = { adding = true }, modifier = Modifier.focusRequester(first))
        LazyColumn(contentPadding = PaddingValues(top = 12.dp, bottom = 80.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            if (rows.isEmpty()) item { Text("Loading rows…", color = Palette.TextSecondary) }
            items(rows, key = { it.key }) { row ->
                val hidden = row.key in prefs.hidden
                val pinned = row.key in prefs.favorites
                Row(
                    Modifier.fillMaxWidth().glassPanel(com.zemu.tv.ui.theme.boxy(RoundedCornerShape(12.dp))).padding(horizontal = 16.dp, vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    Column(Modifier.weight(1f)) {
                        Text(row.title, fontSize = 16.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis,
                            color = if (hidden) Palette.TextMuted else Palette.Text)
                        Text(
                            listOfNotNull("Pinned".takeIf { pinned }, "Removed".takeIf { hidden }, "Added by you".takeIf { prefs.added.any { it.key == row.key } }, "${row.items.size} titles").joinToString(" · "),
                            color = Palette.TextMuted, fontSize = 12.sp,
                        )
                    }
                    if (!hidden) {
                        TvIconButton(if (pinned) AppIcons.Heart else AppIcons.HeartOutline, if (pinned) "Unpin" else "Pin to top", active = pinned) { vm.toggleFavoriteRow(row.key) }
                        TvIconButton(AppIcons.ArrowUp, "Move up") { vm.moveRow(row.key, -1) }
                        TvIconButton(AppIcons.ArrowDown, "Move down") { vm.moveRow(row.key, 1) }
                        TvIconButton(AppIcons.Close, "Remove") { vm.hideRow(row.key) }
                    } else TvButton("Restore", onClick = { vm.showRow(row.key) })
                }
            }
        }
    }
    if (adding) {
        val options = remember { vm.addableRows() }
        ChoiceDialog(
            title = "Add a row",
            options = options.map { ChoiceOption(it.key, it.title) },
            selected = prefs.added.map { it.key }.toSet(),
            multiSelect = false,
            onToggle = { k -> options.firstOrNull { it.key == k }?.let(vm::addRow) },
            onDismiss = { adding = false },
        )
    }
}
