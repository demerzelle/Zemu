package com.zemu.tv.ui.settings

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Star
import androidx.compose.ui.graphics.vector.ImageVector
import com.zemu.tv.ui.components.AppIcons
import com.zemu.tv.ui.theme.retroScrollbar
import androidx.compose.foundation.background
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.Box
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.height
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
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import com.zemu.tv.app
import com.zemu.tv.ui.components.TvChip
import com.zemu.tv.ui.profiles.ProfilesSection
import com.zemu.tv.ui.theme.DynamicTheme
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.runtime.LaunchedEffect
import com.zemu.tv.ui.theme.glassPanel
import kotlinx.coroutines.delay
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.tv.material3.MaterialTheme
import androidx.tv.material3.Text
import com.zemu.tv.AppContainer
import com.zemu.tv.container
import com.zemu.tv.data.Addon
import com.zemu.tv.data.AppSettings
import com.zemu.tv.streams.Languages
import com.zemu.tv.ui.components.ChoiceDialog
import com.zemu.tv.ui.components.SubtitleStyleEditor
import com.zemu.tv.ui.components.ChoiceOption
import com.zemu.tv.ui.components.FocusSurface
import com.zemu.tv.ui.components.SectionTitle
import com.zemu.tv.ui.components.TvButton
import com.zemu.tv.ui.components.TvTextField
import com.zemu.tv.ui.theme.Palette
import androidx.tv.material3.LocalContentColor
import com.zemu.tv.streams.DeviceCapabilities
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch

class SettingsViewModel(private val c: AppContainer, private val appRef: com.zemu.tv.ZemuApp) : ViewModel() {
    val container: AppContainer get() = c
    val addons = c.addons.addons
    val settings = c.userStore.settings
    val capabilities get() = c.capabilities
    val message = MutableStateFlow<String?>(null)
    val remoteAddress = MutableStateFlow<String?>(null)
    private val server = RemoteInputServer(
        profiles = { appProfiles().profiles.value.map { it.id to it.name } },
        onAvatar = { id, bytes ->
            val store = appProfiles()
            val value = store.saveAvatarImage(id, bytes)
            val p = store.profiles.value.firstOrNull { it.id == id }
            if (value == null || p == null) "That file isn't an image Zemu can read."
            else { store.update(p.copy(avatar = value)); "Profile picture updated for ${p.name}" }
        },
    ) { text -> c.handleRemoteInput(text).also { message.value = it } }
    private fun appProfiles() = appRef.profiles

    fun startServer() { remoteAddress.value = server.start(viewModelScope) }
    fun stopServer() = server.stop()
    fun saveTmdbKey(key: String) = viewModelScope.launch { message.value = c.saveTmdbKey(key) }
    override fun onCleared() = server.stop()

    fun update(transform: (AppSettings) -> AppSettings) = viewModelScope.launch {
        val before = c.userStore.settings.value
        c.userStore.updateSettings(transform)
        val after = transform(before)
        if (before.trustDirectLinks != after.trustDirectLinks) c.streams.invalidate()
    }

    /** The look before the change waiting on "Keep changes?"; [lookChanges] restarts its countdown. */
    val pendingLook = MutableStateFlow<AppSettings?>(null)
    val lookChanges = MutableStateFlow(0)

    /** A theme change: applies now, then asks "Keep changes?" and reverts unless kept in time. */
    fun updateLook(transform: (AppSettings) -> AppSettings) {
        if (pendingLook.value == null) pendingLook.value = c.userStore.settings.value
        lookChanges.value++
        update(transform)
    }

    fun keepLook() { pendingLook.value = null }

    fun revertLook() {
        val b = pendingLook.value ?: return
        pendingLook.value = null
        update {
            it.copy(
                theme = b.theme, customAccent = b.customAccent, dynamicTheme = b.dynamicTheme, themeVariants = b.themeVariants,
                themeBeforeRave = b.themeBeforeRave, colorOverrides = b.colorOverrides, lightMode = b.lightMode, glassStyle = b.glassStyle,
            )
        }
    }

    fun clearHistory() = viewModelScope.launch {
        c.userStore.clearHistory()
        message.value = "Watch history cleared"
    }
}

private enum class SettingsDialog { AUDIO, SUBS, MAX_SIZE, COUNTDOWN, STILL_EPISODES }

/** The groups shown in Settings' left-hand list. */
private enum class SettingsCategory(val label: String, val blurb: String, val icon: ImageVector) {
    SEARCH("Search settings", "Type what you're looking for, then pick a result.", Icons.Filled.Search),
    QUICK("Quick setup", "The few things that matter most: your debrid account, the TMDB key, your streaming services and the look.", Icons.Filled.Star),
    ACCOUNTS("Accounts & addons", "Your debrid service, stream addons, metadata, streaming services, Trakt and the free keys that add cast, logos and critic scores.", AppIcons.Puzzle),
    PROFILES("Profiles & kids", "Who's watching, profile pictures, and parental controls for kid profiles.", Icons.Filled.Person),
    PLAYBACK("Playback", "How videos start and end, skipping intros, which streams are picked and the audio language.", AppIcons.Play),
    SUBTITLES("Subtitles", "Which subtitles are picked and how they look.", AppIcons.Subtitles),
    APPEARANCE("Appearance", "Light mode, themes, colors, size and text.", AppIcons.Palette),
    BROWSING("Browsing", "The rows on each page, trailers and search history.", Icons.Filled.Home),
    SOUND("Sounds & touch", "Sound effects and vibration.", AppIcons.Audio),
    SCREENSAVER("Screensaver", "A slideshow of titles picked for you when Zemu sits idle.", AppIcons.Sleep),
    DEVICE("Video & audio formats", "What this device can play, used to pick \"Best for this TV\" streams. Change anything that was detected wrong.", AppIcons.Tv),
    SYSTEM("Updates & storage", "Updates, downloads and watch history.", Icons.Filled.Settings),
}

