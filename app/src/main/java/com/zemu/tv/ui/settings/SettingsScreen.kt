package com.zemu.tv.ui.settings

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
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.runtime.LaunchedEffect
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

    fun clearHistory() = viewModelScope.launch {
        c.userStore.clearHistory()
        message.value = "Watch history cleared"
    }
}

private enum class SettingsDialog { AUDIO, SUBS, MAX_SIZE, COUNTDOWN, STILL_EPISODES }

/** The groups shown in Settings' left-hand list. */
private enum class SettingsCategory(val label: String, val blurb: String) {
    ADDONS("Addons & accounts", "Stream addons, your debrid service, title details and cast info."),
    PROFILES("Profiles", "Who's watching, pictures and the profile picker."),
    PLAYBACK("Playback", "Instant play, autoplay, players and decoders."),
    STREAMS("Streams & languages", "Which cached streams are shown and preferred."),
    SUBTITLES("Subtitles", "How subtitles look and the skip-intro button."),
    APPEARANCE("Appearance", "Color themes, animated themes, vibration and trailers."),
    DEVICE("This device", "What this TV can play, used for \"Best for this TV\"."),
}

@Composable
fun SettingsScreen(onOpenAddons: () -> Unit) {
    val context = LocalContext.current
    val c = context.container
    val vm: SettingsViewModel = viewModel { SettingsViewModel(c, context.app) }
    val settings by vm.settings.collectAsStateWithLifecycle()
    val message by vm.message.collectAsStateWithLifecycle()
    var dialog by remember { mutableStateOf<SettingsDialog?>(null) }
    var category by rememberSaveable { mutableStateOf(SettingsCategory.ADDONS) }
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
                    selected = cat == category,
                    modifier = if (cat == SettingsCategory.ADDONS) Modifier.focusRequester(topFocus) else Modifier,
                    onFocused = { category = cat },
                    onClick = { category = cat },
                )
            }
            Spacer(Modifier.size(40.dp))
        }
        Spacer(Modifier.width(28.dp))
        // Right: the chosen category.
        LazyColumn(
            Modifier.weight(1f).fillMaxHeight(),
            contentPadding = PaddingValues(end = 48.dp, bottom = 120.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            item(key = "title-${category.name}") {
                Text(category.label, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 4.dp))
                Text(category.blurb, color = Palette.TextSecondary, fontSize = 14.sp, modifier = Modifier.padding(top = 4.dp, bottom = 8.dp))
                message?.let { Text(it, color = Palette.Cached, fontSize = 14.sp, modifier = Modifier.padding(bottom = 8.dp)) }
            }
            when (category) {
                SettingsCategory.ADDONS -> addonsCategory(vm, settings, remote, onOpenAddons)
                SettingsCategory.PROFILES -> item(key = "profiles") { ProfilesSection(remote) }
                SettingsCategory.PLAYBACK -> playbackCategory(vm, settings) { dialog = it }
                SettingsCategory.STREAMS -> streamsCategory(vm, settings) { dialog = it }
                SettingsCategory.SUBTITLES -> subtitlesCategory(vm, settings)
                SettingsCategory.APPEARANCE -> appearanceCategory(vm, settings)
                SettingsCategory.DEVICE -> deviceCategory(vm)
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
}

@Composable
private fun CategoryItem(label: String, selected: Boolean, modifier: Modifier, onFocused: () -> Unit, onClick: () -> Unit) {
    FocusSurface(
        onClick = onClick,
        modifier = modifier.fillMaxWidth().padding(vertical = 3.dp).onFocusChanged { if (it.isFocused) onFocused() },
        shape = RoundedCornerShape(10.dp),
        containerColor = if (selected) Palette.SurfaceHigh else Color.Transparent,
        contentColor = if (selected) Color.White else Palette.TextSecondary,
        focusedScale = 1.03f,
    ) {
        Row(Modifier.padding(horizontal = 12.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(width = 4.dp, height = 18.dp).background(if (selected) Palette.Accent else Color.Transparent, RoundedCornerShape(2.dp)))
            Spacer(Modifier.width(10.dp))
            Text(label, fontSize = 16.sp, fontWeight = if (selected) FontWeight.Bold else FontWeight.Medium, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}

/** A labelled group inside a category; [spaced] adds room above it. */
private fun LazyListScope.group(key: String, title: String, note: String? = null, content: @Composable () -> Unit) {
    item(key = key) {
        Column(Modifier.fillMaxWidth().padding(top = 18.dp)) {
            Text(title, fontSize = 17.sp, fontWeight = FontWeight.Bold)
            note?.let { Text(it, color = Palette.TextSecondary, fontSize = 13.sp, modifier = Modifier.padding(top = 2.dp)) }
            Spacer(Modifier.size(8.dp))
            content()
        }
    }
}

private fun LazyListScope.addonsCategory(vm: SettingsViewModel, settings: AppSettings, remote: String?, onOpenAddons: () -> Unit) {
    group("addons", "Stream addons", "Zemu uses Stremio addons. Install a debrid-enabled one (AIOStreams, Torrentio, Comet, MediaFusion, …). Only cached streams are shown.") {
        val addons by vm.addons.collectAsStateWithLifecycle()
        val streamAddons = addons.count { it.manifest.hasResource("stream") }
        ValueRow("Manage addons", "${addons.size} installed · $streamAddons with streams") { onOpenAddons() }
    }
    group("debrid", "Debrid account") {
        DebridSection(vm.container, remote)
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
        ToggleRow("Play something similar", "After a movie or a series finale, count down to a recommended title you haven't seen.", settings.autoplaySimilar) {
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
    group("player", "Player") {
        ToggleRow("Use external player", "Open streams in VLC, Just Player, MX Player, etc. instead of the built-in player.", settings.useExternalPlayer) {
            vm.update { it.copy(useExternalPlayer = !it.useExternalPlayer) }
        }
        ToggleRow(
            "Play Dolby Vision as HDR10",
            "Fixes \"decoding failed\" on TVs whose Dolby Vision decoder can't handle some files. Turned on automatically if needed.",
            settings.avoidDolbyVision,
        ) { vm.update { it.copy(avoidDolbyVision = !it.avoidDolbyVision) } }
        ToggleRow(
            "Prefer software video decoders",
            "Slower, but can play files the TV's hardware decoder rejects. Turned on automatically if needed.",
            settings.preferSoftwareDecoders,
        ) { vm.update { it.copy(preferSoftwareDecoders = !it.preferSoftwareDecoders) } }
    }
    group("history", "History") {
        ValueRow("Clear watch history", "Resets Continue Watching and recommendations") { vm.clearHistory() }
    }
}

private fun LazyListScope.streamsCategory(vm: SettingsViewModel, settings: AppSettings, openDialog: (SettingsDialog) -> Unit) {
    group("cached", "Cached streams", "Catalogs show every title. When you open one, only streams cached on your debrid service are listed.") {
        ToggleRow(
            "Treat direct links as cached",
            "Count plain HTTP streams without debrid markers as instantly playable. Leave off for strict debrid-cached only.",
            settings.trustDirectLinks,
        ) { vm.update { it.copy(trustDirectLinks = !it.trustDirectLinks) } }
        ValueRow("Maximum file size", if (settings.maxSizeGb == 0) "No limit" else "${settings.maxSizeGb} GB") { openDialog(SettingsDialog.MAX_SIZE) }
    }
    group("languages", "Languages") {
        ValueRow("Preferred audio", settings.audioLanguages.joinToString { Languages.displayName(it) }.ifEmpty { "Any" }) { openDialog(SettingsDialog.AUDIO) }
        ValueRow("Preferred subtitles", settings.subtitleLanguages.joinToString { Languages.displayName(it) }.ifEmpty { "None" }) { openDialog(SettingsDialog.SUBS) }
        ToggleRow("Turn on subtitles automatically", "Select a subtitle track in your preferred language when playback starts.", settings.autoSubtitles) {
            vm.update { it.copy(autoSubtitles = !it.autoSubtitles) }
        }
    }
}

private fun LazyListScope.subtitlesCategory(vm: SettingsViewModel, settings: AppSettings) {
    group("subtitle-style", "Subtitle appearance", "Also available in the player: Subtitles → Subtitle style.") {
        SubtitlePreview(settings)
        SubtitleStyleEditor(settings) { t -> vm.update(t) }
    }
    group("skip", "Skipping") {
        ToggleRow("Skip intro button", "Show \"Skip intro\" / \"Skip recap\" while they play (community timestamps from TheIntroDB and AniSkip). The next-episode card starts at the credits.", settings.skipIntroButton) {
            vm.update { it.copy(skipIntroButton = !it.skipIntroButton) }
        }
    }
}

private fun LazyListScope.appearanceCategory(vm: SettingsViewModel, settings: AppSettings) {
    group("theme", "Color theme") {
        ThemePicker(settings) { t -> vm.update(t) }
    }
    group("animated", "Animated themes", "Halloween, Christmas, Cyberpunk and the other effect themes bring their own colors. RGB, Snowfall and Rain keep your color theme.") {
        LazyRow(contentPadding = PaddingValues(vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            items(DynamicTheme.entries.toList(), key = { it.name }) { d ->
                TvChip(d.label, selected = settings.dynamicTheme == d.name, onClick = { vm.update { it.copy(dynamicTheme = d.name) } })
            }
        }
    }
    group("feedback", "Touch screens") {
        ToggleRow("Vibration", "A short vibration when you change pages and when a video starts. Phones and tablets only.", settings.vibration) {
            vm.update { it.copy(vibration = !it.vibration) }
        }
    }
    group("trailers", "Trailers") {
        ToggleRow("Autoplay trailers", "Play the trailer behind the title after you pause on it for a few seconds.", settings.heroTrailers) {
            vm.update { it.copy(heroTrailers = !it.heroTrailers) }
        }
        ToggleRow("Trailer sound", "Play autoplaying trailers with sound. Full-screen trailers (hold OK on a poster) always have sound.", settings.heroTrailerSound) {
            vm.update { it.copy(heroTrailerSound = !it.heroTrailerSound) }
        }
    }
}

private fun LazyListScope.deviceCategory(vm: SettingsViewModel) {
    val caps = vm.capabilities
    group("output", "Video output") {
        InfoRow("Maximum resolution", if (caps.maxResolution >= 2160) "4K" else "${caps.maxResolution}p")
    }
    group("formats", "Formats this device can play") {
        caps.summary().forEach { (label, ok) -> InfoRow(label, if (ok) "✓ Supported" else "✗ Not supported", ok) }
    }
}

/** A read-only line. Focusable so the remote can scroll to it. */
@Composable
private fun InfoRow(title: String, value: String, ok: Boolean = true) {
    FocusSurface(
        onClick = {},
        modifier = Modifier.fillMaxWidth().padding(vertical = 3.dp),
        shape = RoundedCornerShape(10.dp),
        containerColor = Palette.Surface,
        focusedContainerColor = Palette.SurfaceHigh,
        focusedContentColor = Color.White,
        focusedBorder = Color.White,
        focusedScale = 1.01f,
    ) {
        Row(Modifier.padding(horizontal = 18.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(title, fontSize = 16.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
            Text(value, color = if (ok) Palette.Match else Palette.TextMuted, fontSize = 14.sp, fontWeight = FontWeight.Bold)
        }
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
        shape = RoundedCornerShape(10.dp),
        containerColor = Palette.Surface,
        focusedContainerColor = Palette.SurfaceHigh,
        focusedContentColor = Color.White,
        focusedBorder = Color.White,
        focusedScale = 1.01f,
    ) {
        Row(Modifier.padding(horizontal = 18.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(title, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
                Text(description, color = Palette.TextSecondary, fontSize = 13.sp)
            }
            Text(if (on) "ON" else "OFF", color = if (on) Palette.Match else Palette.TextMuted, fontWeight = FontWeight.Black, fontSize = 15.sp)
        }
    }
}

@Composable
private fun ValueRow(title: String, value: String, modifier: Modifier = Modifier, onClick: () -> Unit) {
    FocusSurface(
        onClick = onClick,
        modifier = modifier.fillMaxWidth().padding(vertical = 4.dp),
        shape = RoundedCornerShape(10.dp),
        containerColor = Palette.Surface,
        focusedContainerColor = Palette.SurfaceHigh,
        focusedContentColor = Color.White,
        focusedBorder = Color.White,
        focusedScale = 1.01f,
    ) {
        Row(Modifier.padding(horizontal = 18.dp, vertical = 14.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(title, fontSize = 16.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
            Text(value, color = Palette.TextSecondary, fontSize = 14.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
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
    this.then(Modifier.background(androidx.compose.ui.graphics.Brush.horizontalGradient(listOf(androidx.compose.ui.graphics.Color(0xFF3A4A5A), androidx.compose.ui.graphics.Color(0xFF6A5A3A))), RoundedCornerShape(10.dp)).height(110.dp))

private fun Modifier.subtitleBox(c: androidx.compose.ui.graphics.Color): Modifier = this.then(Modifier.background(c, RoundedCornerShape(4.dp)))
