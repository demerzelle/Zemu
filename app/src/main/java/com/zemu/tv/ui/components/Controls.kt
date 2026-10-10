package com.zemu.tv.ui.components

import com.zemu.tv.ui.theme.DialogBackdropBlur
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.focus.focusProperties
import androidx.compose.ui.input.key.onKeyEvent
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.foundation.gestures.waitForUpOrCancellation
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.focusable
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusDirection
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.tv.material3.Border
import androidx.tv.material3.ClickableSurfaceDefaults
import androidx.tv.material3.Icon
import androidx.tv.material3.MaterialTheme
import androidx.tv.material3.Surface
import androidx.tv.material3.Text
import com.zemu.tv.ui.theme.Palette
import com.zemu.tv.ui.theme.glassPanel

/** Focusable D-pad surface with TV-style scale + colour change on focus. */
@Composable
fun FocusSurface(
    onClick: () -> Unit,
    onLongClick: (() -> Unit)? = null,
    modifier: Modifier = Modifier,
    shape: Shape = RoundedCornerShape(8.dp),
    focusedScale: Float = 1.05f,
    containerColor: Color = Palette.SurfaceHigh,
    contentColor: Color = Palette.Text,
    focusedContainerColor: Color = Palette.Focus,
    focusedContentColor: Color = Palette.OnFocus,
    focusedBorder: Color? = null,
    content: @Composable BoxScope.() -> Unit,
) {
    Surface(
        onClick = onClick,
        onLongClick = onLongClick,
        modifier = modifier.touchClick(onClick, onLongClick),
        shape = ClickableSurfaceDefaults.shape(shape = shape),
        colors = ClickableSurfaceDefaults.colors(
            containerColor = containerColor,
            contentColor = contentColor,
            focusedContainerColor = focusedContainerColor,
            focusedContentColor = focusedContentColor,
            pressedContainerColor = focusedContainerColor,
            pressedContentColor = focusedContentColor,
        ),
        scale = ClickableSurfaceDefaults.scale(focusedScale = focusedScale),
        border = if (focusedBorder != null) {
            ClickableSurfaceDefaults.border(focusedBorder = Border(BorderStroke(2.dp, focusedBorder), shape = shape))
        } else ClickableSurfaceDefaults.border(),
        content = content,
    )
}

@Composable
fun TvButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    icon: ImageVector? = null,
    primary: Boolean = false,
) {
    FocusSurface(
        onClick = onClick,
        modifier = modifier,
        shape = RoundedCornerShape(6.dp),
        containerColor = if (primary) Palette.Accent else Palette.SurfaceHigh.copy(alpha = 0.9f),
        contentColor = if (primary) Palette.OnAccent else Palette.Text,
    ) {
        Row(
            Modifier.padding(horizontal = 22.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (icon != null) {
                Icon(icon, contentDescription = null, modifier = Modifier.size(20.dp))
                Spacer(Modifier.width(8.dp))
            }
            Text(text, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, softWrap = false)
        }
    }
}

/** Round icon-only button; [label] is announced and shown as a hint. */
@Composable
fun TvIconButton(icon: ImageVector, label: String, modifier: Modifier = Modifier, active: Boolean = false, onClick: () -> Unit) {
    FocusSurface(
        onClick = onClick,
        modifier = modifier.size(46.dp),
        shape = androidx.compose.foundation.shape.CircleShape,
        containerColor = if (active) Palette.Accent else Palette.SurfaceHigh.copy(alpha = 0.9f),
        contentColor = if (active) Palette.OnAccent else Palette.Text,
        focusedScale = 1.1f,
    ) {
        Icon(icon, contentDescription = label, modifier = Modifier.align(Alignment.Center).size(22.dp))
    }
}

@Composable
fun TvChip(
    label: String,
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    FocusSurface(
        onClick = onClick,
        modifier = modifier,
        shape = RoundedCornerShape(50),
        containerColor = if (selected) Palette.Accent else Palette.SurfaceHigh,
        contentColor = if (selected) Palette.OnAccent else Palette.Text,
        focusedScale = 1.06f,
    ) {
        Text(
            text = if (selected) "✓ $label" else label,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 7.dp),
            fontSize = 14.sp,
            fontWeight = FontWeight.Medium,
            maxLines = 1,
        )
    }
}

@Composable
fun ImdbBadge(rating: String?, modifier: Modifier = Modifier) {
    if (rating.isNullOrBlank() || rating.toDoubleOrNull()?.let { it <= 0 } == true) return
    Row(modifier, verticalAlignment = Alignment.CenterVertically) {
        Box(
            Modifier
                .background(Palette.Imdb, RoundedCornerShape(3.dp))
                .padding(horizontal = 4.dp, vertical = 1.dp),
        ) {
            Text("IMDb", color = Color.Black, fontWeight = FontWeight.Black, fontSize = 11.sp)
        }
        Spacer(Modifier.width(6.dp))
        Text(rating, fontWeight = FontWeight.Bold, fontSize = 14.sp)
    }
}

