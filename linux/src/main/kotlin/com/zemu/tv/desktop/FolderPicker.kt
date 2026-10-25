package com.zemu.tv.desktop

import android.widget.Toast
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.tv.material3.Text
import com.zemu.tv.ui.components.FocusSurface
import com.zemu.tv.ui.components.TvButton
import com.zemu.tv.ui.components.TvChip
import com.zemu.tv.ui.theme.Palette
import com.zemu.tv.ui.theme.glassPanel
import java.io.File

/** Shortcut places: home, the videos and downloads folders, and mounted drives (USB sticks, disks). */
private fun places(): List<Pair<String, File>> {
    val home = File(System.getProperty("user.home"))
    fun xdg(name: String) = runCatching {
        val p = ProcessBuilder("xdg-user-dir", name).redirectErrorStream(true).start()
        p.inputStream.bufferedReader().readText().trim().also { p.waitFor() }
    }.getOrNull()?.takeIf { it.isNotBlank() && it != home.path }?.let(::File)
    val user = System.getProperty("user.name")
    val drives = listOf(File("/media/$user"), File("/run/media/$user"), File("/media"), File("/mnt"))
        .flatMap { it.listFiles { f -> f.isDirectory && !f.name.startsWith(".") && f.name != user }?.toList().orEmpty() }
        .distinctBy { it.canonicalPath }
    return listOfNotNull("Home" to home, xdg("VIDEOS")?.let { "Videos" to it }, xdg("DOWNLOAD")?.let { "Downloads" to it }) +
        drives.map { "Drive: ${it.name}" to it }
}

/**
 * A folder browser that works with arrows and a controller: shortcut places on top, the folders
 * inside the current one below (".." goes up), and "Use this folder" picks it.
 */
@Composable
fun FolderPicker(start: File, onPick: (File) -> Unit, onCancel: () -> Unit) {
    var dir by remember { mutableStateOf(generateSequence(start) { it.parentFile }.firstOrNull { it.isDirectory } ?: File(System.getProperty("user.home"))) }
    val places = remember { places() }
    val subdirs = remember(dir) {
        dir.listFiles { f -> f.isDirectory && !f.name.startsWith(".") }?.sortedBy { it.name.lowercase() }.orEmpty()
    }
    val first = remember { FocusRequester() }
    val list = rememberLazyListState()
    LaunchedEffect(dir) { list.scrollToItem(0) }
    LaunchedEffect(Unit) { kotlinx.coroutines.delay(80); runCatching { first.requestFocus() } }
    val context = androidx.compose.ui.platform.LocalContext.current
    Column(Modifier.width(720.dp).glassPanel(com.zemu.tv.ui.theme.boxy(RoundedCornerShape(16.dp))).padding(24.dp)) {
        Text("Choose a download folder", fontSize = 22.sp, fontWeight = FontWeight.Bold)
        Text(dir.path, color = Palette.TextSecondary, fontSize = 14.sp, maxLines = 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(top = 4.dp, bottom = 12.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            TvButton("Use this folder", primary = true, modifier = Modifier.focusRequester(first), onClick = {
                if (dir.canWrite()) onPick(dir) else Toast.makeText(context, "Zemu can't write to ${dir.path}. Pick another folder.", Toast.LENGTH_LONG).show()
            })
            TvButton("Cancel", onClick = onCancel)
        }
        LazyRow(Modifier.padding(top = 14.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            items(places) { (label, f) -> TvChip(label, selected = f == dir, onClick = { dir = f }) }
        }
        LazyColumn(Modifier.padding(top = 12.dp).height(320.dp), state = list, verticalArrangement = Arrangement.spacedBy(4.dp)) {
            dir.parentFile?.let { up -> item(key = "..") { FolderRow("⬑  Up to ${up.name.ifBlank { "/" }}") { dir = up } } }
            items(subdirs, key = { it.path }) { f -> FolderRow("📁  ${f.name}") { dir = f } }
            if (subdirs.isEmpty()) item { Text("No folders in here.", color = Palette.TextMuted, fontSize = 14.sp, modifier = Modifier.padding(8.dp)) }
        }
    }
}

@Composable
private fun FolderRow(label: String, onClick: () -> Unit) {
    FocusSurface(onClick = onClick, modifier = Modifier.fillMaxWidth(), focusedScale = 1.01f) {
        Text(label, fontSize = 16.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(horizontal = 14.dp, vertical = 9.dp))
    }
}
