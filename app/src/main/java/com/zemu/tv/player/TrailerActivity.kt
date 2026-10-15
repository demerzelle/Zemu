package com.zemu.tv.player

import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.fillMaxHeight
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.view.KeyEvent
import android.view.WindowManager
import android.webkit.WebView
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.tv.material3.Text
import com.zemu.tv.container
import com.zemu.tv.data.TrailerRef
import com.zemu.tv.ui.components.TvChip
import com.zemu.tv.ui.theme.ZemuTheme
import com.zemu.tv.ui.theme.resolvedColors
import kotlinx.coroutines.delay

/**
 * Full-screen trailers with sound. Plays the first (or the requested one) and carries on through
 * the title's other official trailers. With more than one, a selector bar shows at the start and on
 * Down; pick one with Left/Right + OK, Up or Back closes it. Otherwise OK/Play-Pause toggles,
 * Left/Right seek 10 s, Back exits.
 */
class TrailerActivity : ComponentActivity() {
    private var web: WebView? = null
    private var trailers: List<TrailerRef> = emptyList()
    private var current by mutableIntStateOf(0)
    private var selectorOpen by mutableStateOf(false)
    /** The selector shows (unfocused) until this time, so viewers know other trailers exist. */
    private var hintUntil by mutableLongStateOf(0L)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        val ids = intent.getStringArrayExtra(EXTRA_IDS).orEmpty()
        val titles = intent.getStringArrayExtra(EXTRA_TITLES).orEmpty()
        trailers = ids.mapIndexed { i, id -> TrailerRef(id, titles.getOrNull(i).orEmpty().ifBlank { "Trailer ${i + 1}" }) }
        if (trailers.isEmpty()) return finish()
        current = trailers.indexOfFirst { it.id == intent.getStringExtra(EXTRA_START_ID) }.coerceAtLeast(0)

        val view = YouTubeEmbed.create(this, focusable = false, listener = object : YouTubeEmbed.Listener {
            // Autoplay the next official trailer; leave after the last.
            override fun onEnded() = if (current + 1 < trailers.size) play(current + 1) else finish()
            override fun onError(code: Int) {
                // Embedding disabled by the uploader (101/150) or blocked: skip it, or hand off to YouTube.
                if (current + 1 < trailers.size) { play(current + 1); return }
                Toast.makeText(this@TrailerActivity, "This trailer can't be embedded, opening YouTube", Toast.LENGTH_SHORT).show()
                runCatching { startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://www.youtube.com/watch?v=${trailers[current].id}"))) }
                finish()
            }
        })
        view.setBackgroundColor(android.graphics.Color.BLACK)
        web = view
        YouTubeEmbed.load(view, trailers[current].id, muted = false, controls = true, cover = false, startSeconds = intent.getIntExtra(EXTRA_START, 0))
        if (trailers.size > 1) hintUntil = System.currentTimeMillis() + 5_000

        val s = container.userStore.settings.value
        val colors = s.resolvedColors(light = false)
        setContent {
            ZemuTheme(colors, s.uiZoom, s.font, s.fontSize) {
                if (com.zemu.tv.ui.theme.Palette.Style == com.zemu.tv.ui.theme.UiStyle.RETRO) {
                    // Cybercore: the trailer plays in a window on the desktop, with the taskbar below.
                    val variant = com.zemu.tv.ui.theme.Palette.colors.variant
                    Box(Modifier.fillMaxSize()) {
                        Box(Modifier.fillMaxSize().padding(bottom = 34.dp)) {
                            com.zemu.tv.ui.theme.RetroBackdrop(variant)
                            com.zemu.tv.ui.theme.RetroWindow(
                                trailers[current].title,
                                Modifier.align(Alignment.Center).fillMaxWidth(0.86f).fillMaxHeight(0.88f),
                            ) { AndroidView(factory = { view }, modifier = Modifier.fillMaxSize()) }
                            if (trailers.size > 1) TrailerSelector()
                        }
                        com.zemu.tv.ui.theme.RetroTaskbar(variant, Modifier.align(Alignment.BottomStart).fillMaxWidth().height(34.dp))
                    }
                } else Box(Modifier.fillMaxSize().background(Color.Black)) {
                    AndroidView(factory = { view }, modifier = Modifier.fillMaxSize())
                    if (trailers.size > 1) TrailerSelector()
                }
            }
        }
    }

