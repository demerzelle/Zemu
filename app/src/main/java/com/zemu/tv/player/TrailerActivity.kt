package com.zemu.tv.player

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.view.KeyEvent
import android.view.WindowManager
import android.webkit.WebView
import android.widget.Toast
import androidx.activity.ComponentActivity

/** Full-screen trailer with sound. OK/Play-Pause toggles, Left/Right seek 10 s, Back exits. */
class TrailerActivity : ComponentActivity() {
    private var web: WebView? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        val id = intent.getStringExtra(EXTRA_ID) ?: return finish()
        val view = YouTubeEmbed.create(this, focusable = false, listener = object : YouTubeEmbed.Listener {
            override fun onEnded() = finish()
            override fun onError(code: Int) {
                // Embedding disabled by the uploader (101/150) or blocked: hand off to YouTube.
                Toast.makeText(this@TrailerActivity, "This trailer can't be embedded, opening YouTube", Toast.LENGTH_SHORT).show()
                runCatching { startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://www.youtube.com/watch?v=$id"))) }
                finish()
            }
        })
        view.setBackgroundColor(android.graphics.Color.BLACK)
        setContentView(view)
        YouTubeEmbed.load(view, id, muted = false, controls = true, cover = false, startSeconds = intent.getIntExtra(EXTRA_START, 0))
        web = view
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (event.action != KeyEvent.ACTION_DOWN) return super.dispatchKeyEvent(event)
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
        private const val EXTRA_ID = "yt"
        private const val EXTRA_START = "start"

        fun start(context: Context, youtubeId: String, startSeconds: Int = 0) {
            context.startActivity(
                Intent(context, TrailerActivity::class.java).putExtra(EXTRA_ID, youtubeId).putExtra(EXTRA_START, startSeconds),
            )
        }
    }
}
