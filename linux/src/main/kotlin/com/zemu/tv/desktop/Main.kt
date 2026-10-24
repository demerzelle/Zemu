package com.zemu.tv.desktop

import android.widget.Toast
import androidx.activity.compose.BackDispatcher
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusDirection
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onKeyEvent
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.input.key.isAltPressed
import androidx.compose.ui.input.pointer.isBackPressed
import androidx.compose.ui.input.pointer.PointerEventType
import androidx.compose.ui.input.pointer.onPointerEvent
import androidx.compose.ui.platform.Configuration
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.res.loadImageBitmap
import androidx.compose.ui.graphics.painter.BitmapPainter
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Window
import androidx.compose.ui.window.WindowPlacement
import androidx.compose.ui.window.application
import androidx.compose.ui.window.rememberWindowState
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.NavHostController
import androidx.tv.material3.Text
import coil3.ImageLoader
import coil3.PlatformContext
import coil3.SingletonImageLoader
import coil3.disk.DiskCache
import coil3.memory.MemoryCache
import coil3.network.okhttp.OkHttpNetworkFetcherFactory
import coil3.request.crossfade
import com.zemu.tv.LocalSwitchProfile
import com.zemu.tv.PendingOpen
import com.zemu.tv.ZemuApp
import com.zemu.tv.player.MpvSession
import com.zemu.tv.ui.AppShell
import com.zemu.tv.ui.SoundFx
import com.zemu.tv.ui.profiles.ProfilePicker
import com.zemu.tv.ui.theme.ZemuTheme
import com.zemu.tv.ui.theme.resolvedColors
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import okio.Path.Companion.toOkioPath
import java.io.File

/** AppShell's nav controller, so Esc can go back a page. */
object DesktopNav {
    var controller: NavHostController? = null
}

/** Esc, Backspace, the mouse's back button: the open screen's own Back first, then the previous page. */
private fun goBack() {
    SoundFx.play(SoundFx.Event.BACK)
    if (BackDispatcher.dispatch()) return
    DesktopNav.controller?.let { if (it.previousBackStackEntry != null) it.popBackStack() }
}

fun main() {
    setUpImages()
    firstRun()

    application {
        val windowState = rememberWindowState(placement = WindowPlacement.Maximized, size = DpSize(1280.dp, 800.dp))
        val icon = remember { BitmapPainter(ZemuApp::class.java.classLoader.getResourceAsStream("logo_mark.png")!!.use(::loadImageBitmap)) }
        Window(onCloseRequest = ::exitApplication, state = windowState, title = "Zemu", icon = icon) {
            SideEffect { window.minimumSize = java.awt.Dimension(960, 600) }
            // Back to the front when the player closes.
            SideEffect { MpvSession.onClosed = { java.awt.EventQueue.invokeLater { window.toFront(); window.requestFocus() } } }
            App(onToggleFullscreen = {
                windowState.placement = if (windowState.placement == WindowPlacement.Fullscreen) WindowPlacement.Maximized else WindowPlacement.Fullscreen
            })
        }
    }
}

