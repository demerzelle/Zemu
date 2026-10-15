package com.zemu.tv

import androidx.compose.runtime.LaunchedEffect
import kotlinx.coroutines.launch
import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.zemu.tv.ui.AppShell
import com.zemu.tv.ui.profiles.ProfilePicker
import com.zemu.tv.ui.theme.DynamicTheme
import com.zemu.tv.ui.theme.DynamicThemeLayer
import com.zemu.tv.ui.theme.ZemuTheme
import com.zemu.tv.ui.theme.resolvedColors

/** Opens the "Who's watching?" screen (from Settings). */
val LocalSwitchProfile = staticCompositionLocalOf<() -> Unit> { {} }

/** A title to open from a launcher/widget link: type to id. Consumed by the app shell. */
object PendingOpen {
    var target by mutableStateOf<Pair<String, String>?>(null)
    /** Start playing [target] right away (the screensaver's "Watch now"). */
    var play = false

    fun from(intent: Intent?) {
        val uri = intent?.data ?: return
        if (uri.scheme !in setOf("zemu") || uri.host != "details") return
        val parts = uri.pathSegments
        if (parts.size >= 2) target = parts[0] to parts[1]
    }
}

class MainActivity : ComponentActivity() {
    /** This screen's theme; re-applied on return because the (always dark) player shares [com.zemu.tv.ui.theme.Palette]. */
    private var appColors: com.zemu.tv.ui.theme.ThemeColors? = null

    override fun onResume() {
        super.onResume()
        appColors?.let { com.zemu.tv.ui.theme.Palette.colors = it }
        resumed = true
        lastInput = android.os.SystemClock.uptimeMillis()
    }

    override fun onPause() {
        super.onPause()
        resumed = false
        screensaverOn = false
    }

    // ---- Library screensaver: idle tracking ----
    private var resumed by mutableStateOf(false)
    private var lastInput by androidx.compose.runtime.mutableLongStateOf(0L)
    private var screensaverOn by mutableStateOf(false)

    /** The screensaver slide showing now, for "Watch now". */
    private var saverCurrent: com.zemu.tv.data.ScreensaverSlide? = null
    private var swallowTouch = false
    private var swallowKey = -1

    /**
     * Any key or touch counts as activity. While the screensaver shows, the input only dismisses
     * it: the waking key (through its key-up) and touch never reach the app underneath.
     */
    override fun dispatchKeyEvent(event: android.view.KeyEvent): Boolean {
        lastInput = android.os.SystemClock.uptimeMillis()
        if (screensaverOn) {
            if (event.action == android.view.KeyEvent.ACTION_DOWN) {
                screensaverOn = false
                swallowKey = event.keyCode
                // OK: "Watch now" on the title showing; any other key just wakes the app.
                val ok = event.keyCode in setOf(android.view.KeyEvent.KEYCODE_DPAD_CENTER, android.view.KeyEvent.KEYCODE_ENTER, android.view.KeyEvent.KEYCODE_NUMPAD_ENTER)
                saverCurrent?.takeIf { ok }?.let { PendingOpen.play = true; PendingOpen.target = it.meta.type to it.meta.id }
            }
            return true
        }
        if (event.keyCode == swallowKey) {
            if (event.action == android.view.KeyEvent.ACTION_UP) swallowKey = -1
            return true
        }
        return super.dispatchKeyEvent(event)
    }

    override fun dispatchTouchEvent(ev: android.view.MotionEvent): Boolean {
        lastInput = android.os.SystemClock.uptimeMillis()
        if (screensaverOn && ev.actionMasked == android.view.MotionEvent.ACTION_DOWN) {
            screensaverOn = false
            swallowTouch = true
        }
        if (swallowTouch) {
            if (ev.actionMasked == android.view.MotionEvent.ACTION_UP || ev.actionMasked == android.view.MotionEvent.ACTION_CANCEL) swallowTouch = false
            return true
        }
        return super.dispatchTouchEvent(ev)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        PendingOpen.from(intent)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        com.zemu.tv.ui.theme.Palette.blurSupported = android.os.Build.VERSION.SDK_INT >= 31 &&
            runCatching { getSystemService(android.view.WindowManager::class.java).isCrossWindowBlurEnabled }.getOrDefault(false)
        PendingOpen.from(intent)
        setContent {
            var profileId by remember { mutableStateOf(app.container.profileId) }
            val realProfiles by app.profiles.profiles.collectAsStateWithLifecycle()
            val profiles = realProfiles
            var picking by remember { mutableStateOf(profiles.size > 1 && !app.profileChosen && !app.profiles.skipPicker.value) }

            key(profileId) {
                val c = app.container
                val settings by c.userStore.settings.collectAsStateWithLifecycle()
                val dynamic = DynamicTheme.of(settings.dynamicTheme)
                var rgbAccent by remember { mutableStateOf<Color?>(null) }
                val base = settings.resolvedColors()
                val colors = rgbAccent?.let { base.copy(accent = it) } ?: base
                appColors = colors
                // Dark status/navigation bar icons in light mode (phones and tablets).
                androidx.compose.runtime.SideEffect {
                    androidx.core.view.WindowCompat.getInsetsController(window, window.decorView).apply {
                        isAppearanceLightStatusBars = colors.light
                        isAppearanceLightNavigationBars = colors.light
                    }
                }

                ZemuTheme(colors) {
                    Box(Modifier.fillMaxSize()) {
                        if (picking) {
                            ProfilePicker(profiles, profileId) { p ->
                                if (p.id != profileId) viewModelStore.clear()
                                app.switchProfile(p.id)
                                profileId = p.id
                                picking = false
                            }
                        } else {
                            CompositionLocalProvider(LocalSwitchProfile provides { picking = true }) {
                                AppShell()
                            }
                        }
                        DynamicThemeLayer(dynamic, onAccent = { rgbAccent = it })
                        // Library screensaver: an overlay, so the app underneath stays as it was.
                        var saverSlides by remember { mutableStateOf<List<com.zemu.tv.data.ScreensaverSlide>>(emptyList()) }
                        LaunchedEffect(settings.screensaver, resumed) {
                            if (!settings.screensaver || !resumed) return@LaunchedEffect
                            // A fresh pick of suggestions each run; art for them is looked up ahead of time.
                            var titles = c.screensaverTitles()
                            runCatching { c.screensaverImages.refresh(titles) }
                            while (true) {
                                kotlinx.coroutines.delay(1_000)
                                val idle = android.os.SystemClock.uptimeMillis() - lastInput
                                if (!screensaverOn && idle >= settings.screensaverIdleSec * 1000L) {
                                    // Skip when nothing has art yet.
                                    val slides = c.screensaverImages.slides(titles)
                                    if (slides.isNotEmpty()) { saverSlides = slides; screensaverOn = true }
                                    else lastInput = android.os.SystemClock.uptimeMillis()
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
                    }
                }
            }
        }
    }
}
