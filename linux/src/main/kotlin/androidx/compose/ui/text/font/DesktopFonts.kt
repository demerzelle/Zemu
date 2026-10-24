package androidx.compose.ui.text.font

fun Font(resId: Int): Font = androidx.compose.ui.text.platform.Font(com.zemu.tv.R.paths.getValue(resId))

/** Android's "sans-serif-condensed"/"sans-serif-black": the default family in the matching weight is close enough. */
fun FontFamily(@Suppress("UNUSED_PARAMETER") typeface: android.graphics.Typeface): FontFamily = FontFamily.SansSerif