@Composable
fun SettingsScreen(onOpenAddons: () -> Unit, onOpenServices: () -> Unit = {}, onManageRows: (String) -> Unit = {}) {
    val context = LocalContext.current
    val c = context.container
    val vm: SettingsViewModel = viewModel { SettingsViewModel(c, context.app) }
    val settings by vm.settings.collectAsStateWithLifecycle()
    val message by vm.message.collectAsStateWithLifecycle()
    var dialog by remember { mutableStateOf<SettingsDialog?>(null) }
    var category by rememberSaveable { mutableStateOf(SettingsCategory.QUICK) }
    val remote by vm.remoteAddress.collectAsStateWithLifecycle()
    DisposableEffect(Unit) {
        vm.startServer()
        onDispose { vm.stopServer() }
    }
    val topFocus = remember { FocusRequester() }
    LaunchedEffect(Unit) {
        delay(120)
        runCatching { topFocus.requestFocus() }
    }

    Row(Modifier.fillMaxSize().padding(start = 40.dp, top = 32.dp)) {
        // Left: categories. Moving focus over one shows it on the right, like Android TV's own settings.
        Column(Modifier.width(250.dp).fillMaxHeight().verticalScroll(rememberScrollState())) {
            Text("Settings", style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Black, modifier = Modifier.padding(start = 12.dp, bottom = 20.dp))
            SettingsCategory.entries.forEach { cat ->
                CategoryItem(
                    cat.label,
                    cat.icon,
                    selected = cat == category,
                    modifier = if (cat == SettingsCategory.QUICK) Modifier.focusRequester(topFocus) else Modifier,
                    onFocused = { category = cat },
                    onClick = { category = cat },
                )
            }
            Spacer(Modifier.size(40.dp))
        }
        Spacer(Modifier.width(28.dp))
        // Right: the chosen category.
        val listState = androidx.compose.foundation.lazy.rememberLazyListState()
        LazyColumn(
            Modifier.weight(1f).fillMaxHeight().retroScrollbar(listState),
            state = listState,
            contentPadding = PaddingValues(end = 48.dp, bottom = 120.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            item(key = "title-${category.name}") {
                Text(category.label, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 4.dp))
                Text(category.blurb, color = Palette.TextSecondary, fontSize = 14.sp, modifier = Modifier.padding(top = 4.dp, bottom = 8.dp))
                message?.let { Text(it, color = Palette.Cached, fontSize = 14.sp, modifier = Modifier.padding(bottom = 8.dp)) }
            }
            when (category) {
                SettingsCategory.SEARCH -> searchCategory { category = it }
                SettingsCategory.QUICK -> quickCategory(vm, settings, remote, onOpenServices)
                SettingsCategory.ACCOUNTS -> accountsCategory(vm, settings, remote, onOpenAddons, onOpenServices)
                SettingsCategory.PROFILES -> {
                    group("profiles", "Profiles") { ProfilesSection(remote) }
                    group("kids", "Kids") { KidsSection() }
                }
                SettingsCategory.PLAYBACK -> playbackCategory(vm, settings) { dialog = it }
                SettingsCategory.SUBTITLES -> subtitlesCategory(vm, settings) { dialog = it }
                SettingsCategory.APPEARANCE -> appearanceCategory(vm, settings)
                SettingsCategory.BROWSING -> browsingCategory(vm, settings, onManageRows)
                SettingsCategory.SOUND -> soundsCategory(vm, settings)
                SettingsCategory.SCREENSAVER -> screensaverCategory(vm, settings)
                SettingsCategory.DEVICE -> deviceCategory(vm, settings)
                SettingsCategory.SYSTEM -> systemCategory(vm, settings)
            }
        }
    }

    when (dialog) {
        SettingsDialog.AUDIO -> LanguageDialog("Preferred audio languages", settings.audioLanguages, onDismiss = { dialog = null }) { code ->
            vm.update { s -> s.copy(audioLanguages = s.audioLanguages.toggle(code)) }
        }
        SettingsDialog.SUBS -> LanguageDialog("Preferred subtitle languages", settings.subtitleLanguages, onDismiss = { dialog = null }) { code ->
            vm.update { s -> s.copy(subtitleLanguages = s.subtitleLanguages.toggle(code)) }
        }
        SettingsDialog.COUNTDOWN -> ChoiceDialog(
            title = "Next episode countdown",
            options = listOf(5, 10, 15, 20, 30).map { ChoiceOption(it.toString(), "$it seconds") },
            selected = setOf(settings.autoplayCountdownSec.toString()),
            multiSelect = false,
            onToggle = { v -> vm.update { it.copy(autoplayCountdownSec = v.toInt()) } },
            onDismiss = { dialog = null },
        )
        SettingsDialog.STILL_EPISODES -> ChoiceDialog(
            title = "Ask \"Are you still watching?\" after",
            options = listOf(2, 3, 4, 5, 6, 8).map { ChoiceOption(it.toString(), "$it episodes") },
            selected = setOf(settings.stillWatchingEpisodes.toString()),
            multiSelect = false,
            onToggle = { v -> vm.update { it.copy(stillWatchingEpisodes = v.toInt()) } },
            onDismiss = { dialog = null },
        )
        SettingsDialog.MAX_SIZE -> ChoiceDialog(
            title = "Maximum file size",
            options = listOf(0, 5, 10, 20, 40, 80).map { ChoiceOption(it.toString(), if (it == 0) "No limit" else "$it GB") },
            selected = setOf(settings.maxSizeGb.toString()),
            multiSelect = false,
            onToggle = { v -> vm.update { it.copy(maxSizeGb = v.toInt()) } },
            onDismiss = { dialog = null },
        )
        null -> {}
    }
    val pendingLook by vm.pendingLook.collectAsStateWithLifecycle()
    val lookChanges by vm.lookChanges.collectAsStateWithLifecycle()
    if (pendingLook != null) KeepChangesDialog(lookChanges, onKeep = vm::keepLook, onRevert = vm::revertLook)
}

