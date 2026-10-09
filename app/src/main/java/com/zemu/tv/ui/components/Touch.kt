package com.zemu.tv.ui.components

import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.input.pointer.pointerInput

/**
 * Tap and long-press for touch screens. TV Material surfaces only react to remote keys, so this
 * adds touch on top; it doesn't change anything for D-pad users.
 *
 * Touching an item (including the touch that starts a scroll) highlights it the way D-pad focus
 * does, updating the hero and info; it only opens on a tap, or the menu on a long press.
 */
fun Modifier.touchClick(onClick: () -> Unit, onLongClick: (() -> Unit)? = null): Modifier = composed {
    val click by rememberUpdatedState(onClick)
    val long by rememberUpdatedState(onLongClick)
    val focus = remember { FocusRequester() }
    focusRequester(focus).pointerInput(Unit) {
        detectTapGestures(
            onPress = { runCatching { focus.requestFocus() } },
            onTap = { click() },
            onLongPress = { long?.invoke() ?: click() },
        )
    }
}
