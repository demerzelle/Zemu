package androidx.tv.material3

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsFocusedAsState
import androidx.compose.foundation.interaction.collectIsHoveredAsState
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.Typography
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.painter.Painter
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.PointerEventType
import androidx.compose.ui.input.pointer.isSecondaryPressed
import androidx.compose.ui.input.pointer.onPointerEvent
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.TextUnit

// Desktop stand-ins for the few Compose-for-TV components Zemu uses, built on Material 3.
// Focus works like on a TV: the focused (or hovered) surface scales up and changes color.

val LocalContentColor = androidx.compose.material3.LocalContentColor
val LocalTextStyle = androidx.compose.material3.LocalTextStyle
typealias Typography = androidx.compose.material3.Typography

object MaterialTheme {
    val typography: Typography @Composable @ReadOnlyComposable get() = androidx.compose.material3.MaterialTheme.typography
    val colorScheme: ColorScheme @Composable @ReadOnlyComposable get() = androidx.compose.material3.MaterialTheme.colorScheme
}

@Composable
fun MaterialTheme(colorScheme: ColorScheme, typography: Typography, content: @Composable () -> Unit) =
    androidx.compose.material3.MaterialTheme(colorScheme = colorScheme, typography = typography, content = content)

fun darkColorScheme(
    primary: Color = Color(0xFFD0BCFF), onPrimary: Color = Color(0xFF381E72),
    surface: Color = Color(0xFF1C1B1F), onSurface: Color = Color(0xFFE6E1E5),
    background: Color = Color(0xFF1C1B1F), onBackground: Color = Color(0xFFE6E1E5),
    surfaceVariant: Color = Color(0xFF49454F), onSurfaceVariant: Color = Color(0xFFCAC4D0),
    secondary: Color = Color(0xFFCCC2DC), onSecondary: Color = Color(0xFF332D41),
    error: Color = Color(0xFFF2B8B5),
) = androidx.compose.material3.darkColorScheme(
    primary = primary, onPrimary = onPrimary, surface = surface, onSurface = onSurface,
    background = background, onBackground = onBackground, surfaceVariant = surfaceVariant,
    onSurfaceVariant = onSurfaceVariant, secondary = secondary, onSecondary = onSecondary, error = error,
)

@Composable
fun Text(
    text: String,
    modifier: Modifier = Modifier,
    color: Color = Color.Unspecified,
    fontSize: TextUnit = TextUnit.Unspecified,
    fontStyle: FontStyle? = null,
    fontWeight: FontWeight? = null,
    fontFamily: FontFamily? = null,
    letterSpacing: TextUnit = TextUnit.Unspecified,
    textDecoration: TextDecoration? = null,
    textAlign: TextAlign? = null,
    lineHeight: TextUnit = TextUnit.Unspecified,
    overflow: TextOverflow = TextOverflow.Clip,
    softWrap: Boolean = true,
    maxLines: Int = Int.MAX_VALUE,
    minLines: Int = 1,
    onTextLayout: (TextLayoutResult) -> Unit = {},
    style: TextStyle = androidx.compose.material3.LocalTextStyle.current,
) = androidx.compose.material3.Text(
    text, modifier, color, fontSize, fontStyle, fontWeight, fontFamily, letterSpacing, textDecoration,
    textAlign, lineHeight, overflow, softWrap, maxLines, minLines, onTextLayout, style,
)

@Composable
fun Icon(imageVector: ImageVector, contentDescription: String?, modifier: Modifier = Modifier, tint: Color = LocalContentColor.current) =
    androidx.compose.material3.Icon(imageVector, contentDescription, modifier, tint)

@Composable
fun Icon(painter: Painter, contentDescription: String?, modifier: Modifier = Modifier, tint: Color = LocalContentColor.current) =
    androidx.compose.material3.Icon(painter, contentDescription, modifier, tint)

