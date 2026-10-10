package com.zemu.tv.ui.addons

import com.zemu.tv.ui.theme.glassPanel
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import kotlinx.coroutines.delay
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.tv.material3.MaterialTheme
import androidx.tv.material3.Text
import com.zemu.tv.container
import com.zemu.tv.ui.components.CenteredMessage
import com.zemu.tv.ui.components.ConfirmDialog
import com.zemu.tv.ui.components.RemoteImage
import com.zemu.tv.ui.components.Tag
import com.zemu.tv.ui.components.TvButton
import com.zemu.tv.ui.components.TvChip
import com.zemu.tv.ui.components.TvTextField
import com.zemu.tv.ui.settings.ConfigureActivity
import com.zemu.tv.ui.theme.Palette

@Composable
fun AddonBrowserScreen() {
    val context = LocalContext.current
    val c = context.container
    val vm: AddonBrowserViewModel = viewModel { AddonBrowserViewModel(c) }
    val ui by vm.state.collectAsStateWithLifecycle()
    var url by remember { mutableStateOf("") }
    var confirm by remember { mutableStateOf<Pair<AddonItem, String>?>(null) }

    val topFocus = remember { FocusRequester() }
    DisposableEffect(Unit) {
        vm.startServer()
        onDispose { vm.stopServer() }
    }
    LaunchedEffect(Unit) {
        delay(120)
        runCatching { topFocus.requestFocus() }
    }

    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(top = 32.dp, bottom = 60.dp)) {
        item {
            Column(Modifier.padding(horizontal = 48.dp)) {
                Text("Addons", style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Black)
                Text(
                    "Install, remove and configure Stremio addons. Configure opens the addon's own setup page; its Install button installs here automatically.",
                    color = Palette.TextSecondary, fontSize = 14.sp, modifier = Modifier.padding(top = 6.dp),
                )
            }
            LazyRow(contentPadding = PaddingValues(horizontal = 48.dp, vertical = 14.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                items(ui.tabs, key = { it.first }) { (key, label) ->
                    TvChip(
                        label,
                        selected = ui.tab == key,
                        onClick = { vm.selectTab(key) },
                        modifier = if (key == INSTALLED) Modifier.focusRequester(topFocus) else Modifier,
                    )
                }
            }
            Row(Modifier.padding(horizontal = 48.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                TypeFilter.entries.forEach { t -> TvChip(t.label, selected = ui.type == t, onClick = { vm.setType(t) }) }
                TvTextField(ui.query, vm::setQuery, "Search addons", Modifier.weight(1f))
            }
            Row(Modifier.padding(horizontal = 48.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                TvTextField(url, { url = it }, "Install from URL (https://…/manifest.json)", Modifier.weight(1f), onSubmit = { if (url.isNotBlank()) vm.installUrl(url) })
                TvButton("Install", primary = true, onClick = { if (url.isNotBlank()) vm.installUrl(url) })
            }
            ui.remoteAddress?.let {
                Text(
                    "Or open  $it  on a phone on the same Wi-Fi and paste the URL there.",
                    color = Palette.Info, fontSize = 13.sp, modifier = Modifier.padding(horizontal = 48.dp),
                )
            }
            ui.message?.let { Text(it, color = Palette.Cached, fontSize = 14.sp, modifier = Modifier.padding(horizontal = 48.dp, vertical = 6.dp)) }
            Spacer(Modifier.size(8.dp))
        }
        when {
            ui.loading -> item { Text("Loading addons…", color = Palette.TextSecondary, modifier = Modifier.padding(horizontal = 48.dp, vertical = 16.dp)) }
            ui.error != null -> item { CenteredMessage("Couldn't load this catalog", ui.error, action = { TvButton("Retry", onClick = vm::retry) }) }
            ui.items.isEmpty() -> item { Text("No addons match.", color = Palette.TextSecondary, modifier = Modifier.padding(horizontal = 48.dp, vertical = 16.dp)) }
            else -> items(ui.items, key = { it.manifest.id + it.transportUrl }) { item ->
                AddonCard(
                    item = item,
                    busy = item.manifest.id in ui.busy,
                    onInstall = { vm.install(item) },
                    onUninstall = { vm.uninstallWarning(item)?.let { w -> confirm = item to w } ?: vm.uninstall(item) },
                    onConfigure = { ConfigureActivity.start(context, item.configureUrl, item.manifest.name) },
                )
            }
        }
    }
    confirm?.let { (item, warning) ->
        ConfirmDialog(
            title = "Remove ${item.manifest.name}?",
            message = warning,
            confirmLabel = "Remove anyway",
            onConfirm = { vm.uninstall(item); confirm = null },
            onDismiss = { confirm = null },
        )
    }
}

@Composable
private fun AddonCard(item: AddonItem, busy: Boolean, onInstall: () -> Unit, onUninstall: () -> Unit, onConfigure: () -> Unit) {
    val m = item.manifest
    Row(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 48.dp, vertical = 6.dp)
            .glassPanel(RoundedCornerShape(12.dp))
            .padding(14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.size(64.dp).clip(RoundedCornerShape(10.dp)).background(Palette.SurfaceHigh), contentAlignment = Alignment.Center) {
            Text(m.name.take(1).uppercase(), fontWeight = FontWeight.Black, fontSize = 26.sp, color = Palette.TextMuted)
            RemoteImage(m.logo, Modifier.fillMaxSize(), contentScale = ContentScale.Fit)
        }
        Spacer(Modifier.width(16.dp))
        Column(Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(m.name, fontWeight = FontWeight.Bold, fontSize = 17.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text("  v${m.version}", color = Palette.TextMuted, fontSize = 13.sp)
            }
            m.description?.takeIf { it.isNotBlank() }?.let {
                Text(it, color = Palette.TextSecondary, fontSize = 13.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
            }
            Row(Modifier.padding(top = 6.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                if (item.installed) Tag("INSTALLED", Palette.Match, filled = true)
                m.types.take(4).forEach { Tag(it.uppercase(), Palette.TextSecondary) }
                m.resources.map { it.name }.distinct().filter { it in setOf("stream", "subtitles") }.forEach { Tag(it.uppercase(), Palette.Info) }
                if (m.configurationRequired) Tag("SETUP REQUIRED", Palette.Cached) else if (m.configurable) Tag("CONFIGURABLE", Palette.Cached)
            }
        }
        Spacer(Modifier.width(12.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
            when {
                item.required -> Text("Required", color = Palette.TextMuted, fontSize = 14.sp)
                // One button whose label flips, so focus stays on it after installing/uninstalling.
                item.installed || !m.configurationRequired -> TvButton(
                    text = when {
                        busy -> "Working…"
                        item.installed -> "Uninstall"
                        else -> "Install"
                    },
                    primary = !item.installed,
                    onClick = { if (!busy) { if (item.installed) onUninstall() else onInstall() } },
                )
            }
            if (item.canConfigure) TvButton(if (m.configurationRequired && !item.installed) "Configure & install" else "Configure", onClick = onConfigure)
        }
    }
}
