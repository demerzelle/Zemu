package com.zemu.tv.ui.onboarding

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.focusGroup
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusProperties
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.tv.material3.Text
import com.zemu.tv.AppContainer
import com.zemu.tv.data.AppSettings
import com.zemu.tv.data.SUB_MODES
import com.zemu.tv.data.subMode
import com.zemu.tv.streams.Languages
import com.zemu.tv.ui.SoundFx
import com.zemu.tv.ui.components.QrCode
import com.zemu.tv.ui.components.SubtitleStyleEditor
import com.zemu.tv.ui.components.TvButton
import com.zemu.tv.ui.components.TvChip
import com.zemu.tv.ui.settings.DebridSection
import com.zemu.tv.ui.settings.LanguageDialog
import com.zemu.tv.ui.settings.RemoteInputServer
import com.zemu.tv.ui.settings.SubtitlePreview
import com.zemu.tv.ui.settings.ThemePicker
import com.zemu.tv.ui.settings.toggle
import com.zemu.tv.ui.theme.DynamicTheme
import com.zemu.tv.ui.theme.Palette
import com.zemu.tv.ui.theme.glassPanel
import kotlinx.coroutines.launch

/** Bumped when setup gains a step everyone should see. [AppSettings.setupVersion] -1 = run the whole setup again. */
const val SETUP_VERSION = 1

private enum class Step(val title: String, val blurb: String, val required: Boolean) {
    LANGUAGES("Your languages", "Zemu plays these whenever a stream has them, whatever the file plays first.", true),
    SUBTITLES("Subtitles", "When they show, and how they look.", true),
    ADDONS("Get something to watch", "Addons find the streams. Scan the code to paste addon links from your phone; they install here.", false),
    DEBRID("Link a debrid service", "Optional: with a Real-Debrid, AllDebrid or similar account, streams start faster and play more reliably.", false),
    LOOK("Make it yours", "A color theme and the sounds Zemu makes. Change them any time in Settings.", false),
}

/**
 * Setup after the tour. New users ([full]: no stream addons yet, or "Run setup again") get every step;
 * people updating to 1.1 confirm their subtitles and the look. Languages and subtitles can't be skipped.
 */
