package com.zemu.tv.ui

import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import coil.compose.AsyncImage
import coil.imageLoader
import coil.request.ImageRequest
import kotlinx.coroutines.delay

/**
 * Full-screen slideshow of library backdrops, shuffled once per start, changing every
 * [imageSeconds] with an opacity crossfade only. Shown over the app (which stays mounted); the
 * caller removes it on any input.
 */
@Composable
fun LibraryScreensaver(images: List<String>, imageSeconds: Int) {
    val context = LocalContext.current
    val order = remember(images) { images.shuffled() }
    var index by remember(order) { mutableIntStateOf(0) }
    LaunchedEffect(order) {
        while (order.size > 1) {
            // Fetch the next image ahead so the crossfade never waits on the network.
            context.imageLoader.enqueue(ImageRequest.Builder(context).data(order[(index + 1) % order.size]).build())
            delay(imageSeconds * 1000L)
            index = (index + 1) % order.size
        }
    }
    Box(Modifier.fillMaxSize().background(Color.Black)) {
        Crossfade(targetState = order.getOrNull(index), animationSpec = tween(1500), label = "screensaver") { url ->
            AsyncImage(
                model = ImageRequest.Builder(context).data(url).build(),
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize(),
            )
        }
    }
}
