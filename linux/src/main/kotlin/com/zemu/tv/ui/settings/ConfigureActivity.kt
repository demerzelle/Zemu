package com.zemu.tv.ui.settings

import android.content.Context
import android.widget.Toast

/**
 * An addon's setup page opens in the web browser. Its Install button gives a stremio:// or
 * manifest link: paste it under Addons → "Add by URL" (Zemu also accepts stremio:// links).
 */
object ConfigureActivity {
    fun start(context: Context, url: String, @Suppress("UNUSED_PARAMETER") name: String) {
        val ok = runCatching { ProcessBuilder("xdg-open", url).start() }.isSuccess
        Toast.makeText(context, if (ok) "Opened in your browser. Copy the addon link it gives you and paste it here." else "Couldn't open a browser for $url", Toast.LENGTH_LONG).show()
    }
}
