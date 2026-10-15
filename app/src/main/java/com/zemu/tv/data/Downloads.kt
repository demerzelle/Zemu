package com.zemu.tv.data

import android.app.DownloadManager
import android.content.Context
import android.net.Uri
import android.os.Environment
import android.os.StatFs
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json
import java.io.File

/** A title (or episode) saved on this device for offline playback. */
@Serializable
data class DownloadItem(
    /** DownloadManager's id. */
    val id: Long,
    val meta: Meta,
    val videoId: String,
    val label: String? = null,
    val path: String,
)

/** Where a download stands: [progress] 0–1, [bytes] downloaded so far. */
data class DownloadState(val status: Int, val progress: Float, val bytes: Long) {
    val done: Boolean get() = status == DownloadManager.STATUS_SUCCESSFUL
    val failed: Boolean get() = status == DownloadManager.STATUS_FAILED
}

/**
 * Downloads for offline playback, through Android's DownloadManager (it keeps going in the
 * background and shows a notification). Files go to the app's own movies folder, which needs no
 * storage permission and is removed with the app. Shared by every profile on the device.
 */
class Downloads(private val context: Context, private val json: Json) {
    private val dm = context.getSystemService(DownloadManager::class.java)
    private val file = File(context.filesDir, "downloads.json")
    private val ser = ListSerializer(DownloadItem.serializer())
    val items = MutableStateFlow(runCatching { json.decodeFromString(ser, file.readText()) }.getOrDefault(emptyList()))

    private val folder: File? get() = context.getExternalFilesDir(Environment.DIRECTORY_MOVIES)

    /** False on devices without storage for downloads. */
    val available: Boolean get() = dm != null && folder != null

    /** Starts downloading [url]; returns an error to show, or null when it started. */
    fun start(meta: Meta, videoId: String, label: String?, url: String, headers: Map<String, String>, fileName: String?, sizeBytes: Long?): String? {
        val dir = folder ?: return "This device has no storage for downloads."
        if (dm == null) return "Downloads aren't supported on this device."
        if (items.value.any { it.meta.id == meta.id && it.videoId == videoId }) return "Already downloaded or downloading."
        val free = runCatching { StatFs(dir.path).availableBytes }.getOrDefault(Long.MAX_VALUE)
        if (sizeBytes != null && sizeBytes > free) return "Not enough space: needs %.1f GB, %.1f GB free.".format(sizeBytes / 1e9, free / 1e9)
        val ext = fileName?.substringAfterLast('.', "")?.takeIf { it.length in 2..4 } ?: "mkv"
        val name = (listOfNotNull(meta.title, label).joinToString(" - ").replace(Regex("[^A-Za-z0-9 ._-]"), "").take(80).ifBlank { "video" }) + " [${System.currentTimeMillis()}].$ext"
        val target = File(dir, name)
        val req = DownloadManager.Request(Uri.parse(url))
            .setTitle(listOfNotNull(meta.title, label).joinToString(" · "))
            .setDescription("Zemu download")
            .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
            .setDestinationUri(Uri.fromFile(target))
        headers.forEach { (k, v) -> req.addRequestHeader(k, v) }
        val id = runCatching { dm.enqueue(req) }.getOrElse { return "Couldn't start the download: ${it.message}" }
        save(items.value + DownloadItem(id, meta.slim(), videoId, label, target.path))
        return null
    }

    fun state(item: DownloadItem): DownloadState {
        val q = dm?.query(DownloadManager.Query().setFilterById(item.id))
        q?.use { c ->
            if (c.moveToFirst()) {
                val status = c.getInt(c.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))
                val done = c.getLong(c.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR))
                val total = c.getLong(c.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES))
                return DownloadState(status, if (total > 0) done.toFloat() / total else 0f, done)
            }
        }
        // DownloadManager forgot it (e.g. cleared app data): the file decides.
        val f = File(item.path)
        return if (f.exists()) DownloadState(DownloadManager.STATUS_SUCCESSFUL, 1f, f.length()) else DownloadState(DownloadManager.STATUS_FAILED, 0f, 0)
    }

    /** Cancels it if still running and deletes the file. */
    fun remove(item: DownloadItem) {
        runCatching { dm?.remove(item.id) }
        File(item.path).delete()
        save(items.value.filterNot { it.id == item.id })
    }

    private fun save(list: List<DownloadItem>) {
        items.value = list
        runCatching { file.writeText(json.encodeToString(ser, list)) }
    }
}
