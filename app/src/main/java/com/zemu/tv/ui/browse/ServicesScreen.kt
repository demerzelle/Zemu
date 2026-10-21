package com.zemu.tv.ui.browse

import com.zemu.tv.ui.components.ZemuLoader

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
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
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.tv.material3.Text
import com.zemu.tv.container
import com.zemu.tv.data.DiscoverParams
import com.zemu.tv.data.Meta
import com.zemu.tv.data.Provider
import com.zemu.tv.ui.components.CenteredMessage
import com.zemu.tv.ui.components.ServiceCard
import com.zemu.tv.ui.home.BrowseTarget
import com.zemu.tv.ui.theme.Palette
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * Every streaming service available in your region, logos filling the tiles. OK opens what's on
 * it; holding OK marks it as one you subscribe to (those come first everywhere).
 */
@Composable
fun ServicesScreen(type: String, onBrowse: (BrowseTarget) -> Unit) {
    val c = LocalContext.current.container
    val settings by c.userStore.settings.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()
    var all by remember { mutableStateOf<List<Provider>?>(null) }
    val first = remember { FocusRequester() }
    LaunchedEffect(Unit) { all = runCatching { c.tmdb.allProviders(DiscoverParams.region) }.getOrDefault(emptyList()) }
    val list = all
    Column(Modifier.fillMaxSize().padding(top = 32.dp)) {
        Text("All Streaming Services", fontSize = 26.sp, fontWeight = FontWeight.Black, modifier = Modifier.padding(horizontal = 48.dp))
        Text(
            "OK opens a service. Hold OK to mark the ones you subscribe to; they come first and get their own rows.",
            color = Palette.TextSecondary, fontSize = 14.sp, modifier = Modifier.padding(horizontal = 48.dp, vertical = 6.dp),
        )
        when {
            list == null -> ZemuLoader()
            list.isEmpty() -> CenteredMessage("Couldn't load streaming services", "Check the TMDB key in Settings → Addons.")
            else -> {
                val mine = settings.myServices
                val sorted = list.sortedByDescending { it.ids in mine }
                LazyVerticalGrid(
                    columns = GridCells.Adaptive(176.dp),
                    contentPadding = PaddingValues(start = 48.dp, end = 48.dp, top = 12.dp, bottom = 60.dp),
                    horizontalArrangement = Arrangement.spacedBy(16.dp),
                    verticalArrangement = Arrangement.spacedBy(16.dp),
                ) {
                    items(sorted, key = { it.ids }) { p ->
                        ServiceCard(
                            Meta(id = "service:${p.ids}", name = p.label, poster = p.logo),
                            modifier = if (p == sorted.first()) Modifier.focusRequester(first) else Modifier,
                            selected = p.ids in mine,
                            onLongClick = {
                                scope.launch {
                                    c.userStore.updateSettings { s ->
                                        s.copy(myServices = if (p.ids in s.myServices) s.myServices - p.ids else s.myServices + (p.ids to p.label))
                                    }
                                }
                            },
                        ) { onBrowse(BrowseTarget(type, p.ids, p.label)) }
                    }
                }
                LaunchedEffect(Unit) { delay(100); runCatching { first.requestFocus() } }
            }
        }
    }
}
