package android.content

import java.io.File
import java.util.Properties

/**
 * Desktop stand-in for Android's Context: the shared Android code only needs folders and small
 * preference files from it. Folders follow the XDG base directory spec.
 */
open class Context {
    open val applicationContext: Context get() = this

    private fun xdg(env: String, fallback: String) =
        File(System.getenv(env)?.takeIf { it.isNotBlank() } ?: (System.getProperty("user.home") + fallback), "zemu").apply { mkdirs() }

    val filesDir: File by lazy { xdg("XDG_DATA_HOME", "/.local/share") }
    val cacheDir: File by lazy { xdg("XDG_CACHE_HOME", "/.cache") }

    fun getSharedPreferences(name: String, mode: Int): SharedPreferences = SharedPreferences(File(filesDir, "$name.properties"))

    companion object { const val MODE_PRIVATE = 0 }
}

/** Just enough of SharedPreferences for the shared code: longs and strings in a properties file. */
class SharedPreferences(private val file: File) {
    private val props = Properties().apply { runCatching { file.inputStream().use { load(it) } } }

    fun getLong(key: String, default: Long) = props.getProperty(key)?.toLongOrNull() ?: default
    fun getString(key: String, default: String?): String? = props.getProperty(key) ?: default
    fun edit() = Editor()

    inner class Editor {
        fun putLong(key: String, v: Long) = apply { props.setProperty(key, v.toString()) }
        fun putString(key: String, v: String) = apply { props.setProperty(key, v) }
        fun remove(key: String) = apply { props.remove(key) }
        fun apply() { runCatching { file.outputStream().use { props.store(it, null) } } }
    }
}