@OptIn(androidx.compose.ui.ExperimentalComposeUiApi::class)
@Composable
fun SetupFlow(c: AppContainer, full: Boolean, onDone: (openAddons: Boolean) -> Unit) {
    val steps = if (full) Step.entries.toList() else listOf(Step.SUBTITLES, Step.LOOK)
    val settings by c.userStore.settings.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()
    fun update(t: (AppSettings) -> AppSettings) { scope.launch { c.userStore.updateSettings(t) } }
    var at by remember { mutableStateOf(0) }
    var done by remember { mutableStateOf(false) }
    // New users start on "only when needed"; everyone else on what they had.
    LaunchedEffect(Unit) { if (settings.subtitleMode.isEmpty() && full) update { it.copy(subtitleMode = "auto") } }

    val primary = remember { FocusRequester() }
    Box(
        Modifier
            .fillMaxSize()
            .background(Palette.Background.copy(alpha = 0.94f))
            // Nothing behind setup is reachable while it's up.
            .focusProperties { exit = { FocusRequester.Cancel } }
            .focusGroup(),
        contentAlignment = Alignment.Center,
    ) {
        Column(
            // Full height with the buttons pinned at the bottom: only the step's own content scrolls, so
            // Continue is always on screen however small the TV's layout is.
            Modifier.widthIn(max = 760.dp).fillMaxWidth().then(if (done) Modifier else Modifier.fillMaxHeight())
                .padding(horizontal = 40.dp, vertical = 24.dp)
                .glassPanel(com.zemu.tv.ui.theme.boxy(RoundedCornerShape(18.dp))).padding(horizontal = 36.dp, vertical = 22.dp),
        ) {
            if (done) {
                Text("You're all set", fontSize = 30.sp, fontWeight = FontWeight.Bold)
                Text(
                    "Your choices are saved. Everything here is in Settings, along with Trakt, profiles and Kids Mode, and Settings → Updates & storage can run this setup or the tour again.",
                    color = Palette.TextSecondary, fontSize = 16.sp, modifier = Modifier.padding(top = 10.dp, bottom = 22.dp),
                )
                TvButton("Start watching", onClick = {
                    // Saved here, not on Finish: saving closes setup, and this screen would never show.
                    update { it.copy(setupVersion = SETUP_VERSION) }
                    onDone(full && !c.addons.hasStreamAddons)
                }, primary = true, modifier = Modifier.focusRequester(primary))
                LaunchedEffect(Unit) { runCatching { primary.requestFocus() } }
                return@Column
            }
            val step = steps[at]
            // Progress: a dot per step.
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Step ${at + 1} of ${steps.size}", color = Palette.TextSecondary, fontSize = 14.sp)
                Spacer(Modifier.width(14.dp))
                steps.indices.forEach { i ->
                    Box(Modifier.padding(end = 6.dp).size(if (i == at) 10.dp else 7.dp).background(if (i <= at) Palette.Accent else Palette.TextSecondary.copy(alpha = 0.35f), CircleShape))
                }
            }
            AnimatedContent(
                step,
                modifier = Modifier.weight(1f),
                transitionSpec = { (slideInHorizontally { it / 6 } + fadeIn()) togetherWith (slideOutHorizontally { -it / 6 } + fadeOut()) },
                label = "setupStep",
            ) { s ->
                Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
                    Text(s.title, fontSize = 30.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 14.dp))
                    Text(s.blurb, color = Palette.TextSecondary, fontSize = 16.sp, modifier = Modifier.padding(top = 6.dp, bottom = 18.dp))
                    when (s) {
                        Step.LANGUAGES -> LanguagesStep(settings, ::update)
                        Step.SUBTITLES -> SubtitlesStep(settings, ::update)
                        Step.ADDONS -> AddonsStep(c)
                        Step.DEBRID -> DebridSection(c, phoneAddress = null)
                        Step.LOOK -> LookStep(settings, ::update)
                    }
                }
            }
            Row(Modifier.fillMaxWidth().padding(top = 18.dp), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                if (at > 0) TvButton("Back", onClick = { at-- })
                Spacer(Modifier.weight(1f))
                if (!step.required) TvButton("Skip", onClick = { if (at < steps.lastIndex) at++ else done = true })
                TvButton(
                    if (at < steps.lastIndex) "Continue" else "Finish",
                    onClick = {
                        if (at < steps.lastIndex) at++
                        else done = true
                    },
                    primary = true,
                    modifier = Modifier.focusRequester(primary),
                )
            }
            LaunchedEffect(at) { runCatching { primary.requestFocus() } }
        }
    }
}

