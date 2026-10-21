package com.zemu.tv.ui.components

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.unit.dp
import com.airbnb.lottie.compose.LottieAnimation
import com.airbnb.lottie.compose.LottieCompositionSpec
import com.airbnb.lottie.compose.LottieConstants
import com.airbnb.lottie.compose.rememberLottieComposition
import com.zemu.tv.R

/**
 * The spinning Zemu mark (branding/loader), in the bottom-right corner of whatever box it fills.
 * Sized from the screen, so it reads the same on a 720p box, a 4K TV and a phone.
 */
@Composable
fun ZemuLoader(modifier: Modifier = Modifier) {
    val conf = LocalConfiguration.current
    val short = minOf(conf.screenWidthDp, conf.screenHeightDp)
    val composition = rememberLottieComposition(LottieCompositionSpec.RawRes(R.raw.zemu_loader)).value
    Box(modifier.fillMaxSize()) {
        LottieAnimation(
            composition,
            iterations = LottieConstants.IterateForever,
            // The animation canvas leaves room for the orbiting ring; the Z itself is about half of it.
            modifier = Modifier.align(Alignment.BottomEnd).padding((short * 0.04f).dp).size((short * 0.17f).dp),
        )
    }
}
