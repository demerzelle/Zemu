package android.text.format

import android.content.Context

/** The system's short time format ("9:41 PM" or "21:41"). */
object DateFormat {
    @Suppress("UNUSED_PARAMETER")
    fun getTimeFormat(context: Context): java.text.DateFormat = java.text.DateFormat.getTimeInstance(java.text.DateFormat.SHORT)
}
