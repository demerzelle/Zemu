package com.zemu.tv.ui.downloads

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.tv.material3.MaterialTheme
import androidx.tv.material3.Text
import com.zemu.tv.container
import com.zemu.tv.data.posterUrl
import com.zemu.tv.data.title
import com.zemu.tv.player.Playback
import com.zemu.tv.ui.components.RemoteImage
import com.zemu.tv.ui.components.TvButton
import com.zemu.tv.ui.theme.Palette
import com.zemu.tv.ui.theme.glassPanel

/** Titles saved for offline playback: progress while downloading, then Play; Delete frees the space. */
@Composable
fun DownloadsScreen() {
    val c = LocalContext.current.container
    val context = LocalContext.current
    val items by c.downloads.items.collectAsStateWithLifecycle()
    // Re-reads each download's progress every second.
    var tick by remember { mutableIntStateOf(0) }
    LaunchedEffect(Unit) { while (true) { kotlinx.coroutines.delay(1000); tick++ } }
    Column(Modifier.fillMaxSize().padding(start = 48.dp, top = 32.dp, end = 48.dp)) {
        Text("Downloads", style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Black)
        Text(
            if (!c.downloads.available) "This device has no storage for downloads."
            else if (items.isEmpty()) "Nothing downloaded yet. On a title page, hold OK on a stream and pick \"Download for offline\"."
            else "Saved on this device, so they play without internet.",
            color = Palette.TextSecondary, fontSize = 14.sp, modifier = Modifier.padding(top = 4.dp, bottom = 12.dp),
        )
        LazyColumn(verticalArrangement = Arrangement.spacedBy(10.dp), contentPadding = PaddingValues(bottom = 80.dp)) {
            items(items, key = { it.id }) { item ->
                val st = remember(tick, item.id) { c.downloads.state(item) }
                Row(
                    Modifier.fillMaxWidth().glassPanel(com.zemu.tv.ui.theme.boxy(RoundedCornerShape(12.dp))).padding(12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(16.dp),
                ) {
                    RemoteImage(item.meta.posterUrl(), Modifier.width(60.dp).height(90.dp).clip(com.zemu.tv.ui.theme.boxy(RoundedCornerShape(6.dp))))
                    Column(Modifier.weight(1f)) {
                        Text(listOfNotNull(item.meta.title, item.label).joinToString(" · "), fontSize = 17.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
                        Text(
                            when {
                                st.done -> "Ready · %.1f GB".format(st.bytes / 1e9)
                                st.failed -> "Download failed"
                                else -> "Downloading… %d%%  (%.1f GB)".format((st.progress * 100).toInt(), st.bytes / 1e9)
                            },
                            color = if (st.failed) Palette.Cached else Palette.TextSecondary, fontSize = 14.sp,
                        )
                    }
                    if (st.done) TvButton("Play", primary = true, onClick = { Playback.playDownload(context, item) })
                    TvButton(if (st.done || st.failed) "Delete" else "Cancel", onClick = { c.downloads.remove(item) })
                }
            }
        }
    }
}
