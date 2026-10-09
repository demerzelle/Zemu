package com.zemu.tv.launcher

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import com.zemu.tv.MainActivity
import com.zemu.tv.R
import com.zemu.tv.container
import com.zemu.tv.data.WatchEntry
import com.zemu.tv.data.title

/** Home-screen widget (phones and tablets) listing up to four titles to continue. */
class ContinueWatchingWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        val entries = runCatching {
            context.container.userStore.history.value.filter { it.progress in 0.01f..0.95f }.distinctBy { it.meta.id }
        }.getOrDefault(emptyList())
        render(context, manager, ids, entries)
    }

    companion object {
        private val rows = listOf(
            Triple(R.id.cw_row1, R.id.cw_title1, R.id.cw_sub1),
            Triple(R.id.cw_row2, R.id.cw_title2, R.id.cw_sub2),
            Triple(R.id.cw_row3, R.id.cw_title3, R.id.cw_sub3),
            Triple(R.id.cw_row4, R.id.cw_title4, R.id.cw_sub4),
        )

        fun refresh(context: Context, entries: List<WatchEntry>) {
            val manager = AppWidgetManager.getInstance(context) ?: return
            val ids = runCatching { manager.getAppWidgetIds(ComponentName(context, ContinueWatchingWidget::class.java)) }.getOrNull() ?: return
            if (ids.isNotEmpty()) render(context, manager, ids, entries)
        }

        private fun render(context: Context, manager: AppWidgetManager, ids: IntArray, entries: List<WatchEntry>) {
            val views = RemoteViews(context.packageName, R.layout.widget_continue_watching)
            val open = PendingIntent.getActivity(
                context, 0, Intent(context, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            views.setOnClickPendingIntent(R.id.cw_header, open)
            views.setViewVisibility(R.id.cw_empty, if (entries.isEmpty()) android.view.View.VISIBLE else android.view.View.GONE)
            rows.forEachIndexed { i, (row, title, sub) ->
                val e = entries.getOrNull(i)
                if (e == null) {
                    views.setViewVisibility(row, android.view.View.GONE)
                } else {
                    views.setViewVisibility(row, android.view.View.VISIBLE)
                    views.setTextViewText(title, e.meta.title)
                    views.setTextViewText(sub, listOfNotNull(e.label, "${(e.progress * 100).toInt()}% watched").joinToString(" · "))
                    val pi = PendingIntent.getActivity(
                        context, 100 + i, WatchNext.openIntent(context, e.meta.type, e.meta.id),
                        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
                    )
                    views.setOnClickPendingIntent(row, pi)
                }
            }
            ids.forEach { manager.updateAppWidget(it, views) }
        }
    }
}
