package com.zemu.tv.ui.components

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import com.zemu.tv.R

/** The Zemu mark, gently pulsing in the bottom-right corner (a cheap stand-in for the Lottie loader). */
@Composable
fun ZemuLoader(modifier: Modifier = Modifier) {
    val conf = LocalConfiguration.current
    val short = minOf(conf.screenWidthDp, conf.screenHeightDp)
    val alpha = rememberInfiniteTransition(label = "loader")
        .animateFloat(0.35f, 1f, infiniteRepeatable(tween(700, easing = LinearEasing), RepeatMode.Reverse), label = "a")
    Box(modifier.fillMaxSize()) {
        Image(
            painterResource(R.drawable.logo_mark), contentDescription = "Loading",
            modifier = Modifier.align(Alignment.BottomEnd).padding((short * 0.05f).dp).size((short * 0.08f).dp)
                .graphicsLayer { this.alpha = alpha.value },
        )
    }
}
