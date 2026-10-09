package com.zemu.tv.ui.settings

import android.annotation.SuppressLint
import android.app.AlertDialog
import android.content.Context
import android.content.Intent
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.os.Bundle
import android.os.SystemClock
import android.util.TypedValue
import android.view.Gravity
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import android.webkit.JavascriptInterface
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.lifecycle.lifecycleScope
import com.zemu.tv.container
import kotlinx.coroutines.launch

/**
 * Opens an addon's `/configure` page. Web pages aren't built for a remote, so the D-pad moves an
 * on-screen cursor (OK clicks, screen edges scroll). When the page tries to open a `stremio://`
 * install link, a manifest URL, or copies one to the clipboard, the addon is installed here.
 */
class ConfigureActivity : ComponentActivity() {
    private lateinit var web: WebView
    private lateinit var cursor: CursorView
    private var installing = false

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val url = intent.getStringExtra(EXTRA_URL) ?: return finish()
        val name = intent.getStringExtra(EXTRA_NAME).orEmpty()

        web = WebView(this).apply {
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            settings.databaseEnabled = true
            settings.setSupportMultipleWindows(false)
            settings.loadWithOverviewMode = true
            settings.useWideViewPort = true
            webChromeClient = WebChromeClient()
            addJavascriptInterface(Bridge(), "ScBridge")
            webViewClient = object : WebViewClient() {
                override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean =
                    interceptInstall(request.url.toString())

                override fun onPageFinished(view: WebView, url: String) = injectClipboardHook()

                override fun onReceivedHttpError(view: WebView, request: WebResourceRequest, response: WebResourceResponse) {
                    if (request.isForMainFrame && response.statusCode >= 400) {
                        Toast.makeText(
                            this@ConfigureActivity,
                            "This addon's configure page isn't available (HTTP ${response.statusCode}). Try its website, or install it without configuring.",
                            Toast.LENGTH_LONG,
                        ).show()
                    }
                }
            }
        }
        cursor = CursorView(this)
        val header = TextView(this).apply {
            text = "Configure $name   ·   Arrows move the cursor, OK clicks, edges scroll, Back goes back.   The page's Install button installs the addon here."
            setTextColor(Color.rgb(184, 184, 194))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            setBackgroundColor(Color.rgb(10, 10, 14))
            setPadding(dp(24), dp(10), dp(24), dp(10))
        }
        val frame = FrameLayout(this).apply {
            addView(web, FrameLayout.LayoutParams(-1, -1))
            addView(cursor, FrameLayout.LayoutParams(-1, -1))
        }
        setContentView(LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            addView(header, LinearLayout.LayoutParams(-1, -2))
            addView(frame, LinearLayout.LayoutParams(-1, 0, 1f))
        })
        web.loadUrl(url)
    }

    private fun dp(v: Int) = (v * resources.displayMetrics.density).toInt()

    /** True if [url] is an addon install link (handled here instead of navigating). */
    private fun interceptInstall(url: String): Boolean {
        val install = when {
            url.startsWith("stremio://") -> "https://" + url.removePrefix("stremio://")
            (url.startsWith("http://") || url.startsWith("https://")) && url.substringBefore('?').endsWith("/manifest.json") -> url
            else -> return false
        }
        install(install)
        return true
    }

    private fun install(url: String) {
        if (installing) return
        installing = true
        lifecycleScope.launch {
            val result = container.addons.install(url)
            installing = false
            result.onSuccess { a ->
                container.streams.invalidate()
                Toast.makeText(this@ConfigureActivity, "Installed ${a.manifest.name}", Toast.LENGTH_LONG).show()
                finish()
            }.onFailure {
                Toast.makeText(this@ConfigureActivity, "Couldn't install: ${it.message}", Toast.LENGTH_LONG).show()
            }
        }
    }

    /** Many configure pages offer "Copy URL" instead of an install link; catch that too. */
    private fun injectClipboardHook() {
        web.evaluateJavascript(
            """(function(){if(window.__scHook)return;window.__scHook=1;
            var report=function(t){try{ScBridge.copied(String(t||''))}catch(e){}};
            try{if(navigator.clipboard){navigator.clipboard.writeText=function(t){report(t);return Promise.resolve()}}
                else{Object.defineProperty(navigator,'clipboard',{value:{writeText:function(t){report(t);return Promise.resolve()}}})}}catch(e){}
            var ec=document.execCommand;document.execCommand=function(c){if(c==='copy'){var a=document.activeElement;report(a&&a.value?a.value:String(window.getSelection()))}return ec.apply(document,arguments)};
            })()""",
            null,
        )
    }

    private inner class Bridge {
        @JavascriptInterface
        fun copied(text: String) {
            val t = text.trim()
            if (!t.startsWith("stremio://") && !t.contains("manifest.json")) return
            runOnUiThread {
                AlertDialog.Builder(this@ConfigureActivity, android.R.style.Theme_DeviceDefault_Dialog_Alert)
                    .setTitle("Install this addon?")
                    .setMessage(t.take(300))
                    .setPositiveButton("Install") { _, _ -> interceptInstall(t) }
                    .setNegativeButton("Cancel", null)
                    .show()
            }
        }
    }

    // ---- D-pad cursor ----

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        val step = dp(if (event.repeatCount > 6) 48 else if (event.repeatCount > 2) 28 else 16).toFloat()
        val down = event.action == KeyEvent.ACTION_DOWN
        when (event.keyCode) {
            KeyEvent.KEYCODE_DPAD_UP -> { if (down) move(0f, -step); return true }
            KeyEvent.KEYCODE_DPAD_DOWN -> { if (down) move(0f, step); return true }
            KeyEvent.KEYCODE_DPAD_LEFT -> { if (down) move(-step, 0f); return true }
            KeyEvent.KEYCODE_DPAD_RIGHT -> { if (down) move(step, 0f); return true }
            KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_ENTER, KeyEvent.KEYCODE_NUMPAD_ENTER -> {
                if (down && event.repeatCount == 0) click()
                return true
            }
            KeyEvent.KEYCODE_CHANNEL_DOWN, KeyEvent.KEYCODE_PAGE_DOWN -> { if (down) swipe(-web.height * 0.7f); return true }
            KeyEvent.KEYCODE_CHANNEL_UP, KeyEvent.KEYCODE_PAGE_UP -> { if (down) swipe(web.height * 0.7f); return true }
            KeyEvent.KEYCODE_BACK -> {
                if (down) return true
                if (web.canGoBack()) web.goBack() else finish()
                return true
            }
        }
        return super.dispatchKeyEvent(event)
    }

    private fun move(dx: Float, dy: Float) {
        val edge = dp(24).toFloat()
        val nx = (cursor.x0 + dx).coerceIn(0f, cursor.width.toFloat())
        val ny = cursor.y0 + dy
        when {
            ny > cursor.height - edge -> { cursor.set(nx, cursor.height - edge); swipe(-dy * 4) }
            ny < edge -> { cursor.set(nx, edge); swipe(-dy * 4) }
            else -> cursor.set(nx, ny)
        }
    }

    private fun touch(action: Int, x: Float, y: Float, downTime: Long) {
        val ev = MotionEvent.obtain(downTime, SystemClock.uptimeMillis(), action, x, y, 0)
        ev.source = android.view.InputDevice.SOURCE_TOUCHSCREEN
        web.dispatchTouchEvent(ev)
        ev.recycle()
    }

    private fun click() {
        val t = SystemClock.uptimeMillis()
        touch(MotionEvent.ACTION_DOWN, cursor.x0, cursor.y0, t)
        touch(MotionEvent.ACTION_UP, cursor.x0, cursor.y0, t)
    }

    /** Scrolls whatever is under the cursor (works for inner scroll containers too). */
    private fun swipe(dy: Float) {
        val x = cursor.x0
        val y = (web.height / 2f)
        val t = SystemClock.uptimeMillis()
        touch(MotionEvent.ACTION_DOWN, x, y, t)
        for (i in 1..5) touch(MotionEvent.ACTION_MOVE, x, y + dy * i / 5f, t)
        touch(MotionEvent.ACTION_UP, x, y + dy, t)
    }

    override fun onDestroy() {
        web.destroy()
        super.onDestroy()
    }

    private class CursorView(context: Context) : View(context) {
        var x0 = -1f
            private set
        var y0 = -1f
            private set
        private val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.argb(200, 229, 9, 20) }
        private val ring = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE; style = Paint.Style.STROKE; strokeWidth = 4f }

        init {
            isFocusable = false
            foregroundGravity = Gravity.CENTER
        }

        fun set(x: Float, y: Float) {
            x0 = x
            y0 = y
            invalidate()
        }

        override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
            if (x0 < 0) set(w / 2f, h / 3f)
        }

        override fun onDraw(canvas: Canvas) {
            val r = 14f * resources.displayMetrics.density
            canvas.drawCircle(x0, y0, r, fill)
            canvas.drawCircle(x0, y0, r, ring)
        }
    }

    companion object {
        private const val EXTRA_URL = "url"
        private const val EXTRA_NAME = "name"

        fun start(context: Context, url: String, name: String) {
            context.startActivity(Intent(context, ConfigureActivity::class.java).putExtra(EXTRA_URL, url).putExtra(EXTRA_NAME, name))
        }
    }
}