@Composable
private fun LanguagesStep(settings: AppSettings, update: ((AppSettings) -> AppSettings) -> Unit) {
    var dialog by remember { mutableStateOf<String?>(null) }
    fun names(l: List<String>, empty: String) = l.joinToString { Languages.displayName(it) }.ifEmpty { empty }
    Choice("Audio", names(settings.audioLanguages, "Any")) { dialog = "audio" }
    Choice("Subtitles", names(settings.subtitleLanguages, "None")) { dialog = "subs" }
    Choice("Anime audio", names(settings.animeAudioLanguages, "Same as above")) { dialog = "anime" }
    Text("Titles from the Anime page use the anime audio. In order of preference: the first one a stream has wins.", color = Palette.TextSecondary, fontSize = 13.sp, modifier = Modifier.padding(top = 8.dp))
    when (dialog) {
        "audio" -> LanguageDialog("Audio languages", settings.audioLanguages, onDismiss = { dialog = null }) { code -> update { it.copy(audioLanguages = it.audioLanguages.toggle(code)) } }
        "subs" -> LanguageDialog("Subtitle languages", settings.subtitleLanguages, onDismiss = { dialog = null }) { code -> update { it.copy(subtitleLanguages = it.subtitleLanguages.toggle(code)) } }
        "anime" -> LanguageDialog("Anime audio languages", settings.animeAudioLanguages, onDismiss = { dialog = null }) { code -> update { it.copy(animeAudioLanguages = it.animeAudioLanguages.toggle(code)) } }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun SubtitlesStep(settings: AppSettings, update: ((AppSettings) -> AppSettings) -> Unit) {
    Label("Movies and shows")
    FlowRow(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        SUB_MODES.forEach { (k, label) -> TvChip(label, settings.subMode == k, { update { it.copy(subtitleMode = k) } }) }
    }
    Label("Anime")
    FlowRow(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        SUB_MODES.forEach { (k, label) -> TvChip(label, settings.animeSubtitleMode == k, { update { it.copy(animeSubtitleMode = k) } }) }
    }
    Label("Look")
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        TvChip("Original formatting", settings.subtitleOriginalStyle, { update { it.copy(subtitleOriginalStyle = true) } })
        TvChip("Zemu's style", !settings.subtitleOriginalStyle, { update { it.copy(subtitleOriginalStyle = false) } })
    }
    if (settings.subtitleOriginalStyle) {
        Text("Subtitles show with the fonts, colors and positions the file gives them.", color = Palette.TextSecondary, fontSize = 13.sp, modifier = Modifier.padding(top = 10.dp))
    } else {
        Spacer(Modifier.height(8.dp))
        SubtitlePreview(settings)
        // The editor's own "Custom style" switch would repeat the chips above.
        SubtitleStyleEditor(settings, showModeSwitch = false, update = update)
    }
}

/** Addon links pasted on a phone install here, through the same page as Settings and Addons. */
@Composable
private fun AddonsStep(c: AppContainer) {
    val scope = rememberCoroutineScope()
    var address by remember { mutableStateOf<String?>(null) }
    var message by remember { mutableStateOf<String?>(null) }
    val server = remember { RemoteInputServer { text -> c.handleRemoteInput(text).also { message = it } } }
    DisposableEffect(Unit) {
        address = server.start(scope)
        onDispose { server.stop() }
    }
    val installed by c.addons.addons.collectAsStateWithLifecycle()
    val streams = installed.filter { it.manifest.hasResource("stream") }
    Row(verticalAlignment = Alignment.CenterVertically) {
        address?.let { QrCode(it, 150.dp, Modifier.padding(end = 24.dp)) }
        Column(Modifier.weight(1f)) {
            Text(address?.let { "Or open $it on a phone on the same Wi-Fi." } ?: "Connect to Wi-Fi to paste links from your phone.", fontSize = 16.sp)
            Text(
                if (streams.isEmpty()) "No stream addons yet. You can also browse addons after setup, or link a debrid account on the next step to get one set up for you."
                else "Stream addons: ${streams.joinToString { it.manifest.name }}",
                color = if (streams.isEmpty()) Palette.TextSecondary else Palette.Cached, fontSize = 14.sp, modifier = Modifier.padding(top = 8.dp),
            )
            message?.let { Text(it, color = Palette.Accent, fontSize = 14.sp, modifier = Modifier.padding(top = 8.dp)) }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun LookStep(settings: AppSettings, update: ((AppSettings) -> AppSettings) -> Unit) {
    Label("Color theme")
    ThemePicker(settings, update)
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        TvChip("Dark", !settings.lightMode, { update { it.copy(lightMode = false) } })
        TvChip("Light", settings.lightMode, { update { it.copy(lightMode = true) } })
    }
    // Animated themes aren't on every platform (Linux leaves them out).
    val animated = DynamicTheme.entries.filter { !it.hidden && it != DynamicTheme.NONE && DynamicTheme.of(it.name) == it }
    if (animated.isNotEmpty()) {
        Label("Animated theme")
        FlowRow(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            TvChip("None", settings.dynamicTheme == DynamicTheme.NONE.name, { update { it.copy(dynamicTheme = DynamicTheme.NONE.name) } })
            animated.forEach { d -> TvChip(d.label, settings.dynamicTheme == d.name, { update { it.copy(dynamicTheme = d.name) } }) }
        }
    }
    Label("Sounds")
    FlowRow(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        TvChip("Off", !settings.soundEffects, { update { it.copy(soundEffects = false) } })
        SoundFx.PACKS.forEach { (k, label) ->
            TvChip(label, settings.soundEffects && settings.soundPack == k, { update { it.copy(soundEffects = true, soundPack = k) } })
        }
    }
}

@Composable
private fun Label(text: String) = Text(text, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(top = 16.dp, bottom = 8.dp))

@Composable
private fun Choice(title: String, value: String, onClick: () -> Unit) {
    com.zemu.tv.ui.components.FocusSurface(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
        shape = com.zemu.tv.ui.theme.boxy(RoundedCornerShape(10.dp)),
        containerColor = Palette.Surface,
        focusedScale = 1.01f,
    ) {
        Row(Modifier.padding(horizontal = 18.dp, vertical = 14.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(title, fontSize = 16.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
            Text(value, color = androidx.tv.material3.LocalContentColor.current.copy(alpha = 0.72f), fontSize = 14.sp, maxLines = 1)
        }
    }
}
