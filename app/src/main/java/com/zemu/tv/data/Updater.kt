package com.zemu.tv.data

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
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

/**
 * Updates from the project's GitHub Releases: the newest release's `Zemu-AndroidTV-<version>.apk`
 * is downloaded and handed to Android's installer. Releases must be signed with the same key as the
 * installed app, or Android refuses the update.
 */
class Updater(private val app: Context) {
    private val http = OkHttpClient()
    private val json = Json { ignoreUnknownKeys = true }

    val available = MutableStateFlow<AppUpdate?>(null)
    /** Set by Settings → Check for updates: show the prompt even if it was put off. */
    val showNow = MutableStateFlow(false)
    /** 0..1 while the APK downloads; null otherwise. */
    val progress = MutableStateFlow<Float?>(null)

    val currentVersion: String =
        runCatching { app.packageManager.getPackageInfo(app.packageName, 0).versionName }.getOrNull() ?: "0"

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
            ?.firstOrNull { a -> a.str("name").let { it.startsWith("Zemu-AndroidTV-") && it.endsWith(".apk") } }
        val update = apk?.takeIf { isNewer(version, currentVersion) }?.let {
            AppUpdate(version, o.str("body"), it.str("browser_download_url"), it["size"]?.jsonPrimitive?.longOrNull ?: 0)
        }
        available.value = update
        update
    }

    /**
     * Downloads [u] and opens the system installer. Returns false (and opens the "install unknown
     * apps" screen) when Zemu isn't allowed to install apps yet; the caller asks the user to retry.
     */
    suspend fun install(u: AppUpdate): Boolean {
        if (android.os.Build.VERSION.SDK_INT >= 26 && !app.packageManager.canRequestPackageInstalls()) {
            val opened = runCatching {
                app.startActivity(
                    Intent(android.provider.Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${app.packageName}"))
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                )
            }.isSuccess
            // Some TV builds have no such screen; the installer then asks on its own.
            if (opened) return false
        }
        val file = File(app.cacheDir, "updates/zemu-update.apk").apply { parentFile?.mkdirs() }
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
            } finally {
                progress.value = null
            }
        }
        val uri = FileProvider.getUriForFile(app, "${app.packageName}.updates", file)
        app.startActivity(
            Intent(Intent.ACTION_VIEW).setDataAndType(uri, "application/vnd.android.package-archive")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK),
        )
        return true
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
