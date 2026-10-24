package androidx.compose.ui.viewinterop

import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.ui.Modifier

/** Nothing to embed on desktop; the factory still runs once so its callbacks fire. */
@Composable
fun <T> AndroidView(factory: (android.content.Context) -> T, modifier: Modifier = Modifier, onRelease: (T) -> Unit = {}) {
    DisposableEffect(Unit) {
        val v = factory(com.zemu.tv.ZemuApp)
        onDispose { onRelease(v) }
    }
}
