package com.zemu.tv.ui.profiles

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.tv.material3.Border
import androidx.tv.material3.ClickableSurfaceDefaults
import androidx.tv.material3.Surface
import androidx.tv.material3.Text
import com.zemu.tv.R
import com.zemu.tv.data.Profile
import com.zemu.tv.ui.components.touchClick
import com.zemu.tv.ui.theme.Palette
import kotlinx.coroutines.delay

/** "Who's watching?" — shown at launch when more than one profile exists. */
@Composable
fun ProfilePicker(profiles: List<Profile>, currentId: String, onPick: (Profile) -> Unit) {
    val requesters = remember(profiles) { profiles.associate { it.id to FocusRequester() } }
    LaunchedEffect(profiles) {
        delay(100)
        runCatching { (requesters[currentId] ?: requesters.values.first()).requestFocus() }
    }
    Box(Modifier.fillMaxSize().background(Palette.Background), contentAlignment = Alignment.Center) {
        androidx.compose.foundation.Image(
            painterResource(R.drawable.logo_wordmark),
            contentDescription = "Zemu",
            modifier = Modifier.align(Alignment.TopStart).padding(start = 48.dp, top = 32.dp).height(30.dp).width(200.dp),
        )
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text("Who's watching?", fontSize = 40.sp, fontWeight = FontWeight.Black)
            Spacer(Modifier.height(40.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(36.dp)) {
                profiles.forEach { p ->
                    Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.width(150.dp)) {
                        val shape = RoundedCornerShape(22.dp)
                        Surface(
                            onClick = { onPick(p) },
                            modifier = Modifier.touchClick({ onPick(p) }).size(140.dp).focusRequester(requesters.getValue(p.id)),
                            shape = ClickableSurfaceDefaults.shape(shape = shape),
                            scale = ClickableSurfaceDefaults.scale(focusedScale = 1.1f),
                            border = ClickableSurfaceDefaults.border(focusedBorder = Border(BorderStroke(4.dp, Color.White), shape = shape)),
                            colors = ClickableSurfaceDefaults.colors(containerColor = Color.Transparent, focusedContainerColor = Color.Transparent),
                        ) {
                            Avatar(p.avatar, 140.dp, corner = 22.dp)
                        }
                        Spacer(Modifier.height(14.dp))
                        Text(p.name, fontSize = 18.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, color = Palette.TextSecondary)
                    }
                }
            }
            Spacer(Modifier.height(36.dp))
            Text("Manage profiles in Settings", color = Palette.TextMuted, fontSize = 14.sp)
        }
    }
}
