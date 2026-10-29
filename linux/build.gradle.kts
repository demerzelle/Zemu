import org.jetbrains.compose.desktop.application.dsl.TargetFormat

plugins {
    kotlin("jvm") version "2.1.0"
    id("org.jetbrains.kotlin.plugin.compose") version "2.1.0"
    id("org.jetbrains.kotlin.plugin.serialization") version "2.1.0"
    id("org.jetbrains.compose") version "1.7.3"
}

// Same version as the Android app (release.sh bumps it there).
val zemuVersion = Regex("versionName = \"([^\"]+)\"").find(file("../app/build.gradle.kts").readText())!!.groupValues[1]
version = zemuVersion

// Java 17+ runs it (Ubuntu 22.04's default-jre and newer).
kotlin { compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17) } }
java { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }

/**
 * Small edits to shared files, applied to copies at build time so the Android sources stay the one
 * source of truth. The build fails if a patch no longer matches.
 */
val patches: Map<String, List<Pair<String, String>>> = mapOf(
    // Esc / Backspace need the nav controller to go back.
    "com/zemu/tv/ui/AppShell.kt" to listOf(
        """    val nav = rememberNavController()
""" to """    val nav = rememberNavController()
    com.zemu.tv.desktop.DesktopNav.controller = nav
""",
        """                    CardAction.ROW_OPTIONS -> menuRowOptions?.invoke()""" to
            """                    CardAction.ROW_OPTIONS -> menuRowOptions?.invoke()
                    CardAction.DOWNLOAD -> com.zemu.tv.desktop.CardDownload.start(m)""",
        // A steady logo glow: the breathing one repaints the whole window 60 times a second on desktop.
        """            val pulse = androidx.compose.animation.core.rememberInfiniteTransition(label = "logoGlow")
            val glow by pulse.animateFloat(
                0.35f, 1f,
                androidx.compose.animation.core.infiniteRepeatable(
                    androidx.compose.animation.core.tween(2600, easing = androidx.compose.animation.core.FastOutSlowInEasing),
                    androidx.compose.animation.core.RepeatMode.Reverse,
                ),
                label = "logoGlowAlpha",
            )""" to """            val glow = 0.7f""",
    ),
    // No animated themes on Linux: they're the heaviest part of the UI on slow machines.
    "com/zemu/tv/ui/theme/DynamicThemes.kt" to listOf(
        """fun of(name: String) = entries.firstOrNull { it.name == (RENAMED[name] ?: name) } ?: NONE""" to
            """fun of(@Suppress("UNUSED_PARAMETER") name: String) = NONE""",
    ),
    "com/zemu/tv/ui/kids/KidsMode.kt" to listOf(
        """DynamicTheme.entries.filter { !it.hidden }.forEach""" to """DynamicTheme.entries.filter { it == com.zemu.tv.ui.theme.DynamicTheme.NONE }.forEach""",
    ),
    // Android-only APIs in otherwise shared files.
    "com/zemu/tv/ui/theme/Theme.kt" to listOf(
        """    val effect = android.graphics.RenderEffect.createColorFilterEffect(android.graphics.ColorMatrixColorFilter(m))
    return graphicsLayer { renderEffect = effect.asComposeRenderEffect() }""" to """    return this""",
        """    val view = androidx.compose.ui.platform.LocalView.current
    androidx.compose.runtime.SideEffect {
        val window = (view.parent as? androidx.compose.ui.window.DialogWindowProvider)?.window ?: return@SideEffect
        window.addFlags(android.view.WindowManager.LayoutParams.FLAG_BLUR_BEHIND)
        window.attributes = window.attributes.apply { blurBehindRadius = 48 }
        window.setDimAmount(0.3f)
    }""" to "",
    ),
    "com/zemu/tv/ui/components/QrCode.kt" to listOf(
        "import android.graphics.Bitmap\n" to "",
        """Bitmap.createBitmap(pixels, m.width, m.height, Bitmap.Config.ARGB_8888).asImageBitmap()""" to
            """java.awt.image.BufferedImage(m.width, m.height, java.awt.image.BufferedImage.TYPE_INT_ARGB).apply { setRGB(0, 0, m.width, m.height, pixels, 0, m.width) }.toComposeImageBitmap()""",
        "import androidx.compose.ui.graphics.asImageBitmap" to "import androidx.compose.ui.graphics.toComposeImageBitmap",
    ),
    "com/zemu/tv/ui/components/CardMenu.kt" to listOf(
        """e.nativeKeyEvent.repeatCount > 0 -> true""" to """false -> true""",
        // Download from a card's menu: the movie, or every season of a show.
        """    MARK_WATCHED("Mark as watched"),""" to """    DOWNLOAD("Download"),
    MARK_WATCHED("Mark as watched"),""",
        """    add(if (watched) CardAction.MARK_UNWATCHED else CardAction.MARK_WATCHED)""" to
            """    if (com.zemu.tv.desktop.CardDownload.enabled()) add(CardAction.DOWNLOAD)
    add(if (watched) CardAction.MARK_UNWATCHED else CardAction.MARK_WATCHED)""",
    ),
    "com/zemu/tv/ui/details/DetailsScreen.kt" to listOf(
        "import android.content.Intent\n" to "",
        // Downloads ask first: what, how big, and where (with Change folder).
        """                    val err = downloads.start(m, vm.currentVideoId(), vm.episodeLabel(), rs.stream.raw.url.orEmpty(), rs.stream.raw.behaviorHints?.proxyHeaders?.request.orEmpty(), rs.stream.raw.behaviorHints?.filename, rs.stream.sizeBytes)
                    Toast.makeText(context, err ?: "Downloading. Find it under Downloads in the menu.", Toast.LENGTH_LONG).show()""" to
            """                    com.zemu.tv.desktop.DownloadPrompt.single(m, vm.currentVideoId(), vm.episodeLabel(), rs.stream)""",
        // Whole seasons / series: in the title's More menu, for series with downloads on.
        """                add(SheetAction("Refresh streams") { vm.reloadStreams() })""" to
            """                if (type == "series" && m.videos.isNotEmpty() && c.downloads.available && c.userStore.settings.value.downloads) {
                    season?.let { s -> add(SheetAction(if (s == 0) "Download the specials" else "Download season ${'$'}s") { com.zemu.tv.desktop.DownloadPrompt.season(m, s) }) }
                    if (vm.seasons.count { it != 0 } > 1) add(SheetAction("Download all seasons") { com.zemu.tv.desktop.DownloadPrompt.allSeasons(m) })
                }
                add(SheetAction("Refresh streams") { vm.reloadStreams() })""",
        // ...and next to the season chips, where people look for it.
        """                        onSeason = vm::selectSeason,
""" to """                        onSeason = vm::selectSeason,
                        onDownloadSeason = if (c.downloads.available && settings.downloads) ({ s -> com.zemu.tv.desktop.DownloadPrompt.season(m, s) }) else null,
                        onEpisodeMenu = { v -> com.zemu.tv.desktop.EpisodeMenu.open(m, v, play = { vm.selectEpisode(v, autoPlay = true) }, pick = { vm.selectEpisode(v) }) },
""",
        """    onSeason: (Int) -> Unit,
""" to """    onSeason: (Int) -> Unit,
    onDownloadSeason: ((Int) -> Unit)? = null,
    onEpisodeMenu: ((Video) -> Unit)? = null,
""",
        // Right-click (or hold A / Enter) on an episode: its own menu.
        """EpisodeCard(v, v.id == selected?.id, nextUp = v.id == nextUpId, progress = progress[v.id] ?: 0f, onFocused = { highlighted = v; onEpisodeFocused() }) { onEpisode(v) }""" to
            """EpisodeCard(v, v.id == selected?.id, nextUp = v.id == nextUpId, progress = progress[v.id] ?: 0f, onFocused = { highlighted = v; onEpisodeFocused() }, onLongClick = onEpisodeMenu?.let { f -> { f(v) } }) { onEpisode(v) }""",
        """private fun EpisodeCard(video: Video, selected: Boolean, nextUp: Boolean = false, progress: Float = 0f, onFocused: () -> Unit = {}, onClick: () -> Unit) {""" to
            """private fun EpisodeCard(video: Video, selected: Boolean, nextUp: Boolean = false, progress: Float = 0f, onFocused: () -> Unit = {}, onLongClick: (() -> Unit)? = null, onClick: () -> Unit) {""",
        """            onClick = onClick,
            modifier = Modifier.fillMaxWidth().aspectRatio(16f / 9f).onFocusChanged { if (it.isFocused) onFocused() }.touchClick(onClick),""" to
            """            onClick = onClick,
            onLongClick = onLongClick,
            modifier = Modifier.fillMaxWidth().aspectRatio(16f / 9f).onFocusChanged { if (it.isFocused) onFocused() }.touchClick(onClick, onLongClick),""",
        """                TvChip(if (s == 0) "Specials" else "Season ${'$'}s", selected = s == season, onClick = { onSeason(s) })
            }""" to """                TvChip(if (s == 0) "Specials" else "Season ${'$'}s", selected = s == season, onClick = { onSeason(s) })
            }
            if (onDownloadSeason != null && season != null) item(key = "download-season") {
                TvChip("⬇  Download ${'$'}{if (season == 0) "specials" else "season ${'$'}season"}", selected = false, onClick = { onDownloadSeason(season) })
            }""",
    ),
    // Zemu's own player screen, drawn in a transparent window over mpv's video.
    // Rows and cards; resting the mouse on a card for 3 s shows it in the hero.
    "com/zemu/tv/ui/components/Cards.kt" to listOf(
        // Rows don't restore their last poster: on desktop, entering a row above through it bounced
        // focus out to the row's name, so Up skipped every row's posters.
        // Mouse-only scrolling too: arrows or hovering an end (com.zemu.tv.desktop.MouseScroll).
        """        LazyRow(
            state = rememberLazyListState(),
            modifier = Modifier.focusRestorer(),
            contentPadding = contentPadding,
            horizontalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            itemsIndexed(items, key = { _, it -> key(it) }) { index, item ->
                val req = requesters[key(item)]
                itemContent(index, item, if (req != null) Modifier.focusRequester(req) else Modifier)
            }
        }
""" to """        com.zemu.tv.desktop.MouseScroll { rowState ->
        LazyRow(
            state = rowState,
            modifier = Modifier,
            contentPadding = contentPadding,
            horizontalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            itemsIndexed(items, key = { _, it -> key(it) }) { index, item ->
                val req = requesters[key(item)]
                itemContent(index, item, if (req != null) Modifier.focusRequester(req) else Modifier)
            }
        }
        }
""",
        """            .onFocusChanged { focused = it.isFocused; if (it.isFocused) onFocused(meta) }""" to
            """            .onFocusChanged { focused = it.isFocused; if (it.isFocused) onFocused(meta) }
            .then(com.zemu.tv.desktop.hoverHold { onFocused(meta) })""",
        """            .onFocusChanged { if (it.isFocused) onFocused(meta) }""" to
            """            .onFocusChanged { if (it.isFocused) onFocused(meta) }
            .then(com.zemu.tv.desktop.hoverHold { onFocused(meta) })""",
    ),
    // Top 10 Today rows (Home: movies and series; Movies, Series, Anime: their own).
    "com/zemu/tv/data/Tmdb.kt" to listOf(
        """    private fun TmdbItem.toMeta(type: String): Meta {""" to """    /** Today's trending titles (TMDB /trending/<movie|tv>/day). Cached for 30 minutes. */
    suspend fun trendingToday(type: String): List<Meta> {
        if (!enabled) return emptyList()
        val media = if (type == "series") "tv" else "movie"
        val key = "trending/${'$'}media"
        val now = System.currentTimeMillis()
        discoverCache[key]?.let { (at, list) -> if (now - at < 30 * 60_000L) return list }
        val body = get("/trending/${'$'}media/day")
        val list = withContext(Dispatchers.Default) {
            json.decodeFromString(TmdbPage.serializer(), body).results.filter { it.posterPath != null }.map { it.toMeta(type) }
        }
        discoverCache[key] = now to list
        return list
    }

    private fun TmdbItem.toMeta(type: String): Meta {""",
    ),
    "com/zemu/tv/ui/home/HomeViewModel.kt" to listOf(
        """    private val baseRows = combine(ownRows, c.trakt.friendRecs, c.userStore.watchLater) { rows, recs, later ->
        if (!isHome) return@combine rows""" to """    private val baseRows = combine(ownRows, c.trakt.friendRecs, c.userStore.watchLater, com.zemu.tv.desktop.Top10.rows(c, page)) { rows, recs, later, top10 ->
        if (!isHome) return@combine (rows + top10).sortedBy { it.priority }""",
        """            addAll(rows)
            if (recs.isNotEmpty())""" to """            addAll(rows)
            addAll(top10)
            if (recs.isNotEmpty())""",
    ),
    "com/zemu/tv/ui/home/HomeScreen.kt" to listOf(
        """                    ) { _, m, mod ->
                        when (row.style) {""" to """                    ) { i, m, mod ->
                        when (row.style) {""",
        """                            else PosterCard(m, onClick = { onOpen(m) }, modifier = mod, onFocused = onFocus, badge = row.badges[m.id] ?: row.match[m.id]?.let { "${'$'}it%" })""" to
            """                            else com.zemu.tv.desktop.Ranked(if (row.key.startsWith("top10-")) i + 1 else null) { PosterCard(m, onClick = { onOpen(m) }, modifier = mod, onFocused = onFocus, badge = row.badges[m.id] ?: row.match[m.id]?.let { "${'$'}it%" }) }""",
    ),
    // The picture starts 22% in: fully covered there, so its left edge never shows on wide screens.
    "com/zemu/tv/ui/components/Hero.kt" to listOf(
        """                    0f to Palette.Background,
                    0.3f to Palette.Background.copy(alpha = 0.92f),
                    0.6f to Palette.Background.copy(alpha = 0.35f),""" to """                    0f to Palette.Background,
                    0.25f to Palette.Background,
                    0.42f to Palette.Background.copy(alpha = 0.85f),
                    0.65f to Palette.Background.copy(alpha = 0.35f),""",
    ),
    "com/zemu/tv/player/PlayerScreen.kt" to listOf(
        """            .background(Color.Black)
            .onPreviewKeyEvent { e ->
                lastInteraction = SystemClock.uptimeMillis()""" to """            .background(Color.Transparent)
            .onPreviewKeyEvent { e ->
                lastInteraction = SystemClock.uptimeMillis()""",
        // Esc and Backspace are the desktop's Back.
        """if (e.key == Key.Back && dialog == null && (menu || cardVisible || skipVisible))""" to
            """if ((e.key == Key.Back || e.key == Key.Escape || e.key == Key.Backspace) && dialog == null && (menu || cardVisible || skipVisible))""",
        // Controller buttons under the controls they trigger (only while a controller is connected).
        """                            color = if (item.active) Palette.Accent else Color.White.copy(alpha = 0.55f))
                    }""" to """                            color = if (item.active) Palette.Accent else Color.White.copy(alpha = 0.55f))
                    }
                    com.zemu.tv.desktop.PadHint(item.key)""",
        """        Text("Hold OK on Audio or Subtitles to see every track",""" to """        Text(com.zemu.tv.desktop.trackPanelHint(),""",
        // Full screen, next to My List.
        """        add(MenuItem("fav", "My List", if (inMyList) "Added" else null, if (inMyList) AppIcons.Heart else AppIcons.HeartOutline, active = inMyList) { onToggleMyList() })""" to
            """        add(MenuItem("fav", "My List", if (inMyList) "Added" else null, if (inMyList) AppIcons.Heart else AppIcons.HeartOutline, active = inMyList) { onToggleMyList() })
        add(MenuItem("fullscreen", "Full screen", if (com.zemu.tv.desktop.FullScreen.on) "On" else null, com.zemu.tv.desktop.FullScreen.icon, active = com.zemu.tv.desktop.FullScreen.on) { com.zemu.tv.desktop.FullScreen.toggle() })""",
        // A Back button before the title, for the mouse.
        """                    Column(Modifier.weight(1f)) {
                        Text(a.title,""" to """                    com.zemu.tv.desktop.PlayerBackButton { a.stop() }
                    Column(Modifier.weight(1f)) {
                        Text(a.title,""",
    ),
    // Where downloads go, with a controller-friendly folder browser.
    // Desktop sound packs (Settings → Sound effects), "lofi" being the theme's own sounds made soft.
    "com/zemu/tv/data/Models.kt" to listOf(
        """    val soundEffects: Boolean = true,
""" to """    val soundEffects: Boolean = true,
    val soundPack: String = "lofi",
    /** Mouse-only row scrolling: "arrows" (buttons at the ends) or "edges" (hover near an end). */
    val mouseRowScroll: String = "arrows",
    /** Hover-scroll speed, 1–5 (com.zemu.tv.desktop.EDGE_SPEEDS). */
    val edgeScrollSpeed: Int = 3,
""",
    ),
    "com/zemu/tv/ui/settings/SettingsScreen.kt" to listOf(
        """    "Manage addons" to SettingsCategory.ACCOUNTS,""" to """    "Manage addons" to SettingsCategory.ACCOUNTS,
    "Scrolling rows with the mouse (arrows, hover speed)" to SettingsCategory.BROWSING,""",
        """    group("animated", "Animated themes"""" to """    if (false) group("animated", "Animated themes"""",
        """ On Android 12 and newer, menus also blur what's behind them.""" to "",
        // More zoom steps: on top of the system's display scale, for TVs and small screens alike.
        """            listOf(80, 90, 100, 110, 125, 150).forEach { z ->""" to """            listOf(60, 70, 80, 90, 100, 110, 125, 150, 175, 200).forEach { z ->""",
        """            vm.update { it.copy(hideWatchedInRows = !it.hideWatchedInRows) }
        }
""" to """            vm.update { it.copy(hideWatchedInRows = !it.hideWatchedInRows) }
        }
    }
    group("mouse", "Scrolling rows with the mouse", "Arrow buttons at the ends of a row, or hover near an end to scroll it. Only while you use the mouse, not the keyboard or a controller.") {
        @OptIn(androidx.compose.foundation.layout.ExperimentalLayoutApi::class)
        androidx.compose.foundation.layout.FlowRow(Modifier.padding(top = 6.dp, bottom = 6.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            TvChip("Arrow buttons", settings.mouseRowScroll == "arrows", { vm.update { it.copy(mouseRowScroll = "arrows") } })
            TvChip("Hover an edge", settings.mouseRowScroll == "edges", { vm.update { it.copy(mouseRowScroll = "edges") } })
        }
        if (settings.mouseRowScroll == "edges") {
            Text("Hover scroll speed", fontSize = 15.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(top = 6.dp))
            @OptIn(androidx.compose.foundation.layout.ExperimentalLayoutApi::class)
            androidx.compose.foundation.layout.FlowRow(Modifier.padding(top = 6.dp, bottom = 6.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf(1 to "Slowest", 2 to "Slow", 3 to "Medium", 4 to "Fast", 5 to "Fastest").forEach { (v, label) ->
                    TvChip(label, settings.edgeScrollSpeed == v, { vm.update { it.copy(edgeScrollSpeed = v) } })
                }
            }
        }
""",
        """            vm.update { it.copy(soundEffects = !it.soundEffects) }
        }
""" to """            vm.update { it.copy(soundEffects = !it.soundEffects) }
        }
        if (settings.soundEffects) {
            Text("Sound pack", fontSize = 15.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(top = 6.dp))
            @OptIn(androidx.compose.foundation.layout.ExperimentalLayoutApi::class)
            androidx.compose.foundation.layout.FlowRow(Modifier.padding(top = 6.dp, bottom = 6.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                com.zemu.tv.ui.SoundFx.PACKS.forEach { (k, label) ->
                    TvChip(label, settings.soundPack == k, { vm.update { it.copy(soundPack = k) } })
                }
            }
        }
""",
        """            vm.update { it.copy(downloads = !it.downloads) }
        }
""" to """            vm.update { it.copy(downloads = !it.downloads) }
        }
        val downloadFolder = com.zemu.tv.ZemuApp.container.downloads.folderState.collectAsStateWithLifecycle().value
        ValueRow("Download folder", downloadFolder.path) { com.zemu.tv.desktop.FolderSetting.open = true }
""",
    ),
    // No speech recognizer on desktop.
    "com/zemu/tv/ui/search/SearchScreen.kt" to listOf(
        """import android.content.Intent
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
""" to "",
        """        val voiceIntent = remember {
            Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
                .putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                .putExtra(RecognizerIntent.EXTRA_PROMPT, "Search movies and series")
        }
        // Only devices with a speech recognizer (a mic remote, Google Assistant, ...) get the button.
        val canVoice = remember {
            SpeechRecognizer.isRecognitionAvailable(context) ||
                context.packageManager.queryIntentActivities(voiceIntent, 0).isNotEmpty()
        }
        val voice = rememberLauncherForActivityResult(ActivityResultContracts.StartActivityForResult()) { r ->
            r.data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)?.firstOrNull()?.let(vm::setQuery)
        }
""" to """        val canVoice = false
""",
        """runCatching { voice.launch(voiceIntent) }""" to "",
    ),
)
// The Android app's Kotlin is shared; files that are Android-only are replaced in src/main/kotlin.
val replaced = listOf(
    "com/zemu/tv/ZemuApp.kt",
    "com/zemu/tv/MainActivity.kt",
    "com/zemu/tv/AppContainer.kt",
    // The player screen (PlayerScreen.kt) is shared; the ExoPlayer side is replaced by MpvSession.
    "com/zemu/tv/player/PlayerActivity.kt",
    "com/zemu/tv/player/Playback.kt",
    "com/zemu/tv/player/TrailerActivity.kt",
    "com/zemu/tv/player/YouTubeEmbed.kt",
    "com/zemu/tv/player/DecoderMode.kt",
    "com/zemu/tv/launcher/",
    "com/zemu/tv/data/Downloads.kt",
    "com/zemu/tv/data/Updater.kt",
    "com/zemu/tv/data/ProfileStore.kt",
    "com/zemu/tv/streams/DeviceCapabilities.kt",
    "com/zemu/tv/ui/settings/ConfigureActivity.kt",
    "com/zemu/tv/ui/components/ZemuLoader.kt",
    "com/zemu/tv/ui/components/Haptics.kt",
    "com/zemu/tv/ui/SoundFx.kt",
)
fun isReplaced(path: String) = replaced.any { path == it || (it.endsWith("/") && path.startsWith(it)) }

/** Edits applied to every shared file: dialogs get arrow-key / controller navigation of their own. */
val globalPatches = listOf(
    "import androidx.compose.ui.window.Dialog\n" to "import com.zemu.tv.desktop.DpadDialog as Dialog\n",
    "androidx.compose.ui.window.Dialog(" to "com.zemu.tv.desktop.DpadDialog(",
)
val sharedRoot = file("../app/src/main/java")
val patchedPaths: Set<String> = patches.keys + sharedRoot.walk()
    .filter { it.isFile && it.extension == "kt" }
    .map { it.relativeTo(sharedRoot).invariantSeparatorsPath }
    .filter { !isReplaced(it) && globalPatches.any { (old, _) -> old in file("../app/src/main/java/$it").readText() } }

val patchedDir = layout.buildDirectory.dir("patched")
val patchShared by tasks.registering {
    inputs.property("patches", patches.toString() + globalPatches.toString())
    inputs.files(patchedPaths.map { "../app/src/main/java/$it" })
    outputs.dir(patchedDir)
    doLast {
        patchedDir.get().asFile.deleteRecursively()
        patchedPaths.forEach { path ->
            var text = file("../app/src/main/java/$path").readText()
            patches[path].orEmpty().forEach { (old, new) ->
                check(old in text) { "Patch for $path no longer matches: $old" }
                text = text.replace(old, new)
            }
            globalPatches.forEach { (old, new) -> text = text.replace(old, new) }
            patchedDir.get().file(path).asFile.apply { parentFile.mkdirs() }.writeText(text)
        }
    }
}
tasks.named("compileKotlin") { dependsOn(patchShared) }
val androidOnly = replaced + patchedPaths // the patched copies replace these
sourceSets.main {
    kotlin.srcDirs("../app/src/main/java", patchedDir)
    kotlin.exclude { e ->
        val shared = e.file.path.contains("/app/src/main/java/")
        shared && androidOnly.any { e.relativePath.pathString == it || (it.endsWith("/") && e.relativePath.pathString.startsWith(it)) }
    }
    resources.srcDirs("../app/src/main/assets", "../app/src/main/res/drawable-nodpi", "../app/src/main/res/font", "src/main/resources")
}

dependencies {
    implementation(compose.desktop.currentOs)
    // Linux natives for both PCs and ARM boards (Raspberry Pi etc.), whatever OS builds the jar.
    implementation(compose.desktop.linux_x64)
    implementation(compose.desktop.linux_arm64)
    implementation(compose.material3)
    implementation("org.jetbrains.compose.material:material-icons-core:1.7.3")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-swing:1.9.0")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("com.google.zxing:core:3.5.3")
    implementation("androidx.datastore:datastore-preferences-core:1.1.1")
    implementation("org.jetbrains.androidx.lifecycle:lifecycle-viewmodel-compose:2.8.4")
    implementation("org.jetbrains.androidx.lifecycle:lifecycle-runtime-compose:2.8.4")
    implementation("org.jetbrains.androidx.navigation:navigation-compose:2.8.0-alpha12")
    implementation("io.coil-kt.coil3:coil-compose:3.0.4")
    implementation("io.coil-kt.coil3:coil-network-okhttp:3.0.4")
    testImplementation(kotlin("test"))
}

/** JDK internals Zemu reads its window's X11 id from, so mpv can draw inside it (PlayerHost.kt). */
val x11Opens = "java.desktop/sun.awt java.desktop/sun.awt.X11"

compose.desktop {
    application {
        mainClass = "com.zemu.tv.desktop.MainKt"
        jvmArgs += listOf("-Xss2m", "-Xmx512m", "-XX:+UseSerialGC", "-XX:TieredStopAtLevel=1") +
            x11Opens.split(' ').map { "--add-opens=$it=ALL-UNNAMED" }
        nativeDistributions {
            // jpackage only builds packages for the OS it runs on.
            if (System.getProperty("os.name").startsWith("Linux")) targetFormats(TargetFormat.Deb, TargetFormat.Rpm, TargetFormat.AppImage)
            packageName = "zemu"
            packageVersion = zemuVersion
            description = "Stremio-addon streaming client"
            vendor = "Zemu"
            modules("java.net.http", "jdk.unsupported", "java.naming", "java.sql")
            linux {
                iconFile.set(project.file("packaging/zemu.png"))
                shortcut = true
                appCategory = "AudioVideo"
                debMaintainer = "zemu@users.noreply.github.com"
            }
        }
    }
}

tasks.jar { manifest { attributes("Implementation-Version" to zemuVersion) } }

/** One runnable jar with the Linux x64 and ARM64 natives only (works from any build OS). */
val linuxJar by tasks.registering(Jar::class) {
    archiveFileName.set("zemu.jar")
    destinationDirectory.set(layout.buildDirectory.dir("linux"))
    manifest { attributes("Main-Class" to "com.zemu.tv.desktop.MainKt", "Implementation-Version" to zemuVersion, "Add-Opens" to x11Opens) }
    duplicatesStrategy = DuplicatesStrategy.EXCLUDE
    from(sourceSets.main.get().output)
    dependsOn(configurations.runtimeClasspath)
    from({
        configurations.runtimeClasspath.get()
            .filterNot { Regex("skiko-awt-runtime-(macos|windows)").containsMatchIn(it.name) }
            .map { if (it.isDirectory) it else zipTree(it) }
    })
    exclude("META-INF/*.SF", "META-INF/*.DSA", "META-INF/*.RSA", "META-INF/versions/9/module-info.class")
}

/** Zemu-Linux-<version>.tar.gz: the jar, installer, launcher entry and icon (what GitHub Releases carries). */
val linuxTarball by tasks.registering(Tar::class) {
    archiveFileName.set("Zemu-Linux-$zemuVersion.tar.gz")
    destinationDirectory.set(layout.buildDirectory.dir("linux"))
    compression = Compression.GZIP
    into("zemu") {
        from(linuxJar)
        from("packaging") { filePermissions { unix("755") }; include("install.sh") }
        from("packaging") { exclude("install.sh") }
    }
}

tasks.test {
    // Tests get their own data and cache folders.
    environment("XDG_DATA_HOME", layout.buildDirectory.dir("tmp/test-data").get().asFile.path)
    environment("XDG_CACHE_HOME", layout.buildDirectory.dir("tmp/test-cache").get().asFile.path)
    systemProperty("zemu.testClip", layout.buildDirectory.file("testvid/clip.mkv").get().asFile.path)
}

// src/main/resources is a default resource folder and also listed above.
tasks.processResources { duplicatesStrategy = DuplicatesStrategy.EXCLUDE }
