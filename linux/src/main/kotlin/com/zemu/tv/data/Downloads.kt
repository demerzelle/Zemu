package com.zemu.tv.data

import android.content.Context
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit

/** A title (or episode) saved on this computer for offline playback. */
@Serializable
data class DownloadItem(
    val id: Long,
    val meta: Meta,
    val videoId: String,
    val label: String? = null,
    val path: String,
    /** Kept so an unfinished download picks up where it stopped after Zemu restarts. */
    val url: String = "",
    val headers: Map<String, String> = emptyMap(),
)

/** Where a download stands: [progress] 0–1, [bytes] downloaded so far. */
data class DownloadState(val status: Int, val progress: Float, val bytes: Long, val error: String? = null) {
    val done: Boolean get() = status == STATUS_SUCCESSFUL
    val failed: Boolean get() = status == STATUS_FAILED

    companion object {
        const val STATUS_RUNNING = 2
        const val STATUS_SUCCESSFUL = 8
        const val STATUS_FAILED = 16
    }
}

/**
 * Downloads for offline playback, done by Zemu itself (Linux has no system download manager).
 * Files go to ~/Videos/Zemu (your XDG videos folder). Data is written to "<name>.part" and renamed
 * when complete; an interrupted download resumes with an HTTP Range request, after network errors
 * (up to [MAX_RETRIES] times) and after Zemu restarts. Shared by every profile on the computer.
 */
class Downloads(context: Context, private val json: Json) {
    private val file = File(context.filesDir, "downloads.json")
    private val ser = ListSerializer(DownloadItem.serializer())
    val items = MutableStateFlow(runCatching { json.decodeFromString(ser, file.readText()) }.getOrDefault(emptyList()))

    private val http = OkHttpClient.Builder()
        .connectTimeout(20, TimeUnit.SECONDS)
        .readTimeout(60, TimeUnit.SECONDS)
        .build()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val jobs = ConcurrentHashMap<Long, Job>()
    private val live = ConcurrentHashMap<Long, DownloadState>()

    val folder: File by lazy {
        val videos = runCatching {
            val p = ProcessBuilder("xdg-user-dir", "VIDEOS").redirectErrorStream(true).start()
            p.inputStream.bufferedReader().readText().trim().also { p.waitFor(2, TimeUnit.SECONDS) }
        }.getOrNull()?.takeIf { it.isNotBlank() && it != System.getProperty("user.home") }
            ?: (System.getProperty("user.home") + "/Videos")
        File(videos, "Zemu")
    }

    /** False when the downloads folder can't be created or written. */
    val available: Boolean get() = folder.let { (it.isDirectory || it.mkdirs()) && it.canWrite() }

    init {
        // Pick unfinished downloads back up.
        items.value.filter { !File(it.path).exists() && it.url.isNotBlank() }.forEach(::run)
    }

    /** Starts downloading [url]; returns an error to show, or null when it started. */
    fun start(meta: Meta, videoId: String, label: String?, url: String, headers: Map<String, String>, fileName: String?, sizeBytes: Long?): String? {
        if (!url.startsWith("http")) return "This stream can't be downloaded."
        if (!available) return "Can't write to ${folder.path}."
        if (items.value.any { it.meta.id == meta.id && it.videoId == videoId }) return "Already downloaded or downloading."
        val free = folder.usableSpace
        if (sizeBytes != null && sizeBytes > free) return "Not enough space: needs %.1f GB, %.1f GB free.".format(sizeBytes / 1e9, free / 1e9)
        val ext = fileName?.substringAfterLast('.', "")?.takeIf { it.length in 2..4 && it.all(Char::isLetterOrDigit) } ?: "mkv"
        val name = (listOfNotNull(meta.title, label).joinToString(" - ").replace(Regex("[^A-Za-z0-9 ._-]"), "").take(80).ifBlank { "video" }) + " [${System.currentTimeMillis()}].$ext"
        val item = DownloadItem(System.currentTimeMillis(), meta.slim(), videoId, label, File(folder, name).path, url, headers)
        save(items.value + item)
        run(item)
        return null
    }

    fun state(item: DownloadItem): DownloadState {
        live[item.id]?.let { return it }
        val f = File(item.path)
        if (f.exists()) return DownloadState(DownloadState.STATUS_SUCCESSFUL, 1f, f.length())
        val part = File(item.path + ".part")
        return DownloadState(DownloadState.STATUS_FAILED, 0f, part.length())
    }

    /** Cancels it if still running and deletes the file. */
    fun remove(item: DownloadItem) {
        jobs.remove(item.id)?.cancel()
        live.remove(item.id)
        File(item.path).delete()
        File(item.path + ".part").delete()
        save(items.value.filterNot { it.id == item.id })
    }

    private fun run(item: DownloadItem) {
        live[item.id] = DownloadState(DownloadState.STATUS_RUNNING, 0f, File(item.path + ".part").length())
        jobs[item.id] = scope.launch {
            val target = File(item.path)
            val part = File(item.path + ".part")
            target.parentFile?.mkdirs()
            var attempt = 0
            while (true) {
                try {
                    download(item, part)
                    if (!part.renameTo(target)) throw IOException("Couldn't save ${target.name}")
                    live[item.id] = DownloadState(DownloadState.STATUS_SUCCESSFUL, 1f, target.length())
                    return@launch
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    if (++attempt > MAX_RETRIES || e is HttpGone) {
                        live[item.id] = DownloadState(DownloadState.STATUS_FAILED, 0f, part.length(), e.message)
                        return@launch
                    }
                    live[item.id] = DownloadState(DownloadState.STATUS_RUNNING, live[item.id]?.progress ?: 0f, part.length(), "Retrying…")
                    delay(3_000L * attempt)
                }
            }
        }.also { it.invokeOnCompletion { _ -> jobs.remove(item.id) } }
    }

    private class HttpGone(code: Int) : IOException("The link stopped working (HTTP $code)")

    private suspend fun download(item: DownloadItem, part: File) {
        val have = part.length()
        val req = Request.Builder().url(item.url).apply {
            item.headers.forEach { (k, v) -> header(k, v) }
            if (have > 0) header("Range", "bytes=$have-")
        }.build()
        http.newCall(req).execute().use { r ->
            // Everything was already there.
            if (r.code == 416 && have > 0) return
            if (r.code in 400..499) throw HttpGone(r.code)
            if (!r.isSuccessful) throw IOException("HTTP ${r.code}")
            val body = r.body ?: throw IOException("Empty response")
            val resumed = have > 0 && r.code == 206
            val start = if (resumed) have else 0L
            val total = r.header("Content-Range")?.substringAfterLast('/')?.toLongOrNull()
                ?: body.contentLength().takeIf { it > 0 }?.plus(start) ?: -1L
            var done = start
            FileOutputStream(part, resumed).use { out ->
                body.byteStream().use { input ->
                    val buf = ByteArray(256 * 1024)
                    while (true) {
                        kotlin.coroutines.coroutineContext.ensureActive()
                        val n = input.read(buf)
                        if (n < 0) break
                        out.write(buf, 0, n)
                        done += n
                        live[item.id] = DownloadState(DownloadState.STATUS_RUNNING, if (total > 0) done.toFloat() / total else 0f, done)
                    }
                }
            }
            if (total > 0 && done < total) throw IOException("Connection closed early")
        }
    }

    private fun save(list: List<DownloadItem>) {
        items.value = list
        runCatching { file.writeText(json.encodeToString(ser, list)) }
    }

    private companion object { const val MAX_RETRIES = 5 }
}