@OptIn(androidx.compose.ui.ExperimentalComposeUiApi::class)
@androidx.compose.runtime.Composable
private fun App(onToggleFullscreen: () -> Unit) {
    val app = ZemuApp
    var profileId by remember { mutableStateOf(app.container.profileId) }
    val profiles by app.profiles.profiles.collectAsStateWithLifecycle()
    val kids by app.profiles.kids.collectAsStateWithLifecycle()
    var picking by remember { mutableStateOf(profiles.size > 1 && !app.profileChosen && !app.profiles.skipPicker.value && !kids.on) }
    var lastInput by remember { mutableLongStateOf(System.currentTimeMillis()) }
    var screensaverOn by remember { mutableStateOf(false) }
    var saverCurrent by remember { mutableStateOf<com.zemu.tv.data.ScreensaverSlide?>(null) }
    val focus = LocalFocusManager.current

    BoxWithConstraints(
        Modifier.fillMaxSize()
            .onPointerEvent(PointerEventType.Move) { lastInput = System.currentTimeMillis() }
            .onPointerEvent(PointerEventType.Press) { e ->
                lastInput = System.currentTimeMillis()
                // Mouse "back" side button.
                if (e.buttons.isBackPressed) goBack()
            }
            .onPreviewKeyEvent { e ->
                lastInput = System.currentTimeMillis()
                if (screensaverOn) {
                    if (e.type == KeyEventType.KeyDown) {
                        screensaverOn = false
                        if (e.key == Key.Enter || e.key == Key.NumPadEnter) saverCurrent?.let { PendingOpen.play = true; PendingOpen.target = it.meta.type to it.meta.id }
                    }
                    return@onPreviewKeyEvent true
                }
                if (e.type == KeyEventType.KeyDown && (e.key == Key.F11 || (e.key == Key.Enter && e.isAltPressed))) { onToggleFullscreen(); return@onPreviewKeyEvent true }
                if (e.type == KeyEventType.KeyDown && e.key == Key.Escape) { goBack(); return@onPreviewKeyEvent true }
                false
            }
            // After the focused control had its chance: arrows move focus like a TV remote's D-pad.
            .onKeyEvent { e ->
                if (e.type != KeyEventType.KeyDown) return@onKeyEvent false
                val dir = when (e.key) {
                    Key.DirectionUp -> FocusDirection.Up
                    Key.DirectionDown -> FocusDirection.Down
                    Key.DirectionLeft -> FocusDirection.Left
                    Key.DirectionRight -> FocusDirection.Right
                    Key.Backspace -> { goBack(); return@onKeyEvent true }
                    Key.Enter, Key.NumPadEnter -> { SoundFx.play(SoundFx.Event.SELECT); return@onKeyEvent false }
                    else -> return@onKeyEvent false
                }
                focus.moveFocus(dir).also { if (it) SoundFx.play(SoundFx.Event.MOVE) }
            },
    ) {
        CompositionLocalProvider(LocalConfiguration provides Configuration(maxWidth.value.toInt(), maxHeight.value.toInt())) {
            key(profileId) {
                val c = app.container
                val savedSettings by c.userStore.settings.collectAsStateWithLifecycle()
                val settings = if (kids.on) savedSettings.copy(screensaver = false) else savedSettings
                val colors = settings.resolvedColors()
                SoundFx.enabled = settings.soundEffects
                SideEffect { SoundFx.use(app, SoundFx.setFor(colors.style)) }
                ZemuTheme(colors, settings.uiZoom, settings.font, settings.fontSize) {
                    Box(Modifier.fillMaxSize()) {
                        if (picking) {
                            ProfilePicker(profiles, profileId) { p ->
                                app.switchProfile(p.id)
                                profileId = p.id
                                picking = false
                            }
                        } else {
                            CompositionLocalProvider(LocalSwitchProfile provides { picking = true }) { AppShell() }
                        }
                        if (!picking && !kids.on) com.zemu.tv.ui.UpdatePrompt()

                        // Library screensaver, after the idle time set in Settings.
                        var saverSlides by remember { mutableStateOf<List<com.zemu.tv.data.ScreensaverSlide>>(emptyList()) }
                        LaunchedEffect(settings.screensaver) {
                            if (!settings.screensaver) return@LaunchedEffect
                            var now = PendingOpen.screensaverNow.also { PendingOpen.screensaverNow = false }
                            if (!now) delay(45_000)
                            var titles = c.screensaverTitles()
                            launch { runCatching { c.screensaverImages.refresh(titles) } }
                            while (true) {
                                delay(1_000)
                                val idle = System.currentTimeMillis() - lastInput
                                if (!screensaverOn && (now || idle >= settings.screensaverIdleSec * 1000L)) {
                                    now = false
                                    val slides = c.screensaverImages.slides(titles)
                                    if (slides.isNotEmpty()) { saverSlides = slides; screensaverOn = true } else lastInput = System.currentTimeMillis()
                                    titles = c.screensaverTitles()
                                    launch { runCatching { c.screensaverImages.refresh(titles) } }
                                }
                            }
                        }
                        if (screensaverOn && saverSlides.isNotEmpty()) {
                            com.zemu.tv.ui.LibraryScreensaver(
                                saverSlides, settings.screensaverImageSec, settings.screensaverFadeTenths * 100,
                                settings.screensaverShowTitle, onCurrent = { saverCurrent = it },
                            )
                        }
                        ToastHost()
                    }
                }
            }
        }
    }
}

@androidx.compose.runtime.Composable
private fun androidx.compose.foundation.layout.BoxScope.ToastHost() {
    val shown = Toast.current.value ?: return
    LaunchedEffect(shown.id) {
        delay(shown.durationMs)
        if (Toast.current.value?.id == shown.id) Toast.current.value = null
    }
    Text(
        shown.text,
        color = Color.White,
        fontSize = 16.sp,
        modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = 48.dp)
            .background(Color(0xE0202020), RoundedCornerShape(12.dp)).padding(horizontal = 20.dp, vertical = 12.dp),
    )
}

/**
 * Posters: a small memory cache and no crossfade keep scrolling smooth on slow machines and cheap
 * on RAM; the disk cache saves bandwidth between launches.
 */
private fun setUpImages() {
    SingletonImageLoader.setSafe { ctx: PlatformContext ->
        ImageLoader.Builder(ctx)
            .components { add(OkHttpNetworkFetcherFactory()) }
            .memoryCache { MemoryCache.Builder().maxSizeBytes(64L * 1024 * 1024).build() }
            .diskCache { DiskCache.Builder().directory(File(ZemuApp.cacheDir, "images").toOkioPath()).maxSizeBytes(300L * 1024 * 1024).build() }
            .crossfade(false)
            .build()
    }
}

/** First launch on this computer: lighter defaults for slower PCs, and downloads switched on. */
private fun firstRun() {
    val marker = File(ZemuApp.filesDir, "linux-defaults-v1")
    if (marker.exists()) return
    kotlinx.coroutines.runBlocking {
        ZemuApp.container.userStore.updateSettings { it.copy(downloads = true, heroTrailers = false, glassStyle = false) }
    }
    marker.writeText("1")
}
