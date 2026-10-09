package com.zemu.tv.launcher

import android.annotation.SuppressLint
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import androidx.tvprovider.media.tv.TvContractCompat
import androidx.tvprovider.media.tv.WatchNextProgram
import com.zemu.tv.data.WatchEntry
import com.zemu.tv.data.backdropUrl
import com.zemu.tv.data.posterUrl
import com.zemu.tv.data.title

/**
 * Publishes Continue Watching to the Android TV home screen's "Play Next" row and refreshes the
 * phone widget. Each entry opens the title's page in Zemu.
 */
object WatchNext {
    private const val PREFS = "watch_next"

    fun deepLink(type: String, id: String): Uri = Uri.parse("zemu://details/${Uri.encode(type)}/${Uri.encode(id)}")

    fun openIntent(context: Context, type: String, id: String): Intent =
        Intent(Intent.ACTION_VIEW, deepLink(type, id)).setPackage(context.packageName).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

    fun update(context: Context, inProgress: List<WatchEntry>) {
        ContinueWatchingWidget.refresh(context, inProgress)
        if (!context.packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK)) return
        runCatching { publish(context, inProgress.take(10)) }
    }

    @SuppressLint("RestrictedApi")
    private fun publish(context: Context, entries: List<WatchEntry>) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val resolver = context.contentResolver
        val existing = prefs.all.mapValues { (it.value as? Long) ?: -1L } // metaId -> program id
        val wanted = entries.associateBy { it.meta.id }

        // Remove titles that are no longer in progress.
        existing.filterKeys { it !in wanted }.forEach { (metaId, programId) ->
            runCatching { resolver.delete(TvContractCompat.buildWatchNextProgramUri(programId), null, null) }
            prefs.edit().remove(metaId).apply()
        }

        entries.forEachIndexed { i, e ->
            val m = e.meta
            val program = WatchNextProgram.Builder()
                .setType(if (m.type == "series") TvContractCompat.WatchNextPrograms.TYPE_TV_EPISODE else TvContractCompat.WatchNextPrograms.TYPE_MOVIE)
                .setWatchNextType(TvContractCompat.WatchNextPrograms.WATCH_NEXT_TYPE_CONTINUE)
                .setLastEngagementTimeUtcMillis(e.updatedAt - i) // keep our order
                .setTitle(m.title)
                .setDescription(e.label ?: m.description?.take(200))
                .setPosterArtUri(Uri.parse(m.backdropUrl() ?: m.posterUrl() ?: ""))
                .setPosterArtAspectRatio(TvContractCompat.PreviewPrograms.ASPECT_RATIO_16_9)
                .setLastPlaybackPositionMillis(e.positionMs.toInt())
                .setDurationMillis(e.durationMs.toInt())
                .setIntent(openIntent(context, m.type, m.id))
                .setInternalProviderId(m.id)
                .build()
            val id = existing[m.id]
            if (id != null && id >= 0) {
                val updated = runCatching {
                    resolver.update(TvContractCompat.buildWatchNextProgramUri(id), program.toContentValues(), null, null)
                }.getOrDefault(0)
                if (updated > 0) return@forEachIndexed
            }
            val uri = runCatching { resolver.insert(TvContractCompat.WatchNextPrograms.CONTENT_URI, program.toContentValues()) }.getOrNull()
            if (uri != null) prefs.edit().putLong(m.id, ContentUris.parseId(uri)).apply()
        }
    }
}
