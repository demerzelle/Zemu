package com.zemu.tv.ui.components

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.platform.LocalContext
import com.zemu.tv.container
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.tv.material3.Border
import androidx.tv.material3.ClickableSurfaceDefaults
import androidx.tv.material3.MaterialTheme
import androidx.tv.material3.Surface
import androidx.tv.material3.Text
import com.zemu.tv.ui.theme.Palette

data class CastMember(val key: String, val name: String, val role: String?, val photo: String?)

/**
 * Round actor photos with name and character; OK opens the person. Shows the first [initial]
 * people with a "View more" tile that reveals the rest. Missing photos are looked up lazily.
 */
@Composable
fun CastRow(
    title: String,
    people: List<CastMember>,
    onClick: (CastMember) -> Unit,
    modifier: Modifier = Modifier,
    firstFocus: FocusRequester? = null,
    initial: Int = 6,
) {
    val c = LocalContext.current.container
    var expanded by remember(people) { mutableStateOf(false) }
    val shown = if (expanded || people.size <= initial + 1) people else people.take(initial)
    Column(modifier) {
        Text(
            if (people.size > 1) "$title  ·  ${people.size}" else title,
            style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold, modifier = Modifier.padding(start = 48.dp),
        )
        LazyRow(
            contentPadding = PaddingValues(horizontal = 48.dp, vertical = 16.dp),
            horizontalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            itemsIndexed(shown, key = { _, p -> p.key }) { i, p ->
                val photo by produceState(p.photo, p.name) {
                    if (value == null) value = runCatching { c.freeCast.photoFor(p.name) }.getOrNull()
                }
                CastTile(
                    label = p.name,
                    sub = p.role,
                    photo = photo,
                    modifier = if (i == 0 && firstFocus != null) Modifier.focusRequester(firstFocus) else Modifier,
                ) { onClick(p) }
            }
            if (shown.size < people.size) {
                item(key = "more") {
                    CastTile(label = "View more", sub = "${people.size - shown.size} more", photo = null, initials = "+${people.size - shown.size}") {
                        expanded = true
                    }
                }
            }
        }
    }
}

@Composable
private fun CastTile(label: String, sub: String?, photo: String?, modifier: Modifier = Modifier, initials: String? = null, onClick: () -> Unit) {
    Column(Modifier.width(112.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Surface(
            onClick = onClick,
            modifier = modifier.touchClick(onClick).size(104.dp),
            shape = ClickableSurfaceDefaults.shape(shape = CircleShape),
            scale = ClickableSurfaceDefaults.scale(focusedScale = 1.1f),
            border = ClickableSurfaceDefaults.border(focusedBorder = Border(BorderStroke(3.dp, Palette.FocusBorder), shape = CircleShape)),
            colors = ClickableSurfaceDefaults.colors(containerColor = Palette.SurfaceHigh, focusedContainerColor = Palette.SurfaceHigh),
        ) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Text(
                    initials ?: label.split(' ').mapNotNull { it.firstOrNull()?.uppercase() }.take(2).joinToString(""),
                    fontSize = 30.sp, fontWeight = FontWeight.Bold, color = Palette.TextMuted,
                )
                RemoteImage(photo, Modifier.fillMaxSize())
            }
        }
        Spacer(Modifier.height(8.dp))
        Text(label, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, maxLines = 2, textAlign = TextAlign.Center, overflow = TextOverflow.Ellipsis)
        sub?.let { Text(it, fontSize = 12.sp, color = Palette.TextMuted, maxLines = 1, textAlign = TextAlign.Center, overflow = TextOverflow.Ellipsis) }
    }
}
