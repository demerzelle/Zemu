package com.zemu.tv

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
import com.zemu.tv.ui.theme.applyTo
import com.zemu.tv.ui.theme.themeColors

/** Opens the "Who's watching?" screen (from Settings). */
val LocalSwitchProfile = staticCompositionLocalOf<() -> Unit> { {} }

/** A title to open from a launcher/widget link: type to id. Consumed by the app shell. */
object PendingOpen {
    var target by mutableStateOf<Pair<String, String>?>(null)

    fun from(intent: Intent?) {
        val uri = intent?.data ?: return
        if (uri.scheme !in setOf("zemu") || uri.host != "details") return
        val parts = uri.pathSegments
        if (parts.size >= 2) target = parts[0] to parts[1]
    }
}

class MainActivity : ComponentActivity() {
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        PendingOpen.from(intent)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
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
                val base = dynamic.applyTo(settings.themeColors())
                val colors = rgbAccent?.let { base.copy(accent = it) } ?: base

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
                    }
                }
            }
        }
    }
}
