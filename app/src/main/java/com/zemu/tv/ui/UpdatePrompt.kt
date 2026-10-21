package com.zemu.tv.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.tv.material3.Text
import com.zemu.tv.app
import com.zemu.tv.ui.components.TvButton
import com.zemu.tv.ui.theme.Palette
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * Checks GitHub Releases once per launch and offers a newer version. "Later" hides that version for
 * three days; Settings → Device → Check for updates shows it again right away.
 */
@Composable
fun UpdatePrompt() {
    val context = LocalContext.current
    val updater = context.app.updater
    val update by updater.available.collectAsStateWithLifecycle()
    val forced by updater.showNow.collectAsStateWithLifecycle()
    val progress by updater.progress.collectAsStateWithLifecycle()
    val prefs = remember { context.getSharedPreferences("updates", 0) }
    var hidden by remember { mutableStateOf<String?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    LaunchedEffect(Unit) { runCatching { updater.check() } }

    val u = update ?: return
    val snoozed = System.currentTimeMillis() < prefs.getLong("snooze_${u.version}", 0)
    if (!forced && (hidden == u.version || snoozed)) return
    val close = { hidden = u.version; updater.showNow.value = false }
    val first = remember { FocusRequester() }
    Dialog(onDismissRequest = close, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Column(
            Modifier
                .width(560.dp)
                .background(Palette.Surface, com.zemu.tv.ui.theme.boxy(RoundedCornerShape(16.dp)))
                .padding(28.dp),
        ) {
            Text("Zemu ${u.version} is available", fontSize = 26.sp, fontWeight = FontWeight.Black)
            Text("You have ${updater.currentVersion}.", color = Palette.TextSecondary, fontSize = 15.sp, modifier = Modifier.padding(top = 4.dp))
            val notes = u.notes.lines().map { it.trim() }.filter { it.isNotEmpty() && !it.startsWith("#") }.take(6).joinToString("\n")
            if (notes.isNotEmpty()) Text(notes, color = Palette.TextSecondary, fontSize = 14.sp, maxLines = 6, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(top = 14.dp))
            error?.let { Text(it, color = Palette.Accent, fontSize = 14.sp, modifier = Modifier.padding(top = 12.dp)) }
            Column(Modifier.padding(top = 20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                val p = progress
                TvButton(
                    if (p != null) "Downloading… ${(p * 100).toInt()}%" else "Update now",
                    primary = true,
                    modifier = Modifier.fillMaxWidth().focusRequester(first),
                    onClick = {
                        if (p != null) return@TvButton
                        error = null
                        scope.launch {
                            runCatching { updater.install(u) }
                                .onSuccess { ok -> if (!ok) error = "Allow Zemu to install apps on the screen that opened, then press Update now again." }
                                .onFailure { error = it.message ?: "The download failed. Try again." }
                        }
                    },
                )
                TvButton("Later", modifier = Modifier.fillMaxWidth(), onClick = {
                    prefs.edit().putLong("snooze_${u.version}", System.currentTimeMillis() + 3 * 24 * 3600_000L).apply()
                    close()
                })
            }
        }
    }
    LaunchedEffect(Unit) {
        delay(80)
        runCatching { first.requestFocus() }
    }
}
