package androidx.compose.ui.platform

import androidx.compose.runtime.Composable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.unit.Dp

val LocalContext = staticCompositionLocalOf<android.content.Context> { com.zemu.tv.ZemuApp }

/** Window size in dp, like Android's Configuration. */
class Configuration(val screenWidthDp: Int, val screenHeightDp: Int)

val LocalConfiguration: androidx.compose.runtime.ProvidableCompositionLocal<Configuration> =
    staticCompositionLocalOf { Configuration(1280, 720) }
