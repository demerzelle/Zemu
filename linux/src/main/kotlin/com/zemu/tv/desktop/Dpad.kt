package com.zemu.tv.desktop

import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusDirection
import androidx.compose.ui.focus.FocusManager
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEvent
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.window.DialogProperties
import com.zemu.tv.ui.SoundFx

/**
 * Arrows move focus like a TV remote's D-pad (the Xbox controller sends arrows too). Used after the
 * focused control had its chance, so text fields and lists keep their own arrow keys.
 */
fun dpadMove(e: KeyEvent, focus: FocusManager): Boolean {
    if (e.type != KeyEventType.KeyDown) return false
    val dir = when (e.key) {
        Key.DirectionUp -> FocusDirection.Up
        Key.DirectionDown -> FocusDirection.Down
        Key.DirectionLeft -> FocusDirection.Left
        Key.DirectionRight -> FocusDirection.Right
        else -> return false
    }
    return focus.moveFocus(dir).also { if (it) SoundFx.play(SoundFx.Event.MOVE) }
}

/**
 * Every shared dialog is built with this (swapped in at build time): a dialog has its own focus
 * layer, so it needs its own arrow-key navigation. Backspace closes it like Esc does.
 */
@Composable
fun DpadDialog(onDismissRequest: () -> Unit, properties: DialogProperties = DialogProperties(), content: @Composable () -> Unit) {
    androidx.compose.ui.window.Dialog(onDismissRequest = onDismissRequest, properties = properties) {
        val focus = LocalFocusManager.current
        Box(
            Modifier.onKeyEvent { e ->
                if (e.type == KeyEventType.KeyDown && e.key == Key.Backspace) { SoundFx.play(SoundFx.Event.BACK); onDismissRequest(); true }
                else dpadMove(e, focus)
            },
        ) { content() }
    }
}