@Composable
private fun CategoryItem(label: String, icon: ImageVector, selected: Boolean, modifier: Modifier, onFocused: () -> Unit, onClick: () -> Unit) {
    FocusSurface(
        onClick = onClick,
        modifier = modifier.fillMaxWidth().padding(vertical = 3.dp).onFocusChanged { if (it.isFocused) onFocused() },
        shape = com.zemu.tv.ui.theme.boxy(RoundedCornerShape(10.dp)),
        containerColor = if (selected) Palette.SurfaceHigh else Color.Transparent,
        contentColor = if (selected) Palette.Text else Palette.TextSecondary,
        focusedScale = 1.03f,
    ) {
        Row(Modifier.padding(horizontal = 12.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(width = 4.dp, height = 18.dp).background(if (selected) Palette.Accent else Color.Transparent, com.zemu.tv.ui.theme.boxy(RoundedCornerShape(2.dp))))
            Spacer(Modifier.width(10.dp))
            androidx.tv.material3.Icon(icon, contentDescription = null, tint = if (selected) Palette.Accent else Palette.TextSecondary, modifier = Modifier.size(20.dp))
            Spacer(Modifier.width(12.dp))
            Text(label, fontSize = 16.sp, fontWeight = if (selected) FontWeight.Bold else FontWeight.Medium, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}

/** A labelled group inside a category; [spaced] adds room above it. */
private fun LazyListScope.group(key: String, title: String, note: String? = null, content: @Composable () -> Unit) {
    item(key = key) {
        // A card per section, so each page reads as a few clear sections.
        val shape = com.zemu.tv.ui.theme.boxy(RoundedCornerShape(16.dp))
        Column(Modifier.fillMaxWidth().padding(top = 14.dp).background(Palette.Surface.copy(alpha = 0.35f), shape).padding(horizontal = 20.dp, vertical = 16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(width = 4.dp, height = 18.dp).background(Palette.Accent, com.zemu.tv.ui.theme.boxy(RoundedCornerShape(2.dp))))
                Spacer(Modifier.width(10.dp))
                Text(title, fontSize = 17.sp, fontWeight = FontWeight.Bold)
            }
            note?.let { Text(it, color = Palette.TextSecondary, fontSize = 13.sp, modifier = Modifier.padding(top = 4.dp, start = 14.dp)) }
            Spacer(Modifier.size(10.dp))
            content()
        }
    }
}

/** Where each setting lives, for Search settings. */
private val SETTINGS_INDEX: List<Pair<String, SettingsCategory>> = listOf(
    "Debrid account (Real-Debrid, AllDebrid, Premiumize, TorBox)" to SettingsCategory.ACCOUNTS,
    "Manage addons" to SettingsCategory.ACCOUNTS,
    "Metadata provider" to SettingsCategory.ACCOUNTS,
    "TMDB key (cast, studios, streaming services)" to SettingsCategory.ACCOUNTS,
    "OMDb key (Rotten Tomatoes, Metacritic scores)" to SettingsCategory.ACCOUNTS,
    "Trakt (watchlist, history, scrobbling)" to SettingsCategory.ACCOUNTS,
    "My streaming services" to SettingsCategory.ACCOUNTS,
    "Profiles and profile pictures" to SettingsCategory.PROFILES,
    "Kid profiles, parental controls, allowed ratings, parent code" to SettingsCategory.PROFILES,
    "Instant play" to SettingsCategory.PLAYBACK,
    "Autoplay next episode" to SettingsCategory.PLAYBACK,
    "Play something similar" to SettingsCategory.PLAYBACK,
    "Countdown" to SettingsCategory.PLAYBACK,
    "Are you still watching?" to SettingsCategory.PLAYBACK,
    "Check for updates" to SettingsCategory.SYSTEM,
    "Share search history across profiles" to SettingsCategory.BROWSING,
    "External player (VLC, Just Player)" to SettingsCategory.PLAYBACK,
    "Clear watch history" to SettingsCategory.SYSTEM,
    "Treat direct links as cached" to SettingsCategory.PLAYBACK,
    "Maximum file size" to SettingsCategory.PLAYBACK,
    "Preferred audio language" to SettingsCategory.PLAYBACK,
    "Preferred subtitle language" to SettingsCategory.SUBTITLES,
    "Turn on subtitles automatically" to SettingsCategory.SUBTITLES,
    "Prefer SDH subtitles (deaf / hard of hearing)" to SettingsCategory.SUBTITLES,
    "Original subtitle style / custom style on or off" to SettingsCategory.SUBTITLES,
    "Subtitle size, color, background, outline, position" to SettingsCategory.SUBTITLES,
    "Skip intro button" to SettingsCategory.PLAYBACK,
    "Light mode / dark mode" to SettingsCategory.APPEARANCE,
    "Glass style" to SettingsCategory.APPEARANCE,
    "Color theme" to SettingsCategory.APPEARANCE,
    "Animated themes (PS2, Acidwave, Cyberpunk, Halloween …)" to SettingsCategory.APPEARANCE,
    "Customize colors (background, buttons, text, accent)" to SettingsCategory.APPEARANCE,
    "Hide watched titles in rows" to SettingsCategory.BROWSING,
    "Manage rows (pin, move, remove, add categories)" to SettingsCategory.BROWSING,
    "Weather, Holidays, Cybercore, Graffiti, Liquid Glass themes" to SettingsCategory.APPEARANCE,
    "Screensaver" to SettingsCategory.SCREENSAVER,
    "Vibration" to SettingsCategory.SOUND,
    "Sound effects (clicks, blips)" to SettingsCategory.SOUND,
    "Trailers (autoplay, sound)" to SettingsCategory.BROWSING,
    "UI zoom (poster, text and icon size)" to SettingsCategory.APPEARANCE,
    "Title artwork, logo artwork (plain text titles)" to SettingsCategory.APPEARANCE,
    "Turn off trailers completely" to SettingsCategory.BROWSING,
    "Font, text size" to SettingsCategory.APPEARANCE,
    "Saved palettes, palette editor" to SettingsCategory.APPEARANCE,
    "Mouse pointer color, size and position (Cybercore)" to SettingsCategory.APPEARANCE,
    "Downloads (offline playback)" to SettingsCategory.SYSTEM,
    "4K, HDR10, Dolby Vision, Atmos, DTS support" to SettingsCategory.DEVICE,
    "Reset to recommended settings for my TV" to SettingsCategory.DEVICE,
    "Play Dolby Vision as HDR10" to SettingsCategory.DEVICE,
    "Software video decoders" to SettingsCategory.DEVICE,
)

private fun LazyListScope.searchCategory(open: (SettingsCategory) -> Unit) {
    item(key = "settings-search") {
        var q by rememberSaveable { mutableStateOf("") }
        TvTextField(q, { q = it }, "Search settings", Modifier.fillMaxWidth().padding(vertical = 6.dp))
        val words = q.trim().lowercase().split(' ').filter { it.isNotEmpty() }
        val hits = if (words.isEmpty()) emptyList() else SETTINGS_INDEX.filter { (t, c) -> words.all { w -> t.lowercase().contains(w) || c.label.lowercase().contains(w) } }
        Column(Modifier.padding(top = 8.dp)) {
            if (words.isNotEmpty() && hits.isEmpty()) Text("No settings match \"$q\".", color = Palette.TextSecondary, fontSize = 14.sp)
            hits.forEach { (title, cat) -> ValueRow(title, cat.label) { open(cat) } }
        }
    }
}

/** The essentials in one place, for a first run. */
private fun LazyListScope.quickCategory(vm: SettingsViewModel, settings: AppSettings, remote: String?, onOpenServices: () -> Unit) {
    group("q-debrid", "1 · Debrid account", "Needed to play anything: link Real-Debrid, AllDebrid, Premiumize or TorBox.") {
        DebridSection(vm.container, remote)
    }
    group("q-tmdb", "2 · TMDB key", "Free from themoviedb.org → Settings → API. Turns on streaming services, studios, cast photos and logos." + (remote?.let { " Or paste it from your phone at $it." } ?: "")) {
        var key by remember { mutableStateOf("") }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            TvTextField(key, { key = it }, if (settings.tmdbApiKey.isBlank()) "TMDB API key" else "Key saved (••••${settings.tmdbApiKey.takeLast(4)})", Modifier.weight(1f), onSubmit = { vm.saveTmdbKey(key); key = "" })
            TvButton("Save", onClick = { vm.saveTmdbKey(key); key = "" })
        }
    }
    group("q-services", "3 · Your streaming services") {
        ValueRow("My streaming services", settings.myServices.values.joinToString().ifEmpty { "Pick the ones you subscribe to" }) { onOpenServices() }
    }
    group("q-look", "4 · Look") {
        ToggleRow("Light mode", "Light backgrounds with dark text.", settings.lightMode) { vm.updateLook { it.copy(lightMode = !it.lightMode) } }
        ThemePicker(settings) { t -> vm.updateLook(t) }
    }
}

private fun LazyListScope.accountsCategory(vm: SettingsViewModel, settings: AppSettings, remote: String?, onOpenAddons: () -> Unit, onOpenServices: () -> Unit) {
    group("debrid", "Debrid account") {
        DebridSection(vm.container, remote)
    }
    group("addons", "Stream addons", "Zemu uses Stremio addons. Install a debrid-enabled one (AIOStreams, Torrentio, Comet, MediaFusion, …). Only cached streams are shown.") {
        val addons by vm.addons.collectAsStateWithLifecycle()
        val streamAddons = addons.count { it.manifest.hasResource("stream") }
        ValueRow("Manage addons", "${addons.size} installed · $streamAddons with streams") { onOpenAddons() }
    }
    group("meta", "Metadata provider") {
        val addons by vm.addons.collectAsStateWithLifecycle()
        val providers = addons.filter { a -> a.manifest.hasResource("meta") || a.manifest.catalogs.any { it.type in setOf("movie", "series") } }
        Text(
            if (providers.isEmpty()) "No metadata provider installed: catalogs and title details won't load. Install Cinemeta or another metadata addon."
            else "Used first for title details and the Movies and Series pages. Others fill in when it has nothing.",
            color = if (providers.isEmpty()) Palette.Cached else Palette.TextSecondary, fontSize = 13.sp,
        )
        LazyRow(contentPadding = PaddingValues(vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            item { TvChip("Automatic", selected = settings.metaProvider.isEmpty() || providers.none { it.manifest.id == settings.metaProvider }, onClick = { vm.update { it.copy(metaProvider = "") } }) }
            items(providers, key = { it.manifest.id }) { a ->
                TvChip(a.manifest.name, selected = settings.metaProvider == a.manifest.id, onClick = { vm.update { it.copy(metaProvider = a.manifest.id) } })
            }
        }
    }
    group("services", "My streaming services", "The services you subscribe to come first on Home, Movies and Series and get their own rows.") {
        ValueRow("My streaming services", settings.myServices.values.joinToString().ifEmpty { "None picked: showing the popular ones" }) { onOpenServices() }
    }
    group(
        "trakt", "Trakt",
        "Syncs your Trakt watchlist with My List (both ways), brings in movies you've watched, and scrobbles what you play. Make a free API app at trakt.tv/oauth/applications (redirect URI: urn:ietf:wg:oauth:2.0:oob), then enter its Client ID and Client Secret here.",
    ) { TraktSection(vm, settings) }
    group(
        "tmdb", "Cast & studio info (TMDB)",
        "A free TMDB API key adds cast photos, studios and each actor's other titles: themoviedb.org → Settings → API." +
            (remote?.let { " Or paste it from your phone at $it." } ?: ""),
    ) {
        var tmdbKey by remember { mutableStateOf("") }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            TvTextField(tmdbKey, { tmdbKey = it }, if (settings.tmdbApiKey.isBlank()) "TMDB API key" else "Key saved (••••${settings.tmdbApiKey.takeLast(4)})", Modifier.weight(1f), onSubmit = { vm.saveTmdbKey(tmdbKey); tmdbKey = "" })
            TvButton("Save", primary = true, onClick = { vm.saveTmdbKey(tmdbKey); tmdbKey = "" })
            if (settings.tmdbApiKey.isNotBlank()) TvButton("Remove", onClick = { vm.saveTmdbKey("") })
        }
    }
    group(
        "omdb", "Critic scores (OMDb)",
        "A free OMDb key adds Rotten Tomatoes and Metacritic scores, and US ratings for shows too: omdbapi.com → API Key (free, 1,000 lookups a day).",
    ) {
        var omdbKey by remember { mutableStateOf("") }
        val save = { vm.update { it.copy(omdbApiKey = omdbKey.trim()) }; omdbKey = "" }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            TvTextField(omdbKey, { omdbKey = it }, if (settings.omdbApiKey.isBlank()) "OMDb API key" else "Key saved (••••${settings.omdbApiKey.takeLast(4)})", Modifier.weight(1f), onSubmit = save)
            TvButton("Save", primary = true, onClick = save)
            if (settings.omdbApiKey.isNotBlank()) TvButton("Remove", onClick = { vm.update { it.copy(omdbApiKey = "") } })
        }
    }
}

