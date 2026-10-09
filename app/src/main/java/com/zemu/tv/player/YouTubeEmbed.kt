package com.zemu.tv.player

import android.annotation.SuppressLint
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.ViewGroup
import android.webkit.JavascriptInterface
import android.webkit.WebChromeClient
import android.webkit.WebView

/**
 * YouTube IFrame Player in a WebView. YouTube requires embeds to identify the app via the
 * page origin, so the HTML is loaded with the app's package as base URL.
 */
object YouTubeEmbed {
    private const val ORIGIN = "https://com.zemu.tv"

    interface Listener {
        fun onPlaying() {}
        fun onEnded() {}
        fun onError(code: Int) {}
        fun onTime(seconds: Float) {}
    }

    @SuppressLint("SetJavaScriptEnabled")
    fun create(context: Context, focusable: Boolean, listener: Listener): WebView = WebView(context).apply {
        layoutParams = ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
        setBackgroundColor(0)
        isFocusable = focusable
        isFocusableInTouchMode = focusable
        if (!focusable) descendantFocusability = ViewGroup.FOCUS_BLOCK_DESCENDANTS
        importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
        settings.javaScriptEnabled = true
        settings.domStorageEnabled = true
        settings.mediaPlaybackRequiresUserGesture = false
        webChromeClient = WebChromeClient()
        val main = Handler(Looper.getMainLooper())
        addJavascriptInterface(object {
            @JavascriptInterface fun playing() { main.post { listener.onPlaying() } }
            @JavascriptInterface fun ended() { main.post { listener.onEnded() } }
            @JavascriptInterface fun error(code: Int) { main.post { listener.onError(code) } }
            @JavascriptInterface fun time(t: Float) { main.post { listener.onTime(t) } }
        }, "Bridge")
    }

    fun load(view: WebView, videoId: String, muted: Boolean, controls: Boolean, cover: Boolean, startSeconds: Int = 0) {
        val id = videoId.filter { it.isLetterOrDigit() || it == '-' || it == '_' }
        val fit = if (cover) {
            "position:absolute;top:50%;left:50%;width:100vw;height:56.25vw;min-height:100vh;min-width:177.78vh;transform:translate(-50%,-50%);pointer-events:none"
        } else {
            "position:absolute;top:0;left:0;width:100%;height:100%"
        }
        val html = """<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
<style>html,body{margin:0;height:100%;overflow:hidden;background:transparent}#p{$fit}</style></head>
<body><div id="p"></div><script src="https://www.youtube.com/iframe_api"></script><script>
var player;
function onYouTubeIframeAPIReady(){player=new YT.Player('p',{videoId:'$id',
 playerVars:{autoplay:1,start:$startSeconds,mute:${if (muted) 1 else 0},controls:${if (controls) 1 else 0},rel:0,modestbranding:1,playsinline:1,iv_load_policy:3,fs:0,disablekb:1,origin:'$ORIGIN'},
 events:{onReady:function(e){e.target.playVideo()},
  onStateChange:function(e){if(e.data===1)Bridge.playing();if(e.data===0)Bridge.ended()},
  onError:function(e){Bridge.error(e.data)}}});}
setInterval(function(){try{if(player&&player.getCurrentTime)Bridge.time(player.getCurrentTime())}catch(e){}},1000);
function toggle(){if(!player)return;if(player.getPlayerState()===1)player.pauseVideo();else player.playVideo()}
function seek(d){if(player)player.seekTo(Math.max(0,player.getCurrentTime()+d),true)}
</script></body></html>"""
        view.loadDataWithBaseURL(ORIGIN, html, "text/html", "utf-8", null)
    }
}