    @Composable
    private fun TrailerSelector() {
        var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
        LaunchedEffect(hintUntil) {
            while (System.currentTimeMillis() < hintUntil) { delay(500); now = System.currentTimeMillis() }
            now = System.currentTimeMillis()
        }
        val visible = selectorOpen || now < hintUntil
        val focus = remember { FocusRequester() }
        LaunchedEffect(selectorOpen) { if (selectorOpen) { delay(50); runCatching { focus.requestFocus() } } }
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.BottomStart) {
            AnimatedVisibility(visible = visible, enter = fadeIn(), exit = fadeOut()) {
                Column(
                    Modifier
                        .fillMaxWidth()
                        .background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.85f))))
                        .padding(top = 40.dp, bottom = 28.dp),
                ) {
                    Text(
                        if (selectorOpen) "Official trailers" else "Official trailers · press ↓ to choose",
                        fontSize = 15.sp, color = Color.White.copy(alpha = 0.8f), modifier = Modifier.padding(start = 48.dp, bottom = 8.dp),
                    )
                    LazyRow(contentPadding = PaddingValues(horizontal = 48.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        itemsIndexed(trailers, key = { _, t -> t.id }) { i, t ->
                            TvChip(
                                t.title,
                                selected = i == current,
                                onClick = { selectorOpen = false; play(i) },
                                modifier = if (i == current) Modifier.focusRequester(focus) else Modifier,
                            )
                        }
                    }
                }
            }
        }
    }

    private fun play(index: Int) {
        current = index
        web?.let { YouTubeEmbed.load(it, trailers[index].id, muted = false, controls = true, cover = false) }
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (selectorOpen) {
            // Selector open: arrows/OK go to the chips; Up or Back closes it.
            if (event.action == KeyEvent.ACTION_DOWN && (event.keyCode == KeyEvent.KEYCODE_DPAD_UP || event.keyCode == KeyEvent.KEYCODE_BACK)) {
                selectorOpen = false
                return true
            }
            return super.dispatchKeyEvent(event)
        }
        if (event.action != KeyEvent.ACTION_DOWN) return super.dispatchKeyEvent(event)
        if (event.keyCode == KeyEvent.KEYCODE_DPAD_DOWN && trailers.size > 1) {
            selectorOpen = true
            return true
        }
        if (event.keyCode == KeyEvent.KEYCODE_MEDIA_NEXT) {
            if (current + 1 < trailers.size) play(current + 1)
            return true
        }
        val js = when (event.keyCode) {
            KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_ENTER, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE,
            KeyEvent.KEYCODE_MEDIA_PLAY, KeyEvent.KEYCODE_MEDIA_PAUSE -> "toggle()"
            KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.KEYCODE_MEDIA_REWIND -> "seek(-10)"
            KeyEvent.KEYCODE_DPAD_RIGHT, KeyEvent.KEYCODE_MEDIA_FAST_FORWARD -> "seek(10)"
            else -> null
        } ?: return super.dispatchKeyEvent(event)
        web?.evaluateJavascript(js, null)
        return true
    }

    override fun onPause() {
        super.onPause()
        web?.onPause()
    }

    override fun onResume() {
        super.onResume()
        web?.onResume()
    }

    override fun onDestroy() {
        web?.destroy()
        web = null
        super.onDestroy()
    }

    companion object {
        private const val EXTRA_IDS = "yt_ids"
        private const val EXTRA_TITLES = "yt_titles"
        private const val EXTRA_START_ID = "yt_start_id"
        private const val EXTRA_START = "start"

        /** Plays [trailers] in order, beginning with [startId] (default: the first) at [startSeconds]. */
        fun start(context: Context, trailers: List<TrailerRef>, startId: String? = null, startSeconds: Int = 0) {
            if (trailers.isEmpty()) return
            context.startActivity(
                Intent(context, TrailerActivity::class.java)
                    .putExtra(EXTRA_IDS, trailers.map { it.id }.toTypedArray())
                    .putExtra(EXTRA_TITLES, trailers.map { it.title }.toTypedArray())
                    .putExtra(EXTRA_START_ID, startId)
                    .putExtra(EXTRA_START, startSeconds),
            )
        }

        /** A single trailer. */
        fun start(context: Context, youtubeId: String, startSeconds: Int = 0) =
            start(context, listOf(TrailerRef(youtubeId, "Trailer")), youtubeId, startSeconds)
    }
}