private fun LazyListScope.playbackCategory(vm: SettingsViewModel, settings: AppSettings, openDialog: (SettingsDialog) -> Unit) {
    group("instant", "Starting playback") {
        ToggleRow(
            "Instant play",
            "Selecting a movie, a show or an episode starts it right away with the best cached stream (the one you used last time when it's still cached). Shows resume where you left off.",
            settings.instantPlay,
        ) { vm.update { it.copy(instantPlay = !it.instantPlay) } }
    }
    group("autoplay", "When something ends") {
        ToggleRow("Autoplay next episode", "Near the end of an episode, count down and start the next one.", settings.autoplayNext) {
            vm.update { it.copy(autoplayNext = !it.autoplayNext) }
        }
        ToggleRow("Play something similar after a series", "After a series finale, count down to a recommended show. Movies never autoplay: when the credits start, Zemu goes back to Home.", settings.autoplaySimilar) {
            vm.update { it.copy(autoplaySimilar = !it.autoplaySimilar) }
        }
        if (settings.autoplayNext || settings.autoplaySimilar) {
            ValueRow("Countdown", "${settings.autoplayCountdownSec} seconds") { openDialog(SettingsDialog.COUNTDOWN) }
        }
        if (settings.autoplayNext) {
            ToggleRow("Ask \"Are you still watching?\"", "Pause and check in after several episodes play without touching the remote.", settings.stillWatchingPrompt) {
                vm.update { it.copy(stillWatchingPrompt = !it.stillWatchingPrompt) }
            }
            if (settings.stillWatchingPrompt) {
                ValueRow("Ask after", "${settings.stillWatchingEpisodes} episodes in a row") { openDialog(SettingsDialog.STILL_EPISODES) }
            }
        }
    }
    group("skip", "Skipping") {
        ToggleRow("Skip intro button", "Show \"Skip intro\" / \"Skip recap\" while they play (community timestamps from TheIntroDB and AniSkip). The next-episode card starts at the credits.", settings.skipIntroButton) {
            vm.update { it.copy(skipIntroButton = !it.skipIntroButton) }
        }
    }
    group("cached", "Cached streams", "Catalogs show every title. When you open one, only streams cached on your debrid service are listed.") {
        ToggleRow(
            "Treat direct links as cached",
            "Count plain HTTP streams without debrid markers as instantly playable. Leave off for strict debrid-cached only.",
            settings.trustDirectLinks,
        ) { vm.update { it.copy(trustDirectLinks = !it.trustDirectLinks) } }
        ValueRow("Maximum file size", if (settings.maxSizeGb == 0) "No limit" else "${settings.maxSizeGb} GB") { openDialog(SettingsDialog.MAX_SIZE) }
    }
    group("audio-language", "Audio language") {
        ValueRow("Preferred audio", settings.audioLanguages.joinToString { Languages.displayName(it) }.ifEmpty { "Any" }) { openDialog(SettingsDialog.AUDIO) }
    }
    group("player", "Player") {
        ToggleRow("Use external player", "Open streams in VLC, Just Player, MX Player, etc. instead of the built-in player.", settings.useExternalPlayer) {
            vm.update { it.copy(useExternalPlayer = !it.useExternalPlayer) }
        }
    }
}

