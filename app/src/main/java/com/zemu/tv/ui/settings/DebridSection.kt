package com.zemu.tv.ui.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.tv.material3.Text
import com.zemu.tv.AppContainer
import com.zemu.tv.data.DebridAccount
import com.zemu.tv.data.DebridService
import com.zemu.tv.data.DeviceLogin
import com.zemu.tv.ui.components.QrCode
import com.zemu.tv.ui.components.TvButton
import com.zemu.tv.ui.components.TvChip
import com.zemu.tv.ui.components.TvTextField
import com.zemu.tv.ui.theme.Palette
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** Link a debrid account by approving a code on the service's site, or by pasting its API key. */
@Composable
fun DebridSection(c: AppContainer, phoneAddress: String?) {
    val account by c.userStore.debrid.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()
    var linking by remember { mutableStateOf<DebridService?>(null) }
    var status by remember { mutableStateOf<String?>(null) }

    val a = account
    Text(
        if (a != null) "Linked to ${a.service.label}. Torrentio is set up with this account, so cached streams show up on every title. Pick another service to switch."
        else "Link your debrid account and Zemu sets up a stream addon with it. Pick your service, then scan the code with your phone or enter it on the website.",
        color = Palette.TextSecondary, fontSize = 14.sp, modifier = Modifier.padding(vertical = 8.dp),
    )
    LazyRow(contentPadding = PaddingValues(vertical = 6.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        items(DebridService.entries.toList(), key = { it.name }) { s ->
            TvChip(s.label, selected = a?.service == s, onClick = { linking = s })
        }
        if (a != null) item {
            TvButton("Unlink ${a.service.label}", onClick = { scope.launch { c.unlinkDebrid(); status = "${a.service.label} unlinked." } })
        }
    }
    status?.let { Text(it, color = Palette.Cached, fontSize = 14.sp, modifier = Modifier.padding(top = 8.dp)) }

    linking?.let { s ->
        LinkDialog(c, s, phoneAddress, onDismiss = { linking = null }) { msg ->
            status = msg
            linking = null
        }
    }
}

@Composable
private fun LinkDialog(c: AppContainer, service: DebridService, phoneAddress: String?, onDismiss: () -> Unit, onLinked: (String) -> Unit) {
    val scope = rememberCoroutineScope()
    var login by remember { mutableStateOf<DeviceLogin?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var key by remember { mutableStateOf("") }
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    val first = remember { FocusRequester() }
    var codeLinked by remember { mutableStateOf(false) }
    val before = remember { c.userStore.debrid.value }
    val account by c.userStore.debrid.collectAsStateWithLifecycle()

    // A key pasted on the phone page links the account in the background; close when it lands.
    LaunchedEffect(account) {
        val a = account
        if (a != null && a != before && a.service == service && !codeLinked) onLinked("${service.label} linked. Torrentio is set up with your account.")
    }

    if (service.codeLogin) {
        LaunchedEffect(service) {
            while (true) {
                val l = runCatching { c.debridAuth.start(service) }.onFailure { error = it.message }.getOrNull() ?: return@LaunchedEffect
                login = l
                error = null
                while (System.currentTimeMillis() < l.expiresAt) {
                    delay(l.intervalMs)
                    val linked: DebridAccount? = runCatching { l.check() }.onFailure { error = it.message }.getOrNull()
                    if (linked != null) {
                        codeLinked = true
                        onLinked(c.linkDebrid(linked))
                        return@LaunchedEffect
                    }
                }
                // Code expired: get a fresh one.
            }
        }
        LaunchedEffect(Unit) { while (true) { delay(1000); now = System.currentTimeMillis() } }
    }
    LaunchedEffect(Unit) { delay(150); runCatching { first.requestFocus() } }

    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Column(Modifier.width(900.dp).background(Palette.Surface, RoundedCornerShape(16.dp)).padding(28.dp)) {
            Text("Link ${service.label}", fontSize = 24.sp, fontWeight = FontWeight.Black)
            Spacer(Modifier.height(16.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(28.dp)) {
                if (service.codeLogin) {
                    val l = login
                    Column(Modifier.width(400.dp)) {
                        if (l != null) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                QrCode(l.directUrl, 170.dp)
                                Spacer(Modifier.width(18.dp))
                                Column {
                                    Text("Scan with your phone", fontWeight = FontWeight.Bold, fontSize = 16.sp)
                                    Text("or go to", color = Palette.TextSecondary, fontSize = 14.sp, modifier = Modifier.padding(top = 6.dp))
                                    Text(l.url.removePrefix("https://"), fontSize = 16.sp, fontWeight = FontWeight.Bold)
                                    Text("and enter", color = Palette.TextSecondary, fontSize = 14.sp, modifier = Modifier.padding(top = 6.dp))
                                    Text(l.userCode, fontSize = 30.sp, fontWeight = FontWeight.Black, color = Palette.Accent, letterSpacing = 3.sp)
                                }
                            }
                            val left = ((l.expiresAt - now) / 1000).coerceAtLeast(0)
                            Text(
                                "Waiting for approval… code refreshes in ${left / 60}:${"%02d".format(left % 60)}",
                                color = Palette.TextMuted, fontSize = 13.sp, modifier = Modifier.padding(top = 12.dp),
                            )
                        } else if (error == null) {
                            Text("Getting a code from ${service.label}…", color = Palette.TextSecondary)
                        }
                        error?.let { Text(it, color = Palette.Cached, fontSize = 14.sp, modifier = Modifier.padding(top = 10.dp)) }
                    }
                }
                Column(Modifier.weight(1f)) {
                    Text(if (service.codeLogin) "Or use your API key" else "Paste your API key", fontWeight = FontWeight.Bold, fontSize = 16.sp)
                    Text("Copy it from ${service.keyPage}.", color = Palette.TextSecondary, fontSize = 14.sp, modifier = Modifier.padding(vertical = 6.dp))
                    if (phoneAddress != null) {
                        val url = "$phoneAddress/?kind=debrid.${service.name}"
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            QrCode(url, 130.dp)
                            Spacer(Modifier.width(14.dp))
                            Text(
                                "Scan to paste it from your phone (same Wi-Fi), or open $url",
                                color = Palette.TextSecondary, fontSize = 13.sp,
                            )
                        }
                    }
                    Row(Modifier.padding(top = 12.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        TvTextField(key, { key = it }, "${service.label} API key", Modifier.weight(1f))
                        TvButton("Save", onClick = {
                            scope.launch {
                                if (key.isBlank()) return@launch
                                if (c.debridAuth.verify(service, key)) onLinked(c.linkDebrid(DebridAccount(service, key.trim())))
                                else error = "${service.label} didn't accept that key. Copy it from ${service.keyPage}."
                            }
                        })
                    }
                    if (!service.codeLogin) error?.let { Text(it, color = Palette.Cached, fontSize = 14.sp, modifier = Modifier.padding(top = 10.dp)) }
                }
            }
            Spacer(Modifier.height(18.dp))
            TvButton("Cancel", onClick = onDismiss, modifier = Modifier.focusRequester(first))
        }
    }
}
