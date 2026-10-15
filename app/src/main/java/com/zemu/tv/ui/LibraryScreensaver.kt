package com.zemu.tv.ui

import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.tween
import androidx.compose.animation.core.Animatable
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.tv.material3.Icon
import androidx.tv.material3.Text
import coil.compose.AsyncImage
import coil.imageLoader
import coil.request.ImageRequest
import com.zemu.tv.data.ScreensaverSlide
import com.zemu.tv.ui.components.AppIcons
import com.zemu.tv.ui.theme.Palette
import kotlinx.coroutines.delay

/**
 * Full-screen slideshow of suggested titles: a backdrop with the title's logo and a "Watch now"
 * button (OK on the remote), crossfading to the next title every [imageSeconds] over
 * [fadeMillis]. Shown over the app (which stays mounted); the caller handles input.
 */
@Composable
fun LibraryScreensaver(
    slides: List<ScreensaverSlide>,
    imageSeconds: Int,
    fadeMillis: Int,
    showTitle: Boolean,
    onCurrent: (ScreensaverSlide) -> Unit,
) {
    val context = LocalContext.current
    var index by remember(slides) { mutableIntStateOf(0) }
    LaunchedEffect(slides, index) { slides.getOrNull(index)?.let(onCurrent) }
    LaunchedEffect(slides) {
        while (slides.size > 1) {
            // Fetch the next slide's images ahead so the crossfade never waits on the network.
            val next = slides[(index + 1) % slides.size]
            listOfNotNull(next.image, next.logo).forEach { context.imageLoader.enqueue(ImageRequest.Builder(context).data(it).build()) }
            delay(imageSeconds * 1000L)
            index = (index + 1) % slides.size
        }
    }
    Box(Modifier.fillMaxSize().background(Color.Black)) {
        Crossfade(targetState = slides.getOrNull(index), animationSpec = tween(fadeMillis), label = "screensaver") { slide ->
            if (slide != null) Slide(slide, imageSeconds, showTitle)
        }
    }
}

@Composable
private fun Slide(slide: ScreensaverSlide, imageSeconds: Int, showTitle: Boolean) {
    val context = LocalContext.current
    // Slow push-in while the slide shows.
    val zoom = remember(slide) { Animatable(1f) }
    LaunchedEffect(slide) { zoom.animateTo(1.08f, tween(imageSeconds * 1000 + 2000, easing = LinearEasing)) }
    Box(Modifier.fillMaxSize()) {
        AsyncImage(
            model = ImageRequest.Builder(context).data(slide.image).build(),
            contentDescription = null,
            contentScale = ContentScale.Crop,
            modifier = Modifier.fillMaxSize().graphicsLayer { scaleX = zoom.value; scaleY = zoom.value },
        )
        if (!showTitle) return@Box
        Box(
            Modifier.fillMaxSize().background(
                Brush.verticalGradient(0.45f to Color.Transparent, 1f to Color.Black.copy(alpha = 0.85f)),
            ),
        )
        Column(Modifier.align(Alignment.BottomStart).padding(start = 64.dp, bottom = 56.dp).fillMaxWidth(0.5f)) {
            val m = slide.meta
            if (slide.logo != null) {
                AsyncImage(
                    model = ImageRequest.Builder(context).data(slide.logo).build(),
                    contentDescription = m.name,
                    contentScale = ContentScale.Fit,
                    alignment = Alignment.BottomStart,
                    modifier = Modifier.heightIn(max = 130.dp).widthIn(max = 460.dp),
                )
            } else {
                Text(m.name.orEmpty(), color = Color.White, fontSize = 44.sp, fontWeight = FontWeight.Black, maxLines = 2)
            }
            val info = listOfNotNull(m.releaseInfo, m.genres.take(3).joinToString(" · ").ifEmpty { null }, m.imdbRating?.let { "IMDb $it" })
            if (info.isNotEmpty()) Text(info.joinToString("   "), color = Color.White.copy(alpha = 0.8f), fontSize = 16.sp, modifier = Modifier.padding(top = 12.dp))
            Row(
                Modifier
                    .padding(top = 18.dp)
                    .background(Palette.Accent, RoundedCornerShape(8.dp))
                    .padding(horizontal = 18.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Icon(AppIcons.Play, contentDescription = null, tint = Palette.OnAccent, modifier = Modifier.size(20.dp))
                Text("Watch now  ·  OK", color = Palette.OnAccent, fontSize = 16.sp, fontWeight = FontWeight.Bold)
            }
        }
    }
}