class Border(val border: BorderStroke, val inset: androidx.compose.ui.unit.Dp = androidx.compose.ui.unit.Dp(0f), val shape: Shape = RoundedCornerShape(0)) {
    companion object { val None = Border(BorderStroke(androidx.compose.ui.unit.Dp(0f), Color.Transparent)) }
}

class ClickableSurfaceShape(val shape: Shape, val focusedShape: Shape)
class ClickableSurfaceColors(val containerColor: Color, val contentColor: Color, val focusedContainerColor: Color, val focusedContentColor: Color)
class ClickableSurfaceScale(val scale: Float, val focusedScale: Float)
class ClickableSurfaceBorder(val border: Border, val focusedBorder: Border)

object ClickableSurfaceDefaults {
    fun shape(shape: Shape = RoundedCornerShape(8), focusedShape: Shape = shape) = ClickableSurfaceShape(shape, focusedShape)
    fun scale(scale: Float = 1f, focusedScale: Float = 1.1f, pressedScale: Float = scale) = ClickableSurfaceScale(scale, focusedScale)
    fun border(border: Border = Border.None, focusedBorder: Border = border, pressedBorder: Border = focusedBorder) = ClickableSurfaceBorder(border, focusedBorder)

    @Composable
    @ReadOnlyComposable
    fun colors(
        containerColor: Color = androidx.compose.material3.MaterialTheme.colorScheme.surface,
        contentColor: Color = androidx.compose.material3.MaterialTheme.colorScheme.onSurface,
        focusedContainerColor: Color = androidx.compose.material3.MaterialTheme.colorScheme.onSurface,
        focusedContentColor: Color = androidx.compose.material3.contentColorFor(focusedContainerColor),
        pressedContainerColor: Color = focusedContainerColor,
        pressedContentColor: Color = focusedContentColor,
    ) = ClickableSurfaceColors(containerColor, contentColor, focusedContainerColor, focusedContentColor)
}

@OptIn(androidx.compose.ui.ExperimentalComposeUiApi::class)
private fun Modifier.rightClick(action: () -> Unit) = onPointerEvent(PointerEventType.Press) { e ->
    if (e.buttons.isSecondaryPressed) { e.changes.forEach { it.consume() }; action() }
}

@OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)
@Composable
fun Surface(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    onLongClick: (() -> Unit)? = null,
    enabled: Boolean = true,
    shape: ClickableSurfaceShape = ClickableSurfaceDefaults.shape(),
    colors: ClickableSurfaceColors = ClickableSurfaceDefaults.colors(),
    scale: ClickableSurfaceScale = ClickableSurfaceDefaults.scale(),
    border: ClickableSurfaceBorder = ClickableSurfaceDefaults.border(),
    interactionSource: MutableInteractionSource? = null,
    content: @Composable BoxScope.() -> Unit,
) {
    val source = interactionSource ?: remember { MutableInteractionSource() }
    val focused by source.collectIsFocusedAsState()
    val hovered by source.collectIsHoveredAsState()
    val on = focused || hovered
    val s = if (on) shape.focusedShape else shape.shape
    val b = if (on) border.focusedBorder else border.border
    // No scale animation: a static step is cheaper on slow machines and reads the same.
    val k = if (on) scale.focusedScale else scale.scale
    Box(
        modifier
            .graphicsLayer { scaleX = k; scaleY = k }
            .clip(s)
            .background(if (on) colors.focusedContainerColor else colors.containerColor, s)
            .then(if (b.border.width.value > 0f) Modifier.border(b.border, b.shape) else Modifier)
            .combinedClickable(interactionSource = source, indication = null, enabled = enabled, onLongClick = onLongClick, onClick = onClick)
            // Right-click opens the same options as a long press.
            .then(if (onLongClick != null && enabled) Modifier.rightClick(onLongClick) else Modifier),
    ) {
        CompositionLocalProvider(LocalContentColor provides if (on) colors.focusedContentColor else colors.contentColor) { content() }
    }
}
