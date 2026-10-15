package com.zemu.tv.ui.components

import com.zemu.tv.ui.theme.DialogBackdropBlur
import com.zemu.tv.ui.theme.glassPanel
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.tv.material3.Text
import com.zemu.tv.data.Meta
import com.zemu.tv.data.title
import com.zemu.tv.data.trailerId
import com.zemu.tv.ui.theme.Palette

/** Opens the long-press menu for a title (plus row options when the card sits in a movable row). Provided by the app shell. */
val LocalCardMenu = staticCompositionLocalOf<(Meta, (() -> Unit)?) -> Unit> { { _, _ -> } }

/** Set by screens with movable rows: opens the move/favorite popup for the row a card is in. */
val LocalRowOptions = staticCompositionLocalOf<(() -> Unit)?> { null }

/** Ids of titles marked watched, for the ✓ badge on cards. */
val LocalWatched = compositionLocalOf<Set<String>> { emptySet() }

enum class CardAction(val label: String) {
    PLAY("Play"),
    DETAILS("Details"),
    EPISODES("Episodes"),
    MORE_LIKE_THIS("More like this"),
    TRAILER("View trailer"),
    MY_LIST_ADD("Add to My List"),
    MY_LIST_REMOVE("Remove from My List"),
    MARK_WATCHED("Mark as watched"),
    MARK_UNWATCHED("Mark as unwatched"),
    REMOVE_HISTORY("Remove from history"),
    ROW_OPTIONS("Move or favorite this row"),
}

fun cardActions(meta: Meta, watched: Boolean, inMyList: Boolean, inHistory: Boolean, rowOptions: Boolean = false): List<CardAction> = buildList {
    add(CardAction.PLAY)
    add(CardAction.DETAILS)
    if (meta.type == "series") add(CardAction.EPISODES)
    add(CardAction.MORE_LIKE_THIS)
    if (meta.trailerId != null) add(CardAction.TRAILER)
    add(if (inMyList) CardAction.MY_LIST_REMOVE else CardAction.MY_LIST_ADD)
    add(if (watched) CardAction.MARK_UNWATCHED else CardAction.MARK_WATCHED)
    if (inHistory) add(CardAction.REMOVE_HISTORY)
    if (rowOptions) add(CardAction.ROW_OPTIONS)
}

@Composable
fun CardMenuDialog(meta: Meta, actions: List<CardAction>, onAction: (CardAction) -> Unit, onDismiss: () -> Unit) {
    val first = remember { FocusRequester() }
    // The OK press that opened the menu is usually still held; ignore it until it's released so it
    // can't "click" the first item (Details) by repeating or on key-up.
    var armed by remember { mutableStateOf(false) }
    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        DialogBackdropBlur()
        Row(
            Modifier
                .onPreviewKeyEvent { e ->
                    val center = e.key == Key.DirectionCenter || e.key == Key.Enter || e.key == Key.NumPadEnter
                    if (!center || armed) return@onPreviewKeyEvent false
                    when {
                        e.type == KeyEventType.KeyUp -> { armed = true; true }
                        e.nativeKeyEvent.repeatCount > 0 -> true
                        else -> { armed = true; false }
                    }
                }
                .width(600.dp)
                .glassPanel(RoundedCornerShape(14.dp))
                .padding(20.dp),
        ) {
            Column(Modifier.width(170.dp)) {
                PosterImage(meta, Modifier.fillMaxWidth().height(255.dp))
            }
            Spacer(Modifier.width(20.dp))
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(meta.title, fontWeight = FontWeight.Bold, fontSize = 20.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
                Text(
                    listOfNotNull(meta.releaseInfo, if (meta.type == "series") "Series" else "Movie", meta.imdbRating?.let { "★ $it" }).joinToString("  ·  "),
                    color = Palette.TextSecondary, fontSize = 13.sp,
                )
                Spacer(Modifier.size(6.dp))
                actions.forEachIndexed { i, a ->
                    FocusSurface(
                        onClick = { onAction(a); onDismiss() },
                        modifier = Modifier.fillMaxWidth().then(if (i == 0) Modifier.focusRequester(first) else Modifier),
                        containerColor = Color.Transparent,
                        focusedScale = 1.02f,
                    ) {
                        Row(Modifier.padding(horizontal = 14.dp, vertical = 9.dp), verticalAlignment = Alignment.CenterVertically) {
                            Text(a.label, fontSize = 16.sp, maxLines = 1)
                        }
                    }
                }
            }
        }
    }
    LaunchedEffect(Unit) { runCatching { first.requestFocus() } }
}