private fun LazyListScope.subtitlesCategory(vm: SettingsViewModel, settings: AppSettings, openDialog: (SettingsDialog) -> Unit) {
    group("subtitle-prefs", "Which subtitles") {
        ValueRow("Preferred subtitles", settings.subtitleLanguages.joinToString { Languages.displayName(it) }.ifEmpty { "None" }) { openDialog(SettingsDialog.SUBS) }
        ToggleRow("Turn on subtitles automatically", "Select a subtitle track in your preferred language when playback starts.", settings.autoSubtitles) {
            vm.update { it.copy(autoSubtitles = !it.autoSubtitles) }
        }
        ToggleRow("Prefer SDH subtitles", "Choose subtitles for the deaf and hard of hearing (with sound descriptions like [door slams]) when a language has them.", settings.preferSdh) {
            vm.update { it.copy(preferSdh = !it.preferSdh) }
        }
    }
    group("subtitle-style", "Subtitle appearance", "Turn Custom style off to show subtitles exactly as the file styles them. Also in the player: hold OK on Subtitles → Subtitle style.") {
        if (!settings.subtitleOriginalStyle) SubtitlePreview(settings)
        SubtitleStyleEditor(settings) { t -> vm.update(t) }
    }
}

private fun LazyListScope.appearanceCategory(vm: SettingsViewModel, settings: AppSettings) {
    group("mode", "Light & glass") {
        ToggleRow("Light mode", "Light backgrounds with dark text. The video player always stays dark.", settings.lightMode) {
            vm.updateLook { it.copy(lightMode = !it.lightMode) }
        }
        ToggleRow("Glass style", "Frosted, see-through panels and menus over a soft glow of your theme color. On Android 12 and newer, menus also blur what's behind them.", settings.glassStyle) {
            vm.updateLook { it.copy(glassStyle = !it.glassStyle) }
        }
    }
    group("theme", "Color theme", "With an animated theme on, a palette recolors it: its menus and its scene.") {
        ThemePicker(settings) { t -> vm.updateLook(t) }
    }
    group("animated", "Animated themes", "Weather and Holidays have their own kinds to pick from. Ethereal, PS2 · Y2K, Acidwave, Cybercore, Graffiti and Liquid Glass restyle the whole app; change any of their colors under Customize colors.") {
        val current = DynamicTheme.of(settings.dynamicTheme)
        LazyRow(contentPadding = PaddingValues(vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            items(DynamicTheme.entries.filter { (!it.hidden || settings.catRaveUnlocked) }, key = { it.name }) { d ->
                TvChip(d.label, selected = current == d, onClick = {
                    vm.updateLook { it.copy(dynamicTheme = d.name, themeBeforeRave = if (d == DynamicTheme.CATRAVE && it.dynamicTheme != "CATRAVE") it.dynamicTheme else it.themeBeforeRave) }
                })
            }
        }
        // Sub-themes: the kind of weather, the holiday, the vintage desktop.
        if (current.variants.isNotEmpty()) {
            val chosen = settings.themeVariants[current.name] ?: current.variants.first().first
            LazyRow(contentPadding = PaddingValues(vertical = 4.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                items(current.variants, key = { it.first }) { (k, label) ->
                    val shown = if (k == "AUTO") "$label: ${com.zemu.tv.ui.theme.Holiday.today().label}" else label
                    TvChip(shown, selected = chosen == k, onClick = { vm.updateLook { it.copy(themeVariants = it.themeVariants + (current.name to k)) } })
                }
            }
        }
        // Cybercore's mouse pointer: its color, size and where it sits on the selected button.
        if (current == DynamicTheme.RETRO) {
            Text("Mouse pointer", fontWeight = FontWeight.SemiBold, fontSize = 15.sp, modifier = Modifier.padding(top = 10.dp))
            LazyRow(contentPadding = PaddingValues(vertical = 4.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                val colors = listOf(0L to "Default", 0xFFFFFFFFL to "White", 0xFF000000L to "Black", 0xFFFFE600L to "Yellow", 0xFF39FF14L to "Green", 0xFFFF5FB8L to "Pink", 0xFF00B7FFL to "Blue", 0xFFFF3B30L to "Red")
                items(colors, key = { it.first }) { (v, label) ->
                    TvChip(label, settings.pointerColor == v, { vm.update { it.copy(pointerColor = v) } })
                }
            }
            LazyRow(contentPadding = PaddingValues(vertical = 4.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                items(listOf(75, 100, 150, 200), key = { "size$it" }) { z ->
                    TvChip("Size $z%", settings.pointerSize == z, { vm.update { it.copy(pointerSize = z) } })
                }
                items(listOf("LEFT" to "Left", "CENTER" to "Center", "RIGHT" to "Right", "CORNER" to "Corner"), key = { it.first }) { (k, label) ->
                    TvChip(label, settings.pointerPosition == k, { vm.update { it.copy(pointerPosition = k) } })
                }
            }
        }
    }
    group("colors", "Customize colors", "Every color the theme uses, as a palette: pick one to change it. Each theme keeps its own, separately for light and dark mode. Save palettes to reuse them, for every theme or just this one.") {
        ColorCustomizer(settings, vm::updateLook) { t -> vm.update(t) }
    }
    group("size", "Size, text & artwork", "UI zoom makes everything bigger or smaller: posters, text, icons and the player's menu. Font and text size change only the text, in any theme.") {
        Text("UI zoom", fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
        // Wraps onto a second line at big zoom sizes.
        @OptIn(androidx.compose.foundation.layout.ExperimentalLayoutApi::class)
        androidx.compose.foundation.layout.FlowRow(Modifier.padding(top = 6.dp, bottom = 6.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            listOf(80, 90, 100, 110, 125, 150).forEach { z ->
                TvChip("$z%", settings.uiZoom == z, { vm.update { it.copy(uiZoom = z) } })
            }
        }
        Text("Font", fontSize = 15.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(top = 6.dp))
        @OptIn(androidx.compose.foundation.layout.ExperimentalLayoutApi::class)
        androidx.compose.foundation.layout.FlowRow(Modifier.padding(top = 6.dp, bottom = 6.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            com.zemu.tv.ui.theme.FONT_CHOICES.forEach { (k, label) ->
                // Each chip is written in its own font.
                val f = com.zemu.tv.ui.theme.fontFamilyOf(k)
                FocusSurface(onClick = { vm.update { it.copy(font = k) } }, shape = com.zemu.tv.ui.theme.styledShape(RoundedCornerShape(50)), containerColor = if (settings.font == k) Palette.SurfaceHigh else Palette.Surface) {
                    Text((if (settings.font == k) "✓ " else "") + label, fontFamily = f, fontSize = 15.sp, modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp))
                }
            }
        }
        Text("Text size", fontSize = 15.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(top = 6.dp))
        @OptIn(androidx.compose.foundation.layout.ExperimentalLayoutApi::class)
        androidx.compose.foundation.layout.FlowRow(Modifier.padding(top = 6.dp, bottom = 6.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            listOf(85, 100, 115, 130, 150).forEach { z ->
                TvChip("$z%", settings.fontSize == z, { vm.update { it.copy(fontSize = z) } })
            }
        }
        ToggleRow("Title artwork", "The big picture behind the title at the top of Home, Browse and the title page.", settings.heroArt) {
            vm.update { it.copy(heroArt = !it.heroArt) }
        }
        ToggleRow("Logo artwork", "Show titles as their logo artwork. Off: plain text.", settings.logoArt) {
            vm.update { it.copy(logoArt = !it.logoArt) }
        }
    }
}

private fun LazyListScope.browsingCategory(vm: SettingsViewModel, settings: AppSettings, onManageRows: (String) -> Unit) {
    group("rows", "Rows on each page", "Change, reorder, remove or add the rows on each page.") {
        listOf("home" to "Home", "movie" to "Movies", "series" to "Series", "anime" to "Anime").forEach { (page, label) ->
            ValueRow("Manage $label rows", "Pin · move · remove · add") { onManageRows(page) }
        }
        ToggleRow("Hide watched titles in rows", "Keep movies and shows you've finished out of suggestions and categories.", settings.hideWatchedInRows) {
            vm.update { it.copy(hideWatchedInRows = !it.hideWatchedInRows) }
        }
    }
    group("trailers", "Trailers") {
        ToggleRow("Trailers", "Off: no trailers anywhere, no autoplay and no Trailer buttons.", settings.trailers) {
            vm.update { it.copy(trailers = !it.trailers) }
        }
        if (settings.trailers) ToggleRow("Autoplay trailers", "Play the trailer behind the title after you pause on it for a few seconds.", settings.heroTrailers) {
            vm.update { it.copy(heroTrailers = !it.heroTrailers) }
        }
        if (settings.trailers) ToggleRow("Trailer sound", "Play autoplaying trailers with sound. Full-screen trailers (hold OK on a poster) always have sound.", settings.heroTrailerSound) {
            vm.update { it.copy(heroTrailerSound = !it.heroTrailerSound) }
        }
    }
    group("recents", "Search history", "Recent searches and recently viewed titles show on the Search screen before you type.") {
        val scope = rememberCoroutineScope()
        ToggleRow("Share with every profile on this TV", "One list for everyone, instead of one per profile.", settings.shareRecents) {
            scope.launch { vm.container.userStore.setShareRecents(!settings.shareRecents) }
        }
    }
}

@Composable
private fun TraktSection(vm: SettingsViewModel, settings: AppSettings) {
    val trakt = vm.container.trakt
    val scope = rememberCoroutineScope()
    var id by remember { mutableStateOf("") }
    var secret by remember { mutableStateOf("") }
    var link by remember { mutableStateOf<com.zemu.tv.data.TraktLink?>(null) }
    var status by remember { mutableStateOf<String?>(null) }
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        if (settings.traktAccessToken.isNotBlank()) {
            Text("✓ Linked to Trakt", color = Palette.Cached, fontWeight = FontWeight.Bold)
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                TvButton("Sync now", primary = true, onClick = { scope.launch { status = runCatching { trakt.sync() }.getOrElse { "Sync failed: ${it.message}" } } })
                TvButton("Unlink", onClick = { scope.launch { trakt.disconnect() } })
            }
        } else {
            val saveId = { vm.update { it.copy(traktClientId = id.trim()) }; id = "" }
            val saveSecret = { vm.update { it.copy(traktClientSecret = secret.trim()) }; secret = "" }
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                TvTextField(id, { id = it }, if (settings.traktClientId.isBlank()) "Client ID" else "Client ID saved (••••${settings.traktClientId.takeLast(4)})", Modifier.weight(1f), onSubmit = saveId)
                TvButton("Save", onClick = saveId)
            }
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                TvTextField(secret, { secret = it }, if (settings.traktClientSecret.isBlank()) "Client Secret" else "Secret saved (••••${settings.traktClientSecret.takeLast(4)})", Modifier.weight(1f), onSubmit = saveSecret)
                TvButton("Save", onClick = saveSecret)
            }
            if (trakt.configured) TvButton("Link this TV", primary = true, onClick = {
                scope.launch { link = runCatching { trakt.startLink() }.onFailure { status = "Couldn't reach Trakt: ${it.message}" }.getOrNull() }
            })
        }
        status?.let { Text(it, color = Palette.TextSecondary, fontSize = 14.sp) }
    }
    link?.let { l ->
        // Polls until linked, declined or expired.
        LaunchedEffect(l) {
            while (System.currentTimeMillis() < l.expiresAt) {
                kotlinx.coroutines.delay(l.intervalSec * 1000L)
                val done = runCatching { trakt.pollLink(l) }.getOrElse { status = it.message; link = null; return@LaunchedEffect }
                if (done) { status = "Linked! Syncing your watchlist…"; link = null; return@LaunchedEffect }
            }
            status = "The code expired. Try again."; link = null
        }
        androidx.compose.ui.window.Dialog(onDismissRequest = { link = null }) {
            com.zemu.tv.ui.theme.DialogBackdropBlur()
            Column(
                Modifier.glassPanel(com.zemu.tv.ui.theme.boxy(RoundedCornerShape(16.dp))).padding(28.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Text("Link Trakt", fontSize = 22.sp, fontWeight = FontWeight.Bold)
                Text("On your phone or computer, go to", color = Palette.TextSecondary, modifier = Modifier.padding(top = 10.dp))
                Text(l.url, fontSize = 20.sp, fontWeight = FontWeight.Bold)
                com.zemu.tv.ui.components.QrCode(l.url, 150.dp, Modifier.padding(vertical = 12.dp))
                Text("and enter this code", color = Palette.TextSecondary)
                Text(l.userCode, fontSize = 40.sp, fontWeight = FontWeight.Black, letterSpacing = 6.sp, color = Palette.Accent)
                TvButton("Cancel", onClick = { link = null }, modifier = Modifier.padding(top = 14.dp))
            }
        }
    }
}

private fun LazyListScope.soundsCategory(vm: SettingsViewModel, settings: AppSettings) {
    group("sounds", "Sound effects") {
        ToggleRow("Sound effects", "Soft clicks when you move, select, hold OK and go back. PS2, Acidwave, Cybercore, Graffiti, Liquid Glass, Ethereal and the Cat Rave each have their own sounds.", settings.soundEffects) {
            vm.update { it.copy(soundEffects = !it.soundEffects) }
        }
    }
    group("feedback", "Touch screens") {
        ToggleRow("Vibration", "A short vibration when you change pages and when a video starts. Phones and tablets only.", settings.vibration) {
            vm.update { it.copy(vibration = !it.vibration) }
        }
    }
}

private fun LazyListScope.screensaverCategory(vm: SettingsViewModel, settings: AppSettings) {
    group(
        "screensaver", "Screensaver",
        "After Zemu sits idle, a full-screen slideshow of titles picked for you, from the same suggestions and catalogs as Home (a new mix every time). OK plays the title showing; any other button returns to where you were.",
    ) {
        ToggleRow("Screensaver", "Off by default. Needs a TMDB or fanart.tv key below to find backdrops and title logos.", settings.screensaver) {
            vm.update { it.copy(screensaver = !it.screensaver) }
        }
        ToggleRow("Show title and Watch now", "The title's logo, year and genres, with a Watch now button.", settings.screensaverShowTitle) {
            vm.update { it.copy(screensaverShowTitle = !it.screensaverShowTitle) }
        }
        // Idle timeout: 15 s to 10 min in 15 s steps. Image duration: 3–60 s.
        TvSlider(
            "Idle timeout (s)", (settings.screensaverIdleSec - 15) / 585f, 15f / 585f,
            androidx.compose.ui.graphics.SolidColor(Palette.SurfaceHigh), "${settings.screensaverIdleSec}s",
        ) { v -> vm.update { it.copy(screensaverIdleSec = (15 + Math.round(v * 585 / 15f) * 15).coerceIn(15, 600)) } }
        TvSlider(
            "Time per title (s)", (settings.screensaverImageSec - 3) / 57f, 1f / 57f,
            androidx.compose.ui.graphics.SolidColor(Palette.SurfaceHigh), "${settings.screensaverImageSec}s",
        ) { v -> vm.update { it.copy(screensaverImageSec = (3 + Math.round(v * 57)).coerceIn(3, 60)) } }
        // Fade: 0.3–5 s in tenths.
        TvSlider(
            "Fade between titles", (settings.screensaverFadeTenths - 3) / 47f, 1f / 47f,
            androidx.compose.ui.graphics.SolidColor(Palette.SurfaceHigh), "%.1fs".format(settings.screensaverFadeTenths / 10f),
        ) { v -> vm.update { it.copy(screensaverFadeTenths = (3 + Math.round(v * 47)).coerceIn(3, 50)) } }
        var tmdbKey by remember { mutableStateOf("") }
        Row(Modifier.padding(top = 6.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            TvTextField(tmdbKey, { tmdbKey = it }, if (settings.tmdbApiKey.isBlank()) "TMDB API Key" else "TMDB key saved (••••${settings.tmdbApiKey.takeLast(4)})", Modifier.weight(1f), onSubmit = { vm.saveTmdbKey(tmdbKey); tmdbKey = "" })
            TvButton("Save", onClick = { vm.saveTmdbKey(tmdbKey); tmdbKey = "" })
        }
        var fanartKey by remember { mutableStateOf("") }
        Row(Modifier.padding(top = 6.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            TvTextField(fanartKey, { fanartKey = it }, if (settings.fanartApiKey.isBlank()) "fanart.tv API Key" else "fanart.tv key saved (••••${settings.fanartApiKey.takeLast(4)})", Modifier.weight(1f), onSubmit = { vm.update { s -> s.copy(fanartApiKey = fanartKey.trim()) }; fanartKey = "" })
            TvButton("Save", onClick = { vm.update { s -> s.copy(fanartApiKey = fanartKey.trim()) }; fanartKey = "" })
        }
    }
}

private fun LazyListScope.deviceCategory(vm: SettingsViewModel, settings: AppSettings) {
    val detected = vm.container.detectedCapabilities
    val caps = vm.capabilities
    fun res(r: Int) = if (r >= 2160) "4K" else "${r}p"
    group("reset", "Recommended settings") {
        val changed = settings.deviceOverrides.isNotEmpty() || settings.maxResolutionOverride != 0 || settings.avoidDolbyVision || settings.preferSoftwareDecoders
        ValueRow("Reset to recommended settings for my TV", if (changed) "Uses what this TV reports" else "Already using them") {
            vm.update { it.copy(deviceOverrides = emptyMap(), maxResolutionOverride = 0, avoidDolbyVision = false, preferSoftwareDecoders = false) }
        }
    }
    group("output", "Video output", "OK cycles through the choices.") {
        val options = listOf(0, 2160, 1440, 1080, 720)
        ValueRow("Maximum resolution", if (settings.maxResolutionOverride == 0) "${res(detected.maxResolution)} (detected)" else res(caps.maxResolution)) {
            vm.update { s -> s.copy(maxResolutionOverride = options[(options.indexOf(s.maxResolutionOverride) + 1).mod(options.size)]) }
        }
    }
    group("formats", "Formats this device can play", "OK switches a format on or off. \"Detected\" means it's what the TV reported.") {
        DeviceCapabilities.KEYS.forEach { (key, label) ->
            val on = caps.supports(key)
            val manual = key in settings.deviceOverrides
            ToggleRow(label, if (manual) "Set by you (detected: ${if (detected.supports(key)) "supported" else "not supported"})" else "Detected", on) {
                vm.update { s ->
                    val next = !on
                    // Back to the detected value drops the override, so a reset isn't needed.
                    val o = if (next == detected.supports(key)) s.deviceOverrides - key else s.deviceOverrides + (key to next)
                    s.copy(deviceOverrides = o)
                }
            }
        }
    }
    group("decoders", "Decoders") {
        ToggleRow("Play Dolby Vision as HDR10", "For TVs whose Dolby Vision decoder fails on some files.", settings.avoidDolbyVision) {
            vm.update { it.copy(avoidDolbyVision = !it.avoidDolbyVision) }
        }
        ToggleRow("Prefer software video decoders", "Slower, but plays files the hardware decoder rejects.", settings.preferSoftwareDecoders) {
            vm.update { it.copy(preferSoftwareDecoders = !it.preferSoftwareDecoders) }
        }
    }
}

private fun LazyListScope.systemCategory(vm: SettingsViewModel, settings: AppSettings) {
    group("updates", "Updates", "New versions come from the Zemu releases on GitHub.") {
        val updater = vm.container.appContext.app.updater
        var status by remember { mutableStateOf<String?>(null) }
        val scope = rememberCoroutineScope()
        ValueRow("Check for updates", status ?: "You have ${updater.currentVersion}") {
            status = "Checking…"
            scope.launch {
                status = runCatching { updater.check() }.fold(
                    { u -> if (u == null) "Up to date (${updater.currentVersion})" else { updater.showNow.value = true; "Zemu ${u.version} is available" } },
                    { "Couldn't reach GitHub" },
                )
            }
        }
    }
    group("downloads", "Downloads") {
        ToggleRow("Downloads", "Save titles on this device to watch without internet: adds Downloads to the menu and \"Download for offline\" when you hold OK on a stream. Titles already downloaded stay until you delete them.", settings.downloads) {
            vm.update { it.copy(downloads = !it.downloads) }
        }
    }
    group("history", "Watch history") {
        ValueRow("Clear watch history", "Resets Continue Watching and recommendations") { vm.clearHistory() }
    }
}

private fun List<String>.toggle(code: String) = if (code in this) this - code else this + code

@Composable
private fun LanguageDialog(title: String, selected: List<String>, onDismiss: () -> Unit, onToggle: (String) -> Unit) {
    val codes = (selected + Languages.common).distinct()
    ChoiceDialog(
        title = title,
        options = codes.map { ChoiceOption(it, Languages.displayName(it), selected.indexOf(it).takeIf { i -> i >= 0 }?.let { i -> "#${i + 1}" }) },
        selected = selected.toSet(),
        onToggle = onToggle,
        onDismiss = onDismiss,
    )
}

@Composable
private fun ToggleRow(title: String, description: String, on: Boolean, onClick: () -> Unit) {
    FocusSurface(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
        shape = com.zemu.tv.ui.theme.boxy(RoundedCornerShape(10.dp)),
        containerColor = Palette.Surface,
        focusedScale = 1.01f,
    ) {
        Row(Modifier.padding(horizontal = 18.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(title, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
                Text(description, color = LocalContentColor.current.copy(alpha = 0.72f), fontSize = 13.sp)
            }
            Text(if (on) "ON" else "OFF", color = LocalContentColor.current.copy(alpha = if (on) 1f else 0.5f), fontWeight = FontWeight.Black, fontSize = 15.sp)
        }
    }
}

@Composable
private fun ValueRow(title: String, value: String, modifier: Modifier = Modifier, onClick: () -> Unit) {
    FocusSurface(
        onClick = onClick,
        modifier = modifier.fillMaxWidth().padding(vertical = 4.dp),
        shape = com.zemu.tv.ui.theme.boxy(RoundedCornerShape(10.dp)),
        containerColor = Palette.Surface,
        focusedScale = 1.01f,
    ) {
        Row(Modifier.padding(horizontal = 18.dp, vertical = 14.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(title, fontSize = 16.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
            // Weighted too, so a long value at big UI zoom can't squeeze the title into a word per line.
            Text(value, color = LocalContentColor.current.copy(alpha = 0.72f), fontSize = 14.sp, maxLines = 1, overflow = TextOverflow.Ellipsis,
                textAlign = androidx.compose.ui.text.style.TextAlign.End, modifier = Modifier.weight(1f, fill = false).padding(start = 12.dp))
        }
    }
}

/** A sample line drawn with the chosen subtitle style. */
@Composable
private fun SubtitlePreview(settings: AppSettings) {
    val color = androidx.compose.ui.graphics.Color(settings.subtitleColor.toInt())
    val bg = when (settings.subtitleBackground) {
        1 -> androidx.compose.ui.graphics.Color.Black.copy(alpha = 0.6f)
        2 -> androidx.compose.ui.graphics.Color.Black
        else -> androidx.compose.ui.graphics.Color.Transparent
    }
    val shadow = when (settings.subtitleEdge) {
        1 -> androidx.compose.ui.graphics.Shadow(androidx.compose.ui.graphics.Color.Black, blurRadius = 3f)
        2 -> androidx.compose.ui.graphics.Shadow(androidx.compose.ui.graphics.Color.Black, androidx.compose.ui.geometry.Offset(3f, 3f), 4f)
        else -> null
    }
    androidx.compose.foundation.layout.Box(
        Modifier
            .fillMaxWidth()
            .padding(vertical = 6.dp)
            .previewBackdrop(),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            "This is how subtitles will look.",
            color = color,
            fontSize = (20 * settings.subtitleScale).sp,
            style = androidx.compose.ui.text.TextStyle(shadow = shadow),
            modifier = Modifier.subtitleBox(bg).padding(horizontal = 10.dp, vertical = 4.dp),
        )
    }
}

private fun Modifier.previewBackdrop(): Modifier =
    this.then(Modifier.background(androidx.compose.ui.graphics.Brush.horizontalGradient(listOf(androidx.compose.ui.graphics.Color(0xFF3A4A5A), androidx.compose.ui.graphics.Color(0xFF6A5A3A))), com.zemu.tv.ui.theme.boxy(RoundedCornerShape(10.dp))).height(110.dp))

private fun Modifier.subtitleBox(c: androidx.compose.ui.graphics.Color): Modifier = this.then(Modifier.background(c, com.zemu.tv.ui.theme.boxy(RoundedCornerShape(4.dp))))

@Composable
private fun KidsSection() {
    val context = LocalContext.current
    val kids = com.zemu.tv.ui.kids.rememberKids()
    val store = context.app.profiles
    val scope = rememberCoroutineScope()
    var newCode by remember { mutableStateOf(false) }
    fun update(change: (com.zemu.tv.data.KidsSettings) -> com.zemu.tv.data.KidsSettings) = scope.launch { store.updateKids(change) }
    Column(Modifier.padding(top = 8.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        ToggleRow(
            "Kid profiles",
            "Lets a profile be made a kid profile (Settings → Profiles → edit or add a profile). A kid profile only shows family and kids' titles with the ratings below; leaving it or opening Settings needs the parent code.",
            kids.enabled,
        ) {
            if (!kids.enabled && kids.pinHash.isEmpty()) newCode = true
            update { it.copy(enabled = !it.enabled) }
        }
        if (kids.enabled) {
            Text("Ratings a kid may watch", fontWeight = FontWeight.Bold, fontSize = 16.sp, modifier = Modifier.padding(top = 8.dp))
            Text(
                "Only family or kids' titles show at all, whatever their rating. Movie ratings come from Wikidata (or OMDb or TMDB with a key). TV ratings need an OMDb or TMDB key; without one, kids' shows count as unrated.",
                color = Palette.TextSecondary, fontSize = 13.sp,
            )
            listOf("Movies" to com.zemu.tv.data.Ratings.MOVIE, "TV" to com.zemu.tv.data.Ratings.TV, "Other" to listOf(com.zemu.tv.data.Ratings.UNRATED)).forEach { (group, certs) ->
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(group, color = Palette.TextSecondary, fontSize = 14.sp, modifier = Modifier.width(60.dp))
                    certs.forEach { cert ->
                        TvChip(if (cert == com.zemu.tv.data.Ratings.UNRATED) "Unrated kids' titles" else cert, cert in kids.allowed, {
                            update { it.copy(allowed = if (cert in it.allowed) it.allowed - cert else it.allowed + cert) }
                        })
                    }
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.padding(top = 8.dp)) {
                TvButton(if (kids.pinHash.isEmpty()) "Set parent code" else "Change parent code", onClick = { newCode = true })
            }
        }
    }
    // Settings is locked for kids, so whoever is here may set a new code.
    if (newCode) com.zemu.tv.ui.kids.CreateParentCode(onDismiss = { newCode = false }) { newCode = false }
}
