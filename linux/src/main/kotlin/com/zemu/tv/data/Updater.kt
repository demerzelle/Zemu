package com.zemu.tv.data

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.io.IOException

/** A newer Zemu on GitHub Releases. */
data class AppUpdate(val version: String, val notes: String, val apkUrl: String, val sizeBytes: Long)

/** Where install.sh puts Zemu; updates replace it in place. */
private val installDir = File(System.getProperty("user.home"), ".local/share/zemu-app")

/**
 * Updates from the project's GitHub Releases: the newest release's `Zemu-Linux-<version>.tar.gz`
 * is downloaded, unpacked and installed over this copy by its own install.sh, then Zemu restarts.
 */
class Updater(private val app: Context) {
    private val http = OkHttpClient()
    private val json = Json { ignoreUnknownKeys = true }

    val available = MutableStateFlow<AppUpdate?>(null)
    /** Set by Settings → Check for updates: show the prompt even if it was put off. */
    val showNow = MutableStateFlow(false)
    /** 0..1 while the APK downloads; null otherwise. */
    val progress = MutableStateFlow<Float?>(null)

    val currentVersion: String = Updater::class.java.`package`?.implementationVersion ?: "0"

    /** Asks GitHub for the latest release; returns it when it's newer than this app. */
    suspend fun check(): AppUpdate? = withContext(Dispatchers.IO) {
        val req = Request.Builder().url("https://api.github.com/repos/$REPO/releases/latest")
            .header("Accept", "application/vnd.github+json").build()
        val o = http.newCall(req).execute().use {
            if (!it.isSuccessful) throw IOException("GitHub HTTP ${it.code}")
            json.parseToJsonElement(it.body?.string().orEmpty()).jsonObject
        }
        val version = o.str("tag_name").removePrefix("v")
        val apk = o["assets"]?.jsonArray?.map { it.jsonObject }
            ?.firstOrNull { a -> a.str("name").let { it.startsWith("Zemu-Linux-") && it.endsWith(".tar.gz") } }
        val update = apk?.takeIf { isNewer(version, currentVersion) }?.let {
            AppUpdate(version, o.str("body"), it.str("browser_download_url"), it["size"]?.jsonPrimitive?.longOrNull ?: 0)
        }
        available.value = update
        update
    }

    /** Downloads [u], installs it over this copy and restarts Zemu. Returns true once installed. */
    suspend fun install(u: AppUpdate): Boolean {
        val dir = File(app.cacheDir, "updates").apply { deleteRecursively(); mkdirs() }
        val file = File(dir, "zemu-update.tar.gz")
        withContext(Dispatchers.IO) {
            progress.value = 0f
            try {
                http.newCall(Request.Builder().url(u.apkUrl).build()).execute().use { r ->
                    if (!r.isSuccessful) throw IOException("Download failed (HTTP ${r.code})")
                    val body = r.body ?: throw IOException("Empty download")
                    val total = body.contentLength().takeIf { it > 0 } ?: u.sizeBytes
                    file.outputStream().use { out ->
                        body.byteStream().use { input ->
                            val buf = ByteArray(64 * 1024)
                            var done = 0L
                            while (true) {
                                val n = input.read(buf)
                                if (n < 0) break
                                out.write(buf, 0, n)
                                done += n
                                if (total > 0) progress.value = (done.toFloat() / total).coerceAtMost(1f)
                            }
                        }
                    }
                }
                fun sh(vararg cmd: String) {
                    val p = ProcessBuilder(*cmd).directory(dir).redirectErrorStream(true).start()
                    val out = p.inputStream.bufferedReader().readText()
                    if (p.waitFor() != 0) throw IOException(out.lines().lastOrNull { it.isNotBlank() } ?: "${cmd[0]} failed")
                }
                sh("tar", "-xzf", file.path)
                val script = dir.walkTopDown().maxDepth(2).firstOrNull { it.name == "install.sh" } ?: throw IOException("The update has no installer")
                sh("sh", script.path, "--no-deps")
            } finally {
                progress.value = null
            }
        }
        // Start the new version and quit this one.
        ProcessBuilder(File(installDir, "bin/zemu").path).start()
        kotlin.system.exitProcess(0)
    }

    private fun JsonObject.str(k: String) = this[k]?.jsonPrimitive?.contentOrNull.orEmpty()

    companion object {
        const val REPO = "demerzelle/Zemu"

        /** "1.0.10" > "1.0.9"; a missing part counts as 0. */
        fun isNewer(candidate: String, current: String): Boolean {
            fun parts(v: String) = v.split('.', '-').map { it.toIntOrNull() ?: 0 }
            val a = parts(candidate)
            val b = parts(current)
            for (i in 0 until maxOf(a.size, b.size)) {
                val x = a.getOrElse(i) { 0 }
                val y = b.getOrElse(i) { 0 }
                if (x != y) return x > y
            }
            return false
        }
    }
}