@Composable
fun Tag(text: String, color: Color, modifier: Modifier = Modifier, filled: Boolean = false) {
    Box(
        modifier
            .then(
                if (filled) Modifier.background(color, RoundedCornerShape(4.dp))
                else Modifier.border(1.dp, color.copy(alpha = 0.7f), RoundedCornerShape(4.dp)),
            )
            .padding(horizontal = 6.dp, vertical = 2.dp),
    ) {
        Text(text, color = if (filled) Color.Black else color, fontSize = 12.sp, fontWeight = FontWeight.Bold, maxLines = 1)
    }
}

@Composable
fun SectionTitle(text: String, modifier: Modifier = Modifier) {
    Text(text, modifier = modifier, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
}

/**
 * Text input that only opens the keyboard when it's clicked: OK on the remote or a tap. Moving
 * focus onto it (D-pad, or a screen focusing it on open) just highlights it.
 */
@Composable
fun TvTextField(
    value: String,
    onValueChange: (String) -> Unit,
    placeholder: String,
    modifier: Modifier = Modifier,
    imeAction: ImeAction = ImeAction.Done,
    onSubmit: () -> Unit = {},
) {
    var editing by remember { mutableStateOf(false) }
    var boxFocused by remember { mutableStateOf(false) }
    var fieldFocused by remember { mutableStateOf(false) }
    val fieldFocus = remember { FocusRequester() }
    val focusManager = LocalFocusManager.current
    val keyboard = LocalSoftwareKeyboardController.current
    LaunchedEffect(editing) {
        if (editing) {
            runCatching { fieldFocus.requestFocus() }
            keyboard?.show()
        }
    }
    val active = boxFocused || fieldFocused
    Box(
        modifier
            .onFocusChanged { boxFocused = it.isFocused }
            .onKeyEvent { e ->
                val ok = e.key == Key.DirectionCenter || e.key == Key.Enter || e.key == Key.NumPadEnter
                if (!editing && ok && e.type == KeyEventType.KeyDown) { editing = true; true } else false
            }
            .focusable()
            // Watch taps before the text field sees them, so a tap is what starts editing.
            .pointerInput(Unit) {
                awaitEachGesture {
                    awaitFirstDown(pass = PointerEventPass.Initial)
                    if (waitForUpOrCancellation(pass = PointerEventPass.Initial) != null) editing = true
                }
            }
            .background(if (active) Palette.SurfaceHigh else Palette.Surface, RoundedCornerShape(8.dp))
            .border(2.dp, if (active) Palette.FocusBorder else Color.Transparent, RoundedCornerShape(8.dp))
            .padding(horizontal = 16.dp, vertical = 12.dp),
    ) {
        BasicTextField(
            value = value,
            onValueChange = onValueChange,
            singleLine = true,
            textStyle = TextStyle(color = Palette.Text, fontSize = 18.sp),
            cursorBrush = SolidColor(Palette.Text),
            keyboardOptions = KeyboardOptions(imeAction = imeAction),
            keyboardActions = KeyboardActions(onDone = { onSubmit() }, onSearch = { onSubmit() }, onGo = { onSubmit() }),
            modifier = Modifier
                .fillMaxWidth()
                .focusRequester(fieldFocus)
                // Not focusable until clicked, so D-pad focus can't open the keyboard by itself.
                .focusProperties { canFocus = editing }
                .onFocusChanged {
                    if (fieldFocused && !it.isFocused) editing = false
                    fieldFocused = it.isFocused
                }
                // Single-line fields swallow Up/Down; on a remote that traps focus, so hand them back.
                .onPreviewKeyEvent { e ->
                    if (e.type != KeyEventType.KeyDown) return@onPreviewKeyEvent false
                    when (e.key) {
                        Key.DirectionDown -> focusManager.moveFocus(FocusDirection.Down)
                        Key.DirectionUp -> focusManager.moveFocus(FocusDirection.Up)
                        else -> false
                    }
                },
            decorationBox = { inner ->
                Box {
                    if (value.isEmpty()) Text(placeholder, color = Palette.TextMuted, fontSize = 18.sp, maxLines = 1)
                    inner()
                }
            },
        )
    }
}

data class ChoiceOption(val value: String, val label: String, val trailing: String? = null)

/** Modal list of options; single- or multi-select. */
@Composable
fun ChoiceDialog(
    title: String,
    options: List<ChoiceOption>,
    selected: Set<String>,
    onToggle: (String) -> Unit,
    onDismiss: () -> Unit,
    multiSelect: Boolean = true,
    onClear: (() -> Unit)? = null,
) {
    val first = remember { FocusRequester() }
    Dialog(onDismissRequest = onDismiss) {
        DialogBackdropBlur()
        Column(
            Modifier
                .width(480.dp)
                .heightIn(max = 560.dp)
                .glassPanel(RoundedCornerShape(14.dp))
                .padding(24.dp),
        ) {
            Text(title, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
            Spacer(Modifier.size(14.dp))
            if (options.isEmpty()) {
                Text("No options for the current results.", color = Palette.TextSecondary)
            }
            LazyColumn(
                Modifier.weight(1f, fill = false),
                verticalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                items(options, key = { it.value }) { o ->
                    val isOn = o.value in selected
                    FocusSurface(
                        onClick = {
                            onToggle(o.value)
                            if (!multiSelect) onDismiss()
                        },
                        modifier = Modifier
                            .fillMaxWidth()
                            .then(if (o == options.first()) Modifier.focusRequester(first) else Modifier),
                        containerColor = if (isOn) Palette.SurfaceHigh else Color.Transparent,
                        focusedScale = 1.02f,
                    ) {
                        Row(Modifier.padding(horizontal = 14.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                            Text(
                                if (multiSelect) (if (isOn) "☑" else "☐") else (if (isOn) "◉" else "○"),
                                fontSize = 18.sp,
                            )
                            Spacer(Modifier.width(12.dp))
                            Text(o.label, modifier = Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis)
                            if (o.trailing != null) Text(o.trailing, fontSize = 13.sp)
                        }
                    }
                }
            }
            Spacer(Modifier.size(16.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                if (onClear != null) TvButton("Clear", onClick = onClear)
                TvButton("Done", onClick = onDismiss, primary = true)
            }
        }
    }
    LaunchedEffect(Unit) { runCatching { first.requestFocus() } }
}

@Composable
fun CenteredMessage(title: String, body: String? = null, modifier: Modifier = Modifier, action: (@Composable () -> Unit)? = null) {
    Column(modifier.padding(48.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Text(title, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
        if (body != null) {
            Spacer(Modifier.size(8.dp))
            Text(body, color = Palette.TextSecondary, fontSize = 15.sp)
        }
        if (action != null) {
            Spacer(Modifier.size(16.dp))
            action()
        }
    }
}

/** Yes/no dialog for destructive actions. */
@Composable
fun ConfirmDialog(title: String, message: String, confirmLabel: String, onConfirm: () -> Unit, onDismiss: () -> Unit) {
    val cancel = remember { FocusRequester() }
    Dialog(onDismissRequest = onDismiss) {
        DialogBackdropBlur()
        Column(
            Modifier
                .width(520.dp)
                .glassPanel(RoundedCornerShape(14.dp))
                .padding(24.dp),
        ) {
            Text(title, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
            Spacer(Modifier.size(10.dp))
            Text(message, color = Palette.TextSecondary, fontSize = 15.sp)
            Spacer(Modifier.size(18.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                TvButton("Cancel", onClick = onDismiss, modifier = Modifier.focusRequester(cancel))
                TvButton(confirmLabel, onClick = onConfirm, primary = true)
            }
        }
    }
    LaunchedEffect(Unit) { runCatching { cancel.requestFocus() } }
}

/** One row in an [ActionSheet]. [detail] shows on the right, e.g. the current value. */
data class SheetAction(val label: String, val detail: String? = null, val onClick: () -> Unit)

/**
 * A small menu of actions ("More", "Filters"): keeps rarely used buttons off the main screens.
 * Picking an action closes the sheet first, so actions can open their own dialogs.
 */
@Composable
fun ActionSheet(title: String, actions: List<SheetAction>, onDismiss: () -> Unit) {
    val first = remember { FocusRequester() }
    LaunchedEffect(Unit) { kotlinx.coroutines.delay(60); runCatching { first.requestFocus() } }
    androidx.compose.ui.window.Dialog(onDismissRequest = onDismiss) {
        DialogBackdropBlur()
        Column(
            Modifier
                .width(440.dp)
                .glassPanel(RoundedCornerShape(16.dp))
                .padding(vertical = 18.dp, horizontal = 14.dp),
        ) {
            Text(title, fontSize = 20.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(start = 10.dp, bottom = 10.dp))
            actions.forEachIndexed { i, a ->
                FocusSurface(
                    onClick = { onDismiss(); a.onClick() },
                    modifier = Modifier.fillMaxWidth().padding(vertical = 2.dp).then(if (i == 0) Modifier.focusRequester(first) else Modifier),
                    shape = RoundedCornerShape(10.dp),
                    containerColor = Color.Transparent,
                    contentColor = Palette.Text,
                    focusedScale = 1.02f,
                ) {
                    Row(Modifier.padding(horizontal = 14.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text(a.label, fontSize = 16.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
                        a.detail?.let { Text(it, fontSize = 14.sp, color = androidx.tv.material3.LocalContentColor.current.copy(alpha = 0.7f)) }
                    }
                }
            }
        }
    }
}
