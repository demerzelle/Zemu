# WebView JavaScript bridges (YouTube trailers, addon configuration page) are called by name.
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}
# Media3 loads the FFmpeg audio renderer by class name.
-keep class androidx.media3.decoder.ffmpeg.** { *; }
-dontwarn androidx.media3.decoder.ffmpeg.**
