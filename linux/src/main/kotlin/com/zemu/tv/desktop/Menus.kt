package com.zemu.tv.desktop

import android.widget.Toast
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.tv.material3.Icon
import com.zemu.tv.ZemuApp
import com.zemu.tv.data.Meta
import com.zemu.tv.data.Video
import com.zemu.tv.data.WatchEntry
import com.zemu.tv.data.slim
import com.zemu.tv.ui.components.ActionSheet
import com.zemu.tv.ui.components.FocusSurface
import com.zemu.tv.ui.components.SheetAction
import kotlinx.coroutines.launch

/** "Download" in a movie or show card's menu (right-click, or hold A / Enter on the card). */
object CardDownload {
    fun enabled(): Boolean = ZemuApp.container.let { it.downloads.available && it.userStore.settings.value.downloads }

    fun start(m: Meta) {
        if (m.type != "series") {
            DownloadPrompt.request = DownloadPrompt.Request.Episodes(m, "Download", listOf(Video(id = m.id, name = m.name)))
            return
        }
        // Cards carry no episode list; load the show first.
        val c = ZemuApp.container
        c.appScope.launch {
            val full = runCatching { c.addons.meta("series", m.id) }.getOrNull()
            if (full == null || full.videos.isEmpty()) Toast.makeText(null, "Couldn't load the episodes of ${m.name.orEmpty()}", Toast.LENGTH_LONG).show()
            else DownloadPrompt.allSeasons(full)
        }
    }
}

/** An episode's own menu: right-click it, or hold A / Enter on it. */
object EpisodeMenu {
    class Open(val meta: Meta, val video: Video, val play: () -> Unit, val pick: () -> Unit)

    var current by mutableStateOf<Open?>(null)

    fun open(meta: Meta, video: Video, play: () -> Unit, pick: () -> Unit) {
        current = Open(meta, video, play, pick)
    }
}

@Composable
fun EpisodeMenuDialog() {
    val o = EpisodeMenu.current ?: return
    val c = ZemuApp.container
    val v = o.video
    val label = DownloadPrompt.label(v)
    val downloads = c.downloads.available && c.userStore.settings.value.downloads
    ActionSheet(
        title = "${o.meta.name.orEmpty()} · $label",
        onDismiss = { EpisodeMenu.current = null },
        actions = buildList {
            add(SheetAction("Play") { o.play() })
            add(SheetAction("Choose a stream") { o.pick() })
            // Zemu remembers one place per show: marking an episode moves Continue Watching past it.
            add(SheetAction("Mark as watched", "Continue from the next one") {
                c.appScope.launch { c.userStore.recordProgress(WatchEntry(o.meta.slim(), v.id, label, 1, 1, System.currentTimeMillis())) }
                Toast.makeText(null, "Marked $label as watched", Toast.LENGTH_SHORT).show()
            })
            if (downloads) {
                add(SheetAction("Download episode") {
                    DownloadPrompt.request = DownloadPrompt.Request.Episodes(o.meta, "Download episode", listOf(v))
                })
                v.season?.let { s -> add(SheetAction(if (s == 0) "Download the specials" else "Download season $s") { DownloadPrompt.season(o.meta, s) }) }
            }
        },
    )
}

/** Pages with the side menu; every other page gets a Back button instead. Mirrors AppShell's showRail. */
private fun hasRail(route: String) =
    !route.startsWith("details") && !route.startsWith("person") && !route.startsWith("browse") && !route.startsWith("services") && !route.startsWith("rows/")

/** Top-left Back button on pages without the side menu (title pages, people, browse lists). */
@Composable
fun BoxScope.BackButton() {
    val nav = DesktopNav.controller ?: return
    val entry by nav.currentBackStackEntryAsState()
    val route = entry?.destination?.route ?: return
    if (hasRail(route) || nav.previousBackStackEntry == null) return
    FocusSurface(
        onClick = { nav.popBackStack() },
        modifier = Modifier.align(Alignment.TopStart).padding(16.dp).size(44.dp),
        shape = CircleShape,
        containerColor = Color.Black.copy(alpha = 0.55f),
        contentColor = Color.White,
        focusedScale = 1.1f,
    ) {
        Box(Modifier.size(44.dp), contentAlignment = Alignment.Center) {
            Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back", modifier = Modifier.size(24.dp))
        }
    }
}
